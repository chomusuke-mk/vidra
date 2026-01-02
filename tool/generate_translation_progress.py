#!/usr/bin/env python3
"""Generates a translation progress snapshot for every locale."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Set

ROOT = Path(__file__).resolve().parents[1]
LOCALES_DIR = ROOT / "i18n" / "locales"
LANGUAGE_FILE = ROOT / "lib" / "constants" / "languages.dart"
OUTPUT_PATH = ROOT / "i18n" / "translation_progress.json"
COMPLETED_LIST_PATH = ROOT / "i18n" / "completed_locales.txt"
BASE_LOCALE = "en"
LOCALE_FILES = ("ui.jsonc", "errors.jsonc", "preferences.jsonc")


def _load_language_map() -> Dict[str, str]:
    text = LANGUAGE_FILE.read_text(encoding="utf-8")
    pattern = re.compile(r"'([a-z]{2})':\s*'([^']*)'")
    return {code: name for code, name in pattern.findall(text)}


def _load_json(path: Path) -> Mapping[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def _load_manual_completions() -> Set[str]:
    if not COMPLETED_LIST_PATH.exists():
        return set()
    codes: Set[str] = set()
    for raw_line in COMPLETED_LIST_PATH.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        codes.add(line.lower())
    return codes


def _flatten_strings(data: Any, prefix: str = "") -> Dict[str, str]:
    flat: Dict[str, str] = {}
    if isinstance(data, dict):
        for key, value in data.items():
            child = f"{prefix}.{key}" if prefix else str(key)
            flat.update(_flatten_strings(value, child))
    elif isinstance(data, list):
        for idx, value in enumerate(data):
            child = f"{prefix}[{idx}]" if prefix else f"[{idx}]"
            flat.update(_flatten_strings(value, child))
    else:
        if not prefix:
            return flat
        if data is None:
            flat[prefix] = ""
        else:
            flat[prefix] = str(data)
    return flat


def _has_value(value: str | None) -> bool:
    return bool(value and value.strip())


@dataclass
class FileStats:
    status: str
    total_keys: int
    translated_keys: int
    identical_to_base: int
    missing_keys: int


def _evaluate_file(
    locale: str,
    file_name: str,
    base_catalog: Mapping[str, str],
    target_catalog: Mapping[str, str],
) -> FileStats:
    total = len(base_catalog)
    if total == 0:
        return FileStats("n/a", 0, 0, 0, 0)

    missing = 0
    translated = 0
    identical = 0
    for key, base_value in base_catalog.items():
        target_value = target_catalog.get(key)
        if not _has_value(target_value):
            missing += 1
            continue
        if target_value == base_value:
            identical += 1
        else:
            translated += 1

    if missing:
        status = "missing"
    elif locale == BASE_LOCALE:
        status = "source"
    elif translated == 0:
        status = "untranslated"
    elif translated == total:
        status = "complete"
    else:
        status = "in_progress"

    return FileStats(status, total, translated, identical, missing)


def _overall_status(locale: str, file_stats: Iterable[FileStats]) -> str:
    if locale == BASE_LOCALE:
        return "source"
    statuses = [stats.status for stats in file_stats if stats.status != "n/a"]
    if not statuses:
        return "missing"
    if any(status == "missing" for status in statuses):
        return "missing"
    if all(status == "complete" for status in statuses):
        return "complete"
    if any(status == "in_progress" for status in statuses):
        return "in_progress"
    if all(status == "untranslated" for status in statuses):
        return "untranslated"
    return statuses[0]


def main() -> None:
    language_map = _load_language_map()
    locale_dirs = sorted([p.name for p in LOCALES_DIR.iterdir() if p.is_dir()])
    manual_completions = _load_manual_completions()

    base_payloads = {
        name: _flatten_strings(_load_json(LOCALES_DIR / BASE_LOCALE / name))
        for name in LOCALE_FILES
    }

    locales_payloads: Dict[str, Dict[str, Dict[str, str]]] = {}
    for locale in locale_dirs:
        locale_payloads: Dict[str, Dict[str, str]] = {}
        for file_name in LOCALE_FILES:
            target_path = LOCALES_DIR / locale / file_name
            locale_payloads[file_name] = _flatten_strings(_load_json(target_path))
        locales_payloads[locale] = locale_payloads

    records: List[Dict[str, Any]] = []
    status_counts: Dict[str, int] = {}

    for locale in locale_dirs:
        locale_payloads = locales_payloads[locale]
        file_stats: Dict[str, FileStats] = {
            file_name: _evaluate_file(
                locale,
                file_name,
                base_payloads[file_name],
                locale_payloads[file_name],
            )
            for file_name in LOCALE_FILES
        }

        overall = _overall_status(locale, file_stats.values())
        overridden = False
        if locale in manual_completions and overall != "missing":
            overall = "complete"
            overridden = True
        status_counts[overall] = status_counts.get(overall, 0) + 1

        record: Dict[str, Any] = {
            "code": locale,
            "language": language_map.get(locale, locale),
            "status": overall,
            "files": {
                name: {
                    "status": stats.status,
                    "total_keys": stats.total_keys,
                    "translated_keys": stats.translated_keys,
                    "identical_to_base": stats.identical_to_base,
                    "missing_keys": stats.missing_keys,
                }
                for name, stats in file_stats.items()
            },
        }
        if overridden:
            record["manual_override"] = True
        records.append(record)

    snapshot: Dict[str, Any] = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_locales": len(locale_dirs),
        "summary": status_counts,
        "locales": records,
    }

    OUTPUT_PATH.write_text(
        json.dumps(snapshot, ensure_ascii=True, indent=2) + "\n", encoding="utf-8"
    )


if __name__ == "__main__":
    main()
