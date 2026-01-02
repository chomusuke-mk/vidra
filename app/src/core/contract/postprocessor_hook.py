from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, TYPE_CHECKING

from .info import Info

if TYPE_CHECKING:
    from ...core.downloader import PostProcessorHookArgs

@dataclass(frozen=True, init=False)
class PostprocessorHook:
    """Normalized view over ``yt_dlp`` postprocessor hook payloads.

    Attributes:
        status: Lower-cased status string, e.g. ``started`` or ``finished``.
        postprocessor: Name of the postprocessor that issued the hook.
        message: Optional contextual message describing the current stage.
        percent: Completion percentage for the current postprocessor stage.
        playlist_index: Playlist entry index (1-based) when applicable.
        playlist_id: Identifier for the playlist entry being processed when known.
        entry_id: Identifier for the current entry processed by the postprocessor.
        info: Lightweight :class:`Info` derived from ``info_dict`` when present.
    """

    status: Optional[str]
    postprocessor: Optional[str]
    message: Optional[str]
    percent: Optional[float]
    playlist_index: Optional[int]
    playlist_id: Optional[str]
    entry_id: Optional[str]
    info: Optional[Info]

    def __init__(self, payload: "PostProcessorHookArgs") -> None:
        status = payload["status"].lower()
        postprocessor = payload["postprocessor"]
        message = payload.get("message")
        percent = payload.get("percent")
        playlist_index = payload.get("playlist_index")
        entry_id = payload.get("entry_id")
        playlist_id = payload.get("playlist_id")

        info_dict = payload.get("info_dict")
        info = Info.fast_info(info_dict) if info_dict else None

        if playlist_index is None and info and info.playlist_index is not None:
            playlist_index = info.playlist_index
        if entry_id is None and info and info.id:
            entry_id = info.id
        if playlist_id is None and info and info.id:
            playlist_id = info.id

        object.__setattr__(self, "status", status)
        object.__setattr__(self, "postprocessor", postprocessor)
        object.__setattr__(self, "message", message)
        object.__setattr__(self, "percent", percent)
        object.__setattr__(self, "playlist_index", playlist_index)
        object.__setattr__(self, "playlist_id", playlist_id)
        object.__setattr__(self, "entry_id", entry_id)
        object.__setattr__(self, "info", info)
