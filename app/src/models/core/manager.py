"""Typed payloads exposed by :mod:`src.core.manager`."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field, replace
from typing import Any, Dict, Optional, Sequence, TypeVar, Union, cast

from ...config import JobStatus
from ...core.contract import Info

TPayload = TypeVar("TPayload", bound="ManagerPayload")


@dataclass(frozen=True, kw_only=True)
class ManagerPayload:
    """Base payload offering helpers to annotate scope and serialize values."""

    scope: Optional[str] = field(default=None, kw_only=True)

    def with_scope(self: TPayload, scope: str) -> TPayload:
        return replace(self, scope=scope)

    def to_dict(self) -> Dict[str, Any]:
        raw = asdict(self)
        serialized: Dict[str, Any] = {}
        for key, value in raw.items():
            if value is None:
                continue
            if isinstance(value, tuple):
                serialized[key] = list(cast(Sequence[Any], value))
            elif isinstance(value, list):
                serialized[key] = value
            else:
                serialized[key] = value
        return serialized


@dataclass(frozen=True, kw_only=True)
class IdentityFields:
    """Normalized identifiers shared across playlist-aware payloads."""

    playlist_index: Optional[int] = None
    entry_id: Optional[str] = None
    playlist_id: Optional[str] = None


@dataclass(frozen=True, kw_only=True)
class ExtractInfoResult(ManagerPayload):
    """Normalized data returned by :meth:`Manager.extract_info`."""

    model: Info
    extractor: Optional[str] = None
    extractor_key: Optional[str] = None
    is_playlist: bool = False
    entry_count: Optional[int] = None
    raw: Optional[Dict[str, Any]] = None


@dataclass(frozen=True, kw_only=True)
class ProgressPayload(ManagerPayload):
    event: str = "progress"
    stage: str = "download"
    status: str = JobStatus.RUNNING.value
    type: Optional[str] = None
    percent: Optional[float] = None
    downloaded_bytes: Optional[float] = None
    total_bytes: Optional[float] = None
    remaining_bytes: Optional[float] = None
    speed: Optional[float] = None
    eta: Optional[float] = None
    elapsed: Optional[float] = None
    filename: Optional[str] = None
    tmpfilename: Optional[str] = None
    playlist_index: Optional[int] = None
    entry_id: Optional[str] = None
    playlist_id: Optional[str] = None
    playlist_count: Optional[int] = None
    current_item: Optional[int] = None
    total_items: Optional[int] = None
    title: Optional[str] = None
    index: Optional[int] = None


@dataclass(frozen=True, kw_only=True)
class StagePayload(ManagerPayload):
    type: str = "stage"
    event: str = "info"
    stage: str = "job"
    stage_name: Optional[str] = None
    status: str = JobStatus.RUNNING.value
    message: Optional[str] = None
    stage_percent: Optional[float] = None
    percent: Optional[float] = None
    playlist_index: Optional[int] = None
    entry_id: Optional[str] = None
    playlist_id: Optional[str] = None
    playlist_count: Optional[int] = None
    current_item: Optional[int] = None
    total_items: Optional[int] = None
    filename: Optional[str] = None
    index: Optional[int] = None


@dataclass(frozen=True, kw_only=True)
class EntryEndPayload(ManagerPayload):
    type: str = "entry_end"
    event: str = "entry_end"
    state: str = "END_ITEM"
    status: str = JobStatus.COMPLETED.value
    index: Optional[int] = None
    playlist_index: Optional[int] = None
    entry_id: Optional[str] = None
    playlist_id: Optional[str] = None
    percent: Optional[float] = None
    filename: Optional[str] = None
    title: Optional[str] = None
    url: Optional[str] = None
    entry_count: Optional[int] = None
    files: Optional[Sequence[str]] = None


@dataclass(frozen=True, kw_only=True)
class JobEndPayload(ManagerPayload):
    type: str = "job_end"
    event: str = "end"
    stage: str = "job"
    status: str = JobStatus.COMPLETED.value
    files: Sequence[str] = field(default_factory=tuple)
    primary_file: Optional[str] = None
    message: Optional[str] = None


@dataclass(frozen=True, kw_only=True)
class PlaylistEndPayload(ManagerPayload):
    type: str = "playlist_end"
    event: str = "end"
    stage: str = "playlist_job"
    status: str = JobStatus.COMPLETED.value
    entry_count: Optional[int] = None
    files: Sequence[str] = field(default_factory=tuple)
    playlist_id: Optional[str] = None
    title: Optional[str] = None
    message: Optional[str] = None


@dataclass(frozen=True, kw_only=True)
class PlaylistInfoPayload(ManagerPayload):
    type: str = "playlist_info"
    id: Optional[str] = None
    entry_count: Optional[int] = None
    is_playlist: Optional[bool] = None
    playlist_id: Optional[str] = None
    title: Optional[str] = None
    description: Optional[str] = None
    url: Optional[str] = None
    thumbnail: Optional[str] = None


@dataclass(frozen=True, kw_only=True)
class EntryMetadataPayload(ManagerPayload):
    type: str = "entry_metadata"
    index: Optional[int] = None
    id: Optional[str] = None
    duration: Optional[int] = None
    duration_string: Optional[str] = None
    title: Optional[str] = None
    thumbnail: Optional[str] = None
    url: Optional[str] = None
    description: Optional[str] = None
    playlist_id: Optional[str] = None


@dataclass(frozen=True, kw_only=True)
class PostprocessorPayload(ManagerPayload):
    type: str = "postprocessor"
    event: str = "info"
    stage: str = "postprocessor"
    stage_name: Optional[str] = None
    status: str = JobStatus.RUNNING.value
    message: Optional[str] = None
    stage_percent: Optional[float] = None
    percent: Optional[float] = None
    name: Optional[str] = None
    playlist_index: Optional[int] = None
    entry_id: Optional[str] = None
    playlist_id: Optional[str] = None
    index: Optional[int] = None


@dataclass(frozen=True, kw_only=True)
class PostHookPayload(ManagerPayload):
    type: str = "post_hook"
    event: str = "info"
    stage: str = "job"
    stage_name: str = "job"
    status: str = JobStatus.RUNNING.value
    raw_status: Optional[str] = None
    message: Optional[str] = None
    stage_percent: Optional[float] = None
    percent: Optional[float] = None
    index: Optional[int] = None


@dataclass(frozen=True, kw_only=True)
class LogPayload(ManagerPayload):
    type: str = "log"
    event: str = "info"
    stage: str = "log"
    status: str = "info"
    level: str = "info"
    message: str = ""


@dataclass(frozen=True, kw_only=True)
class ErrorPayload(ManagerPayload):
    type: str = "error"
    event: str = "info"
    stage: str = "job"
    status: str = "error"
    message: str = ""


ManagerProgressEvent = ProgressPayload
ManagerInfoEvent = Union[
    StagePayload,
    PlaylistInfoPayload,
    EntryMetadataPayload,
    PostprocessorPayload,
    PostHookPayload,
    LogPayload,
    ErrorPayload,
]
ManagerEndEvent = Union[JobEndPayload, PlaylistEndPayload, EntryEndPayload]

__all__ = [
    "ErrorPayload",
    "EntryEndPayload",
    "EntryMetadataPayload",
    "ExtractInfoResult",
    "IdentityFields",
    "JobEndPayload",
    "LogPayload",
    "ManagerEndEvent",
    "ManagerInfoEvent",
    "ManagerPayload",
    "ManagerProgressEvent",
    "PlaylistEndPayload",
    "PlaylistInfoPayload",
    "PostHookPayload",
    "PostprocessorPayload",
    "ProgressPayload",
    "StagePayload",
]
