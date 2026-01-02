from __future__ import annotations

from typing import List, TypedDict


class ManagerUtilsThumbnailPayload(TypedDict, total=False):
    url: str
    width: int
    height: int
    id: str


class ManagerUtilsEntryPreviewPayload(TypedDict, total=False):
    title: str
    webpage_url: str
    thumbnail_url: str
    duration_seconds: int
    duration_text: str
    uploader: str
    uploader_url: str
    channel: str
    channel_url: str


class ManagerUtilsPlaylistEntryPayload(TypedDict, total=False):
    index: int
    id: str
    title: str
    uploader: str
    uploader_id: str
    uploader_url: str
    channel: str
    channel_id: str
    channel_url: str
    channel_is_verified: bool
    webpage_url: str
    duration_seconds: int
    duration_text: str
    thumbnail_url: str
    availability: str
    live_status: str
    view_count: int
    preview: ManagerUtilsEntryPreviewPayload
    status: str
    is_completed: bool
    is_current: bool


class ManagerUtilsPlaylistMetadataPayload(TypedDict, total=False):
    id: str
    title: str
    uploader: str
    uploader_id: str
    uploader_url: str
    channel: str
    channel_id: str
    channel_url: str
    channel_follower_count: int
    channel_is_verified: bool
    description: str
    description_short: str
    webpage_url: str
    thumbnail_url: str
    thumbnails: List[ManagerUtilsThumbnailPayload]
    availability: str
    live_status: str
    tags: List[str]
    entries: List[ManagerUtilsPlaylistEntryPayload]
    entry_count: int


class ManagerUtilsPreviewMetadataPayload(TypedDict, total=False):
    title: str
    description: str
    webpage_url: str
    original_url: str
    webpage_url_basename: str
    webpage_url_domain: str
    thumbnail_url: str
    thumbnails: List[ManagerUtilsThumbnailPayload]
    duration_seconds: int
    duration_text: str
    extractor: str
    extractor_id: str
    entry_id: str
    view_count: int
    like_count: int
    availability: str
    live_status: str
    tags: List[str]
    uploader: str
    uploader_id: str
    uploader_url: str
    channel: str
    channel_id: str
    channel_url: str
    channel_follower_count: int
    channel_is_verified: bool
    upload_date_iso: str
    is_playlist: bool
    playlist: ManagerUtilsPlaylistMetadataPayload
    playlist_entry_count: int
    playlist_id: str
    playlist_title: str
    playlist_uploader: str


__all__ = [
    "ManagerUtilsEntryPreviewPayload",
    "ManagerUtilsPlaylistEntryPayload",
    "ManagerUtilsPlaylistMetadataPayload",
    "ManagerUtilsPreviewMetadataPayload",
    "ManagerUtilsThumbnailPayload",
]
