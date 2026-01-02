"""Shared foundational helpers for Vidra domain models."""

from .json_types import (
    JSONPrimitive,
    JSONValue,
    JsonList,
    clone_json_dict,
    clone_json_value,
    get_bool,
    get_dict,
    get_float,
    get_int,
    get_list,
    get_str,
)
from .base import IsoTimestamp, ResourceRef, ensure_iso_timestamp
from .media import (
    PlaylistEntryMetadata,
    PlaylistEntryProgressSnapshot,
    PlaylistEntryReference,
    PlaylistMetadata,
    PreviewMetadata,
    Thumbnail,
)
from .payloads import (
    PlaylistEntryMetadataPayload,
    PlaylistEntryProgressSnapshotPayload,
    PlaylistEntryReferencePayload,
    PlaylistMetadataPayload,
    PreviewMetadataExtras,
    PreviewMetadataPayload,
    PreviewThumbnailPayload,
)

__all__ = [
    "JSONPrimitive",
    "JSONValue",
    "JsonList",
    "clone_json_dict",
    "clone_json_value",
    "get_bool",
    "get_dict",
    "get_float",
    "get_int",
    "get_list",
    "get_str",
    "IsoTimestamp",
    "ResourceRef",
    "ensure_iso_timestamp",
    "Thumbnail",
    "PreviewMetadata",
    "PlaylistEntryMetadata",
    "PlaylistEntryProgressSnapshot",
    "PlaylistEntryReference",
    "PlaylistMetadata",
    "PreviewThumbnailPayload",
    "PreviewMetadataPayload",
    "PreviewMetadataExtras",
    "PlaylistEntryMetadataPayload",
    "PlaylistEntryReferencePayload",
    "PlaylistEntryProgressSnapshotPayload",
    "PlaylistMetadataPayload",
]
