"""Compatibility shim exporting :func:`dataclasses.dataclass`."""

from __future__ import annotations

from dataclasses import dataclass as _stdlib_dataclass
from typing import Any


def dataclass(*args: Any, **kwargs: Any):
    """Thin wrapper over :func:`dataclasses.dataclass` for legacy imports."""

    return _stdlib_dataclass(*args, **kwargs)


__all__ = ["dataclass"]
