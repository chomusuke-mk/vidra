#!/usr/bin/env python3
"""Translates pending locales using deep-translator."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Tuple

from deep_translator import GoogleTranslator  # type: ignore[import]
from deep_translator.exceptions import (  # type: ignore[import-untyped]
    LanguageNotSupportedException,
    NotValidPayload,
    RequestError,
    TooManyRequests,
    TranslationNotFound,
)

ROOT = Path(__file__).resolve().parents[1]
LOCALES_DIR = ROOT / "i18n" / "locales"
BASE_LOCALE = "en"
LOCALE_FILES = ("ui.jsonc", "errors.jsonc", "preferences.jsonc")
COMPLETED_PATH = ROOT / "i18n" / "completed_locales.txt"
PLACEHOLDER_PATTERN = re.compile(r"\{[^{}]+\}")


def _load_completed() -> List[str]:
    if not COMPLETED_PATH.exists():
        return []
    codes: List[str] = []
    for line in COMPLETED_PATH.read_text(encoding="utf-8").splitlines():
        cleaned = line.split("#", 1)[0].strip().lower()
        if cleaned:
            codes.append(cleaned)
    return codes


def _append_completed(code: str) -> None:
    with COMPLETED_PATH.open("a", encoding="utf-8") as handle:
        handle.write(f"{code}\n")


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _save_json(path: Path, data: Any) -> None:
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def _iter_strings(
    node: Any, path: Tuple[Any, ...] = ()
) -> Iterable[Tuple[Tuple[Any, ...], str]]:
    if isinstance(node, dict):
        for key, value in node.items():
            yield from _iter_strings(value, path + (key,))
    elif isinstance(node, list):
        for idx, value in enumerate(node):
            yield from _iter_strings(value, path + (idx,))
    elif isinstance(node, str):
        yield path, node


def _set_value(root: Any, path: Tuple[Any, ...], value: str) -> None:
    node = root
    for key in path[:-1]:
        node = node[key]
    node[path[-1]] = value


def _protect_placeholders(text: str) -> Tuple[str, List[str]]:
    captured: List[str] = []

    def _replace(match: re.Match[str]) -> str:
        captured.append(match.group(0))
        return f"__PH_{len(captured) - 1}__"

    return PLACEHOLDER_PATTERN.sub(_replace, text), captured


def _restore_placeholders(text: str, placeholders: List[str]) -> str:
    restored = text
    for idx, value in enumerate(placeholders):
        restored = restored.replace(f"__PH_{idx}__", value)
    return restored


def _translate_value(text: str, translator: GoogleTranslator) -> str:
    safe_text, placeholders = _protect_placeholders(text)
    try:
        translated = translator.translate(safe_text)
    except (
        TranslationNotFound,
        LanguageNotSupportedException,
        NotValidPayload,
        RequestError,
        TooManyRequests,
        Exception,
    ):  # noqa: BLE001
        return text
    if not isinstance(translated, str):
        translated = str(translated)
    translated = _restore_placeholders(translated, placeholders)
    return translated


def _translate_file(locale: str, translator: GoogleTranslator, file_name: str) -> None:
    base_path = LOCALES_DIR / BASE_LOCALE / file_name
    target_path = LOCALES_DIR / locale / file_name
    base_data = _load_json(base_path)
    if target_path.exists():
        target_data = _load_json(target_path)
    else:
        target_data = json.loads(json.dumps(base_data))

    pending_paths = [path for path, _ in _iter_strings(base_data)]

    for path in pending_paths:
        base_value = base_data
        for key in path:
            base_value = base_value[key]
        target_value = target_data
        for key in path:
            target_value = target_value[key]
        if (
            isinstance(target_value, str)
            and target_value.strip()
            and target_value != base_value
        ):
            continue
        translated = _translate_value(base_value, translator)
        _set_value(target_data, path, translated)

    _save_json(target_path, target_data)


def _build_translator(locale: str) -> GoogleTranslator:
    attempts = [locale]
    if "-" in locale:
        attempts.append(locale.split("-", 1)[0])
    attempts.append(locale.split("_", 1)[0])
    for code in attempts:
        try:
            return GoogleTranslator(source="en", target=code)
        except Exception:  # noqa: BLE001
            continue
    raise RuntimeError(f"Unable to initialize translator for {locale}")


def translate_locale(locale: str) -> None:
    try:
        translator = _build_translator(locale)
    except RuntimeError:
        print(f"Translator unavailable for {locale}; keeping English strings.")
        for file_name in LOCALE_FILES:
            base_path = LOCALES_DIR / BASE_LOCALE / file_name
            target_path = LOCALES_DIR / locale / file_name
            target_path.write_text(
                base_path.read_text(encoding="utf-8"), encoding="utf-8"
            )
        _append_completed(locale)
        return

    for file_name in LOCALE_FILES:
        print(f"Translating {locale}/{file_name}")
        _translate_file(locale, translator, file_name)

    _append_completed(locale)
    print(f"Locale {locale} completed.")


def main() -> None:
    completed = set(_load_completed())
    locale_dirs = sorted(p.name for p in LOCALES_DIR.iterdir() if p.is_dir())
    pending = [
        code for code in locale_dirs if code not in completed and code != BASE_LOCALE
    ]
    if not pending:
        print("No pending locales.")
        return

    selected = sys.argv[1:] if len(sys.argv) > 1 else pending
    for locale in selected:
        if locale not in pending:
            print(f"Skipping {locale}; already completed or missing.")
            continue
        translate_locale(locale)


if __name__ == "__main__":
    main()
