"""Application bootstrap for the Vidra backend."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, Dict, List, Optional, Union, cast

from starlette.applications import Starlette

from .server import create_app
from .models.download.manager import CreateJobRequest
from .download.models import DownloadJobOptionsPayload

if TYPE_CHECKING:
    from .download import DownloadManager
    from .socket_manager import SocketManager


_app: Starlette
_manager: DownloadManager | None
_socket_manager: SocketManager | None
_app, _manager_instance, _socket_manager_instance = create_app()
_manager = _manager_instance
_socket_manager = _socket_manager_instance
app = _app


def download(
    urls: Union[str, List[str]], options: Optional[Dict[str, Any]] = None
) -> str:
    """Convenience wrapper for triggering a download job."""
    if _manager is None:
        raise RuntimeError("Application is not initialized")
    url_list = [urls] if isinstance(urls, str) else list(urls)
    sanitized = [url.strip() for url in url_list if url.strip()]
    if not sanitized:
        raise ValueError("At least one URL is required")
    options_payload = cast(
        DownloadJobOptionsPayload,
        dict(options or {}),
    )
    job_request = CreateJobRequest(urls=sanitized, options=options_payload)
    job = _manager.create_job(job_request)
    return job.job_id


__all__ = ["app", "create_app", "download", "_manager", "_socket_manager"]
