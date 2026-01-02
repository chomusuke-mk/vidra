from __future__ import annotations

import json
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple, cast

from ..log_config import verbose_log
from ..models.shared import JSONValue

PlaylistEntryList = List[Dict[str, JSONValue]]


class PlaylistEntryStore:
    """Persists compact playlist entry payloads per job."""

    def __init__(self, base_path: Path) -> None:
        self._base_path = base_path
        self._lock = threading.RLock()
        try:
            self._base_path.mkdir(parents=True, exist_ok=True)
        except Exception as exc:  # noqa: BLE001 - best effort directory creation
            verbose_log(
                "playlist_entry_store_mkdir_failed",
                {"path": str(self._base_path), "error": repr(exc)},
            )

    def _path_for(self, job_id: str) -> Path:
        return self._base_path / f"{job_id}.json"

    def delete(self, job_id: str) -> None:
        path = self._path_for(job_id)
        with self._lock:
            try:
                if path.exists():
                    path.unlink()
            except Exception as exc:  # noqa: BLE001 - ignore cleanup failures
                verbose_log(
                    "playlist_entry_store_delete_failed",
                    {"path": str(path), "error": repr(exc)},
                )

    def save(
        self,
        job_id: str,
        entries: PlaylistEntryList,
        *,
        version: Optional[int] = None,
    ) -> Optional[int]:
        if not entries:
            self.delete(job_id)
            return None

        resolved_version = version or int(time.time() * 1000)
        entries_payload: List[JSONValue] = [cast(JSONValue, dict(entry)) for entry in entries]
        payload: Dict[str, JSONValue] = {
            "version": resolved_version,
            "entries": entries_payload,
        }
        serialized = json.dumps(payload, ensure_ascii=False)
        path = self._path_for(job_id)
        tmp_path = path.with_suffix(".tmp")
        with self._lock:
            try:
                tmp_path.write_text(serialized, encoding="utf-8")
                tmp_path.replace(path)
            except Exception as exc:  # noqa: BLE001 - capture IO issues
                verbose_log(
                    "playlist_entry_store_save_failed",
                    {"path": str(path), "error": repr(exc)},
                )
                try:
                    if tmp_path.exists():
                        tmp_path.unlink()
                except Exception:
                    pass
                return None
        return resolved_version

    def load(self, job_id: str) -> Tuple[PlaylistEntryList, Optional[int]]:
        path = self._path_for(job_id)
        with self._lock:
            if not path.exists():
                return ([], None)
            try:
                raw = path.read_text(encoding="utf-8")
            except Exception as exc:  # noqa: BLE001
                verbose_log(
                    "playlist_entry_store_load_failed",
                    {"path": str(path), "error": repr(exc)},
                )
                return ([], None)
        try:
            decoded = cast(JSONValue, json.loads(raw))
        except Exception as exc:  # noqa: BLE001
            verbose_log(
                "playlist_entry_store_decode_failed",
                {"path": str(path), "error": repr(exc)},
            )
            return ([], None)
        entries_value = decoded.get("entries") if isinstance(decoded, dict) else None
        if not isinstance(entries_value, list):
            return ([], None)
        compact_entries: PlaylistEntryList = []
        for entry in entries_value:
            if isinstance(entry, dict):
                compact_entries.append(dict(entry))
        version_value = decoded.get("version") if isinstance(decoded, dict) else None
        resolved_version: Optional[int]
        if isinstance(version_value, int):
            resolved_version = version_value
        elif isinstance(version_value, float):
            resolved_version = int(version_value)
        elif isinstance(version_value, str):
            try:
                resolved_version = int(version_value.strip())
            except ValueError:
                resolved_version = None
        else:
            resolved_version = None
        return (compact_entries, resolved_version)
