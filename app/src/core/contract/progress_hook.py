from __future__ import annotations

from dataclasses import dataclass
from typing import Optional, TYPE_CHECKING

from .info import Info

if TYPE_CHECKING:
    from ...core.downloader import ProgressHookArgs

@dataclass(frozen=True, init=False)
class ProgressHook:
    """Normalized view over ``yt_dlp`` progress hook payloads.

    Attributes:
        status: Lower-cased textual status such as ``downloading`` or ``finished``.
        message: Optional human readable status message.
        downloaded_bytes: Bytes already downloaded for the current entry.
        total_bytes: Expected total bytes for the download when reported.
        remaining_bytes: Computed remaining bytes ensuring non-negative output.
        percent: Completion percentage rounded to two decimal places.
        tmpfilename: Temporary filename used by yt-dlp while downloading.
        filename: Final output filename when known.
        eta: Estimated time of arrival in seconds if provided by yt-dlp.
        speed: Current download speed in bytes per second when available.
        elapsed: Seconds elapsed since yt-dlp started processing the entry.
        playlist_index: Position within the playlist when applicable.
        playlist_count: Total number of entries in the playlist when known.
        entry_id: Identifier for the current entry.
        current_item: Current playlist item number reported by yt-dlp.
        total_items: Total playlist items reported by yt-dlp.
        ctx_id: Optional context identifier passed through yt-dlp hooks.
        info: Lightweight :class:`Info` generated from ``info_dict`` when present.
    """

    status: Optional[str]
    message: Optional[str]
    downloaded_bytes: Optional[float]
    total_bytes: Optional[float]
    remaining_bytes: Optional[float]
    percent: Optional[float]
    tmpfilename: Optional[str]
    filename: Optional[str]
    eta: Optional[float]
    speed: Optional[float]
    elapsed: Optional[float]
    playlist_index: Optional[int]
    playlist_count: Optional[int]
    playlist_id: Optional[str]
    entry_id: Optional[str]
    current_item: Optional[int]
    total_items: Optional[int]
    ctx_id: Optional[str]
    info: Optional[Info]

    def __init__(self, payload: "ProgressHookArgs") -> None:
        def _as_float(value: Optional[int | float]) -> Optional[float]:
            if value is None:
                return None
            return float(value)

        status = payload["status"]
        message = payload.get("message")

        downloaded = _as_float(payload.get("downloaded_bytes"))
        total = _as_float(payload.get("total_bytes"))

        remaining: Optional[float] = None
        if downloaded is not None and total is not None:
            remaining = max(total - downloaded, 0.0)

        percent = payload.get("percent")
        tmpfilename = payload.get("tmpfilename")
        filename = payload.get("filename")
        eta = payload.get("eta")
        speed = payload.get("speed")
        elapsed = payload.get("elapsed")

        info_dict = payload["info_dict"]
        info = Info.fast_info(info_dict)

        playlist_index = payload.get("playlist_index")
        if playlist_index is None and info.playlist_index is not None:
            playlist_index = info.playlist_index

        playlist_count = payload.get("playlist_count")
        if playlist_count is None and info.entry_count is not None:
            playlist_count = info.entry_count

        entry_id = payload.get("entry_id") or info.id

        playlist_id = payload.get("playlist_id") or info.id

        current_item = payload.get("current_item")
        total_items = payload.get("total_items")

        ctx_id = payload.get("ctx_id")

        object.__setattr__(self, "status", status)
        object.__setattr__(self, "message", message)
        object.__setattr__(self, "downloaded_bytes", downloaded)
        object.__setattr__(self, "total_bytes", total)
        object.__setattr__(self, "remaining_bytes", remaining)
        object.__setattr__(self, "percent", percent)
        object.__setattr__(self, "tmpfilename", tmpfilename)
        object.__setattr__(self, "filename", filename)
        object.__setattr__(self, "eta", eta)
        object.__setattr__(self, "speed", speed)
        object.__setattr__(self, "elapsed", elapsed)
        object.__setattr__(self, "playlist_index", playlist_index)
        object.__setattr__(self, "playlist_count", playlist_count)
        object.__setattr__(self, "playlist_id", playlist_id)
        object.__setattr__(self, "entry_id", entry_id)
        object.__setattr__(self, "current_item", current_item)
        object.__setattr__(self, "total_items", total_items)
        object.__setattr__(self, "ctx_id", ctx_id)
        object.__setattr__(self, "info", info)
