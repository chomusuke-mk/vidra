"""Query parameter helpers validated via Marshmallow schemas."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from marshmallow import ValidationError, fields, post_load, validates

from ...schemas.base import VidraSchema


def _normalize_bool_flag(value: Any) -> bool | None:
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    if text in {"true", "1", "yes", "on", "full"}:
        return True
    if text in {"false", "0", "no", "off"}:
        return False
    return None


@dataclass(slots=True)
class OffsetLimitQueryParams:
    offset: int | None = None
    limit: int | None = None


@dataclass(slots=True)
class PlaylistSnapshotQueryParams(OffsetLimitQueryParams):
    include_entries: bool = False


@dataclass(slots=True)
class PlaylistItemsDeltaQueryParams:
    since_version: int | None = None


@dataclass(slots=True)
class JobOptionsQueryParams:
    since_version: int | None = None
    include_options: bool = False


@dataclass(slots=True)
class JobLogsQueryParams:
    since_version: int | None = None
    include_logs: bool = False
    limit: int | None = None


class OffsetLimitQuerySchema(VidraSchema):
    def __init__(self, *, max_limit: int | None = None, **kwargs: Any) -> None:
        super().__init__(**kwargs)
        self._max_limit = max_limit

    offset = fields.Integer(
        load_default=None,
        allow_none=True,
        error_messages={"invalid": "offset_not_integer"},
    )
    limit = fields.Integer(
        load_default=None,
        allow_none=True,
        error_messages={"invalid": "limit_not_integer"},
    )

    @validates("offset")
    def _validate_offset(self, value: int | None, **_: Any) -> None:
        if value is None:
            return
        if value < 0:
            raise ValidationError("offset_non_negative")

    @validates("limit")
    def _validate_limit(self, value: int | None, **_: Any) -> None:
        if value is None:
            return
        if value <= 0:
            raise ValidationError("limit_greater_than_zero")

    def _build_offset_limit(self, data: dict[str, Any]) -> OffsetLimitQueryParams:
        limit_value = data.get("limit")
        max_limit = self._max_limit
        if (
            limit_value is not None
            and max_limit is not None
            and limit_value > max_limit
        ):
            data["limit"] = max_limit
        return OffsetLimitQueryParams(
            offset=data.get("offset"),
            limit=data.get("limit"),
        )


class PlaylistSnapshotQuerySchema(OffsetLimitQuerySchema):
    include = fields.String(load_default=None, allow_none=True)
    detail = fields.String(load_default=None, allow_none=True)

    def __init__(self, *, max_limit: int | None = None, **kwargs: Any) -> None:
        super().__init__(max_limit=max_limit, **kwargs)

    @post_load
    def _build_params(
        self, data: dict[str, Any], **_: Any
    ) -> PlaylistSnapshotQueryParams:
        include_entries = False
        include_value = data.get("include")
        if isinstance(include_value, str):
            tokens = {
                token.strip().lower()
                for token in include_value.split(",")
                if token and token.strip()
            }
            if "entries" in tokens:
                include_entries = True
        detail_value = _normalize_bool_flag(data.get("detail"))
        if detail_value:
            include_entries = True
        base = self._build_offset_limit(data)
        return PlaylistSnapshotQueryParams(
            include_entries=include_entries,
            offset=base.offset,
            limit=base.limit,
        )


class PlaylistItemsQuerySchema(OffsetLimitQuerySchema):
    def __init__(self, *, max_limit: int | None = None, **kwargs: Any) -> None:
        super().__init__(max_limit=max_limit, **kwargs)

    @post_load
    def _build_params(self, data: dict[str, Any], **_: Any) -> OffsetLimitQueryParams:
        return self._build_offset_limit(data)


class PlaylistItemsDeltaQuerySchema(VidraSchema):
    since = fields.Integer(
        load_default=None,
        allow_none=True,
        error_messages={"invalid": "since_not_integer"},
    )

    @post_load
    def _build_params(
        self, data: dict[str, Any], **_: Any
    ) -> PlaylistItemsDeltaQueryParams:
        return PlaylistItemsDeltaQueryParams(since_version=data.get("since"))


class JobOptionsQuerySchema(VidraSchema):
    since = fields.Integer(
        load_default=None,
        allow_none=True,
        error_messages={"invalid": "since_not_integer"},
    )
    detail = fields.String(load_default=None, allow_none=True)

    @post_load
    def _build_params(self, data: dict[str, Any], **_: Any) -> JobOptionsQueryParams:
        include_flag = _normalize_bool_flag(data.get("detail"))
        return JobOptionsQueryParams(
            since_version=data.get("since"),
            include_options=bool(include_flag),
        )


class JobLogsQuerySchema(VidraSchema):
    def __init__(self, *, max_limit: int | None = None, **kwargs: Any) -> None:
        super().__init__(**kwargs)
        self._max_limit = max_limit

    since = fields.Integer(
        load_default=None,
        allow_none=True,
        error_messages={"invalid": "since_not_integer"},
    )
    limit = fields.Integer(
        load_default=None,
        allow_none=True,
        error_messages={"invalid": "limit_not_integer"},
    )
    detail = fields.String(load_default=None, allow_none=True)

    @validates("limit")
    def _validate_limit(self, value: int | None, **_: Any) -> None:
        if value is None:
            return
        if value <= 0:
            raise ValidationError("limit_greater_than_zero")

    @post_load
    def _build_params(self, data: dict[str, Any], **_: Any) -> JobLogsQueryParams:
        limit_value = data.get("limit")
        max_limit = self._max_limit
        if (
            limit_value is not None
            and max_limit is not None
            and limit_value > max_limit
        ):
            data["limit"] = max_limit
        include_flag = _normalize_bool_flag(data.get("detail"))
        return JobLogsQueryParams(
            since_version=data.get("since"),
            include_logs=bool(include_flag),
            limit=data.get("limit"),
        )


__all__ = [
    "OffsetLimitQueryParams",
    "PlaylistSnapshotQueryParams",
    "PlaylistItemsDeltaQueryParams",
    "JobOptionsQueryParams",
    "JobLogsQueryParams",
    "OffsetLimitQuerySchema",
    "PlaylistSnapshotQuerySchema",
    "PlaylistItemsQuerySchema",
    "PlaylistItemsDeltaQuerySchema",
    "JobOptionsQuerySchema",
    "JobLogsQuerySchema",
]
