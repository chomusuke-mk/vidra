from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import (
    Any,
    Callable,
    Iterable,
    List,
    Mapping,
    Optional,
    Protocol,
    Sequence,
    Set,
    Tuple,
    TypedDict,
    cast,
)

from ...config import JobStatus, SocketEvent
from ...core.contract import PostprocessorHook, ProgressHook
from ...core.downloader import PostProcessorHookArgs, ProgressHookArgs, YtDlpInfoResult
from ...download.hook_payloads import PostHookPayload
from ...download.mixins.manager_utils import (
    ManagerUtilsMixin,
    metadata_get_playlist_model,
    metadata_store_playlist_model,
)
from ...download.mixins.protocols import ProgressManagerProtocol
from ...download.models import (
    DownloadJob,
    DownloadJobMetadataPayload,
    DownloadJobProgressPayload,
)
from ...download.stages import DownloadStage
from ...log_config import debug_verbose
from ...models.socket import ProgressPayload
from ...utils import now_iso, to_float, to_int
from ...models.shared import (
    JSONValue,
    PlaylistEntryMetadata,
    PlaylistEntryProgressSnapshot,
    PlaylistMetadata,
)
from ...models.download.playlist_entry_error import PlaylistEntryError
from ...models.download.mixins.preview import PlaylistSnapshotPayload


MetadataSanitizer = Callable[[object | None], DownloadJobMetadataPayload]


class ProgressAccumulatorRecord(TypedDict, total=False):
    current_ctx: Optional[str]
    offset_downloaded: float
    offset_total: float
    seen_ctx: Set[str]


ProgressAccumulatorMap = dict[str, ProgressAccumulatorRecord]


class PlaylistEntryEventPayload(TypedDict, total=False):
    job_id: str
    playlist_index: int
    state: str
    timestamp: str
    playlist_entry_id: str
    status: str
    stage: str
    stage_name: str
    percent: float
    stage_percent: float
    downloaded_bytes: int
    total_bytes: int
    speed: float
    eta: int
    elapsed: float
    message: str
    main_file: str
    generated_files: List[str]
    partial_files: List[str]
    playlist_current_entry_id: str
    reason: str
    is_terminal: bool
    is_active: bool
    job_status: str


class PlaylistProgressEventPayload(DownloadJobProgressPayload, total=False):
    playlist_completed_indices: List[int]


class ProgressDataView(Protocol):
    def get(self, key: str, default: object = ...) -> object: ...

    def items(self) -> Iterable[tuple[str, object]]: ...

    def __contains__(self, key: object) -> bool: ...

    def __getitem__(self, key: str) -> object: ...


class ProgressMixin(ManagerUtilsMixin):
    def _progress_manager(self) -> "ProgressManagerProtocol":
        return cast("ProgressManagerProtocol", self)

    def _build_progress_hook(self, job_id: str) -> Callable[[ProgressHookArgs], None]:
        manager = self._progress_manager()

        def _hook(data: ProgressHookArgs) -> None:
            manager.guard_job_signals(job_id)
            progress = ProgressHook(data)
            normalized = self._normalize_progress(job_id, progress, data)
            self._store_progress(job_id, normalized)

        return _hook

    def _build_postprocessor_hook(
        self, job_id: str
    ) -> Callable[[PostProcessorHookArgs], None]:
        manager = self._progress_manager()

        def _hook(data: PostProcessorHookArgs) -> None:
            manager.guard_job_signals(job_id)
            hook = PostprocessorHook(data)
            self._handle_postprocessor_event(job_id, hook, data)

        return _hook

    def _build_post_hook(self, job_id: str) -> Callable[[str], None]:
        def _hook(info: str) -> None:
            payload = PostHookPayload(info)
            self._handle_post_hook_event(job_id, payload)

        return _hook

    def _normalize_progress(
        self,
        job_id: str,
        progress: ProgressHook,
        raw_data: ProgressHookArgs,
    ) -> DownloadJobProgressPayload:
        downloaded_bytes = progress.downloaded_bytes
        if downloaded_bytes is None or float(downloaded_bytes) < 0:
            downloaded_bytes = 0
        if isinstance(downloaded_bytes, float) and downloaded_bytes.is_integer():
            downloaded_bytes = int(downloaded_bytes)
        downloaded_value = int(downloaded_bytes)

        total_bytes = progress.total_bytes
        if total_bytes is not None and float(total_bytes) <= 0:
            total_bytes = None
        if isinstance(total_bytes, float):
            if total_bytes.is_integer():
                total_bytes = int(total_bytes)

        percent = progress.percent
        status = progress.status or JobStatus.RUNNING.value

        result: DownloadJobProgressPayload = {
            "job_id": job_id,
            "status": status,
            "downloaded_bytes": downloaded_value,
        }

        if total_bytes is not None:
            result["total_bytes"] = int(total_bytes)

        remaining_value = to_int(progress.remaining_bytes)
        if remaining_value is not None:
            result["remaining_bytes"] = remaining_value

        speed_value = to_float(progress.speed)
        if speed_value is not None:
            result["speed"] = speed_value

        eta_value = to_int(progress.eta)
        if eta_value is not None:
            result["eta"] = eta_value

        elapsed_value = to_float(progress.elapsed)
        if elapsed_value is not None:
            result["elapsed"] = elapsed_value

        if progress.filename:
            result["filename"] = progress.filename
        if progress.tmpfilename:
            result["tmpfilename"] = progress.tmpfilename

        percent_value = to_float(percent)
        if percent_value is not None:
            result["percent"] = percent_value

        if progress.ctx_id:
            result["ctx_id"] = progress.ctx_id

        data_view = cast(ProgressDataView, raw_data)
        stage_payload = self._derive_stage_metadata(
            progress=progress,
            data=data_view,
            status=status,
            percent=percent,
        )
        result.update(stage_payload)

        playlist_fields = self._extract_playlist_progress_fields(
            data_view,
            progress=progress,
        )
        result.update(playlist_fields)

        if progress.entry_id:
            result.setdefault("playlist_current_entry_id", progress.entry_id)

        return result

    def _derive_stage_metadata(
        self,
        *,
        progress: ProgressHook,
        data: ProgressDataView,
        status: str,
        percent: Optional[float],
    ) -> DownloadJobProgressPayload:
        raw_stage = data.get("stage")
        if raw_stage is None:
            raw_stage = progress.status or status or DownloadStage.PROGRESSING.value
        stage_value_candidate = str(raw_stage).strip()
        stage_value = stage_value_candidate or DownloadStage.PROGRESSING.value

        raw_stage_name = data.get("stage_name")
        if raw_stage_name is not None:
            stage_name_candidate = str(raw_stage_name).strip()
            stage_name = stage_name_candidate or stage_value
        else:
            stage_name = stage_value

        message = data.get("message")
        if message is None and progress.message is not None:
            message = progress.message

        stage_percent_value = data.get("stage_percent")
        if stage_percent_value is None:
            stage_percent_value = self._stage_percent_from_payload(data)
        if stage_percent_value is None and percent is not None:
            stage_percent_value = percent
        normalized_stage_percent = self._normalize_percent_value(stage_percent_value)

        current_item = data.get("current_item", progress.current_item)
        total_items = data.get("total_items", progress.total_items)
        stage_current, stage_total = self._stage_items_from_payload(data)
        if stage_current is not None:
            current_item = stage_current
        if stage_total is not None:
            total_items = stage_total

        payload: DownloadJobProgressPayload = {"stage": stage_value}
        if stage_name:
            payload["stage_name"] = stage_name
        if normalized_stage_percent is not None:
            payload["stage_percent"] = normalized_stage_percent

        normalized_current = to_int(current_item)
        if normalized_current is not None:
            payload["current_item"] = normalized_current

        normalized_total = to_int(total_items)
        if normalized_total is not None:
            payload["total_items"] = normalized_total
        if message is not None:
            message_text = str(message).strip()
            if message_text:
                payload["message"] = message_text

        return payload

    def _handle_postprocessor_event(
        self,
        job_id: str,
        hook: PostprocessorHook,
        raw_data: PostProcessorHookArgs,
    ) -> None:
        manager = self._progress_manager()
        data = cast(ProgressDataView, raw_data)
        job: Optional[DownloadJob] = None
        with manager.lock:
            job = manager.jobs.get(job_id)
            if job:
                self._register_generated_paths(job, data)

        stage_name_value = hook.postprocessor or hook.status
        if isinstance(stage_name_value, str):
            stage_name_value = stage_name_value.strip()
        stage_name = stage_name_value or None
        if not stage_name:
            stage_name = DownloadStage.PROGRESSING.value

        stage_percent = self._normalize_percent_value(hook.percent)
        message = hook.message

        payload_dict: DownloadJobProgressPayload = {"stage": stage_name}
        if stage_name:
            payload_dict["stage_name"] = stage_name
        if message:
            payload_dict["message"] = message
        if stage_percent is not None:
            payload_dict["stage_percent"] = stage_percent

        status_value = hook.status.strip() if isinstance(hook.status, str) else None
        payload_dict["status"] = status_value or (
            job.status if job else JobStatus.RUNNING.value
        )

        current_item, total_items = self._stage_items_from_payload(data)
        if current_item is not None:
            payload_dict["current_item"] = current_item
        if total_items is not None:
            payload_dict["total_items"] = total_items

        entry_id = hook.entry_id
        if entry_id:
            payload_dict["playlist_current_entry_id"] = entry_id

        playlist_fields = self._extract_playlist_progress_fields(
            data,
            postprocessor=hook,
        )
        payload_dict.update(playlist_fields)

        self._store_progress(job_id, payload_dict)

    def _handle_post_hook_event(self, job_id: str, payload: PostHookPayload) -> None:
        completion_payload: DownloadJobProgressPayload = {
            "stage": DownloadStage.COMPLETED.value,
            "stage_name": DownloadStage.COMPLETED.value,
            "status": payload.status,
            "stage_percent": 100.0,
            "percent": 100.0,
        }
        message = payload.message
        normalized_path: Optional[str] = None
        generated_candidates: List[str] = []
        if message:
            completion_payload["message"] = message
            normalized = message.strip()
            if normalized:
                normalized_path = normalized
                generated_candidates.append(normalized)
                manager = self._progress_manager()
                with manager.lock:
                    job = manager.jobs.get(job_id)
                    if job:
                        is_playlist_job = self._job_behaves_like_playlist(job)
                        if not is_playlist_job:
                            job.main_file = normalized
                        job.generated_files.add(normalized)
                        job.partial_files.discard(normalized)
                        job.partial_files.discard(f"{normalized}.part")
                        try:
                            resolved = str(Path(normalized).expanduser().resolve())
                        except Exception:
                            resolved = None
                        if resolved:
                            job.generated_files.add(resolved)
                            job.partial_files.discard(resolved)
                            normalized_path = resolved
                            if resolved not in generated_candidates:
                                generated_candidates.append(resolved)
        if normalized_path:
            completion_payload["main_file"] = normalized_path
        if generated_candidates:
            deduped: List[str] = []
            for candidate in generated_candidates:
                if candidate not in deduped:
                    deduped.append(candidate)
            completion_payload["generated_files"] = deduped
        entry_id = payload.entry_id
        if entry_id:
            completion_payload["playlist_current_entry_id"] = entry_id
        self._store_progress(job_id, completion_payload)

    def _compose_playlist_entry_event_payload(
        self,
        job: DownloadJob,
        *,
        index: int,
        state: str,
        entry_id: Optional[str],
        sources: Sequence[DownloadJobProgressPayload],
        overrides: Optional[PlaylistEntryEventPayload] = None,
    ) -> PlaylistEntryEventPayload:
        data_sources: List[ProgressDataView] = [
            cast(ProgressDataView, source) for source in sources
        ]
        override_source: ProgressDataView | None = (
            cast(ProgressDataView, overrides) if overrides else None
        )

        def _extract(key: str) -> object | None:
            if override_source and key in override_source:
                return override_source.get(key)
            for candidate in data_sources:
                if key in candidate:
                    value = candidate.get(key)
                    if value is not None:
                        return value
            return None

        def _string_value(key: str) -> Optional[str]:
            raw_value = _extract(key)
            if raw_value is None:
                return None
            if isinstance(raw_value, str):
                return raw_value.strip() or None
            if isinstance(raw_value, (int, float, bool)):
                return str(raw_value).strip() or None
            return None

        def _int_value(key: str) -> Optional[int]:
            return to_int(_extract(key))

        def _float_value(key: str) -> Optional[float]:
            return to_float(_extract(key))

        def _string_list(key: str) -> List[str]:
            raw_value = _extract(key)
            entries: List[str] = []
            if raw_value is None:
                return entries
            if isinstance(raw_value, str):
                trimmed = raw_value.strip()
                if trimmed:
                    entries.append(trimmed)
                return entries
            if isinstance(raw_value, Iterable) and not isinstance(
                raw_value, (str, bytes, bytearray)
            ):
                for item in cast(Iterable[object], raw_value):
                    if not isinstance(item, str):
                        continue
                    trimmed = item.strip()
                    if trimmed and trimmed not in entries:
                        entries.append(trimmed)
                return entries
            return entries

        payload_dict: dict[str, object] = {
            "job_id": job.job_id,
            "playlist_index": index,
            "state": state,
            "timestamp": now_iso(),
            "job_status": job.status,
        }
        if entry_id:
            payload_dict["playlist_entry_id"] = entry_id

        default_status_map = {
            "active": JobStatus.RUNNING.value,
            "reopened": JobStatus.RUNNING.value,
            "queued": JobStatus.QUEUED.value,
            "completed": JobStatus.COMPLETED.value,
            "failed": JobStatus.FAILED.value,
            "cancelled": JobStatus.CANCELLED.value,
        }

        status_value = _string_value("status")
        if status_value is None:
            status_value = default_status_map.get(state, job.status)
        payload_dict["status"] = status_value

        stage_value = _string_value("stage")
        if stage_value is None:
            if state == JobStatus.COMPLETED.value:
                stage_value = DownloadStage.COMPLETED.value
            elif state == JobStatus.FAILED.value:
                stage_value = "error"
            elif state == JobStatus.CANCELLED.value:
                stage_value = JobStatus.CANCELLED.value
            else:
                stage_value = DownloadStage.PROGRESSING.value
        payload_dict["stage"] = stage_value

        stage_name_value = _string_value("stage_name")
        if stage_name_value is None:
            stage_name_value = stage_value
        if stage_name_value:
            payload_dict["stage_name"] = stage_name_value

        percent_value = _float_value("percent")
        stage_percent_value = _float_value("stage_percent")
        if percent_value is None and stage_percent_value is not None:
            percent_value = stage_percent_value
        if stage_percent_value is None and percent_value is not None:
            stage_percent_value = percent_value

        if percent_value is None:
            if state == JobStatus.COMPLETED.value:
                percent_value = 100.0
            elif state == JobStatus.FAILED.value:
                percent_value = 100.0
            elif state == JobStatus.CANCELLED.value:
                percent_value = 0.0
            elif state in {"active", "reopened"}:
                percent_value = 0.0
            else:
                percent_value = 0.0
        if stage_percent_value is None:
            stage_percent_value = percent_value

        normalized_percent = self._normalize_percent_value(percent_value)
        normalized_stage_percent = self._normalize_percent_value(stage_percent_value)
        if normalized_percent is not None:
            payload_dict["percent"] = normalized_percent
        if normalized_stage_percent is not None:
            payload_dict["stage_percent"] = normalized_stage_percent

        downloaded_bytes = _int_value("downloaded_bytes")
        if downloaded_bytes is not None:
            payload_dict["downloaded_bytes"] = downloaded_bytes
        total_bytes = _int_value("total_bytes")
        if total_bytes is not None:
            payload_dict["total_bytes"] = total_bytes
        speed_value = _float_value("speed")
        if speed_value is not None:
            payload_dict["speed"] = speed_value
        eta_value = _int_value("eta")
        if eta_value is not None:
            payload_dict["eta"] = eta_value
        elapsed_value = _float_value("elapsed")
        if elapsed_value is not None:
            payload_dict["elapsed"] = elapsed_value

        message_text = _string_value("message")
        if message_text:
            payload_dict["message"] = message_text

        main_file_value = _string_value("main_file")
        if main_file_value:
            payload_dict["main_file"] = main_file_value

        filename_value = _string_value("filename")
        if filename_value:
            payload_dict["filename"] = filename_value
        tmpfilename_value = _string_value("tmpfilename")
        if tmpfilename_value:
            payload_dict["tmpfilename"] = tmpfilename_value

        generated_files: List[str] = _string_list("generated_files")
        for candidate in (main_file_value, filename_value):
            if candidate and candidate not in generated_files:
                generated_files.append(candidate)
        if generated_files:
            payload_dict["generated_files"] = generated_files

        partial_files: List[str] = _string_list("partial_files")
        partial_candidates = [tmpfilename_value]
        if filename_value:
            partial_candidates.append(f"{filename_value}.part")
        for candidate in partial_candidates:
            if candidate and candidate not in partial_files:
                partial_files.append(candidate)
        if partial_files:
            payload_dict["partial_files"] = partial_files

        payload_dict["is_terminal"] = state in {
            JobStatus.COMPLETED.value,
            JobStatus.FAILED.value,
            JobStatus.CANCELLED.value,
        }
        payload_dict["is_active"] = state in {"active", "reopened"}

        if override_source:
            for key, value in override_source.items():
                if value is not None:
                    payload_dict[key] = value

        return cast(PlaylistEntryEventPayload, payload_dict)

    def _resolve_playlist_entry_url(
        self, job: DownloadJob, index: int
    ) -> Optional[str]:
        if index <= 0:
            return None
        metadata: DownloadJobMetadataPayload = job.metadata or {}
        playlist_model = metadata_get_playlist_model(metadata, clone=True)
        if playlist_model is None:
            playlist_meta_raw = metadata.get("playlist")
            if not isinstance(playlist_meta_raw, Mapping):
                return None
            playlist_model = PlaylistMetadata.from_payload(
                cast(Mapping[str, object], playlist_meta_raw)
            )
        for entry in playlist_model.entries:
            if entry.index != index:
                continue
            if entry.webpage_url:
                return entry.webpage_url
            if entry.preview:
                if entry.preview.webpage_url:
                    return entry.preview.webpage_url
                if entry.preview.original_url:
                    return entry.preview.original_url
            if entry.entry_id:
                return entry.entry_id
        return None

    def _upsert_playlist_entry_error(
        self,
        job: DownloadJob,
        *,
        index: int,
        entry_id: Optional[str],
        message: Optional[str],
        timestamp: Optional[str],
        status: Optional[str],
    ) -> bool:
        if index <= 0:
            return False

        url_hint = self._resolve_playlist_entry_url(job, index)
        sanitized_entry_id = entry_id.strip() if isinstance(entry_id, str) else entry_id
        sanitized_message = message.strip() if isinstance(message, str) else message
        sanitized_timestamp = (
            timestamp.strip()
            if isinstance(timestamp, str) and timestamp.strip()
            else None
        )
        changed = False

        record = job.playlist_entry_errors.get(index)
        if record is None:
            record = PlaylistEntryError(
                index=index,
                entry_id=sanitized_entry_id,
                url=url_hint,
                message=sanitized_message,
                recorded_at=sanitized_timestamp or now_iso(),
                last_status=status,
            )
            job.playlist_entry_errors[index] = record
            changed = True
        else:
            if sanitized_entry_id and record.entry_id != sanitized_entry_id:
                record.entry_id = sanitized_entry_id
                changed = True
            if url_hint and record.url != url_hint:
                record.url = url_hint
                changed = True
            if sanitized_message and record.message != sanitized_message:
                record.message = sanitized_message
                changed = True
            if sanitized_timestamp and record.recorded_at != sanitized_timestamp:
                record.recorded_at = sanitized_timestamp
                changed = True
            elif not record.recorded_at:
                record.recorded_at = now_iso()
                changed = True
            if status and record.last_status != status:
                record.last_status = status
                changed = True

        if index not in job.playlist_failed_indices:
            job.playlist_failed_indices.add(index)
            changed = True

        return changed

    def _record_playlist_entry_failure(
        self,
        job: DownloadJob,
        *,
        index: int,
        payload: PlaylistEntryEventPayload,
    ) -> None:
        entry_id_value = payload.get("playlist_entry_id")
        entry_id = entry_id_value.strip() if isinstance(entry_id_value, str) else None
        message_value = payload.get("message") or payload.get("reason")
        message = message_value.strip() if isinstance(message_value, str) else None
        timestamp_value = payload.get("timestamp")
        timestamp = (
            timestamp_value.strip() if isinstance(timestamp_value, str) else None
        )
        status_value = payload.get("status")
        self._upsert_playlist_entry_error(
            job,
            index=index,
            entry_id=entry_id,
            message=message,
            timestamp=timestamp,
            status=str(status_value) if isinstance(status_value, str) else None,
        )

    def _record_playlist_entry_log_error(
        self,
        job: DownloadJob,
        *,
        index: Optional[int],
        entry_id: Optional[str],
        message: str,
        timestamp: Optional[str],
    ) -> bool:
        if index is None or index <= 0:
            return False
        status_hint = JobStatus.FAILED.value
        sanitized_entry_id = entry_id.strip() if isinstance(entry_id, str) else entry_id
        return self._upsert_playlist_entry_error(
            job,
            index=index,
            entry_id=sanitized_entry_id,
            message=message,
            timestamp=timestamp,
            status=status_hint,
        )

    def _clear_playlist_entry_failure(
        self,
        job: DownloadJob,
        index: Optional[int],
        *,
        preserve_record: bool = False,
    ) -> None:
        if index is None or index <= 0:
            return
        if not preserve_record:
            job.playlist_failed_indices.discard(index)
            job.playlist_entry_errors.pop(index, None)
        job.playlist_pending_indices.discard(index)

    def _stage_percent_from_payload(self, data: ProgressDataView) -> Optional[float]:
        for key in (
            "stage_percent",
            "progress_percent",
            "progress",
            "percent",
            "percent_str",
        ):
            if key in data:
                value = self._normalize_percent_value(data.get(key))
                if value is not None:
                    return value
        return None

    def _stage_items_from_payload(
        self, data: ProgressDataView
    ) -> Tuple[Optional[int], Optional[int]]:
        for current_key, total_key in (
            ("progress_idx", "progress_total"),
            ("progress_current", "progress_total"),
        ):
            if current_key in data and total_key in data:
                current = to_int(data.get(current_key))
                total = to_int(data.get(total_key))
                if current is not None or total is not None:
                    return current, total
        return None, None

    def _store_playlist_entry_snapshot(
        self,
        job: DownloadJob,
        *,
        index: int,
        payload: PlaylistEntryEventPayload,
    ) -> bool:
        if index <= 0:
            return False
        metadata: DownloadJobMetadataPayload = job.metadata or {}
        playlist_model = metadata_get_playlist_model(metadata)
        if playlist_model is None:
            playlist_meta = metadata.get("playlist")
            if not isinstance(playlist_meta, dict):
                return False
            playlist_model = PlaylistMetadata.from_payload(playlist_meta)
            metadata_store_playlist_model(metadata, playlist_model)
        target_entry: Optional[PlaylistEntryMetadata] = None
        for entry in playlist_model.entries:
            if entry.index == index:
                target_entry = entry
                break
        if target_entry is None:
            return False

        payload_view = cast(ProgressDataView, payload)
        snapshot = target_entry.progress_snapshot or PlaylistEntryProgressSnapshot()
        changed = False

        def _int_value(key: str) -> Optional[int]:
            numeric = to_float(payload_view.get(key))
            if numeric is None:
                return None
            return int(round(max(numeric, 0.0)))

        def _float_value(key: str, *, precision: int = 3) -> Optional[float]:
            numeric = to_float(payload_view.get(key))
            if numeric is None:
                return None
            return round(numeric, precision)

        def _string_value(key: str) -> Optional[str]:
            raw_value = payload_view.get(key)
            if raw_value is None:
                return None
            if isinstance(raw_value, str):
                text = raw_value.strip()
            else:
                text = str(raw_value).strip()
            return text or None

        def _assign_snapshot(attr: str, value: Optional[object]) -> None:
            nonlocal changed
            if getattr(snapshot, attr) != value:
                setattr(snapshot, attr, value)
                changed = True

        percent_value = to_float(payload_view.get("percent"))
        stage_percent_value = to_float(payload_view.get("stage_percent"))
        _assign_snapshot("downloaded_bytes", _int_value("downloaded_bytes"))
        _assign_snapshot("total_bytes", _int_value("total_bytes"))
        _assign_snapshot("speed", _float_value("speed"))
        _assign_snapshot("eta", _int_value("eta"))
        _assign_snapshot("elapsed", _float_value("elapsed"))
        _assign_snapshot("filename", _string_value("filename"))
        _assign_snapshot("tmpfilename", _string_value("tmpfilename"))
        _assign_snapshot("main_file", _string_value("main_file"))
        if percent_value is not None:
            _assign_snapshot("percent", round(percent_value, 2))
        if stage_percent_value is not None:
            _assign_snapshot("stage_percent", round(stage_percent_value, 2))

        status_value = _string_value("status")
        if status_value is not None:
            _assign_snapshot("status", status_value)
        stage_value = _string_value("stage")
        if stage_value is not None:
            _assign_snapshot("stage", stage_value)
        stage_name_value = _string_value("stage_name")
        if stage_name_value is not None:
            _assign_snapshot("stage_name", stage_name_value)
        message_value = _string_value("message")
        if message_value is not None:
            _assign_snapshot("message", message_value)
        state_value = _string_value("state")
        if state_value is not None:
            _assign_snapshot("state", state_value)

        timestamp = _string_value("timestamp")
        if not timestamp:
            timestamp = now_iso()
        _assign_snapshot("timestamp", timestamp)

        if snapshot.has_data():
            if target_entry.progress_snapshot is not snapshot:
                target_entry.progress_snapshot = snapshot
                changed = True
        elif target_entry.progress_snapshot is not None:
            target_entry.progress_snapshot = None
            changed = True

        def _set_entry_attr(
            attr: str,
            value: Optional[str],
            *,
            only_if_empty: bool = False,
        ) -> None:
            nonlocal changed
            if value is None:
                return
            existing = getattr(target_entry, attr)
            if only_if_empty and existing:
                return
            if existing != value:
                setattr(target_entry, attr, value)
                changed = True

        resolved_main_file = _string_value("main_file")
        if resolved_main_file:
            _set_entry_attr("main_file", resolved_main_file)
        else:
            filename_hint = _string_value("filename")
            if not filename_hint:
                filename_hint = _string_value("tmpfilename")
            if filename_hint:
                _set_entry_attr(
                    "main_file",
                    filename_hint,
                    only_if_empty=True,
                )

        status_hint = snapshot.status or status_value
        if status_hint:
            _set_entry_attr("status", status_hint)

        normalized_state = snapshot.state or (
            state_value.lower() if state_value else None
        )
        if normalized_state:
            normalized_state = normalized_state.strip().lower()

        def _set_flag(attr: str, value: bool) -> None:
            nonlocal changed
            if getattr(target_entry, attr) != value:
                setattr(target_entry, attr, value)
                changed = True

        if normalized_state == JobStatus.COMPLETED.value:
            _set_flag("is_completed", True)
            _set_flag("is_current", False)
        elif normalized_state == "active":
            _set_flag("is_current", True)
            _set_flag("is_completed", False)
        elif normalized_state in {
            JobStatus.FAILED.value,
            JobStatus.CANCELLED.value,
        }:
            _set_flag("is_current", False)
            _set_flag("is_completed", False)

        if changed:
            metadata_store_playlist_model(metadata, playlist_model)
            job.metadata = metadata
        return changed

    def build_playlist_entry_state(
        self,
        job_id: str,
        entry_index: int,
    ) -> Optional[PlaylistEntryEventPayload]:
        if entry_index <= 0:
            return None
        manager = self._progress_manager()
        with manager.lock:
            job = manager.jobs.get(job_id)
            if not job:
                return None
            progress_state = cast(
                DownloadJobProgressPayload,
                dict(job.progress) if job.progress else {},
            )
            current_index = to_int(
                progress_state.get("playlist_current_index")
                or progress_state.get("playlist_index")
            )
            if current_index is not None and current_index <= 0:
                current_index = None

            selected_indices = self._resolve_selected_playlist_indices(job)
            completed_indices = set(job.playlist_completed_indices)
            if selected_indices:
                completed_indices.intersection_update(selected_indices)

            entry_state = JobStatus.QUEUED.value
            if current_index is not None and entry_index == current_index:
                entry_state = "active"
            elif entry_index in completed_indices:
                entry_state = JobStatus.COMPLETED.value
            elif job.status == JobStatus.CANCELLED.value:
                entry_state = JobStatus.CANCELLED.value
            elif job.status == JobStatus.FAILED.value:
                entry_state = JobStatus.FAILED.value

            entry_id = manager.resolve_playlist_entry_id(job, entry_index)
            payload = self._compose_playlist_entry_event_payload(
                job,
                index=entry_index,
                state=entry_state,
                entry_id=entry_id,
                sources=(progress_state,),
            )
            payload.setdefault("job_status", job.status)
            return payload

    @staticmethod
    def _clone_progress_payload(
        payload: DownloadJobProgressPayload | None,
    ) -> DownloadJobProgressPayload:
        clone: DownloadJobProgressPayload = {}
        if payload:
            clone.update(payload)
        return clone

    def _store_progress(self, job_id: str, payload: DownloadJobProgressPayload) -> None:
        progress_summary: Optional[ProgressPayload] = None
        playlist_event: Optional[PlaylistProgressEventPayload] = None
        playlist_snapshot: Optional[PlaylistSnapshotPayload] = None
        playlist_entry_events: List[Tuple[int, PlaylistEntryEventPayload]] = []
        manager = self._progress_manager()
        manager_obj = cast(object, manager)
        persist_required = False
        sync_entries_required = False
        metadata_snapshot: Optional[DownloadJobMetadataPayload] = None
        with manager.lock:
            job = manager.jobs.get(job_id)
            if not job:
                return
            existing_payload = self._clone_progress_payload(job.progress)
            previous_stage = existing_payload.get("stage")
            incoming_payload = self._clone_progress_payload(payload)
            mutable_incoming = cast(dict[str, object], incoming_payload)
            self._harmonize_progress_payload(
                job,
                existing_payload,
                incoming_payload,
            )
            status_value = incoming_payload.get("status")
            status = status_value or job.status
            merged_payload = self._clone_progress_payload(existing_payload)
            mutable_merged = cast(dict[str, object], merged_payload)
            mutable_merged["status"] = status
            for key, value in incoming_payload.items():
                if value is None:
                    mutable_merged.pop(key, None)
                else:
                    mutable_merged[key] = value
            incoming_stage = incoming_payload.get("stage")
            stage_changed = False
            if incoming_stage is not None:
                merged_payload["stage"] = incoming_stage
            elif "stage" not in merged_payload:
                merged_payload["stage"] = DownloadStage.IDENTIFICANDO.value

            new_stage = merged_payload.get("stage")
            if new_stage is not None and previous_stage != new_stage:
                stage_changed = True

            if stage_changed and previous_stage is not None:
                cleanup_keys = (
                    "stage_percent",
                    "stage_name",
                    "message",
                    "current_item",
                    "total_items",
                )
                for key in cleanup_keys:
                    if key not in mutable_incoming:
                        mutable_merged.pop(key, None)

            existing_elapsed = to_float(existing_payload.get("elapsed"))
            incoming_elapsed = to_float(incoming_payload.get("elapsed"))
            if existing_elapsed is not None and incoming_elapsed is not None:
                if incoming_elapsed < existing_elapsed:
                    merged_payload["elapsed"] = existing_elapsed
                else:
                    merged_payload["elapsed"] = incoming_elapsed
            elif incoming_elapsed is not None:
                merged_payload["elapsed"] = incoming_elapsed
            elif existing_elapsed is not None:
                merged_payload["elapsed"] = existing_elapsed

            if job.started_at:
                if job.finished_at and job.finished_at >= job.started_at:
                    computed_elapsed = (
                        job.finished_at - job.started_at
                    ).total_seconds()
                else:
                    utc_now = datetime.now(timezone.utc).replace(tzinfo=None)
                    computed_elapsed = (utc_now - job.started_at).total_seconds()
                if computed_elapsed >= 0:
                    current_elapsed = to_float(merged_payload.get("elapsed"))
                    if current_elapsed is None or computed_elapsed > current_elapsed:
                        merged_payload["elapsed"] = computed_elapsed

            (
                playlist_event,
                playlist_snapshot,
                playlist_entry_events,
                playlist_metadata_changed,
            ) = self._update_playlist_progress(
                job,
                incoming_payload,
                merged_payload,
                existing_payload,
            )

            if playlist_metadata_changed:
                persist_required = True
                safe_metadata_fn = cast(
                    Optional[MetadataSanitizer],
                    getattr(manager, "_safe_metadata_payload", None),
                )
                if safe_metadata_fn is not None:
                    metadata_snapshot = safe_metadata_fn(job.metadata)
                else:
                    metadata_snapshot = cast(
                        DownloadJobMetadataPayload,
                        dict(job.metadata),
                    )
                sync_entries_required = True

            stage_value_str = str(merged_payload.get("stage") or "")
            stage_upper = stage_value_str.upper()
            playlist_index_for_logs = to_int(
                merged_payload.get("playlist_current_index")
                or merged_payload.get("playlist_index")
            )
            entry_id_raw = merged_payload.get("playlist_current_entry_id")
            entry_id_text = None
            if isinstance(entry_id_raw, str):
                entry_id_text = entry_id_raw.strip() or None
            elif entry_id_raw is not None:
                entry_id_text = str(entry_id_raw).strip() or None

            if (
                playlist_index_for_logs is not None
                and playlist_index_for_logs > 0
                and stage_upper != DownloadStage.COMPLETED.value
            ):
                job.active_playlist_log_index = playlist_index_for_logs
                job.active_playlist_log_entry_id = entry_id_text
            elif stage_upper == DownloadStage.COMPLETED.value:
                job.active_playlist_log_index = None
                job.active_playlist_log_entry_id = None
            elif playlist_index_for_logs is None or playlist_index_for_logs <= 0:
                job.active_playlist_log_index = None
                job.active_playlist_log_entry_id = None

            if stage_changed:
                playlist_index_for_log: Optional[int] = None
                for candidate in (
                    incoming_payload.get("playlist_current_index"),
                    incoming_payload.get("playlist_index"),
                    merged_payload.get("playlist_current_index"),
                    merged_payload.get("playlist_index"),
                    existing_payload.get("playlist_current_index"),
                    existing_payload.get("playlist_index"),
                ):
                    index_value = to_int(candidate)
                    if index_value is not None and index_value > 0:
                        playlist_index_for_log = index_value
                        break
                if playlist_index_for_log is not None:
                    stage_value = (
                        new_stage.strip()
                        if isinstance(new_stage, str)
                        else str(new_stage)
                    )
                    if stage_value:
                        debug_verbose(
                            "playlist_stage_change",
                            {
                                "job_id": job_id,
                                "playlist_index": playlist_index_for_log,
                                "stage": stage_value,
                                "stage_name": merged_payload.get("stage_name"),
                            },
                        )

            job.progress = self._clone_progress_payload(merged_payload)
            merged_view = cast(ProgressDataView, merged_payload)
            self._register_generated_paths(job, merged_view)
            progress_summary = self._build_progress_summary(job_id, merged_view)

        if progress_summary:
            serialized_progress = cast(JSONValue, progress_summary.to_dict())
            manager.emit_socket(
                SocketEvent.PROGRESS.value,
                serialized_progress,
                room=manager.job_room(job_id),
            )
        if playlist_event:
            manager.emit_socket(
                SocketEvent.PLAYLIST_PROGRESS.value,
                cast(Any, playlist_event),
                room=manager.job_room(job_id),
            )
        if playlist_snapshot:
            manager.emit_socket(
                SocketEvent.PLAYLIST_SNAPSHOT.value,
                cast(Any, playlist_snapshot),
                room=manager.job_room(job_id),
            )
        for _, entry_payload in playlist_entry_events:
            manager.emit_socket(
                SocketEvent.PLAYLIST_ENTRY_PROGRESS.value,
                cast(Any, entry_payload),
                room=manager.job_room(job_id),
            )

        if persist_required:
            persist_fn = getattr(manager_obj, "_persist_jobs", None)
            if callable(persist_fn):
                persist_fn()
        if sync_entries_required:
            sync_fn = getattr(manager_obj, "_sync_playlist_entries", None)
            if callable(sync_fn):
                sync_fn(job_id, metadata_snapshot=metadata_snapshot)

    def store_progress(self, job_id: str, payload: DownloadJobProgressPayload) -> None:
        """Public wrapper ensuring mixins use the supported entry point."""

        self._store_progress(job_id, payload)

    def _harmonize_progress_payload(
        self,
        job: DownloadJob,
        existing: DownloadJobProgressPayload,
        incoming: DownloadJobProgressPayload,
    ) -> None:
        downloaded_raw = to_float(incoming.get("downloaded_bytes"))
        total_raw = to_float(incoming.get("total_bytes"))
        if downloaded_raw is None and total_raw is None:
            return

        incoming_mapping = cast(ProgressDataView, incoming)
        existing_mapping = cast(ProgressDataView, existing)
        entry_key = self._resolve_progress_entry_key(
            job, incoming_mapping, existing_mapping
        )
        context_key = self._resolve_progress_context_key(
            incoming_mapping, existing_mapping
        )
        if not entry_key:
            entry_key = f"job:{job.job_id}"
        if not context_key:
            context_key = "__default__"

        accumulators = getattr(job, "progress_accumulators", None)
        if not isinstance(accumulators, dict):
            job.progress_accumulators = {}
            accumulators = job.progress_accumulators
        typed_accumulators = cast(ProgressAccumulatorMap, accumulators)

        record: ProgressAccumulatorRecord = typed_accumulators.setdefault(
            entry_key,
            {
                "current_ctx": None,
                "offset_downloaded": 0.0,
                "offset_total": 0.0,
                "seen_ctx": set[str](),
            },
        )

        seen_ctx_raw = record.get("seen_ctx")
        seen_ctx: Set[str] = set(seen_ctx_raw) if seen_ctx_raw else set()
        record["seen_ctx"] = seen_ctx
        offset_downloaded = float(record.get("offset_downloaded") or 0.0)
        offset_total = float(record.get("offset_total") or 0.0)
        previous_ctx = record.get("current_ctx")

        if previous_ctx and context_key != previous_ctx:
            if previous_ctx not in seen_ctx:
                prev_downloaded = to_float(existing.get("downloaded_bytes"))
                prev_total = to_float(existing.get("total_bytes"))
                delta_downloaded = 0.0
                if prev_downloaded is not None:
                    delta_downloaded = max(prev_downloaded - offset_downloaded, 0.0)
                    offset_downloaded += delta_downloaded
                delta_total: Optional[float] = None
                if prev_total is not None:
                    delta_total = max(prev_total - offset_total, delta_downloaded)
                elif delta_downloaded > 0:
                    delta_total = delta_downloaded
                if delta_total is not None:
                    offset_total += max(delta_total, 0.0)
                seen_ctx.add(previous_ctx)

        record["current_ctx"] = context_key
        record["offset_downloaded"] = offset_downloaded
        record["offset_total"] = offset_total

        adjusted_downloaded = (
            downloaded_raw + offset_downloaded if downloaded_raw is not None else None
        )
        adjusted_total: Optional[float]
        if total_raw is not None:
            adjusted_total = total_raw + offset_total
        else:
            adjusted_total = None

        if (
            adjusted_total is None
            and offset_total > 0
            and adjusted_downloaded is not None
        ):
            adjusted_total = max(offset_total, adjusted_downloaded)

        def _format_bytes(value: Optional[float]) -> Optional[int]:
            if value is None:
                return None
            numeric = float(value)
            if numeric < 0:
                numeric = 0.0
            return int(round(numeric))

        if adjusted_downloaded is not None:
            formatted_downloaded = _format_bytes(adjusted_downloaded)
            if formatted_downloaded is not None:
                incoming["downloaded_bytes"] = formatted_downloaded
        elif offset_downloaded > 0:
            formatted_offset_downloaded = _format_bytes(offset_downloaded)
            if formatted_offset_downloaded is not None:
                incoming["downloaded_bytes"] = formatted_offset_downloaded

        if adjusted_total is not None:
            if adjusted_downloaded is not None and adjusted_total < adjusted_downloaded:
                adjusted_total = adjusted_downloaded
            formatted_total = _format_bytes(adjusted_total)
            if formatted_total is not None:
                incoming["total_bytes"] = formatted_total
        elif offset_total > 0:
            formatted_offset_total = _format_bytes(offset_total)
            if (
                formatted_offset_total is not None
                and to_float(incoming.get("total_bytes")) is None
            ):
                incoming["total_bytes"] = formatted_offset_total

        adjusted_downloaded_int = to_float(incoming.get("downloaded_bytes"))
        adjusted_total_int = to_float(incoming.get("total_bytes"))
        if adjusted_total_int is not None and adjusted_downloaded_int is not None:
            remaining = max(adjusted_total_int - adjusted_downloaded_int, 0.0)
            formatted_remaining = _format_bytes(remaining)
            if formatted_remaining is not None:
                incoming["remaining_bytes"] = formatted_remaining
            if adjusted_total_int > 0:
                percent = (adjusted_downloaded_int / adjusted_total_int) * 100.0
                percent = max(min(percent, 100.0), 0.0)
                normalized_percent = round(percent, 2)
                incoming["percent"] = normalized_percent
                incoming["stage_percent"] = normalized_percent

    def _resolve_progress_entry_key(
        self,
        job: DownloadJob,
        incoming: ProgressDataView,
        existing: ProgressDataView,
    ) -> Optional[str]:
        def _string_from(source: ProgressDataView, key: str) -> Optional[str]:
            value = source.get(key)
            if isinstance(value, str):
                trimmed = value.strip()
                if trimmed:
                    return trimmed
            return None

        entry_id = _string_from(incoming, "playlist_current_entry_id") or _string_from(
            existing, "playlist_current_entry_id"
        )
        if entry_id:
            return f"entry:{entry_id}"

        playlist_entry = _string_from(incoming, "playlist_entry_id") or _string_from(
            existing, "playlist_entry_id"
        )
        if playlist_entry:
            return f"entry:{playlist_entry}"

        index_candidate = to_int(
            incoming.get("playlist_current_index") or incoming.get("playlist_index")
        )
        if index_candidate is None:
            index_candidate = to_int(
                existing.get("playlist_current_index") or existing.get("playlist_index")
            )
        if index_candidate is not None and index_candidate > 0:
            return f"index:{index_candidate}"

        filename = _string_from(incoming, "filename") or _string_from(
            existing, "filename"
        )
        if filename:
            return f"file:{filename}"

        ctx = self._resolve_progress_context_key(incoming, existing)
        if ctx:
            return f"ctx:{ctx}"

        return f"job:{job.job_id}"

    def _resolve_progress_context_key(
        self,
        incoming: ProgressDataView,
        existing: ProgressDataView,
    ) -> Optional[str]:
        def _string_from(source: ProgressDataView, key: str) -> Optional[str]:
            value = source.get(key)
            if isinstance(value, str):
                trimmed = value.strip()
                if trimmed:
                    return trimmed
            return None

        for source in (incoming, existing):
            ctx_value = _string_from(source, "ctx_id")
            if ctx_value:
                return ctx_value

        for source in (incoming, existing):
            filename = _string_from(source, "filename")
            if filename:
                return f"file:{filename}"

        for source in (incoming, existing):
            tmp_name = _string_from(source, "tmpfilename")
            if tmp_name:
                return f"tmp:{tmp_name}"

        entry_id = _string_from(incoming, "playlist_current_entry_id") or _string_from(
            existing, "playlist_current_entry_id"
        )
        if entry_id:
            return f"entry:{entry_id}"

        index_candidate = to_int(
            incoming.get("playlist_current_index") or incoming.get("playlist_index")
        )
        if index_candidate is None:
            index_candidate = to_int(
                existing.get("playlist_current_index") or existing.get("playlist_index")
            )
        if index_candidate is not None and index_candidate > 0:
            return f"index:{index_candidate}"

        return None

    def _build_progress_summary(
        self, job_id: str, data: ProgressDataView
    ) -> ProgressPayload:
        def _text(value: object | None) -> Optional[str]:
            if value is None:
                return None
            text = str(value).strip()
            return text or None

        downloaded_bytes = to_int(data.get("downloaded_bytes"))
        total_bytes = to_int(data.get("total_bytes"))
        remaining_bytes = to_int(data.get("remaining_bytes"))
        if (
            remaining_bytes is None
            and downloaded_bytes is not None
            and total_bytes is not None
        ):
            remaining_candidate = total_bytes - downloaded_bytes
            if remaining_candidate >= 0:
                remaining_bytes = remaining_candidate

        return ProgressPayload(
            job_id=job_id,
            status=_text(data.get("status")),
            percent=to_float(data.get("percent")),
            downloaded_bytes=downloaded_bytes,
            total_bytes=total_bytes,
            remaining_bytes=remaining_bytes,
            speed=to_float(data.get("speed")),
            eta=to_int(data.get("eta")),
            elapsed=to_float(data.get("elapsed")),
            filename=_text(data.get("filename")),
            tmpfilename=_text(data.get("tmpfilename")),
            ctx_id=_text(data.get("ctx_id")),
            stage=_text(data.get("stage")),
            stage_name=_text(data.get("stage_name")),
            stage_percent=to_float(data.get("stage_percent")),
            current_item=to_int(data.get("current_item")),
            total_items=to_int(data.get("total_items")),
            message=_text(data.get("message")),
            playlist_index=to_int(data.get("playlist_index")),
            playlist_current_index=to_int(data.get("playlist_current_index")),
            playlist_count=to_int(data.get("playlist_count")),
            playlist_total_items=to_int(data.get("playlist_total_items")),
            playlist_completed_items=to_int(data.get("playlist_completed_items")),
            playlist_pending_items=to_int(data.get("playlist_pending_items")),
            playlist_percent=to_float(data.get("playlist_percent")),
            playlist_current_entry_id=_text(data.get("playlist_current_entry_id")),
            playlist_newly_completed_index=to_int(
                data.get("playlist_newly_completed_index")
            ),
        )

    def build_progress_summary(
        self, job_id: str, data: ProgressDataView
    ) -> ProgressPayload:
        """Public wrapper returning the structured progress summary."""

        return self._build_progress_summary(job_id, data)

    def _extract_playlist_progress_fields(
        self,
        data: ProgressDataView,
        *,
        progress: Optional[ProgressHook] = None,
        postprocessor: Optional[PostprocessorHook] = None,
    ) -> DownloadJobProgressPayload:
        snapshot = {key: value for key, value in data.items()}
        raw_info_dict = snapshot.get("info_dict")
        info_dict: Optional[YtDlpInfoResult]
        if isinstance(raw_info_dict, dict):
            info_dict = cast(YtDlpInfoResult, raw_info_dict)
        else:
            info_dict = None

        playlist_index_value: object | None = None
        playlist_count_value: object | None = None
        entry_id_value: object | None = None

        info_model = progress.info if progress else None

        if progress is not None:
            playlist_index_value = progress.playlist_index
            playlist_count_value = progress.playlist_count
            entry_id_value = progress.entry_id

        if postprocessor is not None:
            if playlist_index_value is None:
                playlist_index_value = postprocessor.playlist_index
            if entry_id_value is None:
                entry_id_value = postprocessor.entry_id
            if info_model is None:
                info_model = postprocessor.info

        if playlist_index_value is None:
            playlist_index_value = snapshot.get("playlist_index")
        if playlist_count_value is None:
            playlist_count_value = snapshot.get("playlist_count")
        if entry_id_value is None:
            entry_id_value = (
                snapshot.get("playlist_current_entry_id")
                or snapshot.get("playlist_entry_id")
                or snapshot.get("current_entry_id")
            )

        if info_dict:
            if playlist_index_value is None:
                playlist_index_value = info_dict.get("playlist_index")
            if playlist_count_value is None:
                for key in ("n_entries", "playlist_count", "playlist_length"):
                    candidate = info_dict.get(key)
                    if candidate is not None:
                        playlist_count_value = candidate
                        break
            if entry_id_value is None:
                for key in (
                    "playlist_current_entry_id",
                    "playlist_entry_id",
                    "id",
                    "original_url",
                    "url",
                    "webpage_url",
                ):
                    candidate = info_dict.get(key)
                    if candidate is not None:
                        entry_id_value = candidate
                        break

        if info_model is not None:
            if playlist_index_value is None and info_model.playlist_index is not None:
                playlist_index_value = info_model.playlist_index
            if playlist_count_value is None and info_model.entry_count is not None:
                playlist_count_value = info_model.entry_count
            if entry_id_value is None and info_model.id:
                entry_id_value = info_model.id

        force_playlist = bool(info_model and info_model.is_playlist)

        fields: DownloadJobProgressPayload = {}
        playlist_index = to_int(playlist_index_value)
        playlist_count = to_int(playlist_count_value)

        if playlist_count is not None:
            if playlist_count <= 1 and not force_playlist:
                playlist_count = None
        if playlist_index is not None:
            if playlist_index <= 0 or (playlist_index <= 1 and not force_playlist):
                playlist_index = None

        if playlist_count is not None:
            fields["playlist_count"] = playlist_count
        if playlist_index is not None:
            fields["playlist_index"] = playlist_index

        emit_entry_id = force_playlist or bool(fields)

        if emit_entry_id and entry_id_value is not None:
            if isinstance(entry_id_value, str):
                entry_id_text = entry_id_value.strip() or None
            else:
                entry_id_text = str(entry_id_value).strip() or None
            if entry_id_text:
                fields["playlist_current_entry_id"] = entry_id_text

        return fields

    def _update_playlist_progress(
        self,
        job: DownloadJob,
        incoming: DownloadJobProgressPayload,
        merged: DownloadJobProgressPayload,
        previous_state: DownloadJobProgressPayload,
    ) -> Tuple[
        Optional[PlaylistProgressEventPayload],
        Optional[PlaylistSnapshotPayload],
        List[Tuple[int, PlaylistEntryEventPayload]],
        bool,
    ]:
        manager = self._progress_manager()
        selected_indices = self._resolve_selected_playlist_indices(job)
        if selected_indices:
            job.playlist_completed_indices.intersection_update(selected_indices)

        entry_events: List[Tuple[int, PlaylistEntryEventPayload]] = []
        reopened_index: Optional[int] = None
        metadata_changed = False

        previous_active_index = to_int(
            previous_state.get("playlist_current_index")
            or previous_state.get("playlist_index")
        )
        if previous_active_index is not None and previous_active_index <= 0:
            previous_active_index = None

        previous_entry_id_raw = previous_state.get("playlist_current_entry_id")
        if isinstance(previous_entry_id_raw, str):
            previous_entry_id = previous_entry_id_raw.strip() or None
        elif previous_entry_id_raw is not None:
            previous_entry_id = str(previous_entry_id_raw).strip() or None
        else:
            previous_entry_id = None

        playlist_count_value = incoming.get("playlist_count")
        if playlist_count_value is None:
            playlist_count_value = merged.get("playlist_count")
        playlist_count = to_int(playlist_count_value)
        selected_total = len(selected_indices) if selected_indices else None
        effective_total = None
        if selected_total:
            effective_total = selected_total
        elif playlist_count is not None and playlist_count > 0:
            effective_total = playlist_count

        if effective_total is not None:
            merged["playlist_count"] = effective_total
            job.playlist_total_items = effective_total
        elif "playlist_count" in merged:
            merged.pop("playlist_count", None)

        stored_playlist_index = to_int(
            merged.get("playlist_current_index") or merged.get("playlist_index")
        )
        had_non_positive_index = (
            stored_playlist_index is not None and stored_playlist_index <= 0
        )

        existing_playlist_index = to_int(
            merged.get("playlist_current_index")
            or merged.get("playlist_index")
            or previous_state.get("playlist_current_index")
            or previous_state.get("playlist_index")
        )
        if existing_playlist_index is not None and existing_playlist_index <= 0:
            existing_playlist_index = None
        entry_id_candidates: Tuple[object | None, ...] = (
            incoming.get("playlist_current_entry_id"),
            incoming.get("playlist_entry_id"),
            incoming.get("current_entry_id"),
        )
        event_entry_id: Optional[str] = None
        explicit_entry_id_clear = False
        for candidate in entry_id_candidates:
            if candidate is None:
                continue
            if isinstance(candidate, str):
                trimmed_candidate = candidate.strip()
                if trimmed_candidate:
                    event_entry_id = trimmed_candidate
                    break
                explicit_entry_id_clear = True
            elif isinstance(candidate, (bytes, int, float)):
                candidate_text = (
                    candidate.decode(errors="ignore").strip()
                    if isinstance(candidate, bytes)
                    else str(candidate).strip()
                )
                if candidate_text:
                    event_entry_id = candidate_text
                    break
        incoming_entry_id: Optional[str] = event_entry_id
        if incoming_entry_id is None and not explicit_entry_id_clear:
            existing_entry_candidate = merged.get(
                "playlist_current_entry_id"
            ) or previous_state.get("playlist_current_entry_id")
            if isinstance(existing_entry_candidate, str):
                incoming_entry_id = existing_entry_candidate.strip() or None
            elif existing_entry_candidate is not None:
                incoming_entry_id = str(existing_entry_candidate).strip() or None
        raw_playlist_index = incoming.get("playlist_index")
        parsed_playlist_index: Optional[int] = None
        if raw_playlist_index is not None:
            parsed_playlist_index = to_int(raw_playlist_index)
        explicit_index_clear = False
        if raw_playlist_index is not None:
            if parsed_playlist_index == 0:
                explicit_index_clear = True
            elif parsed_playlist_index is None and isinstance(raw_playlist_index, str):
                explicit_index_clear = not raw_playlist_index.strip()
        playlist_index = parsed_playlist_index
        if playlist_index is None or playlist_index <= 0:
            if explicit_index_clear:
                playlist_index = None
            else:
                playlist_index = existing_playlist_index
        if (
            (playlist_index is None or playlist_index <= 0)
            and event_entry_id
            and not explicit_index_clear
        ):
            resolved_by_entry = manager.resolve_playlist_index_from_entry_id(
                job, event_entry_id
            )
            if resolved_by_entry is not None and resolved_by_entry > 0:
                playlist_index = resolved_by_entry
        if (
            selected_indices
            and playlist_index is not None
            and playlist_index not in selected_indices
        ):
            playlist_index = None
            explicit_index_clear = True
            incoming_entry_id = None
            explicit_entry_id_clear = True
        if playlist_index is not None and playlist_index > 0:
            merged["playlist_index"] = playlist_index
            merged["playlist_current_index"] = playlist_index
        elif explicit_index_clear or had_non_positive_index:
            merged.pop("playlist_index", None)
            merged.pop("playlist_current_index", None)

        current_entry_id: Optional[str] = None
        if incoming_entry_id:
            current_entry_id = incoming_entry_id
        elif explicit_entry_id_clear:
            current_entry_id = None
        else:
            existing_entry_raw = merged.get("playlist_current_entry_id")
            if isinstance(existing_entry_raw, str):
                current_entry_id = existing_entry_raw.strip() or None
        if (
            current_entry_id is None
            and playlist_index is not None
            and playlist_index > 0
        ):
            resolved_entry_id = manager.resolve_playlist_entry_id(job, playlist_index)
            if resolved_entry_id:
                current_entry_id = resolved_entry_id
        if current_entry_id:
            merged["playlist_current_entry_id"] = current_entry_id
        else:
            merged.pop("playlist_current_entry_id", None)

        status_text = str(incoming.get("status") or merged.get("status") or "").lower()
        stage_hint = incoming.get("stage")
        if stage_hint is None and merged.get("stage") is not None:
            stage_hint = merged.get("stage")
        stage_text = str(stage_hint or "")
        stage_upper = stage_text.upper()
        stage_status_hint = status_text

        if (
            playlist_index is not None
            and playlist_index > 0
            and playlist_index in job.playlist_completed_indices
            and stage_upper != DownloadStage.COMPLETED.value
        ):
            job.playlist_completed_indices.discard(playlist_index)
            reopened_index = playlist_index

        failure_statuses = {
            "error",
            "stopped",
            "stopping",
            "aborted",
            JobStatus.FAILED.value,
            "canceled",
            JobStatus.CANCELLED.value,
        }
        should_mark_completed = (
            stage_upper == DownloadStage.COMPLETED.value
            and stage_status_hint not in failure_statuses
        )
        previous_failure_status = str(previous_state.get("status") or "").lower()
        previous_was_failure = previous_failure_status in failure_statuses

        newly_completed_index: Optional[int] = None
        mark_completion = (
            should_mark_completed
            and playlist_index is not None
            and playlist_index > 0
            and (not selected_indices or playlist_index in selected_indices)
        )
        if mark_completion:
            index_value = cast(int, playlist_index)
            is_new_completion = index_value not in job.playlist_completed_indices
            job.playlist_completed_indices.add(index_value)
            if is_new_completion:
                newly_completed_index = index_value
                merged["playlist_newly_completed_index"] = index_value
                merged["playlist_index"] = 0
                merged["playlist_current_index"] = 0
                merged.pop("playlist_current_entry_id", None)
                playlist_index = 0
                current_entry_id = None
            else:
                merged.pop("playlist_newly_completed_index", None)
        else:
            merged.pop("playlist_newly_completed_index", None)
            if (
                should_mark_completed
                and playlist_index is not None
                and playlist_index > 0
                and selected_indices
                and playlist_index not in selected_indices
            ):
                job.playlist_completed_indices.discard(playlist_index)

        current_active_index = (
            playlist_index
            if playlist_index is not None and playlist_index > 0
            else None
        )

        index_changed = previous_active_index != current_active_index
        auto_completed_index: Optional[int] = None
        failure_entry_index: Optional[int] = None
        if (
            previous_active_index is not None
            and previous_active_index > 0
            and index_changed
        ):
            if previous_was_failure:
                failure_entry_index = previous_active_index
            elif not selected_indices or previous_active_index in selected_indices:
                if previous_active_index not in job.playlist_completed_indices:
                    job.playlist_completed_indices.add(previous_active_index)
                    auto_completed_index = previous_active_index

        total_items: Optional[int] = job.playlist_total_items
        if selected_total:
            total_items = selected_total
        if total_items is not None and total_items > 0:
            merged["playlist_total_items"] = total_items
        else:
            fallback_total = to_int(previous_state.get("playlist_total_items"))
            if fallback_total is None:
                fallback_total = to_int(merged.get("playlist_count"))
            if fallback_total is not None and fallback_total > 0:
                total_items = fallback_total
                job.playlist_total_items = fallback_total
                merged["playlist_total_items"] = fallback_total
            else:
                merged.pop("playlist_total_items", None)

        completed_set = {index for index in job.playlist_completed_indices if index > 0}
        if selected_indices:
            completed_set.intersection_update(selected_indices)
            job.playlist_completed_indices.intersection_update(selected_indices)
        completed_count = len(completed_set)
        if completed_count > 0:
            merged["playlist_completed_items"] = completed_count
        else:
            merged.pop("playlist_completed_items", None)

        if total_items is not None and total_items > 0:
            remaining = max(total_items - completed_count, 0)
            merged["playlist_pending_items"] = remaining
            percent_complete = completed_count / total_items if total_items else 0.0
            merged["playlist_percent"] = round(percent_complete * 100, 2)
        else:
            remaining = None
            percent_complete = None
            merged.pop("playlist_pending_items", None)
            merged.pop("playlist_percent", None)

        previous_total = to_int(previous_state.get("playlist_total_items"))
        previous_completed = to_int(previous_state.get("playlist_completed_items"))
        previous_percent = to_float(previous_state.get("playlist_percent"))

        total_changed = previous_total != (
            total_items if total_items and total_items > 0 else None
        )
        completed_changed = previous_completed != (
            completed_count if completed_count > 0 else None
        )
        percent_changed = False
        if percent_complete is not None:
            current_percent_value = round(percent_complete * 100, 2)
            if (
                previous_percent is None
                or abs(current_percent_value - previous_percent) > 0.001
            ):
                percent_changed = True
        elif previous_percent is not None:
            percent_changed = True

        entry_id_changed = previous_entry_id != current_entry_id

        entry_details_changed = False
        if current_active_index is not None or previous_active_index is not None:
            detail_keys = (
                "percent",
                "stage_percent",
                "stage",
                "stage_name",
                "status",
                "message",
                "downloaded_bytes",
                "total_bytes",
                "speed",
                "eta",
                "elapsed",
            )
            for key in detail_keys:
                if merged.get(key) != previous_state.get(key):
                    entry_details_changed = True
                    break

        has_entry_event = any(
            value is not None
            for value in (
                newly_completed_index,
                reopened_index,
                auto_completed_index,
                failure_entry_index,
            )
        )

        if not (
            has_entry_event
            or index_changed
            or total_changed
            or completed_changed
            or percent_changed
            or entry_id_changed
            or entry_details_changed
        ):
            return None, None, [], metadata_changed

        summary: PlaylistProgressEventPayload = {
            "job_id": job.job_id,
            "status": job.status,
            "playlist_completed_items": completed_count,
            "playlist_completed_indices": [
                int(index) for index in sorted(completed_set)
            ],
        }
        if total_items is not None and total_items > 0:
            summary["playlist_total_items"] = total_items
        if playlist_count is not None and playlist_count > 0:
            summary["playlist_count"] = playlist_count
        if remaining is not None:
            summary["playlist_pending_items"] = remaining
        if percent_complete is not None:
            summary["playlist_percent"] = round(percent_complete * 100, 2)
        if playlist_index is not None:
            summary["playlist_current_index"] = playlist_index
        if current_entry_id:
            summary["playlist_current_entry_id"] = current_entry_id
        if newly_completed_index is not None:
            summary["playlist_newly_completed_index"] = newly_completed_index
        elif auto_completed_index is not None:
            summary["playlist_newly_completed_index"] = auto_completed_index

        def _resolve_entry_id_for(
            index: Optional[int], fallback: Optional[str]
        ) -> Optional[str]:
            if index is None or index <= 0:
                return None
            if fallback:
                return fallback
            return manager.resolve_playlist_entry_id(job, index)

        if failure_entry_index is not None:
            failure_payload = self._compose_playlist_entry_event_payload(
                job,
                index=failure_entry_index,
                state=JobStatus.FAILED.value,
                entry_id=_resolve_entry_id_for(failure_entry_index, previous_entry_id),
                sources=(previous_state, merged, incoming),
                overrides={
                    "reason": "failure",
                    "status": JobStatus.FAILED.value,
                    "stage": "error",
                    "stage_name": "error",
                },
            )
            entry_events.append((failure_entry_index, failure_payload))
            if self._store_playlist_entry_snapshot(
                job,
                index=failure_entry_index,
                payload=failure_payload,
            ):
                metadata_changed = True
            self._record_playlist_entry_failure(
                job,
                index=failure_entry_index,
                payload=failure_payload,
            )

        if (
            auto_completed_index is not None
            and auto_completed_index != newly_completed_index
        ):
            auto_payload = self._compose_playlist_entry_event_payload(
                job,
                index=auto_completed_index,
                state=JobStatus.COMPLETED.value,
                entry_id=_resolve_entry_id_for(auto_completed_index, previous_entry_id),
                sources=(previous_state, merged, incoming),
                overrides={
                    "reason": "progress_transition",
                    "status": JobStatus.COMPLETED.value,
                    "stage": DownloadStage.COMPLETED.value,
                    "stage_name": DownloadStage.COMPLETED.value,
                    "percent": 100.0,
                    "stage_percent": 100.0,
                },
            )
            entry_events.append((auto_completed_index, auto_payload))
            if self._store_playlist_entry_snapshot(
                job,
                index=auto_completed_index,
                payload=auto_payload,
            ):
                metadata_changed = True
            pending_retry = auto_completed_index in job.playlist_pending_indices
            self._clear_playlist_entry_failure(
                job,
                auto_completed_index,
                preserve_record=not pending_retry,
            )

        if newly_completed_index is not None:
            completed_payload = self._compose_playlist_entry_event_payload(
                job,
                index=newly_completed_index,
                state=JobStatus.COMPLETED.value,
                entry_id=_resolve_entry_id_for(newly_completed_index, current_entry_id),
                sources=(incoming, merged, previous_state),
                overrides={
                    "reason": "post_hook",
                    "status": JobStatus.COMPLETED.value,
                    "stage": DownloadStage.COMPLETED.value,
                    "stage_name": DownloadStage.COMPLETED.value,
                    "percent": 100.0,
                    "stage_percent": 100.0,
                },
            )
            entry_events.append((newly_completed_index, completed_payload))
            if self._store_playlist_entry_snapshot(
                job,
                index=newly_completed_index,
                payload=completed_payload,
            ):
                metadata_changed = True
            pending_retry = newly_completed_index in job.playlist_pending_indices
            self._clear_playlist_entry_failure(
                job,
                newly_completed_index,
                preserve_record=not pending_retry,
            )

        if reopened_index is not None:
            self._clear_playlist_entry_failure(
                job,
                reopened_index,
                preserve_record=False,
            )
            reopened_payload = self._compose_playlist_entry_event_payload(
                job,
                index=reopened_index,
                state="reopened",
                entry_id=_resolve_entry_id_for(
                    reopened_index,
                    current_entry_id
                    if current_active_index == reopened_index
                    else previous_entry_id,
                ),
                sources=(merged, incoming, previous_state),
                overrides={"reason": "reopened"},
            )
            entry_events.append((reopened_index, reopened_payload))
            if self._store_playlist_entry_snapshot(
                job,
                index=reopened_index,
                payload=reopened_payload,
            ):
                metadata_changed = True

        if current_active_index is not None and (
            entry_details_changed
            or index_changed
            or reopened_index == current_active_index
        ):
            reason = "entry_progress"
            if index_changed:
                reason = "entry_switched"
            elif reopened_index == current_active_index:
                reason = "reopened"
            active_payload = self._compose_playlist_entry_event_payload(
                job,
                index=current_active_index,
                state="active",
                entry_id=_resolve_entry_id_for(current_active_index, current_entry_id),
                sources=(merged, incoming, previous_state),
                overrides={"reason": reason},
            )
            entry_events.append((current_active_index, active_payload))
            if self._store_playlist_entry_snapshot(
                job,
                index=current_active_index,
                payload=active_payload,
            ):
                metadata_changed = True

        snapshot = manager.build_playlist_snapshot(
            job.job_id,
            include_entries=True,
            include_entry_progress=True,
        )
        return summary, snapshot, entry_events, metadata_changed

    @staticmethod
    def _register_generated_paths(job: DownloadJob, progress: ProgressDataView) -> None:
        generated_raw = getattr(job, "generated_files", None)
        partial_raw = getattr(job, "partial_files", None)
        if not isinstance(generated_raw, set) or not isinstance(partial_raw, set):
            return
        generated = cast(Set[str], generated_raw)
        partials = cast(Set[str], partial_raw)

        base_dirs: Set[Path] = set()

        def _collect_base(raw: object, *, treat_as_file: bool = False) -> None:
            if not isinstance(raw, str):
                return
            trimmed = raw.strip()
            if not trimmed:
                return
            try:
                path = Path(trimmed)
            except Exception:
                return
            if path.is_absolute():
                target = path.parent if treat_as_file else path
                base_dirs.add(target)

        def _normalize_candidate(raw: str) -> str:
            try:
                candidate = Path(raw)
            except Exception:
                return raw
            if candidate.is_absolute():
                return str(candidate)
            for base in base_dirs:
                try:
                    combined = base / candidate
                    return str(combined.resolve())
                except Exception:
                    combined = base / candidate
                    return str(combined)
            return raw

        def _looks_like_partial(path: str) -> bool:
            lowered = path.lower()
            return lowered.endswith((".part", ".ytdl", ".temp", ".tmp"))

        def _target_for(path: str, preferred: Optional[str]) -> Set[str]:
            if preferred == "partial":
                return partials
            if preferred == "final":
                return generated
            return partials if _looks_like_partial(path) else generated

        def _register_partial_variant(value: str) -> None:
            normalized_value = _normalize_candidate(value)
            trimmed = normalized_value.strip()
            if not trimmed:
                return
            if _looks_like_partial(trimmed):
                partials.add(trimmed)
            else:
                partials.add(f"{trimmed}.part")

        def _add_raw_path(
            value: str,
            *,
            include_part: bool = False,
            preferred: Optional[str] = None,
        ) -> None:
            normalized = _normalize_candidate(value)
            target = _target_for(normalized, preferred)
            target.add(normalized)
            if normalized != value:
                target = _target_for(value, preferred)
                target.add(value)
            if include_part:
                _register_partial_variant(normalized)
                if normalized != value:
                    _register_partial_variant(value)

        def _add_path(
            raw: object,
            *,
            include_part: bool = False,
            preferred: Optional[str] = None,
        ) -> None:
            if not isinstance(raw, str):
                return
            trimmed = raw.strip()
            if not trimmed:
                return
            _add_raw_path(trimmed, include_part=include_part, preferred=preferred)

        def _add_paths(
            values: object,
            *,
            include_part: bool = False,
            preferred: Optional[str] = None,
        ) -> None:
            if isinstance(values, Iterable) and not isinstance(values, (str, bytes)):
                values_iter = cast(Iterable[object], values)
                for item in values_iter:
                    _add_path(
                        item,
                        include_part=include_part,
                        preferred=preferred,
                    )
            else:
                _add_path(values, include_part=include_part, preferred=preferred)

        _collect_base(progress.get("directory"))
        _collect_base(progress.get("filename"), treat_as_file=True)
        _collect_base(progress.get("tmpfilename"), treat_as_file=True)

        options_paths = job.options.get("paths")
        if isinstance(options_paths, dict):
            for value in options_paths.values():
                _collect_base(value)

        _add_path(progress.get("filename"), include_part=True, preferred="final")
        _add_path(progress.get("tmpfilename"), preferred="partial")
        _add_path(progress.get("filepath"), include_part=True, preferred="final")
        _add_path(progress.get("target"), include_part=True, preferred="final")
        _add_path(progress.get("directory"))
        _add_path(progress.get("thumbnail"), preferred="final")

        info_dict = progress.get("info_dict")
        if isinstance(info_dict, dict):
            ProgressMixin._register_info_dict_paths(
                cast(YtDlpInfoResult, info_dict),
                add_path=_add_path,
                add_paths=_add_paths,
                collect_base=_collect_base,
            )

    @staticmethod
    def _register_info_dict_paths(
        info_dict: YtDlpInfoResult,
        *,
        add_path: Callable[..., None],
        add_paths: Callable[..., None],
        collect_base: Callable[..., None],
    ) -> None:
        collect_base(info_dict.get("filepath"), treat_as_file=True)
        collect_base(info_dict.get("_filename"), treat_as_file=True)
        collect_base(info_dict.get("filename"), treat_as_file=True)
        collect_base(info_dict.get("_download_dir"))
        collect_base(info_dict.get("__destdir"))
        collect_base(info_dict.get("__finaldir"))
        add_path(info_dict.get("filepath"), include_part=True, preferred="final")
        add_path(info_dict.get("_filename"), include_part=True, preferred="final")
        add_path(info_dict.get("filename"), include_part=True, preferred="final")
        add_path(info_dict.get("thumbnail"), preferred="final")

        downloads_raw = info_dict.get("requested_downloads")
        downloads_seq = ProgressMixin._coerce_object_sequence(downloads_raw)
        if downloads_seq:
            for entry in ProgressMixin._iter_json_mappings(downloads_seq):
                collect_base(entry.get("filepath"), treat_as_file=True)
                collect_base(entry.get("filename"), treat_as_file=True)
                collect_base(entry.get("tmpfilename"), treat_as_file=True)
                add_path(
                    entry.get("filepath"),
                    include_part=True,
                    preferred="final",
                )
                add_path(
                    entry.get("filename"),
                    include_part=True,
                    preferred="final",
                )
                add_path(entry.get("tmpfilename"), preferred="partial")

        subtitles_raw = info_dict.get("requested_subtitles")
        if isinstance(subtitles_raw, dict):
            subtitles_map = cast(Mapping[str, object], subtitles_raw)
            for items in subtitles_map.values():
                items_seq = ProgressMixin._coerce_object_sequence(items)
                if not items_seq:
                    continue
                for entry in ProgressMixin._iter_json_mappings(items_seq):
                    collect_base(entry.get("filepath"), treat_as_file=True)
                    collect_base(entry.get("filename"), treat_as_file=True)
                    add_path(
                        entry.get("filepath"),
                        include_part=True,
                        preferred="final",
                    )
                    add_path(
                        entry.get("filename"),
                        include_part=True,
                        preferred="final",
                    )

        thumbnails_raw = info_dict.get("thumbnails")
        thumbnails_seq = ProgressMixin._coerce_object_sequence(thumbnails_raw)
        if thumbnails_seq:
            for entry in ProgressMixin._iter_json_mappings(thumbnails_seq):
                collect_base(entry.get("filepath"), treat_as_file=True)
                collect_base(entry.get("filename"), treat_as_file=True)
                add_path(entry.get("filepath"), preferred="final")
                add_path(entry.get("filename"), preferred="final")

        attachments_raw = info_dict.get("__files_to_move")
        if isinstance(attachments_raw, dict):
            attachments_map = cast(Mapping[object, JSONValue], attachments_raw)
            for src_value, dest_value in attachments_map.items():
                src_path = src_value if isinstance(src_value, str) else None
                dest_path = dest_value if isinstance(dest_value, str) else None
                if not src_path or not dest_path:
                    continue
                collect_base(src_path, treat_as_file=True)
                collect_base(dest_path, treat_as_file=True)
                add_paths(
                    [src_path, dest_path],
                    include_part=True,
                    preferred="final",
                )

    @staticmethod
    def _coerce_object_sequence(value: object) -> Optional[Sequence[object]]:
        if isinstance(value, Sequence) and not isinstance(
            value, (str, bytes, bytearray)
        ):
            return cast(Sequence[object], value)
        return None

    @staticmethod
    def _iter_json_mappings(
        values: Sequence[object],
    ) -> Iterable[Mapping[str, JSONValue]]:
        for entry in values:
            if isinstance(entry, Mapping):
                yield cast(Mapping[str, JSONValue], entry)
