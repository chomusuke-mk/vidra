from __future__ import annotations

import asyncio
import os
from contextlib import asynccontextmanager
from typing import AsyncIterator, Tuple

import certifi
from starlette.applications import Starlette

from ..config import DATA_FOLDER, CACHE_FOLDER

from ..download import DownloadManager
from ..socket_manager import SocketManager
from ..api.http import register_http_routes
from ..api.websockets import register_websocket_routes


def _configure_certificates() -> None:
    cert_path = certifi.where()
    os.environ.setdefault("SSL_CERT_FILE", cert_path)
    os.environ.setdefault("REQUESTS_CA_BUNDLE", cert_path)

def _configure_xdg_dirs() -> None:
    os.environ["XDG_CONFIG_HOME"] = DATA_FOLDER
    os.environ["XDG_CACHE_HOME"] = CACHE_FOLDER


def create_app() -> Tuple[Starlette, DownloadManager, SocketManager]:
    """Instantiate the Starlette app along with its supporting managers."""

    _configure_certificates()
    _configure_xdg_dirs()
    socket_manager = SocketManager()
    manager = DownloadManager(socket_manager)

    @asynccontextmanager
    async def lifespan(_: Starlette) -> AsyncIterator[None]:
        loop = asyncio.get_running_loop()
        socket_manager.bind_loop(loop)
        try:
            yield
        finally:
            await socket_manager.aclose()

    app = Starlette(lifespan=lifespan)
    register_http_routes(app, manager)
    register_websocket_routes(app, manager, socket_manager)
    app.state.download_manager = manager
    app.state.socket_manager = socket_manager
    return app, manager, socket_manager


__all__ = ["create_app"]
