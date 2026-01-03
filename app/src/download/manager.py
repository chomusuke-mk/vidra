from __future__ import annotations

import json
import threading
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Mapping, Optional, Set, Tuple, Union, cast

from .mixins import PlaylistMixin, PreviewMixin, ProgressMixin
from .mixins.preview import PreviewCollectionError
from .job_logger import JobLogger
from .job_log_store import JobLogStore
from .job_options_store import JobOptionsStore
from .models import (
    DownloadJob,
    DownloadJobMetadataPayload,
    DownloadJobOptionsPayload,
    DownloadJobProgressPayload,
)
from .stages import DownloadStage
from .playlist_entry_store import PlaylistEntryList, PlaylistEntryStore
from .state_store import DownloadStateStore
from ..exceptions import DownloadCancelled, DownloadPaused
from ..log_config import verbose_log
from ..core import (
    DownloadError,
    Manager as CoreManager,
    build_options_config,
    resolve_options,
    download,
)
from ..core.downloader import (
    MatchFilter,
    MatchFilterArgs,
    LoggerLike,
    YtDlpInfoResult,
)
from ..config import (
    ACTIVE_STATUSES,
    CANCEL_IMMEDIATE_STATUSES,
    JobCommandReason,
    JobCommandStatus,
    JobKind,
    JobStatus,
    JobUpdateReason,
    PAUSE_ELIGIBLE_STATUSES,
    RESUMABLE_STATUSES,
    SocketEvent,
    SocketRoom,
    TERMINAL_STATUSES,
    DATA_FOLDER,
)
from ..socket_manager import SocketManager
from ..models.download.manager import (
    CreateJobRequest,
    DownloadPersistedState,
    JobLogEntry,
    JobLogEntryPayload,
)
from ..models.download.mixins.progress import (
    ProgressSnapshot,
    ProgressSnapshotPayload,
)
from ..models.download.mixins.preview import (
    PlaylistMetadataPayload,
    PreviewMetadataPayload,
)
from ..models.shared import JSONValue, PlaylistEntryMetadataPayload, clone_json_value
from ..download.mixins.manager_utils import metadata_public_view
from ..utils import now_iso, strip_ansi, to_bool, to_int

JsonSafePrimitive = None | bool | int | float | str
JsonSafeValue = JsonSafePrimitive | list["JsonSafeValue"] | dict[str, "JsonSafeValue"]
JsonSafeDict = dict[str, JsonSafeValue]
SnapshotPackage = Tuple[
    DownloadPersistedState,
    DownloadJobOptionsPayload,
    List[JobLogEntryPayload],
]
SnapshotDelta = Dict[str, JSONValue]


COMPLETED_STATUSES = {
    JobStatus.COMPLETED.value,
    JobStatus.COMPLETED_WITH_ERRORS.value,
}


def _utc_now_naive() -> datetime:
    """Return a timezone-aware UTC timestamp converted to naive form."""

    return datetime.now(timezone.utc).replace(tzinfo=None)


def _classify_signal_from_message(message: Optional[str]) -> Optional[str]:
    if not message:
        return None
    normalized = message.lower()
    if "paused by user request" in normalized or "descarga pausada" in normalized:
        return JobStatus.PAUSED.value
    if (
        "cancelled by user request" in normalized
        or "canceled by user request" in normalized
        or "descarga cancelada" in normalized
    ):
        return JobStatus.CANCELLED.value
    if "job cancelled" in normalized and "user" in normalized:
        return JobStatus.CANCELLED.value
    return None


class DownloadManager(PreviewMixin, PlaylistMixin, ProgressMixin):
    """Coordinates download jobs and websocket notifications."""

    OVERVIEW_ROOM = SocketRoom.OVERVIEW.value
    OPTION_PREVIEW_KEYS: Tuple[str, ...] = (
        "paths",
        "playlist",
        "playlist_items",
        "output",
        "format",
        "merge_output_format",
    )
    OPTION_PREVIEW_SERIALIZED_LIMIT = 2000

    @staticmethod
    def _normalize_job_kind_value(value: object) -> str:
        if isinstance(value, JobKind):
            return value.value
        if isinstance(value, str):
            normalized = value.strip().lower()
            for member in JobKind:
                if member.value == normalized:
                    return member.value
        return JobKind.UNKNOWN.value

    @staticmethod
    def _coerce_bool_hint(value: JSONValue | object) -> Optional[bool]:
        if isinstance(value, bool):
            return value
        if isinstance(value, str):
            normalized = value.strip().lower()
            if normalized in {"true", "1", "yes", "on"}:
                return True
            if normalized in {"false", "0", "no", "off"}:
                return False
        return None

    def _playlist_payload_indicates_playlist(
        self, playlist_meta: PlaylistMetadataPayload
    ) -> bool:
        entries = playlist_meta.get("entries")
        if isinstance(entries, list) and entries:
            return True
        entry_count = to_int(playlist_meta.get("entry_count"))
        if entry_count and entry_count > 0:
            return True
        total_items = to_int(playlist_meta.get("total_items"))
        if total_items and total_items > 0:
            return True
        return False

    def _preview_metadata_indicates_playlist(
        self, preview_meta: PreviewMetadataPayload
    ) -> bool:
        preview_hint = self._coerce_bool_hint(preview_meta.get("is_playlist"))
        if preview_hint is True:
            return True
        playlist_payload = preview_meta.get("playlist")
        if isinstance(playlist_payload, dict) and playlist_payload:
            return self._playlist_payload_indicates_playlist(playlist_payload)
        entry_count = to_int(preview_meta.get("playlist_entry_count"))
        if entry_count and entry_count > 0:
            return True
        return False

    def _metadata_indicates_playlist(
        self, metadata: DownloadJobMetadataPayload
    ) -> bool:
        hint = self._coerce_bool_hint(metadata.get("is_playlist"))
        if hint is True:
            return True

        playlist_meta = metadata.get("playlist")
        if isinstance(playlist_meta, dict) and playlist_meta:
            if self._playlist_payload_indicates_playlist(playlist_meta):
                return True

        preview_meta = metadata.get("preview")
        if isinstance(preview_meta, dict) and preview_meta:
            if self._preview_metadata_indicates_playlist(preview_meta):
                return True

        selection_hint = metadata.get("requires_playlist_selection")
        if isinstance(selection_hint, bool):
            return selection_hint

        return False

    def _determine_job_kind(
        self,
        job: DownloadJob,
        *,
        preview_metadata: Optional[PreviewMetadataPayload] = None,
    ) -> str:
        if preview_metadata and self._preview_metadata_indicates_playlist(
            preview_metadata
        ):
            return JobKind.PLAYLIST.value

        metadata_payload = job.metadata
        if metadata_payload and self._metadata_indicates_playlist(metadata_payload):
            return JobKind.PLAYLIST.value

        if job.selection_required:
            return JobKind.PLAYLIST.value

        return JobKind.VIDEO.value

    def _apply_job_kind_locked(
        self,
        job: DownloadJob,
        new_kind: object,
        *,
        log_transition: bool = True,
    ) -> bool:
        normalized_kind = self._normalize_job_kind_value(new_kind)
        current_kind = self._normalize_job_kind_value(getattr(job, "kind", None))
        job.kind = normalized_kind
        if current_kind == normalized_kind:
            return False

        if log_transition and normalized_kind != JobKind.UNKNOWN.value:
            label = (
                "lista de reproducción"
                if normalized_kind == JobKind.PLAYLIST.value
                else "video"
            )
            self.append_log(job.job_id, "info", f"Contenido identificado como {label}")
        return True

    def _ensure_job_kind_locked(
        self,
        job: DownloadJob,
        *,
        preview_metadata: Optional[PreviewMetadataPayload] = None,
        log_transition: bool = True,
    ) -> bool:
        desired_kind = self._determine_job_kind(
            job,
            preview_metadata=preview_metadata,
        )
        return self._apply_job_kind_locked(
            job,
            desired_kind,
            log_transition=log_transition,
        )

    def _update_job_kind_from_preview(
        self,
        job: DownloadJob,
        preview_metadata: Optional[PreviewMetadataPayload],
    ) -> bool:
        return self._ensure_job_kind_locked(
            job,
            preview_metadata=preview_metadata,
        )

    def _persist_jobs(self) -> None:
        with self.lock:
            packages = [self._snapshot_job_state(job) for job in self.jobs.values()]

        snapshots: List[DownloadPersistedState] = []
        for snapshot, options_payload, log_payload in packages:
            options_version = self._store_job_options_payload(
                snapshot.job_id,
                options_payload,
            )
            snapshot.options_version = options_version
            snapshot.options_external = options_version is not None

            logs_version = self._store_job_logs_payload(
                snapshot.job_id,
                log_payload,
            )
            snapshot.logs_version = logs_version
            snapshot.logs_external = logs_version is not None

            snapshots.append(snapshot)

        self.state_store.save(snapshots)

    def _snapshot_job_state(self, job: DownloadJob) -> SnapshotPackage:
        metadata_view = metadata_public_view(
            job.metadata,
            include_playlist_entries=False,
        )
        metadata_payload = self._safe_metadata_payload(metadata_view)
        options_payload = self._safe_options_payload(job.options)
        options_preview = self._compact_options_preview(dict(options_payload))

        progress_payload = self._safe_progress_payload(job.progress)
        progress_snapshot = (
            ProgressSnapshot.from_json(cast(ProgressSnapshotPayload, progress_payload))
            if progress_payload
            else None
        )

        log_entries_payload = [entry.to_json() for entry in list(job.logs)]

        completed_indices = sorted(job.playlist_completed_indices)
        failed_indices = sorted(job.playlist_failed_indices)
        pending_indices = sorted(job.playlist_pending_indices)
        removed_indices = sorted(job.playlist_removed_indices)
        entry_error_records = list(job.playlist_entry_errors.values())
        generated_files = sorted(
            {path.strip() for path in job.generated_files if path.strip()}
        )
        partial_files = sorted(
            {path.strip() for path in job.partial_files if path.strip()}
        )
        main_file_value = (
            job.main_file.strip() if isinstance(job.main_file, str) else None
        )

        def _iso_or_none(value: Optional[datetime]) -> Optional[str]:
            if not value:
                return None
            return value.isoformat() + "Z"

        snapshot = DownloadPersistedState(
            job_id=job.job_id,
            urls=[url for url in job.urls if url],
            options=options_preview,
            metadata=metadata_payload,
            status=str(job.status or JobStatus.QUEUED.value),
            kind=self._normalize_job_kind_value(job.kind),
            creator=job.creator,
            created_at=_iso_or_none(job.created_at),
            started_at=_iso_or_none(job.started_at),
            finished_at=_iso_or_none(job.finished_at),
            error=job.error,
            has_error_logs=bool(getattr(job, "has_error_logs", False)),
            progress=progress_snapshot,
            resume_requested=bool(job.resume_requested),
            playlist_total_items=job.playlist_total_items,
            playlist_entries_version=job.playlist_entries_version,
            playlist_completed_indices=completed_indices,
            playlist_failed_indices=failed_indices,
            playlist_pending_indices=pending_indices,
            playlist_removed_indices=removed_indices,
            playlist_entry_errors=entry_error_records,
            generated_files=generated_files,
            partial_files=partial_files,
            main_file=main_file_value,
            selection_required=bool(job.selection_required),
        )
        return snapshot, options_payload, log_entries_payload

    def _restore_persisted_jobs(self) -> None:
        snapshots = self.state_store.load()
        if not snapshots:
            return

        restored: List[DownloadJob] = []
        restoration_notes: Dict[str, Dict[str, str]] = {}
        for snapshot in snapshots:
            job = self._hydrate_job(snapshot)
            if not job:
                continue
            note_message, note_level = self._normalize_restored_job(job)
            restored.append(job)
            restoration_notes[job.job_id] = {
                "message": note_message,
                "level": note_level,
            }

        if not restored:
            return

        with self.lock:
            for job in restored:
                self.jobs[job.job_id] = job

        for job in restored:
            note = restoration_notes.get(job.job_id)
            if note:
                self.append_log(
                    job.job_id,
                    note.get("level", "info"),
                    note.get("message", "Trabajo restaurado"),
                )
            self.emit_job_update(job.job_id, reason=JobUpdateReason.RESTORED.value)

        self.emit_overview()
        self._persist_jobs()

    def _hydrate_job(self, snapshot: DownloadPersistedState) -> Optional[DownloadJob]:
        if not snapshot.job_id or not snapshot.urls:
            return None

        job = DownloadJob(
            job_id=snapshot.job_id,
            urls=list(snapshot.urls),
            options=self._clone_options_payload(snapshot.options),
            creator=snapshot.creator,
            metadata=self._clone_metadata_payload(snapshot.metadata),
        )
        job.options_version = snapshot.options_version

        job.created_at = self._parse_datetime(snapshot.created_at) or _utc_now_naive()
        job.status = str(snapshot.status or JobStatus.QUEUED.value)
        job.started_at = self._parse_datetime(snapshot.started_at)
        job.finished_at = self._parse_datetime(snapshot.finished_at)
        job.error = snapshot.error
        job.has_error_logs = bool(getattr(snapshot, "has_error_logs", False))

        job.progress = (
            cast(DownloadJobProgressPayload, snapshot.progress.to_json())
            if snapshot.progress
            else cast(DownloadJobProgressPayload, {})
        )

        job.playlist_total_items = snapshot.playlist_total_items

        if snapshot.playlist_completed_indices:
            job.playlist_completed_indices = set(snapshot.playlist_completed_indices)

        if snapshot.playlist_failed_indices:
            job.playlist_failed_indices = set(snapshot.playlist_failed_indices)

        if snapshot.playlist_pending_indices:
            job.playlist_pending_indices = set(snapshot.playlist_pending_indices)

        if snapshot.playlist_removed_indices:
            job.playlist_removed_indices = set(snapshot.playlist_removed_indices)

        if snapshot.playlist_entry_errors:
            job.playlist_entry_errors = {
                record.index: record
                for record in snapshot.playlist_entry_errors
                if record.index > 0
            }

        if snapshot.generated_files:
            job.generated_files = set(snapshot.generated_files)
        if snapshot.partial_files:
            job.partial_files = set(snapshot.partial_files)
        else:
            partial_candidates = {
                path for path in job.generated_files if self._looks_like_partial(path)
            }
            if partial_candidates:
                job.partial_files.update(partial_candidates)
                job.generated_files.difference_update(partial_candidates)
        if snapshot.main_file:
            job.main_file = snapshot.main_file

        for entry in snapshot.logs[-200:]:
            job.logs.append(entry)
        job.logs_version = snapshot.logs_version

        job.resume_requested = False
        job.selection_required = bool(snapshot.selection_required)
        job.kind = self._normalize_job_kind_value(snapshot.kind)
        if job.kind == JobKind.UNKNOWN.value:
            job.kind = self._determine_job_kind(job)
        job.playlist_entries_version = snapshot.playlist_entries_version
        self._restore_playlist_entries(job)
        self._restore_job_options(job, snapshot)
        self._restore_job_logs(job, snapshot)
        self._reset_job_events(job)
        return job

    def _normalize_restored_job(self, job: DownloadJob) -> tuple[str, str]:
        original_status = job.status
        normalized_status = original_status.lower()
        message = "Trabajo restaurado tras reinicio"
        level = "info"
        progress = job.progress
        now = _utc_now_naive()
        metadata = job.metadata
        requires_hint_raw = cast(JSONValue, metadata.get("requires_playlist_selection"))
        requires_hint = False
        if isinstance(requires_hint_raw, bool):
            requires_hint = requires_hint_raw
        elif isinstance(requires_hint_raw, str):
            normalized_hint = requires_hint_raw.strip().lower()
            requires_hint = normalized_hint in {"true", "1", "yes", "on"}
        if requires_hint and not job.selection_required:
            job.selection_required = True
            if job.selection_event.is_set():
                job.selection_event.clear()
            preview_event = getattr(job, "preview_ready_event", None)
            if isinstance(preview_event, threading.Event):
                preview_event.set()

        waiting_selection = job.selection_required and not job.selection_event.is_set()
        if waiting_selection:
            job.status = JobStatus.STARTING.value
            job.error = None
            job.finished_at = None
            progress.setdefault("status", JobStatus.STARTING.value)
            progress.setdefault("stage", "identifying")
            progress.setdefault("percent", 0.0)
            progress.setdefault(
                "message",
                "Esperando la selección de elementos de la lista de reproducción",
            )
            job.progress = progress
            return (
                "Trabajo esperando la selección de la lista tras reinicio",
                level,
            )

        if normalized_status in {
            JobStatus.RUNNING.value,
            JobStatus.QUEUED.value,
            JobStatus.STARTING.value,
            JobStatus.RETRYING.value,
        }:
            job.status = JobStatus.FAILED.value
            level = "warning"
            message = "Trabajo marcado como fallido tras reinicio del servicio"
            if not job.error:
                job.error = "La descarga se interrumpió por reinicio del servicio"
            if job.finished_at is None:
                job.finished_at = now
            progress.setdefault("status", JobStatus.FAILED.value)
            progress.setdefault("stage", progress.get("stage") or "error")
        elif normalized_status == JobStatus.PAUSING.value:
            job.status = JobStatus.PAUSED.value
            message = "Trabajo pausado tras reinicio del servicio"
            progress.setdefault("status", JobStatus.PAUSED.value)
            progress.setdefault("stage", progress.get("stage") or "paused")
        elif normalized_status == JobStatus.CANCELLING.value:
            job.status = JobStatus.CANCELLED.value
            message = "Trabajo cancelado tras reinicio del servicio"
            if job.finished_at is None:
                job.finished_at = now
            progress.setdefault("status", JobStatus.CANCELLED.value)
            progress.setdefault("stage", progress.get("stage") or "cancelled")
        else:
            job.status = original_status
            if job.status == JobStatus.FAILED.value and job.finished_at is None:
                job.finished_at = now

        job.progress = progress
        return message, level

    @staticmethod
    def _parse_datetime(value: object) -> Optional[datetime]:
        if not value:
            return None
        text = value.strip() if isinstance(value, str) else None
        if not text:
            return None
        if text.endswith("Z"):
            text = text[:-1]
        try:
            return datetime.fromisoformat(text)
        except Exception:
            return None

    @staticmethod
    def _looks_like_partial(path: str) -> bool:
        lowered = path.lower()
        return lowered.endswith((".part", ".ytdl", ".temp", ".tmp"))

    @staticmethod
    def _normalize_path(path_value: str) -> Optional[Path]:
        try:
            path = Path(path_value).expanduser()
        except Exception:
            return None
        try:
            return path.resolve()
        except Exception:
            return path

    def _cleanup_job_files(
        self, job: DownloadJob, *, include_completed: bool = False
    ) -> None:
        progress = job.progress
        candidates: Set[str] = set()

        tmp_value = progress.get("tmpfilename")
        if isinstance(tmp_value, str) and tmp_value.strip():
            candidates.add(tmp_value.strip())

        filename_value = progress.get("filename")
        if isinstance(filename_value, str) and filename_value.strip():
            sanitized = filename_value.strip()
            if include_completed:
                candidates.add(sanitized)
            candidates.add(f"{sanitized}.part")

        partial_files = job.partial_files
        for raw in list(partial_files):
            trimmed = raw.strip()
            if trimmed:
                candidates.add(trimmed)

        generated_files = job.generated_files
        for raw in list(generated_files):
            trimmed = raw.strip()
            if not trimmed:
                continue
            if include_completed or self._looks_like_partial(trimmed):
                candidates.add(trimmed)

        if include_completed and isinstance(job.main_file, str):
            trimmed_main = job.main_file.strip()
            if trimmed_main:
                candidates.add(trimmed_main)

        for raw_path in candidates:
            path = self._normalize_path(raw_path)
            if not path:
                continue
            try:
                if path.exists() and path.is_file():
                    path.unlink()
                    verbose_log(
                        "job_file_removed",
                        {"job_id": job.job_id, "path": str(path)},
                    )
                    normalized_str = str(path)
                    job.generated_files.discard(raw_path)
                    job.generated_files.discard(normalized_str)
                    partial_files.discard(raw_path)
                    partial_files.discard(normalized_str)
                    if isinstance(job.main_file, str):
                        candidate = job.main_file.strip()
                        if candidate and candidate in {raw_path, normalized_str}:
                            job.main_file = None
            except Exception as exc:  # noqa: BLE001 - best effort cleanup
                verbose_log(
                    "job_file_remove_failed",
                    {
                        "job_id": job.job_id,
                        "path": str(path),
                        "error": repr(exc),
                    },
                )

    def _cleanup_cancelled_job(self, job: DownloadJob) -> None:
        self._cleanup_job_files(job, include_completed=False)

    def _cleanup_before_delete(self, job: DownloadJob) -> None:
        status = (job.status or "").lower()
        if status == JobStatus.CANCELLED.value:
            self._cleanup_cancelled_job(job)
            return
        if status == JobStatus.FAILED.value:
            self._cleanup_job_files(job, include_completed=True)
            return
        if status == JobStatus.COMPLETED_WITH_ERRORS.value:
            self._cleanup_job_files(job, include_completed=False)
            return
        if status == JobStatus.COMPLETED.value:
            return
        self._cleanup_job_files(job, include_completed=True)

    def _should_auto_remove_cancelled_job(self, job: DownloadJob) -> bool:
        """Return ``True`` when a cancelled job can be removed immediately."""

        stage_value = job.progress.get("stage")
        stage = stage_value.strip().upper() if isinstance(stage_value, str) else ""
        if stage != DownloadStage.IDENTIFICANDO.value:
            return False

        if self._job_behaves_like_playlist(job):
            if job.playlist_completed_indices or job.playlist_failed_indices:
                return False
            if job.playlist_removed_indices:
                return False
            metadata = job.metadata or {}
            playlist_meta = metadata.get("playlist")
            entry_count = None
            if isinstance(playlist_meta, dict):
                entry_count = to_int(playlist_meta.get("entry_count"))
            if entry_count and entry_count > 0:
                return False

        if job.generated_files or job.partial_files:
            return False

        tmp_value = job.progress.get("tmpfilename")
        if isinstance(tmp_value, str) and tmp_value.strip():
            return False

        filename_value = job.progress.get("filename")
        if isinstance(filename_value, str) and filename_value.strip():
            return False

        main_file = job.main_file
        if isinstance(main_file, str) and main_file.strip():
            return False

        return True

    def _make_json_safe(
        self,
        value: JsonSafeValue | object,
        *,
        depth: int = 0,
    ) -> JsonSafeValue:
        if depth > 5:
            return None
        if value is None:
            return None
        if isinstance(value, (str, int, float, bool)):
            return value
        if isinstance(value, datetime):
            return value.isoformat() + "Z"
        if isinstance(value, dict):
            safe: JsonSafeDict = {}
            mapping_value = cast(Mapping[object, object], value)
            for key, item in mapping_value.items():
                key_str = str(key)
                safe_value = self._make_json_safe(item, depth=depth + 1)
                if safe_value is not None:
                    safe[key_str] = safe_value
            return safe
        if isinstance(value, (list, tuple, set)):
            sequence_value = cast(Iterable[object], value)
            items: list[JsonSafeValue] = []
            for item in sequence_value:
                safe_item = self._make_json_safe(item, depth=depth + 1)
                if safe_item is not None:
                    items.append(safe_item)
            return items
        return str(value)

    def _sanitize_mapping(self, value: object | None) -> Mapping[str, JSONValue]:
        sanitized = self._make_json_safe(value or {})
        if isinstance(sanitized, dict):
            return cast(Mapping[str, JSONValue], sanitized)
        return {}

    def _safe_metadata_payload(
        self, value: object | None
    ) -> DownloadJobMetadataPayload:
        sanitized = dict(self._sanitize_mapping(value))
        return cast(DownloadJobMetadataPayload, sanitized)

    def _safe_options_payload(self, value: object | None) -> DownloadJobOptionsPayload:
        return dict(self._sanitize_mapping(value))

    def _compact_options_preview(
        self,
        payload: DownloadJobOptionsPayload,
    ) -> DownloadJobOptionsPayload:
        if not payload:
            return {}
        try:
            serialized = json.dumps(payload, ensure_ascii=False)
        except Exception:
            serialized = ""
        if serialized and len(serialized) <= self.OPTION_PREVIEW_SERIALIZED_LIMIT:
            return payload
        preview: DownloadJobOptionsPayload = {}
        for key in self.OPTION_PREVIEW_KEYS:
            value = payload.get(key)
            if value is not None:
                preview[key] = value
        return preview

    def _safe_progress_payload(
        self, value: object | None
    ) -> DownloadJobProgressPayload:
        sanitized = dict(self._sanitize_mapping(value))
        return cast(DownloadJobProgressPayload, sanitized)

    @staticmethod
    def _as_dict(value: object | None) -> Optional[Dict[str, JSONValue]]:
        if isinstance(value, dict):
            return cast(Dict[str, JSONValue], value)
        return None

    @staticmethod
    def _clone_options_payload(
        payload: Optional[DownloadJobOptionsPayload],
    ) -> DownloadJobOptionsPayload:
        payload_dict = DownloadManager._as_dict(payload)
        if payload_dict is None:
            return {}
        cloned = clone_json_value(cast(JSONValue, payload_dict))
        if isinstance(cloned, dict):
            return cloned
        return {}

    @staticmethod
    def _clone_metadata_payload(
        payload: Optional[DownloadJobMetadataPayload],
    ) -> DownloadJobMetadataPayload:
        payload_dict = DownloadManager._as_dict(payload)
        if payload_dict is None:
            return {}
        cloned = clone_json_value(cast(JSONValue, payload_dict))
        if isinstance(cloned, dict):
            return cast(DownloadJobMetadataPayload, cloned)
        return {}

    def _export_playlist_entries(
        self,
        metadata: Optional[DownloadJobMetadataPayload],
    ) -> PlaylistEntryList:
        entries: PlaylistEntryList = []
        metadata_dict = self._as_dict(metadata)
        if metadata_dict is None:
            return entries
        metadata_payload = cast(DownloadJobMetadataPayload, metadata_dict)
        playlist_dict = self._as_dict(metadata_payload.get("playlist"))
        if playlist_dict is None:
            return entries
        playlist_meta = cast(PlaylistMetadataPayload, playlist_dict)
        raw_entries_obj: object | None = playlist_meta.get("entries")
        if not isinstance(raw_entries_obj, list):
            return entries
        raw_entries = cast(List[object], raw_entries_obj)
        selected_raw = playlist_meta.get("selected_indices")
        selected: Set[int] = set()
        if isinstance(selected_raw, list):
            for candidate in selected_raw:
                index_value = to_int(candidate)
                if index_value is not None and index_value > 0:
                    selected.add(index_value)
        for entry in raw_entries:
            entry_obj: object = entry
            if not isinstance(entry_obj, dict):
                continue
            entry_payload = cast(PlaylistEntryMetadataPayload, entry_obj)
            if selected and to_int(entry_payload.get("index")) not in selected:
                continue
            cloned_entry = clone_json_value(cast(JSONValue, entry_payload))
            if isinstance(cloned_entry, dict):
                compact_entry: Dict[str, JSONValue] = dict(cloned_entry)
                entries.append(compact_entry)
        return entries

    def _update_playlist_entries_version_locked(
        self,
        job: DownloadJob,
        version: Optional[int],
    ) -> None:
        metadata_dict = self._as_dict(job.metadata)
        if metadata_dict is not None:
            metadata = cast(DownloadJobMetadataPayload, metadata_dict)
        else:
            metadata = cast(DownloadJobMetadataPayload, {})
            job.metadata = metadata
        playlist_value: object | None = metadata.get("playlist")
        playlist_dict = self._as_dict(playlist_value)
        if playlist_dict is None:
            return
        playlist_payload: PlaylistMetadataPayload = cast(
            PlaylistMetadataPayload, playlist_dict
        )
        if version is None:
            playlist_payload.pop("entries_version", None)
            playlist_payload.pop("entries_external", None)
        else:
            playlist_payload["entries_version"] = version
            playlist_payload["entries_external"] = True

    def _sync_playlist_entries(
        self,
        job_id: str,
        *,
        metadata_snapshot: Optional[DownloadJobMetadataPayload] = None,
    ) -> Optional[int]:
        snapshot = metadata_snapshot
        with self.lock:
            job = self.jobs.get(job_id)
            if not job:
                return None
            if snapshot is None:
                snapshot = self._safe_metadata_payload(job.metadata)
        entries_payload = self._export_playlist_entries(snapshot)
        version: Optional[int]
        if entries_payload:
            version = self.playlist_entry_store.save(job_id, entries_payload)
        else:
            self.playlist_entry_store.delete(job_id)
            version = None
        with self.lock:
            job = self.jobs.get(job_id)
            if not job:
                return version
            job.playlist_entries_version = version
            self._update_playlist_entries_version_locked(job, version)
        return version

    def _restore_playlist_entries(self, job: DownloadJob) -> None:
        entries, stored_version = self.playlist_entry_store.load(job.job_id)
        if not entries:
            return
        metadata_dict = self._as_dict(job.metadata)
        if metadata_dict is not None:
            metadata = cast(DownloadJobMetadataPayload, metadata_dict)
        else:
            metadata = cast(DownloadJobMetadataPayload, {})
            job.metadata = metadata
        playlist_value: object | None = metadata.get("playlist")
        playlist_dict = self._as_dict(playlist_value)
        if playlist_dict is not None:
            playlist_payload = cast(PlaylistMetadataPayload, playlist_dict)
        else:
            playlist_payload = cast(PlaylistMetadataPayload, {})
            metadata["playlist"] = playlist_payload
        typed_entries: List[PlaylistEntryMetadataPayload] = [
            cast(PlaylistEntryMetadataPayload, dict(entry)) for entry in entries
        ]
        playlist_payload["entries"] = typed_entries
        version_value = stored_version or job.playlist_entries_version
        if version_value is not None:
            playlist_payload["entries_version"] = version_value
            playlist_payload["entries_external"] = True
            job.playlist_entries_version = version_value

    def _restore_job_options(
        self,
        job: DownloadJob,
        snapshot: Optional[DownloadPersistedState] = None,
    ) -> None:
        options_payload, stored_version = self.job_options_store.load(job.job_id)
        if options_payload:
            job.options = options_payload
            job.options_version = stored_version
            return
        fallback = snapshot.options if snapshot else {}
        if fallback:
            job.options = fallback
            version = self._store_job_options_payload(job.job_id, fallback)
            job.options_version = version
        else:
            job.options = {}
            job.options_version = stored_version

    def _restore_job_logs(
        self,
        job: DownloadJob,
        snapshot: Optional[DownloadPersistedState] = None,
    ) -> None:
        log_payload, stored_version = self.job_log_store.load(job.job_id)
        entries_loaded = False
        if log_payload:
            job.logs.clear()
            for entry_payload in log_payload:
                entry_dict = self._as_dict(entry_payload)
                if entry_dict is None:
                    continue
                try:
                    job.logs.append(
                        JobLogEntry.from_json(cast(JobLogEntryPayload, entry_dict))
                    )
                except ValueError:
                    continue
            job.logs_version = stored_version
            entries_loaded = True
        if entries_loaded:
            return
        fallback_entries = snapshot.logs if snapshot else []
        if fallback_entries:
            job.logs.clear()
            for entry in fallback_entries[-200:]:
                job.logs.append(entry)
            payload = [entry.to_json() for entry in list(job.logs)]
            version = self._store_job_logs_payload(job.job_id, payload)
            job.logs_version = version
        else:
            job.logs_version = stored_version

    def _build_delta_metadata(
        self,
        *,
        version: Optional[int],
        since_version: Optional[int],
        default_type: str = "full",
    ) -> Tuple[str, SnapshotDelta]:
        delta_type = default_type
        if (
            version is not None
            and since_version is not None
            and since_version == version
        ):
            delta_type = "noop"
        return (
            delta_type,
            {
                "type": delta_type,
                "version": version,
                "since": since_version,
            },
        )

    def build_job_options_snapshot(
        self,
        job_id: str,
        *,
        since_version: Optional[int] = None,
        include_options: bool = True,
    ) -> Optional[Dict[str, JSONValue]]:
        job = self.get_job(job_id)
        if not job:
            return None
        with self.lock:
            job_ref = self.jobs.get(job_id)
            if not job_ref:
                return None
            options_payload = self._safe_options_payload(job_ref.options)
            version = job_ref.options_version

        delta_type, delta_payload = self._build_delta_metadata(
            version=version,
            since_version=since_version,
        )

        include_payload = include_options or delta_type != "noop"
        response: Dict[str, JSONValue] = {
            "job_id": job_id,
            "version": version,
            "delta": cast(JSONValue, delta_payload),
        }
        if version is not None:
            response["external"] = True
        if include_payload:
            response["options"] = cast(JSONValue, options_payload)
        return response

    def build_job_logs_snapshot(
        self,
        job_id: str,
        *,
        since_version: Optional[int] = None,
        include_logs: bool = True,
        limit: Optional[int] = None,
    ) -> Optional[Dict[str, JSONValue]]:
        job = self.get_job(job_id)
        if not job:
            return None
        with self.lock:
            job_ref = self.jobs.get(job_id)
            if not job_ref:
                return None
            entries = list(job_ref.logs)
            if isinstance(limit, int) and limit > 0:
                entries = entries[-limit:]
            log_payload = [entry.to_json() for entry in entries]
            version = job_ref.logs_version

        delta_type, delta_payload = self._build_delta_metadata(
            version=version,
            since_version=since_version,
        )

        include_payload = include_logs or delta_type != "noop"
        response: Dict[str, JSONValue] = {
            "job_id": job_id,
            "version": version,
            "count": len(log_payload),
            "delta": cast(JSONValue, delta_payload),
        }
        if version is not None:
            response["external"] = True
        if include_payload:
            response["logs"] = cast(JSONValue, log_payload)
        return response

    def _store_job_options_payload(
        self,
        job_id: str,
        options_payload: DownloadJobOptionsPayload,
    ) -> Optional[int]:
        if options_payload:
            version = self.job_options_store.save(job_id, options_payload)
        else:
            self.job_options_store.delete(job_id)
            version = None
        with self.lock:
            job = self.jobs.get(job_id)
            if job:
                job.options_version = version
        return version

    def _sync_job_options(
        self,
        job_id: str,
        *,
        options_snapshot: Optional[DownloadJobOptionsPayload] = None,
    ) -> Optional[int]:
        payload = options_snapshot
        if payload is None:
            with self.lock:
                job = self.jobs.get(job_id)
                if not job:
                    return None
                payload = self._safe_options_payload(job.options)
        return self._store_job_options_payload(job_id, payload)

    def _store_job_logs_payload(
        self,
        job_id: str,
        log_payload: List[JobLogEntryPayload],
    ) -> Optional[int]:
        if log_payload:
            version = self.job_log_store.save(job_id, log_payload)
        else:
            self.job_log_store.delete(job_id)
            version = None
        with self.lock:
            job = self.jobs.get(job_id)
            if job:
                job.logs_version = version
        return version

    def _sync_job_logs(
        self,
        job_id: str,
        *,
        entries_snapshot: Optional[List[JobLogEntryPayload]] = None,
    ) -> Optional[int]:
        payload = entries_snapshot
        if payload is None:
            with self.lock:
                job = self.jobs.get(job_id)
                if not job:
                    return None
                payload = [entry.to_json() for entry in list(job.logs)]
        return self._store_job_logs_payload(job_id, payload)

    def __init__(self, socket_manager: SocketManager) -> None:
        self.socket_manager = socket_manager
        self.lock = threading.RLock()
        self.jobs: dict[str, DownloadJob] = {}
        self.core_manager = CoreManager()
        self.playlist_entry_store = PlaylistEntryStore(
            Path(DATA_FOLDER, "playlist_entries")
        )
        self.job_options_store = JobOptionsStore(Path(DATA_FOLDER, "job_options"))
        self.job_log_store = JobLogStore(Path(DATA_FOLDER, "job_logs"))
        self.state_store = DownloadStateStore(Path(DATA_FOLDER, "download_state.json"))
        self._restore_persisted_jobs()

    # ------------------------------------------------------------------
    # Public API expected by HTTP/WebSocket endpoints
    # ------------------------------------------------------------------
    def create_job(self, request: CreateJobRequest) -> DownloadJob:
        """Create a new download job and queue preview/worker threads.

        This is the entry point for inbound URLs coming from the HTTP API.
        The method normalizes user input, emits the initial IDENTIFICANDO
        stage for the UI, schedules the preview collector (which determines
        whether the URL is a playlist) and spawns the background worker that
        will wait for preview data and playlist selection before downloading.
        The preview workflow now emits websocket events ``GLOBAL_INFO``,
        ``ENTRY_INFO`` and ``LIST_INFO_ENDS`` so the client can render playlist
        metadata progressively before issuing playlist commands.
        """
        payload = request.clone()
        url_list = self._normalize_urls(payload.urls)
        if not url_list:
            raise ValueError("At least one URL is required")

        job_id = str(uuid.uuid4())
        job = DownloadJob(
            job_id=job_id,
            urls=url_list,
            options=payload.options,
            creator=payload.creator,
            metadata=payload.metadata,
        )
        job.created_at = _utc_now_naive()
        job.status = JobStatus.STARTING.value
        self._reset_job_events(job)

        with self.lock:
            self.jobs[job_id] = job

        self._store_progress(
            job_id,
            cast(
                DownloadJobProgressPayload,
                {
                    "status": JobStatus.STARTING.value,
                    "stage": DownloadStage.IDENTIFICANDO.value,
                    "stage_name": DownloadStage.IDENTIFICANDO.value,
                    "stage_percent": 0.0,
                    "percent": 0.0,
                    "message": "Identificando el contenido",
                },
            ),
        )

        self._persist_jobs()
        self.append_log(job_id, "info", "Trabajo creado")
        self._schedule_preview_collection(job_id, url_list, job.options)
        self.emit_job_update(job_id, reason=JobUpdateReason.CREATED.value)
        self.emit_overview()
        self._spawn_worker(job_id)
        return job

    def list_jobs(
        self,
        *,
        status: Optional[str] = None,
        owner: Optional[str] = None,
    ) -> List[DownloadJob]:
        with self.lock:
            jobs = list(self.jobs.values())
        if status:
            status_lower = status.lower()
            jobs = [job for job in jobs if job.status.lower() == status_lower]
        if owner:
            jobs = [job for job in jobs if job.creator == owner]
        jobs.sort(
            key=lambda job: job.created_at or datetime.min,
            reverse=False,
        )
        return jobs

    def get_job(self, job_id: str) -> Optional[DownloadJob]:
        with self.lock:
            return self.jobs.get(job_id)

    def cancel_job(self, job_id: str) -> Dict[str, JSONValue]:
        job = self.get_job(job_id)
        if not job:
            return {"job_id": job_id, "status": JobCommandStatus.NOT_FOUND.value}
        if job.status in COMPLETED_STATUSES:
            return {"job_id": job_id, "status": job.status}
        if job.status == JobStatus.CANCELLED.value:
            return {"job_id": job_id, "status": JobStatus.CANCELLED.value}

        if (
            job.selection_required
            and not job.selection_event.is_set()
            and job.status in {JobStatus.STARTING.value, JobStatus.QUEUED.value}
        ):
            job.cancel_event.set()
            job.pause_event.set()
            preview_event = getattr(job, "preview_ready_event", None)
            if isinstance(preview_event, threading.Event):
                preview_event.set()
            job.selection_event.set()
            self._finalize_job(
                job_id,
                status=JobStatus.CANCELLED.value,
                error=None,
            )
            return self.delete_job(job_id)

        if job.status in CANCEL_IMMEDIATE_STATUSES:
            job.cancel_event.set()
            self._finalize_job(job_id, status=JobStatus.CANCELLED.value, error=None)
            self._persist_jobs()
            return {"job_id": job_id, "status": JobStatus.CANCELLED.value}

        job.cancel_event.set()
        self._abort_controller(job)
        with self.lock:
            if job.status not in {JobStatus.PAUSING.value, JobStatus.PAUSED.value}:
                job.status = JobStatus.CANCELLING.value
        self.append_log(job_id, "info", "Cancelando trabajo")
        self.emit_job_update(job_id, reason=JobUpdateReason.CANCELLING.value)
        self.emit_overview()
        self._persist_jobs()
        return {"job_id": job_id, "status": JobStatus.CANCELLING.value}

    def cancel_jobs(self, job_ids: Iterable[str]) -> List[Dict[str, JSONValue]]:
        return [self.cancel_job(job_id) for job_id in job_ids]

    def cancel_all(self, *, owner: Optional[str] = None) -> List[Dict[str, JSONValue]]:
        with self.lock:
            if owner is None:
                job_ids = list(self.jobs.keys())
            else:
                job_ids = [
                    job_id for job_id, job in self.jobs.items() if job.creator == owner
                ]
        return [self.cancel_job(job_id) for job_id in job_ids]

    def pause_job(self, job_id: str) -> Dict[str, JSONValue]:
        job = self.get_job(job_id)
        if not job:
            return {"job_id": job_id, "status": JobCommandStatus.NOT_FOUND.value}
        if job.status in TERMINAL_STATUSES:
            return {"job_id": job_id, "status": job.status}
        if job.status == JobStatus.PAUSED.value:
            return {"job_id": job_id, "status": JobStatus.PAUSED.value}
        if job.status not in PAUSE_ELIGIBLE_STATUSES:
            return {"job_id": job_id, "status": job.status}

        job.pause_event.set()
        self._abort_controller(job)
        with self.lock:
            job.status = JobStatus.PAUSING.value
        self.append_log(job_id, "info", "Pausando trabajo")
        self.emit_job_update(job_id, reason=JobUpdateReason.PAUSING.value)
        self.emit_overview()
        self._persist_jobs()
        return {"job_id": job_id, "status": JobStatus.PAUSING.value}

    def resume_job(self, job_id: str) -> Dict[str, JSONValue]:
        job = self.get_job(job_id)
        if not job:
            return {"job_id": job_id, "status": JobCommandStatus.NOT_FOUND.value}
        if job.status not in RESUMABLE_STATUSES:
            return {"job_id": job_id, "status": job.status}

        previous_status = job.status
        job.pause_event.clear()
        job.cancel_event.clear()
        job.resume_requested = True
        resume_candidate = self._locate_resume_path(job)
        with self.lock:
            job.status = JobStatus.QUEUED.value
            job.finished_at = None
            job.error = None
            job.preview_error = None
        if previous_status == JobStatus.FAILED.value and not resume_candidate:
            self.append_log(
                job_id,
                "warning",
                "No se encontraron archivos parciales; la descarga se reiniciará",
            )
        message = (
            "Reanudando trabajo" if resume_candidate else "Iniciando trabajo nuevamente"
        )
        self.append_log(job_id, "info", message)
        self._persist_jobs()
        self._spawn_worker(job_id)
        self.emit_job_update(job_id, reason=JobUpdateReason.RESUMED.value)
        self.emit_overview()
        return {"job_id": job_id, "status": JobStatus.RUNNING.value}

    def retry_job(self, job_id: str) -> Dict[str, JSONValue]:
        job = self.get_job(job_id)
        if not job:
            return {"job_id": job_id, "status": JobCommandStatus.NOT_FOUND.value}
        if job.status in ACTIVE_STATUSES or job.status == JobStatus.QUEUED.value:
            return {"job_id": job_id, "status": job.status}

        job.cancel_event.clear()
        job.pause_event.clear()
        with self.lock:
            job.status = JobStatus.QUEUED.value
            job.error = None
            job.finished_at = None
            job.progress = cast(DownloadJobProgressPayload, {})
            job.preview_error = None
            job.playlist_completed_indices.clear()
            job.playlist_failed_indices.clear()
            job.playlist_pending_indices.clear()
            job.playlist_removed_indices.clear()
            job.playlist_entry_errors.clear()
            job.playlist_total_items = None
        self._cleanup_before_delete(job)
        job.generated_files.clear()
        job.partial_files.clear()
        job.main_file = None
        self.append_log(job_id, "info", "Reintentando trabajo")
        self._spawn_worker(job_id)
        self.emit_job_update(job_id, reason=JobUpdateReason.RETRY.value)
        self.emit_overview()
        return {"job_id": job_id, "status": JobStatus.QUEUED.value}

    def retry_playlist_entries(
        self,
        job_id: str,
        *,
        indices: Optional[Iterable[int]] = None,
        entry_ids: Optional[Iterable[str]] = None,
    ) -> Dict[str, JSONValue]:
        job = self.get_job(job_id)
        if not job:
            return {"job_id": job_id, "status": JobCommandStatus.NOT_FOUND.value}

        if not self._job_behaves_like_playlist(job):
            return {
                "job_id": job_id,
                "status": JobCommandStatus.NOT_PLAYLIST.value,
                "reason": JobCommandReason.JOB_IS_NOT_PLAYLIST.value,
            }

        if job.status not in TERMINAL_STATUSES:
            return {"job_id": job_id, "status": job.status}

        pending_targets: Set[int] = set()
        if indices:
            for index in indices:
                if index > 0:
                    pending_targets.add(index)
        if entry_ids:
            for entry_id in entry_ids:
                if not entry_id:
                    continue
                normalized = entry_id.strip()
                if not normalized:
                    continue
                resolved_index = self.resolve_playlist_index_from_entry_id(
                    job, normalized
                )
                if resolved_index and resolved_index > 0:
                    pending_targets.add(resolved_index)

        if not pending_targets:
            return {
                "job_id": job_id,
                "status": JobCommandStatus.NO_ENTRIES.value,
                "reason": JobCommandReason.PLAYLIST_ENTRIES_REQUIRED.value,
            }

        failed_candidates = {
            index for index in job.playlist_failed_indices if index > 0
        }
        if not failed_candidates and job.playlist_entry_errors:
            failed_candidates.update(
                index for index in job.playlist_entry_errors.keys() if index > 0
            )
        if failed_candidates:
            pending_targets.intersection_update(failed_candidates)

        if not pending_targets:
            return {
                "job_id": job_id,
                "status": JobCommandStatus.ENTRIES_NOT_FAILED.value,
                "reason": JobCommandReason.ENTRIES_NOT_FAILED.value,
            }

        job.playlist_pending_indices.update(pending_targets)
        job.cancel_event.clear()
        job.pause_event.clear()
        job.resume_requested = False

        selection_spec = self._format_playlist_selection(sorted(pending_targets))
        retry_count = len(pending_targets)
        retry_message = (
            "Reintentando una entrada fallida de la lista"
            if retry_count == 1
            else f"Reintentando {retry_count} entradas fallidas de la lista"
        )

        with self.lock:
            job.status = JobStatus.QUEUED.value
            job.error = None
            job.finished_at = None
            job.progress = cast(
                DownloadJobProgressPayload,
                {
                    "status": JobStatus.RETRYING.value,
                    "stage": DownloadStage.IDENTIFICANDO.value,
                    "stage_name": DownloadStage.IDENTIFICANDO.value,
                    "percent": 0.0,
                    "stage_percent": 0.0,
                    "message": retry_message,
                },
            )

        self.append_log(job_id, "info", retry_message)
        self._persist_jobs()
        self._spawn_worker(job_id)
        self.emit_job_update(job_id, reason=JobUpdateReason.RETRY.value)
        self.emit_overview()
        pending_list = [int(index) for index in sorted(pending_targets)]
        response: Dict[str, JSONValue] = {
            "job_id": job_id,
            "status": JobStatus.QUEUED.value,
            "pending_indices": cast(JSONValue, pending_list),
        }
        if selection_spec:
            response["selection"] = selection_spec
        return response

    def delete_playlist_entries(
        self,
        job_id: str,
        *,
        indices: Optional[Iterable[int]] = None,
        entry_ids: Optional[Iterable[str]] = None,
    ) -> Dict[str, JSONValue]:
        job = self.get_job(job_id)
        if not job:
            return {"job_id": job_id, "status": JobCommandStatus.NOT_FOUND.value}

        if not self._job_behaves_like_playlist(job):
            return {
                "job_id": job_id,
                "status": JobCommandStatus.NOT_PLAYLIST.value,
                "reason": JobCommandReason.JOB_IS_NOT_PLAYLIST.value,
            }

        if job.status not in TERMINAL_STATUSES:
            return {"job_id": job_id, "status": job.status}

        target_indices: Set[int] = set()
        invalid_indices: Set[int] = set()
        if indices:
            for index in indices:
                if index <= 0:
                    invalid_indices.add(index)
                    continue
                target_indices.add(index)

        missing_entry_ids: List[str] = []
        if entry_ids:
            for entry_id in entry_ids:
                if not entry_id:
                    continue
                normalized = entry_id.strip()
                if not normalized:
                    continue
                resolved_index = self.resolve_playlist_index_from_entry_id(
                    job,
                    normalized,
                )
                if resolved_index and resolved_index > 0:
                    target_indices.add(resolved_index)
                else:
                    missing_entry_ids.append(normalized)

        if not target_indices:
            return {
                "job_id": job_id,
                "status": JobCommandStatus.NO_ENTRIES.value,
                "reason": JobCommandReason.PLAYLIST_ENTRIES_REQUIRED.value,
            }

        new_removals = {
            index
            for index in target_indices
            if index not in job.playlist_removed_indices
        }
        if not new_removals:
            response: Dict[str, JSONValue] = {
                "job_id": job_id,
                "status": JobCommandStatus.ENTRIES_ALREADY_REMOVED.value,
                "removed_indices": cast(JSONValue, sorted(target_indices)),
            }
            if missing_entry_ids:
                response["missing_entry_ids"] = cast(JSONValue, missing_entry_ids)
            if invalid_indices:
                response["invalid_indices"] = cast(JSONValue, sorted(invalid_indices))
            return response

        newly_removed_list = sorted(new_removals)
        status_transition = False

        with self.lock:
            job_snapshot = self.jobs.get(job_id)
            if job_snapshot is None:
                return {"job_id": job_id, "status": JobCommandStatus.NOT_FOUND.value}
            for index in new_removals:
                job_snapshot.playlist_completed_indices.discard(index)
                self._clear_playlist_entry_failure(job_snapshot, index)
                job_snapshot.playlist_removed_indices.add(index)
            if (
                job_snapshot.status == JobStatus.COMPLETED_WITH_ERRORS.value
                and not job_snapshot.playlist_failed_indices
                and not job_snapshot.playlist_entry_errors
            ):
                job_snapshot.status = JobStatus.COMPLETED.value
                job_snapshot.error = None
                job_snapshot.progress.setdefault("status", JobStatus.COMPLETED.value)
                job_snapshot.progress.setdefault("stage", DownloadStage.COMPLETED.value)
                job_snapshot.progress.setdefault(
                    "stage_name", DownloadStage.COMPLETED.value
                )
                job_snapshot.progress.setdefault("percent", 100.0)
                job_snapshot.progress.setdefault("stage_percent", 100.0)
                status_transition = True

        removed_payload = cast(JSONValue, newly_removed_list)
        response = {
            "job_id": job_id,
            "status": JobCommandStatus.ENTRIES_REMOVED.value,
            "removed_indices": removed_payload,
        }
        if missing_entry_ids:
            response["missing_entry_ids"] = cast(JSONValue, missing_entry_ids)
        if invalid_indices:
            response["invalid_indices"] = cast(JSONValue, sorted(invalid_indices))
        if status_transition:
            response["job_status"] = JobStatus.COMPLETED.value

        entry_word = "entrada" if len(newly_removed_list) == 1 else "entradas"
        self.append_log(
            job_id,
            "info",
            f"{len(newly_removed_list)} {entry_word} de la lista fueron eliminadas",
        )
        self._persist_jobs()
        self.emit_job_update(job_id, reason=JobUpdateReason.UPDATED.value)
        self.emit_overview()
        return response

    def delete_job(self, job_id: str) -> Dict[str, JSONValue]:
        with self.lock:
            job = self.jobs.get(job_id)
            if not job:
                return {"job_id": job_id, "status": JobCommandStatus.NOT_FOUND.value}
            if job.status not in TERMINAL_STATUSES:
                return {
                    "job_id": job_id,
                    "status": JobCommandStatus.JOB_ACTIVE.value,
                }
            previous_status = job.status
            self.jobs.pop(job_id)

        self._cleanup_before_delete(job)
        job.generated_files.clear()
        job.partial_files.clear()
        job.main_file = None
        self.playlist_entry_store.delete(job_id)
        self.job_options_store.delete(job_id)
        self.job_log_store.delete(job_id)

        payload: Dict[str, JSONValue] = {
            "job_id": job_id,
            "status": JobCommandStatus.DELETED.value,
            "previous_status": previous_status,
            "reason": JobCommandReason.DELETED.value,
            "timestamp": now_iso(),
        }
        self._persist_jobs()
        self._broadcast_update(payload)
        self.emit_overview()
        return {
            "job_id": job_id,
            "status": JobCommandStatus.DELETED.value,
            "reason": JobCommandReason.DELETED.value,
        }

    def apply_playlist_selection(
        self,
        job_id: str,
        *,
        indices: Optional[Iterable[int]],
    ) -> Dict[str, JSONValue]:
        """Persist user-selected playlist indices and resume the job.

        Called once the frontend displays the playlist modal (triggered by the
        preview collector). It stores the selection in job options, clears the
        ``selection_required`` flag, and if the worker thread was waiting it is
        re-queued so the download flow can proceed with the chosen entries.
        """
        job = self.get_job(job_id)
        if not job:
            return {"job_id": job_id, "status": JobCommandStatus.NOT_FOUND.value}

        if job.status in TERMINAL_STATUSES:
            return {
                "job_id": job_id,
                "status": job.status,
                "reason": JobCommandReason.JOB_TERMINATED.value,
            }

        raw_indices = list(indices or [])
        formatted_spec = self._format_playlist_selection(raw_indices)
        sorted_indices = sorted({index for index in raw_indices if index > 0})

        spawn_worker = False
        with self.lock:
            job = self.jobs.get(job_id)
            if not job:
                return {
                    "job_id": job_id,
                    "status": JobCommandStatus.NOT_FOUND.value,
                }

            if not getattr(job, "selection_required", False):
                selection_event = getattr(job, "selection_event", None)
                if (
                    isinstance(selection_event, threading.Event)
                    and selection_event.is_set()
                ):
                    options = job.options
                    current_spec = options.get("playlist_items")
                    return {
                        "job_id": job_id,
                        "status": job.status,
                        "selection": current_spec or "all",
                        "reason": JobCommandReason.PLAYLIST_SELECTION_LOCKED.value,
                    }

            options = job.options
            if formatted_spec:
                options["playlist_items"] = formatted_spec
            else:
                options.pop("playlist_items", None)
            job.options = options

            metadata = job.metadata
            playlist_value: object | None = metadata.get("playlist")
            playlist_dict = self._as_dict(playlist_value)
            if playlist_dict is not None:
                playlist_meta = cast(PlaylistMetadataPayload, playlist_dict)
                if sorted_indices:
                    playlist_meta["selected_indices"] = list(sorted_indices)
                else:
                    playlist_meta.pop("selected_indices", None)
                entries_raw: object | None = playlist_meta.get("entries")
                filtered_entries: Optional[List[PlaylistEntryMetadataPayload]] = None
                entries_payload: List[object] = []
                if isinstance(entries_raw, list):
                    entries_payload = cast(List[object], entries_raw)
                    if sorted_indices:
                        selected_set = {index for index in sorted_indices}
                        filtered_entries = []
                        for entry in entries_payload:
                            entry_candidate: object = entry
                            if not isinstance(entry_candidate, Mapping):
                                continue
                            entry_mapping = cast(
                                Mapping[str, JSONValue], entry_candidate
                            )
                            index_value = to_int(entry_mapping.get("index"))
                            if index_value is not None and index_value in selected_set:
                                filtered_entries.append(
                                    cast(
                                        PlaylistEntryMetadataPayload,
                                        dict(entry_mapping),
                                    )
                                )
                        playlist_meta["entries"] = filtered_entries
                    else:
                        playlist_meta["entries"] = cast(
                            List[PlaylistEntryMetadataPayload],
                            [],
                        )
                received_count = to_int(playlist_meta.get("received_count"))
                original_entries_len = len(entries_payload)
                collection_complete_flag = bool(
                    to_bool(playlist_meta.get("collection_complete"))
                )
                if sorted_indices:
                    selected_count = len(sorted_indices)
                    resolved_received = len(filtered_entries or [])
                    if resolved_received == 0 and original_entries_len > 0:
                        resolved_received = min(original_entries_len, selected_count)
                    playlist_meta["received_count"] = max(
                        resolved_received,
                        selected_count,
                        received_count or 0,
                    )
                    playlist_meta["entry_count"] = selected_count
                    playlist_meta["total_items"] = selected_count
                    playlist_meta["collection_complete"] = True
                    playlist_meta["has_indefinite_length"] = False
                    collection_complete_flag = True
                elif original_entries_len > 0:
                    playlist_meta["received_count"] = max(
                        original_entries_len,
                        received_count or 0,
                    )
                if sorted_indices:
                    job.playlist_total_items = len(sorted_indices)
                else:
                    entry_count = to_int(playlist_meta.get("entry_count"))
                    if entry_count is not None and entry_count > 0:
                        job.playlist_total_items = entry_count
                if collection_complete_flag:
                    playlist_meta["is_collecting_entries"] = False
            metadata["requires_playlist_selection"] = False

            job.selection_required = False
            job.selection_event.set()

            thread_obj = (
                job.thread if isinstance(job.thread, threading.Thread) else None
            )
            thread_alive = thread_obj.is_alive() if thread_obj else False
            if not thread_alive:
                job.thread = None
                job.status = JobStatus.QUEUED.value
                job.started_at = None
                job.finished_at = None
                spawn_worker = True

        self._store_progress(
            job_id,
            cast(
                DownloadJobProgressPayload,
                {
                    "status": JobStatus.STARTING.value,
                    "stage": DownloadStage.IDENTIFICANDO.value,
                    "stage_name": DownloadStage.IDENTIFICANDO.value,
                    "message": "Selección de la lista de reproducción recibida",
                },
            ),
        )

        self._sync_playlist_entries(job_id)
        self._persist_jobs()
        self.emit_job_update(job_id, reason=JobUpdateReason.UPDATED.value)
        self.emit_overview()

        if spawn_worker:
            self._spawn_worker(job_id)

        return {
            "job_id": job_id,
            "status": job.status,
            "selection": formatted_spec or "all",
        }

    def get_job_logs(self, job_id: str) -> Optional[List[JobLogEntryPayload]]:
        job = self.get_job(job_id)
        if not job:
            return None
        with self.lock:
            return [entry.to_json() for entry in job.logs]

    def overview_snapshot(self) -> Dict[str, JSONValue]:
        with self.lock:
            jobs = list(self.jobs.values())
        return {"summary": self._build_overview_summary(jobs)}

    def serialize_job(
        self, job: DownloadJob, *, detail: bool = False
    ) -> Dict[str, JSONValue]:
        payload: Dict[str, JSONValue] = {
            "job_id": job.job_id,
            "status": job.status,
            "kind": self._normalize_job_kind_value(job.kind),
            "creator": job.creator,
            "created_at": job.created_at.isoformat() + "Z",
            "started_at": job.started_at.isoformat() + "Z" if job.started_at else None,
            "finished_at": job.finished_at.isoformat() + "Z"
            if job.finished_at
            else None,
            "error": job.error,
        }

        progress_payload = self._safe_progress_payload(job.progress)
        payload["progress"] = (
            cast(JSONValue, progress_payload) if progress_payload else None
        )

        metadata_payload = metadata_public_view(
            job.metadata,
            include_playlist_entries=bool(job.selection_required),
        )
        if job.selection_required:
            metadata_payload.setdefault("requires_playlist_selection", True)
        if metadata_payload:
            payload["metadata"] = cast(JSONValue, metadata_payload)

        preview = self._build_preview_payload(job)
        if preview:
            payload["preview"] = cast(JSONValue, preview)

        playlist_snapshot = self.build_playlist_snapshot(
            job.job_id,
            include_entries=detail,
            include_entry_progress=detail,
        )
        if playlist_snapshot:
            playlist_payload = playlist_snapshot.get("playlist")
            if playlist_payload:
                payload["playlist"] = cast(JSONValue, playlist_payload)

        failed_indices = sorted(
            index for index in job.playlist_failed_indices if index > 0
        )
        if failed_indices:
            payload["playlist_failed_indices"] = cast(JSONValue, failed_indices)

        pending_indices = sorted(
            index for index in job.playlist_pending_indices if index > 0
        )
        if pending_indices:
            payload["playlist_pending_indices"] = cast(JSONValue, pending_indices)

        removed_indices = sorted(
            index for index in job.playlist_removed_indices if index > 0
        )
        if removed_indices:
            payload["playlist_removed_indices"] = cast(JSONValue, removed_indices)

        if detail and job.playlist_entry_errors:
            payload["playlist_entry_errors"] = cast(
                JSONValue,
                [
                    job.playlist_entry_errors[index].to_json()
                    for index in sorted(job.playlist_entry_errors)
                ],
            )

        if job.selection_required and not job.selection_event.is_set():
            payload["status_hint"] = "waiting_user_confirmation"
        elif (
            getattr(job, "has_error_logs", False)
            and job.status not in TERMINAL_STATUSES
        ):
            payload["status_hint"] = "running_with_errors"

        if detail:
            payload["urls"] = cast(JSONValue, list(job.urls))
            payload["options"] = cast(
                JSONValue, self._safe_options_payload(job.options)
            )
            if "metadata" not in payload and job.metadata:
                payload["metadata"] = cast(
                    JSONValue, self._safe_metadata_payload(job.metadata)
                )
            payload["logs"] = cast(JSONValue, [entry.to_json() for entry in job.logs])
        else:
            payload["options_external"] = True
            payload["logs_external"] = True

        if job.options_version is not None:
            payload["options_version"] = job.options_version
            payload["options_external"] = True
        if job.logs_version is not None:
            payload["logs_version"] = job.logs_version
            payload["logs_external"] = True

        include_file_lists = detail
        if include_file_lists:
            generated_files = sorted(
                {path.strip() for path in job.generated_files if path.strip()}
            )
            if generated_files:
                payload["generated_files"] = cast(JSONValue, list(generated_files))
            partial_files = sorted(
                {path.strip() for path in job.partial_files if path.strip()}
            )
            if partial_files:
                payload["partial_files"] = cast(JSONValue, list(partial_files))

        if isinstance(job.main_file, str):
            main_file_value = job.main_file.strip()
            if main_file_value:
                payload["main_file"] = main_file_value

        return {key: value for key, value in payload.items() if value is not None}

    def build_playlist_entries_delta(
        self,
        job_id: str,
        *,
        since_version: Optional[int] = None,
    ) -> Optional[Dict[str, JSONValue]]:
        job = self.get_job(job_id)
        if not job:
            return None
        selected_indices = self._resolve_selected_playlist_indices(job)
        snapshot = self.build_playlist_snapshot(
            job_id,
            include_entries=False,
            include_entry_progress=False,
        )
        if not snapshot:
            return None
        playlist_value: object | None = snapshot.get("playlist")
        if not isinstance(playlist_value, dict):
            return None
        playlist_payload = cast(Dict[str, JSONValue], playlist_value)

        entries, stored_version = self.playlist_entry_store.load(job_id)
        if not entries:
            metadata_snapshot = self._safe_metadata_payload(job.metadata)
            entries = self._export_playlist_entries(metadata_snapshot)
            if entries:
                stored_version = self._sync_playlist_entries(
                    job_id, metadata_snapshot=metadata_snapshot
                )
                entries, stored_version = self.playlist_entry_store.load(job_id)

        if selected_indices and entries:
            selected_set = {index for index in selected_indices}
            filtered_entries: PlaylistEntryList = []
            for entry in entries:
                entry_dict = self._as_dict(entry)
                if entry_dict is None:
                    continue
                entry_mapping = cast(Mapping[str, JSONValue], entry_dict)
                candidate_index = to_int(entry_mapping.get("index"))
                if candidate_index is None or candidate_index not in selected_set:
                    continue
                filtered_entries.append(dict(entry_mapping))
            entries = filtered_entries

        version = stored_version or job.playlist_entries_version
        if version is not None:
            playlist_payload["entries_version"] = version
            playlist_payload["entries_external"] = True

        delta_type = "reset"
        if (
            version is not None
            and since_version is not None
            and version == since_version
        ):
            delta_type = "noop"
        else:
            delta_type = "full" if since_version is None else "reset"
            playlist_payload["entries"] = [
                cast(JSONValue, dict(entry)) for entry in entries
            ]

        response: Dict[str, JSONValue] = {
            "job_id": job_id,
            "status": snapshot.get("status"),
            "playlist": cast(JSONValue, playlist_payload),
            "version": version,
            "delta": {
                "type": delta_type,
                "version": version,
                "since": since_version,
            },
        }
        if delta_type == "noop":
            playlist_payload.pop("entries", None)
        return response

    def emit_job_update(
        self, job_id: str, *, reason: str = JobUpdateReason.UPDATED.value
    ) -> None:
        job = self.get_job(job_id)
        if not job:
            return
        payload = self.serialize_job(job, detail=False)
        payload["reason"] = reason
        payload["timestamp"] = now_iso()
        self._broadcast_update(payload)

    def emit_overview(self) -> None:
        snapshot = self.overview_snapshot()
        snapshot["timestamp"] = now_iso()
        self._emit_socket(SocketEvent.OVERVIEW.value, snapshot, room=self.OVERVIEW_ROOM)

    def preview_cli(
        self,
        urls: Union[str, Iterable[str]],
        options: Optional[Dict[str, JSONValue]] = None,
    ) -> List[str]:
        url_list = self._normalize_urls(urls)
        if not url_list:
            return []
        options_config = build_options_config(options)
        resolved = resolve_options(url_list, options=options_config, download=True)
        return resolved.cli_args

    def preview_metadata(
        self,
        urls: Union[str, Iterable[str]],
        options: Optional[DownloadJobOptionsPayload] = None,
    ) -> Optional[PreviewMetadataPayload]:
        url_list = self._normalize_urls(urls)
        if not url_list:
            return None
        return self._collect_preview_metadata(url_list, options)

    # ------------------------------------------------------------------
    # Helper methods reused by mixins / worker threads
    # ------------------------------------------------------------------
    def _build_cli_args(self, job: DownloadJob) -> List[str]:
        option_copy: DownloadJobOptionsPayload = dict(job.options or {})
        self._prepare_resume_options(job, option_copy)
        return self._build_cli_args_from(job.urls, option_copy)

    def append_log(self, job_id: str, level: str, message: str) -> None:
        text = str(message)
        sanitized = strip_ansi(text)
        if sanitized is not None:
            text = sanitized
        entry = JobLogEntry(timestamp=now_iso(), level=level, message=text)
        flush_required = False
        now_ts = time.time()
        playlist_error_logged = False
        error_logged_transition = False
        with self.lock:
            job = self.jobs.get(job_id)
            if not job:
                return
            playlist_index = job.active_playlist_log_index
            playlist_entry_id = job.active_playlist_log_entry_id
            if playlist_index is not None:
                entry.playlist_index = playlist_index
            if playlist_entry_id:
                entry.playlist_entry_id = playlist_entry_id
            job.logs.append(entry)
            last_flush = getattr(job, "log_persist_at", 0.0)
            normalized_level = str(level or "").lower()
            error_level = normalized_level in {"error", "stderr"}
            if error_level:
                if not getattr(job, "has_error_logs", False):
                    job.has_error_logs = True
                    error_logged_transition = True
                    if job.status not in COMPLETED_STATUSES:
                        state_value = str(job.progress.get("state") or "").lower()
                        if state_value != "running_with_errors":
                            job.progress["state"] = "running_with_errors"
                flush_required = True
            elif normalized_level == "warning":
                flush_required = True
            elif now_ts - last_flush >= 1.0:
                flush_required = True
            if flush_required:
                job.log_persist_at = now_ts
            if error_level and playlist_index is not None and playlist_index > 0:
                playlist_error_logged = self._record_playlist_entry_log_error(
                    job,
                    index=playlist_index,
                    entry_id=playlist_entry_id,
                    message=text,
                    timestamp=entry.timestamp,
                )
        serialized = entry.to_json()
        serialized_payload = cast(Dict[str, JSONValue], serialized)
        log_payload: Dict[str, JSONValue] = {"job_id": job_id}
        log_payload.update(serialized_payload)
        verbose_log("job_log", log_payload)
        self._emit_socket(
            SocketEvent.LOG.value,
            log_payload,
            room=self.job_room(job_id),
        )
        if flush_required:
            self._sync_job_logs(job_id)
        if playlist_error_logged:
            snapshot = self.build_playlist_snapshot(
                job_id,
                include_entries=False,
                include_entry_progress=False,
            )
            if snapshot:
                self.emit_socket(
                    SocketEvent.PLAYLIST_SNAPSHOT.value,
                    cast(JSONValue, snapshot),
                    room=self.job_room(job_id),
                )
            self.emit_job_update(job_id, reason=JobUpdateReason.UPDATED.value)
        elif error_logged_transition:
            self.emit_job_update(job_id, reason=JobUpdateReason.UPDATED.value)

    def job_room(self, job_id: str) -> str:
        return SocketRoom.for_job(job_id)

    def _broadcast_update(self, payload: Dict[str, JSONValue]) -> None:
        job_id_value = payload.get("job_id")
        job_id = job_id_value if isinstance(job_id_value, str) else None
        overview_payload: Dict[str, JSONValue] = payload
        if job_id:
            job = self.get_job(job_id)
            if job:
                overview_payload = self.serialize_job(job, detail=False)
                for key in ("reason", "timestamp", "selection", "status_hint"):
                    if key in payload and key not in overview_payload:
                        overview_payload[key] = payload[key]
        self._emit_socket(
            SocketEvent.UPDATE.value,
            overview_payload,
            room=self.OVERVIEW_ROOM,
        )
        if job_id:
            self._emit_socket(
                SocketEvent.UPDATE.value, payload, room=self.job_room(job_id)
            )

    def broadcast_update(self, payload: Dict[str, JSONValue]) -> None:
        self._broadcast_update(payload)

    def _emit_socket(
        self,
        event: str,
        payload: JSONValue,
        *,
        room: Optional[str] = None,
    ) -> None:
        manager = getattr(self, "socket_manager", None)
        if manager is None:
            return
        try:
            if not manager.has_subscribers(room):
                return
            manager.emit(event, payload, room=room)
        except Exception as exc:  # noqa: BLE001 - avoid breaking the download pipeline on socket issues
            verbose_log(
                "socket_emit_failed", {"event": event, "room": room, "error": repr(exc)}
            )

    def emit_socket(
        self,
        event: str,
        payload: JSONValue,
        *,
        room: Optional[str] = None,
    ) -> None:
        self._emit_socket(event, payload, room=room)

    def _spawn_worker(self, job_id: str) -> None:
        thread = threading.Thread(
            target=self._run_download,
            args=(job_id,),
            name=f"download-{job_id}",
            daemon=True,
        )
        with self.lock:
            job = self.jobs.get(job_id)
            if not job:
                return
            job.thread = thread
        thread.start()

    def _prepare_resume_options(
        self,
        job: DownloadJob,
        options: DownloadJobOptionsPayload,
    ) -> None:
        self._apply_playlist_pending_selection(job, options)
        if not self._should_attempt_resume(job):
            job.resume_requested = False
            return

        resume_path = self._locate_resume_path(job)
        if not resume_path:
            job.resume_requested = False
            return

        previous_force_overwrites = options.get("force_overwrites")
        options["force_overwrites"] = False
        self._apply_playlist_resume_hint(job, options)
        job.resume_requested = False

        verbose_log(
            "resume_prepare",
            {
                "job_id": job.job_id,
                "resume_path": str(resume_path),
                "previous_force_overwrites": previous_force_overwrites,
            },
        )

    def _apply_playlist_pending_selection(
        self,
        job: DownloadJob,
        options: DownloadJobOptionsPayload,
    ) -> None:
        pending = sorted(index for index in job.playlist_pending_indices if index > 0)
        if not pending:
            return
        new_spec = self._format_playlist_selection(pending)
        if not new_spec:
            return
        options["playlist_items"] = new_spec
        verbose_log(
            "pending_playlist_items",
            {
                "job_id": job.job_id,
                "pending_indices": pending,
                "applied_spec": new_spec,
            },
        )

    def _should_attempt_resume(self, job: DownloadJob) -> bool:
        if job.resume_requested:
            return True
        progress_status = str(job.progress.get("status") or "").lower()
        return progress_status in {
            JobStatus.PAUSED.value,
            JobStatus.PAUSING.value,
        }

    def _locate_resume_path(self, job: DownloadJob) -> Optional[Path]:
        progress = job.progress

        candidates: List[Path] = []
        tmp_value = progress.get("tmpfilename")
        if isinstance(tmp_value, str) and tmp_value.strip():
            candidates.append(Path(tmp_value.strip()))

        filename_value = progress.get("filename")
        if isinstance(filename_value, str) and filename_value.strip():
            filename_path = Path(filename_value.strip())
            candidates.append(filename_path)
            candidates.append(Path(f"{filename_value.strip()}.part"))

        for candidate in candidates:
            try:
                if candidate.exists():
                    return candidate
            except OSError:
                continue

        return None

    # ------------------------------------------------------------------
    # Playlist resume helpers
    # ------------------------------------------------------------------
    def _apply_playlist_resume_hint(
        self,
        job: DownloadJob,
        options: DownloadJobOptionsPayload,
    ) -> None:
        if job.playlist_pending_indices:
            return
        playlist_enabled = options.get("playlist")
        if playlist_enabled is False:
            return

        resume_index = self._resolve_resume_start_index(job)
        if resume_index is None or resume_index <= 0:
            return

        total_items = self._resolve_playlist_total(job)
        if total_items is not None and resume_index > total_items:
            return

        existing_spec = str(options.get("playlist_items") or "").strip()
        new_spec = self._build_playlist_resume_spec(existing_spec, resume_index)
        if not new_spec:
            return

        options["playlist_items"] = new_spec
        verbose_log(
            "resume_playlist_items",
            {
                "job_id": job.job_id,
                "resume_index": resume_index,
                "playlist_total": total_items,
                "applied_spec": new_spec,
                "completed_indices": sorted(job.playlist_completed_indices),
            },
        )

    def _resolve_resume_start_index(self, job: DownloadJob) -> Optional[int]:
        progress = job.progress
        current_index = to_int(
            progress.get("playlist_index") or progress.get("playlist_current_index")
        )
        selected_list = sorted(self._resolve_selected_playlist_indices(job))
        selected_set = set(selected_list)
        completed_set = {
            idx for idx in job.playlist_completed_indices if idx and idx > 0
        }
        if selected_set:
            completed_set.intersection_update(selected_set)
            job.playlist_completed_indices.intersection_update(selected_set)
        if (
            current_index is not None
            and current_index > 0
            and (not selected_set or current_index in selected_set)
            and current_index not in completed_set
        ):
            return current_index

        if selected_list:
            for index in selected_list:
                if index not in completed_set:
                    return index
            return None

        total_items = self._resolve_playlist_total(job)
        completed = sorted(completed_set)
        if not completed:
            if total_items is None:
                return None
            return 1

        next_candidate = 1
        for idx in completed:
            if idx != next_candidate:
                return next_candidate
            next_candidate += 1
        if total_items is not None and next_candidate > total_items:
            return None
        return next_candidate

    def _resolve_playlist_total(self, job: DownloadJob) -> Optional[int]:
        selected = self._resolve_selected_playlist_indices(job)
        if selected:
            return len(selected)
        if isinstance(job.playlist_total_items, int) and job.playlist_total_items > 0:
            return job.playlist_total_items
        progress = job.progress
        total = to_int(
            progress.get("playlist_total_items") or progress.get("playlist_count")
        )
        if total is not None and total > 0:
            return total
        metadata = job.metadata
        playlist_meta = metadata.get("playlist")
        if isinstance(playlist_meta, dict):
            entries = playlist_meta.get("entries")
            if isinstance(entries, list) and entries:
                return len(entries)
            total_value = playlist_meta.get("count") or playlist_meta.get("length")
            resolved = to_int(total_value)
            if resolved is not None and resolved > 0:
                return resolved
        return None

    def _build_playlist_resume_spec(
        self, existing_spec: str, resume_index: int
    ) -> Optional[str]:
        normalized_spec = existing_spec.strip()
        if not normalized_spec:
            return f"{resume_index}-"

        adjusted_ranges = self._adjust_playlist_spec(normalized_spec, resume_index)
        if not adjusted_ranges:
            return None
        return ",".join(adjusted_ranges)

    def _adjust_playlist_spec(self, spec: str, resume_index: int) -> List[str]:
        ranges: List[Tuple[int, Optional[int]]] = []
        open_range_start: Optional[int] = None

        for raw_part in spec.split(","):
            part = raw_part.strip()
            if not part:
                continue
            token = part.replace(":", "-")
            if token.endswith("-"):
                start_value = to_int(token[:-1])
                if start_value is None:
                    continue
                start_value = max(start_value, resume_index)
                if open_range_start is None or start_value < open_range_start:
                    open_range_start = start_value
                continue
            if "-" in token:
                start_text, end_text = token.split("-", 1)
                start_value = to_int(start_text)
                end_value = to_int(end_text)
                if start_value is None or end_value is None:
                    continue
                start_value = max(start_value, resume_index)
                if start_value > end_value:
                    continue
                ranges.append((start_value, end_value))
                continue
            single_value = to_int(token)
            if single_value is None or single_value < resume_index:
                continue
            ranges.append((single_value, single_value))

        if open_range_start is not None:
            ranges.append((open_range_start, None))

        merged = self._merge_playlist_ranges(ranges)
        return [self._format_playlist_range(start, end) for start, end in merged]

    def _merge_playlist_ranges(
        self, ranges: List[Tuple[int, Optional[int]]]
    ) -> List[Tuple[int, Optional[int]]]:
        if not ranges:
            return []
        ranges.sort(key=lambda item: item[0])
        merged: List[Tuple[int, Optional[int]]] = []
        for start, end in ranges:
            if not merged:
                merged.append((start, end))
                continue
            prev_start, prev_end = merged[-1]
            if prev_end is None:
                continue
            if end is None:
                if start <= prev_end + 1:
                    merged[-1] = (prev_start, None)
                else:
                    merged.append((start, None))
                continue
            if start <= prev_end + 1:
                merged[-1] = (prev_start, max(prev_end, end))
            else:
                merged.append((start, end))
        return merged

    def _wait_for_preview_ready(self, job_id: str) -> None:
        """Block the worker until preview extraction finishes.

        Ensures that playlist metadata (and potential selection requirements)
        are resolved before the download stage begins. The preview thread
        toggles ``preview_ready_event`` once yt-dlp finishes enumerating the
        playlist, allowing the worker to continue.
        """
        while True:
            self._guard_job_signals(job_id)
            with self.lock:
                job = self.jobs.get(job_id)
                if not job:
                    return
                preview_event = getattr(job, "preview_ready_event", None)
                preview_error = getattr(job, "preview_error", None)
            if not isinstance(preview_event, threading.Event):
                return
            if preview_event.is_set():
                if preview_error:
                    raise PreviewCollectionError(preview_error)
                return
            preview_event.wait(timeout=0.5)

    def _wait_for_playlist_selection(self, job_id: str) -> None:
        """Pause the worker until the user confirms a playlist selection."""
        while True:
            self._guard_job_signals(job_id)
            with self.lock:
                job = self.jobs.get(job_id)
                if not job:
                    return
                selection_required = job.selection_required
                selection_event = job.selection_event
            if not selection_required or selection_event.is_set():
                return
            selection_event.wait(timeout=0.5)

    @staticmethod
    def _format_playlist_range(start: int, end: Optional[int]) -> str:
        if end is None:
            return f"{start}-"
        if start == end:
            return str(start)
        return f"{start}-{end}"

    def _format_playlist_selection(self, indices: Iterable[int]) -> Optional[str]:
        normalized = sorted({index for index in indices if index > 0})
        if not normalized:
            return None
        ranges: List[Tuple[int, int]] = []
        start = normalized[0]
        end = start
        for index in normalized[1:]:
            if index == end + 1:
                end = index
                continue
            ranges.append((start, end))
            start = end = index
        ranges.append((start, end))
        parts: List[str] = []
        for range_start, range_end in ranges:
            if range_start == range_end:
                parts.append(str(range_start))
            else:
                parts.append(f"{range_start}-{range_end}")
        return ",".join(parts)

    def _run_download(self, job_id: str) -> None:
        """Worker thread target that executes a yt-dlp download session."""
        job = self.get_job(job_id)
        if not job:
            return

        with self.lock:
            job.status = JobStatus.STARTING.value
            job.started_at = _utc_now_naive()
            job.finished_at = None
            job.error = None
            job.preview_error = None
            job.has_error_logs = False

        self.append_log(job_id, "info", "Preparando descarga")
        self.emit_job_update(job_id, reason=JobUpdateReason.STARTED.value)
        self.emit_overview()

        try:
            self._wait_for_preview_ready(job_id)
            self._wait_for_playlist_selection(job_id)
            kind_changed = False
            with self.lock:
                job = self.jobs.get(job_id)
                if not job:
                    return
                kind_changed = self._ensure_job_kind_locked(job)
                job.status = JobStatus.RUNNING.value
                job.error = None
            self.append_log(job_id, "info", "Iniciando descarga")
            self._store_progress(
                job_id,
                cast(
                    DownloadJobProgressPayload,
                    {
                        "status": JobStatus.RUNNING.value,
                        "stage": DownloadStage.IDENTIFICANDO.value,
                        "stage_name": DownloadStage.IDENTIFICANDO.value,
                        "percent": 0.0,
                        "stage_percent": 0.0,
                    },
                ),
            )
            self.emit_job_update(job_id, reason=JobUpdateReason.UPDATED.value)
            self.emit_overview()
            if kind_changed:
                self._persist_jobs()

            option_copy: DownloadJobOptionsPayload = dict(job.options or {})
            self._prepare_resume_options(job, option_copy)
            options_config = build_options_config(option_copy)
        except DownloadPaused:
            self._finalize_job(job_id, status=JobStatus.PAUSED.value, error=None)
            return
        except DownloadCancelled:
            self._finalize_job(job_id, status=JobStatus.CANCELLED.value, error=None)
            return
        except PreviewCollectionError as exc:
            self._finalize_job(
                job_id,
                status=JobStatus.FAILED.value,
                error=str(exc),
            )
            return
        except Exception as exc:  # noqa: BLE001 - capture option parsing errors
            self._finalize_job(
                job_id,
                status=JobStatus.FAILED.value,
                error=f"Error preparando opciones: {exc}",
            )
            return

        status = JobStatus.COMPLETED.value
        error: Optional[str] = None

        logger = cast(LoggerLike, JobLogger(self, job_id))
        progress_hook = self._build_progress_hook(job_id)
        postprocessor_hook = self._build_postprocessor_hook(job_id)
        post_hook = self._build_post_hook(job_id)

        try:
            download(
                job.urls,
                options=options_config,
                logger=logger,
                progress_hooks=[progress_hook],
                postprocessor_hooks=[postprocessor_hook],
                post_hooks=[post_hook],
                match_filter=self._build_match_filter(job_id),
            )
        except DownloadPaused:
            status = JobStatus.PAUSED.value
        except DownloadCancelled:
            status = JobStatus.CANCELLED.value
        except DownloadError as exc:
            cause = exc.__cause__
            if isinstance(cause, DownloadPaused):
                status = JobStatus.PAUSED.value
                error = None
            elif isinstance(cause, DownloadCancelled):
                status = JobStatus.CANCELLED.value
                error = None
            else:
                message = strip_ansi(str(exc))
                signal = _classify_signal_from_message(message)
                if signal == JobStatus.PAUSED.value:
                    status = JobStatus.PAUSED.value
                    error = None
                elif signal == JobStatus.CANCELLED.value:
                    status = JobStatus.CANCELLED.value
                    error = None
                else:
                    status = JobStatus.FAILED.value
                    error = message or str(exc)
        except Exception as exc:  # noqa: BLE001 - catch-all to avoid thread crashes
            message = strip_ansi(repr(exc))
            status = JobStatus.FAILED.value
            error = message or repr(exc)
            print("=====================ERROR EN DESCARGA==>>>>>>>>>>>==============")

        if status == JobStatus.FAILED.value and not error:
            error = self._last_error_message(job) or "Una o más descargas fallaron"

        status, error = self._resolve_final_status(job_id, status, error)
        job_snapshot = self.get_job(job_id)
        if job_snapshot and status == JobStatus.COMPLETED.value:
            has_playlist_failures = bool(job_snapshot.playlist_failed_indices)
            has_error_logs = bool(getattr(job_snapshot, "has_error_logs", False))
            if has_playlist_failures or has_error_logs:
                status = JobStatus.COMPLETED_WITH_ERRORS.value
        self._finalize_job(job_id, status=status, error=error)

    def _resolve_final_status(
        self, job_id: str, status: str, error: Optional[str]
    ) -> tuple[str, Optional[str]]:
        """Resolve the final persisted status taking pause/cancel signals into account."""
        job = self.get_job(job_id)
        if not job:
            return status, error

        sanitized_error = strip_ansi(error)
        error = sanitized_error if sanitized_error is not None else error
        signal = _classify_signal_from_message(error)

        if signal == JobStatus.PAUSED.value:
            return JobStatus.PAUSED.value, None
        if signal == JobStatus.CANCELLED.value:
            return JobStatus.CANCELLED.value, None

        if status == JobStatus.COMPLETED.value:
            if job.pause_event.is_set():
                return JobStatus.PAUSED.value, None
            if job.cancel_event.is_set():
                return JobStatus.CANCELLED.value, None

        if status == JobStatus.FAILED.value:
            signal_hint = _classify_signal_from_message(sanitized_error)
            if signal_hint == JobStatus.PAUSED.value:
                return JobStatus.PAUSED.value, None
            if signal_hint == JobStatus.CANCELLED.value:
                return JobStatus.CANCELLED.value, None

        if status == JobStatus.CANCELLED.value and job.pause_event.is_set():
            inferred = self._resolve_status_from_progress(job)
            if inferred in {None, JobStatus.PAUSED.value}:
                return JobStatus.PAUSED.value, None

        return status, error

    def _resolve_status_from_progress(self, job: DownloadJob) -> Optional[str]:
        """Infer a status hint from the stored progress dictionary."""
        progress = job.progress
        status_value = progress.get("status")
        if isinstance(status_value, str) and status_value.strip():
            return status_value.strip().lower()

        stage_value = progress.get("stage")
        if isinstance(stage_value, str) and stage_value.strip():
            stage = stage_value.strip().lower()
            if stage in {JobStatus.PAUSING.value, JobStatus.PAUSED.value}:
                return JobStatus.PAUSED.value
            if stage in {JobStatus.CANCELLING.value, JobStatus.CANCELLED.value}:
                return JobStatus.CANCELLED.value

        return None

    def _finalize_job(self, job_id: str, *, status: str, error: Optional[str]) -> None:
        """Persist terminal state, emit notifications, and clean up resources."""
        job = self.get_job(job_id)
        if not job:
            return

        if status == JobStatus.COMPLETED.value and getattr(
            job, "has_error_logs", False
        ):
            status = JobStatus.COMPLETED_WITH_ERRORS.value

        auto_remove = False
        with self.lock:
            job.thread = None
            job.finished_at = _utc_now_naive()
            job.error = error
            job.resume_requested = False
            if status in COMPLETED_STATUSES:
                job.progress.setdefault("status", status)
                job.progress.setdefault("stage", DownloadStage.COMPLETED.value)
                job.progress.setdefault("stage_name", DownloadStage.COMPLETED.value)
                job.progress.setdefault("percent", 100.0)
                job.progress.setdefault("stage_percent", 100.0)
                job.progress["state"] = status
            elif status == JobStatus.PAUSED.value:
                job.progress.setdefault("status", JobStatus.PAUSED.value)
                job.progress.setdefault(
                    "stage",
                    job.progress.get("stage") or DownloadStage.IDENTIFICANDO.value,
                )
                job.progress.setdefault(
                    "stage_name",
                    job.progress.get("stage_name") or JobStatus.PAUSED.value,
                )
                job.progress["state"] = JobStatus.PAUSED.value
            elif status == JobStatus.CANCELLED.value:
                job.progress.setdefault("status", JobStatus.CANCELLED.value)
                job.progress.setdefault(
                    "stage",
                    job.progress.get("stage") or DownloadStage.IDENTIFICANDO.value,
                )
                job.progress.setdefault(
                    "stage_name",
                    job.progress.get("stage_name") or JobStatus.CANCELLED.value,
                )
                job.progress["state"] = JobStatus.CANCELLED.value
            job.status = status
            if status == JobStatus.CANCELLED.value:
                auto_remove = self._should_auto_remove_cancelled_job(job)

        if status == JobStatus.COMPLETED.value:
            self.append_log(job_id, "info", "Descarga completada")
        elif status == JobStatus.COMPLETED_WITH_ERRORS.value:
            self.append_log(job_id, "warning", "Descarga completada con errores")
        elif status == JobStatus.PAUSED.value:
            self.append_log(job_id, "info", "Descarga pausada")
        elif status == JobStatus.CANCELLED.value:
            self.append_log(job_id, "info", "Descarga cancelada")
            self._cleanup_cancelled_job(job)
        else:
            self.append_log(job_id, "error", error or "Descarga fallida")

        reason_enum = JobUpdateReason._value2member_map_.get(status)
        reason_value = (
            reason_enum.value if reason_enum else JobUpdateReason.UPDATED.value
        )
        self.emit_job_update(job_id, reason=reason_value)
        self.emit_overview()
        self._persist_jobs()

        if auto_remove:
            self.delete_job(job_id)

    def _last_error_message(self, job: DownloadJob) -> Optional[str]:
        with self.lock:
            log_entries = list(job.logs)
        for entry in reversed(log_entries):
            level = str(entry.level or "").lower()
            if level not in {"error", "stderr"}:
                continue
            message = entry.message.strip()
            if message:
                return message
        return None

    def _normalize_urls(self, urls: Union[str, Iterable[str]]) -> List[str]:
        if isinstance(urls, str):
            normalized = [urls.strip()] if urls.strip() else []
        else:
            normalized = [url.strip() for url in urls if url.strip()]
        return normalized

    def _abort_controller(self, job: DownloadJob) -> None:
        controller = job.controller
        if controller is None:
            return
        try:
            setattr(controller, "_abort_download", True)
        except Exception:  # noqa: BLE001 - controller may not expose attribute yet
            pass

    def _reset_job_events(self, job: DownloadJob) -> None:
        job.cancel_event = threading.Event()
        job.pause_event = threading.Event()
        job.selection_event = threading.Event()
        job.preview_ready_event = threading.Event()
        job.preview_error = None
        metadata = job.metadata
        preview_present = bool(metadata.get("preview") or metadata.get("playlist"))
        if not getattr(job, "selection_required", False):
            job.selection_event.set()
        if preview_present or getattr(job, "selection_required", False):
            job.preview_ready_event.set()
        job.controller = None
        job.thread = None
        job.progress_accumulators = {}

    def _build_overview_summary(
        self, jobs: Iterable[DownloadJob]
    ) -> Dict[str, JSONValue]:
        status_counts: Dict[str, int] = {}
        for job in jobs:
            status_counts[job.status] = status_counts.get(job.status, 0) + 1
        total = sum(status_counts.values())
        active = sum(status_counts.get(status, 0) for status in ACTIVE_STATUSES)
        queued = status_counts.get(JobStatus.QUEUED.value, 0)
        status_counts_json: Dict[str, JSONValue] = {
            key: count for key, count in status_counts.items()
        }
        return {
            "total": total,
            "active": active,
            JobStatus.QUEUED.value: queued,
            "status_counts": status_counts_json,
        }

    def _build_match_filter(self, job_id: str) -> MatchFilter:
        def _filter(info: YtDlpInfoResult, args: MatchFilterArgs) -> Optional[str]:
            self._guard_job_signals(job_id)
            title = info.get("title") or info.get("id")
            self.append_log(job_id, "info", f"Entrada seleccionada: {title}")
            return None

        return _filter

    def _guard_job_signals(self, job_id: str) -> None:
        """Abort ongoing work when pause/cancel signals are observed."""
        with self.lock:
            job = self.jobs.get(job_id)
            if not job:
                return
            if job.cancel_event.is_set():
                if job.status not in TERMINAL_STATUSES:
                    job.status = JobStatus.CANCELLING.value
                raise DownloadCancelled("Job cancelled by user request")
            if job.pause_event.is_set():
                if job.status not in {
                    JobStatus.PAUSED.value,
                    JobStatus.PAUSING.value,
                }:
                    job.status = JobStatus.PAUSING.value
                raise DownloadPaused("Job paused by user request")

    def guard_job_signals(self, job_id: str) -> None:
        """Public wrapper so mixins can check job control signals safely."""

        self._guard_job_signals(job_id)

    def _complete_without_download(
        self,
        job_id: str,
        *,
        reason: str,
        listed_urls: Optional[List[str]] = None,
    ) -> None:
        """Mark a job as completed when the download phase is skipped entirely."""
        self.append_log(job_id, "info", reason)
        if listed_urls:
            for index, url in enumerate(listed_urls, start=1):
                self.append_log(job_id, "debug", f"Listado #{index}: {url}")
        job = self.get_job(job_id)
        if not job:
            return
        with self.lock:
            job.status = JobStatus.COMPLETED.value
            job.error = None
            job.finished_at = _utc_now_naive()
            job.progress = {
                "job_id": job_id,
                "status": JobStatus.COMPLETED.value,
                "stage": JobStatus.COMPLETED.value,
                "percent": 100.0,
                "stage_percent": 100.0,
            }
        self.emit_job_update(job_id, reason=JobUpdateReason.COMPLETED.value)
        self.emit_overview()
        self._persist_jobs()


__all__ = ["DownloadManager"]
