from __future__ import annotations

import sys
from pathlib import Path
from typing import Generator, cast
from unittest import TestCase

APP_ROOT = Path(__file__).resolve().parents[1]
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))

from src.core.contract.info import Info
from src.core.downloader import (
    YtDlpInfoResult,
    looks_like_playlist as adapter_looks_like_playlist,
)

class PlaylistDetectionTests(TestCase):
    def test_info_detects_playlist_without_entries_via_type_hint(self) -> None:
        payload = cast(
            YtDlpInfoResult,
            {
                "_type": "playlist",
                "playlist_count": 5,
                "id": "pl-123",
            },
        )

        info = Info.fast_info(payload)

        self.assertTrue(info.is_playlist)

    def test_info_detects_playlist_without_entries_via_count(self) -> None:
        payload = cast(
            YtDlpInfoResult,
            {
                "playlist_count": 3,
                "id": "pl-456",
            },
        )

        info = Info.fast_info(payload)

        self.assertTrue(info.is_playlist)

    def test_adapter_detects_playlist_from_meta_mapping(self) -> None:
        payload = cast(
            YtDlpInfoResult,
            {
                "playlist": {"id": "pl-meta", "title": "Mix"},
                "id": "video-1",
            },
        )

        self.assertTrue(adapter_looks_like_playlist(payload))

    def test_single_video_payload_remains_non_playlist(self) -> None:
        payload = cast(
            YtDlpInfoResult,
            {
                "id": "video-2",
                "title": "Song",
                "webpage_url": "https://example.test/watch?v=1",
            },
        )

        self.assertFalse(adapter_looks_like_playlist(payload))
        self.assertFalse(Info.fast_info(payload).is_playlist)

    def test_generator_entries_do_not_raise(self) -> None:
        def _entry_stream() -> Generator[YtDlpInfoResult, None, None]:
            for index in range(3):
                yield cast(
                    YtDlpInfoResult,
                    {
                        "id": f"video-{index}",
                        "title": f"Video {index}",
                    },
                )

        payload = cast(
            YtDlpInfoResult,
            {
                "_type": "playlist",
                "id": "mix-1",
                "entries": _entry_stream(),
            },
        )

        info = Info.fast_info(payload)

        self.assertTrue(info.is_playlist)
        self.assertIsNone(info.entry_count)
