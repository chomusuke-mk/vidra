"""Typed payloads shared with download manager endpoints."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, List, Mapping, Optional, TypedDict, NotRequired, cast

from ...config.constants import JobKind, JobStatus
from ...download.models import (
    DownloadJobMetadataPayload,
    DownloadJobOptionsPayload,
    DownloadJobProgressPayload,
)
from ...models.download.mixins.preview import (
    PlaylistMetadataPayload,
    PreviewMetadataPayload,
)
from .playlist_entry_error import PlaylistEntryError, PlaylistEntryErrorPayload
from ..shared import (
    IsoTimestamp,
    JSONValue,
    clone_json_dict,
    get_bool,
    get_dict,
    get_int,
    get_list,
    get_str,
)
from .mixins.progress import (
    PlaylistProgressSnapshot,
    PlaylistProgressSnapshotPayload,
    ProgressSnapshot,
    ProgressSnapshotPayload,
)


class JobActionResponse(TypedDict, total=False):
    job_id: str
    status: str
    reason: NotRequired[str]
    previous_status: NotRequired[str]
    selection: NotRequired[str]
    timestamp: NotRequired[str]


class JobLogEntryPayload(TypedDict, total=False):
    timestamp: str
    level: str
    message: str
    playlist_index: NotRequired[int]
    playlist_entry_id: NotRequired[str]


class JobLogBroadcastPayload(JobLogEntryPayload):
    job_id: str


class SerializedJobBasePayload(TypedDict):
    job_id: str
    status: str
    kind: str


class SerializedJobPayload(SerializedJobBasePayload, total=False):
    creator: Optional[str]
    created_at: str
    started_at: Optional[str]
    finished_at: Optional[str]
    error: Optional[str]
    progress: DownloadJobProgressPayload
    metadata: DownloadJobMetadataPayload
    preview: PreviewMetadataPayload
    playlist: PlaylistMetadataPayload
    status_hint: str
    urls: List[str]
    options: DownloadJobOptionsPayload
    logs: List[JobLogEntryPayload]
    playlist_detail: PlaylistMetadataPayload
    reason: str
    timestamp: str


class OverviewSummaryPayload(TypedDict):
    total: int
    active: int
    queued: int
    status_counts: Dict[str, int]


class OverviewSnapshotPayload(TypedDict, total=False):
    summary: OverviewSummaryPayload
    timestamp: str


class JobMetadataPayloadRequired(TypedDict):
    job_id: str
    url: str


class JobMetadataPayload(JobMetadataPayloadRequired, total=False):
    ctx_id: str | None
    title: str
    author: str
    thumbnail: str
    playlist_index: int
    playlist_count: int
    created_at: IsoTimestamp


class DownloadJobSnapshotPayloadRequired(TypedDict):
    metadata: JobMetadataPayload
    logs: List[JobLogEntryPayload]


class DownloadJobSnapshotPayload(DownloadJobSnapshotPayloadRequired, total=False):
    progress: ProgressSnapshotPayload
    playlist_progress: PlaylistProgressSnapshotPayload
    last_event_at: IsoTimestamp
    last_error: str
    state: str


class DownloadPersistedStatePayloadRequired(TypedDict):
    job_id: str
    urls: List[str]
    metadata: DownloadJobMetadataPayload
    status: str
    kind: str


class DownloadPersistedStatePayload(DownloadPersistedStatePayloadRequired, total=False):
    creator: str
    created_at: IsoTimestamp
    started_at: IsoTimestamp
    finished_at: IsoTimestamp
    error: str
    has_error_logs: bool
    options: DownloadJobOptionsPayload
    options_version: int
    options_external: bool
    progress: ProgressSnapshotPayload
    playlist_progress: PlaylistProgressSnapshotPayload
    resume_requested: bool
    playlist_total_items: int
    playlist_entries_version: int
    playlist_completed_indices: List[int]
    playlist_failed_indices: List[int]
    playlist_entry_errors: List[PlaylistEntryErrorPayload]
    playlist_pending_indices: List[int]
    playlist_removed_indices: List[int]
    generated_files: List[str]
    partial_files: List[str]
    main_file: str
    logs: List[JobLogEntryPayload]
    logs_version: int
    logs_external: bool
    last_event_at: IsoTimestamp
    last_error: str
    state: str
    selection_required: bool


def _job_log_entry_list_factory() -> List["JobLogEntry"]:
    return []


def _int_list_factory() -> List[int]:
    return []


def _str_list_factory() -> List[str]:
    return []


def _entry_error_list_factory() -> List[PlaylistEntryError]:
    return []


def _options_payload_factory() -> DownloadJobOptionsPayload:
    return {}


def _metadata_payload_factory() -> DownloadJobMetadataPayload:
    return {}


def _clone_options_payload(
    payload: DownloadJobOptionsPayload,
) -> DownloadJobOptionsPayload:
    return clone_json_dict(cast(Mapping[str, JSONValue], payload))


def _clone_metadata_payload(
    payload: DownloadJobMetadataPayload,
) -> DownloadJobMetadataPayload:
    return cast(
        DownloadJobMetadataPayload,
        clone_json_dict(cast(Mapping[str, JSONValue], payload)),
    )


@dataclass(slots=True)
class CreateJobRequest:
    urls: List[str] = field(default_factory=_str_list_factory)
    options: DownloadJobOptionsPayload = field(default_factory=_options_payload_factory)
    metadata: DownloadJobMetadataPayload = field(
        default_factory=_metadata_payload_factory
    )
    creator: Optional[str] = None

    def clone(self) -> "CreateJobRequest":
        return CreateJobRequest(
            urls=list(self.urls),
            options=_clone_options_payload(self.options),
            metadata=_clone_metadata_payload(self.metadata),
            creator=self.creator,
        )


@dataclass(slots=True)
class JobLogEntry:
    timestamp: IsoTimestamp
    level: str
    message: str
    playlist_index: Optional[int] = None
    playlist_entry_id: Optional[str] = None

    def to_json(self) -> JobLogEntryPayload:
        payload: JobLogEntryPayload = {
            "timestamp": self.timestamp,
            "level": self.level,
            "message": self.message,
        }
        if isinstance(self.playlist_index, int):
            payload["playlist_index"] = self.playlist_index
        if self.playlist_entry_id:
            payload["playlist_entry_id"] = self.playlist_entry_id
        return payload

    @classmethod
    def from_json(cls, data: JobLogEntryPayload) -> "JobLogEntry":
        mapping = cast(Mapping[str, JSONValue], data)
        timestamp = get_str(mapping, "timestamp")
        level = get_str(mapping, "level")
        message = get_str(mapping, "message")
        if not timestamp or not level or not message:
            raise ValueError("Invalid log entry payload")
        playlist_index = get_int(mapping, "playlist_index")
        playlist_entry_id = get_str(mapping, "playlist_entry_id")
        return cls(
            timestamp=timestamp,
            level=level,
            message=message,
            playlist_index=playlist_index,
            playlist_entry_id=playlist_entry_id,
        )


@dataclass(slots=True)
class JobMetadata:
    job_id: str
    ctx_id: Optional[str]
    url: str
    title: Optional[str] = None
    author: Optional[str] = None
    thumbnail: Optional[str] = None
    playlist_index: Optional[int] = None
    playlist_count: Optional[int] = None
    created_at: Optional[IsoTimestamp] = None

    def to_json(self) -> JobMetadataPayload:
        payload: JobMetadataPayload = {
            "job_id": self.job_id,
            "url": self.url,
        }
        if self.ctx_id:
            payload["ctx_id"] = self.ctx_id
        if self.title:
            payload["title"] = self.title
        if self.author:
            payload["author"] = self.author
        if self.thumbnail:
            payload["thumbnail"] = self.thumbnail
        if isinstance(self.playlist_index, int):
            payload["playlist_index"] = self.playlist_index
        if isinstance(self.playlist_count, int):
            payload["playlist_count"] = self.playlist_count
        if self.created_at:
            payload["created_at"] = self.created_at
        return payload

    @classmethod
    def from_json(cls, data: JobMetadataPayload) -> "JobMetadata":
        mapping = cast(Mapping[str, JSONValue], data)
        job_id = get_str(mapping, "job_id")
        url = get_str(mapping, "url")
        if not job_id or not url:
            raise ValueError("Job metadata requires job_id and url")
        return cls(
            job_id=job_id,
            ctx_id=get_str(mapping, "ctx_id"),
            url=url,
            title=get_str(mapping, "title"),
            author=get_str(mapping, "author"),
            thumbnail=get_str(mapping, "thumbnail"),
            playlist_index=get_int(mapping, "playlist_index"),
            playlist_count=get_int(mapping, "playlist_count"),
            created_at=get_str(mapping, "created_at"),
        )


@dataclass(slots=True)
class DownloadJobSnapshot:
    metadata: JobMetadata
    progress: Optional[ProgressSnapshot] = None
    playlist_progress: Optional[PlaylistProgressSnapshot] = None
    logs: List[JobLogEntry] = field(default_factory=_job_log_entry_list_factory)
    last_event_at: Optional[IsoTimestamp] = None
    last_error: Optional[str] = None
    state: Optional[str] = None

    def to_json(self) -> DownloadJobSnapshotPayload:
        payload: DownloadJobSnapshotPayload = {
            "metadata": self.metadata.to_json(),
            "logs": [entry.to_json() for entry in self.logs],
        }
        if self.progress:
            payload["progress"] = self.progress.to_json()
        if self.playlist_progress:
            payload["playlist_progress"] = self.playlist_progress.to_json()
        if self.last_event_at:
            payload["last_event_at"] = self.last_event_at
        if self.last_error:
            payload["last_error"] = self.last_error
        if self.state:
            payload["state"] = self.state
        return payload

    @classmethod
    def from_json(cls, data: DownloadJobSnapshotPayload) -> "DownloadJobSnapshot":
        mapping = cast(Mapping[str, JSONValue], data)
        metadata_raw = get_dict(mapping, "metadata")
        if metadata_raw is None:
            raise ValueError("Download job snapshot requires metadata")
        progress_raw = get_dict(mapping, "progress")
        playlist_progress_raw = get_dict(mapping, "playlist_progress")
        logs_raw = get_list(mapping, "logs")
        logs: List[JobLogEntry] = []
        if logs_raw:
            for entry in logs_raw:
                if isinstance(entry, dict):
                    logs.append(JobLogEntry.from_json(cast(JobLogEntryPayload, entry)))
        metadata_payload = cast(JobMetadataPayload, metadata_raw)
        return cls(
            metadata=JobMetadata.from_json(metadata_payload),
            progress=ProgressSnapshot.from_json(
                cast(ProgressSnapshotPayload, progress_raw)
            )
            if progress_raw is not None
            else None,
            playlist_progress=PlaylistProgressSnapshot.from_json(
                cast(PlaylistProgressSnapshotPayload, playlist_progress_raw)
            )
            if playlist_progress_raw is not None
            else None,
            logs=logs,
            last_event_at=get_str(mapping, "last_event_at"),
            last_error=get_str(mapping, "last_error"),
            state=get_str(mapping, "state"),
        )


@dataclass(slots=True)
class DownloadPersistedState:
    job_id: str
    urls: List[str]
    options: DownloadJobOptionsPayload = field(default_factory=_options_payload_factory)
    options_version: Optional[int] = None
    options_external: bool = False
    metadata: DownloadJobMetadataPayload = field(
        default_factory=_metadata_payload_factory
    )
    status: str = JobStatus.QUEUED.value
    kind: str = JobKind.UNKNOWN.value
    creator: Optional[str] = None
    created_at: Optional[IsoTimestamp] = None
    started_at: Optional[IsoTimestamp] = None
    finished_at: Optional[IsoTimestamp] = None
    error: Optional[str] = None
    has_error_logs: bool = False
    progress: Optional[ProgressSnapshot] = None
    playlist_progress: Optional[PlaylistProgressSnapshot] = None
    resume_requested: bool = False
    playlist_total_items: Optional[int] = None
    playlist_entries_version: Optional[int] = None
    playlist_completed_indices: List[int] = field(default_factory=_int_list_factory)
    playlist_failed_indices: List[int] = field(default_factory=_int_list_factory)
    playlist_entry_errors: List[PlaylistEntryError] = field(
        default_factory=_entry_error_list_factory
    )
    playlist_pending_indices: List[int] = field(default_factory=_int_list_factory)
    playlist_removed_indices: List[int] = field(default_factory=_int_list_factory)
    generated_files: List[str] = field(default_factory=_str_list_factory)
    partial_files: List[str] = field(default_factory=_str_list_factory)
    main_file: Optional[str] = None
    logs: List[JobLogEntry] = field(default_factory=_job_log_entry_list_factory)
    logs_version: Optional[int] = None
    logs_external: bool = False
    selection_required: bool = False

    def to_json(self) -> DownloadPersistedStatePayload:
        clean_urls = [url for url in self.urls if url]
        payload: DownloadPersistedStatePayload = {
            "job_id": self.job_id,
            "urls": clean_urls,
            "metadata": _clone_metadata_payload(self.metadata),
            "status": self.status,
            "kind": self.kind,
        }
        if self.creator:
            payload["creator"] = self.creator
        if self.created_at:
            payload["created_at"] = self.created_at
        if self.started_at:
            payload["started_at"] = self.started_at
        if self.finished_at:
            payload["finished_at"] = self.finished_at
        if self.error:
            payload["error"] = self.error
        if self.has_error_logs:
            payload["has_error_logs"] = True
        if self.progress:
            payload["progress"] = self.progress.to_json()
        if self.playlist_progress:
            payload["playlist_progress"] = self.playlist_progress.to_json()
        if self.resume_requested:
            payload["resume_requested"] = self.resume_requested
        if isinstance(self.playlist_total_items, int):
            payload["playlist_total_items"] = self.playlist_total_items
        if self.playlist_completed_indices:
            payload["playlist_completed_indices"] = list(
                self.playlist_completed_indices
            )
        if self.playlist_failed_indices:
            payload["playlist_failed_indices"] = list(self.playlist_failed_indices)
        if self.playlist_entry_errors:
            payload["playlist_entry_errors"] = [
                record.to_json() for record in self.playlist_entry_errors
            ]
        if self.playlist_pending_indices:
            payload["playlist_pending_indices"] = list(self.playlist_pending_indices)
        if self.playlist_removed_indices:
            payload["playlist_removed_indices"] = list(self.playlist_removed_indices)
        if self.generated_files:
            payload["generated_files"] = list(self.generated_files)
        if self.partial_files:
            payload["partial_files"] = list(self.partial_files)
        if self.main_file:
            payload["main_file"] = self.main_file
        if self.selection_required:
            payload["selection_required"] = self.selection_required
        if isinstance(self.playlist_entries_version, int):
            payload["playlist_entries_version"] = self.playlist_entries_version
        if isinstance(self.options_version, int):
            payload["options_version"] = self.options_version
            if self.options_external:
                payload["options_external"] = True
        if isinstance(self.logs_version, int):
            payload["logs_version"] = self.logs_version
            if self.logs_external:
                payload["logs_external"] = True
        return payload

    @classmethod
    def from_json(cls, data: DownloadPersistedStatePayload) -> "DownloadPersistedState":
        mapping = cast(Mapping[str, JSONValue], data)
        job_id = get_str(mapping, "job_id")
        urls_raw = get_list(mapping, "urls")
        if not job_id or not job_id.strip():
            raise ValueError("job_id is required for persisted state")
        if urls_raw is None:
            raise ValueError("urls list is required for persisted state")
        urls: List[str] = []
        for raw in urls_raw:
            if isinstance(raw, str):
                trimmed = raw.strip()
                if trimmed:
                    urls.append(trimmed)
        if not urls:
            raise ValueError("persisted state requires at least one url")

        options_raw = get_dict(mapping, "options")
        metadata_raw = get_dict(mapping, "metadata")
        progress_raw = get_dict(mapping, "progress")
        playlist_progress_raw = get_dict(mapping, "playlist_progress")
        logs_raw = get_list(mapping, "logs")
        playlist_completed_raw = get_list(mapping, "playlist_completed_indices")
        playlist_failed_raw = get_list(mapping, "playlist_failed_indices")
        generated_files_raw = get_list(mapping, "generated_files")
        partial_files_raw = get_list(mapping, "partial_files")
        playlist_entry_errors_raw = get_list(mapping, "playlist_entry_errors")
        playlist_pending_raw = get_list(mapping, "playlist_pending_indices")
        playlist_removed_raw = get_list(mapping, "playlist_removed_indices")

        options = clone_json_dict(options_raw) if options_raw is not None else {}
        metadata: DownloadJobMetadataPayload
        if metadata_raw is not None:
            metadata = cast(
                DownloadJobMetadataPayload,
                clone_json_dict(metadata_raw),
            )
        else:
            metadata = {}
        progress = (
            ProgressSnapshot.from_json(cast(ProgressSnapshotPayload, progress_raw))
            if progress_raw is not None
            else None
        )
        playlist_progress = (
            PlaylistProgressSnapshot.from_json(
                cast(PlaylistProgressSnapshotPayload, playlist_progress_raw)
            )
            if playlist_progress_raw is not None
            else None
        )

        logs: List[JobLogEntry] = []
        if logs_raw:
            for entry in logs_raw:
                if isinstance(entry, dict):
                    try:
                        logs.append(
                            JobLogEntry.from_json(cast(JobLogEntryPayload, entry))
                        )
                    except ValueError:
                        continue

        playlist_completed_indices: List[int] = []
        if playlist_completed_raw:
            for value in playlist_completed_raw:
                if isinstance(value, int):
                    playlist_completed_indices.append(value)

        playlist_failed_indices: List[int] = []
        if playlist_failed_raw:
            for value in playlist_failed_raw:
                if isinstance(value, int):
                    playlist_failed_indices.append(value)

        generated_files: List[str] = []
        if generated_files_raw:
            for entry in generated_files_raw:
                if isinstance(entry, str):
                    trimmed = entry.strip()
                    if trimmed:
                        generated_files.append(trimmed)

        partial_files: List[str] = []
        if partial_files_raw:
            for entry in partial_files_raw:
                if isinstance(entry, str):
                    trimmed = entry.strip()
                    if trimmed:
                        partial_files.append(trimmed)

        playlist_pending_indices: List[int] = []
        if playlist_pending_raw:
            for value in playlist_pending_raw:
                if isinstance(value, int):
                    playlist_pending_indices.append(value)

        playlist_removed_indices: List[int] = []
        if playlist_removed_raw:
            for value in playlist_removed_raw:
                if isinstance(value, int):
                    playlist_removed_indices.append(value)

        main_file = get_str(mapping, "main_file")

        playlist_entry_errors: List[PlaylistEntryError] = []
        if playlist_entry_errors_raw:
            for entry in playlist_entry_errors_raw:
                if isinstance(entry, dict):
                    try:
                        playlist_entry_errors.append(
                            PlaylistEntryError.from_json(
                                cast(PlaylistEntryErrorPayload, entry)
                            )
                        )
                    except ValueError:
                        continue

        resume_requested_flag = get_bool(mapping, "resume_requested")
        selection_required_flag = get_bool(mapping, "selection_required")
        options_external_flag = get_bool(mapping, "options_external")
        logs_external_flag = get_bool(mapping, "logs_external")
        has_error_logs_flag = get_bool(mapping, "has_error_logs")

        return cls(
            job_id=job_id.strip(),
            urls=urls,
            options=options,
            options_version=get_int(mapping, "options_version"),
            options_external=bool(options_external_flag),
            metadata=metadata,
            status=get_str(mapping, "status") or JobStatus.QUEUED.value,
            kind=get_str(mapping, "kind") or JobKind.UNKNOWN.value,
            creator=get_str(mapping, "creator"),
            created_at=get_str(mapping, "created_at"),
            started_at=get_str(mapping, "started_at"),
            finished_at=get_str(mapping, "finished_at"),
            error=get_str(mapping, "error"),
            has_error_logs=bool(has_error_logs_flag),
            progress=progress,
            playlist_progress=playlist_progress,
            resume_requested=bool(resume_requested_flag),
            playlist_total_items=get_int(mapping, "playlist_total_items"),
            playlist_entries_version=get_int(mapping, "playlist_entries_version"),
            playlist_completed_indices=playlist_completed_indices,
            playlist_failed_indices=playlist_failed_indices,
            playlist_entry_errors=playlist_entry_errors,
            playlist_pending_indices=playlist_pending_indices,
            playlist_removed_indices=playlist_removed_indices,
            generated_files=generated_files,
            partial_files=partial_files,
            main_file=main_file,
            logs=logs,
            logs_version=get_int(mapping, "logs_version"),
            logs_external=bool(logs_external_flag),
            selection_required=bool(selection_required_flag),
        )


__all__ = [
    "CreateJobRequest",
    "JobActionResponse",
    "JobMetadataPayload",
    "JobLogBroadcastPayload",
    "JobLogEntryPayload",
    "SerializedJobBasePayload",
    "SerializedJobPayload",
    "OverviewSnapshotPayload",
    "OverviewSummaryPayload",
    "DownloadJobSnapshotPayload",
    "DownloadPersistedStatePayload",
    "JobLogEntry",
    "JobMetadata",
    "DownloadJobSnapshot",
    "DownloadPersistedState",
]
