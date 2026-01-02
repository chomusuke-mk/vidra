from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping, Optional, TypedDict, cast

from ..shared import IsoTimestamp, JSONValue, get_int, get_str


class PlaylistEntryErrorPayload(TypedDict, total=False):
    index: int
    entry_id: str
    url: str
    message: str
    recorded_at: IsoTimestamp
    last_status: str
    pending_retry: bool


@dataclass(slots=True)
class PlaylistEntryError:
    index: int
    entry_id: Optional[str] = None
    url: Optional[str] = None
    message: Optional[str] = None
    recorded_at: Optional[IsoTimestamp] = None
    last_status: Optional[str] = None

    def to_json(self) -> PlaylistEntryErrorPayload:
        payload: PlaylistEntryErrorPayload = {"index": max(self.index, 0)}
        if self.entry_id:
            payload["entry_id"] = self.entry_id
        if self.url:
            payload["url"] = self.url
        if self.message:
            payload["message"] = self.message
        if self.recorded_at:
            payload["recorded_at"] = self.recorded_at
        if self.last_status:
            payload["last_status"] = self.last_status
        return payload

    @classmethod
    def from_json(cls, payload: PlaylistEntryErrorPayload) -> "PlaylistEntryError":
        mapping = cast(Mapping[str, JSONValue], payload)
        index_value = get_int(mapping, "index")
        if not index_value or index_value <= 0:
            raise ValueError("playlist entry error payload requires a positive index")
        return cls(
            index=index_value,
            entry_id=get_str(mapping, "entry_id"),
            url=get_str(mapping, "url"),
            message=get_str(mapping, "message"),
            recorded_at=get_str(mapping, "recorded_at"),
            last_status=get_str(mapping, "last_status"),
        )

    def matches(self, *, entry_id: Optional[str], url: Optional[str]) -> bool:
        entry_id_match = False
        if self.entry_id and entry_id:
            entry_id_match = self.entry_id.strip() == entry_id.strip()
        url_match = False
        if self.url and url:
            url_match = self.url.strip() == url.strip()
        if self.entry_id and entry_id:
            return entry_id_match
        if self.url and url:
            return url_match
        return entry_id_match or url_match


__all__ = ["PlaylistEntryError", "PlaylistEntryErrorPayload"]
