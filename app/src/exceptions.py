"""Custom exceptions used by the download manager."""


class DownloadCancelled(Exception):
    """Raised when a download is cancelled by the user."""


class DownloadPaused(Exception):
    """Raised when a download is paused by the user."""
