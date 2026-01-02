#!/usr/bin/env python3
"""Scans locales and reports any placeholder mismatches vs English."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any

from fix_placeholder_tokens import (
    FILES,
    LOCALES_DIR,
    PLACEHOLDER_REGEX,
    _get_value,
    _iter_values,
)

BASE_LOCALE = "en"


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    base_payloads = {
        name: _load_json(LOCALES_DIR / BASE_LOCALE / name) for name in FILES
    }
    issues = []

    for locale_dir in sorted(
        p.name for p in LOCALES_DIR.iterdir() if p.is_dir() and p.name != BASE_LOCALE
    ):
        for file_name in FILES:
            target_path = LOCALES_DIR / locale_dir / file_name
            if not target_path.exists():
                continue
            target_data = _load_json(target_path)
            base_data = base_payloads[file_name]

            for path, base_value in _iter_values(base_data):
                if not isinstance(base_value, str):
                    continue
                placeholders = PLACEHOLDER_REGEX.findall(base_value)
                if not placeholders:
                    continue
                try:
                    target_value = _get_value(target_data, path)
                except Exception:
                    continue
                if not isinstance(target_value, str):
                    continue
                target_placeholders = PLACEHOLDER_REGEX.findall(target_value)
                if Counter(placeholders) == Counter(target_placeholders):
                    continue
                issues.append(
                    {
                        "locale": locale_dir,
                        "file": file_name,
                        "path": path,
                        "en": base_value,
                        "locale": target_value,
                        "en_placeholders": placeholders,
                        "locale_placeholders": target_placeholders,
                    }
                )

    report_path = LOCALES_DIR.parent / "placeholder_issues.json"
    report_path.write_text(
        json.dumps(issues, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        f"Locales scanned: {len({p.name for p in LOCALES_DIR.iterdir() if p.is_dir()})}"
    )
    print(f"Placeholder issues found: {len(issues)} (see {report_path})")


if __name__ == "__main__":
    main()
