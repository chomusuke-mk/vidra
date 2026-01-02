from __future__ import annotations

from dataclasses import dataclass
from operator import length_hint
from typing import Mapping, Optional, Sequence, Sized, Tuple, TYPE_CHECKING, cast

if TYPE_CHECKING:
    from ...core.downloader import YtDlpInfoResult, YtDlpInfoResultThumbnail


def _score_thumbnail(
    candidate: "YtDlpInfoResultThumbnail", index: int
) -> Tuple[float, int, int]:
    preference = candidate.get("preference")
    pref_score = 0.0
    if isinstance(preference, (int, float)):
        pref_score = float(preference)
    elif isinstance(preference, str):
        try:
            pref_score = float(preference.strip()) if preference.strip() else 0.0
        except ValueError:
            pref_score = 0.0
    width = candidate.get("width") or 0
    height = candidate.get("height") or 0
    area = width * height if width and height else 0
    return pref_score, area, -index


def _best_thumbnail(data: "YtDlpInfoResult") -> Optional[str]:
    direct = (
        data.get("thumbnail")
        or data.get("thumbnail_url")
        or data.get("preview_thumbnail")
    )
    if direct:
        return direct

    candidates = data.get("thumbnails")
    if not candidates:
        return None

    best_url: Optional[str] = None
    best_score: Optional[Tuple[float, int, int]] = None
    for index, candidate in enumerate(candidates):
        url = candidate.get("url")
        if not url:
            continue
        score = _score_thumbnail(candidate, index)
        if best_score is None or score > best_score:
            best_score = score
            best_url = url
    return best_url


def _looks_like_playlist(data: "YtDlpInfoResult") -> bool:
    entries = data.get("entries")
    if entries:
        return True
    entry_count = _extract_entry_count(data)
    if entry_count and entry_count > 0:
        return True
    playlist_meta = data.get("playlist")
    if isinstance(playlist_meta, Mapping) and playlist_meta:
        return True
    playlist_id = data.get("playlist_id")
    if playlist_id:
        return True
    entry_type = data.get("media_type") or data.get("_type")
    return entry_type in {"playlist", "multi_video", "multi_audio"}


def _extract_entry_count(data: "YtDlpInfoResult") -> Optional[int]:
    for key in ("playlist_count", "n_entries"):
        value = data.get(key)
        if isinstance(value, int) and value >= 0:
            return value
    entries = data.get("entries")
    if entries:
        try:
            return len(cast(Sized, entries))
        except TypeError:
            hint = length_hint(entries, 0)
            if hint > 0:
                return hint
    return None


def _extract_entry_payloads(data: "YtDlpInfoResult") -> Tuple["YtDlpInfoResult", ...]:
    entries = data.get("entries")
    if not entries:
        return ()
    return tuple(entries)


def _extract_tags(raw: Sequence[str] | None) -> Optional[Tuple[str, ...]]:
    if not raw:
        return None
    filtered = [entry for entry in raw if entry]
    return tuple(filtered) if filtered else None


@dataclass(frozen=True)
class Info:
    """Normalized view over yt-dlp playlist/video metadata payloads.

    Attributes:
        id: Stable identifier resolved from video or playlist fields.
        title: Human readable title for the current entry.
        description: Long form description if provided by the source.
    url: Canonical web URL pointing to the entry or playlist.
    extractor: yt-dlp extractor name describing the source platform.
    extractor_key: Internal extractor key reported by yt-dlp.
        thumbnail: Best-effort direct thumbnail URL.
        media_type: Raw ``media_type`` (falling back to ``_type`` when needed).
        is_playlist: Flag indicating whether this payload represents a playlist.
        availability: Visibility reported by the source platform.
        live_status: State reported for live streams.
        duration: Duration in seconds when available.
        duration_string: Human readable duration string when provided.
        tags: Tuple of normalized tags when provided.
    entry_count: Number of child entries when the payload is a playlist.
    playlist_index: Position within a playlist when representing a playlist entry.
    entries: Tuple with fast metadata for each playlist entry if expanded.
        view_count: Total views reported by the hosting platform.
        like_count: Total likes reported by the hosting platform.
        channel: Public channel name associated with the entry.
        channel_id: Channel identifier string.
        channel_url: Canonical URL to the channel page.
        channel_follower_count: Reported follower/subscriber count.
        channel_is_verified: Whether the channel is verified by the platform.
        uploader: Display name for the uploader account.
        uploader_id: Stable identifier for the uploader account.
        uploader_url: Canonical URL to the uploader profile.
        release_date: Date string in ``YYYYMMDD`` or similar extracted format.
        release_year: Four digit release year when available.
        timestamp: Unix timestamp for the release or upload moment.
        webpage_url_basename: Final component of the webpage path.
        webpage_url_domain: Domain extracted from ``webpage_url``.
    """

    id: Optional[str]
    title: Optional[str]
    description: Optional[str]
    url: Optional[str]
    extractor: Optional[str]
    extractor_key: Optional[str]
    thumbnail: Optional[str]
    media_type: Optional[str]
    is_playlist: bool
    availability: Optional[str]
    live_status: Optional[str]
    duration: Optional[int]
    duration_string: Optional[str]
    tags: Optional[Tuple[str, ...]]
    entry_count: Optional[int]
    playlist_index: Optional[int]
    entries: Optional[Tuple["Info", ...]]
    view_count: Optional[int]
    like_count: Optional[int]
    channel: Optional[str]
    channel_id: Optional[str]
    channel_url: Optional[str]
    channel_follower_count: Optional[int]
    channel_is_verified: Optional[bool]
    uploader: Optional[str]
    uploader_id: Optional[str]
    uploader_url: Optional[str]
    release_date: Optional[str]
    release_year: Optional[int]
    timestamp: Optional[int]
    webpage_url_basename: Optional[str]
    webpage_url_domain: Optional[str]

    @classmethod
    def from_info(cls, data: "YtDlpInfoResult") -> "Info":
        """Build a normalized Info object performing deep playlist traversal."""

        return cls._construct(data, recursive=True)

    @classmethod
    def fast_info(cls, data: "YtDlpInfoResult") -> "Info":
        """Build a normalized Info object without traversing nested entries."""

        return cls._construct(data, recursive=False)

    @classmethod
    def _construct(cls, data: "YtDlpInfoResult", *, recursive: bool) -> "Info":
        is_playlist = _looks_like_playlist(data)
        entry_count = _extract_entry_count(data) if is_playlist else None

        playlist_index = (
            data.get("playlist_index")
            or data.get("playlist_autonumber")
            or data.get("__last_playlist_index")
        )

        entries_payload: Optional[Tuple[Info, ...]] = None
        if recursive and is_playlist:
            children = [
                cls._construct(entry_payload, recursive=False)
                for entry_payload in _extract_entry_payloads(data)
            ]
            if children:
                entries_payload = tuple(children)
                if entry_count is None:
                    entry_count = len(entries_payload)

        tags = _extract_tags(data.get("tags"))
        release_year_value = data.get("release_year")
        release_year: Optional[int]
        if isinstance(release_year_value, bool):
            release_year = int(release_year_value)
        elif isinstance(release_year_value, int):
            release_year = release_year_value
        elif isinstance(release_year_value, str):
            try:
                release_year = int(release_year_value.strip())
            except ValueError:
                release_year = None
        else:
            release_year = None

        return cls(
            id=data.get("id") or data.get("playlist_id") or data.get("display_id"),
            title=data.get("title"),
            description=data.get("description"),
            url=(
                data.get("webpage_url")
                or data.get("playlist_webpage_url")
                or data.get("original_url")
                or data.get("url")
            ),
            extractor=data.get("extractor"),
            extractor_key=data.get("extractor_key"),
            thumbnail=_best_thumbnail(data),
            media_type=data.get("media_type") or data.get("_type"),
            is_playlist=is_playlist,
            availability=data.get("availability"),
            live_status=data.get("live_status"),
            duration=data.get("duration"),
            duration_string=data.get("duration_string"),
            tags=tags,
            entry_count=entry_count,
            playlist_index=playlist_index,
            entries=entries_payload,
            view_count=data.get("view_count"),
            like_count=data.get("like_count"),
            channel=data.get("channel") or data.get("playlist_channel"),
            channel_id=data.get("channel_id") or data.get("playlist_channel_id"),
            channel_url=data.get("channel_url") or data.get("playlist_channel_url"),
            channel_follower_count=data.get("channel_follower_count"),
            channel_is_verified=data.get("channel_is_verified"),
            uploader=data.get("uploader") or data.get("playlist_uploader"),
            uploader_id=data.get("uploader_id") or data.get("playlist_uploader_id"),
            uploader_url=data.get("uploader_url") or data.get("playlist_uploader_url"),
            release_date=(
                data.get("release_date")
                or data.get("modified_date")
                or data.get("upload_date")
            ),
            release_year=release_year,
            timestamp=data.get("timestamp") or data.get("release_timestamp"),
            webpage_url_basename=data.get("webpage_url_basename"),
            webpage_url_domain=data.get("webpage_url_domain"),
        )
