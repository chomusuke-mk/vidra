from __future__ import annotations
from .mixins.manager_utils import ManagerUtilsMixin
from .mixins.playlist import PlaylistMixin
from .mixins.preview import PreviewMixin
from .mixins.progress import ProgressMixin

"""Compatibility exports for legacy mixins.

This module now re-exports the individual mixin implementations that live
under :mod:`src.download.mixins`. Importers that still rely on
``src.download._mixins`` continue to work while allowing each class to reside
in its dedicated module.
"""

__all__ = [
    "ManagerUtilsMixin",
    "PreviewMixin",
    "PlaylistMixin",
    "ProgressMixin",
]
