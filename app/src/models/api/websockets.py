from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Any, Mapping, Optional, Sequence, TypedDict

from marshmallow import ValidationError, fields, post_load, pre_load

from ...core import OptionsConfig, build_options_config
from ...core.contract.info import Info
from ...schemas.base import VidraSchema


class OverviewSummary(TypedDict):
    total: int
    active: int
    queued: int
    status_counts: dict[str, int]


class HandleExtractResult(TypedDict):
    event: str
    stage: str
    status: str
    normalized_info: Info
    extractor: Optional[str]
    extractor_key: Optional[str]
    is_playlist: bool
    entry_count: Optional[int]


UrlCollection = Sequence[Any] | str | None


def _clean_str(value: Any | None) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _normalize_urls(value: UrlCollection) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        candidate = _clean_str(value)
        return [candidate] if candidate else []
    if isinstance(value, Sequence):
        normalized: list[str] = []
        for entry in value:
            candidate = _clean_str(entry)
            if candidate:
                normalized.append(candidate)
        return normalized
    candidate = _clean_str(value)
    return [candidate] if candidate else []


def _collect_urls(urls: UrlCollection, single_url: str | None) -> list[str]:
    normalized = _normalize_urls(urls)
    if single_url and (candidate := _clean_str(single_url)):
        normalized.append(candidate)
    return normalized


class DownloadSocketAction(str, Enum):
    EXTRACT_INFO = "extraer_informacion"
    DOWNLOAD = "descargar"
    DOWNLOAD_PLAYLIST = "descargar_playlist"


@dataclass(slots=True)
class DownloadsSocketMessage:
    action: DownloadSocketAction
    urls: list[str]
    options: OptionsConfig | None = None
    download: bool = False

    @property
    def action_label(self) -> str:
        return self.action.value


class DownloadsSocketMessageSchema(VidraSchema):
    action = fields.String(required=True)
    urls = fields.Raw(load_default=None)
    url = fields.String(load_default=None)
    options = fields.Dict(
        keys=fields.String(),
        values=fields.Raw(),
        load_default=None,
    )
    download = fields.Boolean(load_default=False)

    @pre_load
    def _alias_fields(self, data: Mapping[str, Any], **_: Any) -> Mapping[str, Any]:
        if isinstance(data, Mapping) and "action" not in data and "accion" in data:
            mutable = dict(data)
            mutable["action"] = mutable["accion"]
            return mutable
        return data

    @post_load
    def _build_message(
        self, data: Mapping[str, Any], **_: Any
    ) -> DownloadsSocketMessage:
        raw_action = str(data.get("action", "")).strip().lower()
        try:
            action = DownloadSocketAction(raw_action)
        except ValueError as exc:
            raise ValidationError(
                {"action": [f"unknown action '{data.get('action')}'"]}
            ) from exc

        urls = _collect_urls(data.get("urls"), data.get("url"))
        if not urls:
            raise ValidationError({"urls": ["At least one URL is required"]})

        options_payload = data.get("options")
        options: OptionsConfig | None = None
        if options_payload is not None:
            options = build_options_config(options_payload)  # type: ignore[arg-type]

        return DownloadsSocketMessage(
            action=action,
            urls=urls,
            options=options,
            download=bool(data.get("download")),
        )


__all__ = [
    "OverviewSummary",
    "HandleExtractResult",
    "DownloadSocketAction",
    "DownloadsSocketMessage",
    "DownloadsSocketMessageSchema",
]
