from __future__ import annotations

import asyncio
import os
from typing import (
    Any,
    Awaitable,
    Callable,
    Dict,
    List,
    Mapping,
    Optional,
    Sequence,
    cast,
)

from marshmallow import Schema, ValidationError
from starlette import status
from starlette.applications import Starlette
from starlette.middleware.base import BaseHTTPMiddleware, RequestResponseEndpoint
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from ..common.starlette_helpers import (
    RequestValidationError,
    read_json_body,
    load_with_schema,
)
from ..config import (
    ApiRoute,
    JobCommandReason,
    JobCommandStatus,
    JobStatus,
    HEALTH_CHECK_PATH,
    get_server_environment,
)
from ..core import OptionsConfig, build_options_config
from ..core.downloader import resolve_download_options
from ..download import DownloadManager
from ..log_config import verbose_log
from ..download.models import DownloadJobOptionsPayload
from ..security import is_valid_token, token_from_headers
from ..models.api.errors import ErrorCode
from ..models.api.http import (
    CreateJobEndpointResponse,
    DryRunJobEndPointResponse,
    DryRunOptionsPayload,
    HealthCheckResponse,
    ListJobsEndPointResponse,
)
from ..models.api.query import (
    JobLogsQueryParams,
    JobLogsQuerySchema,
    JobOptionsQueryParams,
    JobOptionsQuerySchema,
    OffsetLimitQueryParams,
    PlaylistItemsDeltaQueryParams,
    PlaylistItemsDeltaQuerySchema,
    PlaylistItemsQuerySchema,
    PlaylistSnapshotQueryParams,
    PlaylistSnapshotQuerySchema,
)
from ..models.api.requests import (
    CancelJobsRequestSchema,
    CreateJobRequestSchema,
    DryRunJobRequestSchema,
    PlaylistEntryActionRequestSchema,
    PlaylistEntryDeleteRequestSchema,
    PlaylistSelectionRequestSchema,
    PreviewRequestSchema,
)
from ..models.download.manager import CreateJobRequest, SerializedJobPayload
from ..models.api.websockets import OverviewSummary
from ..models.shared import JSONValue
from ..utils import now_iso

PLAYLIST_PAGE_MAX_LIMIT = 500
ENABLE_PREVIEW_API = os.environ.get(
    "VIDRA_ENABLE_PREVIEW_API", "0"
).strip().lower() in {
    "1",
    "true",
    "yes",
    "on",
}
SERVER_CONFIG = get_server_environment()

QUERY_ERROR_MAP: dict[tuple[str, str], ErrorCode] = {
    ("offset", "offset_not_integer"): ErrorCode.OFFSET_MUST_BE_INTEGER,
    ("offset", "offset_non_negative"): ErrorCode.OFFSET_MUST_BE_NON_NEGATIVE,
    ("limit", "limit_not_integer"): ErrorCode.LIMIT_MUST_BE_INTEGER,
    ("limit", "limit_greater_than_zero"): ErrorCode.LIMIT_GREATER_THAN_ZERO,
}

DELTA_ERROR_MAP: dict[tuple[str, str], ErrorCode] = {
    ("since", "since_not_integer"): ErrorCode.SINCE_MUST_BE_INTEGER,
}

JOB_QUERY_ERROR_MAP: dict[tuple[str, str], ErrorCode] = {
    **QUERY_ERROR_MAP,
    **DELTA_ERROR_MAP,
}


def register_http_routes(app: Starlette, manager: DownloadManager) -> None:
    """Attach REST endpoints and middleware to the Starlette application."""

    async def _parse_payload(request: Request, schema_cls: type[Schema]) -> Any:
        raw_body = await read_json_body(request)
        if not isinstance(raw_body, Mapping):
            raise RequestValidationError({"json": "JSON object required"})
        return load_with_schema(schema_cls(), raw_body)

    def _query_error_response(
        exc: ValidationError,
        *,
        mapping: Mapping[tuple[str, str], ErrorCode],
    ) -> JSONResponse:
        messages = exc.normalized_messages()
        if isinstance(messages, Mapping):
            for field, errors in messages.items():
                if not isinstance(errors, Sequence):
                    continue
                for reason in errors:
                    key = (str(field), str(reason))
                    error_code = mapping.get(key)
                    if error_code:
                        return error_response(error_code, status_code=400)
        return error_response(
            ErrorCode.INVALID_JSON_PAYLOAD,
            status_code=400,
            detail=cast(JSONValue, messages),
        )

    def json_response(payload: Any, status: int = 200) -> JSONResponse:
        verbose_log("http_response", {"status": status, "payload": payload})
        return JSONResponse(content=payload, status_code=status)

    def error_response(
        code: ErrorCode | str,
        *,
        status_code: int,
        detail: JSONValue | None = None,
        extra: Mapping[str, JSONValue] | None = None,
    ) -> JSONResponse:
        payload: Dict[str, JSONValue] = {
            "error": code.value if isinstance(code, ErrorCode) else str(code)
        }
        if detail is not None:
            payload["detail"] = detail
        if extra:
            for key, value in extra.items():
                payload[str(key)] = value
        return json_response(payload, status=status_code)

    async def _handle_request_validation(
        _: Request, exc: RequestValidationError
    ) -> JSONResponse:
        detail: JSONValue | None = None
        if exc.errors:
            detail = cast(JSONValue, dict(exc.errors))
        elif exc.args:
            detail = cast(JSONValue, exc.args[0])
        return error_response(
            ErrorCode.INVALID_JSON_PAYLOAD,
            status_code=400,
            detail=detail,
        )

    app.add_exception_handler(RequestValidationError, _handle_request_validation)  # type: ignore[arg-type]

    def _route(
        path: str, *, methods: list[str]
    ) -> Callable[
        [Callable[..., Awaitable[JSONResponse]]], Callable[..., Awaitable[JSONResponse]]
    ]:
        def decorator(
            func: Callable[..., Awaitable[JSONResponse]],
        ) -> Callable[..., Awaitable[JSONResponse]]:
            app.router.add_route(path, func, methods=methods)
            return func

        return decorator

    def get(
        path: str,
    ) -> Callable[
        [Callable[..., Awaitable[JSONResponse]]], Callable[..., Awaitable[JSONResponse]]
    ]:
        return _route(path, methods=["GET"])

    def post(
        path: str,
    ) -> Callable[
        [Callable[..., Awaitable[JSONResponse]]], Callable[..., Awaitable[JSONResponse]]
    ]:
        return _route(path, methods=["POST"])

    def delete(
        path: str,
    ) -> Callable[
        [Callable[..., Awaitable[JSONResponse]]], Callable[..., Awaitable[JSONResponse]]
    ]:
        return _route(path, methods=["DELETE"])

    def job_not_found_response() -> JSONResponse:
        return error_response(ErrorCode.JOB_NOT_FOUND, status_code=404)

    def _options_config_from_payload(
        payload: DownloadJobOptionsPayload,
    ) -> OptionsConfig | None:
        return build_options_config(payload)

    def _clone_json_value(value: Any, *, depth: int = 0) -> JSONValue:
        if depth > 5:
            return None
        if value is None or isinstance(value, (str, int, float, bool)):
            return value
        if isinstance(value, Mapping):
            mapping = cast(Mapping[object, object], value)
            nested: Dict[str, JSONValue] = {}
            for key, item in mapping.items():
                nested_value = _clone_json_value(item, depth=depth + 1)
                if nested_value is not None:
                    nested[str(key)] = nested_value
            return nested
        if isinstance(value, Sequence) and not isinstance(
            value, (str, bytes, bytearray)
        ):
            nested_list: List[JSONValue] = []
            sequence = cast(Sequence[object], value)
            for item in sequence:
                nested_value = _clone_json_value(item, depth=depth + 1)
                if nested_value is not None:
                    nested_list.append(nested_value)
            return nested_list
        return str(value)

    def _json_dict_from_any(payload: Mapping[str, Any]) -> DryRunOptionsPayload:
        result: DryRunOptionsPayload = {}
        for key, value in payload.items():
            json_value = _clone_json_value(value)
            if json_value is not None:
                result[str(key)] = json_value
        return result

    def _parse_int_param(value: str | None) -> Optional[int]:
        if value is None:
            return None
        try:
            return int(value.strip())
        except (ValueError, AttributeError):
            return None

    def _parse_entry_index_fragment(fragment: str | None) -> Optional[int]:
        if fragment is None:
            return None
        token = fragment.strip()
        if not token:
            return None
        if token.lower().startswith("entry-"):
            suffix = token[6:]
            if suffix.isdigit():
                try:
                    candidate = int(suffix)
                except ValueError:
                    return None
                return candidate if candidate > 0 else None
        if token.isdigit():
            try:
                candidate = int(token)
            except ValueError:
                return None
            return candidate if candidate > 0 else None
        return None

    def _resolve_entry_selector(
        job_id: str,
        params: Mapping[str, str],
    ) -> tuple[str, Optional[Dict[str, Any]], Optional[str]]:
        raw_entry_index = params.get("entry_index")
        entry_index = _parse_int_param(raw_entry_index)
        if raw_entry_index and entry_index is None:
            return (job_id, None, "entry_index")
        entry_id_param = params.get("entry_id")
        playlist_entry_id = entry_id_param.strip() if entry_id_param else None
        normalized_job_id = job_id
        fragment: str | None = None
        if "::" in job_id:
            normalized_job_id, _, fragment = job_id.partition("::")
        fragment = fragment.strip() if fragment else None
        if fragment:
            if not playlist_entry_id:
                playlist_entry_id = fragment
            if entry_index is None:
                entry_index = _parse_entry_index_fragment(fragment)
                if entry_index is not None and playlist_entry_id == fragment:
                    playlist_entry_id = None
        if not playlist_entry_id and entry_index is None:
            return (normalized_job_id, None, None)
        selector: Dict[str, Any] = {
            "requested_job_id": job_id,
            "playlist_entry_id": playlist_entry_id,
            "playlist_index": entry_index,
        }
        return (normalized_job_id, selector, None)

    def _attach_entry_context(
        snapshot: Dict[str, JSONValue], selector: Mapping[str, Any]
    ) -> None:
        payload: Dict[str, JSONValue] = {}
        entry_id_value = selector.get("playlist_entry_id")
        if isinstance(entry_id_value, str) and entry_id_value:
            payload["playlist_entry_id"] = entry_id_value
        index_value = selector.get("playlist_index")
        if isinstance(index_value, int) and index_value > 0:
            payload["playlist_index"] = index_value
        requested_job_id = selector.get("requested_job_id")
        if isinstance(requested_job_id, str) and requested_job_id:
            payload["requested_job_id"] = requested_job_id
        if payload:
            snapshot["entry"] = cast(JSONValue, payload)

    def _filter_logs_for_entry(
        snapshot: Dict[str, JSONValue], selector: Mapping[str, Any]
    ) -> None:
        logs_value = snapshot.get("logs")
        if not isinstance(logs_value, list):
            return
        entry_id_value = selector.get("playlist_entry_id")
        entry_index_value = selector.get("playlist_index")
        has_filter = (isinstance(entry_id_value, str) and entry_id_value) or (
            isinstance(entry_index_value, int) and entry_index_value > 0
        )
        if not has_filter:
            return
        filtered: List[JSONValue] = []
        for raw_entry in logs_value:
            if not isinstance(raw_entry, Mapping):
                continue
            matches = False
            if isinstance(entry_id_value, str) and entry_id_value:
                candidate = raw_entry.get("playlist_entry_id")
                if isinstance(candidate, str) and candidate == entry_id_value:
                    matches = True
            if (not matches) and isinstance(entry_index_value, int):
                candidate_index = raw_entry.get("playlist_index")
                if isinstance(candidate_index, (int, float)):
                    if int(candidate_index) == entry_index_value:
                        matches = True
            if matches:
                filtered.append(cast(JSONValue, dict(raw_entry)))
        snapshot["logs"] = filtered
        snapshot["count"] = len(filtered)

    def _overview_summary() -> OverviewSummary:
        snapshot = manager.overview_snapshot()
        summary_value = snapshot.get("summary")
        total = 0
        active = 0
        queued = 0
        status_counts: dict[str, int] = {}
        if isinstance(summary_value, Mapping):
            total_value = summary_value.get("total")
            if isinstance(total_value, (int, float)):
                total = int(total_value)
            active_value = summary_value.get("active")
            if isinstance(active_value, (int, float)):
                active = int(active_value)
            queued_value = summary_value.get(JobStatus.QUEUED.value)
            if isinstance(queued_value, (int, float)):
                queued = int(queued_value)
            raw_counts = summary_value.get("status_counts")
            if isinstance(raw_counts, Mapping):
                for key, value in raw_counts.items():
                    if isinstance(value, (int, float)):
                        status_counts[str(key)] = int(value)
        return {
            "total": total,
            "active": active,
            JobStatus.QUEUED.value: queued,
            "status_counts": status_counts,
        }

    async def enforce_token(
        request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        normalized_path = request.url.path.rstrip("/") or "/"
        health_path = HEALTH_CHECK_PATH.rstrip("/") or "/"
        if normalized_path == health_path or request.method.upper() == "OPTIONS":
            return await call_next(request)
        token = token_from_headers(request.headers)
        if not is_valid_token(token):
            return error_response(
                ErrorCode.TOKEN_MISSING_OR_INVALID,
                status_code=status.HTTP_401_UNAUTHORIZED,
            )
        return await call_next(request)

    app.add_middleware(BaseHTTPMiddleware, dispatch=enforce_token)

    async def log_request(
        request: Request, call_next: RequestResponseEndpoint
    ) -> Response:
        body: Any
        try:
            body = await request.json()
        except Exception:  # noqa: BLE001 - best effort logging
            body = None
        verbose_log(
            "http_request",
            {
                "method": request.method,
                "path": request.url.path,
                "query": dict(request.query_params.multi_items()),
                "json": body,
                "headers": dict(request.headers),
            },
        )
        return await call_next(request)

    app.add_middleware(BaseHTTPMiddleware, dispatch=log_request)

    @get(HEALTH_CHECK_PATH)
    async def health_check(request: Request) -> JSONResponse:  # noqa: ARG001 - Starlette route signature
        payload: HealthCheckResponse = {
            "service": SERVER_CONFIG.name,
            "time": now_iso(),
            "overview": _overview_summary(),
            "description": SERVER_CONFIG.description,
            "metadata": cast(Dict[str, JSONValue], dict(SERVER_CONFIG.metadata)),
            "base_url": SERVER_CONFIG.base_url,
            "api_url": SERVER_CONFIG.api_url,
            "overview_socket_url": SERVER_CONFIG.overview_socket_url,
            "job_socket_base_url": SERVER_CONFIG.job_socket_base_url,
            "timeout_seconds": SERVER_CONFIG.timeout_seconds,
        }
        return json_response(payload)

    @post(ApiRoute.JOBS.value)
    async def create_job_endpoint(request: Request) -> JSONResponse:
        """Receive download requests from the client and create a job."""

        payload = await _parse_payload(request, CreateJobRequestSchema)

        urls = payload.normalized_urls()
        if not urls:
            return error_response(ErrorCode.URLS_REQUIRED, status_code=400)

        job_request = CreateJobRequest(
            urls=urls,
            options=payload.options_payload(),
            metadata=payload.metadata_payload(),
            creator=payload.effective_creator(),
        )

        job = manager.create_job(job_request)
        response: CreateJobEndpointResponse = {
            "job_id": job.job_id,
            "status": job.status,
            "created_at": job.created_at.isoformat() + "Z",
        }
        progress = job.progress
        if progress:
            stage_value = progress.get("stage")
            if isinstance(stage_value, str):
                response["stage"] = stage_value
            stage_name = progress.get("stage_name") or progress.get("stage")
            if isinstance(stage_name, str):
                response["stage_name"] = stage_name
            stage_status = progress.get("stage_status")
            if isinstance(stage_status, str):
                response["stage_status"] = stage_status
            stage_percent = progress.get("stage_percent")
            if isinstance(stage_percent, (int, float)):
                response["stage_percent"] = float(stage_percent)
            percent_value = progress.get("percent")
            if isinstance(percent_value, (int, float)):
                response["percent"] = float(percent_value)
            message_value = progress.get("message")
            if isinstance(message_value, str):
                response["message"] = message_value
        return json_response(response, status=201)

    @get(ApiRoute.JOBS.value)
    async def list_jobs_endpoint(request: Request) -> JSONResponse:
        status_filter = request.query_params.get("status")
        owner = request.query_params.get("owner")
        jobs = manager.list_jobs(status=status_filter, owner=owner)
        job_payloads = [manager.serialize_job(job) for job in jobs]
        response: ListJobsEndPointResponse = {
            "jobs": cast(List[SerializedJobPayload], job_payloads),
            "summary": _overview_summary(),
        }
        return json_response(response)

    @get(ApiRoute.JOB_DETAIL.value)
    async def get_job_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        job = manager.get_job(job_id)
        if not job:
            return job_not_found_response()
        return json_response(manager.serialize_job(job, detail=True))

    @post(ApiRoute.JOB_CANCEL.value)
    async def cancel_job_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        payload = manager.cancel_job(job_id)
        status_value = payload["status"]
        if status_value == JobCommandStatus.NOT_FOUND.value:
            return job_not_found_response()
        return json_response(payload)

    @post(ApiRoute.JOB_CANCEL_BULK.value)
    async def cancel_jobs_endpoint(request: Request) -> JSONResponse:
        payload = await _parse_payload(request, CancelJobsRequestSchema)
        scope_token = payload.scope.strip().lower() if payload.scope else None
        owner = payload.normalized_owner()
        if scope_token == "all":
            results = manager.cancel_all(owner=owner)
        elif scope_token:
            return error_response(
                ErrorCode.INVALID_JSON_PAYLOAD,
                status_code=400,
                detail=f"unsupported scope: {scope_token}",
            )
        else:
            try:
                job_ids = payload.normalized_job_ids()
            except ValueError as exc:
                return error_response(
                    ErrorCode.INVALID_JSON_PAYLOAD,
                    status_code=400,
                    detail=str(exc),
                )
            results = manager.cancel_jobs(job_ids)
        return json_response({"results": results})

    @post(ApiRoute.JOB_PAUSE.value)
    async def pause_job_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        payload = manager.pause_job(job_id)
        status_value = payload["status"]
        if status_value == JobCommandStatus.NOT_FOUND.value:
            return job_not_found_response()
        if status_value in {
            JobStatus.COMPLETED.value,
            JobStatus.FAILED.value,
            JobStatus.CANCELLED.value,
        }:
            return error_response(
                ErrorCode.JOB_STATUS_CONFLICT,
                status_code=409,
                detail=status_value,
            )
        return json_response(payload)

    @post(ApiRoute.JOB_RESUME.value)
    async def resume_job_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        payload = manager.resume_job(job_id)
        status_value = payload["status"]
        if status_value == JobCommandStatus.NOT_FOUND.value:
            return job_not_found_response()
        if status_value != JobStatus.RUNNING.value:
            return error_response(
                ErrorCode.JOB_STATUS_CONFLICT,
                status_code=409,
                detail=status_value,
            )
        return json_response(payload)

    @post(ApiRoute.JOB_RETRY.value)
    async def retry_job_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        payload = manager.retry_job(job_id)
        status_value = payload["status"]
        if status_value == JobCommandStatus.NOT_FOUND.value:
            return job_not_found_response()
        if status_value not in {JobStatus.QUEUED.value, JobStatus.RUNNING.value}:
            return error_response(
                ErrorCode.JOB_STATUS_CONFLICT,
                status_code=409,
                detail=status_value,
            )
        return json_response(payload)

    @delete(ApiRoute.JOB_DELETE.value)
    async def delete_job_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        payload = manager.delete_job(job_id)
        status_value = payload["status"]
        if status_value == JobCommandStatus.NOT_FOUND.value:
            return job_not_found_response()
        if status_value == JobCommandStatus.JOB_ACTIVE.value:
            return error_response(
                ErrorCode.JOB_DELETE_CONFLICT_ACTIVE,
                status_code=409,
            )
        return json_response(payload)

    @get(ApiRoute.JOB_OPTIONS.value)
    async def get_job_options_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        normalized_job_id, entry_selector, selector_error = _resolve_entry_selector(
            job_id,
            request.query_params,
        )
        if selector_error == "entry_index":
            return error_response(
                ErrorCode.ENTRY_INDEX_INVALID,
                status_code=400,
            )
        if not manager.get_job(normalized_job_id):
            return job_not_found_response()
        schema = JobOptionsQuerySchema()
        try:
            loaded_query = schema.load(dict(request.query_params))
            query_params = cast(JobOptionsQueryParams, loaded_query)
        except ValidationError as exc:
            return _query_error_response(exc, mapping=DELTA_ERROR_MAP)
        snapshot = manager.build_job_options_snapshot(
            normalized_job_id,
            since_version=query_params.since_version,
            include_options=query_params.include_options,
        )
        if snapshot is None:
            return job_not_found_response()
        if entry_selector:
            _attach_entry_context(snapshot, entry_selector)
        return json_response(snapshot)

    @get(ApiRoute.JOB_LOGS.value)
    async def get_job_logs_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        schema = JobLogsQuerySchema()
        try:
            loaded_query = schema.load(dict(request.query_params))
            logs_query = cast(JobLogsQueryParams, loaded_query)
        except ValidationError as exc:
            return _query_error_response(exc, mapping=JOB_QUERY_ERROR_MAP)
        normalized_job_id, entry_selector, selector_error = _resolve_entry_selector(
            job_id,
            request.query_params,
        )
        if selector_error == "entry_index":
            return error_response(
                ErrorCode.ENTRY_INDEX_INVALID,
                status_code=400,
            )
        if not manager.get_job(normalized_job_id):
            return job_not_found_response()
        snapshot = manager.build_job_logs_snapshot(
            normalized_job_id,
            since_version=logs_query.since_version,
            include_logs=logs_query.include_logs,
            limit=logs_query.limit,
        )
        if snapshot is None:
            return job_not_found_response()
        if entry_selector:
            _attach_entry_context(snapshot, entry_selector)
            _filter_logs_for_entry(snapshot, entry_selector)
        return json_response(snapshot)

    @get(ApiRoute.JOB_PLAYLIST.value)
    async def get_job_playlist_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        job = manager.get_job(job_id)
        if not job:
            return job_not_found_response()
        schema = PlaylistSnapshotQuerySchema(max_limit=PLAYLIST_PAGE_MAX_LIMIT)
        try:
            loaded_query = schema.load(dict(request.query_params))
            query_params = cast(PlaylistSnapshotQueryParams, loaded_query)
        except ValidationError as exc:
            return _query_error_response(exc, mapping=QUERY_ERROR_MAP)
        include_entries = query_params.include_entries
        offset_value = query_params.offset
        limit_value = query_params.limit
        if include_entries:
            snapshot = manager.build_playlist_snapshot(
                job_id,
                include_entries=True,
                include_entry_progress=True,
                entry_offset=offset_value,
                max_entries=limit_value,
            )
        else:
            snapshot = manager.build_playlist_snapshot(job_id)
        if not snapshot or not snapshot.get("playlist"):
            return error_response(
                ErrorCode.PLAYLIST_ENTRIES_UNAVAILABLE,
                status_code=404,
            )
        return json_response(snapshot)

    @get(ApiRoute.JOB_PLAYLIST_ITEMS.value)
    async def get_job_playlist_items_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        job = manager.get_job(job_id)
        if not job:
            return job_not_found_response()
        schema = PlaylistItemsQuerySchema(max_limit=PLAYLIST_PAGE_MAX_LIMIT)
        try:
            loaded_query = schema.load(dict(request.query_params))
            query_params = cast(OffsetLimitQueryParams, loaded_query)
        except ValidationError as exc:
            return _query_error_response(exc, mapping=QUERY_ERROR_MAP)
        offset_value = query_params.offset
        limit_value = query_params.limit
        snapshot = manager.build_playlist_entries(
            job_id,
            entry_offset=offset_value,
            max_entries=limit_value,
        )
        if not snapshot or not snapshot.get("playlist"):
            return error_response(
                ErrorCode.PLAYLIST_METADATA_UNAVAILABLE,
                status_code=404,
            )
        return json_response(snapshot)

    @get(ApiRoute.JOB_PLAYLIST_ITEMS_DELTA.value)
    async def get_job_playlist_items_delta_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        job = manager.get_job(job_id)
        if not job:
            return job_not_found_response()
        schema = PlaylistItemsDeltaQuerySchema()
        try:
            loaded_query = schema.load(dict(request.query_params))
            delta_params = cast(PlaylistItemsDeltaQueryParams, loaded_query)
        except ValidationError as exc:
            return _query_error_response(exc, mapping=DELTA_ERROR_MAP)
        payload = manager.build_playlist_entries_delta(
            job_id,
            since_version=delta_params.since_version,
        )
        if not payload or not payload.get("playlist"):
            return error_response(
                ErrorCode.PLAYLIST_METADATA_UNAVAILABLE,
                status_code=404,
            )
        return json_response(payload)

    @post(ApiRoute.JOB_PLAYLIST_SELECTION.value)
    async def set_job_playlist_selection_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        try:
            payload = await _parse_payload(request, PlaylistSelectionRequestSchema)
        except RequestValidationError as exc:
            detail: JSONValue | None = None
            indices_errors = exc.errors.get("indices") if exc.errors else None
            if isinstance(indices_errors, list) and indices_errors:
                detail = cast(JSONValue, indices_errors[0])
            return error_response(
                ErrorCode.INVALID_JSON_PAYLOAD,
                status_code=400,
                detail=detail or cast(JSONValue, "indices must be a list"),
            )
        try:
            indices = payload.normalized_indices()
        except ValueError as exc:
            return error_response(
                ErrorCode.INVALID_JSON_PAYLOAD,
                status_code=400,
                detail=str(exc),
            )

        result = manager.apply_playlist_selection(job_id, indices=indices)
        status_value = result.get("status")
        if status_value == JobCommandStatus.NOT_FOUND.value:
            return job_not_found_response()
        if result.get("reason") == JobCommandReason.JOB_TERMINATED.value:
            return json_response(result, status=409)
        return json_response(result)

    @post(ApiRoute.JOB_PLAYLIST_RETRY.value)
    async def retry_playlist_entries_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        payload = await _parse_payload(request, PlaylistEntryActionRequestSchema)
        try:
            indices = payload.normalized_indices()
        except ValueError as exc:
            return error_response(
                ErrorCode.INVALID_JSON_PAYLOAD,
                status_code=400,
                detail=str(exc),
            )
        entry_ids = payload.normalized_entry_ids()
        result = manager.retry_playlist_entries(
            job_id,
            indices=indices,
            entry_ids=entry_ids,
        )
        status_value = result.get("status")
        if status_value == JobCommandStatus.NOT_FOUND.value:
            return job_not_found_response()
        if status_value not in {JobStatus.QUEUED.value, JobStatus.RUNNING.value}:
            return json_response(result, status=409)
        return json_response(result)

    @post(ApiRoute.JOB_PLAYLIST_DELETE.value)
    async def delete_playlist_entries_endpoint(request: Request) -> JSONResponse:
        job_id = request.path_params.get("job_id", "")
        payload = await _parse_payload(request, PlaylistEntryDeleteRequestSchema)
        try:
            indices = payload.normalized_indices()
        except ValueError as exc:
            return error_response(
                ErrorCode.INVALID_JSON_PAYLOAD,
                status_code=400,
                detail=str(exc),
            )
        entry_ids = payload.normalized_entry_ids()
        result = manager.delete_playlist_entries(
            job_id,
            indices=indices,
            entry_ids=entry_ids,
        )
        status_value = result.get("status")
        if status_value == JobCommandStatus.NOT_FOUND.value:
            return job_not_found_response()
        if status_value == JobCommandStatus.JOB_ACTIVE.value:
            return json_response(result, status=409)
        return json_response(result)

    if ENABLE_PREVIEW_API:

        @post(ApiRoute.JOB_DRY_RUN.value)
        async def dry_run_job_endpoint(request: Request) -> JSONResponse:
            payload = await _parse_payload(request, DryRunJobRequestSchema)
            urls = payload.normalized_urls()
            if not urls:
                return error_response(ErrorCode.URLS_REQUIRED, status_code=400)

            options_config: OptionsConfig | None = None
            options_payload = payload.options_payload()
            if options_payload:
                options_config = _options_config_from_payload(options_payload)

            try:
                resolved = resolve_download_options(
                    urls,
                    options=options_config,
                    download=True,
                )
            except Exception as exc:
                return error_response(
                    ErrorCode.DRY_RUN_FAILED,
                    status_code=400,
                    detail=repr(exc),
                )

            response: DryRunJobEndPointResponse = {
                "cli_args": resolved.cli_args,
                "urls": resolved.urls,
                "options": _json_dict_from_any(resolved.ydl_opts),
            }
            return json_response(response)

        @post(ApiRoute.PREVIEW.value)
        async def preview_endpoint(request: Request) -> JSONResponse:
            payload = await _parse_payload(request, PreviewRequestSchema)
            urls = payload.normalized_urls()
            if not urls:
                return error_response(ErrorCode.URLS_REQUIRED, status_code=400)

            options_payload = payload.options_payload()
            loop = asyncio.get_running_loop()
            try:
                preview = await loop.run_in_executor(
                    None,
                    lambda: manager.preview_metadata(urls, options_payload),
                )
            except Exception as exc:  # noqa: BLE001 - capture unexpected preview errors
                verbose_log(
                    "preview_endpoint_error",
                    {"urls": urls, "error": repr(exc)},
                )
                return error_response(
                    ErrorCode.PREVIEW_FAILED,
                    status_code=500,
                    detail=repr(exc),
                )

            response = {"preview": preview}
            return json_response(response)
    else:
        dry_run_job_endpoint = None  # type: ignore[assignment]
        preview_endpoint = None  # type: ignore[assignment]

    @get(ApiRoute.PROFILES.value)
    async def list_profiles_endpoint(request: Request) -> JSONResponse:  # noqa: ARG001 - unused
        return json_response(
            {
                "profiles": [],
                "message": ErrorCode.PROFILES_NOT_IMPLEMENTED.value,
            }
        )

    # ensure static analyzers don't report it as unused
    _ = set_job_playlist_selection_endpoint
    _ = get_job_playlist_items_endpoint
    _ = get_job_playlist_items_delta_endpoint
    _ = get_job_playlist_endpoint
    _ = get_job_options_endpoint
    _ = delete_job_endpoint
    _ = retry_job_endpoint
    _ = retry_playlist_entries_endpoint
    _ = delete_playlist_entries_endpoint
    _ = resume_job_endpoint
    _ = pause_job_endpoint
    _ = cancel_jobs_endpoint
    _ = cancel_job_endpoint
    _ = get_job_endpoint
    _ = list_jobs_endpoint
    _ = create_job_endpoint
    _ = health_check
    _ = log_request
    _ = dry_run_job_endpoint
    _ = preview_endpoint
    _ = list_profiles_endpoint
    _ = get_job_logs_endpoint


__all__ = ["register_http_routes"]
