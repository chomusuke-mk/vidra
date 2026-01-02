"""Typed payload definition for progress updates."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from .base import SocketPayload


@dataclass(slots=True)
class ProgressPayload(SocketPayload):
    """Represents the ongoing progress reported to websocket clients."""

    status: Optional[str] = None
    downloaded_bytes: Optional[int] = None
    total_bytes: Optional[int] = None
    remaining_bytes: Optional[int] = None
    speed: Optional[float] = None
    eta: Optional[int] = None
    elapsed: Optional[float] = None
    filename: Optional[str] = None
    tmpfilename: Optional[str] = None
    percent: Optional[float] = None
    ctx_id: Optional[str] = None
    stage: Optional[str] = None
    stage_name: Optional[str] = None
    stage_percent: Optional[float] = None
    current_item: Optional[int] = None
    total_items: Optional[int] = None
    message: Optional[str] = None
    playlist_index: Optional[int] = None
    playlist_current_index: Optional[int] = None
    playlist_count: Optional[int] = None
    playlist_total_items: Optional[int] = None
    playlist_completed_items: Optional[int] = None
    playlist_pending_items: Optional[int] = None
    playlist_percent: Optional[float] = None
    playlist_current_entry_id: Optional[str] = None
    playlist_newly_completed_index: Optional[int] = None
