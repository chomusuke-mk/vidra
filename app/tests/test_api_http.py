from __future__ import annotations

import asyncio
import json
import os
import tempfile
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import (
    Any,
    AsyncIterator,
    Callable,
    Dict,
    Iterable,
    List,
    Mapping,
    MutableMapping,
    Optional,
    Protocol,
    Tuple,
    cast,
)
from unittest import TestCase
from urllib.parse import urlencode

from starlette.applications import Starlette
from starlette.testclient import TestClient
from starlette.types import ASGIApp
from src.api.http import register_http_routes  # noqa: E402
from src.api.websockets import register_websocket_routes  # noqa: E402
from src.config import (  # noqa: E402
    ACTIVE_STATUSES,
    JobStatus,
    PAUSE_ELIGIBLE_STATUSES,
    RESUMABLE_STATUSES,
    TERMINAL_STATUSES,
    SocketEvent,
    SocketRoom,
)
from src.download.manager import DownloadManager  # noqa: E402
from src.models.api.errors import ErrorCode  # noqa: E402
from src.models.download.manager import CreateJobRequest  # noqa: E402
from src.models.socket import ProgressPayload  # noqa: E402
from src.socket_manager import SocketManager  # noqa: E402

SERVER_TOKEN = os.getenv("VIDRA_SERVER_TOKEN")

NCS_VIDEO_URL = "https://www.youtube.com/watch?v=jK2aIUmmdP4"
NCS_PLAYLIST_URL = (
    "https://www.youtube.com/watch?v=jK2aIUmmdP4&list=RDjK2aIUmmdP4&start_radio=1"
)


class FakeJob:
    def __init__(
        self,
        job_id: str,
        urls: List[str],
        metadata: Optional[Dict[str, Any]],
        *,
        output_dir: Path,
    ) -> None:
        self.job_id = job_id
        self.status = JobStatus.QUEUED.value
        self.urls = urls
        self.metadata = metadata or {}
        self.created_at = datetime.now(timezone.utc).replace(tzinfo=None)
        self.progress: Dict[str, Any] = {"stage": "starting"}
        self.logs: List[Dict[str, Any]] = [
            {
                "timestamp": self.created_at.isoformat() + "Z",
                "level": "info",
                "message": "job created",
            }
        ]
        self.logs_version: int = 1
        self.options: Dict[str, Any] = {
            "format": "mp4",
            "paths": {"output": str(output_dir)},
        }
        self.options_version: int = 1
        self.output_dir = output_dir
        self.generated_files: List[str] = []
        self.partial_files: List[str] = []
        self.main_file: Optional[str] = None
        self.selection_required = False
        self.playlist_entries: List[Dict[str, Any]] = []
        self.selected_indices: List[int] = []
        self.entry_progress: Dict[int, Dict[str, Any]] = {}
        self.error: Optional[str] = None


class PlaylistEntryEmitter(Protocol):
    def __call__(
        self,
        job: FakeJob,
        *,
        entry_index: int,
        status: str,
        stage: str,
        url: str,
        filename: Optional[str] = None,
    ) -> None: ...


class RecordingSocketManager(SocketManager):
    """Simple socket manager double that records emitted events."""

    def __init__(self) -> None:
        super().__init__()
        self.events: List[Dict[str, Any]] = []

    def emit(
        self,
        event: str,
        payload: Dict[str, Any],
        *,
        room: Optional[str] = None,
    ) -> None:
        self.events.append({"event": event, "payload": payload, "room": room})

    # Compatibility no-ops -------------------------------------------------
    def bind_loop(self, *_: Any, **__: Any) -> None:  # pragma: no cover - test shim
        return None

    def register_overview(self, *_: Any, **__: Any) -> None:  # pragma: no cover
        return None

    def unregister_overview(self, *_: Any, **__: Any) -> None:  # pragma: no cover
        return None

    def register_job(self, *_: Any, **__: Any) -> None:  # pragma: no cover
        return None

    def unregister_job(self, *_: Any, **__: Any) -> None:  # pragma: no cover
        return None

    async def aclose(self) -> None:  # pragma: no cover - async compatibility hook
        self.events.clear()

    # Test helpers --------------------------------------------------------
    def select(
        self, *, event: Optional[str] = None, room: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        matches: List[Dict[str, Any]] = []
        for record in self.events:
            if event and record["event"] != event:
                continue
            if room and record["room"] != room:
                continue
            matches.append(record)
        return matches

    def drain(
        self, *, event: Optional[str] = None, room: Optional[str] = None
    ) -> List[Dict[str, Any]]:
        matches = self.select(event=event, room=room)
        if not matches:
            return []
        match_ids = {id(record) for record in matches}
        self.events = [record for record in self.events if id(record) not in match_ids]
        return matches

    def clear(self) -> None:
        self.events.clear()

    def has_subscribers(self, room: Optional[str] = None) -> bool:
        return True

    def subscriber_count(self, room: Optional[str] = None) -> int:
        return 1


class FakeDownloadManager:
    def __init__(
        self, *, download_dir: Path, socket_manager: Optional[SocketManager] = None
    ) -> None:
        self.jobs: Dict[str, FakeJob] = {}
        self.download_dir = download_dir
        self.download_dir.mkdir(parents=True, exist_ok=True)
        self.socket_manager = socket_manager

    def _emit_job_update(self, job: FakeJob, *, reason: str = "test_update") -> None:
        if not self.socket_manager:
            return
        payload = {
            "job_id": job.job_id,
            "status": job.status,
            "reason": reason,
            "files": list(job.generated_files),
            "timestamp": self._now(),
        }
        self.socket_manager.emit(
            SocketEvent.UPDATE.value,
            payload,
            room=SocketRoom.for_job(job.job_id),
        )

    def _emit_playlist_snapshot(self, job: FakeJob) -> None:
        if not self.socket_manager:
            return
        payload = {
            "job_id": job.job_id,
            "playlist": {
                "entries": job.playlist_entries,
                "requires_selection": job.selection_required,
                "selected_indices": job.selected_indices,
            },
            "timestamp": self._now(),
        }
        self.socket_manager.emit(
            SocketEvent.PLAYLIST_SNAPSHOT.value,
            payload,
            room=SocketRoom.for_job(job.job_id),
        )

    @staticmethod
    def _contains_playlist(urls: List[str], metadata: Optional[Dict[str, Any]]) -> bool:
        if metadata and metadata.get("requires_playlist_selection"):
            return True
        return any("list=" in url for url in urls)

    @staticmethod
    def _build_playlist_entries(urls: List[str]) -> List[Dict[str, Any]]:
        base_url = urls[0] if urls else NCS_PLAYLIST_URL
        entries: List[Dict[str, Any]] = []
        for index in range(1, 4):
            entries.append(
                {
                    "index": index,
                    "title": f"NCS Playlist Track {index}",
                    "url": f"{base_url}&index={index}",
                    "duration": 180 + index,
                }
            )
        return entries

    def _write_download_assets(self, job: FakeJob) -> None:
        timestamp = self._now()
        if job.playlist_entries:
            indexed_urls: List[Tuple[int, str]] = []
            for fallback_index, entry in enumerate(job.playlist_entries, start=1):
                entry_index = self._to_int(entry.get("index")) or fallback_index
                entry_url = str(entry.get("url") or job.urls[0])
                indexed_urls.append((entry_index, entry_url))
        else:
            indexed_urls = list(enumerate(job.urls, start=1))
        total_entries = len(indexed_urls) or 1
        for index, url in indexed_urls:
            self._emit_playlist_entry_progress(
                job,
                entry_index=index,
                status=JobStatus.RUNNING.value,
                stage="starting",
                url=url,
            )
            filename = job.output_dir / f"{job.job_id}-{index}.txt"
            payload = f"Simulated download for {url}\nSaved at {timestamp}\n"
            filename.write_text(payload, encoding="utf-8")
            job.generated_files.append(str(filename))
            job.partial_files.append(f"{filename}.part")
            job.logs.append(
                {
                    "timestamp": timestamp,
                    "level": "info",
                    "message": f"Archivo generado: {filename.name}",
                }
            )
            job.logs_version += 1
            self._emit_playlist_entry_progress(
                job,
                entry_index=index,
                status=JobStatus.COMPLETED.value,
                stage="completed",
                url=url,
                filename=filename.name,
            )
            self._emit_playlist_progress(
                job,
                completed_entries=index,
                total_entries=total_entries,
                latest_entry=index,
            )

        if job.generated_files:
            job.main_file = job.generated_files[-1]

    def overview_snapshot(self) -> Dict[str, Any]:
        total = len(self.jobs)
        queued = sum(
            1 for job in self.jobs.values() if job.status == JobStatus.QUEUED.value
        )
        active = sum(1 for job in self.jobs.values() if job.status in ACTIVE_STATUSES)
        return {"summary": {"total": total, "queued": queued, "active": active}}

    def create_job(self, request: CreateJobRequest) -> FakeJob:
        normalized_urls = [str(url) for url in request.urls if str(url)]
        normalized_options = dict(request.options or {})
        metadata_payload = dict(request.metadata or {})
        output_dir = self._resolve_output_dir(normalized_options.get("output_dir"))
        output_dir.mkdir(parents=True, exist_ok=True)
        job_id = f"job-{len(self.jobs) + 1}"
        job = FakeJob(job_id, normalized_urls, metadata_payload, output_dir=output_dir)
        playlist_job = self._contains_playlist(normalized_urls, job.metadata)
        if playlist_job:
            job.selection_required = True
            job.playlist_entries = self._build_playlist_entries(normalized_urls)
            self._emit_playlist_snapshot(job)
        self.jobs[job_id] = job
        self._write_download_assets(job)
        if normalized_options.get("defer_complete"):
            job.status = JobStatus.RUNNING.value
        else:
            job.status = JobStatus.COMPLETED.value
        self._emit_job_update(job, reason="created")
        return job

    def _resolve_output_dir(self, candidate: Any) -> Path:
        if isinstance(candidate, Path):
            return candidate
        if isinstance(candidate, str):
            text = candidate.strip()
            if text:
                return Path(text)
        return self.download_dir

    def list_jobs(
        self, status: Optional[str] = None, owner: Optional[str] = None
    ) -> List[FakeJob]:
        jobs = list(self.jobs.values())
        if status:
            jobs = [job for job in jobs if job.status == status]
        return jobs

    def serialize_job(self, job: FakeJob, *, detail: bool = False) -> Dict[str, Any]:
        payload: Dict[str, Any] = {
            "job_id": job.job_id,
            "status": job.status,
            "created_at": job.created_at.isoformat() + "Z",
            "urls": job.urls,
            "files": job.generated_files,
            "generated_files": list(job.generated_files),
            "partial_files": list(job.partial_files),
            "main_file": job.main_file,
        }
        if detail:
            payload["metadata"] = job.metadata
            payload["selection_required"] = job.selection_required
            payload["selected_indices"] = job.selected_indices
        return payload

    def get_job(self, job_id: str) -> Optional[FakeJob]:
        return self.jobs.get(job_id)

    def cancel_job(self, job_id: str) -> Dict[str, Any]:
        job = self.jobs.get(job_id)
        if not job:
            return {"job_id": job_id, "status": "not_found"}
        if job.status in TERMINAL_STATUSES:
            return {"job_id": job.job_id, "status": job.status}
        job.status = JobStatus.CANCELLED.value
        self._emit_job_update(job, reason="cancelled")
        return {"job_id": job.job_id, "status": job.status}

    def cancel_jobs(self, job_ids: List[str]) -> List[Dict[str, Any]]:
        return [self.cancel_job(job_id) for job_id in job_ids]

    def cancel_all(self, owner: Optional[str] = None) -> List[Dict[str, Any]]:
        return [self.cancel_job(job_id) for job_id in list(self.jobs)]

    def pause_job(self, job_id: str) -> Dict[str, Any]:
        job = self.jobs.get(job_id)
        if not job:
            return {"job_id": job_id, "status": "not_found"}
        if job.status not in PAUSE_ELIGIBLE_STATUSES:
            return {"job_id": job.job_id, "status": job.status}
        job.status = JobStatus.PAUSED.value
        self._emit_job_update(job, reason="paused")
        return {"job_id": job.job_id, "status": job.status}

    def resume_job(self, job_id: str) -> Dict[str, Any]:
        job = self.jobs.get(job_id)
        if not job:
            return {"job_id": job_id, "status": "not_found"}
        if job.status not in RESUMABLE_STATUSES:
            return {"job_id": job.job_id, "status": job.status}
        job.status = JobStatus.RUNNING.value
        self._emit_job_update(job, reason="resumed")
        return {"job_id": job.job_id, "status": job.status}

    def retry_job(self, job_id: str) -> Dict[str, Any]:
        job = self.jobs.get(job_id)
        if not job:
            return {"job_id": job_id, "status": "not_found"}
        if job.status not in {JobStatus.FAILED.value, JobStatus.CANCELLED.value}:
            return {"job_id": job.job_id, "status": job.status}
        job.status = JobStatus.RUNNING.value
        self._emit_job_update(job, reason="retry")
        return {"job_id": job.job_id, "status": job.status}

    def delete_job(self, job_id: str) -> Dict[str, Any]:
        job = self.jobs.get(job_id)
        if not job:
            return {"job_id": job_id, "status": "not_found"}
        if job.status in ACTIVE_STATUSES:
            return {"job_id": job_id, "status": "job_active"}
        del self.jobs[job_id]
        self._emit_job_update(job, reason="deleted")
        return {"job_id": job_id, "status": JobStatus.CANCELLED.value}

    def get_job_logs(self, job_id: str) -> Optional[List[Dict[str, Any]]]:
        job = self.jobs.get(job_id)
        if not job:
            return None
        return job.logs

    def build_job_options_snapshot(
        self,
        job_id: str,
        *,
        since_version: Optional[int] = None,
        include_options: bool = True,
    ) -> Optional[Dict[str, Any]]:
        job = self.jobs.get(job_id)
        if not job:
            return None
        version = getattr(job, "options_version", None)
        delta_type = "full"
        if (
            version is not None
            and since_version is not None
            and version == since_version
        ):
            delta_type = "noop"
        include_payload = include_options or delta_type != "noop"
        payload: Dict[str, Any] = {
            "job_id": job.job_id,
            "version": version,
            "delta": {
                "type": delta_type,
                "version": version,
                "since": since_version,
            },
        }
        if include_payload:
            payload["options"] = job.options
        return payload

    def build_job_logs_snapshot(
        self,
        job_id: str,
        *,
        since_version: Optional[int] = None,
        include_logs: bool = True,
        limit: Optional[int] = None,
    ) -> Optional[Dict[str, Any]]:
        job = self.jobs.get(job_id)
        if not job:
            return None
        version = getattr(job, "logs_version", None)
        logs = list(job.logs)
        if isinstance(limit, int) and limit > 0:
            logs = logs[-limit:]
        delta_type = "full"
        if (
            version is not None
            and since_version is not None
            and version == since_version
        ):
            delta_type = "noop"
        include_payload = include_logs or delta_type != "noop"
        payload: Dict[str, Any] = {
            "job_id": job.job_id,
            "version": version,
            "count": len(logs),
            "delta": {
                "type": delta_type,
                "version": version,
                "since": since_version,
            },
        }
        if include_payload:
            payload["logs"] = logs
        return payload

    def build_playlist_snapshot(
        self,
        job_id: str,
        *,
        include_entries: bool = False,
        include_entry_progress: bool = False,
    ) -> Optional[Dict[str, Any]]:
        job = self.jobs.get(job_id)
        if not job:
            return None
        playlist: Dict[str, Any] = {
            "entry_count": len(job.playlist_entries),
            "requires_selection": job.selection_required,
            "selected_indices": list(job.selected_indices),
        }
        if include_entries:
            playlist["entries"] = job.playlist_entries
        if include_entry_progress:
            playlist["entry_progress"] = list(job.entry_progress.values())
        return {"job_id": job.job_id, "playlist": playlist}

    def build_playlist_entries(self, job_id: str, **_: Any) -> Optional[Dict[str, Any]]:
        job = self.jobs.get(job_id)
        if not job:
            return None
        return {"job_id": job.job_id, "playlist": {"entries": job.playlist_entries}}

    def build_playlist_entry_state(
        self, job_id: str, entry_index: int
    ) -> Optional[Dict[str, Any]]:
        job = self.jobs.get(job_id)
        if not job:
            return None
        state = job.entry_progress.get(entry_index)
        if state:
            return dict(state)
        entry = next(
            (item for item in job.playlist_entries if item.get("index") == entry_index),
            None,
        )
        if not entry:
            return None
        return {
            "job_id": job.job_id,
            "entry_index": entry_index,
            "entry": entry,
            "status": job.status,
        }

    def apply_playlist_selection(
        self, job_id: str, *, indices: Optional[List[int]]
    ) -> Dict[str, Any]:
        job = self.jobs.get(job_id)
        if not job:
            return {"job_id": job_id, "status": "not_found"}
        if indices is None:
            job.selected_indices = []
        else:
            job.selected_indices = indices
            job.selection_required = False
            job.status = JobStatus.RUNNING.value
        self._emit_playlist_snapshot(job)
        self._emit_job_update(job, reason="selection_applied")
        return {
            "job_id": job.job_id,
            "status": job.status,
            "indices": job.selected_indices,
        }

    def _emit_playlist_entry_progress(
        self,
        job: FakeJob,
        *,
        entry_index: int,
        status: str,
        stage: str,
        url: str,
        filename: Optional[str] = None,
    ) -> None:
        if not self.socket_manager:
            return
        entry = next(
            (item for item in job.playlist_entries if item.get("index") == entry_index),
            None,
        )
        payload: Dict[str, Any] = {
            "job_id": job.job_id,
            "entry_index": entry_index,
            "status": status,
            "stage": stage,
            "url": url,
            "timestamp": self._now(),
        }
        if filename:
            payload["filename"] = filename
        if entry:
            payload["entry"] = entry
        job.entry_progress[entry_index] = payload
        self.socket_manager.emit(
            SocketEvent.PLAYLIST_ENTRY_PROGRESS.value,
            payload,
            room=SocketRoom.for_job(job.job_id),
        )

    def _emit_playlist_progress(
        self,
        job: FakeJob,
        *,
        completed_entries: int,
        total_entries: int,
        latest_entry: Optional[int] = None,
    ) -> None:
        if not self.socket_manager or total_entries <= 0:
            return
        percent = (completed_entries / total_entries) * 100
        progress_state: Dict[str, Any] = {
            "status": job.status,
            "stage": "downloading_playlist",
            "stage_name": "Downloading playlist",
            "stage_percent": percent,
            "percent": percent,
            "playlist_total_items": total_entries,
            "playlist_completed_items": completed_entries,
            "playlist_pending_items": max(total_entries - completed_entries, 0),
            "playlist_percent": percent,
            "playlist_newly_completed_index": latest_entry,
        }
        job.progress = dict(progress_state)
        summary = self._build_progress_summary(job.job_id, progress_state).to_dict()
        summary["timestamp"] = self._now()
        summary.setdefault("reason", "simulated_progress")
        self.socket_manager.emit(
            SocketEvent.PLAYLIST_PROGRESS.value,
            summary,
            room=SocketRoom.for_job(job.job_id),
        )
        self.socket_manager.emit(
            SocketEvent.PROGRESS.value,
            summary,
            room=SocketRoom.for_job(job.job_id),
        )

    @staticmethod
    def _text(value: Any) -> Optional[str]:
        if value is None:
            return None
        text = str(value).strip()
        return text or None

    @staticmethod
    def _to_int(value: Any) -> Optional[int]:
        try:
            return int(value)
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _to_float(value: Any) -> Optional[float]:
        try:
            return float(value)
        except (TypeError, ValueError):
            return None

    def _build_progress_summary(
        self, job_id: str, data: Dict[str, Any]
    ) -> ProgressPayload:
        return ProgressPayload(
            job_id=job_id,
            status=self._text(data.get("status")),
            percent=self._to_float(data.get("percent")),
            stage=self._text(data.get("stage")),
            stage_name=self._text(data.get("stage_name")),
            stage_percent=self._to_float(data.get("stage_percent")),
            playlist_total_items=self._to_int(data.get("playlist_total_items")),
            playlist_completed_items=self._to_int(data.get("playlist_completed_items")),
            playlist_pending_items=self._to_int(data.get("playlist_pending_items")),
            playlist_percent=self._to_float(data.get("playlist_percent")),
            playlist_newly_completed_index=self._to_int(
                data.get("playlist_newly_completed_index")
            ),
        )

    def build_progress_summary(
        self, job_id: str, data: Mapping[str, Any]
    ) -> ProgressPayload:
        return self._build_progress_summary(job_id, dict(data))

    @staticmethod
    def _now() -> str:
        now_utc = datetime.now(timezone.utc).replace(tzinfo=None)
        return now_utc.isoformat() + "Z"

    def preview_metadata(
        self, urls: Any, options: Optional[Dict[str, Any]]
    ) -> Dict[str, Any]:
        candidates: List[Any]
        if isinstance(urls, list):
            iterable_urls = cast(Iterable[Any], urls)
            candidates = list(iterable_urls)
        else:
            candidates = [urls]
        normalized_urls: list[str] = []
        for value in candidates:
            text = self._text(value)
            if text is not None:
                normalized_urls.append(text)
        is_playlist = self._contains_playlist(normalized_urls, None)
        entries: List[Dict[str, Any]] = []
        if is_playlist:
            entries = self._build_playlist_entries(normalized_urls)
        else:
            primary = normalized_urls[0] if normalized_urls else NCS_VIDEO_URL
            entries = [
                {
                    "index": 1,
                    "title": "NCS Track",
                    "url": primary,
                    "duration": 210,
                }
            ]
        return {
            "urls": normalized_urls,
            "options": options or {},
            "entries": entries,
            "is_playlist": is_playlist,
        }


class SimpleResponse:
    def __init__(
        self, status_code: int, body: bytes, headers: list[tuple[bytes, bytes]]
    ) -> None:
        self.status_code = status_code
        self._body = body
        self.headers = headers

    def json(self) -> Any:
        if not self._body:
            return None
        return json.loads(self._body.decode())


class SimpleASGITestClient:
    """Minimal ASGI test client that avoids httpx dependency."""

    def __init__(self, app: ASGIApp, *, token: Optional[str] = None) -> None:
        self.app = app
        self._token = token

    def request(
        self,
        method: str,
        path: str,
        *,
        json_body: Optional[Dict[str, Any]] = None,
        query: Optional[Dict[str, Any]] = None,
    ) -> SimpleResponse:
        body = b""
        headers: list[tuple[bytes, bytes]] = [(b"host", b"testserver")]
        if self._token:
            headers.append((b"authorization", f"Bearer {self._token}".encode("utf-8")))
        if json_body is not None:
            body = json.dumps(json_body).encode("utf-8")
            headers.append((b"content-type", b"application/json"))
        pending_body = [body]
        query_string = urlencode(query or {}, doseq=True).encode("utf-8")
        scope = {
            "type": "http",
            "asgi": {"version": "3.0"},
            "http_version": "1.1",
            "method": method.upper(),
            "path": path,
            "raw_path": path.encode("utf-8"),
            "query_string": query_string,
            "headers": headers,
            "client": ("testclient", 50000),
            "server": ("testserver", 80),
        }
        response_body = bytearray()
        response_headers: list[tuple[bytes, bytes]] = []
        status_code = 500

        async def receive() -> MutableMapping[str, Any]:
            if not pending_body:
                return {"type": "http.disconnect"}
            current = pending_body.pop()
            return {"type": "http.request", "body": current, "more_body": False}

        async def send(message: MutableMapping[str, Any]) -> None:
            nonlocal status_code, response_headers
            if message["type"] == "http.response.start":
                status_code = message["status"]
                response_headers = message.get("headers", [])
            elif message["type"] == "http.response.body":
                response_body.extend(message.get("body", b""))

        async def _invoke_app() -> None:
            await self.app(scope, receive, send)

        asyncio.run(_invoke_app())
        return SimpleResponse(status_code, bytes(response_body), response_headers)

    def get(
        self, path: str, *, query: Optional[Dict[str, Any]] = None
    ) -> SimpleResponse:
        return self.request("GET", path, query=query)

    def post(
        self,
        path: str,
        *,
        json: Optional[Dict[str, Any]] = None,
        query: Optional[Dict[str, Any]] = None,
    ) -> SimpleResponse:
        return self.request("POST", path, json_body=json, query=query)


class ApiHttpRoutesTest(TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.download_dir = Path(self.temp_dir.name) / "downloads"
        self.socket_manager = RecordingSocketManager()
        self.manager = FakeDownloadManager(
            download_dir=self.download_dir, socket_manager=self.socket_manager
        )
        app = Starlette()
        manager_stub = cast(DownloadManager, self.manager)
        register_http_routes(app, manager_stub)
        register_websocket_routes(
            app,
            manager_stub,
            cast(SocketManager, self.socket_manager),
        )
        self.token = SERVER_TOKEN
        self.client = SimpleASGITestClient(app, token=self.token)
        self.addCleanup(self.temp_dir.cleanup)

    def _default_options(self, **overrides: Any) -> Dict[str, Any]:
        options: Dict[str, Any] = {"output_dir": str(self.download_dir)}
        options.update(overrides)
        return options

    def _create_job(
        self,
        urls: Any,
        *,
        options: Optional[Dict[str, Any]] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> str:
        payload: Dict[str, Any] = {"urls": urls}
        payload["options"] = options or self._default_options()
        if metadata:
            payload["metadata"] = metadata
        response = self.client.post("/api/jobs", json=payload)
        self.assertEqual(response.status_code, 201)
        payload_json = cast(Dict[str, Any], response.json())
        job_id = payload_json.get("job_id")
        assert isinstance(job_id, str)
        return job_id

    def test_healthcheck_returns_summary(self) -> None:
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertIn("overview", payload)
        self.assertEqual(payload["overview"]["total"], 0)

    def test_create_job_requires_urls(self) -> None:
        response = self.client.post("/api/jobs", json={"options": {}})
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"], ErrorCode.URLS_REQUIRED.value)

    def test_create_job_success(self) -> None:
        response = self.client.post(
            "/api/jobs",
            json={"urls": [NCS_VIDEO_URL], "options": self._default_options()},
        )
        self.assertEqual(response.status_code, 201)
        payload = response.json()
        self.assertTrue(payload["job_id"].startswith("job-"))
        self.assertEqual(payload["status"], JobStatus.COMPLETED.value)

    def test_list_jobs_returns_serialized_entries(self) -> None:
        self._create_job(NCS_VIDEO_URL)
        response = self.client.get("/api/jobs")
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertGreaterEqual(len(payload["jobs"]), 1)
        self.assertIn("summary", payload)
        first_job = payload["jobs"][0]
        self.assertIn("generated_files", first_job)
        self.assertIn("partial_files", first_job)
        self.assertIn("main_file", first_job)

    def test_list_jobs_preserves_insertion_order(self) -> None:
        first = self._create_job(f"{NCS_VIDEO_URL}&order=1")
        second = self._create_job(f"{NCS_VIDEO_URL}&order=2")
        third = self._create_job(f"{NCS_VIDEO_URL}&order=3")

        response = self.client.get("/api/jobs")
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        jobs = payload["jobs"]
        self.assertGreaterEqual(len(jobs), 3)
        returned_ids = [entry["job_id"] for entry in jobs[:3]]
        self.assertEqual(returned_ids, [first, second, third])

    def test_get_job_not_found(self) -> None:
        response = self.client.get("/api/jobs/unknown")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["error"], ErrorCode.JOB_NOT_FOUND.value)

    def test_cancel_job_not_found(self) -> None:
        response = self.client.post("/api/jobs/missing/cancel")
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()["error"], ErrorCode.JOB_NOT_FOUND.value)

    def test_bulk_cancel_jobs_by_ids(self) -> None:
        first = self._create_job(NCS_VIDEO_URL)
        second = self._create_job(NCS_PLAYLIST_URL)
        response = self.client.post(
            "/api/jobs/cancel",
            json={"job_ids": [first, second]},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertIn("results", payload)
        cancelled_ids = {entry["job_id"] for entry in payload["results"]}
        self.assertSetEqual(cancelled_ids, {first, second})

    def test_bulk_cancel_jobs_scope_all(self) -> None:
        first = self._create_job(NCS_VIDEO_URL)
        second = self._create_job(NCS_PLAYLIST_URL)
        response = self.client.post(
            "/api/jobs/cancel",
            json={"scope": "all"},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        cancelled_ids = {entry["job_id"] for entry in payload["results"]}
        self.assertIn(first, cancelled_ids)
        self.assertIn(second, cancelled_ids)

    def test_bulk_cancel_jobs_requires_scope_or_ids(self) -> None:
        response = self.client.post("/api/jobs/cancel", json={})
        self.assertEqual(response.status_code, 400)
        payload = response.json()
        self.assertEqual(payload["error"], ErrorCode.INVALID_JSON_PAYLOAD.value)

    def test_playlist_selection_requires_list(self) -> None:
        response = self.client.post(
            "/api/jobs/fake-job/playlist/selection",
            json={"indices": "invalid"},
        )
        self.assertEqual(response.status_code, 400)
        payload = response.json()
        self.assertEqual(payload["error"], ErrorCode.INVALID_JSON_PAYLOAD.value)
        self.assertEqual(payload["detail"], "indices must be a list")

    def test_preview_endpoint_returns_payload(self) -> None:
        response = self.client.post(
            "/api/preview",
            json={"urls": [NCS_PLAYLIST_URL], "options": {"quality": "best"}},
        )
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertTrue(payload["preview"]["entries"])
        self.assertTrue(payload["preview"]["is_playlist"])

    def test_job_logs_endpoint_returns_logs(self) -> None:
        job_id = self._create_job(NCS_VIDEO_URL)
        response = self.client.get(f"/api/jobs/{job_id}/logs")
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["job_id"], job_id)
        self.assertGreaterEqual(len(payload["logs"]), 1)
        self.assertIn("version", payload)

    def test_job_logs_endpoint_delta_flow(self) -> None:
        job_id = self._create_job(NCS_VIDEO_URL)
        first = self.client.get(f"/api/jobs/{job_id}/logs").json()
        version = first.get("version")
        self.assertIsNotNone(version)
        delta_response = self.client.get(
            f"/api/jobs/{job_id}/logs",
            query={"since": str(version)},
        )
        self.assertEqual(delta_response.status_code, 200)
        delta_payload = delta_response.json()
        self.assertNotIn("logs", delta_payload)
        detailed_response = self.client.get(
            f"/api/jobs/{job_id}/logs",
            query={"since": str(version), "detail": "true", "limit": "1"},
        )
        self.assertEqual(detailed_response.status_code, 200)
        detailed_payload = detailed_response.json()
        self.assertIn("logs", detailed_payload)
        self.assertLessEqual(len(detailed_payload["logs"]), 1)

    def test_job_logs_endpoint_validates_params(self) -> None:
        job_id = self._create_job(NCS_VIDEO_URL)
        response = self.client.get(
            f"/api/jobs/{job_id}/logs",
            query={"since": "abc"},
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.json()["error"], ErrorCode.SINCE_MUST_BE_INTEGER.value
        )
        limit_response = self.client.get(
            f"/api/jobs/{job_id}/logs",
            query={"limit": "NaN"},
        )
        self.assertEqual(limit_response.status_code, 400)
        self.assertEqual(
            limit_response.json()["error"],
            ErrorCode.LIMIT_MUST_BE_INTEGER.value,
        )

    def test_job_logs_endpoint_rejects_invalid_entry_index(self) -> None:
        job_id = self._create_job(NCS_VIDEO_URL)
        response = self.client.get(
            f"/api/jobs/{job_id}/logs",
            query={"entry_index": "abc"},
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"], ErrorCode.ENTRY_INDEX_INVALID.value)

    def test_job_options_endpoint_returns_options(self) -> None:
        job_id = self._create_job(NCS_VIDEO_URL)
        response = self.client.get(f"/api/jobs/{job_id}/options")
        self.assertEqual(response.status_code, 200)
        payload = response.json()
        self.assertEqual(payload["job_id"], job_id)
        self.assertIn("options", payload)
        self.assertIn("version", payload)

    def test_job_options_endpoint_since_validation(self) -> None:
        job_id = self._create_job(NCS_VIDEO_URL)
        response = self.client.get(
            f"/api/jobs/{job_id}/options",
            query={"since": "bad"},
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(
            response.json()["error"], ErrorCode.SINCE_MUST_BE_INTEGER.value
        )

    def test_job_options_endpoint_rejects_invalid_entry_index(self) -> None:
        job_id = self._create_job(NCS_VIDEO_URL)
        response = self.client.get(
            f"/api/jobs/{job_id}/options",
            query={"entry_index": "xyz"},
        )
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()["error"], ErrorCode.ENTRY_INDEX_INVALID.value)

    def test_create_job_writes_file_to_temp_directory(self) -> None:
        job_id = self._create_job(NCS_VIDEO_URL)
        job = self.manager.get_job(job_id)
        self.assertIsNotNone(job)
        assert job is not None
        self.assertTrue(job.generated_files)
        generated_path = Path(job.generated_files[0])
        self.assertTrue(generated_path.exists())
        self.assertIn(NCS_VIDEO_URL, generated_path.read_text(encoding="utf-8"))

    def test_pause_and_resume_job_flow(self) -> None:
        job_id = self._create_job(
            NCS_VIDEO_URL,
            options=self._default_options(defer_complete=True),
        )
        pause_response = self.client.post(f"/api/jobs/{job_id}/pause")
        self.assertEqual(pause_response.status_code, 200)
        self.assertEqual(pause_response.json()["status"], JobStatus.PAUSED.value)
        resume_response = self.client.post(f"/api/jobs/{job_id}/resume")
        self.assertEqual(resume_response.status_code, 200)
        self.assertEqual(resume_response.json()["status"], JobStatus.RUNNING.value)

    def test_retry_job_after_failure(self) -> None:
        job_id = self._create_job(
            NCS_VIDEO_URL,
            options=self._default_options(defer_complete=True),
        )
        job = self.manager.get_job(job_id)
        assert job is not None
        job.status = JobStatus.FAILED.value
        retry_response = self.client.post(f"/api/jobs/{job_id}/retry")
        self.assertEqual(retry_response.status_code, 200)
        self.assertEqual(retry_response.json()["status"], JobStatus.RUNNING.value)

    def test_playlist_snapshot_and_selection_flow(self) -> None:
        job_id = self._create_job(
            [NCS_PLAYLIST_URL],
            options=self._default_options(defer_complete=True),
            metadata={"requires_playlist_selection": True},
        )
        playlist_response = self.client.get(f"/api/jobs/{job_id}/playlist")
        self.assertEqual(playlist_response.status_code, 200)
        snapshot = playlist_response.json()
        self.assertGreater(snapshot["playlist"]["entry_count"], 0)
        entries_response = self.client.get(f"/api/jobs/{job_id}/playlist/items")
        self.assertEqual(entries_response.status_code, 200)
        entries_payload = entries_response.json()
        self.assertTrue(entries_payload["playlist"]["entries"])
        selection_response = self.client.post(
            f"/api/jobs/{job_id}/playlist/selection",
            json={"indices": [1, 2]},
        )
        self.assertEqual(selection_response.status_code, 200)
        selection_payload = selection_response.json()
        self.assertEqual(selection_payload["indices"], [1, 2])
        self.assertEqual(selection_payload["status"], JobStatus.RUNNING.value)

    def test_playlist_entry_events_stream_over_socket(self) -> None:
        job_id = self._create_job(
            [NCS_PLAYLIST_URL],
            options=self._default_options(defer_complete=True),
            metadata={"requires_playlist_selection": True},
        )
        job = self.manager.get_job(job_id)
        assert job is not None
        job_room = SocketRoom.for_job(job_id)
        snapshots = self.socket_manager.select(
            event=SocketEvent.PLAYLIST_SNAPSHOT.value, room=job_room
        )
        self.assertTrue(snapshots, "expected playlist snapshot to be emitted")
        entry_events = self.socket_manager.select(
            event=SocketEvent.PLAYLIST_ENTRY_PROGRESS.value
        )
        self.assertGreaterEqual(len(entry_events), len(job.playlist_entries) * 2)
        events_by_index: Dict[int, List[Dict[str, Any]]] = {}
        for record in entry_events:
            payload = record["payload"]
            entry_index = payload["entry_index"]
            events_by_index.setdefault(entry_index, []).append(payload)
        for entry in job.playlist_entries:
            entry_index = entry["index"]
            tracked = events_by_index.get(entry_index)
            self.assertIsNotNone(tracked, f"missing events for entry {entry_index}")
            assert tracked is not None
            stages = {item["stage"] for item in tracked}
            self.assertIn("starting", stages)
            self.assertIn("completed", stages)

    def test_job_lifecycle_updates_broadcast_reasons(self) -> None:
        job_id = self._create_job(
            NCS_VIDEO_URL,
            options=self._default_options(defer_complete=True),
        )
        job_room = SocketRoom.for_job(job_id)
        creation_events = self.socket_manager.select(
            event=SocketEvent.UPDATE.value, room=job_room
        )
        self.assertTrue(
            any(evt["payload"].get("reason") == "created" for evt in creation_events)
        )
        for endpoint, expected_reason in (
            (f"/api/jobs/{job_id}/pause", "paused"),
            (f"/api/jobs/{job_id}/resume", "resumed"),
            (f"/api/jobs/{job_id}/cancel", "cancelled"),
        ):
            response = self.client.post(endpoint)
            self.assertEqual(response.status_code, 200)
            events = self.socket_manager.drain(
                event=SocketEvent.UPDATE.value, room=job_room
            )
            reasons = [evt["payload"].get("reason") for evt in events]
            self.assertIn(expected_reason, reasons)

    def test_playlist_selection_emits_snapshot_and_job_update(self) -> None:
        job_id = self._create_job(
            [NCS_PLAYLIST_URL],
            options=self._default_options(defer_complete=True),
            metadata={"requires_playlist_selection": True},
        )
        self.socket_manager.clear()
        response = self.client.post(
            f"/api/jobs/{job_id}/playlist/selection",
            json={"indices": [1, 3]},
        )
        self.assertEqual(response.status_code, 200)
        job_room = SocketRoom.for_job(job_id)
        snapshots = self.socket_manager.select(
            event=SocketEvent.PLAYLIST_SNAPSHOT.value, room=job_room
        )
        self.assertTrue(snapshots)
        latest_snapshot = snapshots[-1]["payload"]
        self.assertEqual(latest_snapshot["playlist"]["selected_indices"], [1, 3])
        updates = self.socket_manager.select(
            event=SocketEvent.UPDATE.value, room=job_room
        )
        self.assertTrue(
            any(evt["payload"].get("reason") == "selection_applied" for evt in updates)
        )


class ApiWebSocketRoutesTest(TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.download_dir = Path(self.temp_dir.name) / "downloads"
        self.socket_manager = SocketManager()
        self.manager = FakeDownloadManager(
            download_dir=self.download_dir, socket_manager=self.socket_manager
        )

        @asynccontextmanager
        async def lifespan(_: Starlette) -> AsyncIterator[None]:
            loop = asyncio.get_running_loop()
            self.socket_manager.bind_loop(loop)
            try:
                yield
            finally:
                await self.socket_manager.aclose()

        app = Starlette(lifespan=lifespan)
        manager_stub = cast(DownloadManager, self.manager)
        register_http_routes(app, manager_stub)
        register_websocket_routes(
            app,
            manager_stub,
            self.socket_manager,
        )
        self._client_cm = TestClient(app)
        self.client = self._client_cm.__enter__()
        self.token = SERVER_TOKEN
        self.client.headers.update({"Authorization": f"Bearer {self.token}"})
        self.addCleanup(self._client_cm.__exit__, None, None, None)
        self.addCleanup(self.temp_dir.cleanup)

    def _default_options(self, **overrides: Any) -> Dict[str, Any]:
        options: Dict[str, Any] = {
            "output_dir": str(self.download_dir),
            "defer_complete": True,
        }
        options.update(overrides)
        return options

    def _create_job(
        self,
        urls: Any,
        *,
        options: Optional[Dict[str, Any]] = None,
        metadata: Optional[Dict[str, Any]] = None,
    ) -> str:
        payload: Dict[str, Any] = {
            "urls": urls,
            "options": options or self._default_options(),
        }
        if metadata:
            payload["metadata"] = metadata
        response = self.client.post("/api/jobs", json=payload)
        self.assertEqual(response.status_code, 201, response.text)
        payload_json = cast(Dict[str, Any], response.json())
        job_id = payload_json.get("job_id")
        assert isinstance(job_id, str)
        return job_id

    def _ws_headers(self) -> Dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}

    def _wait_for_event(
        self,
        websocket: Any,
        event_name: str,
        *,
        predicate: Optional[Callable[[Dict[str, Any]], bool]] = None,
        attempts: int = 10,
    ) -> Dict[str, Any]:
        for _ in range(attempts):
            message = cast(Dict[str, Any], websocket.receive_json())
            if message.get("event") != event_name:
                continue
            payload_data = message.get("payload", {})
            if isinstance(payload_data, dict):
                payload_dict = cast(Dict[str, Any], payload_data)
            else:
                payload_dict = {}
            payload = payload_dict
            if predicate and not predicate(payload):
                continue
            return payload
        self.fail(f"event '{event_name}' not received after {attempts} attempts")

    def test_job_socket_emits_lifecycle_events(self) -> None:
        job_id = self._create_job(
            NCS_VIDEO_URL,
            options=self._default_options(),
        )
        with self.client.websocket_connect(
            f"/ws/jobs/{job_id}", headers=self._ws_headers()
        ) as websocket:
            self._wait_for_event(
                websocket,
                SocketEvent.UPDATE.value,
                predicate=lambda payload: payload.get("reason") == "initial_sync",
            )
            pause_response = self.client.post(f"/api/jobs/{job_id}/pause")
            self.assertEqual(pause_response.status_code, 200)
            paused = self._wait_for_event(
                websocket,
                SocketEvent.UPDATE.value,
                predicate=lambda payload: payload.get("status")
                == JobStatus.PAUSED.value,
            )
            self.assertEqual(paused["reason"], "paused")
            resume_response = self.client.post(f"/api/jobs/{job_id}/resume")
            self.assertEqual(resume_response.status_code, 200)
            resumed = self._wait_for_event(
                websocket,
                SocketEvent.UPDATE.value,
                predicate=lambda payload: payload.get("reason") == "resumed",
            )
            self.assertEqual(resumed["status"], JobStatus.RUNNING.value)
            cancel_response = self.client.post(f"/api/jobs/{job_id}/cancel")
            self.assertEqual(cancel_response.status_code, 200)
            cancelled = self._wait_for_event(
                websocket,
                SocketEvent.UPDATE.value,
                predicate=lambda payload: payload.get("reason") == "cancelled",
            )
            self.assertEqual(cancelled["status"], JobStatus.CANCELLED.value)

    def test_job_socket_reflects_playlist_selection_changes(self) -> None:
        job_id = self._create_job(
            [NCS_PLAYLIST_URL],
            options=self._default_options(),
            metadata={"requires_playlist_selection": True},
        )
        with self.client.websocket_connect(
            f"/ws/jobs/{job_id}", headers=self._ws_headers()
        ) as websocket:
            self._wait_for_event(
                websocket,
                SocketEvent.PLAYLIST_SNAPSHOT.value,
                predicate=lambda payload: payload["playlist"].get("entry_count") == 3,
            )
            selection_response = self.client.post(
                f"/api/jobs/{job_id}/playlist/selection",
                json={"indices": [1, 3]},
            )
            self.assertEqual(selection_response.status_code, 200)
            updated_snapshot = self._wait_for_event(
                websocket,
                SocketEvent.PLAYLIST_SNAPSHOT.value,
                predicate=lambda payload: payload["playlist"].get("selected_indices")
                == [1, 3],
            )
            self.assertEqual(updated_snapshot["playlist"]["selected_indices"], [1, 3])

    def test_job_socket_reports_playlist_entry_state(self) -> None:
        job_id = self._create_job(
            [NCS_PLAYLIST_URL],
            options=self._default_options(),
            metadata={"requires_playlist_selection": True},
        )
        job = self.manager.get_job(job_id)
        assert job is not None
        with self.client.websocket_connect(
            f"/ws/jobs/{job_id}", headers=self._ws_headers()
        ) as websocket:
            emit_progress = cast(
                PlaylistEntryEmitter,
                getattr(self.manager, "_emit_playlist_entry_progress"),
            )
            emit_progress(
                job,
                entry_index=1,
                status=JobStatus.COMPLETED.value,
                stage="completed",
                url=job.urls[0],
            )
            entry_payload = self._wait_for_event(
                websocket,
                SocketEvent.PLAYLIST_ENTRY_PROGRESS.value,
                predicate=lambda payload: payload.get("entry_index") == 1,
            )
            self.assertEqual(entry_payload["entry"]["index"], 1)
            self.assertEqual(entry_payload["status"], JobStatus.COMPLETED.value)
