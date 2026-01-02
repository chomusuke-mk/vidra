"""High-level integration layer around yt_dlp consumption.

This module centralices every direct call to :mod:`yt_dlp` so the rest of the
codebase can rely on a stable, application-tailored contract.  All functions in
this module accept plain dictionaries/lists and optional hooks so callers can
re-use their existing handlers without dealing with yt-dlp specific details.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import (
    Any,
    Callable,
    Generator,
    Iterable,
    Literal,
    Mapping,
    Optional,
    Sequence,
    TypedDict,
    TypeVar,
    cast,
    NotRequired,
    Protocol,
)

from yt_dlp import YoutubeDL, parse_options as _parse_options

from ..core.utils import OptionsConfig
from .utils import parse_options
from .contract import Info
from ..download.hook_payloads import (
    PostHookPayload,
    PostProcessorHookPayload,
    ProgressHookPayload,
)
from ..utils import (
    clean_string,
    normalize_float,
    normalize_int,
    normalize_percent,
    normalize_upload_date,
    strip_ansi,
    to_bool,
    truncate_string,
)


TReturn = TypeVar("TReturn")


class YtDlpInfoResultThumbnail(TypedDict, total=False):
    url: str
    height: int
    width: int
    preference: int | float | str


class YtDlpInfoResult(TypedDict, total=False):
    """Type alias for yt-dlp info dicts."""

    id: Optional[str]
    title: Optional[str]
    description: Optional[str]
    thumbnail: Optional[str]
    _type: Optional[str]
    ie_key: Optional[str]
    url: Optional[str]
    duration: Optional[int]
    duration_string: Optional[str]
    channel_id: Optional[str]
    channel: Optional[str]
    channel_url: Optional[str]
    uploader: Optional[str]
    uploader_id: Optional[str]
    uploader_url: Optional[str]
    thumbnails: list[YtDlpInfoResultThumbnail]
    timestamp: Optional[int]
    release_timestamp: Optional[int]
    release_date: Optional[str]
    upload_date: Optional[str]
    availability: Optional[str]
    view_count: Optional[int]
    live_status: Optional[str]
    channel_is_verified: Optional[bool]
    webpage_url: Optional[str]
    comment_count: Optional[int]
    original_url: Optional[str]
    extractor: Optional[str]
    extractor_key: Optional[str]
    entries: Optional[list[YtDlpInfoResult]]
    like_count: Optional[int]
    age_limit: Optional[int]
    tags: Optional[list[str]]
    channel_follower_count: Optional[int]
    media_type: Optional[str]
    preview_thumbnail: Optional[str]
    thumbnail_url: Optional[str]
    playlist_webpage_url: Optional[str]
    # playlist
    playlist_count: Optional[int]
    playlist_id: Optional[str]
    playlist_title: Optional[str]
    playlist_uploader: Optional[str]
    playlist_uploader_id: Optional[str]
    playlist_uploader_url: Optional[str]
    playlist_channel: Optional[str]
    playlist_channel_id: Optional[str]
    playlist_channel_url: Optional[str]
    playlist_length: Optional[int]
    n_entries: Optional[int]
    playlist_index: Optional[int]
    playlist_autonumber: Optional[int]
    __last_playlist_index: Optional[int]
    display_id: Optional[str]
    modified_date: Optional[str]
    webpage_url_basename: Optional[str]
    webpage_url_domain: Optional[str]


class ProgressHookArgs(TypedDict):
    status: Literal["downloading", "finished", "error"]
    info_dict: YtDlpInfoResult
    message: NotRequired[Optional[str]]
    filename: NotRequired[Optional[str]]
    tmpfilename: NotRequired[Optional[str]]
    downloaded_bytes: NotRequired[Optional[int]]
    total_bytes: NotRequired[Optional[int]]
    total_bytes_estimate: NotRequired[Optional[int]]
    percent: NotRequired[Optional[float]]
    elapsed: NotRequired[Optional[float]]
    eta: NotRequired[Optional[float]]
    speed: NotRequired[Optional[float]]
    fragment_index: NotRequired[Optional[int]]
    fragment_count: NotRequired[Optional[int]]
    playlist_index: NotRequired[Optional[int]]
    playlist_count: NotRequired[Optional[int]]
    playlist_id: NotRequired[Optional[str]]
    entry_id: NotRequired[Optional[str]]
    current_item: NotRequired[Optional[int]]
    total_items: NotRequired[Optional[int]]
    ctx_id: NotRequired[Optional[str]]


class PostProcessorHookArgs(TypedDict):
    status: Literal["started", "processing", "finished", "error"]
    postprocessor: str
    info_dict: YtDlpInfoResult
    percent: Optional[float]
    message: Optional[str]
    playlist_index: Optional[int]
    playlist_id: Optional[str]
    entry_id: Optional[str]


class MatchFilterArgs(TypedDict):
    incomplete: bool


ProgressHook = Callable[[ProgressHookArgs], None]
PostProcessorHook = Callable[[PostProcessorHookArgs], None]
PostHook = Callable[[str], None]
MatchFilter = Callable[[YtDlpInfoResult, MatchFilterArgs], Optional[str]]

InfoHandler = Callable[[YtDlpInfoResult], None]
PlaylistHandler = Callable[[YtDlpInfoResult], None]
EntryHandler = Callable[[int, YtDlpInfoResult], None]


class LoggerLike(Protocol):
    def debug(self, msg: str) -> None: ...

    def warning(self, msg: str) -> None: ...

    def error(self, msg: str) -> None: ...


class _BufferedLogger(LoggerLike):
    """Minimal logger that stores yt-dlp warnings/errors for later inspection."""

    def __init__(self) -> None:
        self._warnings: list[str] = []
        self._errors: list[str] = []

    @staticmethod
    def _normalize(message: object) -> Optional[str]:
        text = str(message)
        cleaned = strip_ansi(text)
        if cleaned is not None:
            text = cleaned
        normalized = " ".join(part for part in text.split() if part)
        return normalized or None

    def debug(self, msg: str) -> None:  # noqa: D401 - interface contract
        return None

    def warning(self, msg: str) -> None:
        normalized = self._normalize(msg)
        if normalized:
            self._warnings.append(normalized)

    def error(self, msg: str) -> None:
        normalized = self._normalize(msg)
        if normalized:
            self._errors.append(normalized)

    def last_message(self) -> Optional[str]:
        for bucket in (self._errors, self._warnings):
            for message in reversed(bucket):
                if message:
                    return message
        return None


class ExtraOptions(TypedDict, total=False):
    logger: LoggerLike
    progress_hooks: list[Callable[[Mapping[str, Any]], None]]
    postprocessor_hooks: list[Callable[[Mapping[str, Any]], None]]
    post_hooks: list[Callable[[Any], None]]
    match_filter: Callable[[Mapping[str, Any], bool], Optional[str]]


class DownloadError(RuntimeError):
    """Raised when yt_dlp raises an unexpected exception."""


@dataclass(frozen=True)
class ResolvedDownloadOptions:
    """Result of parsing CLI arguments via :func:`resolve_download_options`."""

    cli_args: list[str]
    ydl_opts: dict[str, Any]
    urls: list[str]


@dataclass(frozen=True)
class ResolvedOptions:
    """Result of parsing CLI arguments via :func:`resolve_download_options`."""

    cli_args: list[str]
    urls: list[str]


@dataclass
class ExtractInformationResult:
    """Data returned by :func:`extract_information`."""

    info: YtDlpInfoResult
    extractor: Optional[str]
    extractor_key: Optional[str]
    is_playlist: bool
    entry_count: Optional[int]


@dataclass
class DownloadResult:
    """Information produced by :func:`descargar`."""

    infos: list[YtDlpInfoResult]
    filepaths: list[str]

    @property
    def primary_info(self) -> Optional[YtDlpInfoResult]:
        return self.infos[0] if self.infos else None

    @property
    def primary_filepath(self) -> Optional[str]:
        return self.filepaths[0] if self.filepaths else None


@dataclass
class DownloadPlaylistResult:
    """Information produced by :func:`download_playlist`."""

    playlist_info: YtDlpInfoResult
    entries: list[YtDlpInfoResult]
    filepaths: list[str]

    @property
    def primary_entry(self) -> Optional[YtDlpInfoResult]:
        return self.entries[0] if self.entries else None


def extract_information(
    urls: str | Iterable[str],
    *,
    options: Optional[OptionsConfig] = None,
    download: bool = False,
    fix_urls: bool = True,
) -> ExtractInformationResult:
    """Retrieve metadata for one or more URLs.

    Parameters mirror yt-dlp options but stay intentionally high level.
    ``info_handler`` runs with the raw info dict whenever extraction succeeds.
    """
    targets = _ensure_targets(urls)
    resolved = resolve_download_options(
        targets,
        options=options,
        download=download,
    )
    ydl_opts = resolved.ydl_opts
    if fix_urls:
        __nt: list[str] = []
        fixup_opts: dict[str, Any] = dict(ydl_opts)
        fixup_opts.update(
            {
                "quiet": True,
                "no_warnings": True,
                "skip_download": True,
                "simulate": True,
                "extract_flat": True,
                "ignoreerrors": True,
                "postprocessors": [],
                "progress_hooks": [],
                "postprocessor_hooks": [],
                "noprogress": True,
                "lazy_playlist": True,
                "noplaylist": ydl_opts.get("noplaylist", False),
            }
        )
        with YoutubeDL(cast(Any, fixup_opts)) as __other_yt_dl:
            for __t in targets:
                __inf = __other_yt_dl.extract_info(__t, download=False, process=False)
                if __inf.get("url") and isinstance(__inf.get("url"), str):
                    __nt.append(cast(str, __inf.get("url")))
                    continue
                elif __inf.get("webpage_url") and isinstance(
                    __inf.get("webpage_url"), str
                ):
                    __nt.append(cast(str, __inf.get("webpage_url")))
                    continue
                elif __inf.get("original_url") and isinstance(
                    __inf.get("original_url"), str
                ):
                    __nt.append(cast(str, __inf.get("original_url")))
                    continue
                else:
                    __nt.append(__t)
            targets = __nt

    capture_logger: Optional[_BufferedLogger] = None
    if "logger" not in ydl_opts:
        capture_logger = _BufferedLogger()
        ydl_opts["logger"] = capture_logger

    def _resolve_extract_failure_message() -> str:
        if capture_logger:
            buffered = capture_logger.last_message()
            if buffered:
                return buffered
        return "yt-dlp no devolvió información para la URL solicitada"

    def _runner(ydl: YoutubeDL) -> ExtractInformationResult:
        info_payload = ydl.extract_info(targets[0], download=download, process=False)
        if info_payload is None:
            raise DownloadError(_resolve_extract_failure_message())
        if not isinstance(info_payload, Mapping):
            raise DownloadError("yt-dlp devolvió un resultado inesperado")
        info = cast(YtDlpInfoResult, dict(info_payload))
        extractor_raw = info.get("extractor")
        extractor_key_raw = info.get("extractor_key")
        extractor = extractor_raw if isinstance(extractor_raw, str) else None
        extractor_key = (
            extractor_key_raw if isinstance(extractor_key_raw, str) else None
        )
        is_playlist = looks_like_playlist(info)
        entry_count = _resolve_entry_count(info)
        return ExtractInformationResult(
            info=info,
            extractor=extractor,
            extractor_key=extractor_key,
            is_playlist=is_playlist,
            entry_count=entry_count,
        )

    return _run_with_ytdlp(ydl_opts, _runner)


def download(
    urls: str | Sequence[str],
    *,
    options: Optional[OptionsConfig] = None,
    logger: Optional[LoggerLike] = None,
    progress_hooks: Optional[Iterable[ProgressHook]] = None,
    postprocessor_hooks: Optional[Iterable[PostProcessorHook]] = None,
    post_hooks: Optional[Iterable[PostHook]] = None,
    match_filter: Optional[MatchFilter] = None,
    info_handler: Optional[InfoHandler] = None,
) -> DownloadResult:
    """Download one or more media entries."""

    targets = _ensure_targets(urls)
    wrapped_progress_hooks = _wrap_progress_hooks(progress_hooks)
    wrapped_postprocessor_hooks = _wrap_postprocessor_hooks(postprocessor_hooks)
    wrapped_post_hooks = _wrap_post_hooks(post_hooks)
    wrapped_match_filter = _wrap_match_filter(match_filter)
    overrides = _collect_extra_options(
        logger=logger,
        progress_hooks=wrapped_progress_hooks,
        postprocessor_hooks=wrapped_postprocessor_hooks,
        post_hooks=wrapped_post_hooks,
        match_filter=wrapped_match_filter,
    )
    resolved = resolve_download_options(
        targets,
        options=options,
        download=True,
        extra_ydl_opts=overrides,
    )
    ydl_opts = resolved.ydl_opts
    final_targets = resolved.urls or targets

    def _runner(ydl: YoutubeDL) -> DownloadResult:
        infos: list[YtDlpInfoResult] = []
        filepaths: list[str] = []
        for target in final_targets:
            info = cast(YtDlpInfoResult, ydl.extract_info(target, download=True))
            infos.append(info)
            if info_handler:
                info_handler(info)
            filepath = _safe_prepare_filename(ydl, info)
            if filepath:
                filepaths.append(filepath)
        return DownloadResult(infos=infos, filepaths=filepaths)

    return _run_with_ytdlp(ydl_opts, _runner)


def download_playlist(
    url: str | list[str],
    *,
    options: Optional[OptionsConfig] = None,
    logger: Optional[LoggerLike] = None,
    progress_hooks: Optional[Iterable[ProgressHook]] = None,
    postprocessor_hooks: Optional[Iterable[PostProcessorHook]] = None,
    post_hooks: Optional[Iterable[PostHook]] = None,
    match_filter: Optional[MatchFilter] = None,
    playlist_handler: Optional[PlaylistHandler] = None,
    entry_handler: Optional[EntryHandler] = None,
) -> DownloadPlaylistResult:
    """Download a playlist entry-by-entry while exposing hooks."""

    targets = _ensure_targets(url)
    wrapped_progress_hooks = _wrap_progress_hooks(progress_hooks)
    wrapped_postprocessor_hooks = _wrap_postprocessor_hooks(postprocessor_hooks)
    wrapped_post_hooks = _wrap_post_hooks(post_hooks)
    wrapped_match_filter = _wrap_match_filter(match_filter)
    overrides = _collect_extra_options(
        logger=logger,
        progress_hooks=wrapped_progress_hooks,
        postprocessor_hooks=wrapped_postprocessor_hooks,
        post_hooks=wrapped_post_hooks,
        match_filter=wrapped_match_filter,
    )
    resolved = resolve_download_options(
        targets,
        options=options,
        download=True,
        extra_ydl_opts=overrides,
    )
    ydl_opts = resolved.ydl_opts
    final_targets = resolved.urls or targets

    def _runner(ydl: YoutubeDL) -> DownloadPlaylistResult:
        playlist_info = cast(
            YtDlpInfoResult, ydl.extract_info(final_targets[0], download=True)
        )
        if playlist_handler:
            playlist_handler(playlist_info)

        raw_entries = playlist_info.get("entries")
        entries: list[YtDlpInfoResult] = []
        filepaths: list[str] = []
        candidates = _materialize_entries(raw_entries)
        for index, entry in enumerate(candidates, start=1):
            entries.append(entry)
            if entry_handler:
                entry_handler(index, entry)
            filepath = _safe_prepare_filename(ydl, entry)
            if filepath:
                filepaths.append(filepath)

        return DownloadPlaylistResult(
            playlist_info=playlist_info,
            entries=entries,
            filepaths=filepaths,
        )

    return _run_with_ytdlp(ydl_opts, _runner)


def resolve_download_options(
    urls: str | Iterable[str],
    *,
    options: Optional[OptionsConfig] = None,
    download: bool = False,
    extra_ydl_opts: Optional[ExtraOptions] = None,
) -> ResolvedDownloadOptions:
    """Return the fully parsed yt-dlp option set for the given inputs."""

    targets = _ensure_targets(urls)
    command = parse_options(targets, params=options)
    parsed = _parse_options(command)
    ydl_opts = dict(parsed.ydl_opts)

    ydl_opts.setdefault("quiet", True)
    ydl_opts.setdefault("no_warnings", True)
    if not download:
        ydl_opts.update(
            {
                "skip_download": True,
                "simulate": True,
                "ignoreerrors": True,
                "extract_flat": True,
                "lazy_playlist": True,
            }
        )

    if extra_ydl_opts:
        for key, value in extra_ydl_opts.items():
            ydl_opts[key] = value

    urls_list = list(parsed.urls)
    if not urls_list and targets:
        urls_list = list(targets)

    return ResolvedDownloadOptions(
        cli_args=list(command), ydl_opts=ydl_opts, urls=urls_list
    )


def resolve_options(
    urls: str | Iterable[str],
    *,
    options: Optional[OptionsConfig] = None,
    download: bool = False,
    extra_ydl_opts: Optional[ExtraOptions] = None,
) -> ResolvedOptions:
    """Return the fully parsed yt-dlp option set for the given inputs."""
    response = resolve_download_options(
        urls,
        options=options,
        download=download,
        extra_ydl_opts=extra_ydl_opts,
    )
    return ResolvedOptions(cli_args=response.cli_args, urls=response.urls)


def _ensure_targets(urls: str | Iterable[str]) -> list[str]:
    targets = _sanitize_urls(urls)
    if not targets:
        raise DownloadError("Se requieren al menos una URL válida para continuar")
    return targets


def _sanitize_urls(urls: str | Iterable[str]) -> list[str]:
    if isinstance(urls, str):
        iterable: Iterable[str] = [urls]
    else:
        iterable = list(urls)
    sanitized: list[str] = []
    for candidate in iterable:
        trimmed = candidate.strip()
        if trimmed:
            sanitized.append(trimmed)
    return sanitized


def _collect_extra_options(
    *,
    logger: Optional[LoggerLike] = None,
    progress_hooks: Optional[Iterable[Callable[[Mapping[str, Any]], None]]] = None,
    postprocessor_hooks: Optional[Iterable[Callable[[Mapping[str, Any]], None]]] = None,
    post_hooks: Optional[Iterable[Callable[[Any], None]]] = None,
    match_filter: Optional[Callable[[Mapping[str, Any], bool], Optional[str]]] = None,
) -> ExtraOptions:
    extra: ExtraOptions = {}
    if logger is not None:
        extra["logger"] = logger
    if progress_hooks:
        extra["progress_hooks"] = list(progress_hooks)
    if postprocessor_hooks:
        extra["postprocessor_hooks"] = list(postprocessor_hooks)
    if post_hooks:
        extra["post_hooks"] = list(post_hooks)
    if match_filter is not None:
        extra["match_filter"] = match_filter
    return extra


def _materialize_entries(
    raw_entries: Generator[YtDlpInfoResult, None, None] | list[YtDlpInfoResult] | None,
) -> list[YtDlpInfoResult]:
    if raw_entries is None:
        return []
    try:
        return list(raw_entries)
    except Exception:
        return []


def looks_like_playlist(
    info: YtDlpInfoResult,
) -> bool:
    try:
        model = Info.fast_info(info)
    except Exception:
        model = None
    if model is not None:
        return bool(model.is_playlist)
    entries = info.get("entries")
    return entries is not None


def _resolve_entry_count(info: YtDlpInfoResult) -> Optional[int]:
    for key in ("playlist_count", "n_entries", "playlist_length"):
        value = info.get(key)
        if isinstance(value, int) and value >= 0:
            return value
        try:
            parsed = int(str(value))
        except (TypeError, ValueError):
            parsed = None
        if parsed is not None and parsed >= 0:
            return parsed
    entries = info.get("entries")
    if isinstance(entries, (list, tuple)):
        return len(entries)
    return None


def _safe_prepare_filename(ydl: YoutubeDL, info: YtDlpInfoResult) -> Optional[str]:
    try:
        return ydl.prepare_filename(cast(Any, info))
    except Exception:  # noqa: BLE001 - filepath best effort
        return None


def _run_with_ytdlp(
    options: Mapping[str, Any],
    runner: Callable[[YoutubeDL], TReturn],
) -> TReturn:
    try:
        with YoutubeDL(cast(Any, dict(options))) as ydl:
            return runner(ydl)
    except DownloadError:
        raise
    except Exception as exc:  # noqa: BLE001 - wrap third-party exceptions
        raise DownloadError(str(exc)) from exc


def _normalize_string(value: Any) -> Optional[str]:
    text = clean_string(value)
    if not text:
        return None
    stripped = strip_ansi(text)
    candidate = stripped if stripped is not None else text.strip()
    return candidate or None


def _normalize_description(value: Any) -> Optional[str]:
    text = _normalize_string(value)
    if text is None:
        return None
    truncated = truncate_string(text)
    return truncated or text


def _normalize_tags(raw: Any) -> Optional[list[str]]:
    if not isinstance(raw, Sequence) or isinstance(raw, (str, bytes)):
        return None
    sequence = cast(Sequence[object], raw)
    tags: list[str] = []
    for entry in sequence:
        text = _normalize_string(entry)
        if text:
            tags.append(text)
    return tags or None


def _normalize_thumbnails(
    raw: Any,
) -> Optional[list[YtDlpInfoResultThumbnail]]:
    if not isinstance(raw, Sequence) or isinstance(raw, (str, bytes)):
        return None
    sequence = cast(Sequence[object], raw)
    thumbnails: list[YtDlpInfoResultThumbnail] = []
    for candidate in sequence:
        if not isinstance(candidate, Mapping):
            continue
        entry_map = cast(Mapping[str, Any], candidate)
        entry: dict[str, Any] = dict(entry_map)
        url = _normalize_string(entry.get("url"))
        if not url:
            continue
        entry["url"] = url
        height = normalize_int(entry.get("height"))
        if height is not None:
            entry["height"] = height
        elif "height" in entry:
            entry.pop("height", None)
        width = normalize_int(entry.get("width"))
        if width is not None:
            entry["width"] = width
        elif "width" in entry:
            entry.pop("width", None)
        thumbnails.append(cast(YtDlpInfoResultThumbnail, entry))
    return thumbnails or None


def _normalize_entries(raw: Any) -> Optional[list[YtDlpInfoResult]]:
    if raw is None:
        return None
    iterable: list[Any]
    try:
        iterable = list(cast(Iterable[Any], raw))
    except Exception:  # noqa: BLE001 - fall back when entries are generators
        return None
    entries: list[YtDlpInfoResult] = []
    for item in iterable:
        if isinstance(item, Mapping):
            mapping_item = cast(Mapping[str, Any], item)
            entries.append(_normalize_info_dict(mapping_item))
    return entries or None


def _assign(normalized: dict[str, Any], key: str, value: Any) -> None:
    if value is None:
        normalized.pop(key, None)
    else:
        normalized[key] = value


def _normalize_info_dict(data: Mapping[str, Any]) -> YtDlpInfoResult:
    source = dict(data)
    normalized: dict[str, Any] = dict(source)

    _assign(normalized, "id", _normalize_string(source.get("id")))
    _assign(normalized, "title", _normalize_string(source.get("title")))
    _assign(
        normalized, "description", _normalize_description(source.get("description"))
    )
    _assign(normalized, "thumbnail", _normalize_string(source.get("thumbnail")))
    _assign(normalized, "_type", _normalize_string(source.get("_type")))
    _assign(normalized, "ie_key", _normalize_string(source.get("ie_key")))
    _assign(normalized, "url", _normalize_string(source.get("url")))
    _assign(normalized, "original_url", _normalize_string(source.get("original_url")))
    _assign(normalized, "webpage_url", _normalize_string(source.get("webpage_url")))
    _assign(normalized, "duration", normalize_int(source.get("duration")))
    _assign(
        normalized, "duration_string", _normalize_string(source.get("duration_string"))
    )
    _assign(normalized, "timestamp", normalize_int(source.get("timestamp")))
    _assign(
        normalized, "release_timestamp", normalize_int(source.get("release_timestamp"))
    )
    _assign(
        normalized, "release_date", normalize_upload_date(source.get("release_date"))
    )
    _assign(normalized, "upload_date", normalize_upload_date(source.get("upload_date")))
    _assign(normalized, "channel_id", _normalize_string(source.get("channel_id")))
    _assign(normalized, "channel", _normalize_string(source.get("channel")))
    _assign(normalized, "channel_url", _normalize_string(source.get("channel_url")))
    _assign(normalized, "uploader", _normalize_string(source.get("uploader")))
    _assign(normalized, "uploader_id", _normalize_string(source.get("uploader_id")))
    _assign(normalized, "uploader_url", _normalize_string(source.get("uploader_url")))
    _assign(normalized, "availability", _normalize_string(source.get("availability")))
    _assign(normalized, "live_status", _normalize_string(source.get("live_status")))
    _assign(normalized, "view_count", normalize_int(source.get("view_count")))
    _assign(normalized, "like_count", normalize_int(source.get("like_count")))
    _assign(normalized, "comment_count", normalize_int(source.get("comment_count")))
    _assign(
        normalized,
        "channel_follower_count",
        normalize_int(source.get("channel_follower_count")),
    )
    _assign(
        normalized, "channel_is_verified", to_bool(source.get("channel_is_verified"))
    )
    _assign(normalized, "tags", _normalize_tags(source.get("tags")))
    _assign(normalized, "playlist_count", normalize_int(source.get("playlist_count")))
    _assign(normalized, "playlist_id", _normalize_string(source.get("playlist_id")))
    _assign(
        normalized, "playlist_title", _normalize_string(source.get("playlist_title"))
    )
    _assign(
        normalized,
        "playlist_uploader",
        _normalize_string(source.get("playlist_uploader")),
    )
    _assign(
        normalized,
        "playlist_uploader_id",
        _normalize_string(source.get("playlist_uploader_id")),
    )
    _assign(normalized, "n_entries", normalize_int(source.get("n_entries")))
    _assign(normalized, "playlist_index", normalize_int(source.get("playlist_index")))
    _assign(
        normalized,
        "playlist_autonumber",
        normalize_int(source.get("playlist_autonumber")),
    )
    _assign(normalized, "display_id", _normalize_string(source.get("display_id")))
    _assign(normalized, "age_limit", normalize_int(source.get("age_limit")))

    thumbnails = _normalize_thumbnails(source.get("thumbnails"))
    if thumbnails is not None:
        _assign(normalized, "thumbnails", thumbnails)

    entries = _normalize_entries(source.get("entries"))
    if entries is not None:
        _assign(normalized, "entries", entries)

    return cast(YtDlpInfoResult, normalized)


def _normalize_progress_status(
    value: Optional[str],
) -> Literal["downloading", "finished", "error"]:
    if not value:
        return "downloading"
    text = value.strip().lower()
    if text in {"finished", "done", "completed", "complete"}:
        return "finished"
    if text in {"error", "failed", "aborted"}:
        return "error"
    return "downloading"


def _normalize_postprocessor_status(
    value: Optional[str],
) -> Literal["started", "processing", "finished", "error"]:
    if not value:
        return "processing"
    text = value.strip().lower()
    if text in {"started", "starting"}:
        return "started"
    if text in {"finished", "done", "completed", "complete"}:
        return "finished"
    if text in {"error", "failed", "aborted"}:
        return "error"
    return "processing"


def _normalize_progress_hook_args(data: Mapping[str, Any]) -> ProgressHookArgs:
    payload = ProgressHookPayload(dict(data))
    status = _normalize_progress_status(payload.status)
    info_dict = _normalize_info_dict(payload.info_dict or {})

    normalized: ProgressHookArgs = {
        "status": status,
        "info_dict": info_dict,
    }

    downloaded = normalize_int(payload.downloaded_bytes)
    if downloaded is not None:
        normalized["downloaded_bytes"] = downloaded

    total = normalize_int(payload.total_bytes)
    if total is not None:
        normalized["total_bytes"] = total

    estimate = normalize_int(data.get("total_bytes_estimate"))
    if estimate is not None:
        normalized["total_bytes_estimate"] = estimate

    percent = payload.percent
    if percent is not None:
        normalized["percent"] = normalize_percent(percent)

    message = _normalize_string(payload.message)
    if message is not None:
        normalized["message"] = message

    tmpfilename = _normalize_string(payload.tmpfilename)
    if tmpfilename is not None:
        normalized["tmpfilename"] = tmpfilename

    filename = _normalize_string(payload.filename)
    if filename is not None:
        normalized["filename"] = filename

    eta = normalize_float(payload.eta)
    if eta is not None:
        normalized["eta"] = eta

    speed = normalize_float(payload.speed)
    if speed is not None:
        normalized["speed"] = speed

    elapsed = normalize_float(payload.elapsed)
    if elapsed is not None:
        normalized["elapsed"] = elapsed

    fragment_index = normalize_int(data.get("fragment_index"))
    if fragment_index is not None:
        normalized["fragment_index"] = fragment_index

    fragment_count = normalize_int(data.get("fragment_count"))
    if fragment_count is not None:
        normalized["fragment_count"] = fragment_count

    playlist_index = normalize_int(payload.playlist_index)
    if playlist_index is not None:
        normalized["playlist_index"] = playlist_index

    playlist_count = normalize_int(payload.playlist_count)
    if playlist_count is not None:
        normalized["playlist_count"] = playlist_count

    entry_id = _normalize_string(payload.entry_id)
    if entry_id is not None:
        normalized["entry_id"] = entry_id

    playlist_id = _normalize_string(info_dict.get("playlist_id"))
    if playlist_id is not None:
        normalized["playlist_id"] = playlist_id

    current_item = normalize_int(payload.current_item)
    if current_item is not None:
        normalized["current_item"] = current_item

    total_items = normalize_int(payload.total_items)
    if total_items is not None:
        normalized["total_items"] = total_items

    ctx_id = _normalize_string(data.get("ctx_id"))
    if ctx_id is not None:
        normalized["ctx_id"] = ctx_id

    return normalized


def _normalize_postprocessor_hook_args(
    data: Mapping[str, Any],
) -> PostProcessorHookArgs:
    payload = PostProcessorHookPayload(dict(data))
    status = _normalize_postprocessor_status(payload.status)
    postprocessor = _normalize_string(payload.postprocessor) or "postprocessor"
    info_dict = _normalize_info_dict(payload.info_dict or {})
    normalized: PostProcessorHookArgs = {
        "status": status,
        "postprocessor": postprocessor,
        "info_dict": info_dict,
        "percent": payload.stage_percent,
        "message": payload.message,
        "playlist_index": normalize_int(payload.playlist_index),
        "entry_id": _normalize_string(payload.entry_id),
        "playlist_id": _normalize_string(info_dict.get("playlist_id")),
    }

    return normalized


def _normalize_post_hook_message(data: Any) -> str:
    if isinstance(data, Mapping):
        mapping = cast(Mapping[str, Any], data)
        payload = PostHookPayload(dict(mapping))
        message = payload.message
        if message:
            return message
        status = _normalize_string(mapping.get("status"))
        if status:
            return status
    text_source: Any = cast(Any, data)
    text = "" if text_source is None else str(text_source)
    cleaned = strip_ansi(text)
    candidate = cleaned if cleaned is not None else text.strip()
    return candidate or ""


def _wrap_progress_hooks(
    hooks: Optional[Iterable[ProgressHook]],
) -> Optional[list[Callable[[Mapping[str, Any]], None]]]:
    if not hooks:
        return None

    wrapped: list[Callable[[Mapping[str, Any]], None]] = []

    def _adapter(user_hook: ProgressHook) -> Callable[[Mapping[str, Any]], None]:
        def _wrapped(payload: Mapping[str, Any]) -> None:
            normalized = _normalize_progress_hook_args(payload)
            user_hook(normalized)

        return _wrapped

    for hook in hooks:
        wrapped.append(_adapter(hook))
    return wrapped or None


def _wrap_postprocessor_hooks(
    hooks: Optional[Iterable[PostProcessorHook]],
) -> Optional[list[Callable[[Mapping[str, Any]], None]]]:
    if not hooks:
        return None

    wrapped: list[Callable[[Mapping[str, Any]], None]] = []

    def _adapter(user_hook: PostProcessorHook) -> Callable[[Mapping[str, Any]], None]:
        def _wrapped(payload: Mapping[str, Any]) -> None:
            normalized = _normalize_postprocessor_hook_args(payload)
            user_hook(normalized)

        return _wrapped

    for hook in hooks:
        wrapped.append(_adapter(hook))
    return wrapped or None


def _wrap_post_hooks(
    hooks: Optional[Iterable[PostHook]],
) -> Optional[list[Callable[[Any], None]]]:
    if not hooks:
        return None

    wrapped: list[Callable[[Any], None]] = []

    def _adapter(user_hook: PostHook) -> Callable[[Any], None]:
        def _wrapped(payload: Any) -> None:
            message = _normalize_post_hook_message(payload)
            user_hook(message)

        return _wrapped

    for hook in hooks:
        wrapped.append(_adapter(hook))
    return wrapped or None


def _wrap_match_filter(
    user_filter: Optional[MatchFilter],
) -> Optional[Callable[[Mapping[str, Any], bool], Optional[str]]]:
    if user_filter is None:
        return None

    def _wrapped(info: Mapping[str, Any], incomplete: bool) -> Optional[str]:
        normalized_info = _normalize_info_dict(info)
        args: MatchFilterArgs = {"incomplete": bool(incomplete)}
        return user_filter(normalized_info, args)

    return _wrapped
