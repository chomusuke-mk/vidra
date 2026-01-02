"""Compatibility shim for the relocated SocketManager implementation."""

from .sockets.manager import SocketManager

__all__ = ["SocketManager"]
