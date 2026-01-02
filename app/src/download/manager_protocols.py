"""Protocols used to avoid circular dependencies."""

from __future__ import annotations

from typing import Protocol


class DownloadManagerProtocol(Protocol):
    def append_log(self, job_id: str, level: str, message: str) -> None:
        ...
