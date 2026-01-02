"""Stage definitions for download workflow."""

from __future__ import annotations

from enum import Enum
from typing import Any, Optional


class DownloadStage(str, Enum):
    """Normalized stages emitted by the backend pipeline."""

    IDENTIFICANDO = "IDENTIFICANDO"
    WAIT_FOR_ELEMENTS = "WAIT_FOR_ELEMENTS"
    WAIT_FOR_SELECTION = "WAIT_FOR_SELECTION"
    PROGRESSING = "PROGRESSING"
    POSTPROCESSING = "POSTPROCESSING"
    COMPLETED = "COMPLETED"

    @classmethod
    def from_value(cls, value: Any) -> Optional["DownloadStage"]:
        if isinstance(value, cls):
            return value
        if isinstance(value, str):
            upper = value.strip().upper()
            for stage in cls:
                if stage.value == upper:
                    return stage
        return None


DEFAULT_STAGE_NAME = ""
DEFAULT_STAGE_STATUS = ""
