"""Helpers for validating the shared backend access token."""

from __future__ import annotations

import os
from typing import Mapping, Optional, TypeAlias

def _load_expected_token() -> str:
    raw = os.getenv("VIDRA_SERVER_TOKEN")
    if raw is None:
        raise RuntimeError(
            "Missing environment variable 'VIDRA_SERVER_TOKEN'. Provide a value to allow backend access."
        )
    token = raw.strip()
    if not token:
        raise RuntimeError("Environment variable 'VIDRA_SERVER_TOKEN' cannot be empty.")
    return token


EXPECTED_SERVER_TOKEN: str = _load_expected_token()


HeadersMapping: TypeAlias = Mapping[str, str]
QueryMapping: TypeAlias = Mapping[str, str]


def _normalize_token(token: Optional[str]) -> Optional[str]:
    if token is None:
        return None
    candidate = token.strip()
    return candidate or None


def parse_authorization_header(value: Optional[str]) -> Optional[str]:
    """Return the token encoded inside an Authorization header."""

    normalized = _normalize_token(value)
    if not normalized:
        return None
    if normalized.lower().startswith("bearer "):
        return _normalize_token(normalized[7:])
    return normalized


def token_from_headers(headers: HeadersMapping) -> Optional[str]:
    """Extract a token from Authorization or X-API-Token headers."""

    token = parse_authorization_header(headers.get("authorization"))
    if token:
        return token
    return _normalize_token(headers.get("x-api-token"))


def token_from_query(query: QueryMapping) -> Optional[str]:
    """Return the ?token= value if present."""

    return _normalize_token(query.get("token"))


def is_valid_token(candidate: Optional[str]) -> bool:
    """Check whether the provided token matches the configured secret."""

    return candidate == EXPECTED_SERVER_TOKEN


__all__ = [
    "EXPECTED_SERVER_TOKEN",
    "HeadersMapping",
    "QueryMapping",
    "is_valid_token",
    "parse_authorization_header",
    "token_from_headers",
    "token_from_query",
]
