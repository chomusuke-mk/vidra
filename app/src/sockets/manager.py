from __future__ import annotations

import asyncio
import threading
from typing import Any, Dict, List, Optional, Set

from starlette.websockets import WebSocket, WebSocketState

from ..log_config import verbose_log
from ..config import SocketRoom


class SocketManager:
    """Manages websocket rooms and dispatches events from worker threads."""

    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._overview_clients: Set[WebSocket] = set()
        self._room_clients: Dict[str, Set[WebSocket]] = {}
        self._shutting_down = False

    def bind_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        """Bind the running asyncio loop so background threads can schedule work."""
        with self._lock:
            self._loop = loop

    def register_overview(self, websocket: WebSocket) -> None:
        """Track a websocket subscribed to the overview broadcast channel."""
        with self._lock:
            if self._shutting_down:
                return
            self._overview_clients.add(websocket)

    def unregister_overview(self, websocket: WebSocket) -> None:
        """Remove a websocket from the overview channel if present."""
        self._remove(websocket)

    def register_job(self, job_id: str, websocket: WebSocket) -> None:
        """Attach a websocket to a specific job room."""
        self._register_room(SocketRoom.for_job(job_id), websocket)

    def unregister_job(self, job_id: str, websocket: WebSocket) -> None:
        """Detach a websocket from a specific job room."""
        self._unregister_room(SocketRoom.for_job(job_id), websocket)

    def subscriber_count(self, room: Optional[str] = None) -> int:
        """Return the number of active subscribers for the given room."""
        with self._lock:
            return self._subscriber_count_locked(room)

    def has_subscribers(self, room: Optional[str] = None) -> bool:
        """Indicate whether a room currently has at least one subscriber."""
        return self.subscriber_count(room) > 0

    def emit(self, event: str, payload: Any, *, room: Optional[str] = None) -> None:
        """Broadcast an event payload to the requested room (or all overview clients)."""
        message = {"event": event, "payload": payload}
        with self._lock:
            if self._shutting_down:
                return
            loop = self._loop
            if loop is None or loop.is_closed():
                return
            targets = self._resolve_targets(room)
        if not targets:
            return
        for websocket in targets:
            per_message = dict(message)
            try:
                loop.call_soon_threadsafe(self._schedule_send, websocket, per_message)
            except RuntimeError:
                self._remove(websocket)

    async def aclose(self) -> None:
        """Close all tracked websockets and prevent further emissions."""
        with self._lock:
            if self._shutting_down:
                return
            self._shutting_down = True
            clients: Set[WebSocket] = set(self._overview_clients)
            for sockets in self._room_clients.values():
                clients.update(sockets)
            self._overview_clients.clear()
            self._room_clients.clear()
        for websocket in clients:
            try:
                await websocket.close()
            except RuntimeError:
                continue
            except Exception as exc:  # noqa: BLE001 - best effort shutdown
                verbose_log("socket_close_failed", {"error": repr(exc)})
        with self._lock:
            self._loop = None

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------
    def _subscriber_count_locked(self, room: Optional[str]) -> int:
        if room is None or room == SocketRoom.OVERVIEW.value:
            return len(self._overview_clients)
        clients = self._room_clients.get(room)
        return len(clients) if clients else 0

    def _resolve_targets(self, room: Optional[str]) -> List[WebSocket]:
        """Return a list of active websockets that should receive an event."""
        if room is None or room == SocketRoom.OVERVIEW.value:
            candidates = list(self._overview_clients)
        else:
            candidates = list(self._room_clients.get(room, set()))
        alive: List[WebSocket] = []
        for websocket in candidates:
            if self._is_open(websocket):
                alive.append(websocket)
            else:
                self._remove(websocket)
        return alive

    def _schedule_send(self, websocket: WebSocket, message: Dict[str, Any]) -> None:
        """Schedule an asynchronous JSON send if the websocket is still open."""
        if not self._is_open(websocket):
            self._remove(websocket)
            return
        asyncio.create_task(self._send(websocket, message))

    async def _send(self, websocket: WebSocket, message: Dict[str, Any]) -> None:
        try:
            await websocket.send_json(message)
        except Exception:  # noqa: BLE001 - log and drop the socket
            verbose_log("socket_send_failed", {"message": message})
            self._remove(websocket)

    def _remove(self, websocket: WebSocket) -> None:
        with self._lock:
            self._overview_clients.discard(websocket)
            to_prune: List[str] = []
            for room, clients in self._room_clients.items():
                clients.discard(websocket)
                if not clients:
                    to_prune.append(room)
            for room in to_prune:
                self._room_clients.pop(room, None)

    def _register_room(self, room: str, websocket: WebSocket) -> None:
        with self._lock:
            if self._shutting_down:
                return
            self._room_clients.setdefault(room, set()).add(websocket)

    def _unregister_room(self, room: str, websocket: WebSocket) -> None:
        with self._lock:
            clients = self._room_clients.get(room)
            if not clients:
                return
            clients.discard(websocket)
            if not clients:
                self._room_clients.pop(room, None)

    @staticmethod
    def _is_open(websocket: WebSocket) -> bool:
        client_state = getattr(websocket, "client_state", None)
        if client_state is not None and client_state != WebSocketState.CONNECTED:
            return False
        application_state = getattr(websocket, "application_state", None)
        if (
            application_state is not None
            and application_state != WebSocketState.CONNECTED
        ):
            return False
        return True


__all__ = ["SocketManager"]
