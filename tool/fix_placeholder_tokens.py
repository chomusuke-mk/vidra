#!/usr/bin/env python3
"""Restores {placeholder} tokens corrupted during translation."""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path
from typing import Any, Dict, Iterable, Tuple

ROOT = Path(__file__).resolve().parents[1]
LOCALES_DIR = ROOT / "i18n" / "locales"
BASE_LOCALE = "en"
FILES = ("ui.jsonc", "errors.jsonc", "preferences.jsonc")
PLACEHOLDER_REGEX = re.compile(r"\{[^{}]+\}")
NAMED_TOKEN_PATTERN = re.compile(r"_{1,}\s*[A-Za-z]*\s*\{([^{}]+)\}", re.UNICODE)
TOKEN_PATTERNS = [
    re.compile(r"_{1,}\s*[A-Za-z]*\s*(?P<idx>\d+)\s*_{1,}", re.UNICODE),
    re.compile(r"_{1,}\s*[A-Za-z]*\s*(?P<idx>\d+)(?!\d)", re.UNICODE),
    re.compile(r"_{2,}\s*(?P<idx>\d+)\b", re.UNICODE),
]
FALLBACK_PATTERN = re.compile(r"_{2,}", re.UNICODE)


def _load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def _save_json(path: Path, data: Any) -> None:
    path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def _iter_values(
    node: Any, path: Tuple[Any, ...] = ()
) -> Iterable[Tuple[Tuple[Any, ...], Any]]:
    if isinstance(node, dict):
        for key, value in node.items():
            yield from _iter_values(value, path + (key,))
    elif isinstance(node, list):
        for idx, value in enumerate(node):
            yield from _iter_values(value, path + (idx,))
    else:
        yield path, node


def _placeholders_in(text: str) -> Tuple[str, ...]:
    return tuple(match.group(0) for match in PLACEHOLDER_REGEX.finditer(text))


def _replace_tokens(text: str, placeholders: Tuple[str, ...]) -> str:
    if not placeholders:
        return text

    updated = text

    for pattern in TOKEN_PATTERNS:

        def repl(match: re.Match[str]) -> str:
            idx = int(match.group("idx"))
            if 0 <= idx < len(placeholders):
                return placeholders[idx]
            return match.group(0)

        updated = pattern.sub(repl, updated)

    return updated


def _restore_named_tokens(text: str, placeholder_map: Dict[str, str]) -> str:
    if not placeholder_map:
        return text

    def repl(match: re.Match[str]) -> str:
        name = match.group(1).strip()
        canonical = placeholder_map.get(name)
        if canonical:
            return canonical
        return match.group(0)

    return NAMED_TOKEN_PATTERN.sub(repl, text)


def _get_value(root: Any, path: Tuple[Any, ...]) -> Any:
    node = root
    for key in path:
        node = node[key]
    return node


def _set_value(root: Any, path: Tuple[Any, ...], value: Any) -> None:
    node = root
    for key in path[:-1]:
        node = node[key]
    node[path[-1]] = value


def _missing_placeholders(
    placeholders: Tuple[str, ...],
    base_counter: Counter,
    restored_counter: Counter,
) -> Tuple[str, ...]:
    diff = base_counter - restored_counter
    if not diff:
        return ()
    remaining = diff.copy()
    missing = []
    for placeholder in placeholders:
        if remaining[placeholder] > 0:
            missing.append(placeholder)
            remaining[placeholder] -= 1
    return tuple(missing)


def _fallback_replace(text: str, missing: Tuple[str, ...]) -> str:
    if not missing:
        return text

    idx = 0

    def repl(match: re.Match[str]) -> str:
        nonlocal idx
        if idx >= len(missing):
            return match.group(0)
        value = missing[idx]
        idx += 1
        return value

    updated = FALLBACK_PATTERN.sub(repl, text)
    if idx < len(missing):
        pending = " ".join(missing[idx:])
        updated = f"{updated} {pending}" if pending else updated
    return updated


def main() -> None:
    base_payloads: Dict[str, Any] = {
        name: _load_json(LOCALES_DIR / BASE_LOCALE / name) for name in FILES
    }

    total_fixed = 0
    unresolved = []

    for locale_dir in sorted(
        p.name for p in LOCALES_DIR.iterdir() if p.is_dir() and p.name != BASE_LOCALE
    ):
        locale_fixed = False
        for file_name in FILES:
            target_path = LOCALES_DIR / locale_dir / file_name
            if not target_path.exists():
                continue
            target_data = _load_json(target_path)
            base_data = base_payloads[file_name]
            changed = False

            for path, base_value in _iter_values(base_data):
                if not isinstance(base_value, str):
                    continue
                placeholders = _placeholders_in(base_value)
                if not placeholders:
                    continue
                placeholder_map = {
                    placeholder.strip("{}"): placeholder for placeholder in placeholders
                }
                try:
                    target_value = _get_value(target_data, path)
                except Exception:
                    continue
                if not isinstance(target_value, str):
                    continue
                base_counter = Counter(placeholders)
                target_counter = Counter(PLACEHOLDER_REGEX.findall(target_value))
                needs_fix = base_counter != target_counter or bool(
                    NAMED_TOKEN_PATTERN.search(target_value)
                )
                if not needs_fix:
                    continue
                restored = target_value
                if base_counter != target_counter:
                    restored = _replace_tokens(restored, placeholders)
                restored = _restore_named_tokens(restored, placeholder_map)
                restored_counter = Counter(PLACEHOLDER_REGEX.findall(restored))
                if restored_counter != base_counter:
                    missing = _missing_placeholders(
                        placeholders, base_counter, restored_counter
                    )
                    restored = _fallback_replace(restored, missing)
                    restored_counter = Counter(PLACEHOLDER_REGEX.findall(restored))
                if restored_counter != base_counter:
                    unresolved.append((locale_dir, file_name, path, target_value))
                    continue
                _set_value(target_data, path, restored)
                changed = True
                locale_fixed = True
                total_fixed += 1

            if changed:
                _save_json(target_path, target_data)

        if locale_fixed:
            print(f"Restored placeholders in {locale_dir}")

    print(f"Total strings fixed: {total_fixed}")
    if unresolved:
        report = ROOT / "i18n" / "placeholder_unresolved.json"
        payload = [
            {
                "locale": locale,
                "file": file_name,
                "path": path,
                "value": value,
            }
            for locale, file_name, path, value in unresolved
        ]
        report.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(f"Unresolved placeholders: {len(unresolved)} (see {report})")


if __name__ == "__main__":
    main()
