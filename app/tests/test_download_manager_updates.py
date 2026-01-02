from __future__ import annotations

import threading
from typing import Any, Dict, List, Optional

from src.config import SocketEvent, SocketRoom
from src.download.manager import DownloadManager
from src.download.models import DownloadJob
from src.models.download.manager import JobLogEntry
from src.socket_manager import SocketManager


class _RecordingSocketManager(SocketManager):
    def __init__(self) -> None:
        super().__init__()
        self.events: List[Dict[str, Any]] = []

    def emit(
        self,
        event: str,
        payload: Dict[str, Any],
        *,
        room: Optional[str] = None,
    ) -> None:
        self.events.append({"event": event, "payload": payload, "room": room})

    def select(
        self,
        *,
        event: Optional[str] = None,
        room: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        matches: List[Dict[str, Any]] = []
        for record in self.events:
            if event and record["event"] != event:
                continue
            if room and record["room"] != room:
                continue
            matches.append(record)
        return matches

    def has_subscribers(self, room: Optional[str] = None) -> bool:
        return True

    def subscriber_count(self, room: Optional[str] = None) -> int:
        return 1


def _build_manager(socket_manager: SocketManager) -> DownloadManager:
    manager = DownloadManager.__new__(DownloadManager)
    manager.socket_manager = socket_manager
    manager.lock = threading.RLock()
    manager.jobs = {}
    return manager


def test_emit_job_update_keeps_overview_payload_lightweight() -> None:
    socket_manager = _RecordingSocketManager()
    manager = _build_manager(socket_manager)

    job = DownloadJob(
        job_id="job-test",
        urls=["https://example.com/watch?v=123"],
        options={"format": "mp4", "paths": {"output": "/tmp"}},
    )
    job.logs.append(
        JobLogEntry(
            timestamp="2024-01-01T00:00:00Z",
            level="info",
            message="Test log",
        )
    )
    manager.jobs[job.job_id] = job

    manager.emit_job_update(job.job_id, reason="unit_test")

    job_room = SocketRoom.for_job(job.job_id)
    overview_events = socket_manager.select(
        event=SocketEvent.UPDATE.value, room=SocketRoom.OVERVIEW.value
    )
    job_events = socket_manager.select(event=SocketEvent.UPDATE.value, room=job_room)

    assert overview_events, "expected overview update payload"
    assert job_events, "expected job room update payload"

    overview_payload = overview_events[-1]["payload"]
    job_payload = job_events[-1]["payload"]

    assert overview_payload.get("reason") == "unit_test"
    assert job_payload.get("reason") == "unit_test"

    assert "options" not in overview_payload
    assert "logs" not in overview_payload
    assert "options" not in job_payload
    assert "logs" not in job_payload

    for target in (overview_payload, job_payload):
        assert target.get("options_external") is True
        assert target.get("logs_external") is True
