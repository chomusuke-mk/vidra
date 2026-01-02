"""Shared Starlette helper utilities used across the Vidra backend."""

from __future__ import annotations

import json
from typing import Any, Mapping, MutableMapping, TypeAlias

from marshmallow import Schema, ValidationError  # type: ignore[import-not-found]
from starlette.requests import Request
from starlette.responses import JSONResponse

JSONPrimitive = str | int | float | bool | None
JSONValue: TypeAlias = JSONPrimitive | list["JSONValue"] | dict[str, "JSONValue"]


class RequestValidationError(RuntimeError):
    """Raised when an incoming request payload fails validation."""

    def __init__(
        self,
        errors: Mapping[str, Any] | None = None,
        *,
        message: str = "Invalid request payload",
    ) -> None:
        super().__init__(message)
        self.errors: dict[str, Any] = dict(errors or {})


async def read_json_body(request: Request) -> Any:
    """Read and return the request JSON payload, raising a friendly error on failure."""

    try:
        return await request.json()
    except (
        json.JSONDecodeError
    ) as exc:  # pragma: no cover - Starlette already tested heavily
        raise RequestValidationError({"json": "Invalid JSON payload"}) from exc


def json_response(
    payload: JSONValue | Mapping[str, Any],
    *,
    status_code: int = 200,
    headers: Mapping[str, str] | None = None,
) -> JSONResponse:
    """Wrap Starlette's JSONResponse to ensure consistent logging and typing."""

    content: MutableMapping[str, Any]
    if isinstance(payload, Mapping):
        content = dict(payload)
    else:
        content = {"data": payload}
    return JSONResponse(
        content=content, status_code=status_code, headers=dict(headers or {})
    )


def load_with_schema(
    schema: Schema, payload: Any, *, partial: bool | None = None
) -> Any:
    """Validate and deserialize input data with the provided Marshmallow schema."""

    try:
        return schema.load(payload, partial=partial)
    except ValidationError as exc:
        raise RequestValidationError(exc.normalized_messages()) from exc


def dump_with_schema(schema: Schema, payload: Any) -> Any:
    """Serialize data using the provided Marshmallow schema."""

    return schema.dump(payload)


__all__ = [
    "RequestValidationError",
    "read_json_body",
    "json_response",
    "load_with_schema",
    "dump_with_schema",
]
