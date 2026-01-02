"""Request payload helpers validated via Marshmallow schemas."""

from __future__ import annotations

from typing import Any, Mapping, Sequence, TypeAlias, cast

from marshmallow import INCLUDE, ValidationError, fields, post_load, pre_load

from ...download.models import (
    DownloadJobMetadataPayload,
    DownloadJobOptionsPayload,
    DownloadJobPathsOptions,
)
from ...models.shared import JSONValue
from ...models.shared.media import PlaylistMetadata, PreviewMetadata
from ...schemas.base import VidraSchema

UrlValue = list[str] | Sequence[str] | str | None
StringListValue = list[str] | Sequence[str] | str | None
IntListValue = list[int | str | None] | Sequence[int | str | None] | str | None


def _clean_str(value: str | None) -> str | None:
    if value is None:
        return None
    text = value.strip()
    return text or None


def _normalize_string_collection(value: StringListValue) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        candidate = _clean_str(value)
        return [candidate] if candidate else []
    normalized: list[str] = []
    for item in value:
        candidate = _clean_str(item)
        if candidate:
            normalized.append(candidate)
    return normalized


def _ensure_list(value: UrlValue) -> list[str]:
    return _normalize_string_collection(value)


def _normalize_cli_args(value: list[str] | Sequence[str] | str | None) -> list[str]:
    return _normalize_string_collection(value)


def _normalize_indices(value: IntListValue) -> list[int] | None:
    if value is None:
        return None
    if isinstance(value, str):
        raise ValueError("indices must be a list")
    normalized: list[int] = []
    for entry in value:
        if entry is None:
            continue
        if isinstance(entry, int):
            candidate = entry
        else:
            text = _clean_str(entry)
            if not text:
                raise ValueError("indices must be integers")
            try:
                candidate = int(text)
            except ValueError as exc:  # pragma: no cover - defensive guard
                raise ValueError("indices must be integers") from exc
        if candidate > 0:
            normalized.append(candidate)
    return normalized


class DownloadJobPathsOptionsRequest:
    """Structured request for download directory overrides."""

    def __init__(
        self,
        home: str | None = None,
        temp: str | None = None,
        output: str | None = None,
        download: str | None = None,
        **_: Any,
    ) -> None:
        self.home = home
        self.temp = temp
        self.output = output
        self.download = download

    def to_payload(self) -> DownloadJobPathsOptions:
        payload: DownloadJobPathsOptions = {}
        if home := _clean_str(self.home):
            payload["home"] = home
        if temp := _clean_str(self.temp):
            payload["temp"] = temp
        if output := _clean_str(self.output):
            payload["output"] = output
        if download := _clean_str(self.download):
            payload["download"] = download
        return payload


class DownloadJobOptionsRequest:
    """Request helper for download-specific yt-dlp options."""

    _KNOWN_ATTRS: set[str] = {
        "playlist",
        "playlist_items",
        "playlist_start",
        "playlist_end",
        "force_overwrites",
        "download_archive",
        "format",
        "output",
        "output_dir",
        "paths",
        "cli_args",
        "defer_complete",
    }

    def __init__(
        self,
        playlist: bool | None = None,
        playlist_items: str | None = None,
        playlist_start: int | None = None,
        playlist_end: int | None = None,
        force_overwrites: bool | None = None,
        download_archive: str | None = None,
        format: str | None = None,
        output: str | None = None,
        output_dir: str | None = None,
        paths: DownloadJobPathsOptionsRequest | None = None,
        cli_args: list[str] | Sequence[str] | str | None = None,
        defer_complete: bool | None = None,
        **extra: Any,
    ) -> None:
        self.playlist = playlist
        self.playlist_items = playlist_items
        self.playlist_start = playlist_start
        self.playlist_end = playlist_end
        self.force_overwrites = force_overwrites
        self.download_archive = download_archive
        self.format = format
        self.output = output
        self.output_dir = output_dir
        self.paths = paths
        self.cli_args = cli_args
        self.defer_complete = defer_complete
        for key, value in extra.items():
            setattr(self, key, value)

    def to_payload(self) -> DownloadJobOptionsPayload:
        payload: DownloadJobOptionsPayload = {}
        if self.playlist is not None:
            payload["playlist"] = self.playlist
        if text := _clean_str(self.playlist_items):
            payload["playlist_items"] = text
        if self.playlist_start is not None:
            payload["playlist_start"] = self.playlist_start
        if self.playlist_end is not None:
            payload["playlist_end"] = self.playlist_end
        if self.force_overwrites is not None:
            payload["force_overwrites"] = self.force_overwrites
        if archive := _clean_str(self.download_archive):
            payload["download_archive"] = archive
        if fmt := _clean_str(self.format):
            payload["format"] = fmt
        if output := _clean_str(self.output):
            payload["output"] = output
        if output_dir := _clean_str(self.output_dir):
            payload["output_dir"] = output_dir
        if self.defer_complete is not None:
            payload["defer_complete"] = self.defer_complete
        if self.paths is not None:
            paths_payload = self.paths.to_payload()
            if paths_payload:
                payload["paths"] = cast(JSONValue, paths_payload)
        cli_args = _normalize_cli_args(self.cli_args)
        if cli_args:
            payload["cli_args"] = cast(JSONValue, cli_args)
        for key, value in self._extra_option_entries().items():
            payload.setdefault(key, value)
        return payload

    def _extra_option_entries(self) -> dict[str, JSONValue]:
        extras: dict[str, JSONValue] = {}
        for key, value in self.__dict__.items():
            if key in self._KNOWN_ATTRS or key.startswith("_"):
                continue
            if value is None:
                continue
            extras[key] = cast(JSONValue, value)
        return extras


class DownloadJobMetadataRequest:
    """High-level metadata accompanying a job submission."""

    def __init__(
        self,
        playlist: PlaylistMetadata | Mapping[str, object] | None = None,
        preview: PreviewMetadata | Mapping[str, object] | None = None,
        requires_playlist_selection: bool | None = None,
        is_playlist: bool | None = None,
        ctx_id: str | None = None,
        playlist_id: str | None = None,
        playlist_entry_count: int | None = None,
        playlist_title: str | None = None,
        title: str | None = None,
        description: str | None = None,
        thumbnail_url: str | None = None,
        webpage_url: str | None = None,
        original_url: str | None = None,
        preview_collected_at: str | None = None,
        **_: Any,
    ) -> None:
        self.playlist = (
            playlist
            if isinstance(playlist, PlaylistMetadata)
            else PlaylistMetadata.from_payload(playlist)  # type: ignore[arg-type]
            if isinstance(playlist, Mapping)
            else None
        )
        self.preview = (
            preview
            if isinstance(preview, PreviewMetadata)
            else PreviewMetadata.from_payload(preview)  # type: ignore[arg-type]
            if isinstance(preview, Mapping)
            else None
        )
        self.requires_playlist_selection = requires_playlist_selection
        self.is_playlist = is_playlist
        self.ctx_id = ctx_id
        self.playlist_id = playlist_id
        self.playlist_entry_count = playlist_entry_count
        self.playlist_title = playlist_title
        self.title = title
        self.description = description
        self.thumbnail_url = thumbnail_url
        self.webpage_url = webpage_url
        self.original_url = original_url
        self.preview_collected_at = preview_collected_at

    def to_payload(self) -> DownloadJobMetadataPayload:
        payload: DownloadJobMetadataPayload = {}
        if self.playlist is not None:
            payload["playlist"] = self.playlist.to_payload()
        if self.preview is not None:
            payload["preview"] = self.preview.to_payload()
        if self.requires_playlist_selection is not None:
            payload["requires_playlist_selection"] = self.requires_playlist_selection
        if self.is_playlist is not None:
            payload["is_playlist"] = self.is_playlist
        if ctx_id := _clean_str(self.ctx_id):
            payload["ctx_id"] = ctx_id
        if playlist_id := _clean_str(self.playlist_id):
            payload["playlist_id"] = playlist_id
        if self.playlist_entry_count is not None:
            payload["playlist_entry_count"] = self.playlist_entry_count
        if playlist_title := _clean_str(self.playlist_title):
            payload["playlist_title"] = playlist_title
        if title := _clean_str(self.title):
            payload["title"] = title
        if description := _clean_str(self.description):
            payload["description"] = description
        if thumbnail := _clean_str(self.thumbnail_url):
            payload["thumbnail_url"] = thumbnail
        if webpage := _clean_str(self.webpage_url):
            payload["webpage_url"] = webpage
        if original := _clean_str(self.original_url):
            payload["original_url"] = original
        if collected := _clean_str(self.preview_collected_at):
            payload["preview_collected_at"] = collected
        return payload


class UrlRequestBase:
    """Base helper for request bodies that include URLs."""

    def __init__(self, urls: UrlValue = None, url: str | None = None, **_: Any) -> None:
        self.urls = urls
        self.url = url

    def normalized_urls(self) -> list[str]:
        normalized = _ensure_list(self.urls)
        if candidate := _clean_str(self.url):
            normalized.append(candidate)
        return normalized


class CreateJobRequestBody(UrlRequestBase):
    def __init__(
        self,
        urls: UrlValue = None,
        url: str | None = None,
        options: DownloadJobOptionsRequest | None = None,
        owner: str | None = None,
        creator: str | None = None,
        metadata: DownloadJobMetadataRequest | None = None,
        **_: Any,
    ) -> None:
        super().__init__(urls=urls, url=url)
        self.options = options
        self.owner = owner
        self.creator = creator
        self.metadata = metadata

    def options_payload(self) -> DownloadJobOptionsPayload:
        if self.options is None:
            return {}
        return self.options.to_payload()

    def metadata_payload(self) -> DownloadJobMetadataPayload:
        if self.metadata is None:
            return {}
        return self.metadata.to_payload()

    def effective_creator(self) -> str | None:
        return _clean_str(self.owner) or _clean_str(self.creator)


class CancelJobsRequestBody:
    def __init__(
        self,
        job_ids: list[str] | None = None,
        scope: str | None = None,
        owner: str | None = None,
        **_: Any,
    ) -> None:
        self.job_ids = job_ids
        self.scope = scope
        self.owner = owner

    def normalized_job_ids(self) -> list[str]:
        if not self.job_ids:
            raise ValueError("job_ids or scope required")
        return list(self.job_ids)

    def normalized_owner(self) -> str | None:
        return _clean_str(self.owner)


class PlaylistSelectionRequestBody:
    def __init__(self, indices: list[int] | None = None, **_: Any) -> None:
        self.indices = indices

    def normalized_indices(self) -> list[int] | None:
        return list(self.indices) if self.indices else None


class PlaylistEntryActionRequestBody:
    def __init__(
        self,
        indices: list[int] | None = None,
        entry_ids: list[str] | None = None,
        **_: Any,
    ) -> None:
        self.indices = indices
        self.entry_ids = entry_ids

    def normalized_indices(self) -> list[int]:
        return list(self.indices) if self.indices else []

    def normalized_entry_ids(self) -> list[str]:
        return list(self.entry_ids) if self.entry_ids else []


class PlaylistEntryDeleteRequestBody:
    def __init__(
        self,
        indices: list[int] | None = None,
        entry_ids: list[str] | None = None,
        **_: Any,
    ) -> None:
        self.indices = indices
        self.entry_ids = entry_ids

    def normalized_indices(self) -> list[int]:
        return list(self.indices) if self.indices else []

    def normalized_entry_ids(self) -> list[str]:
        return list(self.entry_ids) if self.entry_ids else []


class DryRunJobRequestBody(UrlRequestBase):
    def __init__(
        self,
        urls: UrlValue = None,
        url: str | None = None,
        options: DownloadJobOptionsRequest | None = None,
        **_: Any,
    ) -> None:
        super().__init__(urls=urls, url=url)
        self.options = options

    def options_payload(self) -> DownloadJobOptionsPayload:
        if self.options is None:
            return {}
        return self.options.to_payload()


class PreviewRequestBody(UrlRequestBase):
    def __init__(
        self,
        urls: UrlValue = None,
        url: str | None = None,
        options: DownloadJobOptionsRequest | None = None,
        **_: Any,
    ) -> None:
        super().__init__(urls=urls, url=url)
        self.options = options

    def options_payload(self) -> DownloadJobOptionsPayload | None:
        if self.options is None:
            return None
        payload = self.options.to_payload()
        return payload if payload else None


class DownloadJobPathsOptionsSchema(VidraSchema):
    home = fields.String(load_default=None, allow_none=True)
    temp = fields.String(load_default=None, allow_none=True)
    output = fields.String(load_default=None, allow_none=True)
    download = fields.String(load_default=None, allow_none=True)

    @post_load
    def make(self, data: dict[str, Any], **_: Any) -> DownloadJobPathsOptionsRequest:
        return DownloadJobPathsOptionsRequest(**data)


class DownloadJobOptionsSchema(VidraSchema):
    playlist = fields.Boolean(load_default=None, allow_none=True)
    playlist_items = fields.String(load_default=None, allow_none=True)
    playlist_start = fields.Integer(load_default=None, allow_none=True)
    playlist_end = fields.Integer(load_default=None, allow_none=True)
    force_overwrites = fields.Boolean(load_default=None, allow_none=True)
    download_archive = fields.String(load_default=None, allow_none=True)
    format = fields.String(load_default=None, allow_none=True)
    output = fields.String(load_default=None, allow_none=True)
    output_dir = fields.String(load_default=None, allow_none=True)
    paths = fields.Nested(DownloadJobPathsOptionsSchema, allow_none=True)
    cli_args = fields.Raw(load_default=None, allow_none=True)
    defer_complete = fields.Boolean(load_default=None, allow_none=True)

    class Meta(VidraSchema.Meta):
        unknown = INCLUDE

    @post_load
    def make(self, data: dict[str, Any], **_: Any) -> DownloadJobOptionsRequest:
        return DownloadJobOptionsRequest(**data)


class DownloadJobMetadataSchema(VidraSchema):
    playlist = fields.Raw(load_default=None, allow_none=True)
    preview = fields.Raw(load_default=None, allow_none=True)
    requires_playlist_selection = fields.Boolean(load_default=None, allow_none=True)
    is_playlist = fields.Boolean(load_default=None, allow_none=True)
    ctx_id = fields.String(load_default=None, allow_none=True)
    playlist_id = fields.String(load_default=None, allow_none=True)
    playlist_entry_count = fields.Integer(load_default=None, allow_none=True)
    playlist_title = fields.String(load_default=None, allow_none=True)
    title = fields.String(load_default=None, allow_none=True)
    description = fields.String(load_default=None, allow_none=True)
    thumbnail_url = fields.String(load_default=None, allow_none=True)
    webpage_url = fields.String(load_default=None, allow_none=True)
    original_url = fields.String(load_default=None, allow_none=True)
    preview_collected_at = fields.String(load_default=None, allow_none=True)

    @post_load
    def make(self, data: dict[str, Any], **_: Any) -> DownloadJobMetadataRequest:
        playlist_payload = data.get("playlist")
        if isinstance(playlist_payload, Mapping):
            data["playlist"] = PlaylistMetadata.from_payload(playlist_payload)
        preview_payload = data.get("preview")
        if isinstance(preview_payload, Mapping):
            data["preview"] = PreviewMetadata.from_payload(preview_payload)
        return DownloadJobMetadataRequest(**data)


class CreateJobRequestSchema(VidraSchema):
    urls = fields.Raw(load_default=None, allow_none=True)
    url = fields.String(load_default=None, allow_none=True)
    options = fields.Nested(DownloadJobOptionsSchema, allow_none=True)
    owner = fields.String(load_default=None, allow_none=True)
    creator = fields.String(load_default=None, allow_none=True)
    metadata = fields.Nested(DownloadJobMetadataSchema, allow_none=True)

    @post_load
    def make(self, data: dict[str, Any], **_: Any) -> CreateJobRequestBody:
        return CreateJobRequestBody(**data)


class CancelJobsRequestSchema(VidraSchema):
    job_ids = fields.Raw(load_default=None, allow_none=True)
    scope = fields.String(load_default=None, allow_none=True)
    owner = fields.String(load_default=None, allow_none=True)

    @pre_load
    def _alias_job_ids(self, data: Any, **_: Any) -> Any:
        if isinstance(data, Mapping):
            has_snake = "job_ids" in data
            has_camel = "jobIds" in data
            if has_snake and not has_camel:
                cloned = dict(data)
                cloned["jobIds"] = cloned["job_ids"]
                return cloned
        return data

    @post_load
    def make(self, data: dict[str, Any], **_: Any) -> CancelJobsRequestBody:
        if data.get("job_ids") is not None:
            data["job_ids"] = _normalize_string_collection(
                cast(StringListValue, data["job_ids"])
            )
        return CancelJobsRequestBody(**data)


class PlaylistSelectionRequestSchema(VidraSchema):
    indices = fields.Raw(load_default=None, allow_none=True)

    @post_load
    def make(self, data: dict[str, Any], **_: Any) -> PlaylistSelectionRequestBody:
        if data.get("indices") is not None:
            try:
                data["indices"] = _normalize_indices(
                    cast(IntListValue, data["indices"])
                )
            except ValueError as exc:  # pragma: no cover - marshmallow handles
                raise ValidationError(str(exc), field_name="indices") from exc
        return PlaylistSelectionRequestBody(**data)


class PlaylistEntryActionRequestSchema(VidraSchema):
    indices = fields.Raw(load_default=None, allow_none=True)
    entry_ids = fields.Raw(load_default=None, allow_none=True)

    @post_load
    def make(self, data: dict[str, Any], **_: Any) -> PlaylistEntryActionRequestBody:
        if data.get("indices") is not None:
            try:
                data["indices"] = _normalize_indices(
                    cast(IntListValue, data["indices"])
                )
            except ValueError as exc:  # pragma: no cover
                raise ValidationError(str(exc), field_name="indices") from exc
        if data.get("entry_ids") is not None:
            data["entry_ids"] = _normalize_string_collection(
                cast(StringListValue, data["entry_ids"])
            )
        return PlaylistEntryActionRequestBody(**data)


class PlaylistEntryDeleteRequestSchema(VidraSchema):
    indices = fields.Raw(load_default=None, allow_none=True)
    entry_ids = fields.Raw(load_default=None, allow_none=True)

    @post_load
    def make(self, data: dict[str, Any], **_: Any) -> PlaylistEntryDeleteRequestBody:
        if data.get("indices") is not None:
            try:
                data["indices"] = _normalize_indices(
                    cast(IntListValue, data["indices"])
                )
            except ValueError as exc:  # pragma: no cover
                raise ValidationError(str(exc), field_name="indices") from exc
        if data.get("entry_ids") is not None:
            data["entry_ids"] = _normalize_string_collection(
                cast(StringListValue, data["entry_ids"])
            )
        return PlaylistEntryDeleteRequestBody(**data)


class DryRunJobRequestSchema(VidraSchema):
    urls = fields.Raw(load_default=None, allow_none=True)
    url = fields.String(load_default=None, allow_none=True)
    options = fields.Nested(DownloadJobOptionsSchema, allow_none=True)

    @post_load
    def make(self, data: dict[str, Any], **_: Any) -> DryRunJobRequestBody:
        return DryRunJobRequestBody(**data)


class PreviewRequestSchema(VidraSchema):
    urls = fields.Raw(load_default=None, allow_none=True)
    url = fields.String(load_default=None, allow_none=True)
    options = fields.Nested(DownloadJobOptionsSchema, allow_none=True)

    @post_load
    def make(self, data: dict[str, Any], **_: Any) -> PreviewRequestBody:
        return PreviewRequestBody(**data)


__all__ = [
    "DownloadJobPathsOptionsRequest",
    "DownloadJobOptionsRequest",
    "DownloadJobMetadataRequest",
    "CreateJobRequestBody",
    "CancelJobsRequestBody",
    "PlaylistSelectionRequestBody",
    "PlaylistEntryActionRequestBody",
    "PlaylistEntryDeleteRequestBody",
    "DryRunJobRequestBody",
    "PreviewRequestBody",
    "DownloadJobPathsOptionsSchema",
    "DownloadJobOptionsSchema",
    "DownloadJobMetadataSchema",
    "CreateJobRequestSchema",
    "CancelJobsRequestSchema",
    "PlaylistSelectionRequestSchema",
    "PlaylistEntryActionRequestSchema",
    "PlaylistEntryDeleteRequestSchema",
    "DryRunJobRequestSchema",
    "PreviewRequestSchema",
]
