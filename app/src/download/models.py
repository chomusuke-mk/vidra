"""Data models for download jobs."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from datetime import datetime
import threading
from typing import TYPE_CHECKING, Deque, Dict, List, Optional, Set, TypedDict

from ..config import JobKind, JobStatus
from ..models.shared import JSONValue
from ..models.download.mixins.preview import (
    PlaylistMetadataPayload,
    PreviewMetadataPayload,
)
from ..models.download.playlist_entry_error import PlaylistEntryError

if TYPE_CHECKING:  # pragma: no cover - only used for type hints
    from ..models.download.manager import JobLogEntry


class DownloadJobPathsOptions(TypedDict, total=False):
    home: str
    temp: str
    output: str
    download: str


# JSON-friendly dict storing the original option payload the client sent.
DownloadJobOptionsPayload = Dict[str, JSONValue]


class DownloadJobMetadataPayload(TypedDict, total=False):
    playlist: PlaylistMetadataPayload
    preview: PreviewMetadataPayload
    requires_playlist_selection: bool
    is_playlist: bool
    ctx_id: str
    playlist_id: str
    playlist_entry_count: int
    playlist_title: str
    title: str
    description: str
    thumbnail_url: str
    webpage_url: str
    original_url: str
    preview_collected_at: str


class DownloadJobProgressPayload(TypedDict, total=False):
    job_id: str
    status: str
    state: str
    downloaded_bytes: int
    total_bytes: int
    remaining_bytes: int
    speed: float
    eta: int
    elapsed: float
    filename: str
    tmpfilename: str
    main_file: str
    generated_files: List[str]
    partial_files: List[str]
    percent: float
    ctx_id: str
    stage: str
    stage_name: str
    stage_percent: float
    current_item: int
    total_items: int
    message: str
    playlist_index: int
    playlist_current_index: int
    playlist_count: int
    playlist_total_items: int
    playlist_completed_items: int
    playlist_pending_items: int
    playlist_percent: float
    playlist_current_entry_id: str
    playlist_newly_completed_index: int
    is_current: bool
    is_completed: bool
    state_hint: str
    reason: str


class DownloadJobAccumulatorRecord(TypedDict, total=False):
    current_ctx: Optional[str]
    offset_downloaded: float
    offset_total: float
    seen_ctx: Set[str]


def _empty_metadata_payload() -> "DownloadJobMetadataPayload":
    return {}


def _empty_progress_payload() -> "DownloadJobProgressPayload":
    return {}


def _empty_int_set() -> Set[int]:
    return set()


def _empty_str_set() -> Set[str]:
    return set()


def _empty_accumulator_map() -> dict[str, "DownloadJobAccumulatorRecord"]:
    return {}


def _empty_entry_error_map() -> Dict[int, PlaylistEntryError]:
    return {}


@dataclass
class DownloadJob:
    job_id: str
    urls: List[str]
    options: DownloadJobOptionsPayload
    options_version: Optional[int] = None
    creator: Optional[str] = None
    metadata: DownloadJobMetadataPayload = field(
        default_factory=_empty_metadata_payload
    )
    status: str = JobStatus.QUEUED.value
    created_at: datetime = field(default_factory=datetime.now)
    started_at: Optional[datetime] = None
    finished_at: Optional[datetime] = None
    progress: DownloadJobProgressPayload = field(
        default_factory=_empty_progress_payload
    )
    error: Optional[str] = None
    cancel_event: threading.Event = field(default_factory=threading.Event)
    pause_event: threading.Event = field(default_factory=threading.Event)
    thread: Optional[threading.Thread] = None
    controller: Optional[object] = None
    logs: Deque["JobLogEntry"] = field(default_factory=lambda: deque(maxlen=200))
    last_state_broadcast: Optional[str] = None
    playlist_total_items: Optional[int] = None
    playlist_entries_version: Optional[int] = None
    playlist_completed_indices: Set[int] = field(default_factory=_empty_int_set)
    playlist_failed_indices: Set[int] = field(default_factory=_empty_int_set)
    playlist_entry_errors: Dict[int, PlaylistEntryError] = field(
        default_factory=_empty_entry_error_map
    )
    playlist_pending_indices: Set[int] = field(default_factory=_empty_int_set)
    playlist_removed_indices: Set[int] = field(default_factory=_empty_int_set)
    resume_requested: bool = False
    generated_files: Set[str] = field(default_factory=_empty_str_set)
    partial_files: Set[str] = field(default_factory=_empty_str_set)
    main_file: Optional[str] = None
    selection_required: bool = False
    selection_event: threading.Event = field(default_factory=threading.Event)
    preview_ready_event: threading.Event = field(default_factory=threading.Event)
    preview_error: Optional[str] = None
    has_error_logs: bool = False
    active_playlist_log_index: Optional[int] = None
    active_playlist_log_entry_id: Optional[str] = None
    logs_version: Optional[int] = None
    log_persist_at: float = 0.0
    kind: str = JobKind.UNKNOWN.value
    progress_accumulators: dict[str, DownloadJobAccumulatorRecord] = field(
        default_factory=_empty_accumulator_map, repr=False
    )
