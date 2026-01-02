from __future__ import annotations

import copy
from typing import (
    Any,
    Dict,
    List,
    Mapping,
    MutableMapping,
    Optional,
    Sequence,
    Set,
    Tuple,
    cast,
)

from ...core.contract import Info
from ...core.manager import ExtractInfoResult, Manager as CoreManager
from ...core.downloader import YtDlpInfoResult, YtDlpInfoResultThumbnail
from ...download import playlist_helpers
from ...download.models import (
    DownloadJob,
    DownloadJobMetadataPayload,
    DownloadJobOptionsPayload,
)
from ...config import JobKind
from ...models.download.mixins.preview import PreviewThumbnailPayload
from ...models.shared import (
    JSONValue,
    PlaylistEntryMetadata,
    PlaylistMetadata,
    PreviewMetadata,
    Thumbnail,
    clone_json_value,
)
from ...utils import helpers as utils_helpers, truncate_string


INTERNAL_PREVIEW_MODEL_KEY = "_preview_model"
INTERNAL_PLAYLIST_MODEL_KEY = "_playlist_model"
INTERNAL_METADATA_MODEL_KEYS = (
    INTERNAL_PREVIEW_MODEL_KEY,
    INTERNAL_PLAYLIST_MODEL_KEY,
)


MetadataStore = MutableMapping[str, Any]

_PLAYLIST_ENTRY_STRING_KEYS = {
    "title",
    "uploader",
    "channel",
    "webpage_url",
    "duration_text",
    "thumbnail_url",
    "availability",
    "live_status",
    "status",
    "main_file",
}
_PLAYLIST_ENTRY_BOOL_KEYS = {"is_completed", "is_current", "is_live"}
_PLAYLIST_ENTRY_INT_KEYS = {"index", "duration_seconds"}


def _sanitize_preview_payload(payload: JSONValue) -> JSONValue:
    if isinstance(payload, Mapping):
        sanitized = clone_json_value(payload)
        if isinstance(sanitized, dict):
            sanitized.pop("playlist", None)
            return sanitized
    return clone_json_value(payload)


def _coerce_bool(value: JSONValue) -> Optional[bool]:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"true", "1", "yes", "on"}:
            return True
        if normalized in {"false", "0", "no", "off"}:
            return False
    if isinstance(value, (int, float)):
        if value == 1:
            return True
        if value == 0:
            return False
    return None


def _coerce_int(value: JSONValue) -> Optional[int]:
    numeric = utils_helpers.normalize_int(value)
    if numeric is None:
        return None
    return int(numeric)


def _compact_playlist_entry(entry: JSONValue) -> Optional[Dict[str, JSONValue]]:
    if not isinstance(entry, Mapping):
        return None
    mapping = cast(Mapping[str, JSONValue], entry)
    index = _coerce_int(mapping.get("index"))
    if index is None or index <= 0:
        return None
    compact: Dict[str, JSONValue] = {"index": index}
    entry_id = mapping.get("id") or mapping.get("entry_id")
    if isinstance(entry_id, str) and entry_id.strip():
        compact["id"] = entry_id.strip()
    for key in _PLAYLIST_ENTRY_STRING_KEYS:
        value = mapping.get(key)
        if isinstance(value, str):
            trimmed = value.strip()
            if trimmed:
                compact[key] = trimmed
    for key in _PLAYLIST_ENTRY_INT_KEYS:
        if key == "index":
            continue
        numeric = _coerce_int(mapping.get(key))
        if numeric is not None and numeric >= 0:
            compact[key] = numeric
    for key in _PLAYLIST_ENTRY_BOOL_KEYS:
        flag = _coerce_bool(mapping.get(key))
        if flag is not None:
            compact[key] = flag
    return compact


def _compact_entry_refs(value: JSONValue) -> Optional[List[Dict[str, JSONValue]]]:
    if not isinstance(value, list):
        return None
    refs: List[Dict[str, JSONValue]] = []
    for item in value:
        if not isinstance(item, Mapping):
            continue
        mapping = cast(Mapping[str, JSONValue], item)
        index = _coerce_int(mapping.get("index"))
        if index is None or index <= 0:
            continue
        ref: Dict[str, JSONValue] = {"index": index}
        entry_id = mapping.get("id") or mapping.get("entry_id")
        if isinstance(entry_id, str) and entry_id.strip():
            ref["id"] = entry_id.strip()
        status = mapping.get("status")
        if isinstance(status, str) and status.strip():
            ref["status"] = status.strip()
        refs.append(ref)
    return refs if refs else None


def _compact_playlist_payload(payload: Mapping[str, JSONValue]) -> Dict[str, JSONValue]:
    cloned = clone_json_value(cast(JSONValue, payload))
    if not isinstance(cloned, dict):
        return {}
    compact: Dict[str, JSONValue] = dict(cloned)
    entries_value = compact.get("entries")
    if isinstance(entries_value, list):
        compact_entries: List[Dict[str, JSONValue]] = []
        for entry in entries_value:
            compact_entry = _compact_playlist_entry(entry)
            if compact_entry:
                compact_entries.append(compact_entry)
        compact["entries"] = cast(JSONValue, compact_entries)
    else:
        compact.pop("entries", None)
    entry_refs = _compact_entry_refs(compact.get("entry_refs"))
    if entry_refs is not None:
        compact["entry_refs"] = cast(JSONValue, entry_refs)
    else:
        compact.pop("entry_refs", None)
    compact.pop("thumbnails", None)
    compact.pop("tags", None)
    compact.pop("preview", None)
    return compact


def _coerce_metadata_store(
    metadata: Optional[DownloadJobMetadataPayload],
) -> Optional[MetadataStore]:
    if isinstance(metadata, dict):
        return cast(MetadataStore, metadata)
    return None


def metadata_store_preview_model(
    metadata: Optional[DownloadJobMetadataPayload],
    model: Optional[PreviewMetadata],
) -> None:
    store = _coerce_metadata_store(metadata)
    if store is None:
        return
    if model is None:
        store.pop(INTERNAL_PREVIEW_MODEL_KEY, None)
        return
    store[INTERNAL_PREVIEW_MODEL_KEY] = model
    store["preview"] = model.to_payload()


def metadata_store_playlist_model(
    metadata: Optional[DownloadJobMetadataPayload],
    model: Optional[PlaylistMetadata],
) -> None:
    store = _coerce_metadata_store(metadata)
    if store is None:
        return
    if model is None:
        store.pop(INTERNAL_PLAYLIST_MODEL_KEY, None)
        return
    store[INTERNAL_PLAYLIST_MODEL_KEY] = model
    store["playlist"] = model.to_payload()


def _coerce_preview_model(value: Any) -> Optional[PreviewMetadata]:
    if isinstance(value, PreviewMetadata):
        return value
    if isinstance(value, Mapping):
        payload = cast(Mapping[str, JSONValue], value)
        return PreviewMetadata.from_payload(payload)
    return None


def _coerce_playlist_model(value: Any) -> Optional[PlaylistMetadata]:
    if isinstance(value, PlaylistMetadata):
        return value
    if isinstance(value, Mapping):
        payload = cast(Mapping[str, JSONValue], value)
        return PlaylistMetadata.from_payload(payload)
    return None


def _coerce_thumbnail_payloads(
    thumbnails_value: Sequence[PreviewThumbnailPayload | YtDlpInfoResultThumbnail]
    | None,
) -> Sequence[Mapping[str, JSONValue]] | None:
    if thumbnails_value is None:
        return None
    payloads: list[Mapping[str, JSONValue]] = []
    for entry in thumbnails_value:
        payloads.append(cast(Mapping[str, JSONValue], entry))
    return payloads


def metadata_get_preview_model(
    metadata: Optional[DownloadJobMetadataPayload],
    *,
    clone: bool = False,
) -> Optional[PreviewMetadata]:
    store = _coerce_metadata_store(metadata)
    if store is None:
        return None
    model = _coerce_preview_model(store.get(INTERNAL_PREVIEW_MODEL_KEY))
    if model is None:
        preview_payload = store.get("preview")
        model = _coerce_preview_model(preview_payload)
        if model is None:
            return None
        store[INTERNAL_PREVIEW_MODEL_KEY] = model
    return copy.deepcopy(model) if clone else model


def metadata_get_playlist_model(
    metadata: Optional[DownloadJobMetadataPayload],
    *,
    clone: bool = False,
) -> Optional[PlaylistMetadata]:
    store = _coerce_metadata_store(metadata)
    if store is None:
        return None
    model = _coerce_playlist_model(store.get(INTERNAL_PLAYLIST_MODEL_KEY))
    if model is None:
        playlist_payload = store.get("playlist")
        model = _coerce_playlist_model(playlist_payload)
        if model is None:
            return None
        store[INTERNAL_PLAYLIST_MODEL_KEY] = model
    return copy.deepcopy(model) if clone else model


def metadata_public_view(
    metadata: Optional[DownloadJobMetadataPayload],
    *,
    include_playlist_entries: bool = True,
    max_playlist_entries: Optional[int] = None,
) -> Dict[str, JSONValue]:
    if not isinstance(metadata, dict):
        return {}
    public_view: Dict[str, JSONValue] = {}
    for key, value in metadata.items():
        if key in INTERNAL_METADATA_MODEL_KEYS:
            continue
        if isinstance(value, (str, int, float, bool)) or value is None:
            public_view[key] = value
        elif isinstance(value, list) or isinstance(value, dict):
            if key == "preview":
                public_view[key] = _sanitize_preview_payload(cast(JSONValue, value))
            elif key == "playlist" and isinstance(value, Mapping):
                playlist_payload = _compact_playlist_payload(
                    cast(Mapping[str, JSONValue], value)
                )
                entries_value = playlist_payload.get("entries")
                if not include_playlist_entries:
                    playlist_payload.pop("entries", None)
                    playlist_payload["entries_external"] = True
                elif max_playlist_entries is not None:
                    if (
                        isinstance(entries_value, list)
                        and len(entries_value) > max_playlist_entries
                    ):
                        playlist_payload["entries"] = entries_value[
                            :max_playlist_entries
                        ]
                        playlist_payload["entries_truncated"] = True
                if "is_collecting_entries" not in playlist_payload:
                    playlist_payload["is_collecting_entries"] = False
                if "collection_complete" not in playlist_payload:
                    playlist_payload["collection_complete"] = False
                if "has_indefinite_length" not in playlist_payload:
                    playlist_payload["has_indefinite_length"] = False
                public_view[key] = playlist_payload
            else:
                public_view[key] = clone_json_value(cast(JSONValue, value))
    if "requires_playlist_selection" not in public_view:
        public_view["requires_playlist_selection"] = False
    return public_view


class ManagerUtilsMixin:
    def _core_manager(self) -> CoreManager:
        manager = getattr(self, "core_manager", None)
        if manager is None:
            raise RuntimeError("core manager is not configured")
        return cast(CoreManager, manager)

    _normalize_upload_date = staticmethod(utils_helpers.normalize_upload_date)
    _select_best_thumbnail_url = staticmethod(
        playlist_helpers.select_best_thumbnail_url
    )
    _gather_thumbnail_entries = staticmethod(playlist_helpers.gather_thumbnail_entries)
    _normalize_selected_indices = staticmethod(
        playlist_helpers.normalize_selected_indices
    )
    _parse_playlist_items_spec = staticmethod(
        playlist_helpers.parse_playlist_items_spec
    )
    _select_primary_entry = staticmethod(playlist_helpers.select_primary_entry)
    _normalize_thumbnail_list = staticmethod(playlist_helpers.normalize_thumbnail_list)
    _normalize_percent_value = staticmethod(utils_helpers.normalize_percent)
    _extract_stage_percent = staticmethod(playlist_helpers.extract_stage_percent)
    _extract_stage_items = staticmethod(playlist_helpers.extract_stage_items)
    _is_playlist = staticmethod(playlist_helpers.is_playlist)

    def _build_preview_from_info(
        self,
        result: ExtractInfoResult,
    ) -> Optional[PreviewMetadata]:
        model = result.model
        raw_info = getattr(result, "raw", None)
        raw_mapping: Optional[YtDlpInfoResult] = None
        if isinstance(raw_info, dict):
            raw_mapping = cast(YtDlpInfoResult, raw_info)
        preview = PreviewMetadata()

        if model.title:
            preview.title = model.title
        if model.description:
            truncated_description = truncate_string(model.description)
            if truncated_description:
                preview.description = truncated_description
        if model.url:
            preview.webpage_url = model.url
            if preview.original_url is None:
                preview.original_url = model.url
        if model.webpage_url_basename:
            preview.webpage_url_basename = model.webpage_url_basename
        if model.webpage_url_domain:
            preview.webpage_url_domain = model.webpage_url_domain
        if model.thumbnail:
            preview.thumbnail_url = model.thumbnail

        thumbnails_value: Sequence[YtDlpInfoResultThumbnail] | None = (
            raw_mapping.get("thumbnails") if raw_mapping else None
        )
        thumbnails, best_thumbnail = self._build_thumbnails_from_source(
            thumbnails_value
        )
        if thumbnails:
            preview.thumbnails = thumbnails
        if best_thumbnail:
            preview.thumbnail_url = best_thumbnail

        if model.duration is not None:
            preview.duration_seconds = model.duration
        if model.duration_string:
            preview.duration_text = model.duration_string
        if result.extractor:
            preview.extractor = result.extractor
        if result.extractor_key:
            preview.extractor_id = result.extractor_key
        if model.id:
            preview.entry_id = model.id
        if model.view_count is not None:
            preview.view_count = model.view_count
        if model.like_count is not None:
            preview.like_count = model.like_count
        if model.availability:
            preview.availability = model.availability
        if model.live_status:
            preview.live_status = model.live_status
        if model.tags:
            preview.tags = list(model.tags)
        if model.uploader:
            preview.uploader = model.uploader
        if model.uploader_id:
            preview.uploader_id = model.uploader_id
        if model.uploader_url:
            preview.uploader_url = model.uploader_url
        if model.channel:
            preview.channel = model.channel
        if model.channel_id:
            preview.channel_id = model.channel_id
        if model.channel_url:
            preview.channel_url = model.channel_url
        if model.channel_follower_count is not None:
            preview.channel_follower_count = model.channel_follower_count
        if model.channel_is_verified is not None:
            preview.channel_is_verified = model.channel_is_verified

        upload_iso = self._normalize_upload_date(model.release_date)
        if upload_iso:
            preview.upload_date_iso = upload_iso

        if model.is_playlist:
            preview.is_playlist = True
            playlist_metadata = self._build_playlist_metadata_from_info(
                model,
                raw_mapping,
            )
            if playlist_metadata:
                preview.playlist = playlist_metadata
            if model.entry_count is not None:
                preview.playlist_entry_count = model.entry_count
            if model.id:
                preview.playlist_id = model.id
            if model.title and preview.playlist_title is None:
                preview.playlist_title = model.title
            if model.uploader and preview.playlist_uploader is None:
                preview.playlist_uploader = model.uploader

        return preview if preview.has_data() else None

    def _build_playlist_metadata_from_info(
        self,
        playlist_info: Info,
        raw_playlist: Optional[YtDlpInfoResult] = None,
    ) -> Optional[PlaylistMetadata]:
        metadata = PlaylistMetadata()
        if playlist_info.id:
            metadata.playlist_id = playlist_info.id
        if playlist_info.title:
            metadata.title = playlist_info.title
        if playlist_info.uploader:
            metadata.uploader = playlist_info.uploader
        if playlist_info.uploader_id:
            metadata.uploader_id = playlist_info.uploader_id
        if playlist_info.uploader_url:
            metadata.uploader_url = playlist_info.uploader_url
        if playlist_info.channel:
            metadata.channel = playlist_info.channel
        if playlist_info.channel_id:
            metadata.channel_id = playlist_info.channel_id
        if playlist_info.channel_url:
            metadata.channel_url = playlist_info.channel_url
        if playlist_info.channel_follower_count is not None:
            metadata.channel_follower_count = playlist_info.channel_follower_count
        if playlist_info.channel_is_verified is not None:
            metadata.channel_is_verified = playlist_info.channel_is_verified
        if playlist_info.description:
            truncated_description = truncate_string(playlist_info.description)
            if truncated_description:
                metadata.description = truncated_description
                metadata.description_short = truncated_description
        if playlist_info.url:
            metadata.webpage_url = playlist_info.url
        if playlist_info.availability:
            metadata.availability = playlist_info.availability
        if playlist_info.live_status:
            metadata.live_status = playlist_info.live_status
        if playlist_info.thumbnail:
            metadata.thumbnail_url = playlist_info.thumbnail

        thumbnails_value: Sequence[YtDlpInfoResultThumbnail] | None = (
            raw_playlist.get("thumbnails") if raw_playlist else None
        )
        thumbnails, best_thumbnail = self._build_thumbnails_from_source(
            thumbnails_value
        )
        if thumbnails:
            metadata.thumbnails = thumbnails
        if best_thumbnail:
            metadata.thumbnail_url = best_thumbnail

        if playlist_info.tags:
            metadata.tags = list(playlist_info.tags)

        entries_payload: list[PlaylistEntryMetadata] = []
        if playlist_info.entries:
            for index, entry_info in enumerate(playlist_info.entries, start=1):
                entry_payload = self._build_playlist_entry_from_info(entry_info, index)
                if entry_payload:
                    entries_payload.append(entry_payload)
        if entries_payload:
            metadata.entries = entries_payload

        if playlist_info.entry_count is not None:
            metadata.entry_count = playlist_info.entry_count
        elif entries_payload:
            metadata.entry_count = len(entries_payload)

        return metadata if metadata.has_data() else None

    def _build_playlist_entry_from_info(
        self,
        entry_info: Info,
        index: int,
    ) -> Optional[PlaylistEntryMetadata]:
        entry = PlaylistEntryMetadata(index=index)
        if entry_info.id:
            entry.entry_id = entry_info.id
        if entry_info.title:
            entry.title = entry_info.title
        if entry_info.uploader:
            entry.uploader = entry_info.uploader
        if entry_info.uploader_id:
            entry.uploader_id = entry_info.uploader_id
        if entry_info.uploader_url:
            entry.uploader_url = entry_info.uploader_url
        if entry_info.channel:
            entry.channel = entry_info.channel
        if entry_info.channel_id:
            entry.channel_id = entry_info.channel_id
        if entry_info.channel_url:
            entry.channel_url = entry_info.channel_url
        if entry_info.channel_is_verified is not None:
            entry.channel_is_verified = entry_info.channel_is_verified
        if entry_info.url:
            entry.webpage_url = entry_info.url
        if entry_info.duration is not None:
            entry.duration_seconds = entry_info.duration
        if entry_info.duration_string:
            entry.duration_text = entry_info.duration_string
        if entry_info.thumbnail:
            entry.thumbnail_url = entry_info.thumbnail
        if entry_info.availability:
            entry.availability = entry_info.availability
        if entry_info.live_status:
            entry.live_status = entry_info.live_status
        if entry_info.view_count is not None:
            entry.view_count = entry_info.view_count

        preview = PreviewMetadata()
        if entry_info.title:
            preview.title = entry_info.title
        if entry_info.url:
            preview.webpage_url = entry_info.url
            preview.original_url = entry_info.url
        if entry_info.thumbnail:
            preview.thumbnail_url = entry_info.thumbnail
        if entry_info.duration is not None:
            preview.duration_seconds = entry_info.duration
        if entry_info.duration_string:
            preview.duration_text = entry_info.duration_string
        if entry_info.uploader:
            preview.uploader = entry_info.uploader
        if entry_info.uploader_url:
            preview.uploader_url = entry_info.uploader_url
        if entry_info.channel:
            preview.channel = entry_info.channel
        if entry_info.channel_url:
            preview.channel_url = entry_info.channel_url
        if preview.has_data():
            entry.preview = preview

        if entry.status is None:
            entry.status = "pending"

        return entry if entry.has_data() else None

    def _build_thumbnails_from_source(
        self,
        thumbnails_value: Sequence[PreviewThumbnailPayload | YtDlpInfoResultThumbnail]
        | None,
    ) -> Tuple[list[Thumbnail], Optional[str]]:
        normalized = self._normalize_thumbnail_list(
            _coerce_thumbnail_payloads(thumbnails_value)
        )
        if not normalized:
            return [], None
        thumbnails = self._convert_thumbnails(normalized)
        best_thumbnail = self._select_best_thumbnail_url(normalized)
        return thumbnails, best_thumbnail

    @staticmethod
    def _convert_thumbnails(
        thumbnails: list[PreviewThumbnailPayload],
    ) -> list[Thumbnail]:
        models: list[Thumbnail] = []
        for payload in thumbnails:
            url = payload.get("url")
            if not isinstance(url, str) or not url:
                continue
            width = payload.get("width")
            height = payload.get("height")
            identifier = payload.get("id")
            models.append(
                Thumbnail(
                    url=url,
                    width=width if isinstance(width, int) else None,
                    height=height if isinstance(height, int) else None,
                    identifier=identifier if isinstance(identifier, str) else None,
                )
            )
        return models

    def _resolve_selected_playlist_indices(self, job: DownloadJob) -> Set[int]:
        metadata: DownloadJobMetadataPayload = job.metadata
        playlist_meta = metadata.get("playlist")
        selected: Set[int] = set()
        if isinstance(playlist_meta, dict):
            selected = self._normalize_selected_indices(
                playlist_meta.get("selected_indices")
            )
        if selected:
            return selected
        options: DownloadJobOptionsPayload = job.options
        spec = options.get("playlist_items")
        if isinstance(spec, str) and spec.strip():
            parsed = self._parse_playlist_items_spec(spec)
            if parsed:
                return parsed
        return selected

    @staticmethod
    def _job_behaves_like_playlist(job: DownloadJob) -> bool:
        kind_value = (job.kind or "").strip().lower()
        if kind_value == JobKind.PLAYLIST.value:
            return True
        if kind_value == JobKind.VIDEO.value:
            return False

        metadata = job.metadata or {}
        metadata_flag = metadata.get("is_playlist")
        if isinstance(metadata_flag, bool):
            return metadata_flag

        playlist_meta = metadata.get("playlist")
        if isinstance(playlist_meta, Mapping):
            playlist_flag = playlist_meta.get("is_playlist")
            if isinstance(playlist_flag, bool):
                return playlist_flag
            entry_count = playlist_meta.get("entry_count")
            if isinstance(entry_count, int) and entry_count > 1:
                return True

        total_items = job.playlist_total_items
        if isinstance(total_items, int) and total_items > 1:
            return True

        if job.playlist_completed_indices:
            return True

        return False
