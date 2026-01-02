from __future__ import annotations

from enum import Enum


class ErrorCode(str, Enum):
    """Canonical error identifiers shared across HTTP and websocket APIs."""

    TOKEN_MISSING_OR_INVALID = "token_missing_or_invalid"
    URLS_REQUIRED = "urls_required"
    JOB_NOT_FOUND = "job_not_found"
    JOB_DELETE_CONFLICT_ACTIVE = "job_delete_conflict_active"
    JOB_STATUS_CONFLICT = "job_status_conflict"
    SINCE_MUST_BE_INTEGER = "since_must_be_integer"
    ENTRY_INDEX_INVALID = "entry_index_invalid"
    LIMIT_MUST_BE_INTEGER = "limit_must_be_integer"
    LIMIT_GREATER_THAN_ZERO = "limit_greater_than_zero"
    OFFSET_MUST_BE_INTEGER = "offset_must_be_integer"
    OFFSET_MUST_BE_NON_NEGATIVE = "offset_must_be_non_negative"
    PLAYLIST_ENTRIES_UNAVAILABLE = "playlist_entries_unavailable"
    PLAYLIST_METADATA_UNAVAILABLE = "playlist_metadata_unavailable"
    DRY_RUN_FAILED = "dry_run_failed"
    PREVIEW_FAILED = "preview_failed"
    PROFILES_NOT_IMPLEMENTED = "profiles_not_implemented"
    DOWNLOAD_ERROR = "download_error"
    INVALID_JSON_PAYLOAD = "invalid_json_payload"
    OPTIONS_NOT_OBJECT = "options_not_object"
    PAYLOAD_NOT_OBJECT = "payload_not_object"
    ACTION_REQUIRED = "action_required"
    UNKNOWN_ACTION = "unknown_action"
    PLAYLIST_SELECTION_RECEIVED = "playlist_selection_received"
    IDENTIFYING_CONTENT = "identifying_content"
    DOWNLOADS_FAILED = "downloads_failed"

    def __str__(self) -> str:  # pragma: no cover - trivial
        return str(self.value)


__all__ = ["ErrorCode"]
