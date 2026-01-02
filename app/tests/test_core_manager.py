from __future__ import annotations

from typing import Any, Dict, List, Sequence, cast

import pytest

import src.core.manager as core_manager
from src.core.manager import Manager
from src.core.downloader import ExtractInformationResult, YtDlpInfoResult
from src.core.utils import OptionsConfig


def _make_extract_information_result() -> ExtractInformationResult:
    sample_info = cast(
        YtDlpInfoResult,
        {
            "title": "Sample Playlist",
            "entries": [
                {
                    "id": "video-1",
                    "title": "Video 1",
                }
            ],
            "playlist_count": 1,
            "_type": "playlist",
        },
    )
    return ExtractInformationResult(
        info=sample_info,
        extractor="youtube",
        extractor_key="YoutubeTab",
        is_playlist=True,
        entry_count=1,
    )


def test_extract_info_exposes_raw_payload(monkeypatch: pytest.MonkeyPatch) -> None:
    manager = Manager()
    captured_calls: List[Dict[str, Any]] = []

    def _fake_extract_information(
        urls: str | Sequence[str],
        *,
        options: OptionsConfig | None = None,
        download: bool = False,
    ) -> ExtractInformationResult:
        captured_calls.append(
            {
                "urls": urls,
                "options": options,
                "download": download,
            }
        )
        return _make_extract_information_result()

    monkeypatch.setattr(
        core_manager,
        "extract_information",
        _fake_extract_information,
    )

    result = manager.extract_info(
        ["https://example.com/playlist"], options=None, download=False
    )

    assert result.raw is not None
    assert result.raw.get("title") == "Sample Playlist"
    assert result.entry_count == 1
    assert captured_calls[0]["download"] is False
