from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable, List, Literal, Mapping, Optional, Tuple, TypedDict, cast

from ...shared import (
    IsoTimestamp,
    JSONValue,
    PlaylistEntryMetadataPayload,
    PlaylistEntryProgressSnapshotPayload,
    PlaylistEntryReferencePayload,
    PlaylistMetadataPayload,
    PreviewMetadataExtras,
    PreviewMetadataPayload,
    PreviewThumbnailPayload,
    clone_json_value,
    get_bool,
    get_int,
    get_str,
)


def _thumbnail_data_list_factory() -> List["ThumbnailData"]:
    return []


def _metadata_dict_factory() -> PreviewMetadataExtras:
    return cast(PreviewMetadataExtras, {})


class PlaylistEntryPayload(PlaylistEntryMetadataPayload, total=False):
    id: str
    url: str
    state_hint: str
    job_id: str
    progress: PlaylistEntryProgressSnapshotPayload


class PlaylistSnapshotPayload(TypedDict, total=False):
    job_id: str
    status: str
    playlist: PlaylistMetadataPayload
    timestamp: IsoTimestamp


PreviewListInfoSnapshot = Tuple[
    List[PlaylistEntryPayload],
    Optional[int],
    Optional[str],
]


@dataclass(slots=True)
class ThumbnailData:
    url: str
    width: Optional[int] = None
    height: Optional[int] = None
    identifier: Optional[str] = None

    def to_json(self) -> PreviewThumbnailPayload:
        payload: PreviewThumbnailPayload = {"url": self.url}
        if self.width is not None:
            payload["width"] = self.width
        if self.height is not None:
            payload["height"] = self.height
        if self.identifier:
            payload["id"] = self.identifier
        return payload

    @classmethod
    def from_json(cls, data: PreviewThumbnailPayload) -> "ThumbnailData":
        data_map = cast(Mapping[str, JSONValue], data)
        return cls(
            url=str(data.get("url", "")) or "",
            width=get_int(data_map, "width"),
            height=get_int(data_map, "height"),
            identifier=get_str(data_map, "id"),
        )


@dataclass(slots=True)
class PreviewData:
    title: Optional[str] = None
    description: Optional[str] = None
    webpage_url: Optional[str] = None
    original_url: Optional[str] = None
    duration_text: Optional[str] = None
    duration_seconds: Optional[int] = None
    thumbnail_url: Optional[str] = None
    uploader: Optional[str] = None
    channel: Optional[str] = None
    upload_date_iso: Optional[IsoTimestamp] = None
    extractor: Optional[str] = None
    extractor_id: Optional[str] = None
    entry_id: Optional[str] = None
    view_count: Optional[int] = None
    like_count: Optional[int] = None
    thumbnails: List[ThumbnailData] = field(
        default_factory=_thumbnail_data_list_factory
    )
    is_playlist: bool | None = None
    metadata: PreviewMetadataExtras = field(default_factory=_metadata_dict_factory)

    def to_json(self) -> PreviewMetadataPayload:
        payload: PreviewMetadataPayload = {}
        _assign_preview_str(payload, "title", self.title)
        _assign_preview_str(payload, "description", self.description)
        _assign_preview_str(payload, "webpage_url", self.webpage_url)
        _assign_preview_str(payload, "original_url", self.original_url)
        _assign_preview_str(payload, "duration_text", self.duration_text)
        _assign_preview_str(payload, "thumbnail_url", self.thumbnail_url)
        _assign_preview_str(payload, "uploader", self.uploader)
        _assign_preview_str(payload, "channel", self.channel)
        _assign_preview_str(payload, "upload_date_iso", self.upload_date_iso)
        _assign_preview_str(payload, "extractor", self.extractor)
        _assign_preview_str(payload, "extractor_id", self.extractor_id)
        _assign_preview_str(payload, "entry_id", self.entry_id)

        _assign_preview_int(payload, "duration_seconds", self.duration_seconds)
        _assign_preview_int(payload, "view_count", self.view_count)
        _assign_preview_int(payload, "like_count", self.like_count)

        if self.is_playlist is not None:
            payload["is_playlist"] = self.is_playlist
        if self.thumbnails:
            payload["thumbnails"] = [thumb.to_json() for thumb in self.thumbnails]
        if self.metadata:
            metadata_json = clone_json_value(cast(JSONValue, self.metadata))
            payload["metadata"] = cast(PreviewMetadataExtras, metadata_json)
        return payload

    @classmethod
    def from_json(cls, data: PreviewMetadataPayload) -> "PreviewData":
        data_map = cast(Mapping[str, JSONValue], data)
        thumbnails_raw = data_map.get("thumbnails")
        thumbnails: List[ThumbnailData] = []
        if isinstance(thumbnails_raw, list):
            for entry in thumbnails_raw:
                if isinstance(entry, Mapping):
                    entry_map = cast(Mapping[str, JSONValue], entry)
                else:
                    continue
                if entry_map.get("url"):
                    thumbnails.append(
                        ThumbnailData.from_json(
                            cast(PreviewThumbnailPayload, entry_map)
                        )
                    )
        metadata_raw = data_map.get("metadata")
        metadata: PreviewMetadataExtras | None = None
        if isinstance(metadata_raw, dict):
            metadata_json = clone_json_value(cast(JSONValue, metadata_raw))
            metadata = cast(PreviewMetadataExtras, metadata_json)
        return cls(
            title=get_str(data_map, "title"),
            description=get_str(data_map, "description"),
            webpage_url=get_str(data_map, "webpage_url"),
            original_url=get_str(data_map, "original_url"),
            duration_text=get_str(data_map, "duration_text"),
            duration_seconds=get_int(data_map, "duration_seconds"),
            thumbnail_url=get_str(data_map, "thumbnail_url"),
            uploader=get_str(data_map, "uploader"),
            channel=get_str(data_map, "channel"),
            upload_date_iso=get_str(data_map, "upload_date_iso"),
            extractor=get_str(data_map, "extractor"),
            extractor_id=get_str(data_map, "extractor_id"),
            entry_id=get_str(data_map, "entry_id"),
            view_count=get_int(data_map, "view_count"),
            like_count=get_int(data_map, "like_count"),
            thumbnails=thumbnails,
            is_playlist=get_bool(data_map, "is_playlist"),
            metadata=metadata or cast(PreviewMetadataExtras, {}),
        )

    def update_from(self, other: "PreviewData") -> None:
        for field_name, value in other.__dict__.items():
            if value in (None, [], {}):
                continue
            setattr(self, field_name, value)

    @classmethod
    def from_thumbnails(
        cls, thumbnails: Iterable[ThumbnailData]
    ) -> List[PreviewThumbnailPayload]:
        return [thumb.to_json() for thumb in thumbnails]


__all__ = [
    "PlaylistEntryPayload",
    "PlaylistEntryProgressSnapshotPayload",
    "PlaylistEntryReferencePayload",
    "PlaylistMetadataPayload",
    "PlaylistSnapshotPayload",
    "PreviewListInfoSnapshot",
    "PreviewMetadataPayload",
    "PreviewThumbnailPayload",
    "PreviewData",
    "ThumbnailData",
]


PreviewStrKey = Literal[
    "title",
    "description",
    "webpage_url",
    "original_url",
    "duration_text",
    "thumbnail_url",
    "uploader",
    "channel",
    "upload_date_iso",
    "extractor",
    "extractor_id",
    "entry_id",
]

PreviewIntKey = Literal["duration_seconds", "view_count", "like_count"]


def _assign_preview_str(
    payload: PreviewMetadataPayload, key: PreviewStrKey, value: Optional[str]
) -> None:
    if value:
        payload[key] = value


def _assign_preview_int(
    payload: PreviewMetadataPayload, key: PreviewIntKey, value: Optional[int]
) -> None:
    if value is not None:
        payload[key] = value
