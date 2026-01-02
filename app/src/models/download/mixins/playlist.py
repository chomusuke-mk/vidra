"""Playlist metadata models shared with download mixins."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable, List, Literal, Mapping, Optional, cast

from ...shared import (
    JSONValue,
    IsoTimestamp,
    PlaylistEntryProgressSnapshot,
    PlaylistEntryProgressSnapshotPayload,
    PlaylistEntryMetadataPayload,
    get_bool,
    get_dict,
    get_float,
    get_int,
    get_list,
    get_str,
)
from .preview import (
    PlaylistEntryPayload,
    PlaylistEntryReferencePayload,
    PlaylistMetadataPayload,
    PreviewData,
    PreviewMetadataPayload,
    PreviewThumbnailPayload,
    ThumbnailData,
)

def _thumbnail_list_factory() -> List[ThumbnailData]:
    return []


def _playlist_entry_list_factory() -> List["PlaylistEntry"]:
    return []


def _entry_ref_list_factory() -> List[PlaylistEntryReferencePayload]:
    return []


def _int_list_factory() -> List[int]:
    return []


def _str_list_factory() -> List[str]:
    return []


@dataclass(slots=True)
class PlaylistEntry:
    index: int
    entry_id: Optional[str] = None
    title: Optional[str] = None
    uploader: Optional[str] = None
    uploader_id: Optional[str] = None
    uploader_url: Optional[str] = None
    channel: Optional[str] = None
    channel_id: Optional[str] = None
    channel_url: Optional[str] = None
    webpage_url: Optional[str] = None
    duration_seconds: Optional[int] = None
    duration_text: Optional[str] = None
    thumbnail_url: Optional[str] = None
    main_file: Optional[str] = None
    thumbnails: List[ThumbnailData] = field(default_factory=_thumbnail_list_factory)
    preview: Optional[PreviewData] = None
    status: Optional[str] = None
    is_completed: bool = False
    is_current: bool = False
    availability: Optional[str] = None
    live_status: Optional[str] = None
    view_count: Optional[int] = None
    channel_is_verified: Optional[bool] = None
    progress_snapshot: Optional[PlaylistEntryProgressSnapshot] = None

    def to_json(self) -> PlaylistEntryPayload:
        payload: PlaylistEntryPayload = {"index": self.index}
        _assign_entry_str(payload, "entry_id", self.entry_id)
        _assign_entry_str(payload, "title", self.title)
        _assign_entry_str(payload, "uploader", self.uploader)
        _assign_entry_str(payload, "uploader_id", self.uploader_id)
        _assign_entry_str(payload, "uploader_url", self.uploader_url)
        _assign_entry_str(payload, "channel", self.channel)
        _assign_entry_str(payload, "channel_id", self.channel_id)
        _assign_entry_str(payload, "channel_url", self.channel_url)
        _assign_entry_str(payload, "webpage_url", self.webpage_url)
        _assign_entry_str(payload, "duration_text", self.duration_text)
        _assign_entry_str(payload, "thumbnail_url", self.thumbnail_url)
        _assign_entry_str(payload, "main_file", self.main_file)
        _assign_entry_str(payload, "status", self.status)
        _assign_entry_str(payload, "availability", self.availability)
        _assign_entry_str(payload, "live_status", self.live_status)

        _assign_entry_int(payload, "duration_seconds", self.duration_seconds)
        _assign_entry_int(payload, "view_count", self.view_count)
        if self.is_completed:
            payload["is_completed"] = True
        if self.is_current:
            payload["is_current"] = True
        if self.channel_is_verified is not None:
            payload["channel_is_verified"] = self.channel_is_verified
        if self.thumbnails:
            payload["thumbnails"] = [thumb.to_json() for thumb in self.thumbnails]
        if self.preview:
            payload["preview"] = self.preview.to_json()
        if self.progress_snapshot:
            payload["progress_snapshot"] = self.progress_snapshot.to_payload()
        return payload

    @classmethod
    def from_json(cls, payload: PlaylistEntryPayload) -> "PlaylistEntry":
        payload_map = cast(Mapping[str, JSONValue], payload)
        thumbnails_raw = get_list(payload_map, "thumbnails")
        thumbnails: List[ThumbnailData] = []
        if thumbnails_raw:
            for entry in thumbnails_raw:
                if isinstance(entry, dict) and entry.get("url"):
                    thumbnails.append(
                        ThumbnailData.from_json(cast(PreviewThumbnailPayload, entry))
                    )
        preview_raw = get_dict(payload_map, "preview")
        preview = (
            PreviewData.from_json(cast(PreviewMetadataPayload, preview_raw))
            if preview_raw
            else None
        )
        progress_raw = get_dict(payload_map, "progress_snapshot")
        progress = (
            PlaylistEntryProgressSnapshot.from_payload(
                cast(PlaylistEntryProgressSnapshotPayload, progress_raw)
            )
            if progress_raw
            else None
        )
        return cls(
            index=get_int(payload_map, "index") or 0,
            entry_id=get_str(payload_map, "entry_id"),
            title=get_str(payload_map, "title"),
            uploader=get_str(payload_map, "uploader"),
            channel=get_str(payload_map, "channel"),
            uploader_id=get_str(payload_map, "uploader_id"),
            uploader_url=get_str(payload_map, "uploader_url"),
            channel_id=get_str(payload_map, "channel_id"),
            channel_url=get_str(payload_map, "channel_url"),
            webpage_url=get_str(payload_map, "webpage_url"),
            duration_seconds=get_int(payload_map, "duration_seconds"),
            duration_text=get_str(payload_map, "duration_text"),
            thumbnail_url=get_str(payload_map, "thumbnail_url"),
            main_file=get_str(payload_map, "main_file"),
            thumbnails=thumbnails,
            preview=preview,
            status=get_str(payload_map, "status"),
            is_completed=bool(get_bool(payload_map, "is_completed")),
            is_current=bool(get_bool(payload_map, "is_current")),
            availability=get_str(payload_map, "availability"),
            live_status=get_str(payload_map, "live_status"),
            view_count=get_int(payload_map, "view_count"),
            channel_is_verified=get_bool(payload_map, "channel_is_verified"),
            progress_snapshot=progress,
        )


@dataclass(slots=True)
class PlaylistState:
    playlist_id: Optional[str] = None
    title: Optional[str] = None
    uploader: Optional[str] = None
    uploader_id: Optional[str] = None
    uploader_url: Optional[str] = None
    channel: Optional[str] = None
    channel_id: Optional[str] = None
    channel_url: Optional[str] = None
    description: Optional[str] = None
    description_short: Optional[str] = None
    webpage_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    entry_count: Optional[int] = None
    total_items: Optional[int] = None
    completed_items: Optional[int] = None
    pending_items: Optional[int] = None
    percent: Optional[float] = None
    current_index: Optional[int] = None
    current_entry_id: Optional[str] = None
    selected_indices: List[int] = field(default_factory=_int_list_factory)
    entries_endpoint: Optional[str] = None
    entries: List[PlaylistEntry] = field(default_factory=_playlist_entry_list_factory)
    entry_refs: List[PlaylistEntryReferencePayload] = field(
        default_factory=_entry_ref_list_factory
    )
    thumbnails: List[ThumbnailData] = field(default_factory=_thumbnail_list_factory)
    tags: List[str] = field(default_factory=_str_list_factory)
    received_count: Optional[int] = None
    is_collecting_entries: Optional[bool] = None
    has_indefinite_length: Optional[bool] = None
    collection_complete: Optional[bool] = None
    availability: Optional[str] = None
    live_status: Optional[str] = None
    channel_follower_count: Optional[int] = None
    channel_is_verified: Optional[bool] = None
    collected_at: Optional[IsoTimestamp] = None

    def to_json(self, *, include_entries: bool = True) -> PlaylistMetadataPayload:
        payload: PlaylistMetadataPayload = {}
        if self.playlist_id:
            payload["playlist_id"] = self.playlist_id
        if self.title:
            payload["title"] = self.title
        if self.uploader:
            payload["uploader"] = self.uploader
        if self.uploader_id:
            payload["uploader_id"] = self.uploader_id
        if self.uploader_url:
            payload["uploader_url"] = self.uploader_url
        if self.channel:
            payload["channel"] = self.channel
        if self.channel_id:
            payload["channel_id"] = self.channel_id
        if self.channel_url:
            payload["channel_url"] = self.channel_url
        if self.description:
            payload["description"] = self.description
        if self.description_short:
            payload["description_short"] = self.description_short
        if self.thumbnail_url:
            payload["thumbnail_url"] = self.thumbnail_url
        if self.current_entry_id:
            payload["current_entry_id"] = self.current_entry_id
        if self.entries_endpoint:
            payload["entries_endpoint"] = self.entries_endpoint
        if self.webpage_url:
            payload["webpage_url"] = self.webpage_url
        if self.availability:
            payload["availability"] = self.availability
        if self.live_status:
            payload["live_status"] = self.live_status
        if self.collected_at:
            payload["collected_at"] = self.collected_at

        if self.entry_count is not None:
            payload["entry_count"] = self.entry_count
        if self.total_items is not None:
            payload["total_items"] = self.total_items
        if self.completed_items is not None:
            payload["completed_items"] = self.completed_items
        if self.pending_items is not None:
            payload["pending_items"] = self.pending_items
        if self.current_index is not None:
            payload["current_index"] = self.current_index
        if self.received_count is not None:
            payload["received_count"] = self.received_count
        if self.channel_follower_count is not None:
            payload["channel_follower_count"] = self.channel_follower_count
        if self.percent is not None:
            payload["percent"] = float(self.percent)

        if self.selected_indices:
            payload["selected_indices"] = list(self.selected_indices)
        if self.entry_refs:
            payload["entry_refs"] = list(self.entry_refs)
        if self.thumbnails:
            payload["thumbnails"] = [thumb.to_json() for thumb in self.thumbnails]
        if self.tags:
            payload["tags"] = list(self.tags)
        if include_entries and self.entries:
            entry_payloads: List[PlaylistEntryMetadataPayload] = [
                cast(PlaylistEntryMetadataPayload, entry.to_json())
                for entry in self.entries
            ]
            payload["entries"] = entry_payloads
        if self.is_collecting_entries is not None:
            payload["is_collecting_entries"] = self.is_collecting_entries
        if self.has_indefinite_length is not None:
            payload["has_indefinite_length"] = self.has_indefinite_length
        if self.collection_complete is not None:
            payload["collection_complete"] = self.collection_complete
        if self.channel_is_verified is not None:
            payload["channel_is_verified"] = self.channel_is_verified

        return payload

    @classmethod
    def from_json(cls, data: PlaylistMetadataPayload) -> "PlaylistState":
        payload_map = cast(Mapping[str, JSONValue], data)
        entries_raw = get_list(payload_map, "entries")
        entries: list[PlaylistEntry] = []
        if entries_raw:
            for entry in entries_raw:
                if isinstance(entry, dict):
                    entries.append(
                        PlaylistEntry.from_json(cast(PlaylistEntryPayload, entry))
                    )
        thumbnails_raw = get_list(payload_map, "thumbnails")
        thumbnails: list[ThumbnailData] = []
        if thumbnails_raw:
            for thumb in thumbnails_raw:
                if isinstance(thumb, dict) and thumb.get("url"):
                    thumbnails.append(
                        ThumbnailData.from_json(cast(PreviewThumbnailPayload, thumb))
                    )
        entry_refs_raw = get_list(payload_map, "entry_refs")
        entry_refs: list[PlaylistEntryReferencePayload] = []
        if entry_refs_raw:
            for ref in entry_refs_raw:
                if isinstance(ref, dict):
                    entry_refs.append(cast(PlaylistEntryReferencePayload, dict(ref)))
        selected_raw = get_list(payload_map, "selected_indices")
        selected: list[int] = []
        if selected_raw:
            for item in selected_raw:
                if isinstance(item, int):
                    selected.append(item)
        return cls(
            playlist_id=get_str(payload_map, "playlist_id"),
            title=get_str(payload_map, "title"),
            uploader=get_str(payload_map, "uploader"),
            uploader_id=get_str(payload_map, "uploader_id"),
            uploader_url=get_str(payload_map, "uploader_url"),
            channel=get_str(payload_map, "channel"),
            channel_id=get_str(payload_map, "channel_id"),
            channel_url=get_str(payload_map, "channel_url"),
            description=get_str(payload_map, "description"),
            description_short=get_str(payload_map, "description_short"),
            webpage_url=get_str(payload_map, "webpage_url"),
            thumbnail_url=get_str(payload_map, "thumbnail_url"),
            entry_count=get_int(payload_map, "entry_count"),
            total_items=get_int(payload_map, "total_items"),
            completed_items=get_int(payload_map, "completed_items"),
            pending_items=get_int(payload_map, "pending_items"),
            percent=get_float(payload_map, "percent"),
            current_index=get_int(payload_map, "current_index"),
            current_entry_id=get_str(payload_map, "current_entry_id"),
            selected_indices=selected,
            entries_endpoint=get_str(payload_map, "entries_endpoint"),
            entries=entries,
            entry_refs=entry_refs,
            thumbnails=thumbnails,
            tags=[
                str(tag)
                for tag in (get_list(payload_map, "tags") or [])
                if isinstance(tag, str)
            ],
            received_count=get_int(payload_map, "received_count"),
            is_collecting_entries=get_bool(payload_map, "is_collecting_entries"),
            has_indefinite_length=get_bool(payload_map, "has_indefinite_length"),
            collection_complete=get_bool(payload_map, "collection_complete"),
            availability=get_str(payload_map, "availability"),
            live_status=get_str(payload_map, "live_status"),
            channel_follower_count=get_int(payload_map, "channel_follower_count"),
            channel_is_verified=get_bool(payload_map, "channel_is_verified"),
            collected_at=get_str(payload_map, "collected_at"),
        )

    def merge_entries(self, new_entries: Iterable[PlaylistEntry]) -> None:
        existing = {entry.index: entry for entry in self.entries}
        for entry in new_entries:
            existing[entry.index] = entry
        self.entries = [existing[index] for index in sorted(existing)]


__all__ = ["PlaylistEntry", "PlaylistState"]


EntryStrKey = Literal[
    "entry_id",
    "title",
    "uploader",
    "uploader_id",
    "uploader_url",
    "channel",
    "channel_id",
    "channel_url",
    "webpage_url",
    "duration_text",
    "thumbnail_url",
    "main_file",
    "status",
    "availability",
    "live_status",
]

EntryIntKey = Literal["duration_seconds", "view_count"]


def _assign_entry_str(
    payload: PlaylistEntryPayload, key: EntryStrKey, value: Optional[str]
) -> None:
    if value:
        payload[key] = value


def _assign_entry_int(
    payload: PlaylistEntryPayload, key: EntryIntKey, value: Optional[int]
) -> None:
    if value is not None:
        payload[key] = value
