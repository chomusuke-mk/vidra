from __future__ import annotations

import re
import threading
from typing import Callable, Optional, Sequence, Set, TypeVar

from ..config import JobStatus
from ..models.core.manager import (
    EntryEndPayload,
    EntryMetadataPayload,
    ErrorPayload,
    ExtractInfoResult,
    IdentityFields,
    JobEndPayload,
    LogPayload,
    ManagerEndEvent,
    ManagerInfoEvent,
    ManagerPayload,
    ManagerProgressEvent,
    PlaylistEndPayload,
    PlaylistInfoPayload,
    PostHookPayload,
    PostprocessorPayload,
    ProgressPayload,
    StagePayload,
)

from .contract import Info, PostprocessorHook, ProgressHook
from .downloader import (
    DownloadError,
    DownloadPlaylistResult,
    DownloadResult,
    LoggerLike,
    ProgressHookArgs,
    PostProcessorHookArgs,
    YtDlpInfoResult,
    download,
    download_playlist,
    extract_information,
)
from .utils import OptionsConfig
from ..utils import normalize_percent


_LOG_TAG_PATTERN = re.compile(r"^\[(?P<tag>[^\]]+)\]\s*(?P<message>.*)$")
_STATUS_PREFIXES = {"info", "warning", "warn", "error"}

ProgressHandler = Callable[[ManagerProgressEvent], None]
InfoHandler = Callable[[ManagerInfoEvent], None]
EndHandler = Callable[[ManagerEndEvent], None]
PayloadT = TypeVar("PayloadT", bound=ManagerPayload)


class Manager:
    """High level orchestration over yt-dlp actions for websocket clients."""

    def __init__(self) -> None:
        self._lock = threading.RLock()

    # ------------------------------------------------------------------
    # Stage formatting helpers
    # ------------------------------------------------------------------
    @staticmethod
    def _format_stage_name(
        value: Optional[str], *, default: Optional[str] = None
    ) -> Optional[str]:
        if value is None:
            return default
        text = value.strip()
        if not text:
            return default
        return text

    @staticmethod
    def _format_stage_message(value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        text = value.strip()
        if not text:
            return None
        tag_match = _LOG_TAG_PATTERN.match(text)
        if tag_match:
            candidate = tag_match.group("message") or ""
            candidate = candidate.strip()
            if candidate:
                text = candidate
        if ":" in text:
            head, tail = text.split(":", 1)
            left = head.strip().lower()
            if left in _STATUS_PREFIXES and tail.strip():
                text = tail.strip()
        normalized = " ".join(part for part in text.split() if part)
        return normalized or None

    @staticmethod
    def _normalize_playlist_targets(urls: str | Sequence[str]) -> str | list[str]:
        if isinstance(urls, str):
            return urls
        return list(urls)

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------
    def extract_info(
        self,
        urls: str | Sequence[str],
        *,
        options: Optional[OptionsConfig] = None,
        download: bool = False,
    ) -> ExtractInfoResult:
        """Return metadata for the given URLs without exposing yt-dlp internals."""

        result = extract_information(urls, options=options, download=download)
        info_data = result.info
        model = Info.fast_info(info_data)
        raw_payload = dict(info_data)
        return ExtractInfoResult(
            model=model,
            extractor=result.extractor,
            extractor_key=result.extractor_key,
            is_playlist=result.is_playlist,
            entry_count=result.entry_count,
            raw=raw_payload,
        )

    def download(
        self,
        urls: str | Sequence[str],
        *,
        options: Optional[OptionsConfig] = None,
        progress_handler: Optional[ProgressHandler] = None,
        info_handler: Optional[InfoHandler] = None,
        end_handler: Optional[EndHandler] = None,
    ) -> DownloadResult:
        """Download one or more entries providing rich callbacks for the UI layer."""

        progress_hook = self._build_progress_hook(
            scope="download",
            progress_handler=progress_handler,
            info_handler=info_handler,
        )
        postprocessor_hook = self._build_postprocessor_hook(
            scope="download",
            info_handler=info_handler,
        )
        post_hook = self._build_post_hook(
            scope="download",
            info_handler=info_handler,
        )
        logger = self._build_logger(scope="download", info_handler=info_handler)

        try:
            result = download(
                urls,
                options=options,
                logger=logger,
                progress_hooks=[progress_hook],
                postprocessor_hooks=[postprocessor_hook],
                post_hooks=[post_hook],
            )
        except DownloadError as exc:  # noqa: BLE001 - propagate after notifying handlers
            error_message = str(exc)
            self._emit(
                info_handler,
                ErrorPayload(message=error_message),
                scope="download",
            )
            self._emit(
                end_handler,
                JobEndPayload(status="error", files=tuple(), message=error_message),
                scope="download",
            )
            raise
        else:
            payload = JobEndPayload(
                status="completed",
                files=tuple(result.filepaths),
                primary_file=result.primary_filepath,
            )
            self._emit(end_handler, payload, scope="download")
            return result

    def download_playlist(
        self,
        urls: str | Sequence[str],
        *,
        options: Optional[OptionsConfig] = None,
        playlist_progress_handler: Optional[ProgressHandler] = None,
        playlist_info_handler: Optional[InfoHandler] = None,
        playlist_end_handler: Optional[EndHandler] = None,
        entry_progress_handler: Optional[ProgressHandler] = None,
        entry_info_handler: Optional[InfoHandler] = None,
        entry_end_handler: Optional[EndHandler] = None,
    ) -> DownloadPlaylistResult:
        """Download playlist entries exposing independent playlist and item callbacks."""

        finished_entries: Set[int] = set()
        progress_hook = self._build_progress_hook(
            scope="playlist",
            progress_handler=playlist_progress_handler,
            info_handler=playlist_info_handler,
            entry_progress_handler=entry_progress_handler,
            entry_info_handler=entry_info_handler,
            entry_end_handler=entry_end_handler,
            finished_entries=finished_entries,
        )
        postprocessor_hook = self._build_postprocessor_hook(
            scope="playlist",
            info_handler=playlist_info_handler,
            entry_info_handler=entry_info_handler,
        )
        post_hook = self._build_post_hook(
            scope="playlist",
            info_handler=playlist_info_handler,
            entry_info_handler=entry_info_handler,
        )
        logger = self._build_logger(
            scope="playlist", info_handler=playlist_info_handler
        )

        def _playlist_info_emitter(info: YtDlpInfoResult) -> None:
            model = Info.from_info(info)
            playlist_id = model.id or info.get("playlist_id") or info.get("id")
            payload = PlaylistInfoPayload(
                id=playlist_id,
                entry_count=model.entry_count,
                is_playlist=model.is_playlist,
                playlist_id=model.id or playlist_id,
                title=model.title or info.get("title") or info.get("playlist_title"),
                description=model.description,
                url=model.url,
                thumbnail=model.thumbnail,
            )
            self._emit(playlist_info_handler, payload, scope="playlist")

        def _entry_metadata_emitter(index: int, info: YtDlpInfoResult) -> None:
            model = Info.fast_info(info)
            entry_id = model.id or info.get("id") or info.get("url")
            payload = EntryMetadataPayload(
                index=index,
                id=entry_id,
                duration=model.duration or info.get("duration"),
                duration_string=model.duration_string or info.get("duration_string"),
                title=model.title or info.get("title"),
                thumbnail=model.thumbnail,
                url=model.url or info.get("url"),
                description=model.description,
                playlist_id=model.id,
            )
            self._emit(entry_info_handler, payload, scope="playlist_entry")

        playlist_targets = self._normalize_playlist_targets(urls)

        try:
            result = download_playlist(
                playlist_targets,
                options=options,
                logger=logger,
                progress_hooks=[progress_hook],
                postprocessor_hooks=[postprocessor_hook],
                post_hooks=[post_hook],
                playlist_handler=_playlist_info_emitter
                if playlist_info_handler
                else None,
                entry_handler=_entry_metadata_emitter if entry_info_handler else None,
            )
        except DownloadError as exc:  # noqa: BLE001
            error_message = str(exc)
            self._emit(
                playlist_info_handler,
                ErrorPayload(stage="playlist_job", message=error_message),
                scope="playlist",
            )
            self._emit(
                playlist_end_handler,
                PlaylistEndPayload(
                    status="error",
                    entry_count=None,
                    files=tuple(),
                    message=error_message,
                ),
                scope="playlist",
            )
            raise
        else:
            playlist_model = Info.from_info(result.playlist_info)
            playlist_identifier = (
                playlist_model.id
                or result.playlist_info.get("playlist_id")
                or result.playlist_info.get("id")
            )

            if entry_end_handler:
                total_entries = len(result.entries)
                for index in range(1, total_entries + 1):
                    if index in finished_entries:
                        continue
                    entry_data = result.entries[index - 1]
                    entry_model = Info.fast_info(entry_data)
                    entry_identifier = (
                        entry_model.id or entry_data.get("id") or entry_data.get("url")
                    )
                    playlist_item_id = entry_data.get("playlist_id") or entry_identifier
                    identity = self._identity_fields(
                        playlist_index=index,
                        entry_id=entry_identifier,
                        playlist_id=playlist_item_id,
                    )
                    payload = EntryEndPayload(
                        state="END_ITEM",
                        status="completed",
                        index=index,
                        playlist_index=identity.playlist_index,
                        entry_id=identity.entry_id,
                        playlist_id=identity.playlist_id,
                        title=entry_model.title,
                        url=entry_model.url or entry_data.get("url"),
                    )
                    self._emit(entry_end_handler, payload, scope="playlist_entry")

                summary_payload = EntryEndPayload(
                    state="END_JOB",
                    status="completed",
                    entry_count=len(result.entries),
                    files=tuple(result.filepaths),
                    playlist_id=playlist_identifier,
                    title=playlist_model.title,
                )
                self._emit(entry_end_handler, summary_payload, scope="playlist_entry")

            playlist_payload = PlaylistEndPayload(
                status="completed",
                entry_count=len(result.entries),
                files=tuple(result.filepaths),
                playlist_id=playlist_identifier,
                title=playlist_model.title,
            )
            self._emit(playlist_end_handler, playlist_payload, scope="playlist")
            return result

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------
    def _build_progress_hook(
        self,
        *,
        scope: str,
        progress_handler: Optional[ProgressHandler] = None,
        info_handler: Optional[InfoHandler] = None,
        entry_progress_handler: Optional[ProgressHandler] = None,
        entry_info_handler: Optional[InfoHandler] = None,
        entry_end_handler: Optional[EndHandler] = None,
        finished_entries: Optional[Set[int]] = None,
    ) -> Callable[[ProgressHookArgs], None]:
        finished: Set[int]
        if finished_entries is not None:
            finished = finished_entries
        else:
            finished = set[int]()

        def _hook(data: ProgressHookArgs) -> None:
            progress = ProgressHook(data)
            identity = self._identity_fields(
                playlist_index=progress.playlist_index,
                entry_id=progress.entry_id,
                playlist_id=progress.playlist_id,
            )
            base_stage = "playlist" if scope == "playlist" else "download"
            job_status = self._normalize_job_status(progress.status)
            title = (
                progress.info.title if progress.info and progress.info.title else None
            )

            primary_payload = ProgressPayload(
                type="playlist_progress" if scope == "playlist" else None,
                stage=base_stage,
                status=job_status,
                percent=progress.percent,
                downloaded_bytes=progress.downloaded_bytes,
                total_bytes=progress.total_bytes,
                remaining_bytes=progress.remaining_bytes,
                speed=progress.speed,
                eta=progress.eta,
                elapsed=progress.elapsed,
                filename=progress.filename,
                tmpfilename=progress.tmpfilename,
                playlist_index=identity.playlist_index,
                entry_id=identity.entry_id,
                playlist_id=identity.playlist_id,
                playlist_count=progress.playlist_count,
                current_item=progress.current_item,
                total_items=progress.total_items,
                title=title,
            )
            if progress_handler:
                self._emit(progress_handler, primary_payload, scope=scope)

            stage_percent = normalize_percent(progress.percent)
            stage_value = self._format_stage_name(progress.status, default=base_stage)
            stage_payload = StagePayload(
                stage=stage_value or base_stage,
                stage_name=stage_value or base_stage,
                status=job_status,
                message=self._format_stage_message(progress.message),
                stage_percent=stage_percent,
                percent=stage_percent,
                playlist_index=identity.playlist_index,
                entry_id=identity.entry_id,
                playlist_id=identity.playlist_id,
                playlist_count=progress.playlist_count,
                current_item=progress.current_item,
                total_items=progress.total_items,
                filename=progress.filename,
            )
            if info_handler:
                self._emit(info_handler, stage_payload, scope=scope)

            if entry_progress_handler and progress.playlist_index is not None:
                entry_progress_payload = ProgressPayload(
                    type="entry_progress",
                    stage="playlist_entry",
                    status=job_status,
                    percent=progress.percent,
                    downloaded_bytes=progress.downloaded_bytes,
                    total_bytes=progress.total_bytes,
                    remaining_bytes=progress.remaining_bytes,
                    speed=progress.speed,
                    eta=progress.eta,
                    elapsed=progress.elapsed,
                    filename=progress.filename,
                    tmpfilename=progress.tmpfilename,
                    playlist_index=identity.playlist_index,
                    entry_id=identity.entry_id,
                    playlist_id=identity.playlist_id,
                    playlist_count=progress.playlist_count,
                    current_item=progress.current_item,
                    total_items=progress.total_items,
                    title=title,
                    index=progress.playlist_index,
                )
                self._emit(
                    entry_progress_handler,
                    entry_progress_payload,
                    scope="playlist_entry",
                )

            if entry_info_handler and progress.playlist_index is not None:
                entry_stage_payload = StagePayload(
                    type="entry_stage",
                    stage=stage_payload.stage,
                    stage_name=stage_payload.stage_name,
                    status=stage_payload.status,
                    message=stage_payload.message,
                    stage_percent=stage_payload.stage_percent,
                    percent=stage_payload.percent,
                    playlist_index=identity.playlist_index,
                    entry_id=identity.entry_id,
                    playlist_id=identity.playlist_id,
                    playlist_count=progress.playlist_count,
                    current_item=progress.current_item,
                    total_items=progress.total_items,
                    filename=stage_payload.filename,
                    index=progress.playlist_index,
                )
                self._emit(
                    entry_info_handler, entry_stage_payload, scope="playlist_entry"
                )

            if (
                entry_end_handler
                and progress.playlist_index is not None
                and progress.status in {"finished", "error"}
                and progress.playlist_index not in finished
            ):
                finished.add(progress.playlist_index)
                entry_end_payload = EntryEndPayload(
                    state="END_ITEM",
                    status=job_status,
                    index=progress.playlist_index,
                    playlist_index=identity.playlist_index,
                    entry_id=identity.entry_id,
                    playlist_id=identity.playlist_id,
                    percent=progress.percent,
                    filename=progress.filename,
                    title=title,
                    url=progress.info.url if progress.info else None,
                )
                self._emit(entry_end_handler, entry_end_payload, scope="playlist_entry")

        return _hook

    def _build_postprocessor_hook(
        self,
        *,
        scope: str,
        info_handler: Optional[InfoHandler] = None,
        entry_info_handler: Optional[InfoHandler] = None,
    ) -> Callable[[PostProcessorHookArgs], None]:
        def _hook(data: PostProcessorHookArgs) -> None:
            hook = PostprocessorHook(data)
            identity = self._identity_fields(
                playlist_index=hook.playlist_index,
                entry_id=hook.entry_id,
                playlist_id=hook.playlist_id,
            )
            status = self._normalize_job_status(hook.status)
            stage_name = (
                self._format_stage_name(hook.postprocessor, default=hook.status)
                or "postprocessor"
            )
            stage_message = self._format_stage_message(hook.message)
            stage_percent = normalize_percent(hook.percent)

            payload = PostprocessorPayload(
                type="postprocessor",
                stage=stage_name,
                stage_name=stage_name,
                status=status,
                message=stage_message,
                stage_percent=stage_percent,
                percent=stage_percent,
                name=stage_name,
                playlist_index=identity.playlist_index,
                entry_id=identity.entry_id,
                playlist_id=identity.playlist_id,
            )
            if info_handler:
                self._emit(info_handler, payload, scope=scope)

            if entry_info_handler and hook.playlist_index is not None:
                entry_payload = PostprocessorPayload(
                    type="entry_postprocessor",
                    stage=stage_name,
                    stage_name=stage_name,
                    status=status,
                    message=stage_message,
                    stage_percent=stage_percent,
                    percent=stage_percent,
                    name=stage_name,
                    playlist_index=identity.playlist_index,
                    entry_id=identity.entry_id,
                    playlist_id=identity.playlist_id,
                    index=hook.playlist_index,
                )
                self._emit(entry_info_handler, entry_payload, scope="playlist_entry")

        return _hook

    def _build_post_hook(
        self,
        *,
        scope: str,
        info_handler: Optional[InfoHandler] = None,
        entry_info_handler: Optional[InfoHandler] = None,
    ) -> Callable[[str], None]:
        def _hook(message: str) -> None:
            status_value = self._infer_post_hook_status(message)
            job_status = self._normalize_job_status(status_value)
            stage_name = self._format_stage_name("job") or "job"
            formatted_message = self._format_stage_message(message)
            stage_percent = 100.0 if job_status == "completed" else None

            payload = PostHookPayload(
                type="post_hook",
                stage=stage_name,
                stage_name=stage_name,
                status=job_status,
                raw_status=status_value,
                message=formatted_message,
                stage_percent=stage_percent,
                percent=stage_percent,
            )
            if info_handler:
                self._emit(info_handler, payload, scope=scope)

            if entry_info_handler:
                entry_payload = PostHookPayload(
                    type="entry_post_hook",
                    stage=stage_name,
                    stage_name=stage_name,
                    status=job_status,
                    raw_status=status_value,
                    message=formatted_message,
                    stage_percent=stage_percent,
                    percent=stage_percent,
                )
                self._emit(entry_info_handler, entry_payload, scope="playlist_entry")

        return _hook

    def _build_logger(
        self,
        *,
        scope: str,
        info_handler: Optional[InfoHandler],
    ) -> LoggerLike:
        manager = self

        class _ForwardLogger:
            def debug(self, msg: str) -> None:
                manager._emit_log(info_handler, scope, "debug", msg)

            def info(self, msg: str) -> None:
                manager._emit_log(info_handler, scope, "info", msg)

            def warning(self, msg: str) -> None:  # noqa: D401 - same semantics
                manager._emit_log(info_handler, scope, "warning", msg)

            def error(self, msg: str) -> None:
                manager._emit_log(info_handler, scope, "error", msg)

        return _ForwardLogger()

    def _emit(
        self,
        handler: Optional[Callable[[PayloadT], None]],
        payload: Optional[PayloadT],
        *,
        scope: str,
    ) -> None:
        if handler is None or payload is None:
            return
        scoped = payload.with_scope(scope)
        self._safe_call(handler, scoped)

    def _emit_log(
        self, handler: Optional[InfoHandler], scope: str, level: str, message: object
    ) -> None:
        if handler is None:
            return
        normalized_level = str(level or "info").strip().lower() or "info"
        text = "" if message is None else str(message)
        sanitized = text.strip()
        if not sanitized:
            return
        payload = LogPayload(
            status=normalized_level,
            level=normalized_level,
            message=sanitized,
        )
        self._emit(handler, payload, scope=scope)

    @staticmethod
    def _infer_post_hook_status(raw_message: Optional[str]) -> str:
        if raw_message is None:
            return "finished"
        text = raw_message.strip()
        if not text:
            return "finished"
        tag_match = _LOG_TAG_PATTERN.match(text)
        if tag_match:
            tag = (tag_match.group("tag") or "").strip().lower()
            if tag in _STATUS_PREFIXES:
                return tag
        lowered = text.lower()
        if ":" in text:
            head, tail = text.split(":", 1)
            candidate = head.strip().lower()
            if candidate in _STATUS_PREFIXES and tail.strip():
                return candidate
        for prefix in _STATUS_PREFIXES:
            if lowered.startswith(prefix):
                return prefix
        return "finished"

    @staticmethod
    def _normalize_job_status(status: Optional[str]) -> str:
        if status is None:
            return JobStatus.RUNNING.value
        text = str(status).strip().lower()
        if not text:
            return JobStatus.RUNNING.value
        if text in {"finished", "done", "completed", "complete"}:
            return JobStatus.COMPLETED.value
        if text in {"error", "failed", "fail", "aborted"}:
            return "error"
        if text in {
            "downloading",
            "postprocessing",
            "processing",
            "preprocessing",
            "started",
            "starting",
            "in_progress",
        }:
            return JobStatus.RUNNING.value
        return text

    @staticmethod
    def _identity_fields(
        *,
        playlist_index: Optional[int],
        entry_id: Optional[str],
        playlist_id: Optional[str],
    ) -> IdentityFields:
        entry_value = str(entry_id).strip() if entry_id else None
        playlist_value = str(playlist_id).strip() if playlist_id else None
        return IdentityFields(
            playlist_index=playlist_index,
            entry_id=entry_value,
            playlist_id=playlist_value,
        )

    @staticmethod
    def _safe_call(handler: Callable[[PayloadT], None], payload: PayloadT) -> None:
        try:
            handler(payload)
        except Exception:
            # Best effort: downstream handlers should not break the download flow.
            return


__all__ = ["Manager", "ExtractInfoResult"]
