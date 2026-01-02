"""Common helpers for typed websocket payloads."""

from __future__ import annotations

from dataclasses import dataclass, fields, is_dataclass
from typing import Any, Mapping, Required, Sequence, TypedDict, cast

from ...models.shared import JSONValue


class SocketPayloadDict(TypedDict, total=False):
    job_id: Required[str]
    reason: str
    timestamp: str


@dataclass(slots=True)
class SocketPayload:
    """Base dataclass for payloads emitted to websocket clients."""

    job_id: str

    def to_dict(self) -> SocketPayloadDict:
        """Return a JSON-serialisable representation of the payload."""

        raw_payload = _strip_none(_convert_payload_value(self))
        if isinstance(raw_payload, dict):
            return cast(SocketPayloadDict, raw_payload)
        raise TypeError("socket payloads must serialize into mappings")


def _strip_none(value: Any) -> JSONValue:
    """Recursively drop ``None`` values from dataclass payloads."""

    if isinstance(value, Mapping):
        mapping = cast(Mapping[str, JSONValue], value)
        return {
            key: _strip_none(item) for key, item in mapping.items() if item is not None
        }
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray)):
        sequence = cast(Sequence[object], value)
        cleaned_list: list[JSONValue] = []
        for item in sequence:
            if item is None:
                continue
            cleaned_list.append(_strip_none(item))
        return cleaned_list
    if is_dataclass(value) and not isinstance(value, type):
        return _strip_none(_convert_payload_value(value))
    if value is None:
        return None
    if isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="ignore")
    return str(value)


def _convert_payload_value(value: Any) -> JSONValue:
    """Map dataclass or shared model instances into socket-friendly dicts."""

    if value is None:
        return None
    to_payload = getattr(value, "to_payload", None)
    if callable(to_payload):
        return cast(JSONValue, to_payload())
    if is_dataclass(value) and not isinstance(value, type):
        data: dict[str, JSONValue] = {}
        for field_info in fields(value):
            data[field_info.name] = _convert_payload_value(
                getattr(value, field_info.name)
            )
        return data
    if isinstance(value, Mapping):
        mapping = cast(Mapping[str, JSONValue], value)
        return {
            key: _convert_payload_value(item)
            for key, item in mapping.items()
            if item is not None
        }
    if isinstance(value, Sequence) and not isinstance(value, (str, bytes, bytearray)):
        sequence = cast(Sequence[object], value)
        cleaned_list: list[JSONValue] = []
        for item in sequence:
            if item is None:
                continue
            cleaned_list.append(_convert_payload_value(item))
        return cleaned_list
    if isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="ignore")
    return str(value)
