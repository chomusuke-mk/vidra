"""Logging helpers for the Vidra backend."""

from __future__ import annotations

import os
import sys
from typing import Any
from .utils import now_iso
from .config import CACHE_FOLDER


def _read_flag(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    normalized = raw.strip().lower()
    return normalized in {"1", "true", "yes", "on"}


DEBUG = _read_flag("VIDRA_SERVER_DEBUG", False)
VERBOSE = _read_flag("VIDRA_SERVER_VERBOSE", True)


LOG_FILE = os.path.join(CACHE_FOLDER, "logs.txt")


def _emit(prefix: str, label: str, payload: Any) -> None:
    timestamp = now_iso()
    message = f"[{prefix}][{timestamp}] {label}: {payload}"
    _append_log(message)


def _append_log(message: str) -> None:
    os.makedirs(CACHE_FOLDER, exist_ok=True)
    encoding = getattr(sys.stdout, "encoding", None) or "utf-8"
    safe_message = message.encode(encoding, errors="replace").decode(encoding)
    with open(LOG_FILE, "a", encoding=encoding) as log_file:
        log_file.write(f"{safe_message}\n")


def verbose_log(label: str, payload: Any) -> None:
    """Emit structured logs when verbose mode is enabled."""
    if not VERBOSE:
        return
    _emit("VERBOSE", label, payload)


def debug_verbose(label: str, payload: Any) -> None:
    """Emit debug logs when debug mode is active, or always in verbose mode."""
    if not (DEBUG or VERBOSE):
        return
    _emit("DEBUG", label, payload)


__all__ = ["DEBUG", "VERBOSE", "verbose_log", "debug_verbose"]
