"""Typed payload models describing playlist-related websocket messages."""

from __future__ import annotations

from dataclasses import dataclass
from typing import List, Optional

from ...models.shared import (
    PlaylistEntryMetadata,
    PlaylistEntryProgressSnapshot,
    PlaylistMetadata,
    PreviewMetadata,
    Thumbnail,
)

from .base import SocketPayload

# These aliases keep the socket type names stable while reusing shared models.
ThumbnailSummary = Thumbnail
PreviewSummary = PreviewMetadata
PlaylistEntrySummary = PlaylistEntryMetadata
PlaylistSummary = PlaylistMetadata


@dataclass(slots=True)
class GlobalInfoPayload(SocketPayload):
    """Payload broadcast through the GLOBAL_INFO channel."""

    status: str
    kind: Optional[str]
    is_playlist: bool
    selection_required: bool
    preview: Optional[PreviewSummary] = None
    playlist: Optional[PlaylistSummary] = None
    playlist_total_items: Optional[int] = None
    timestamp: Optional[str] = None


@dataclass(slots=True)
class EntryInfoPayload(SocketPayload):
    """Payload sent as each playlist entry is discovered."""

    entry: PlaylistEntrySummary
    received_count: int
    index: int
    entry_count: Optional[int] = None
    timestamp: Optional[str] = None


@dataclass(slots=True)
class ListInfoEndsPayload(SocketPayload):
    """Payload signalling the end of playlist entry enumeration."""

    entries: List[PlaylistEntrySummary]
    entry_count: Optional[int] = None
    error: Optional[str] = None
    timestamp: Optional[str] = None


__all__ = [
    "ThumbnailSummary",
    "PreviewSummary",
    "PlaylistEntrySummary",
    "PlaylistSummary",
    "PlaylistEntryProgressSnapshot",
    "GlobalInfoPayload",
    "EntryInfoPayload",
    "ListInfoEndsPayload",
]
