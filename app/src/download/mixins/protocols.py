from __future__ import annotations

import threading
from typing import Optional, Protocol

from ..models import DownloadJob, DownloadJobProgressPayload
from ...models.download.manager import SerializedJobPayload
from ...models.download.mixins.preview import PlaylistSnapshotPayload
from ...models.shared import JSONValue


class BaseManagerProtocol(Protocol):
    lock: threading.RLock
    jobs: dict[str, DownloadJob]

    def serialize_job(
        self, job: DownloadJob, *, detail: bool = False
    ) -> SerializedJobPayload: ...

    def _broadcast_update(self, payload: SerializedJobPayload) -> None: ...

    def broadcast_update(self, payload: SerializedJobPayload) -> None: ...

    def emit_overview(self) -> None: ...

    def emit_job_update(
        self,
        job_id: str,
        *,
        reason: str,
    ) -> None: ...

    def append_log(self, job_id: str, level: str, message: str) -> None: ...

    def _guard_job_signals(self, job_id: str) -> None: ...

    def guard_job_signals(self, job_id: str) -> None: ...

    def _emit_socket(
        self,
        event: str,
        payload: JSONValue,
        *,
        room: Optional[str] = None,
    ) -> None: ...

    def emit_socket(
        self,
        event: str,
        payload: JSONValue,
        *,
        room: Optional[str] = None,
    ) -> None: ...

    def job_room(self, job_id: str) -> str: ...

    def _resolve_playlist_entry_id(
        self,
        job: DownloadJob,
        index: Optional[int],
    ) -> Optional[str]: ...

    def _resolve_playlist_index_from_entry_id(
        self,
        job: DownloadJob,
        entry_id: Optional[str],
    ) -> Optional[int]: ...

    def resolve_playlist_entry_id(
        self,
        job: DownloadJob,
        index: Optional[int],
    ) -> Optional[str]: ...

    def resolve_playlist_index_from_entry_id(
        self,
        job: DownloadJob,
        entry_id: Optional[str],
    ) -> Optional[int]: ...

    def build_playlist_snapshot(
        self,
        job_id: str,
        *,
        include_entries: bool = False,
        include_entry_progress: bool = False,
    ) -> Optional[PlaylistSnapshotPayload]: ...


class PlaylistManagerProtocol(BaseManagerProtocol, Protocol):
    pass


class PreviewManagerProtocol(BaseManagerProtocol, Protocol):
    pass


class ProgressManagerProtocol(BaseManagerProtocol, Protocol):
    def _store_progress(
        self, job_id: str, payload: DownloadJobProgressPayload
    ) -> None: ...

    def store_progress(
        self, job_id: str, payload: DownloadJobProgressPayload
    ) -> None: ...
