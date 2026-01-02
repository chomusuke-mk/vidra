#!/usr/bin/env python3
"""Automates the multi-locale i18n migration workflow."""

from __future__ import annotations

import json
import subprocess
import sys
from copy import deepcopy
from pathlib import Path
from shutil import which
from typing import Any, Dict, List, Tuple, cast

ROOT = Path(__file__).resolve().parents[1]
STATUS_PATH = ROOT / "i18n_migration_status.json"
LOCALES_DIR = ROOT / "i18n" / "locales"
ENV_PATH = ROOT / ".env"
BASE_LOCALE = "en"
LOCALE_FILES = ("ui.jsonc", "errors.jsonc", "preferences.jsonc")
FALLBACK_KEYS = ("fallback", "fallback_language")


class MigrationError(RuntimeError):
    """Indicates that the migration loop failed."""


def _load_status() -> Dict[str, Any]:
    text = STATUS_PATH.read_text(encoding="utf-8")
    data = json.loads(text)
    data.setdefault("completed", [])
    data.setdefault("current_target", None)
    return data


def _save_status(data: Dict[str, Any]) -> None:
    STATUS_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def _load_env_lines() -> List[str]:
    if not ENV_PATH.exists():
        raise MigrationError(".env file is required for this workflow")
    return ENV_PATH.read_text(encoding="utf-8").splitlines()


def _ensure_fallback_entry(lines: List[str]) -> Tuple[str, int, str]:
    fallback_key = FALLBACK_KEYS[0]
    for idx, raw in enumerate(lines):
        stripped = raw.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        if key.strip().lower() in FALLBACK_KEYS:
            fallback_key = key.strip()
            return value.strip(), idx, fallback_key
    # If we reach here, append a new fallback entry defaulting to English.
    lines.append(f"{fallback_key}=en")
    return "en", len(lines) - 1, fallback_key


def _update_env_fallback(lines: List[str], idx: int, key: str, locale: str) -> None:
    normalized = locale.strip().lower()
    lines[idx] = f"{key}={normalized}"
    ENV_PATH.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Updated {ENV_PATH.name} fallback -> {normalized}")


def _load_base_payloads() -> Dict[str, Any]:
    base_dir = LOCALES_DIR / BASE_LOCALE
    if not base_dir.exists():
        raise MigrationError(f"Missing base locale directory: {base_dir}")
    payloads: Dict[str, Any] = {}
    for file_name in LOCALE_FILES:
        path = base_dir / file_name
        if not path.exists():
            raise MigrationError(f"Missing base file: {path}")
        payloads[file_name] = json.loads(path.read_text(encoding="utf-8"))
    return payloads


def _merge_payloads(base: Any, current: Any) -> Any:
    if isinstance(base, dict):
        base_dict = cast(Dict[str, Any], base)
        result: Dict[str, Any] = {}
        current_dict = (
            cast(Dict[str, Any], current)
            if isinstance(current, dict)
            else cast(Dict[str, Any], {})
        )
        for key, base_value in base_dict.items():
            result[key] = _merge_payloads(base_value, current_dict.get(key))
        return result
    if isinstance(base, list):
        base_list = cast(List[Any], base)
        if isinstance(current, list) and len(current) == len(base_list):
            current_list = cast(List[Any], current)
            return [
                _merge_payloads(b_item, c_item)
                for b_item, c_item in zip(base_list, current_list)
            ]
        return deepcopy(base_list)
    return current if _has_value(current) else base


def _has_value(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    return True


def _ensure_locale_assets(locale: str, payloads: Dict[str, Any]) -> None:
    normalized = locale.lower()
    locale_dir = LOCALES_DIR / normalized
    locale_dir.mkdir(parents=True, exist_ok=True)
    for file_name, base_payload in payloads.items():
        target_path = locale_dir / file_name
        if target_path.exists():
            try:
                current_content = json.loads(target_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                current_content = None
        else:
            current_content = None
        merged = _merge_payloads(base_payload, current_content)
        target_path.write_text(
            json.dumps(merged, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    print(f"Assets ready for {normalized} -> {locale_dir}")


def _run_coverage_tests(locale: str) -> None:
    print(f"Running coverage test for {locale}...")
    flutter_cmd = which("flutter")
    if not flutter_cmd:
        raise MigrationError("flutter command not found on PATH")
    subprocess.run(
        [
            flutter_cmd,
            "test",
            "test/i18n/translation_coverage_test.dart",
            "--plain-name",
            "fallback locale stays at 100% coverage",
        ],
        check=True,
        cwd=ROOT,
    )


def _finalize(
    status: Dict[str, Any],
    env_lines: List[str],
    fallback_idx: int,
    fallback_key: str,
) -> None:
    original = status.get("original_fallback", BASE_LOCALE)
    _update_env_fallback(env_lines, fallback_idx, fallback_key, original)
    STATUS_PATH.unlink(missing_ok=True)
    print("Restored fallback and removed status file.")


def main() -> None:
    if not STATUS_PATH.exists():
        print("Status file not found; nothing to process.")
        return

    try:
        status = _load_status()
    except json.JSONDecodeError as exc:  # pragma: no cover - defensive
        raise MigrationError(f"Cannot parse {STATUS_PATH.name}: {exc}") from exc

    env_lines = _load_env_lines()
    fallback_value, fallback_idx, fallback_key = _ensure_fallback_entry(env_lines)

    if "original_fallback" not in status:
        status["original_fallback"] = fallback_value
        _save_status(status)

    languages: List[str] = status.get("total_languages", [])
    completed: List[str] = status.get("completed", [])
    remaining = [code for code in languages if code not in completed]

    if not remaining:
        _finalize(status, env_lines, fallback_idx, fallback_key)
        print("All languages already processed. Cleaned up state.")
        return

    base_payloads = _load_base_payloads()

    for code in remaining:
        status["current_target"] = code
        _save_status(status)
        print(f"\n=== Processing {code} ===")
        _ensure_locale_assets(code, base_payloads)
        _update_env_fallback(env_lines, fallback_idx, fallback_key, code)
        try:
            _run_coverage_tests(code)
        except subprocess.CalledProcessError as exc:
            print(f"Tests failed for {code}. Leaving state for retry.")
            raise MigrationError("Coverage tests failed") from exc
        completed.append(code)
        status["completed"] = completed
        status["current_target"] = None
        _save_status(status)

    _finalize(status, env_lines, fallback_idx, fallback_key)
    print("\nAll locales processed successfully.")


if __name__ == "__main__":
    try:
        main()
    except MigrationError as exc:
        print(f"Migration failed: {exc}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:  # pragma: no cover - manual stop
        print("Interrupted.", file=sys.stderr)
        sys.exit(130)
