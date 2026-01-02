"""Safe helper objects for yt-dlp hook payloads."""

from __future__ import annotations

import json
from typing import Any, Callable, Mapping, TypeVar, cast

from ..utils import clean_string, to_float, to_int

JsonMapping = Mapping[str, Any]
JsonLike = str | JsonMapping | None

_CacheValue = TypeVar("_CacheValue")


def _clone_mapping(source: JsonMapping) -> dict[str, Any]:
    return {key: value for key, value in source.items()}


def _coerce_dict(source: JsonLike) -> dict[str, Any]:
    if isinstance(source, Mapping):
        return _clone_mapping(source)
    if isinstance(source, str):
        stripped = source.strip()
        if stripped:
            if stripped.startswith("{") and stripped.endswith("}"):
                try:
                    parsed = json.loads(stripped)
                    if isinstance(parsed, Mapping):
                        return _clone_mapping(cast(JsonMapping, parsed))
                except (json.JSONDecodeError, TypeError, ValueError):
                    pass
            return {"raw": stripped}
    return {}


class HookPayloadBase:
    """Base class providing cached, safe getters."""

    def __init__(self, source: JsonLike) -> None:
        self._source = source
        self._data = _coerce_dict(source)
        self._cache: dict[str, Any] = {}

    def raw(self) -> JsonLike:
        return self._source

    def as_dict(self) -> dict[str, Any]:
        return _clone_mapping(self._data)

    def _cached(self, key: str, factory: Callable[[], _CacheValue]) -> _CacheValue:
        sentinel = object()
        cached = self._cache.get(key, sentinel)
        if cached is sentinel:
            try:
                cached = factory()
            except Exception:
                cached = None
            self._cache[key] = cached
        return cast(_CacheValue, cached)

    def _value(self, key: str) -> Any:
        return self._data.get(key)

    def _str(self, key: str) -> str | None:
        return clean_string(self._value(key))

    def _int(self, key: str) -> int | None:
        return to_int(self._value(key))

    def _float(self, key: str) -> float | None:
        return to_float(self._value(key))

    def _dict(self, key: str) -> dict[str, Any] | None:
        value = self._value(key)
        if isinstance(value, Mapping):
            mapping_value = cast(JsonMapping, value)
            return _clone_mapping(mapping_value)
        return None


class ExtractInfoPayload(HookPayloadBase):
    """Metadata returned by the preview extraction step."""

    @property
    def info(self) -> dict[str, Any]:
        return self._cached("info", lambda: self.as_dict())

    @property
    def playlist_index(self) -> int | None:
        return self._cached(
            "playlist_index",
            lambda: to_int(self._value("playlist_index")),
        )

    @property
    def playlist_count(self) -> int | None:
        return self._cached(
            "playlist_count",
            lambda: to_int(
                self._value("playlist_count")
                or self._value("n_entries")
                or self._value("playlist_length")
            ),
        )

    @property
    def entry_id(self) -> str | None:
        return self._cached("entry_id", lambda: clean_string(self._value("id")))


class ProgressHookPayload(HookPayloadBase):
    """Payload exposed by yt-dlp progress hooks."""

    @property
    def status(self) -> str | None:
        return self._cached("status", lambda: clean_string(self._value("status")))

    @property
    def downloaded_bytes(self) -> float | None:
        return self._cached(
            "downloaded_bytes", lambda: to_float(self._value("downloaded_bytes"))
        )

    @property
    def total_bytes(self) -> float | None:
        return self._cached(
            "total_bytes",
            lambda: to_float(
                self._value("total_bytes") or self._value("total_bytes_estimate")
            ),
        )

    @property
    def speed(self) -> float | None:
        return self._cached("speed", lambda: to_float(self._value("speed")))

    @property
    def eta(self) -> float | None:
        return self._cached("eta", lambda: to_float(self._value("eta")))

    @property
    def elapsed(self) -> float | None:
        return self._cached("elapsed", lambda: to_float(self._value("elapsed")))

    @property
    def tmpfilename(self) -> str | None:
        return self._cached("tmpfilename", lambda: self._str("tmpfilename"))

    @property
    def filename(self) -> str | None:
        return self._cached("filename", lambda: self._str("filename"))

    @property
    def percent(self) -> float | None:
        def _resolve() -> float | None:
            direct = self._float("percent")
            if direct is not None:
                return round(direct, 2)
            total = self.total_bytes
            downloaded = self.downloaded_bytes or 0.0
            if total and total > 0:
                return round((downloaded / total) * 100, 2)
            return None

        return self._cached("percent", _resolve)

    @property
    def message(self) -> str | None:
        def _resolve() -> str | None:
            for key in ("progress_msg", "status_text", "message", "info"):
                text = self._str(key)
                if text:
                    return text
            return None

        return self._cached("message", _resolve)

    @property
    def info_dict(self) -> dict[str, Any]:
        return self._cached("info_dict", lambda: self._dict("info_dict") or {})

    @property
    def playlist_index(self) -> int | None:
        def _resolve() -> int | None:
            candidates = (
                self._value("playlist_index"),
                self.info_dict.get("playlist_index"),
                self.info_dict.get("playlist_autonumber"),
            )
            for candidate in candidates:
                index = to_int(candidate)
                if index and index > 0:
                    return index
            return None

        return self._cached("playlist_index", _resolve)

    @property
    def playlist_count(self) -> int | None:
        def _resolve() -> int | None:
            candidates = (
                self._value("playlist_count"),
                self.info_dict.get("n_entries"),
                self.info_dict.get("playlist_count"),
                self.info_dict.get("playlist_length"),
            )
            for candidate in candidates:
                count = to_int(candidate)
                if count and count > 0:
                    return count
            return None

        return self._cached("playlist_count", _resolve)

    @property
    def entry_id(self) -> str | None:
        def _resolve() -> str | None:
            candidates = (
                self._value("playlist_current_entry_id"),
                self._value("playlist_entry_id"),
                self._value("current_entry_id"),
                self.info_dict.get("playlist_current_entry_id"),
                self.info_dict.get("playlist_entry_id"),
                self.info_dict.get("id"),
                self.info_dict.get("original_url"),
                self.info_dict.get("url"),
                self.info_dict.get("webpage_url"),
            )
            for candidate in candidates:
                text = clean_string(candidate)
                if text:
                    return text
            return None

        return self._cached("entry_id", _resolve)

    @property
    def postprocessor_progress(self) -> dict[str, Any]:
        return self._cached(
            "postprocessor_progress",
            lambda: self._dict("postprocessor_progress") or {},
        )

    @property
    def preprocessor_progress(self) -> dict[str, Any]:
        return self._cached(
            "preprocessor_progress",
            lambda: self._dict("preprocessor_progress") or {},
        )

    @property
    def current_item(self) -> int | None:
        return self._cached("current_item", lambda: self._int("current_item"))

    @property
    def total_items(self) -> int | None:
        return self._cached("total_items", lambda: self._int("total_items"))


class PostProcessorHookPayload(HookPayloadBase):
    """Payload exposed by yt-dlp postprocessor hooks."""

    @property
    def status(self) -> str | None:
        return self._cached("status", lambda: clean_string(self._value("status")))

    @property
    def postprocessor(self) -> str | None:
        def _resolve() -> str | None:
            for key in ("postprocessor", "postprocessor_name"):
                value = self._str(key)
                if value:
                    return value
            return None

        return self._cached("postprocessor", _resolve)

    @property
    def stage_percent(self) -> float | None:
        def _resolve() -> float | None:
            value = self._value("stage_percent")
            percent = to_float(value)
            if percent is not None:
                return round(percent, 2)
            status = (self.status or "").lower()
            if status == "finished":
                return 100.0
            if status == "started":
                return 0.0
            return None

        return self._cached("stage_percent", _resolve)

    @property
    def message(self) -> str | None:
        def _resolve() -> str | None:
            for key in ("message", "status_text", "info"):
                text = self._str(key)
                if text:
                    return text
            post = self.postprocessor
            status = self.status
            if post and status:
                lower = status.lower()
                if lower == "started":
                    return f"Iniciando {post}"
                if lower == "finished":
                    return f"{post} finalizado"
                if lower == "error":
                    return f"{post} falló"
            return None

        return self._cached("message", _resolve)

    @property
    def info_dict(self) -> dict[str, Any]:
        return self._cached("info_dict", lambda: self._dict("info_dict") or {})

    @property
    def playlist_index(self) -> int | None:
        def _resolve() -> int | None:
            candidates = (
                self._value("playlist_index"),
                self.info_dict.get("playlist_index"),
                self.info_dict.get("playlist_autonumber"),
            )
            for candidate in candidates:
                index = to_int(candidate)
                if index and index > 0:
                    return index
            return None

        return self._cached("playlist_index", _resolve)

    @property
    def entry_id(self) -> str | None:
        def _resolve() -> str | None:
            candidates = (
                self._value("playlist_current_entry_id"),
                self.info_dict.get("playlist_current_entry_id"),
                self.info_dict.get("id"),
                self.info_dict.get("original_url"),
                self.info_dict.get("url"),
                self.info_dict.get("webpage_url"),
            )
            for candidate in candidates:
                text = clean_string(candidate)
                if text:
                    return text
            return None

        return self._cached("entry_id", _resolve)


class PostHookPayload(HookPayloadBase):
    """Payload emitted after post-processing completes."""

    @property
    def status(self) -> str:
        return self._cached("status", lambda: "finished") or "finished"

    @property
    def message(self) -> str | None:
        return self._cached("message", lambda: clean_string(self._value("raw")))

    @property
    def entry_id(self) -> str | None:
        return None

    @property
    def playlist_index(self) -> int | None:
        return None
