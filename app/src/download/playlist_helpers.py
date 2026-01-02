"""Helpers estrechamente ligados al flujo de playlist y yt-dlp."""

from __future__ import annotations

from typing import Iterable, Mapping, Optional, Sequence, Set, Tuple, cast

from ..core.contract import Info
from ..utils import normalize_percent, to_int
from ..core.downloader import YtDlpInfoResult
from ..models.shared import JSONValue
from ..models.download.mixins.preview import PreviewThumbnailPayload


def select_best_thumbnail_url(
    thumbnails: Sequence[PreviewThumbnailPayload],
) -> Optional[str]:
    if not thumbnails:
        return None

    def _sort_key(item: PreviewThumbnailPayload) -> Tuple[int, int]:
        return (
            to_int(item.get("width")) or 0,
            to_int(item.get("height")) or 0,
        )

    candidates = [thumb for thumb in thumbnails if thumb.get("url")]
    if not candidates:
        return None
    candidates.sort(key=_sort_key, reverse=True)
    top = candidates[0]
    url = top.get("url")
    return str(url) if isinstance(url, str) else None


def gather_thumbnail_entries(
    sources: Iterable[YtDlpInfoResult],
) -> list[PreviewThumbnailPayload]:
    thumbnails: list[PreviewThumbnailPayload] = []
    seen: Set[str] = set()
    for source in sources:
        raw_thumbnails = source.get("thumbnails")
        if not isinstance(raw_thumbnails, list):
            continue
        for thumb in raw_thumbnails:
            url = thumb.get("url")
            if not isinstance(url, str):
                continue

            normalized_url = url.strip()
            if not normalized_url or normalized_url in seen:
                continue

            item: PreviewThumbnailPayload = {"url": normalized_url}

            width = to_int(thumb.get("width"))
            if width is not None:
                item["width"] = width

            height = to_int(thumb.get("height"))
            if height is not None:
                item["height"] = height

            thumb_id = thumb.get("id")
            if isinstance(thumb_id, str) and thumb_id.strip():
                item["id"] = thumb_id.strip()

            thumbnails.append(item)
            seen.add(normalized_url)
    return thumbnails


def normalize_selected_indices(
    value: Sequence[object] | str | None,
) -> Set[int]:
    indices: Set[int] = set()
    if value is None:
        return indices
    if isinstance(value, str):
        if value.strip():
            indices.update(parse_playlist_items_spec(value))
        return indices
    for item in value:
        index = to_int(item)
        if index is not None and index > 0:
            indices.add(index)
    return indices


def parse_playlist_items_spec(spec: str) -> Set[int]:
    indices: Set[int] = set()
    if not spec:
        return indices
    for raw_part in spec.split(","):
        part = raw_part.strip()
        if not part:
            continue
        if "-" in part:
            start_text, end_text = part.split("-", 1)
            start_value = to_int(start_text)
            end_value = to_int(end_text)
            if start_value is None or start_value <= 0:
                continue
            if end_value is None or end_value < start_value:
                continue
            for index_value in range(start_value, end_value + 1):
                indices.add(index_value)
            continue
        value = to_int(part)
        if value is not None and value > 0:
            indices.add(value)
    return indices


def select_primary_entry(
    info: YtDlpInfoResult | dict[str, object] | None,
) -> Optional[YtDlpInfoResult]:
    if not isinstance(info, dict):
        return None
    info_dict = cast(YtDlpInfoResult, dict(info))
    entries_value = info_dict.get("entries")
    if isinstance(entries_value, list):
        for candidate in entries_value:
            return candidate
    elif entries_value is not None:
        try:
            for candidate in cast(Iterable[object], entries_value):
                if isinstance(candidate, Mapping):
                    candidate_map = cast(Mapping[str, object], candidate)
                    return cast(YtDlpInfoResult, dict(candidate_map))
        except TypeError:
            pass
    return info_dict


def normalize_thumbnail_list(
    thumbnails_value: Sequence[Mapping[str, JSONValue]] | None,
) -> list[PreviewThumbnailPayload]:
    sanitized: list[PreviewThumbnailPayload] = []
    if not thumbnails_value:
        return sanitized
    for entry in thumbnails_value:
        entry_dict = entry
        url = entry_dict.get("url")
        if not isinstance(url, str) or not url.strip():
            continue
        item: PreviewThumbnailPayload = {"url": url.strip()}
        width = to_int(entry_dict.get("width"))
        height = to_int(entry_dict.get("height"))
        thumb_id = entry_dict.get("id")
        if width is not None and width > 0:
            item["width"] = width
        if height is not None and height > 0:
            item["height"] = height
        if isinstance(thumb_id, str) and thumb_id.strip():
            item["id"] = thumb_id.strip()
        sanitized.append(item)
    return sanitized


def extract_stage_percent(data: Mapping[str, JSONValue]) -> Optional[float]:
    candidate_keys = [
        "stage_percent",
        "progress_percent",
        "progress",
        "percent",
        "percent_str",
    ]
    for key in candidate_keys:
        if key in data:
            value = normalize_percent(data.get(key))
            if value is not None:
                return value
    return None


def extract_stage_items(
    data: Mapping[str, JSONValue],
) -> Tuple[Optional[int], Optional[int]]:
    for current_key, total_key in (
        ("progress_idx", "progress_total"),
        ("progress_current", "progress_total"),
    ):
        if current_key in data and total_key in data:
            current = to_int(data.get(current_key))
            total = to_int(data.get(total_key))
            return current, total
    return None, None


def is_playlist(info: YtDlpInfoResult | dict[str, object] | None) -> bool:
    if not isinstance(info, dict):
        return False
    info_dict = cast(YtDlpInfoResult, dict(info))
    try:
        model = Info.fast_info(info_dict)
    except Exception:
        entry_type = str(info_dict.get("_type") or "").lower()
        if entry_type in {"playlist", "multi_video", "multi_audio"}:
            return True
        if info_dict.get("playlist"):
            return True
        entries = info_dict.get("entries")
        if isinstance(entries, list) and entries:
            return True
        try:
            iterable_entries = cast(Iterable[object], entries)
            first = next(iter(iterable_entries), None)
            return isinstance(first, dict)
        except Exception:
            return False
    return model.is_playlist


__all__ = [
    "select_best_thumbnail_url",
    "gather_thumbnail_entries",
    "normalize_selected_indices",
    "parse_playlist_items_spec",
    "select_primary_entry",
    "normalize_thumbnail_list",
    "extract_stage_percent",
    "extract_stage_items",
    "is_playlist",
]
