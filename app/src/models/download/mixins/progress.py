"""Typed representation for download and playlist progress."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Optional, TypedDict

from ...shared import IsoTimestamp


class ProgressSnapshotPayload(TypedDict, total=False):
    status: str
    percent: float
    stage: str
    stage_name: str
    stage_percent: float
    downloaded_bytes: float
    total_bytes: float
    remaining_bytes: float
    speed: float
    eta: float
    elapsed: float
    current_item: int
    total_items: int
    message: str
    filename: str
    tmpfilename: str
    ctx_id: str
    playlist_index: int
    playlist_current_entry_id: str
    playlist_total_items: int
    timestamp: IsoTimestamp
    state: str


class PlaylistProgressSnapshotPayload(TypedDict, total=False):
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
    state: str
    timestamp: IsoTimestamp


@dataclass(slots=True)
class ProgressSnapshot:
    status: Optional[str] = None
    percent: Optional[float] = None
    stage: Optional[str] = None
    stage_name: Optional[str] = None
    stage_percent: Optional[float] = None
    downloaded_bytes: Optional[float] = None
    total_bytes: Optional[float] = None
    remaining_bytes: Optional[float] = None
    speed: Optional[float] = None
    eta: Optional[float] = None
    elapsed: Optional[float] = None
    current_item: Optional[int] = None
    total_items: Optional[int] = None
    message: Optional[str] = None
    filename: Optional[str] = None
    tmpfilename: Optional[str] = None
    ctx_id: Optional[str] = None
    playlist_index: Optional[int] = None
    playlist_current_entry_id: Optional[str] = None
    playlist_total_items: Optional[int] = None
    timestamp: Optional[IsoTimestamp] = None
    state: Optional[str] = None

    def to_json(self) -> ProgressSnapshotPayload:
        payload: ProgressSnapshotPayload = {}
        _assign_progress_str(payload, "status", self.status)
        _assign_progress_str(payload, "stage", self.stage)
        _assign_progress_str(payload, "stage_name", self.stage_name)
        _assign_progress_str(payload, "message", self.message)
        _assign_progress_str(payload, "filename", self.filename)
        _assign_progress_str(payload, "tmpfilename", self.tmpfilename)
        _assign_progress_str(payload, "ctx_id", self.ctx_id)
        _assign_progress_str(
            payload, "playlist_current_entry_id", self.playlist_current_entry_id
        )
        _assign_progress_str(payload, "state", self.state)
        _assign_progress_str(payload, "timestamp", self.timestamp)

        _assign_progress_float(payload, "percent", self.percent)
        _assign_progress_float(payload, "stage_percent", self.stage_percent)
        _assign_progress_float(payload, "downloaded_bytes", self.downloaded_bytes)
        _assign_progress_float(payload, "total_bytes", self.total_bytes)
        _assign_progress_float(payload, "remaining_bytes", self.remaining_bytes)
        _assign_progress_float(payload, "speed", self.speed)
        _assign_progress_float(payload, "eta", self.eta)
        _assign_progress_float(payload, "elapsed", self.elapsed)

        _assign_progress_int(payload, "current_item", self.current_item)
        _assign_progress_int(payload, "total_items", self.total_items)
        _assign_progress_int(payload, "playlist_index", self.playlist_index)
        _assign_progress_int(payload, "playlist_total_items", self.playlist_total_items)
        return payload

    @classmethod
    def from_json(cls, data: ProgressSnapshotPayload) -> "ProgressSnapshot":
        return cls(
            status=_coerce_str(data.get("status")),
            percent=_coerce_float(data.get("percent")),
            stage=_coerce_str(data.get("stage")),
            stage_name=_coerce_str(data.get("stage_name")),
            stage_percent=_coerce_float(data.get("stage_percent")),
            downloaded_bytes=_coerce_float(data.get("downloaded_bytes")),
            total_bytes=_coerce_float(data.get("total_bytes")),
            remaining_bytes=_coerce_float(data.get("remaining_bytes")),
            speed=_coerce_float(data.get("speed")),
            eta=_coerce_float(data.get("eta")),
            elapsed=_coerce_float(data.get("elapsed")),
            current_item=_coerce_int(data.get("current_item")),
            total_items=_coerce_int(data.get("total_items")),
            message=_coerce_str(data.get("message")),
            filename=_coerce_str(data.get("filename")),
            tmpfilename=_coerce_str(data.get("tmpfilename")),
            ctx_id=_coerce_str(data.get("ctx_id")),
            playlist_index=_coerce_int(data.get("playlist_index")),
            playlist_current_entry_id=_coerce_str(
                data.get("playlist_current_entry_id")
            ),
            playlist_total_items=_coerce_int(data.get("playlist_total_items")),
            timestamp=_coerce_str(data.get("timestamp")),
            state=_coerce_str(data.get("state")),
        )


@dataclass(slots=True)
class PlaylistProgressSnapshot:
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
    state: Optional[str] = None
    timestamp: Optional[IsoTimestamp] = None

    def to_json(self) -> PlaylistProgressSnapshotPayload:
        payload: PlaylistProgressSnapshotPayload = {}
        _assign_playlist_str(payload, "status", self.status)
        _assign_playlist_str(payload, "stage", self.stage)
        _assign_playlist_str(payload, "stage_name", self.stage_name)
        _assign_playlist_str(payload, "message", self.message)
        _assign_playlist_str(payload, "state", self.state)
        _assign_playlist_str(payload, "timestamp", self.timestamp)

        _assign_playlist_int(payload, "downloaded_bytes", self.downloaded_bytes)
        _assign_playlist_int(payload, "total_bytes", self.total_bytes)
        _assign_playlist_int(payload, "eta", self.eta)

        _assign_playlist_float(payload, "speed", self.speed)
        _assign_playlist_float(payload, "elapsed", self.elapsed)
        _assign_playlist_float(payload, "percent", self.percent)
        _assign_playlist_float(payload, "stage_percent", self.stage_percent)
        return payload

    @classmethod
    def from_json(
        cls, data: PlaylistProgressSnapshotPayload
    ) -> "PlaylistProgressSnapshot":
        return cls(
            downloaded_bytes=_coerce_int(data.get("downloaded_bytes")),
            total_bytes=_coerce_int(data.get("total_bytes")),
            speed=_coerce_float(data.get("speed")),
            eta=_coerce_int(data.get("eta")),
            elapsed=_coerce_float(data.get("elapsed")),
            percent=_coerce_float(data.get("percent")),
            stage_percent=_coerce_float(data.get("stage_percent")),
            status=_coerce_str(data.get("status")),
            stage=_coerce_str(data.get("stage")),
            stage_name=_coerce_str(data.get("stage_name")),
            message=_coerce_str(data.get("message")),
            state=_coerce_str(data.get("state")),
            timestamp=_coerce_str(data.get("timestamp")),
        )


def _coerce_str(value: object | None) -> str | None:
    return value if isinstance(value, str) else None


def _coerce_int(value: object | None) -> int | None:
    if isinstance(value, bool):
        return None
    return value if isinstance(value, int) else None


def _coerce_float(value: object | None) -> float | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    return None


ProgressStrKey = Literal[
    "status",
    "stage",
    "stage_name",
    "message",
    "filename",
    "tmpfilename",
    "ctx_id",
    "playlist_current_entry_id",
    "state",
    "timestamp",
]
ProgressFloatKey = Literal[
    "percent",
    "stage_percent",
    "downloaded_bytes",
    "total_bytes",
    "remaining_bytes",
    "speed",
    "eta",
    "elapsed",
]
ProgressIntKey = Literal[
    "current_item",
    "total_items",
    "playlist_index",
    "playlist_total_items",
]


def _assign_progress_str(
    payload: ProgressSnapshotPayload, key: ProgressStrKey, value: Optional[str]
) -> None:
    if value:
        payload[key] = value


def _assign_progress_float(
    payload: ProgressSnapshotPayload, key: ProgressFloatKey, value: Optional[float]
) -> None:
    if value is not None:
        payload[key] = float(value)


def _assign_progress_int(
    payload: ProgressSnapshotPayload, key: ProgressIntKey, value: Optional[int]
) -> None:
    if value is not None:
        payload[key] = value


PlaylistStrKey = Literal[
    "status",
    "stage",
    "stage_name",
    "message",
    "state",
    "timestamp",
]
PlaylistIntKey = Literal["downloaded_bytes", "total_bytes", "eta"]
PlaylistFloatKey = Literal["speed", "elapsed", "percent", "stage_percent"]


def _assign_playlist_str(
    payload: PlaylistProgressSnapshotPayload,
    key: PlaylistStrKey,
    value: Optional[str],
) -> None:
    if value:
        payload[key] = value


def _assign_playlist_int(
    payload: PlaylistProgressSnapshotPayload,
    key: PlaylistIntKey,
    value: Optional[int],
) -> None:
    if value is not None:
        payload[key] = value


def _assign_playlist_float(
    payload: PlaylistProgressSnapshotPayload,
    key: PlaylistFloatKey,
    value: Optional[float],
) -> None:
    if value is not None:
        payload[key] = float(value)


__all__ = [
    "ProgressSnapshot",
    "PlaylistProgressSnapshot",
    "ProgressSnapshotPayload",
    "PlaylistProgressSnapshotPayload",
]
