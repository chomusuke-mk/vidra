from src.core.utils import build_options_config


def test_build_options_config_returns_none_for_empty_payload() -> None:
    assert build_options_config({}) is None


def test_build_options_config_normalizes_format_string() -> None:
    config = build_options_config({"format": "bestvideo+bestaudio/best"})
    assert config is not None
    assert config.format == ["bestvideo+bestaudio", "best"]


def test_build_options_config_wraps_output_string() -> None:
    template = "%(title)s - %(artist)s[%(id)s].%(ext)s"
    config = build_options_config({"output": template})
    assert config is not None
    assert config.output == [template]
