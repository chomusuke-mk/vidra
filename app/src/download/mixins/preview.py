from __future__ import annotations

import shlex
import threading
from datetime import datetime, timezone
from typing import (
    Any,
    Callable,
    Dict,
    Iterable,
    List,
    Mapping,
    Optional,
    Sequence,
    Set,
    Tuple,
    TypedDict,
    cast,
)
import traceback

from ...config import JobStatus, JobUpdateReason, SocketEvent
from ...core import build_options_config, parse_options
from ...core.contract import Info
from ...core.downloader import YtDlpInfoResult
from ...download.mixins.manager_utils import (
    ManagerUtilsMixin,
    metadata_get_playlist_model,
    metadata_get_preview_model,
    metadata_store_playlist_model,
    metadata_store_preview_model,
)
from ...download.mixins.protocols import (
    PreviewManagerProtocol,
    ProgressManagerProtocol,
)
from ...download.models import (
    DownloadJob,
    DownloadJobMetadataPayload,
    DownloadJobOptionsPayload,
    DownloadJobProgressPayload,
)
from ...download.stages import DownloadStage
from ...log_config import verbose_log
from ...models.download.manager import SerializedJobPayload
from ...models.download.mixins.preview import (
    PlaylistEntryPayload,
    PlaylistMetadataPayload,
    PreviewMetadataPayload,
    PreviewThumbnailPayload,
    PlaylistSnapshotPayload,
)
from ...models.socket import (
    EntryInfoPayload,
    GlobalInfoPayload,
    ListInfoEndsPayload,
    PlaylistEntrySummary,
    PlaylistSummary,
    PreviewSummary,
)
from ...models.shared import (
    JSONValue,
    PlaylistEntryMetadataPayload,
    PlaylistMetadata,
    PreviewMetadata,
    Thumbnail,
    clone_json_value,
)
from ...utils import now_iso, strip_ansi, to_bool, to_int


EntrySource = Sequence[YtDlpInfoResult] | Iterable[YtDlpInfoResult]

MetadataSanitizer = Callable[[object | None], DownloadJobMetadataPayload]


class PreviewExtractionPayload(TypedDict, total=False):
    entries: EntrySource


class PreviewCollectionError(RuntimeError):
    """Raised when preview extraction fails before the download phase."""


def _coerce_thumbnail_sequence(
    value: Sequence[PreviewThumbnailPayload]
    | Sequence[Mapping[str, JSONValue]]
    | Mapping[str, JSONValue]
    | None,
) -> Sequence[Mapping[str, JSONValue]] | None:
    if value is None:
        return None
    if isinstance(value, Mapping):
        return [value]
    sequence = cast(Sequence[Any], value)
    payloads: list[Mapping[str, JSONValue]] = []
    for entry in sequence:
        if isinstance(entry, Mapping):
            payloads.append(cast(Mapping[str, JSONValue], entry))
    return payloads
    return None


class PreviewMixin(ManagerUtilsMixin):
    def _emit_socket_event(
        self,
        event: str,
        payload: JSONValue,
        *,
        room: Optional[str],
    ) -> None:
        manager = self._preview_manager()
        manager.emit_socket(event, payload, room=room)

    def _store_progress_payload(
        self, job_id: str, payload: DownloadJobProgressPayload
    ) -> None:
        progress_manager = cast("ProgressManagerProtocol", self)
        progress_manager.store_progress(job_id, payload)

    def _preview_manager(self) -> "PreviewManagerProtocol":
        return cast("PreviewManagerProtocol", self)

    def _build_cli_args(self, job: DownloadJob) -> List[str]:
        return self._build_cli_args_from(job.urls, job.options)

    def _build_cli_args_from(
        self,
        urls: List[str],
        options: Optional[DownloadJobOptionsPayload],
    ) -> List[str]:
        option_copy = dict(options or {})
        cli_args_raw: Any = option_copy.pop("cli_args", None)
        cli_args: JSONValue | None
        cli_args_value: object | None = cli_args_raw
        if cli_args_value is None:
            cli_args = None
        elif isinstance(cli_args_value, (str, int, float, bool)):
            cli_args = cast(JSONValue, cli_args_value)
        elif isinstance(cli_args_value, list):
            cli_args = cast(JSONValue, cli_args_value)
        elif isinstance(cli_args_value, dict):
            cli_args = cast(JSONValue, cli_args_value)
        else:
            text_value = str(cli_args_value).strip()
            cli_args = text_value or None
        sanitized_urls = [url.strip() for url in urls if url.strip()]
        if not sanitized_urls:
            sanitized_urls = list(urls)
        if cli_args:
            command = self._normalize_cli_args(cli_args)
            command.extend(sanitized_urls)
            return command
        params = build_options_config(option_copy)
        return parse_options(sanitized_urls, params=params)

    def _normalize_cli_args(self, cli_args: JSONValue) -> List[str]:
        if cli_args is None:
            return []
        if isinstance(cli_args, str):
            return [arg for arg in shlex.split(cli_args) if arg]
        if isinstance(cli_args, Sequence) and not isinstance(cli_args, (str, bytes)):
            normalized: List[str] = []
            for arg in cli_args:
                if arg is None:
                    continue
                text = str(arg).strip()
                if text:
                    normalized.append(text)
            return normalized
        if isinstance(cli_args, Iterable):
            normalized = []
            for arg in cli_args:
                if arg is None:
                    continue
                text = str(arg).strip()
                if text:
                    normalized.append(text)
            return normalized
        text = str(cli_args).strip()
        return [text] if text else []

    def _schedule_preview_collection(
        self,
        job_id: str,
        urls: Iterable[str],
        options: Optional[DownloadJobOptionsPayload],
    ) -> None:
        """Start a background thread to gather preview metadata for a job.

        The preview thread calls ``_collect_preview_for_job`` which runs the
        lightweight yt-dlp extraction. Its output determines if the URL behaves
        as a playlist and streams entries so the UI can render the selection
        modal progressively, while emitting GLOBAL_INFO/ENTRY_INFO websocket
        events for the frontend.
        """
        candidates = [url.strip() for url in urls if url.strip()]
        if not candidates:
            self._mark_preview_ready(job_id)
            return
        options_copy = dict(options or {})
        thread = threading.Thread(
            target=self._collect_preview_for_job,
            args=(job_id, candidates, options_copy),
            name=f"preview-{job_id}",
            daemon=True,
        )
        thread.start()

    def _ensure_job_playlist_flag(
        self,
        job_id: str,
        *,
        is_playlist: Optional[bool],
    ) -> None:
        if is_playlist is not False:
            return
        manager = self._preview_manager()
        updated = False
        with manager.lock:
            job = manager.jobs.get(job_id)
            if not job:
                return
            options = job.options
            playlist_flag = options.get("playlist")
            if playlist_flag is False:
                return
            updated_options: DownloadJobOptionsPayload = dict(options)
            updated_options["playlist"] = False
            job.options = updated_options
            updated = True
        if not updated:
            return
        verbose_log(
            "job_option_playlist_disabled",
            {"job_id": job_id, "reason": "preview_detected_non_playlist"},
        )
        append_log = getattr(self, "append_log", None)
        if callable(append_log):
            append_log(
                job_id,
                "info",
                "Se desactivó playlist porque la vista previa no detectó playlist",
            )
        persist_jobs = getattr(self, "_persist_jobs", None)
        if callable(persist_jobs):
            persist_jobs()

    def _collect_preview_for_job(
        self,
        job_id: str,
        urls: List[str],
        options: Optional[DownloadJobOptionsPayload],
    ) -> None:
        """Run yt-dlp metadata extraction and feed playlist previews.

        Uses ``CoreManager.extract_info`` (and therefore
        ``ytdlp_adapter.extraer_informacion`` with ``process=False``) so entries
        remain as a generator. As items arrive it updates job metadata,
        broadcasts playlist snapshots, emits ENTRY_INFO websocket events, and
        decides whether user selection is required. Once enumeration finishes
        it sends LIST_INFO_ENDS before releasing the worker thread.
        """
        collected_entries: List[PlaylistEntryPayload] = []
        total_count_hint: Optional[int] = None
        preview_ready_marked = False
        try:
            core = self._core_manager()
            options_config = build_options_config(options)
            result = core.extract_info(
                urls,
                options=options_config,
                download=False,
            )
            self._ensure_job_playlist_flag(
                job_id,
                is_playlist=result.is_playlist,
            )
            total_count_hint = result.entry_count
            entries_source: Optional[EntrySource] = None
            collecting_entries = False
            raw_payload_value = getattr(result, "raw", None)
            raw_payload: Optional[PreviewExtractionPayload] = None
            if isinstance(raw_payload_value, dict):
                raw_payload = cast(PreviewExtractionPayload, raw_payload_value)
            if raw_payload is not None:
                raw_entries = raw_payload.get("entries")
                (
                    entries_source,
                    collecting_entries,
                ) = self._coerce_entry_source(raw_entries)

            preview_metadata_model = self._build_preview_from_info(result)
            preview_metadata: Optional[PreviewMetadataPayload] = None
            playlist_model_from_preview = (
                preview_metadata_model.playlist if preview_metadata_model else None
            )
            if preview_metadata_model:
                preview_metadata = preview_metadata_model.to_payload()
                playlist_preview: Optional[PlaylistMetadataPayload] = None
                if preview_metadata_model.playlist is not None:
                    playlist_preview = preview_metadata_model.playlist.to_payload()
                    preview_metadata["playlist"] = playlist_preview
                else:
                    playlist_preview_raw = preview_metadata.get("playlist")
                    if isinstance(playlist_preview_raw, dict):
                        playlist_preview = cast(
                            PlaylistMetadataPayload,
                            dict(playlist_preview_raw),
                        )
                        preview_metadata["playlist"] = playlist_preview
                if isinstance(playlist_preview, dict):
                    entries_meta = playlist_preview.get("entries")
                    entries_len: Optional[int] = None
                    if isinstance(entries_meta, Sequence) and not isinstance(
                        entries_meta, (str, bytes)
                    ):
                        entries_len = len(entries_meta)
                    if "received_count" not in playlist_preview:
                        playlist_preview["received_count"] = entries_len or 0
                    if collecting_entries:
                        playlist_preview["is_collecting_entries"] = True
                        playlist_preview["collection_complete"] = False
                    else:
                        playlist_preview["is_collecting_entries"] = False
                        playlist_preview.setdefault("collection_complete", True)
                    if total_count_hint is not None:
                        playlist_preview.setdefault("entry_count", total_count_hint)
                        playlist_preview.setdefault("total_items", total_count_hint)
                        playlist_preview["has_indefinite_length"] = False
                    else:
                        total_value = to_int(
                            playlist_preview.get("total_items")
                            or playlist_preview.get("entry_count")
                        )
                        if total_value is not None and total_value > 0:
                            playlist_preview.setdefault("total_items", total_value)
                            playlist_preview.setdefault("entry_count", total_value)
                            playlist_preview.setdefault("has_indefinite_length", False)
                        else:
                            playlist_preview.setdefault("has_indefinite_length", True)
                    thumbnail_fallback = preview_metadata.get("thumbnail_url")
                    if thumbnail_fallback and not playlist_preview.get("thumbnail_url"):
                        playlist_preview["thumbnail_url"] = thumbnail_fallback
                    title_fallback = preview_metadata.get("title")
                    if title_fallback and not playlist_preview.get("title"):
                        playlist_preview["title"] = title_fallback
                _, collecting_state = self._apply_preview_metadata(
                    job_id,
                    preview_metadata,
                    preview_model=preview_metadata_model,
                    playlist_model=playlist_model_from_preview,
                )
                if collecting_entries:
                    collecting_state = True
                if not collecting_state:
                    self._mark_preview_ready(job_id)
                    preview_ready_marked = True

            if entries_source is not None:
                for entry_payload in self._yield_preview_entries(entries_source):
                    collected_entries.append(entry_payload)
                    self._record_preview_entries(
                        job_id,
                        collected_entries,
                        total_count_hint=total_count_hint,
                        latest_entry=entry_payload,
                    )
        except Exception as exc:
            error_message = self._handle_preview_exception(job_id, exc)
            if not preview_ready_marked:
                self._mark_preview_ready(job_id)
                preview_ready_marked = True
            self._complete_playlist_collection_stream(
                job_id,
                entries=[
                    cast(PlaylistEntryPayload, dict(entry))
                    for entry in collected_entries
                ],
                total_count=total_count_hint,
                error=error_message,
            )
            return
        else:
            if collected_entries:
                metadata_entries = [
                    cast(PlaylistEntryMetadataPayload, dict(entry))
                    for entry in collected_entries
                ]
                playlist_payload: PlaylistMetadataPayload = {
                    "entries": metadata_entries,
                }
                if total_count_hint is not None:
                    playlist_payload["entry_count"] = total_count_hint
                    playlist_payload["total_items"] = total_count_hint
                else:
                    playlist_payload.setdefault("entry_count", len(collected_entries))
                    playlist_payload.setdefault("total_items", len(collected_entries))
                playlist_payload["received_count"] = len(collected_entries)
                playlist_payload["is_collecting_entries"] = False
                playlist_payload["collection_complete"] = True
                playlist_payload["has_indefinite_length"] = total_count_hint is None
                playlist_model = PlaylistMetadata.from_payload(playlist_payload)
                final_metadata: PreviewMetadataPayload = {
                    "playlist": cast(
                        PlaylistMetadataPayload,
                        dict(playlist_payload),
                    )
                }
                self._apply_preview_metadata(
                    job_id,
                    final_metadata,
                    playlist_model=playlist_model,
                )
                self._emit_playlist_snapshot(job_id)
                manager_instance = self._preview_manager()
                persist_fn = getattr(manager_instance, "_persist_jobs", None)
                if callable(persist_fn):
                    persist_fn()
                completed_total = (
                    total_count_hint
                    if total_count_hint is not None
                    else len(collected_entries)
                )
                self._complete_playlist_collection_stream(
                    job_id,
                    entries=[
                        cast(PlaylistEntryPayload, dict(entry))
                        for entry in collected_entries
                    ],
                    total_count=completed_total,
                    error=None,
                )
            elif collecting_entries:
                self._complete_playlist_collection_stream(
                    job_id,
                    entries=[],
                    total_count=total_count_hint,
                    error=None,
                )
            if not preview_ready_marked:
                self._mark_preview_ready(job_id)
                preview_ready_marked = True

    def _yield_preview_entries(
        self,
        raw_entries: EntrySource,
    ) -> Iterable[PlaylistEntryPayload]:
        for index, entry_mapping in enumerate(
            self._iter_playlist_entries_source(raw_entries),
            start=1,
        ):
            entry_info = Info.fast_info(entry_mapping)
            entry_payload = self._build_playlist_entry_from_info(entry_info, index)
            if entry_payload:
                yield cast(PlaylistEntryPayload, entry_payload.to_payload())

    def _iter_playlist_entries_source(
        self,
        entries_source: EntrySource,
    ) -> Iterable[YtDlpInfoResult]:
        return entries_source

    def _coerce_entry_source(
        self, raw_entries: object
    ) -> tuple[Optional[EntrySource], bool]:
        if isinstance(raw_entries, Sequence) and not isinstance(
            raw_entries, (str, bytes, bytearray)
        ):
            sanitized: List[YtDlpInfoResult] = []
            entries_seq = cast(Sequence[object], raw_entries)
            for entry in entries_seq:
                entry_dict = self._coerce_info_entry(entry)
                if entry_dict is not None:
                    sanitized.append(entry_dict)
            return sanitized, len(sanitized) > 0
        if isinstance(raw_entries, Iterable) and not isinstance(
            raw_entries, (str, bytes, bytearray)
        ):
            iterable_entries = cast(Iterable[object], raw_entries)

            def _iterator() -> Iterable[YtDlpInfoResult]:
                for entry in iterable_entries:
                    entry_dict = self._coerce_info_entry(entry)
                    if entry_dict is not None:
                        yield entry_dict

            return _iterator(), True
        return None, False

    @staticmethod
    def _coerce_info_entry(value: object) -> Optional[YtDlpInfoResult]:
        if not isinstance(value, Mapping):
            return None
        mapping_value = cast(Mapping[str, JSONValue], value)
        return cast(YtDlpInfoResult, dict(mapping_value))

    def _record_preview_entries(
        self,
        job_id: str,
        entries: Sequence[PlaylistEntryPayload],
        *,
        total_count_hint: Optional[int],
        latest_entry: Optional[PlaylistEntryPayload],
    ) -> None:
        """Persist streamed playlist entries and emit progressive updates."""
        progress_payload: Optional[DownloadJobProgressPayload] = None
        manager = self._preview_manager()
        with manager.lock:
            job = manager.jobs.get(job_id)
            if not job:
                return
            base_metadata: DownloadJobMetadataPayload = job.metadata or {}
            updated_metadata = cast(
                DownloadJobMetadataPayload,
                dict(base_metadata),
            )
            playlist_meta = updated_metadata.get("playlist")
            if isinstance(playlist_meta, dict):
                playlist_payload = cast(PlaylistMetadataPayload, playlist_meta)
            else:
                playlist_payload = cast(PlaylistMetadataPayload, {})
                updated_metadata["playlist"] = playlist_payload
            metadata_entries_raw = playlist_payload.get("entries")
            if isinstance(metadata_entries_raw, list):
                metadata_entries = cast(
                    List[PlaylistEntryMetadataPayload], metadata_entries_raw
                )
            else:
                metadata_entries = []
                playlist_payload["entries"] = metadata_entries
            current_count = len(metadata_entries)
            requested_count = len(entries)
            if current_count > requested_count:
                del metadata_entries[requested_count:]
                current_count = requested_count
            if requested_count > current_count:
                for index in range(current_count, requested_count):
                    metadata_entries.append(
                        cast(PlaylistEntryMetadataPayload, dict(entries[index]))
                    )
            if total_count_hint is not None:
                playlist_payload.setdefault("entry_count", total_count_hint)
                playlist_payload.setdefault("total_items", total_count_hint)
                job.playlist_total_items = total_count_hint
            else:
                inferred_total = to_int(
                    playlist_payload.get("entry_count")
                    or playlist_payload.get("total_items")
                    or getattr(job, "playlist_total_items", None)
                )
                if inferred_total is not None and inferred_total > 0:
                    playlist_payload.setdefault("entry_count", inferred_total)
                    playlist_payload.setdefault("total_items", inferred_total)
                    job.playlist_total_items = inferred_total
            received_count = len(metadata_entries)
            playlist_payload["is_collecting_entries"] = True
            playlist_payload["collection_complete"] = False
            playlist_payload.pop("collection_error", None)
            playlist_payload["received_count"] = received_count
            total_items_value = to_int(
                playlist_payload.get("total_items")
                or playlist_payload.get("entry_count")
                or getattr(job, "playlist_total_items", None)
            )
            if total_items_value is not None and total_items_value > 0:
                playlist_payload["has_indefinite_length"] = False
            else:
                playlist_payload["has_indefinite_length"] = True
            stage_percent: Optional[float] = None
            if total_items_value is not None and total_items_value > 0:
                stage_percent = min(
                    (received_count / float(total_items_value)) * 100.0,
                    100.0,
                )
            message_text: Optional[str] = None
            if total_items_value is not None and total_items_value > 0:
                message_text = (
                    f"Recibidos {received_count} de {total_items_value} elementos"
                )
            elif received_count > 0:
                message_text = f"{received_count} elementos recibidos"

            metadata_store_playlist_model(updated_metadata, None)
            job.metadata = updated_metadata

            job_status = job.status or JobStatus.STARTING.value
            progress_payload = DownloadJobProgressPayload(
                status=job_status,
                stage=DownloadStage.WAIT_FOR_ELEMENTS.value,
                stage_name="Esperando elementos",
            )
            if stage_percent is not None:
                progress_payload["stage_percent"] = stage_percent
            if received_count > 0:
                progress_payload["current_item"] = received_count
            if total_items_value is not None and total_items_value > 0:
                progress_payload["total_items"] = total_items_value
                progress_payload["playlist_total_items"] = total_items_value
            if message_text:
                progress_payload["message"] = message_text
        if latest_entry:
            entry_payload = cast(PlaylistEntryPayload, dict(latest_entry))
            entry_summary = self._build_playlist_entry_summary(entry_payload)
            payload = EntryInfoPayload(
                job_id=job_id,
                entry=entry_summary,
                received_count=received_count,
                index=entry_summary.index,
                entry_count=total_count_hint,
                timestamp=now_iso(),
            )
            self._emit_playlist_entry_info(payload)
        if progress_payload:
            self._store_progress_payload(job_id, progress_payload)

    def _emit_playlist_entry_info(self, payload: EntryInfoPayload) -> None:
        manager = self._preview_manager()
        serialized = payload.to_dict()
        json_payload = cast(JSONValue, serialized)
        self._emit_socket_event(
            SocketEvent.ENTRY_INFO.value,
            json_payload,
            room=manager.job_room(payload.job_id),
        )
        self._emit_socket_event(
            SocketEvent.PLAYLIST_PREVIEW_ENTRY.value,
            json_payload,
            room=manager.job_room(payload.job_id),
        )

    def _complete_playlist_collection_stream(
        self,
        job_id: str,
        *,
        entries: Sequence[PlaylistEntryPayload],
        total_count: Optional[int],
        error: Optional[str],
    ) -> None:
        entries_snapshot = [
            cast(PlaylistEntryPayload, dict(entry)) for entry in entries
        ]
        entries_len = len(entries_snapshot)
        collection_error_message = error
        if collection_error_message is None and entries_len == 0:
            collection_error_message = (
                "La lista no devolvió elementos para seleccionar."
            )
        manager = self._preview_manager()
        with manager.lock:
            job = manager.jobs.get(job_id)
            if job:
                metadata = cast(
                    DownloadJobMetadataPayload,
                    dict(job.metadata or {}),
                )
                playlist_model = (
                    metadata_get_playlist_model(metadata) or PlaylistMetadata()
                )
                playlist_model.is_collecting_entries = False
                playlist_model.collection_complete = True
                playlist_model.received_count = entries_len
                if total_count is not None and total_count > 0:
                    playlist_model.entry_count = total_count
                    playlist_model.total_items = total_count
                    playlist_model.has_indefinite_length = False
                    job.playlist_total_items = total_count
                else:
                    if playlist_model.entry_count is None:
                        playlist_model.entry_count = entries_len
                    if playlist_model.total_items is None:
                        playlist_model.total_items = entries_len
                    playlist_model.has_indefinite_length = True
                if collection_error_message:
                    playlist_model.collection_error = collection_error_message
                else:
                    playlist_model.collection_error = None
                metadata_store_playlist_model(metadata, playlist_model)
                if collection_error_message:
                    metadata["requires_playlist_selection"] = False
                    job.selection_required = False
                    selection_event = getattr(job, "selection_event", None)
                    if isinstance(selection_event, threading.Event):
                        selection_event.set()
                job.metadata = metadata
        self._emit_playlist_collection_complete(
            job_id,
            entries=entries_snapshot,
            total_count=total_count,
            error=collection_error_message,
        )

    def _emit_playlist_collection_complete(
        self,
        job_id: str,
        *,
        entries: Sequence[PlaylistEntryPayload],
        total_count: Optional[int],
        error: Optional[str] = None,
    ) -> None:
        """Notify listeners that playlist entry enumeration has finished."""

        entry_summaries = [
            self._build_playlist_entry_summary(entry) for entry in entries
        ]
        final_count = total_count if total_count is not None else len(entry_summaries)
        payload = ListInfoEndsPayload(
            job_id=job_id,
            entries=entry_summaries,
            entry_count=final_count,
            error=error,
            timestamp=now_iso(),
        )
        manager = self._preview_manager()
        serialized = payload.to_dict()
        json_payload = cast(JSONValue, serialized)
        self._emit_socket_event(
            SocketEvent.LIST_INFO_ENDS.value,
            json_payload,
            room=manager.job_room(job_id),
        )

    @staticmethod
    def _clean_string(value: JSONValue) -> Optional[str]:
        if isinstance(value, str):
            trimmed = value.strip()
            return trimmed or None
        return None

    def _best_thumbnail_from_models(
        self,
        thumbnails: Sequence[Thumbnail],
    ) -> Optional[str]:
        best_candidate: Optional[str] = None
        highest_resolution = -1
        for thumb in thumbnails:
            url = thumb.url.strip() if thumb.url else ""
            if not url:
                continue
            width = thumb.width or 0
            height = thumb.height or 0
            resolution = width * height
            if resolution > highest_resolution:
                highest_resolution = resolution
                best_candidate = url
        return best_candidate

    def _build_preview_summary(
        self,
        data: Optional[PreviewMetadataPayload],
    ) -> Optional[PreviewSummary]:
        if not data:
            return None
        summary = PreviewSummary.from_payload(data)
        if summary.thumbnails and not summary.thumbnail_url:
            summary.thumbnail_url = self._best_thumbnail_from_models(summary.thumbnails)
        return summary if summary.has_data() else None

    def _build_playlist_summary(
        self,
        playlist_meta: Optional[PlaylistMetadataPayload],
        job: DownloadJob,
    ) -> Optional[PlaylistSummary]:
        if not playlist_meta:
            return None
        summary = PlaylistSummary.from_payload(playlist_meta)
        if summary.entries and not summary.entry_count:
            summary.entry_count = len(summary.entries)
        selected_indices = sorted(self._resolve_selected_playlist_indices(job))
        summary.selected_indices = selected_indices
        if summary.thumbnails and not summary.thumbnail_url:
            summary.thumbnail_url = self._best_thumbnail_from_models(summary.thumbnails)
        return summary if summary.has_data() else None

    def _build_playlist_entry_summary(
        self,
        entry: PlaylistEntryPayload,
    ) -> PlaylistEntrySummary:
        summary = PlaylistEntrySummary.from_payload(entry)
        preview = summary.preview
        if preview:
            if preview.thumbnails and not summary.thumbnails:
                summary.thumbnails = list(preview.thumbnails)
            if preview.thumbnail_url and not summary.thumbnail_url:
                summary.thumbnail_url = preview.thumbnail_url
        if summary.thumbnails and not summary.thumbnail_url:
            summary.thumbnail_url = self._best_thumbnail_from_models(summary.thumbnails)
        return summary

    def _build_global_info_payload(
        self,
        job: DownloadJob,
    ) -> GlobalInfoPayload:
        metadata: DownloadJobMetadataPayload = job.metadata or {}
        preview_payload = self._build_preview_payload(job)
        preview_summary = self._build_preview_summary(preview_payload)
        playlist_meta = metadata.get("playlist")
        playlist_payload = playlist_meta if isinstance(playlist_meta, dict) else None
        playlist_summary = self._build_playlist_summary(playlist_payload, job)
        is_playlist_flag = to_bool(metadata.get("is_playlist"))
        is_playlist = (
            bool(is_playlist_flag)
            if is_playlist_flag is not None
            else bool(playlist_summary)
        )
        kind_value = job.kind or None
        total_items = (
            job.playlist_total_items
            if isinstance(job.playlist_total_items, int)
            and job.playlist_total_items > 0
            else None
        )
        return GlobalInfoPayload(
            job_id=job.job_id,
            status=job.status,
            kind=kind_value,
            is_playlist=is_playlist,
            selection_required=bool(job.selection_required),
            preview=preview_summary,
            playlist=playlist_summary,
            playlist_total_items=total_items,
            timestamp=now_iso(),
        )

    def _emit_global_info_payload(self, payload: GlobalInfoPayload) -> None:
        manager = self._preview_manager()
        serialized = payload.to_dict()
        json_payload = cast(JSONValue, serialized)
        self._emit_socket_event(
            SocketEvent.GLOBAL_INFO.value,
            json_payload,
            room=manager.job_room(payload.job_id),
        )

    def _emit_playlist_snapshot(self, job_id: str) -> None:
        manager = self._preview_manager()
        snapshot = manager.build_playlist_snapshot(
            job_id,
            include_entries=True,
            include_entry_progress=False,
        )
        if not snapshot:
            return
        payload_value = clone_json_value(cast(JSONValue, snapshot))
        if not isinstance(payload_value, dict):
            return
        payload = cast(PlaylistSnapshotPayload, payload_value)
        payload.setdefault("timestamp", now_iso())
        payload_json = cast(JSONValue, payload)
        self._emit_socket_event(
            SocketEvent.PLAYLIST_SNAPSHOT.value,
            payload_json,
            room=manager.job_room(job_id),
        )

    def _apply_preview_metadata(
        self,
        job_id: str,
        preview_metadata: PreviewMetadataPayload,
        *,
        preview_model: Optional[PreviewMetadata] = None,
        playlist_model: Optional[PlaylistMetadata] = None,
    ) -> Tuple[bool, bool]:
        """Merge preview metadata into the job and detect playlist selection.

        Updates job metadata, toggles ``selection_required`` when a playlist has
        multiple entries without a predefined filter, emits progress/log events
        for the WAIT_FOR_SELECTION stage, and returns whether selection is still
        pending plus the current collecting state.
        """
        payload: Optional[SerializedJobPayload] = None
        progress_payload: Optional[DownloadJobProgressPayload] = None
        should_log_waiting = False
        should_log_resume = False
        persist_required = False
        collecting_state = False
        manager = self._preview_manager()
        kind_changed = False
        selection_state = False
        global_info_payload: Optional[GlobalInfoPayload] = None
        sync_entries_required = False
        metadata_snapshot: Optional[DownloadJobMetadataPayload] = None
        with manager.lock:
            job = manager.jobs.get(job_id)
            if not job:
                return False, False
            base_metadata: DownloadJobMetadataPayload = job.metadata or {}
            updated_metadata = cast(
                DownloadJobMetadataPayload,
                dict(base_metadata),
            )
            selected_indices_tracked = self._resolve_selected_playlist_indices(job)
            suppress_playlist_entries = bool(selected_indices_tracked)
            changed = self._merge_preview_metadata_dict(
                updated_metadata,
                preview_metadata,
                preview_model=preview_model,
                playlist_model=playlist_model,
                suppress_playlist_entries=suppress_playlist_entries,
                selected_indices=selected_indices_tracked,
            )
            previous_required = getattr(job, "selection_required", False)
            selection_hint = self._requires_playlist_selection(job, preview_metadata)
            selection_event = getattr(job, "selection_event", None)
            waiting_selection = (
                previous_required
                and not selection_hint
                and isinstance(selection_event, threading.Event)
                and not selection_event.is_set()
            )
            selection_required = selection_hint or waiting_selection
            selection_changed = selection_required != previous_required
            job.selection_required = selection_required
            if selection_required:
                job.selection_event.clear()
                if updated_metadata.get("requires_playlist_selection") is not True:
                    updated_metadata["requires_playlist_selection"] = True
                    changed = True
                if not previous_required:
                    should_log_waiting = True
                if selection_changed:
                    persist_required = True
            else:
                removed_hint = updated_metadata.pop("requires_playlist_selection", None)
                if removed_hint is not None:
                    changed = True
                job.selection_event.set()
                if previous_required:
                    should_log_resume = True
                    persist_required = True
            job.metadata = updated_metadata
            if changed:
                persist_required = True

            entries_ready = False
            playlist_candidate = updated_metadata.get("playlist")
            if isinstance(playlist_candidate, dict):
                entries_value = playlist_candidate.get("entries")
                has_entries = isinstance(entries_value, list) and bool(entries_value)
                collecting_flag = to_bool(
                    playlist_candidate.get("is_collecting_entries")
                )
                collection_complete_flag = to_bool(
                    playlist_candidate.get("collection_complete")
                )
                collecting_state_flag = (
                    bool(collecting_flag) if collecting_flag is not None else False
                )
                if collection_complete_flag is True:
                    collecting_state_flag = False
                entries_ready = has_entries and not collecting_state_flag
            if entries_ready:
                safe_metadata_fn = cast(
                    Optional[MetadataSanitizer],
                    getattr(manager, "_safe_metadata_payload", None),
                )
                if safe_metadata_fn is not None:
                    metadata_snapshot = safe_metadata_fn(updated_metadata)
                else:
                    metadata_snapshot = cast(
                        DownloadJobMetadataPayload,
                        dict(updated_metadata),
                    )
                sync_entries_required = True

            playlist_meta: Optional[PlaylistMetadataPayload] = None
            playlist_model_resolved = metadata_get_playlist_model(updated_metadata)
            if playlist_model_resolved is not None:
                collecting_flag = playlist_model_resolved.is_collecting_entries
                if collecting_flag is None:
                    collecting_state = False
                else:
                    collecting_state = bool(collecting_flag)
                if playlist_model_resolved.collection_complete is True:
                    collecting_state = False
                elif playlist_model_resolved.collection_complete is False:
                    collecting_state = True
            else:
                playlist_meta_candidate = updated_metadata.get("playlist")
                if isinstance(playlist_meta_candidate, dict):
                    playlist_meta = playlist_meta_candidate
                    flag = to_bool(playlist_meta.get("is_collecting_entries"))
                    collecting_state = bool(flag) if flag is not None else False
                    completion_flag = to_bool(playlist_meta.get("collection_complete"))
                    if completion_flag is True:
                        collecting_state = False
                    elif completion_flag is False:
                        collecting_state = True
                else:
                    playlist_meta = None

            kind_updater = getattr(manager, "_update_job_kind_from_preview", None)
            if callable(kind_updater):
                kind_changed = bool(kind_updater(job, preview_metadata))
                if kind_changed:
                    persist_required = True

            selection_state = job.selection_required
            if not changed and not selection_changed and not kind_changed:
                return selection_state, collecting_state
            if playlist_model_resolved is not None:
                total_items = (
                    playlist_model_resolved.entry_count
                    or playlist_model_resolved.total_items
                )
                if total_items is not None and total_items > 0:
                    job.playlist_total_items = total_items
            elif isinstance(playlist_meta, dict):
                total_items_hint = to_int(playlist_meta.get("entry_count")) or to_int(
                    playlist_meta.get("total_items")
                )
                if total_items_hint is not None and total_items_hint > 0:
                    job.playlist_total_items = total_items_hint
            payload = manager.serialize_job(job, detail=True)
            global_info_payload = self._build_global_info_payload(job)
            if selection_required and not collecting_state:
                progress_payload = DownloadJobProgressPayload(
                    status=JobStatus.STARTING.value,
                    stage=DownloadStage.WAIT_FOR_SELECTION.value,
                    stage_name="Esperando selección",
                    stage_percent=0.0,
                    percent=0.0,
                    message="Esperando la selección de elementos de la lista de reproducción",
                )
            elif previous_required and not selection_required:
                progress_payload = DownloadJobProgressPayload(
                    status=JobStatus.STARTING.value,
                    stage="starting",
                    message="Preparando descarga",
                )
        if not payload:
            if persist_required:
                persist_fn = getattr(manager, "_persist_jobs", None)
                if callable(persist_fn):
                    persist_fn()
            return selection_state, collecting_state
        if should_log_waiting:
            manager.append_log(
                job_id,
                "info",
                "Esperando la selección de elementos de la lista de reproducción",
            )
        elif should_log_resume:
            manager.append_log(
                job_id,
                "info",
                "Selección de la lista de reproducción recibida",
            )
        verbose_log(
            "preview_metadata_applied",
            {
                "job_id": job_id,
                "title": preview_metadata.get("title"),
                "thumbnail": preview_metadata.get("thumbnail_url"),
            },
        )
        payload["reason"] = "preview_ready"
        manager.broadcast_update(payload)
        manager.emit_overview()
        if global_info_payload:
            self._emit_global_info_payload(global_info_payload)
        if progress_payload:
            self._store_progress_payload(job_id, progress_payload)
        if persist_required:
            persist_fn = getattr(manager, "_persist_jobs", None)
            if callable(persist_fn):
                persist_fn()
        if sync_entries_required:
            sync_fn = getattr(manager, "_sync_playlist_entries", None)
            if callable(sync_fn):
                sync_fn(job_id, metadata_snapshot=metadata_snapshot)
        return selection_state, collecting_state

    def _mark_preview_ready(self, job_id: str) -> None:
        manager = self._preview_manager()
        kind_changed = False
        with manager.lock:
            job = manager.jobs.get(job_id)
            if not job:
                return
            ensure_kind = getattr(manager, "_ensure_job_kind_locked", None)
            if callable(ensure_kind):
                kind_changed = bool(ensure_kind(job))
            event = getattr(job, "preview_ready_event", None)
            if isinstance(event, threading.Event):
                event.set()
        if kind_changed:
            manager.emit_job_update(job_id, reason=JobUpdateReason.UPDATED.value)
            manager.emit_overview()
            persist_fn = getattr(manager, "_persist_jobs", None)
            if callable(persist_fn):
                persist_fn()

    def _register_preview_error(self, job_id: str, message: str) -> bool:
        manager = self._preview_manager()
        updated = False
        with manager.lock:
            job = manager.jobs.get(job_id)
            if not job:
                return False
            previous = getattr(job, "preview_error", None)
            job.preview_error = message
            job.error = message
            updated = previous != message
        return updated

    def _handle_preview_exception(self, job_id: str, exc: Exception) -> str:
        message = strip_ansi(str(exc)) or repr(exc)
        friendly = f"No se pudo generar la vista previa: {message}"
        manager = self._preview_manager()
        append_log = getattr(manager, "append_log", None)
        if callable(append_log):
            append_log(job_id, "error", friendly)
        if self._register_preview_error(job_id, friendly):
            manager.emit_job_update(job_id, reason=JobUpdateReason.UPDATED.value)
            manager.emit_overview()
        return friendly

    def _requires_playlist_selection(
        self,
        job: DownloadJob,
        preview_metadata: PreviewMetadataPayload,
    ) -> bool:
        """Determine if the user must choose specific playlist entries."""
        if not preview_metadata:
            return False
        playlist_payload = preview_metadata.get("playlist")
        if not isinstance(playlist_payload, dict):
            return False

        entries_value = playlist_payload.get("entries")
        entries_count: Optional[int] = None
        if isinstance(entries_value, Sequence) and not isinstance(
            entries_value, (str, bytes)
        ):
            entries_count = len(entries_value)

        received_count = to_int(playlist_payload.get("received_count"))
        if received_count is not None and received_count < 0:
            received_count = 0

        entry_refs_value = playlist_payload.get("entry_refs")
        if (
            entries_count is None
            and isinstance(entry_refs_value, Sequence)
            and not isinstance(entry_refs_value, (str, bytes))
        ):
            entries_count = len(entry_refs_value)

        total_items_hint = to_int(playlist_payload.get("entry_count")) or to_int(
            playlist_payload.get("total_items")
        )
        preview_entry_count_hint = to_int(preview_metadata.get("playlist_entry_count"))
        job_total_items = to_int(getattr(job, "playlist_total_items", None))

        entries_candidates = (
            entries_count,
            received_count,
            total_items_hint,
            preview_entry_count_hint,
            job_total_items,
        )

        actual_count: Optional[int] = None
        for candidate in entries_candidates:
            if candidate is None:
                continue
            candidate = max(candidate, 0)
            if actual_count is None or candidate > actual_count:
                actual_count = candidate

        collecting_flag = to_bool(playlist_payload.get("is_collecting_entries"))
        collecting_entries = (
            bool(collecting_flag) if collecting_flag is not None else False
        )
        completion_flag = to_bool(playlist_payload.get("collection_complete"))
        if completion_flag is True:
            collecting_entries = False
        elif completion_flag is False:
            collecting_entries = True
        playlist_flag = to_bool(preview_metadata.get("is_playlist"))
        playlist_identified = bool(
            playlist_payload.get("playlist_id") or playlist_payload.get("id")
        )
        playlist_named = bool(playlist_payload.get("title"))

        if (
            (actual_count is None or actual_count <= 1)
            and collecting_entries
            and (playlist_flag is True or playlist_identified or playlist_named)
        ):
            fallback_count = 0
            for candidate in entries_candidates:
                if candidate is None:
                    continue
                fallback_count = max(fallback_count, candidate)
            if fallback_count <= 1:
                fallback_count = 2
            actual_count = fallback_count

        if actual_count is None:
            return False
        if actual_count <= 1:
            return False

        options: DownloadJobOptionsPayload = job.options or {}
        playlist_items = options.get("playlist_items")
        if isinstance(playlist_items, str) and playlist_items.strip():
            return False
        if playlist_items:
            return False
        return True

    def _merge_preview_metadata_dict(
        self,
        metadata: DownloadJobMetadataPayload,
        preview_metadata: PreviewMetadataPayload,
        *,
        preview_model: Optional[PreviewMetadata] = None,
        playlist_model: Optional[PlaylistMetadata] = None,
        suppress_playlist_entries: bool = False,
        selected_indices: Optional[Set[int]] = None,
    ) -> bool:
        if not preview_metadata:
            return False

        changed = False

        existing_preview = metadata.get("preview")
        if isinstance(existing_preview, dict):
            merged_preview = cast(
                PreviewMetadataPayload,
                dict(existing_preview),
            )
            merged_preview.update(preview_metadata)
        else:
            merged_preview = cast(PreviewMetadataPayload, dict(preview_metadata))
        if existing_preview != merged_preview:
            metadata["preview"] = merged_preview
            changed = True
        if merged_preview:
            if preview_model is None:
                preview_model = PreviewMetadata.from_payload(merged_preview)
            metadata_store_preview_model(metadata, preview_model)

        playlist_payload = preview_metadata.get("playlist")
        if isinstance(playlist_payload, dict):
            playlist_payload = cast(PlaylistMetadataPayload, dict(playlist_payload))
            if suppress_playlist_entries:
                playlist_payload.pop("entries", None)
            existing_playlist = metadata.get("playlist")
            if isinstance(existing_playlist, dict):
                merged_playlist = cast(
                    PlaylistMetadataPayload,
                    dict(existing_playlist),
                )
                merged_playlist.update(playlist_payload)
                if merged_playlist != existing_playlist:
                    metadata["playlist"] = merged_playlist
                    changed = True
            else:
                metadata["playlist"] = cast(
                    PlaylistMetadataPayload,
                    dict(playlist_payload),
                )
                changed = True
            playlist_payload_current = metadata.get("playlist")
            if isinstance(playlist_payload_current, dict):
                if playlist_model is None:
                    playlist_model = PlaylistMetadata.from_payload(
                        playlist_payload_current
                    )
                metadata_store_playlist_model(metadata, playlist_model)
            if "is_playlist" not in metadata:
                metadata["is_playlist"] = True
                changed = True
            playlist_id_value = playlist_payload.get("id")
            if isinstance(playlist_id_value, str):
                normalized_id = playlist_id_value.strip()
                if normalized_id and "playlist_id" not in metadata:
                    metadata["playlist_id"] = normalized_id
                    changed = True
            entry_count_value = playlist_payload.get("entry_count")
            if entry_count_value is not None and "playlist_entry_count" not in metadata:
                metadata["playlist_entry_count"] = entry_count_value
                changed = True
            title_value = playlist_payload.get("title")
            if isinstance(title_value, str):
                normalized_title = title_value.strip()
                if normalized_title and "playlist_title" not in metadata:
                    metadata["playlist_title"] = normalized_title
                    changed = True

            if suppress_playlist_entries:
                playlist_meta_current = metadata.get("playlist")
                if isinstance(playlist_meta_current, dict):
                    entries_raw: object | None = playlist_meta_current.get("entries")
                    if isinstance(entries_raw, list):
                        entries_value = cast(List[object], entries_raw)
                        selected_set = set(selected_indices or ())
                        filtered_entries: List[PlaylistEntryMetadataPayload] = []
                        for entry in entries_value:
                            entry_candidate: object = entry
                            if not isinstance(entry_candidate, Mapping):
                                continue
                            entry_mapping = cast(
                                Mapping[str, JSONValue], entry_candidate
                            )
                            index_value = to_int(entry_mapping.get("index"))
                            if selected_set and index_value not in selected_set:
                                continue
                            filtered_entries.append(
                                cast(PlaylistEntryMetadataPayload, dict(entry_mapping))
                            )
                        if filtered_entries:
                            if len(filtered_entries) != len(entries_value):
                                playlist_meta_current["entries"] = filtered_entries
                                changed = True
                        else:
                            playlist_meta_current.pop("entries", None)
                            changed = True

        for key in (
            "title",
            "description",
            "thumbnail_url",
            "webpage_url",
            "original_url",
        ):
            value = preview_metadata.get(key)
            if isinstance(value, str):
                trimmed = value.strip()
                if trimmed and key not in metadata:
                    metadata[key] = trimmed
                    changed = True

        if "preview_collected_at" not in metadata:
            collected_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            metadata["preview_collected_at"] = collected_at
            changed = True

        return changed

    def _collect_preview_metadata(
        self,
        urls: List[str],
        options: Optional[DownloadJobOptionsPayload],
    ) -> Optional[PreviewMetadataPayload]:
        if not urls:
            return None
        try:
            core = self._core_manager()
            options_config = build_options_config(options)
            result = core.extract_info(
                urls,
                options=options_config,
                download=False,
            )
        except Exception as exc:  # noqa: BLE001 - propagate best effort metadata issues only via logs
            verbose_log(
                "preview_metadata_error",
                {
                    "urls": urls,
                    "error": repr(exc),
                },
            )
            return None

        preview = self._build_preview_from_info(result)
        if preview:
            payload = preview.to_payload()
            verbose_log(
                "preview_metadata",
                {
                    "url": urls[0],
                    "title": payload.get("title"),
                    "thumbnail_url": payload.get("thumbnail_url"),
                },
            )
            return payload
        return None

    def _build_preview_payload(
        self,
        job: DownloadJob,
    ) -> Optional[PreviewMetadataPayload]:
        metadata: DownloadJobMetadataPayload = job.metadata or {}
        preview_model = metadata_get_preview_model(metadata, clone=True)
        if preview_model:
            payload = preview_model.to_payload()
            collected_at = metadata.get("preview_collected_at")
            if isinstance(collected_at, str) and collected_at.strip():
                payload.setdefault("collected_at", collected_at.strip())
            return payload
        preview_source: Optional[PreviewMetadataPayload] = None
        candidate = metadata.get("preview")
        if isinstance(candidate, dict):
            preview_source = candidate
        if preview_source is None:
            fallback: PreviewMetadataPayload = {}
            for key in (
                "title",
                "description",
                "thumbnail_url",
                "webpage_url",
                "original_url",
            ):
                value = metadata.get(key)
                if isinstance(value, str) and value.strip():
                    fallback[key] = value.strip()
            if fallback:
                preview_source = fallback
        if not preview_source:
            return None
        normalized = self._normalize_preview_payload(preview_source)
        if not normalized:
            return None
        collected_at = metadata.get("preview_collected_at")
        if isinstance(collected_at, str) and collected_at.strip():
            normalized.setdefault("collected_at", collected_at.strip())
        return normalized

    def _normalize_preview_payload(
        self,
        preview: PreviewMetadataPayload,
    ) -> Optional[PreviewMetadataPayload]:
        sanitized: Dict[str, JSONValue] = {}

        def _assign_string(key: str, source_key: Optional[str] = None) -> None:
            lookup = source_key or key
            value = preview.get(lookup)
            if isinstance(value, str):
                trimmed = value.strip()
                if trimmed:
                    sanitized[key] = trimmed

        for key in (
            "title",
            "description",
            "webpage_url",
            "original_url",
            "duration_text",
            "thumbnail_url",
            "uploader",
            "channel",
            "upload_date_iso",
            "extractor",
            "extractor_id",
            "entry_id",
        ):
            _assign_string(key)

        if "thumbnail_url" not in sanitized:
            _assign_string("thumbnail_url", "thumbnail")

        for key in ("duration_seconds", "view_count", "like_count"):
            value = to_int(preview.get(key))
            if value is not None and value >= 0:
                sanitized[key] = value

        tags_value = preview.get("tags")
        if isinstance(tags_value, list):
            tags_raw = cast(Sequence[JSONValue], tags_value)
            tags: List[str] = []
            for tag in tags_raw:
                if isinstance(tag, str):
                    trimmed = tag.strip()
                    if trimmed:
                        tags.append(trimmed)
            if tags:
                sanitized["tags"] = list(tags[:25])

        thumbnails_value = _coerce_thumbnail_sequence(preview.get("thumbnails"))
        thumbnails = self._normalize_thumbnail_list(thumbnails_value)
        if thumbnails:
            thumb_payloads: List[PreviewThumbnailPayload] = [
                cast(PreviewThumbnailPayload, dict(entry)) for entry in thumbnails
            ]
            sanitized["thumbnails"] = cast(JSONValue, thumb_payloads)
            best_thumbnail = self._select_best_thumbnail_url(thumbnails)
            if best_thumbnail and "thumbnail_url" not in sanitized:
                sanitized["thumbnail_url"] = best_thumbnail

        is_playlist = preview.get("is_playlist")
        if isinstance(is_playlist, bool):
            sanitized["is_playlist"] = is_playlist

        if not sanitized:
            return None
        return cast(PreviewMetadataPayload, sanitized)
