from __future__ import annotations

import json
import threading
from pathlib import Path
from typing import Iterable, List, cast

from ..log_config import verbose_log
from ..models.shared import JSONValue
from ..models.download.manager import (
    DownloadPersistedState,
    DownloadPersistedStatePayload,
)


def _extract_job_payloads(decoded: JSONValue) -> List[DownloadPersistedStatePayload]:
    """Normalize legacy/newer snapshot layouts into a flat payload list."""

    if isinstance(decoded, dict):
        raw_entries: JSONValue | None = decoded.get("jobs")
    else:
        raw_entries = decoded

    if not isinstance(raw_entries, list):
        return []

    payloads: List[DownloadPersistedStatePayload] = []
    for entry in raw_entries:
        if isinstance(entry, dict):
            payloads.append(cast(DownloadPersistedStatePayload, entry))
    return payloads


class DownloadStateStore:
    """Persists download job snapshots to disk for restoration."""

    def __init__(self, path: Path) -> None:
        self._path = path
        self._lock = threading.RLock()
        try:
            self._path.parent.mkdir(parents=True, exist_ok=True)
        except Exception as exc:  # noqa: BLE001 - best effort directory creation
            verbose_log(
                "state_store_mkdir_failed",
                {"path": str(self._path.parent), "error": repr(exc)},
            )

    def load(self) -> List[DownloadPersistedState]:
        with self._lock:
            if not self._path.exists():
                return []
            try:
                raw = self._path.read_text(encoding="utf-8")
            except Exception as exc:  # noqa: BLE001
                verbose_log(
                    "state_store_load_failed",
                    {"path": str(self._path), "error": repr(exc)},
                )
                return []
        if not raw.strip():
            return []
        try:
            decoded = cast(JSONValue, json.loads(raw))
        except Exception as exc:  # noqa: BLE001
            verbose_log(
                "state_store_decode_failed",
                {"path": str(self._path), "error": repr(exc)},
            )
            return []

        snapshots: List[DownloadPersistedState] = []
        for payload in _extract_job_payloads(decoded):
            try:
                snapshots.append(DownloadPersistedState.from_json(payload))
            except ValueError as exc:
                verbose_log(
                    "state_store_entry_invalid",
                    {"path": str(self._path), "error": repr(exc)},
                )
        return snapshots

    def save(self, jobs: Iterable[DownloadPersistedState]) -> None:
        payload = {"jobs": [job.to_json() for job in jobs]}
        try:
            serialized = json.dumps(payload, ensure_ascii=False, indent=2)
        except Exception as exc:  # noqa: BLE001
            verbose_log("state_store_encode_failed", {"error": repr(exc)})
            return

        tmp_path = self._path.with_suffix(self._path.suffix + ".tmp")
        with self._lock:
            try:
                tmp_path.write_text(serialized, encoding="utf-8")
                tmp_path.replace(self._path)
            except Exception as exc:  # noqa: BLE001
                verbose_log(
                    "state_store_save_failed",
                    {"path": str(self._path), "error": repr(exc)},
                )
                try:
                    if tmp_path.exists():
                        tmp_path.unlink()
                except Exception:
                    pass

