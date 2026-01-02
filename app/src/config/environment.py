from __future__ import annotations

import json
import os
from dataclasses import dataclass
from functools import lru_cache
from typing import Any, Dict, Tuple, cast
from urllib.parse import urlunsplit

_DEFAULTS: Dict[str, str] = {
    "VIDRA_SERVER_NAME": "Vidra Download Service",
    "VIDRA_SERVER_DESCRIPTION": "Local server backend for Vidra",
    "VIDRA_SERVER_SCHEME": "http",
    "VIDRA_SERVER_HOST": "0.0.0.0",
    "VIDRA_SERVER_PORT": "5000",
    "VIDRA_SERVER_BASE_PATH": "/",
    "VIDRA_SERVER_API_ROOT": "/api",
    "VIDRA_SERVER_WS_OVERVIEW_PATH": "/ws/overview",
    "VIDRA_SERVER_WS_JOB_PATH": "/ws/jobs",
    "VIDRA_SERVER_METADATA": "{}",
    "VIDRA_SERVER_TIMEOUT_SECONDS": "30",
    "VIDRA_SERVER_LOG_LEVEL": "info",
}


@dataclass(frozen=True)
class ServerEnvironmentConfig:
    name: str
    description: str
    scheme: str
    host: str
    port: int
    base_path: str
    api_root: str
    ws_overview_path: str
    ws_job_path: str
    metadata: Dict[str, Any]
    timeout_seconds: int
    log_level: str
    base_url: str
    api_url: str
    overview_socket_url: str
    job_socket_base_url: str
    data_folder: str
    cache_folder: str


def _coalesce_env(key: str) -> str:
    default = _DEFAULTS.get(key)
    value = os.getenv(key)
    if value is None:
        if default is None:
            raise RuntimeError(f"Missing environment variable '{key}'")
        return default
    trimmed = value.strip()
    if not trimmed:
        if default is not None:
            return default
        raise RuntimeError(f"Environment variable '{key}' cannot be empty")
    return trimmed


def _parse_int(key: str) -> int:
    raw = _coalesce_env(key)
    try:
        return int(raw)
    except ValueError as exc:  # pragma: no cover - defensive parsing
        raise RuntimeError(f"Environment variable '{key}' must be an integer") from exc


def _parse_metadata(raw: str) -> Dict[str, Any]:
    try:
        parsed = json.loads(raw)
    except json.JSONDecodeError as exc:  # pragma: no cover - defensive parsing
        raise RuntimeError("VIDRA_SERVER_METADATA must be valid JSON") from exc
    if not isinstance(parsed, dict):
        raise RuntimeError("VIDRA_SERVER_METADATA must be a JSON object")
    parsed_dict = cast(Dict[str, Any], parsed)
    return dict(parsed_dict)


def _normalize_segments(raw: str) -> Tuple[str, ...]:
    trimmed = raw.strip()
    if not trimmed or trimmed == "/":
        return tuple()
    segments = [segment.strip() for segment in trimmed.split("/") if segment.strip()]
    return tuple(segments)


def _sanitize_path(raw: str) -> str:
    trimmed = raw.strip() or "/"
    return trimmed if trimmed.startswith("/") else f"/{trimmed}"


def _is_default_port(scheme: str, port: int) -> bool:
    return (scheme == "http" and port == 80) or (scheme == "https" and port == 443)


def _build_url(scheme: str, host: str, port: int, segments: Tuple[str, ...]) -> str:
    path = "/".join(segments)
    normalized_path = f"/{path}" if path else "/"
    netloc = host if _is_default_port(scheme, port) else f"{host}:{port}"
    return urlunsplit((scheme, netloc, normalized_path, "", ""))


def _ensure_trailing_slash(url: str) -> str:
    return url if url.endswith("/") else f"{url}/"

def _parse_string(raw: Any) -> str:
    if not raw:
        raise RuntimeError("Environment variable cannot be empty.")
    return raw.strip()

@lru_cache(maxsize=1)
def get_server_environment() -> ServerEnvironmentConfig:
    name = _coalesce_env("VIDRA_SERVER_NAME")
    description = _coalesce_env("VIDRA_SERVER_DESCRIPTION")
    scheme = _coalesce_env("VIDRA_SERVER_SCHEME").lower()
    host = _coalesce_env("VIDRA_SERVER_HOST")
    port = _parse_int("VIDRA_SERVER_PORT")
    base_path = _sanitize_path(_coalesce_env("VIDRA_SERVER_BASE_PATH"))
    api_root = _sanitize_path(_coalesce_env("VIDRA_SERVER_API_ROOT"))
    ws_overview_path = _sanitize_path(_coalesce_env("VIDRA_SERVER_WS_OVERVIEW_PATH"))
    ws_job_path = _sanitize_path(_coalesce_env("VIDRA_SERVER_WS_JOB_PATH"))
    metadata: Dict[str, Any] = _parse_metadata(_coalesce_env("VIDRA_SERVER_METADATA"))
    timeout_seconds = _parse_int("VIDRA_SERVER_TIMEOUT_SECONDS")
    log_level = _coalesce_env("VIDRA_SERVER_LOG_LEVEL").lower()

    base_segments = _normalize_segments(base_path)
    api_segments = base_segments + _normalize_segments(api_root)
    overview_segments = base_segments + _normalize_segments(ws_overview_path)
    job_segments = base_segments + _normalize_segments(ws_job_path)

    base_url = _build_url(scheme, host, port, base_segments)
    api_url = _ensure_trailing_slash(_build_url(scheme, host, port, api_segments))
    ws_scheme = "wss" if scheme == "https" else "ws"
    overview_socket_url = _build_url(ws_scheme, host, port, overview_segments)
    job_socket_base_url = _ensure_trailing_slash(
        _build_url(ws_scheme, host, port, job_segments)
    )
    data_folder = _parse_string(os.getenv("VIDRA_SERVER_DATA"))
    cache_folder = _parse_string(os.getenv("VIDRA_SERVER_CACHE"))
    os.makedirs(data_folder, exist_ok=True)
    os.makedirs(cache_folder, exist_ok=True)

    return ServerEnvironmentConfig(
        name=name,
        description=description,
        scheme=scheme,
        host=host,
        port=port,
        base_path=base_path,
        api_root=api_root,
        ws_overview_path=ws_overview_path,
        ws_job_path=ws_job_path,
        metadata=metadata,
        timeout_seconds=timeout_seconds,
        log_level=log_level,
        base_url=base_url,
        api_url=api_url,
        overview_socket_url=overview_socket_url,
        job_socket_base_url=job_socket_base_url,
        data_folder=data_folder,
        cache_folder=cache_folder,
    )


__all__ = ["ServerEnvironmentConfig", "get_server_environment"]
