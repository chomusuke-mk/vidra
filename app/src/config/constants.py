from __future__ import annotations

from enum import Enum
from typing import Final, FrozenSet

from .environment import get_server_environment

# ---------------------------------------------------------------------------
# Application bootstrap defaults
# ---------------------------------------------------------------------------
_SERVER_ENV = get_server_environment()

DEFAULT_HOST: Final[str] = _SERVER_ENV.host
DEFAULT_PORT: Final[int] = _SERVER_ENV.port
DEFAULT_LOG_LEVEL: Final[str] = _SERVER_ENV.log_level
DATA_FOLDER: Final[str] = _SERVER_ENV.data_folder
CACHE_FOLDER: Final[str] = _SERVER_ENV.cache_folder

# ---------------------------------------------------------------------------
# API routing conventions
# ---------------------------------------------------------------------------
API_PREFIX: Final[str] = "/api"
HEALTH_CHECK_PATH: Final[str] = "/"


class ApiRoute(str, Enum):
    JOBS = f"{API_PREFIX}/jobs"
    JOB_DETAIL = f"{API_PREFIX}/jobs/{{job_id}}"
    JOB_CANCEL = f"{API_PREFIX}/jobs/{{job_id}}/cancel"
    JOB_PAUSE = f"{API_PREFIX}/jobs/{{job_id}}/pause"
    JOB_RESUME = f"{API_PREFIX}/jobs/{{job_id}}/resume"
    JOB_RETRY = f"{API_PREFIX}/jobs/{{job_id}}/retry"
    JOB_DELETE = f"{API_PREFIX}/jobs/{{job_id}}"
    JOB_LOGS = f"{API_PREFIX}/jobs/{{job_id}}/logs"
    JOB_OPTIONS = f"{API_PREFIX}/jobs/{{job_id}}/options"
    JOB_PLAYLIST = f"{API_PREFIX}/jobs/{{job_id}}/playlist"
    JOB_PLAYLIST_ITEMS = f"{API_PREFIX}/jobs/{{job_id}}/playlist/items"
    JOB_PLAYLIST_ITEMS_DELTA = f"{API_PREFIX}/jobs/{{job_id}}/playlist/items/delta"
    JOB_PLAYLIST_SELECTION = f"{API_PREFIX}/jobs/{{job_id}}/playlist/selection"
    JOB_PLAYLIST_RETRY = f"{API_PREFIX}/jobs/{{job_id}}/playlist/retry"
    JOB_PLAYLIST_DELETE = f"{API_PREFIX}/jobs/{{job_id}}/playlist/delete"
    JOB_CANCEL_BULK = f"{API_PREFIX}/jobs/cancel"
    JOB_DRY_RUN = f"{API_PREFIX}/jobs/dry-run"
    PROFILES = f"{API_PREFIX}/profiles"
    PREVIEW = f"{API_PREFIX}/preview"


# ---------------------------------------------------------------------------
# Job lifecycle constants
# ---------------------------------------------------------------------------
class JobStatus(str, Enum):
    QUEUED = "queued"
    RUNNING = "running"
    STARTING = "starting"
    RETRYING = "retrying"
    PAUSING = "pausing"
    PAUSED = "paused"
    CANCELLING = "cancelling"
    CANCELLED = "cancelled"
    FAILED = "failed"
    COMPLETED = "completed"
    COMPLETED_WITH_ERRORS = "completed_with_errors"


class JobCommandStatus(str, Enum):
    NOT_FOUND = "not_found"
    JOB_ACTIVE = "job_active"
    DELETED = "deleted"
    NOT_PLAYLIST = "not_playlist"
    NO_ENTRIES = "no_entries"
    ENTRIES_NOT_FAILED = "entries_not_failed"
    ENTRIES_ALREADY_REMOVED = "entries_already_removed"
    ENTRIES_REMOVED = "entries_removed"


class JobCommandReason(str, Enum):
    JOB_IS_NOT_PLAYLIST = "job_is_not_playlist"
    PLAYLIST_ENTRIES_REQUIRED = "playlist_entries_required"
    ENTRIES_NOT_FAILED = "entries_not_failed"
    DELETED = "deleted"
    JOB_TERMINATED = "job_terminated"
    PLAYLIST_SELECTION_LOCKED = "playlist_selection_locked"


class JobKind(str, Enum):
    UNKNOWN = "unknown"
    VIDEO = "video"
    PLAYLIST = "playlist"


TERMINAL_STATUSES: Final[FrozenSet[str]] = frozenset(
    {
        JobStatus.COMPLETED.value,
        JobStatus.COMPLETED_WITH_ERRORS.value,
        JobStatus.FAILED.value,
        JobStatus.CANCELLED.value,
    }
)
ACTIVE_STATUSES: Final[FrozenSet[str]] = frozenset(
    {
        JobStatus.RUNNING.value,
        JobStatus.CANCELLING.value,
        JobStatus.PAUSING.value,
        JobStatus.STARTING.value,
        JobStatus.RETRYING.value,
    }
)
RESUMABLE_STATUSES: Final[FrozenSet[str]] = frozenset(
    {JobStatus.PAUSED.value, JobStatus.FAILED.value}
)
PAUSE_ELIGIBLE_STATUSES: Final[FrozenSet[str]] = frozenset(
    {JobStatus.RUNNING.value, JobStatus.STARTING.value, JobStatus.RETRYING.value}
)
CANCEL_IMMEDIATE_STATUSES: Final[FrozenSet[str]] = frozenset(
    {JobStatus.PAUSED.value, JobStatus.FAILED.value}
)


class JobUpdateReason(str, Enum):
    CREATED = "created"
    STARTED = "started"
    UPDATED = "updated"
    RESUMED = "resumed"
    RETRY = "retry"
    COMPLETED = JobStatus.COMPLETED.value
    COMPLETED_WITH_ERRORS = JobStatus.COMPLETED_WITH_ERRORS.value
    FAILED = JobStatus.FAILED.value
    CANCELLED = JobStatus.CANCELLED.value
    PAUSED = JobStatus.PAUSED.value
    CANCELLING = JobStatus.CANCELLING.value
    PAUSING = JobStatus.PAUSING.value
    RESTORED = "restored"


# ---------------------------------------------------------------------------
# Websocket events and routing
# ---------------------------------------------------------------------------
class SocketEvent(str, Enum):
    OVERVIEW = "overview"
    UPDATE = "update"
    LOG = "log"
    PROGRESS = "progress"
    GLOBAL_INFO = "global_info"
    ENTRY_INFO = "entry_info"
    LIST_INFO_ENDS = "list_info_ends"
    PLAYLIST_PREVIEW_ENTRY = "playlist_preview_entry"
    PLAYLIST_SNAPSHOT = "playlist_snapshot"
    PLAYLIST_PROGRESS = "playlist_progress"
    PLAYLIST_ENTRY_PROGRESS = "playlist_entry_progress"
    ERROR = "error"


class SocketRoom(str, Enum):
    OVERVIEW = "overview"
    JOB_PREFIX = "job:"

    @classmethod
    def for_job(cls, job_id: str) -> str:
        return f"{cls.JOB_PREFIX.value}{job_id}"


INITIAL_SYNC_REASON: Final[str] = "initial_sync"


# ---------------------------------------------------------------------------
# yt-dlp mapping aids
# ---------------------------------------------------------------------------
class YtDlpField(str, Enum):
    URLS = "urls"
    OPTIONS = "options"
    METADATA = "metadata"
    PROGRESS = "progress"
    PLAYLIST = "playlist"
    ENTRIES = "entries"
    LOGS = "logs"


class YtDlpOptionKey(str, Enum):
    CLI_ARGS = "cli_args"
    PLAYLIST_ITEMS = "playlist_items"
    PLAYLIST = "playlist"
    RESUME = "resume"


__all__ = [
    "ACTIVE_STATUSES",
    "API_PREFIX",
    "ApiRoute",
    "CANCEL_IMMEDIATE_STATUSES",
    "DEFAULT_HOST",
    "DEFAULT_LOG_LEVEL",
    "DATA_FOLDER",
    "CACHE_FOLDER",
    "DEFAULT_PORT",
    "HEALTH_CHECK_PATH",
    "INITIAL_SYNC_REASON",
    "JobCommandReason",
    "JobCommandStatus",
    "JobKind",
    "JobStatus",
    "JobUpdateReason",
    "PAUSE_ELIGIBLE_STATUSES",
    "RESUMABLE_STATUSES",
    "SocketEvent",
    "SocketRoom",
    "TERMINAL_STATUSES",
    "YtDlpField",
    "YtDlpOptionKey",
]
