"""REST and websocket route registration helpers."""

from .http import register_http_routes
from .websockets import register_websocket_routes

__all__ = ["register_http_routes", "register_websocket_routes"]
