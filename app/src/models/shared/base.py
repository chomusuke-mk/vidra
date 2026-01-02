"""Foundational aliases shared by Vidra domain models."""

from __future__ import annotations

from dataclasses import dataclass

from .json_types import JSONValue

IsoTimestamp = str


def ensure_iso_timestamp(value: str | None) -> IsoTimestamp | None:
    """Return the string if it looks like an ISO timestamp, else ``None``."""

    if value is None:
        return None
    text = value.strip()
    return text or None


@dataclass(slots=True)
class ResourceRef:
    """Generic identifier wrapper used by several typed payloads."""

    id: str
    label: str | None = None

    def to_json(self) -> JSONValue:
        payload: dict[str, JSONValue] = {"id": self.id}
        if self.label:
            payload["label"] = self.label
        return payload
