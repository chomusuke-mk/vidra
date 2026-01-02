from typing import Any, cast

from src.models.api.requests import DownloadJobOptionsRequest


def test_options_request_preserves_unknown_fields() -> None:
    request = DownloadJobOptionsRequest(playlist=True)
    request_extras = cast(Any, request)
    request_extras.extract_audio = True
    request_extras.audio_format = "mp3"
    request_extras.audio_quality = 0

    payload = request.to_payload()

    assert payload["playlist"] is True
    assert payload["extract_audio"] is True
    assert payload["audio_format"] == "mp3"
    assert payload["audio_quality"] == 0


def test_options_request_skips_none_unknown_fields() -> None:
    request = DownloadJobOptionsRequest(playlist=False)
    request_extras = cast(Any, request)
    request_extras.extract_audio = None
    request_extras.audio_format = None

    payload = request.to_payload()

    assert "extract_audio" not in payload
    assert "audio_format" not in payload
    assert payload["playlist"] is False
