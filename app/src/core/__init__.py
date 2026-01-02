"""Core service layer for media extraction and download."""

from .utils import OptionsConfig, build_options_config, parse_options
from .downloader import (
    DownloadError,
    DownloadResult,
    DownloadPlaylistResult,
    ExtractInformationResult,
    download,
    download_playlist,
    extract_information,
    resolve_options,
)
from .manager import ExtractInfoResult, Manager
from .contract import Info

__all__ = [
    "DownloadError",
    "DownloadResult",
    "DownloadPlaylistResult",
    "ExtractInformationResult",
    "download",
    "download_playlist",
    "extract_information",
    "Manager",
    "ExtractInfoResult",
    "parse_options",
    "Info",
    "OptionsConfig",
    "resolve_options",
    "build_options_config",
]
