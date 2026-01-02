"""Shared dataclasses describing preview and playlist metadata."""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Mapping, Optional, Sequence, TypeAlias, cast

from .json_types import JSONValue
from .payloads import (
    PlaylistEntryMetadataPayload,
    PlaylistEntryProgressSnapshotPayload,
    PlaylistEntryReferencePayload,
    PlaylistMetadataPayload,
    PreviewMetadataPayload,
    PreviewThumbnailPayload,
)


JSONLike: TypeAlias = JSONValue | Mapping[str, object] | Sequence[object]


def _empty_thumbnail_list() -> list["Thumbnail"]:
    return []


def _empty_str_list() -> list[str]:
    return []


def _empty_entry_metadata_list() -> list["PlaylistEntryMetadata"]:
    return []


def _empty_entry_reference_list() -> list["PlaylistEntryReference"]:
    return []


def _empty_int_list() -> list[int]:
    return []


def _strip_empty(value: JSONLike) -> JSONValue:
    """Recursively drop ``None`` values and empty collections."""

    if isinstance(value, list):
        cleaned_list: list[JSONValue] = []
        for item in cast(Sequence[JSONLike], value):
            cleaned_item = _strip_empty(item)
            if cleaned_item in (None, {}, []):
                continue
            cleaned_list.append(cleaned_item)
        return cleaned_list
    if isinstance(value, Mapping):
        cleaned_dict: dict[str, JSONValue] = {}
        for key, item in cast(Mapping[str, JSONLike], value).items():
            cleaned_item = _strip_empty(item)
            if cleaned_item in (None, {}, []):
                continue
            cleaned_dict[key] = cleaned_item
        return cleaned_dict
    if value is None:
        return None
    if isinstance(value, (str, int, float, bool)):
        return value
    return cast(JSONValue, str(value))


def _to_json_dict(payload: Mapping[str, object]) -> dict[str, JSONValue]:
    cleaned = _strip_empty(cast(JSONLike, payload))
    if isinstance(cleaned, dict):
        return cleaned
    return {}


def _coerce_str(value: object) -> Optional[str]:
    if isinstance(value, str):
        text = value.strip()
        return text or None
    return None


def _coerce_int(value: object) -> Optional[int]:
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float) and not value != value:
        return int(value)
    return None


def _coerce_float(value: object) -> Optional[float]:
    if isinstance(value, bool):
        return float(value)
    if isinstance(value, (int, float)) and not value != value:
        return float(value)
    if isinstance(value, str):
        try:
            candidate = float(value.strip())
        except ValueError:
            return None
        return candidate
    return None


def _coerce_bool(value: object) -> Optional[bool]:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        text = value.strip().lower()
        if text in {"true", "1", "yes", "y"}:
            return True
        if text in {"false", "0", "no", "n"}:
            return False
    return None



@dataclass(slots=True)
class Thumbnail:
    """Image metadata shared between previews and playlist entries."""

    url: str
    width: Optional[int] = None
    height: Optional[int] = None
    identifier: Optional[str] = None

    def to_payload(self) -> PreviewThumbnailPayload:
        payload: PreviewThumbnailPayload = {"url": self.url}
        if self.width is not None:
            payload["width"] = self.width
        if self.height is not None:
            payload["height"] = self.height
        if self.identifier:
            payload["id"] = self.identifier
        return payload

    @classmethod
    def from_payload(
        cls, payload: Mapping[str, object] | PreviewThumbnailPayload
    ) -> "Thumbnail":
        return cls(
            url=str(payload.get("url", "")) or "",
            width=_coerce_int(payload.get("width")),
            height=_coerce_int(payload.get("height")),
            identifier=_coerce_str(payload.get("id"))
            or _coerce_str(payload.get("identifier")),
        )


@dataclass(slots=True)
class PreviewMetadata:
    """High-level media information resolved during preview extraction."""

    title: Optional[str] = None
    description: Optional[str] = None
    webpage_url: Optional[str] = None
    original_url: Optional[str] = None
    webpage_url_basename: Optional[str] = None
    webpage_url_domain: Optional[str] = None
    duration_seconds: Optional[int] = None
    duration_text: Optional[str] = None
    thumbnail_url: Optional[str] = None
    thumbnails: list[Thumbnail] = field(default_factory=_empty_thumbnail_list)
    uploader: Optional[str] = None
    uploader_id: Optional[str] = None
    uploader_url: Optional[str] = None
    channel: Optional[str] = None
    channel_id: Optional[str] = None
    channel_url: Optional[str] = None
    channel_follower_count: Optional[int] = None
    channel_is_verified: Optional[bool] = None
    upload_date_iso: Optional[str] = None
    extractor: Optional[str] = None
    extractor_id: Optional[str] = None
    entry_id: Optional[str] = None
    view_count: Optional[int] = None
    like_count: Optional[int] = None
    availability: Optional[str] = None
    live_status: Optional[str] = None
    tags: list[str] = field(default_factory=_empty_str_list)
    playlist_entry_count: Optional[int] = None
    playlist_id: Optional[str] = None
    playlist_title: Optional[str] = None
    playlist_uploader: Optional[str] = None
    is_playlist: Optional[bool] = None
    collected_at: Optional[str] = None
    playlist: Optional["PlaylistMetadata"] = None

    def to_payload(self) -> PreviewMetadataPayload:
        payload = cast(dict[str, object], asdict(self))
        payload["thumbnails"] = [thumb.to_payload() for thumb in self.thumbnails]
        if self.playlist is not None:
            payload["playlist"] = self.playlist.to_payload()
        return cast(PreviewMetadataPayload, _to_json_dict(payload))

    def has_data(self) -> bool:
        return bool(self.to_payload())

    @classmethod
    def from_payload(
        cls, payload: Mapping[str, object] | PreviewMetadataPayload
    ) -> "PreviewMetadata":
        thumbnails_payload = payload.get("thumbnails")
        thumbnails: list[Thumbnail] = []
        if isinstance(thumbnails_payload, Sequence):
            for entry in cast(Sequence[object], thumbnails_payload):
                if isinstance(entry, Mapping):
                    entry_mapping = cast(Mapping[str, object], entry)
                    if entry_mapping.get("url"):
                        thumbnails.append(Thumbnail.from_payload(entry_mapping))

        playlist_payload = payload.get("playlist")
        playlist: Optional["PlaylistMetadata"] = None
        if isinstance(playlist_payload, Mapping):
            playlist = PlaylistMetadata.from_payload(
                cast(Mapping[str, object], playlist_payload)
            )

        tags_payload = payload.get("tags")
        tags: list[str] = []
        if isinstance(tags_payload, Sequence):
            for entry in cast(Sequence[object], tags_payload):
                if isinstance(entry, str) and entry.strip():
                    tags.append(entry.strip())

        return cls(
            title=_coerce_str(payload.get("title")),
            description=_coerce_str(payload.get("description")),
            webpage_url=_coerce_str(payload.get("webpage_url")),
            original_url=_coerce_str(payload.get("original_url")),
            webpage_url_basename=_coerce_str(payload.get("webpage_url_basename")),
            webpage_url_domain=_coerce_str(payload.get("webpage_url_domain")),
            duration_seconds=_coerce_int(payload.get("duration_seconds")),
            duration_text=_coerce_str(payload.get("duration_text")),
            thumbnail_url=_coerce_str(payload.get("thumbnail_url")),
            thumbnails=thumbnails,
            uploader=_coerce_str(payload.get("uploader")),
            uploader_id=_coerce_str(payload.get("uploader_id")),
            uploader_url=_coerce_str(payload.get("uploader_url")),
            channel=_coerce_str(payload.get("channel")),
            channel_id=_coerce_str(payload.get("channel_id")),
            channel_url=_coerce_str(payload.get("channel_url")),
            channel_follower_count=_coerce_int(payload.get("channel_follower_count")),
            channel_is_verified=_coerce_bool(payload.get("channel_is_verified")),
            upload_date_iso=_coerce_str(payload.get("upload_date_iso")),
            extractor=_coerce_str(payload.get("extractor")),
            extractor_id=_coerce_str(payload.get("extractor_id")),
            entry_id=_coerce_str(payload.get("entry_id")),
            view_count=_coerce_int(payload.get("view_count")),
            like_count=_coerce_int(payload.get("like_count")),
            availability=_coerce_str(payload.get("availability")),
            live_status=_coerce_str(payload.get("live_status")),
            tags=tags,
            playlist_entry_count=_coerce_int(payload.get("playlist_entry_count")),
            playlist_id=_coerce_str(payload.get("playlist_id")),
            playlist_title=_coerce_str(payload.get("playlist_title")),
            playlist_uploader=_coerce_str(payload.get("playlist_uploader")),
            is_playlist=_coerce_bool(payload.get("is_playlist")),
            collected_at=_coerce_str(payload.get("collected_at")),
            playlist=playlist,
        )


@dataclass(slots=True)
class PlaylistEntryProgressSnapshot:
    """Progress details associated with a playlist entry."""

    downloaded_bytes: Optional[int] = None
    total_bytes: Optional[int] = None
    speed: Optional[float] = None
    eta: Optional[int] = None
    elapsed: Optional[float] = None
    percent: Optional[float] = None
    stage_percent: Optional[float] = None
    status: Optional[str] = None
    stage: Optional[str] = None
    stage_name: Optional[str] = None
    message: Optional[str] = None
    filename: Optional[str] = None
    tmpfilename: Optional[str] = None
    main_file: Optional[str] = None
    state: Optional[str] = None
    timestamp: Optional[str] = None

    def to_payload(self) -> PlaylistEntryProgressSnapshotPayload:
        raw = cast(dict[str, object], asdict(self))
        return cast(PlaylistEntryProgressSnapshotPayload, _to_json_dict(raw))

    def has_data(self) -> bool:
        raw = cast(dict[str, object], asdict(self))
        return bool(_strip_empty(raw))

    @classmethod
    def from_payload(
        cls, payload: Mapping[str, object]
    ) -> "PlaylistEntryProgressSnapshot":
        return cls(
            downloaded_bytes=_coerce_int(payload.get("downloaded_bytes")),
            total_bytes=_coerce_int(payload.get("total_bytes")),
            speed=_coerce_float(payload.get("speed")),
            eta=_coerce_int(payload.get("eta")),
            elapsed=_coerce_float(payload.get("elapsed")),
            percent=_coerce_float(payload.get("percent")),
            stage_percent=_coerce_float(payload.get("stage_percent")),
            status=_coerce_str(payload.get("status")),
            stage=_coerce_str(payload.get("stage")),
            stage_name=_coerce_str(payload.get("stage_name")),
            message=_coerce_str(payload.get("message")),
            filename=_coerce_str(payload.get("filename")),
            tmpfilename=_coerce_str(payload.get("tmpfilename")),
            main_file=_coerce_str(payload.get("main_file")),
            state=_coerce_str(payload.get("state")),
            timestamp=_coerce_str(payload.get("timestamp")),
        )


@dataclass(slots=True)
class PlaylistEntryReference:
    """Lightweight identifier pointing to a playlist entry."""

    index: int
    entry_id: Optional[str] = None
    status: Optional[str] = None

    def to_payload(self) -> PlaylistEntryReferencePayload:
        payload: dict[str, object] = {"index": self.index}
        if self.entry_id:
            payload["id"] = self.entry_id
        if self.status:
            payload["status"] = self.status
        return cast(PlaylistEntryReferencePayload, _to_json_dict(payload))

    @classmethod
    def from_payload(cls, payload: Mapping[str, object]) -> "PlaylistEntryReference":
        index = _coerce_int(payload.get("index")) or 0
        entry_id = _coerce_str(payload.get("id") or payload.get("entry_id"))
        status = _coerce_str(payload.get("status"))
        return cls(index=index, entry_id=entry_id, status=status)


@dataclass(slots=True)
class PlaylistEntryMetadata:
    """Information describing a single playlist entry."""

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
    thumbnails: list[Thumbnail] = field(default_factory=_empty_thumbnail_list)
    availability: Optional[str] = None
    live_status: Optional[str] = None
    view_count: Optional[int] = None
    channel_is_verified: Optional[bool] = None
    status: Optional[str] = None
    is_completed: bool = False
    is_current: bool = False
    preview: Optional[PreviewMetadata] = None
    progress_snapshot: Optional[PlaylistEntryProgressSnapshot] = None
    main_file: Optional[str] = None

    def to_payload(self) -> PlaylistEntryMetadataPayload:
        payload: dict[str, object] = {
            "index": self.index,
        }
        if self.entry_id:
            payload["id"] = self.entry_id
        for key in (
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
            "availability",
            "live_status",
            "status",
            "main_file",
        ):
            value = getattr(self, key)
            if value:
                payload[key] = value
        if self.duration_seconds is not None:
            payload["duration_seconds"] = self.duration_seconds
        if self.view_count is not None:
            payload["view_count"] = self.view_count
        if self.channel_is_verified is not None:
            payload["channel_is_verified"] = self.channel_is_verified
        payload["is_completed"] = self.is_completed
        payload["is_current"] = self.is_current
        if self.thumbnails:
            payload["thumbnails"] = [thumb.to_payload() for thumb in self.thumbnails]
        if self.preview is not None:
            payload["preview"] = self.preview.to_payload()
        if self.progress_snapshot is not None:
            payload["progress_snapshot"] = self.progress_snapshot.to_payload()
        return cast(PlaylistEntryMetadataPayload, _to_json_dict(payload))

    def has_data(self) -> bool:
        return bool(self.to_payload())

    @classmethod
    def from_payload(cls, payload: Mapping[str, object]) -> "PlaylistEntryMetadata":
        thumbnails_payload = payload.get("thumbnails")
        thumbnails: list[Thumbnail] = []
        if isinstance(thumbnails_payload, Sequence):
            for entry in cast(Sequence[object], thumbnails_payload):
                if isinstance(entry, Mapping):
                    entry_mapping = cast(Mapping[str, object], entry)
                    if entry_mapping.get("url"):
                        thumbnails.append(Thumbnail.from_payload(entry_mapping))
        preview_payload = payload.get("preview")
        preview: Optional[PreviewMetadata] = None
        if isinstance(preview_payload, Mapping):
            preview = PreviewMetadata.from_payload(
                cast(Mapping[str, object], preview_payload)
            )
        progress_payload = payload.get("progress_snapshot")
        progress: Optional[PlaylistEntryProgressSnapshot] = None
        if isinstance(progress_payload, Mapping):
            progress = PlaylistEntryProgressSnapshot.from_payload(
                cast(Mapping[str, object], progress_payload)
            )
        return cls(
            index=_coerce_int(payload.get("index")) or 0,
            entry_id=_coerce_str(payload.get("id") or payload.get("entry_id")),
            title=_coerce_str(payload.get("title")),
            uploader=_coerce_str(payload.get("uploader")),
            uploader_id=_coerce_str(payload.get("uploader_id")),
            uploader_url=_coerce_str(payload.get("uploader_url")),
            channel=_coerce_str(payload.get("channel")),
            channel_id=_coerce_str(payload.get("channel_id")),
            channel_url=_coerce_str(payload.get("channel_url")),
            webpage_url=_coerce_str(payload.get("webpage_url")),
            duration_seconds=_coerce_int(payload.get("duration_seconds")),
            duration_text=_coerce_str(payload.get("duration_text")),
            thumbnail_url=_coerce_str(payload.get("thumbnail_url")),
            thumbnails=thumbnails,
            availability=_coerce_str(payload.get("availability")),
            live_status=_coerce_str(payload.get("live_status")),
            view_count=_coerce_int(payload.get("view_count")),
            channel_is_verified=_coerce_bool(payload.get("channel_is_verified")),
            status=_coerce_str(payload.get("status")),
            is_completed=bool(payload.get("is_completed")),
            is_current=bool(payload.get("is_current")),
            preview=preview,
            progress_snapshot=progress,
            main_file=_coerce_str(payload.get("main_file")),
        )


@dataclass(slots=True)
class PlaylistMetadata:
    """Metadata describing a playlist and its entries."""

    playlist_id: Optional[str] = None
    entries_endpoint: Optional[str] = None
    entries_version: Optional[int] = None
    entries_external: Optional[bool] = None
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
    thumbnails: list[Thumbnail] = field(default_factory=_empty_thumbnail_list)
    entry_count: Optional[int] = None
    total_items: Optional[int] = None
    completed_items: Optional[int] = None
    pending_items: Optional[int] = None
    percent: Optional[float] = None
    current_index: Optional[int] = None
    current_entry_id: Optional[str] = None
    selected_indices: list[int] = field(default_factory=_empty_int_list)
    entries: list[PlaylistEntryMetadata] = field(
        default_factory=_empty_entry_metadata_list
    )
    entry_refs: list[PlaylistEntryReference] = field(
        default_factory=_empty_entry_reference_list
    )
    received_count: Optional[int] = None
    is_collecting_entries: Optional[bool] = None
    has_indefinite_length: Optional[bool] = None
    collection_complete: Optional[bool] = None
    collection_error: Optional[str] = None
    availability: Optional[str] = None
    live_status: Optional[str] = None
    channel_follower_count: Optional[int] = None
    channel_is_verified: Optional[bool] = None
    tags: list[str] = field(default_factory=_empty_str_list)
    collected_at: Optional[str] = None

    def to_payload(self, *, include_entries: bool = True) -> PlaylistMetadataPayload:
        payload: dict[str, object] = {}
        if self.playlist_id:
            payload["playlist_id"] = self.playlist_id
            payload.setdefault("id", self.playlist_id)
        for key in (
            "entries_endpoint",
            "title",
            "uploader",
            "uploader_id",
            "uploader_url",
            "channel",
            "channel_id",
            "channel_url",
            "description",
            "description_short",
            "webpage_url",
            "thumbnail_url",
            "availability",
            "live_status",
            "collected_at",
        ):
            value = getattr(self, key)
            if value:
                payload[key] = value
        for key in (
            "entry_count",
            "total_items",
            "completed_items",
            "pending_items",
            "current_index",
            "received_count",
            "channel_follower_count",
        ):
            value = getattr(self, key)
            if isinstance(value, int):
                payload[key] = value
        if self.entries_version is not None:
            payload["entries_version"] = int(self.entries_version)
        if self.percent is not None:
            payload["percent"] = float(self.percent)
        if self.current_entry_id:
            payload["current_entry_id"] = self.current_entry_id
        if self.selected_indices:
            payload["selected_indices"] = list(self.selected_indices)
        if self.entry_refs:
            payload["entry_refs"] = [ref.to_payload() for ref in self.entry_refs]
        if self.thumbnails:
            payload["thumbnails"] = [thumb.to_payload() for thumb in self.thumbnails]
        if self.tags:
            payload["tags"] = list(self.tags)
        if self.is_collecting_entries is not None:
            payload["is_collecting_entries"] = self.is_collecting_entries
        if self.has_indefinite_length is not None:
            payload["has_indefinite_length"] = self.has_indefinite_length
        if self.collection_complete is not None:
            payload["collection_complete"] = self.collection_complete
        if self.collection_error:
            payload["collection_error"] = self.collection_error
        if self.channel_is_verified is not None:
            payload["channel_is_verified"] = self.channel_is_verified
        if self.entries_external is not None:
            payload["entries_external"] = self.entries_external
        if include_entries and self.entries:
            payload["entries"] = [entry.to_payload() for entry in self.entries]
        return cast(PlaylistMetadataPayload, _to_json_dict(payload))

    def has_data(self) -> bool:
        return bool(self.to_payload())

    @classmethod
    def from_payload(cls, payload: Mapping[str, object]) -> "PlaylistMetadata":
        thumbnails_payload = payload.get("thumbnails")
        thumbnails: list[Thumbnail] = []
        if isinstance(thumbnails_payload, Sequence):
            for entry in cast(Sequence[object], thumbnails_payload):
                if isinstance(entry, Mapping):
                    entry_mapping = cast(Mapping[str, object], entry)
                    if entry_mapping.get("url"):
                        thumbnails.append(Thumbnail.from_payload(entry_mapping))

        entries_payload = payload.get("entries")
        entries: list[PlaylistEntryMetadata] = []
        if isinstance(entries_payload, Sequence):
            for entry in cast(Sequence[object], entries_payload):
                if isinstance(entry, Mapping):
                    entries.append(
                        PlaylistEntryMetadata.from_payload(
                            cast(Mapping[str, object], entry)
                        )
                    )

        entry_refs_payload = payload.get("entry_refs")
        entry_refs: list[PlaylistEntryReference] = []
        if isinstance(entry_refs_payload, Sequence):
            for ref in cast(Sequence[object], entry_refs_payload):
                if isinstance(ref, Mapping):
                    entry_refs.append(
                        PlaylistEntryReference.from_payload(
                            cast(Mapping[str, object], ref)
                        )
                    )

        tags_payload = payload.get("tags")
        tags: list[str] = []
        if isinstance(tags_payload, Sequence):
            for entry in cast(Sequence[object], tags_payload):
                if isinstance(entry, str) and entry.strip():
                    tags.append(entry.strip())

        selected_payload = payload.get("selected_indices")
        selected_indices: list[int] = []
        if isinstance(selected_payload, Sequence):
            for item in cast(Sequence[object], selected_payload):
                index = _coerce_int(item)
                if index is not None and index > 0:
                    selected_indices.append(index)

        return cls(
            playlist_id=_coerce_str(payload.get("playlist_id") or payload.get("id")),
            entries_endpoint=_coerce_str(payload.get("entries_endpoint")),
            entries_version=_coerce_int(payload.get("entries_version")),
            entries_external=_coerce_bool(payload.get("entries_external")),
            title=_coerce_str(payload.get("title")),
            uploader=_coerce_str(payload.get("uploader")),
            uploader_id=_coerce_str(payload.get("uploader_id")),
            uploader_url=_coerce_str(payload.get("uploader_url")),
            channel=_coerce_str(payload.get("channel")),
            channel_id=_coerce_str(payload.get("channel_id")),
            channel_url=_coerce_str(payload.get("channel_url")),
            description=_coerce_str(payload.get("description")),
            description_short=_coerce_str(payload.get("description_short")),
            webpage_url=_coerce_str(payload.get("webpage_url")),
            thumbnail_url=_coerce_str(payload.get("thumbnail_url")),
            thumbnails=thumbnails,
            entry_count=_coerce_int(payload.get("entry_count")),
            total_items=_coerce_int(payload.get("total_items")),
            completed_items=_coerce_int(payload.get("completed_items")),
            pending_items=_coerce_int(payload.get("pending_items")),
            percent=_coerce_float(payload.get("percent")),
            current_index=_coerce_int(payload.get("current_index")),
            current_entry_id=_coerce_str(payload.get("current_entry_id")),
            selected_indices=selected_indices,
            entries=entries,
            entry_refs=entry_refs,
            tags=tags,
            received_count=_coerce_int(payload.get("received_count")),
            is_collecting_entries=_coerce_bool(payload.get("is_collecting_entries")),
            has_indefinite_length=_coerce_bool(payload.get("has_indefinite_length")),
            collection_complete=_coerce_bool(payload.get("collection_complete")),
            collection_error=_coerce_str(payload.get("collection_error")),
            availability=_coerce_str(payload.get("availability")),
            live_status=_coerce_str(payload.get("live_status")),
            channel_follower_count=_coerce_int(payload.get("channel_follower_count")),
            channel_is_verified=_coerce_bool(payload.get("channel_is_verified")),
            collected_at=_coerce_str(payload.get("collected_at")),
        )
