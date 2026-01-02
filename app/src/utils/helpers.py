from __future__ import annotations

import re
import math
from datetime import datetime, timezone
from typing import Any, Optional, Union
from .parsers import to_float

Number = Union[int, float]
_ANSI_ESCAPE_RE = re.compile(r"\x1B[@-_][0-?]*[ -/]*[@-~]")

def truncate_string(value: Optional[str], limit: int = 800) -> Optional[str]:
    if not value:
        return None
    text = value.strip()
    if len(text) <= limit:
        return text
    return text[: limit - 3].rstrip() + "..."


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

def normalize_percent(value: Any) -> Optional[float]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        numeric = float(value)
    else:
        text = str(value).strip()
        if not text:
            return None
        if text.endswith("%"):
            text = text[:-1].strip()
        try:
            numeric = float(text)
        except (TypeError, ValueError):
            return None
    if numeric != numeric:  # NaN
        return None
    clamped = max(0.0, min(numeric, 100.0))
    return round(clamped, 2)

def normalize_int(value: Any) -> Optional[int]:
    numeric = to_float(value)
    if numeric is None or math.isnan(numeric) or math.isinf(numeric):
        return None
    if numeric.is_integer():
        return int(numeric)
    # round towards zero
    return int(numeric // 1)

def normalize_float(value: Any) -> Optional[float]:
    numeric = to_float(value)
    if numeric is None or math.isnan(numeric) or math.isinf(numeric):
        return None
    return numeric

def normalize_upload_date(value: Any) -> Optional[str]:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    if len(text) == 8 and text.isdigit():
        return f"{text[:4]}-{text[4:6]}-{text[6:]}"
    try:
        parsed = datetime.fromisoformat(text)
        return parsed.date().isoformat()
    except Exception:  # noqa: BLE001 - fallback to raw value if parsing fails
        return text

def strip_ansi(text: Optional[str]) -> Optional[str]:
    if text is None:
        return None
    cleaned = _ANSI_ESCAPE_RE.sub("", text)
    trimmed = cleaned.strip()
    return trimmed or None


__all__ = [
    "now_iso",
    "truncate_string",
    "normalize_int",
    "normalize_float",
    "normalize_upload_date",
    "normalize_percent",
    "strip_ansi",
]

