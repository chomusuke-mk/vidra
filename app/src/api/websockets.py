from __future__ import annotations

import asyncio
import typing as t
from typing import Awaitable, Callable, cast

from marshmallow import ValidationError
from starlette.applications import Starlette
from starlette.websockets import WebSocket, WebSocketDisconnect

from ..models.api.websockets import (
    DownloadSocketAction,
    DownloadsSocketMessage,
    DownloadsSocketMessageSchema,
    HandleExtractResult,
)

from ..config import (
    INITIAL_SYNC_REASON,
    JobStatus,
    JobUpdateReason,
    SocketEvent,
    SocketRoom,
    TERMINAL_STATUSES,
)
from ..core import DownloadError, Manager
from ..download import DownloadManager
from ..socket_manager import SocketManager
from ..utils import now_iso
from ..security import is_valid_token, token_from_headers, token_from_query

if t.TYPE_CHECKING:
    from ..download.mixins.progress import ProgressDataView


PayloadMapping = t.Mapping[str, object]
PayloadDict = dict[str, object]


class SupportsToDict(t.Protocol):
    def to_dict(self) -> PayloadMapping: ...


def register_websocket_routes(
    app: Starlette,
    manager: DownloadManager,
    socket_manager: SocketManager,
) -> None:
    """Attach websocket endpoints used by the frontend dashboards."""

    downloads_schema = DownloadsSocketMessageSchema()

    async def _authorize_websocket(websocket: WebSocket) -> bool:
        token = token_from_query(websocket.query_params) or token_from_headers(
            websocket.headers
        )
        if not is_valid_token(token):
            await websocket.close(code=1008, reason="Missing or invalid token")
            return False
        return True

    def websocket_route(
        path: str,
    ) -> Callable[
        [Callable[[WebSocket], Awaitable[None]]], Callable[[WebSocket], Awaitable[None]]
    ]:
        def decorator(
            func: Callable[[WebSocket], Awaitable[None]],
        ) -> Callable[[WebSocket], Awaitable[None]]:
            app.add_websocket_route(path, func)
            return func

        return decorator

    @websocket_route("/ws/downloads")
    async def downloads_socket(websocket: WebSocket) -> None:
        if not await _authorize_websocket(websocket):
            return
        await websocket.accept()
        core_manager = Manager()
        loop = asyncio.get_running_loop()
        queue: asyncio.Queue[tuple[str, PayloadDict]] = asyncio.Queue()

        async def _sender() -> None:
            try:
                while True:
                    event, payload = await queue.get()
                    try:
                        await websocket.send_json({"event": event, "payload": payload})
                    except WebSocketDisconnect:
                        break
                    except Exception:
                        break
            except asyncio.CancelledError:
                pass

        sender_task = asyncio.create_task(_sender())

        def emit(
            event: str,
            payload: PayloadMapping | SupportsToDict,
            *,
            action: str | None = None,
        ) -> None:
            if loop.is_closed():
                return
            message: PayloadDict
            if isinstance(payload, dict):
                message = dict(payload)
            elif isinstance(payload, t.Mapping):
                message = dict(payload)
            else:
                raw_payload = payload.to_dict()
                message = dict(raw_payload)
            if action:
                message.setdefault("action", action)
            loop.call_soon_threadsafe(queue.put_nowait, (event, message))

        async def handle_extract(message: DownloadsSocketMessage) -> None:
            action = message.action_label
            emit(
                SocketEvent.UPDATE.value,
                {"status": JobUpdateReason.STARTED.value},
                action=action,
            )
            try:
                result = await asyncio.to_thread(
                    core_manager.extract_info,
                    message.urls,
                    options=message.options,
                    download=message.download,
                )
            except DownloadError as exc:
                emit(SocketEvent.ERROR.value, {"message": str(exc)}, action=action)
            except Exception as exc:  # noqa: BLE001 - surface unexpected errors to the client
                emit(SocketEvent.ERROR.value, {"message": repr(exc)}, action=action)
            else:
                info_payload = result.model
                payload: HandleExtractResult = {
                    "event": "end",
                    "stage": "info",
                    "status": JobStatus.COMPLETED.value,
                    "normalized_info": info_payload,
                    "extractor": result.extractor,
                    "extractor_key": result.extractor_key,
                    "is_playlist": result.is_playlist,
                    "entry_count": result.entry_count,
                }
                emit(SocketEvent.UPDATE.value, payload, action=action)

        async def handle_download(message: DownloadsSocketMessage) -> None:
            action = message.action_label
            emit(
                SocketEvent.UPDATE.value,
                {"status": JobUpdateReason.STARTED.value},
                action=action,
            )
            try:
                await asyncio.to_thread(
                    core_manager.download,
                    message.urls,
                    options=message.options,
                    progress_handler=lambda payload: emit(
                        SocketEvent.PROGRESS.value,
                        payload,
                        action=action,
                    ),
                    info_handler=lambda payload: emit(
                        SocketEvent.LOG.value,
                        payload,
                        action=action,
                    ),
                    end_handler=lambda payload: emit(
                        SocketEvent.UPDATE.value,
                        payload,
                        action=action,
                    ),
                )
            except DownloadError as exc:
                emit(SocketEvent.ERROR.value, {"message": str(exc)}, action=action)
            except Exception as exc:  # noqa: BLE001
                emit(SocketEvent.ERROR.value, {"message": repr(exc)}, action=action)

        async def handle_playlist(message: DownloadsSocketMessage) -> None:
            action = message.action_label
            emit(
                SocketEvent.UPDATE.value,
                {"status": JobUpdateReason.STARTED.value},
                action=action,
            )
            try:
                await asyncio.to_thread(
                    core_manager.download_playlist,
                    message.urls,
                    options=message.options,
                    playlist_progress_handler=lambda payload: emit(
                        SocketEvent.PLAYLIST_PROGRESS.value,
                        payload,
                        action=action,
                    ),
                    playlist_info_handler=lambda payload: emit(
                        SocketEvent.LOG.value,
                        payload,
                        action=action,
                    ),
                    playlist_end_handler=lambda payload: emit(
                        SocketEvent.UPDATE.value,
                        payload,
                        action=action,
                    ),
                    entry_progress_handler=lambda payload: emit(
                        SocketEvent.PLAYLIST_ENTRY_PROGRESS.value,
                        payload,
                        action=action,
                    ),
                    entry_info_handler=lambda payload: emit(
                        SocketEvent.LOG.value,
                        payload,
                        action=action,
                    ),
                    entry_end_handler=lambda payload: emit(
                        SocketEvent.PLAYLIST_ENTRY_PROGRESS.value,
                        payload,
                        action=action,
                    ),
                )
            except DownloadError as exc:
                emit(SocketEvent.ERROR.value, {"message": str(exc)}, action=action)
            except Exception as exc:  # noqa: BLE001
                emit(SocketEvent.ERROR.value, {"message": repr(exc)}, action=action)

        async def process_message(message: object) -> None:
            if not isinstance(message, t.Mapping):
                emit(SocketEvent.ERROR.value, {"message": "payload must be an object"})
                return
            try:
                parsed = cast(DownloadsSocketMessage, downloads_schema.load(message))
            except ValidationError as exc:
                emit(
                    SocketEvent.ERROR.value,
                    {
                        "message": "invalid payload",
                        "errors": exc.normalized_messages(),
                    },
                )
                return

            if parsed.action is DownloadSocketAction.EXTRACT_INFO:
                await handle_extract(parsed)
            elif parsed.action is DownloadSocketAction.DOWNLOAD:
                await handle_download(parsed)
            elif parsed.action is DownloadSocketAction.DOWNLOAD_PLAYLIST:
                await handle_playlist(parsed)
            else:  # pragma: no cover - all actions handled above
                emit(
                    SocketEvent.ERROR.value,
                    {"message": f"unknown action '{parsed.action.value}'"},
                )

        try:
            while True:
                try:
                    message = await websocket.receive_json()
                except ValueError:
                    emit(SocketEvent.ERROR.value, {"message": "invalid JSON payload"})
                    continue
                await process_message(message)
        except WebSocketDisconnect:
            pass
        finally:
            sender_task.cancel()
            await asyncio.gather(sender_task, return_exceptions=True)

    @websocket_route(f"/ws/{SocketRoom.OVERVIEW.value}")
    async def overview_socket(websocket: WebSocket) -> None:
        if not await _authorize_websocket(websocket):
            return
        await websocket.accept()
        socket_manager.register_overview(websocket)
        await websocket.send_json(
            {
                "event": SocketEvent.UPDATE.value,
                "payload": {
                    "job_id": None,
                    "reason": INITIAL_SYNC_REASON,
                    "timestamp": now_iso(),
                },
            }
        )
        try:
            while True:
                await websocket.receive_text()
        except WebSocketDisconnect:
            pass
        finally:
            socket_manager.unregister_overview(websocket)

    @websocket_route("/ws/jobs/{job_id}")
    async def job_socket(websocket: WebSocket) -> None:
        job_id = websocket.path_params.get("job_id", "")
        if not await _authorize_websocket(websocket):
            return
        await websocket.accept()
        job = manager.get_job(job_id)
        if not job:
            await websocket.send_json(
                {
                    "event": SocketEvent.ERROR.value,
                    "payload": {"message": "job not found", "job_id": job_id},
                }
            )
            await websocket.close()
            return

        socket_manager.register_job(job_id, websocket)
        await websocket.send_json(
            {
                "event": SocketEvent.UPDATE.value,
                "payload": {
                    "job_id": job_id,
                    "status": job.status,
                    "is_terminal": job.status in TERMINAL_STATUSES,
                    "reason": INITIAL_SYNC_REASON,
                    "timestamp": now_iso(),
                    **({"error": job.error} if job.error else {}),
                },
            }
        )
        playlist_snapshot = manager.build_playlist_snapshot(job_id)
        if playlist_snapshot:
            snapshot_payload = dict(playlist_snapshot)
            snapshot_payload.setdefault("reason", INITIAL_SYNC_REASON)
            snapshot_payload.setdefault("timestamp", now_iso())
            await websocket.send_json(
                {
                    "event": SocketEvent.PLAYLIST_SNAPSHOT.value,
                    "payload": snapshot_payload,
                }
            )
        if job.progress:
            progress_view = t.cast("ProgressDataView", job.progress)
            progress_payload = manager.build_progress_summary(
                job_id, progress_view
            ).to_dict()
            progress_payload["reason"] = INITIAL_SYNC_REASON
            progress_payload["timestamp"] = now_iso()
            await websocket.send_json(
                {
                    "event": SocketEvent.PROGRESS.value,
                    "payload": progress_payload,
                }
            )
        try:
            while True:
                await websocket.receive_text()
        except WebSocketDisconnect:
            pass
        finally:
            socket_manager.unregister_job(job_id, websocket)

    _ = downloads_socket
    _ = overview_socket
    _ = job_socket
__all__ = ["register_websocket_routes"]
