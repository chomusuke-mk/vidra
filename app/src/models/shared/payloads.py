"""TypedDict payload definitions shared across Vidra models."""

from __future__ import annotations

from typing import List, TypedDict

from .base import IsoTimestamp
from ..download.playlist_entry_error import PlaylistEntryErrorPayload


class PreviewMetadataExtras(TypedDict, total=False):
    """Free-form metadata captured from extractor results."""


class PreviewThumbnailPayload(TypedDict, total=False):
    url: str
    width: int
    height: int
    id: str


class PlaylistEntryProgressSnapshotPayload(TypedDict, total=False):
    downloaded_bytes: int
    total_bytes: int
    speed: float
    eta: int
    elapsed: float
    percent: float
    stage_percent: float
    status: str
    stage: str
    stage_name: str
    message: str
    main_file: str
    state: str
    timestamp: IsoTimestamp


class PlaylistEntryReferencePayload(TypedDict, total=False):
    index: int
    id: str
    status: str


class PreviewMetadataPayload(TypedDict, total=False):
    title: str
    description: str
    webpage_url: str
    original_url: str
    webpage_url_basename: str
    webpage_url_domain: str
    duration_seconds: int
    duration_text: str
    thumbnail_url: str
    thumbnails: List[PreviewThumbnailPayload]
    uploader: str
    uploader_id: str
    uploader_url: str
    channel: str
    channel_id: str
    channel_url: str
    channel_follower_count: int
    channel_is_verified: bool
    upload_date_iso: str
    extractor: str
    extractor_id: str
    entry_id: str
    view_count: int
    like_count: int
    availability: str
    live_status: str
    tags: List[str]
    playlist_entry_count: int
    playlist_id: str
    playlist_title: str
    playlist_uploader: str
    playlist: "PlaylistMetadataPayload"
    preview_ready: bool
    is_playlist: bool
    collected_at: str
    metadata: PreviewMetadataExtras


class PlaylistEntryMetadataPayload(TypedDict, total=False):
    index: int
    entry_id: str
    title: str
    uploader: str
    uploader_id: str
    uploader_url: str
    channel: str
    channel_id: str
    channel_url: str
    webpage_url: str
    duration_seconds: int
    duration_text: str
    thumbnail_url: str
    thumbnails: List[PreviewThumbnailPayload]
    availability: str
    live_status: str
    view_count: int
    channel_is_verified: bool
    status: str
    is_completed: bool
    is_current: bool
    main_file: str
    preview: PreviewMetadataPayload
    progress_snapshot: PlaylistEntryProgressSnapshotPayload


class PlaylistMetadataPayload(TypedDict, total=False):
    playlist_id: str
    entries_endpoint: str
    entries_version: int
    entries_external: bool
    title: str
    uploader: str
    uploader_id: str
    uploader_url: str
    channel: str
    channel_id: str
    channel_url: str
    description: str
    description_short: str
    webpage_url: str
    webpage_url_basename: str
    webpage_url_domain: str
    thumbnail_url: str
    thumbnails: List[PreviewThumbnailPayload]
    entry_count: int
    total_items: int
    completed_items: int
    pending_items: int
    percent: float
    current_index: int
    current_entry_id: str
    selected_indices: List[int]
    received_count: int
    is_collecting_entries: bool
    has_indefinite_length: bool
    collection_complete: bool
    collection_error: str
    entry_refs: List[PlaylistEntryReferencePayload]
    entries: List[PlaylistEntryMetadataPayload]
    last_entry: PlaylistEntryMetadataPayload
    entries_offset: int
    entries_truncated: bool
    completed_indices: List[int]
    failed_indices: List[int]
    pending_retry_indices: List[int]
    removed_indices: List[int]
    entry_errors: List[PlaylistEntryErrorPayload]
    channel_follower_count: int
    channel_is_verified: bool
    availability: str
    live_status: str
    tags: List[str]
    collected_at: str


__all__ = [
    "PlaylistEntryMetadataPayload",
    "PlaylistEntryProgressSnapshotPayload",
    "PlaylistEntryReferencePayload",
    "PlaylistMetadataPayload",
    "PreviewMetadataExtras",
    "PreviewMetadataPayload",
    "PreviewThumbnailPayload",
]
