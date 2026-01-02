from __future__ import annotations

import json
import threading
import time
from pathlib import Path
from typing import Dict, Optional, Tuple, cast

from ..download.models import DownloadJobOptionsPayload
from ..log_config import verbose_log
from ..models.shared import JSONValue, clone_json_value


class JobOptionsStore:
    """Persists full job option payloads outside the main state snapshot."""

    def __init__(self, base_path: Path) -> None:
        self._base_path = base_path
        self._lock = threading.RLock()
        try:
            self._base_path.mkdir(parents=True, exist_ok=True)
        except Exception as exc:  # noqa: BLE001 - best effort directory creation
            verbose_log(
                "job_options_store_mkdir_failed",
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
            except Exception as exc:  # noqa: BLE001
                verbose_log(
                    "job_options_store_delete_failed",
                    {"path": str(path), "error": repr(exc)},
                )

    def save(
        self,
        job_id: str,
        options: DownloadJobOptionsPayload,
    ) -> Optional[int]:
        version = int(time.time() * 1000)
        payload: Dict[str, JSONValue] = {
            "version": version,
            "options": clone_json_value(cast(JSONValue, options)) or {},
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
                    "job_options_store_save_failed",
                    {"path": str(path), "error": repr(exc)},
                )
                try:
                    if tmp_path.exists():
                        tmp_path.unlink()
                except Exception:
                    pass
                return None
        return version

    def load(self, job_id: str) -> Tuple[DownloadJobOptionsPayload, Optional[int]]:
        path = self._path_for(job_id)
        with self._lock:
            if not path.exists():
                return ({}, None)
            try:
                raw = path.read_text(encoding="utf-8")
            except Exception as exc:  # noqa: BLE001
                verbose_log(
                    "job_options_store_load_failed",
                    {"path": str(path), "error": repr(exc)},
                )
                return ({}, None)
        if not raw.strip():
            return ({}, None)
        try:
            decoded: JSONValue = json.loads(raw)
        except Exception as exc:  # noqa: BLE001
            verbose_log(
                "job_options_store_decode_failed",
                {"path": str(path), "error": repr(exc)},
            )
            return ({}, None)
        options_payload: DownloadJobOptionsPayload = {}
        version_value: Optional[int] = None
        if isinstance(decoded, dict):
            raw_options = decoded.get("options")
            if isinstance(raw_options, dict):
                cloned = clone_json_value(raw_options)
                if isinstance(cloned, dict):
                    options_payload = cloned
            version_field = decoded.get("version")
            if isinstance(version_field, int):
                version_value = version_field
            elif isinstance(version_field, (float, str)):
                try:
                    version_value = int(str(version_field).strip())
                except (TypeError, ValueError):
                    version_value = None
        return (options_payload, version_value)
