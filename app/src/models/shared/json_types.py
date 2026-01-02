"""Shared JSON-compatible type aliases and helpers."""

from __future__ import annotations

from typing import Mapping, TypeAlias

JSONPrimitive: TypeAlias = str | int | float | bool | None
JSONValue: TypeAlias = JSONPrimitive | list["JSONValue"] | dict[str, "JSONValue"]
JsonList: TypeAlias = list[JSONValue]
JsonDict: TypeAlias = dict[str, JSONValue]


def clone_json_value(value: JSONValue) -> JSONValue:
    """Return a shallow-deep copy of a JSON value preserving nested structures."""

    if isinstance(value, list):
        return [clone_json_value(item) for item in value]
    if isinstance(value, dict):
        return {key: clone_json_value(item) for key, item in value.items()}
    return value


def clone_json_dict(value: Mapping[str, JSONValue]) -> JsonDict:
    """Clone a mapping that is known to use JSON-compatible keys and values."""

    return {key: clone_json_value(item) for key, item in value.items()}


def get_str(mapping: Mapping[str, JSONValue], key: str) -> str | None:
    value = mapping.get(key)
    return value if isinstance(value, str) else None


def get_int(mapping: Mapping[str, JSONValue], key: str) -> int | None:
    value = mapping.get(key)
    return value if isinstance(value, int) else None


def get_float(mapping: Mapping[str, JSONValue], key: str) -> float | None:
    value = mapping.get(key)
    if isinstance(value, (int, float)):
        return float(value)
    return None


def get_bool(mapping: Mapping[str, JSONValue], key: str) -> bool | None:
    value = mapping.get(key)
    return value if isinstance(value, bool) else None


def get_dict(mapping: Mapping[str, JSONValue], key: str) -> JsonDict | None:
    value = mapping.get(key)
    return value if isinstance(value, dict) else None


def get_list(mapping: Mapping[str, JSONValue], key: str) -> JsonList | None:
    value = mapping.get(key)
    return value if isinstance(value, list) else None
