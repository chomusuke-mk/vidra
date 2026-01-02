"""Base Marshmallow schemas and helpers for Vidra."""

from __future__ import annotations

from typing import Any

from marshmallow import EXCLUDE, Schema  # type: ignore[import-not-found]


def _camel_case(name: str) -> str:
    parts = name.split("_")
    return (
        parts[0] + "".join(part.capitalize() for part in parts[1:]) if parts else name
    )


class VidraSchema(Schema):
    """Default schema with common configuration (ordered output, ignore unknown)."""

    class Meta:
        ordered = True
        unknown = EXCLUDE

    def on_bind_field(self, field_name: str, field_obj: Any) -> None:  # type: ignore[override]
        super().on_bind_field(field_name, field_obj)
        if not getattr(field_obj, "data_key", None):
            field_obj.data_key = _camel_case(field_name)


__all__ = ["VidraSchema"]
