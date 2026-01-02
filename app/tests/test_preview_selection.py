from __future__ import annotations

from typing import Callable, Dict, cast

from src.download.mixins.preview import PreviewMixin
from src.download.mixins.protocols import PreviewManagerProtocol
from src.download.models import DownloadJob, DownloadJobOptionsPayload
from src.models.download.mixins.preview import PreviewMetadataPayload


class _PreviewMixinStub(PreviewMixin):
    """Minimal stub exposing the selection helper for unit tests."""

    def _preview_manager(self) -> PreviewManagerProtocol:  # pragma: no cover - not used by tests
        raise RuntimeError("preview manager not available in tests")


def _make_job(options: Dict[str, object] | None = None) -> DownloadJob:
    return DownloadJob(
        job_id="job-test",
        urls=["https://example.com/watch?v=vid"],
        options=cast(DownloadJobOptionsPayload, dict(options or {})),
    )


def _call_requires_selection(
    mixin: PreviewMixin,
    job: DownloadJob,
    preview_metadata: PreviewMetadataPayload,
) -> bool:
    method = cast(
        Callable[[DownloadJob, PreviewMetadataPayload], bool],
        getattr(mixin, "_requires_playlist_selection"),
    )
    return method(job, preview_metadata)


def test_requires_selection_when_collecting_without_counts() -> None:
    mixin = _PreviewMixinStub()
    job = _make_job()
    preview_metadata: PreviewMetadataPayload = {
        "is_playlist": True,
        "playlist": {
            "playlist_id": "RD123",
            "is_collecting_entries": True,
            "received_count": 0,
        },
    }

    assert _call_requires_selection(mixin, job, preview_metadata) is True


def test_respects_playlist_items_filter_even_with_collecting_flag() -> None:
    mixin = _PreviewMixinStub()
    job = _make_job(options={"playlist_items": "1-3"})
    preview_metadata: PreviewMetadataPayload = {
        "playlist": {
            "playlist_id": "RD234",
            "is_collecting_entries": True,
            "received_count": 0,
        },
    }

    assert _call_requires_selection(mixin, job, preview_metadata) is False


def test_uses_preview_entry_count_hint_when_playlist_payload_missing() -> None:
    mixin = _PreviewMixinStub()
    job = _make_job()
    preview_metadata: PreviewMetadataPayload = {
        "is_playlist": True,
        "playlist_entry_count": 4,
        "playlist": {
            "playlist_id": "RD345",
            "is_collecting_entries": True,
            "received_count": 0,
        },
    }

    assert _call_requires_selection(mixin, job, preview_metadata) is True


def test_does_not_require_selection_for_single_entry_playlist() -> None:
    mixin = _PreviewMixinStub()
    job = _make_job()
    preview_metadata: PreviewMetadataPayload = {
        "playlist": {
            "playlist_id": "RD456",
            "entry_count": 1,
            "received_count": 1,
        },
    }

    assert _call_requires_selection(mixin, job, preview_metadata) is False
