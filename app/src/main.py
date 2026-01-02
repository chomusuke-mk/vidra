"""Application entrypoint for running the Vidra backend locally."""

# ruff: noqa: E402
# pylint: disable=wrong-import-position

from __future__ import annotations

import os
import sys
from pathlib import Path
import importlib
import importlib.util
import json
import platform
import shutil
import traceback
from datetime import datetime, timezone
from types import ModuleType
from typing import Any, Tuple, cast


def _env_flag(name: str, *, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "y", "on"}


# When enabled, we emit large directory listings and sys.path scans.
# Keep it off by default to avoid bloating release logs in normal runs.
_VERBOSE_DIAGNOSTICS = _env_flag("VIDRA_SERVER_DIAGNOSTICS", default=False)


def _dump_path(
    label: str,
    path: Path,
    *,
    max_entries: int = 80,
    list_entries: bool = True,
) -> None:
    """Print a best-effort filesystem snapshot to stdout/stderr.

    stdout/stderr are redirected to `release_logs.txt` early in this module,
    so these prints become persistent diagnostics for Android startup issues.
    """

    try:
        raw = str(path)
        abspath = os.path.abspath(raw)
        realpath = os.path.realpath(raw)
        exists = path.exists()
        is_dir = path.is_dir()
        is_file = path.is_file()
        print(
            f"[vidra][fs] {label}",
            f"  path={raw}",
            f"  abspath={abspath}",
            f"  realpath={realpath}",
            f"  exists={exists} is_dir={is_dir} is_file={is_file}",
            sep="\n",
            flush=True,
        )

        if exists and is_dir and list_entries:
            try:
                entries = sorted([p.name for p in path.iterdir()])
                print(f"  entries_count={len(entries)}", flush=True)
                for name in entries[:max_entries]:
                    print(f"    - {name}", flush=True)
                if len(entries) > max_entries:
                    print(f"    ... (+{len(entries) - max_entries} más)", flush=True)
            except Exception as e:
                print(f"  listdir_error={e!r}", flush=True)
        elif exists and is_file:
            try:
                print(f"  size={path.stat().st_size}", flush=True)
            except Exception as e:
                print(f"  stat_error={e!r}", flush=True)
    except Exception as e:
        # Never let diagnostics crash startup.
        try:
            print(f"[vidra][fs] {label} error={e!r}", flush=True)
        except Exception:
            pass


def _dump_sys_path_candidates(*, package_root: Path) -> None:
    try:
        if not _VERBOSE_DIAGNOSTICS:
            return
        print("[vidra][fs] sys.path candidates for server", flush=True)
        seen = set()
        for entry in sys.path:
            if not entry or entry in seen:
                continue
            seen.add(entry)
            base = Path(entry)
            for candidate in (
                base / "server",
                base / "app" / "server",
                base / "flet" / "app" / "server",
            ):
                if candidate.exists():
                    _dump_path("candidate_server_dir", candidate)
        _dump_path("expected_package_root", package_root)
        _dump_path("expected_server_dir", package_root / "server")
    except Exception as e:
        try:
            print(f"[vidra][fs] sys.path scan failed: {e!r}", flush=True)
        except Exception:
            pass


def _normalize_backslash_extracted_tree(root: Path) -> None:
    """Fix incorrect extraction where '/' became '\\' in filenames.

    We have observed Android extractions that create files like:
      - 'server\\__init__.py'
      - 'core\\contract\\info.py'
    instead of real directories. This breaks Python imports.

    This function converts those flat filenames into a proper directory tree.
    It is safe on platforms where backslashes are not valid filename
    characters (the scan will just find nothing).
    """

    try:
        if not root.exists() or not root.is_dir():
            return

        candidates = [p for p in root.iterdir() if "\\" in p.name]
        if not candidates:
            return

        print(
            "[vidra][fs] Detected backslash paths in extracted tree; normalizing.",
            f"root={root}",
            f"count={len(candidates)}",
            sep="\n",
            flush=True,
        )

        moved = 0
        skipped = 0
        errors = 0
        for source in candidates:
            try:
                parts = [part for part in source.name.split("\\") if part]
                if not parts:
                    skipped += 1
                    continue

                destination = root.joinpath(*parts)
                destination.parent.mkdir(parents=True, exist_ok=True)

                if destination.exists():
                    skipped += 1
                    continue

                os.replace(str(source), str(destination))
                moved += 1
            except Exception:
                errors += 1

        print(
            "[vidra][fs] Backslash normalization complete.",
            f"moved={moved}",
            f"skipped={skipped}",
            f"errors={errors}",
            sep="\n",
            flush=True,
        )
    except Exception:
        # Never let diagnostics/repair crash startup.
        pass


def _load_app_package() -> ModuleType:
    """Ensure the 'app' package is importable when executed as a script.

    This avoids relying on `sys.path` ordering, which can be tricky in
    embedded Android runtimes (mixed /data/user/0 and /data/data paths, and
    a sys.path entry that points directly at the package directory).
    """

    package_name = "app"
    existing = sys.modules.get(package_name)
    if existing is not None:
        # If something imported a top-level `app.py` as a module named `app`,
        # it won't have a `__path__` and submodule imports like `app.server`
        # will fail. In that case, discard it and load the real package.
        if getattr(existing, "__path__", None):
            return existing
        del sys.modules[package_name]

    package_root = Path(__file__).resolve().parent
    package_root_raw = Path(__file__).parent

    # Workaround for incorrect extraction that turns directory separators into
    # literal backslashes in filenames (Android issue observed in the wild).
    _normalize_backslash_extracted_tree(package_root_raw)
    _normalize_backslash_extracted_tree(package_root)

    init_path = package_root / "__init__.py"
    if not init_path.exists():
        raise ImportError("Unable to locate app package __init__.py")

    parent_dir = str(package_root.parent)
    if parent_dir not in sys.path:
        sys.path.insert(0, parent_dir)

    spec = importlib.util.spec_from_file_location(
        package_name,
        init_path,
        submodule_search_locations=[str(package_root)],
    )
    if spec is None or spec.loader is None:
        raise ImportError("Failed to import app package")

    module = importlib.util.module_from_spec(spec)
    # Ensure this is treated as a package during `__init__.py` execution.
    # Some embedded runtimes end up with odd `sys.path` entries or import order,
    # and having these set up-front makes relative imports more reliable.
    module.__package__ = package_name
    module.__path__ = [str(package_root)]
    sys.modules[package_name] = module
    try:
        spec.loader.exec_module(module)
    except Exception:
        # Best-effort diagnostics for the common Android failure mode.
        try:
            print(
                "[vidra][import] Failed importing 'app' package.",
                sep="\n",
                file=sys.stderr,
            )

            server_dir = package_root / "server"
            backslash_count = -1
            try:
                backslash_count = sum(
                    1 for p in package_root_raw.iterdir() if "\\" in p.name
                )
            except Exception:
                pass

            print(
                "[vidra][import] quick snapshot",
                f"package_root={package_root}",
                f"server_dir_exists={server_dir.exists()}",
                f"backslash_entries_in_root={backslash_count}",
                sep="\n",
                file=sys.stderr,
                flush=True,
            )

            if _VERBOSE_DIAGNOSTICS:
                _dump_path("__file__", Path(__file__))
                _dump_path("cwd", Path(os.getcwd()))
                _dump_path("package_root_resolved", package_root)
                _dump_path("package_root_raw", package_root_raw)
                _dump_path("package_init", package_root / "__init__.py")
                _dump_path("package_app_py", package_root / "app.py")
                _dump_path("package_server_dir", server_dir)
                _dump_sys_path_candidates(package_root=package_root)
        except Exception:
            pass
        raise
    return module


def _import_application_modules() -> Tuple[ModuleType, ModuleType]:
    """Load the app/config modules.

    When executed as a script (the embedded/packaged case), explicitly load
    the `app` package from disk so imports like `app.server` work reliably.
    """

    if __package__ in (None, ""):
        app_pkg = _load_app_package()
        config_pkg = sys.modules.get("app.config")
        if config_pkg is None:
            config_pkg = importlib.import_module("app.config")
        return app_pkg, config_pkg

    # pragma: no cover - executed only when run as packaged module
    app_pkg = importlib.import_module(f"{__package__}.app")
    config_pkg = importlib.import_module(f"{__package__}.config")
    return app_pkg, config_pkg


# view launch logging setup
_SCRIPT_DIR = Path(__file__).resolve().parent
_DEFAULT_BACKEND_DIR = _SCRIPT_DIR / "backend"


def _resolve_backend_dir() -> Path:
    data_root = os.getenv("VIDRA_SERVER_DATA")
    if data_root:
        return Path(data_root)
    return _DEFAULT_BACKEND_DIR


def _determine_log_file(data_dir: Path) -> Path:
    explicit = os.getenv("VIDRA_SERVER_LOG_FILE")
    if explicit:
        return Path(explicit)
    return data_dir / "release_logs.txt"


def _determine_status_file(data_dir: Path) -> Path:
    explicit = os.getenv("VIDRA_SERVER_STATUS_FILE")
    if explicit:
        return Path(explicit)
    return data_dir / "startup_status.json"


def _write_status(
    status_file: Path,
    *,
    phase: str,
    message: str | None = None,
    traceback_text: str | None = None,
    extra: dict[str, object] | None = None,
) -> None:
    payload: dict[str, object] = {
        "status": phase,
        "message": message,
        "traceback": traceback_text,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "source": "backend",
    }
    if extra:
        payload.update(extra)
    payload.setdefault("log_path", str(_LOG_FILE_PATH))
    status_file.parent.mkdir(parents=True, exist_ok=True)
    status_file.write_text(
        json.dumps({k: v for k, v in payload.items() if v is not None}, indent=2),
        encoding="utf-8",
    )


_DATA_DIR = _resolve_backend_dir()
_DATA_DIR.mkdir(parents=True, exist_ok=True)
_STATUS_FILE_PATH = _determine_status_file(_DATA_DIR)
_LOG_FILE_PATH = _determine_log_file(_DATA_DIR)

_write_status(
    _STATUS_FILE_PATH,
    phase="starting",
    message="Inicializando runtime de Python",
)

old_stdout = sys.stdout
old_stderr = sys.stderr
log_file = None
try:
    os.makedirs(_LOG_FILE_PATH.parent, exist_ok=True)
    log_file = open(
        _LOG_FILE_PATH,
        "w",
        encoding="utf-8",
    )
    sys.stdout = log_file
    sys.stderr = log_file

    print("[vidra][startup] release log initialized", flush=True)

    # Normalize the extracted app tree ASAP, before imports rely on packages
    # like `server/` existing as real directories.
    _normalize_backslash_extracted_tree(Path(__file__).parent)
    _normalize_backslash_extracted_tree(Path(__file__).resolve().parent)

    _dump_path("log_file", _LOG_FILE_PATH)
    _dump_path("data_dir", _DATA_DIR)
    _dump_path("script_dir", _SCRIPT_DIR, list_entries=_VERBOSE_DIAGNOSTICS)
    _dump_path("cwd", Path(os.getcwd()), list_entries=_VERBOSE_DIAGNOSTICS)

    if not _VERBOSE_DIAGNOSTICS:
        print(
            "[vidra][startup] Tip: set VIDRA_SERVER_DIAGNOSTICS=1 for verbose dumps",
            flush=True,
        )
except Exception as e:
    old_stdout.write(
        f"ERROR: No se pudo abrir el archivo de log '{_LOG_FILE_PATH}': {e}\n"
    )
    log_file = None
# -------------------------------


def _collect_python_diagnostics() -> dict[str, object]:
    version_info = sys.version_info
    diag: dict[str, object] = {
        "sys_version": sys.version.replace("\n", " "),
        "version_tuple": f"{version_info.major}.{version_info.minor}.{version_info.micro}",
        "hex_version": hex(sys.hexversion),
        "implementation": platform.python_implementation(),
        "compiler": platform.python_compiler(),
        "build_info": " ".join(platform.python_build()),
        "executable": sys.executable,
        "executable_exists": bool(sys.executable and Path(sys.executable).exists()),
        "platform": platform.platform(),
        "machine": platform.machine(),
        "system": platform.system(),
        "release": platform.release(),
        "architecture": platform.architecture()[0],
        "cwd": os.getcwd(),
        "path_env": os.environ.get("PATH"),
        "pythonpath_env": os.environ.get("PYTHONPATH"),
        "pythonhome_env": os.environ.get("PYTHONHOME"),
        "virtual_env": os.environ.get("VIRTUAL_ENV"),
        "sys_prefix": sys.prefix,
        "base_prefix": getattr(sys, "base_prefix", "<unset>"),
        "exec_prefix": sys.exec_prefix,
        "path_entries": list(dict.fromkeys(sys.path)),
        "argv": list(sys.argv),
        "which_python": shutil.which("python"),
    }
    if os.name == "nt":
        diag["dll_search_path"] = os.environ.get("PATH", "").split(os.pathsep)
    return {k: v for k, v in diag.items() if v not in (None, "", [])}


def _emit_python_diagnostics() -> None:
    print("--- Python runtime diagnostics ---")
    diagnostics = _collect_python_diagnostics()
    for key, value in diagnostics.items():
        if isinstance(value, list):
            items = cast(list[Any], value)
            print(f"{key}:")
            for item in items:
                print(f"  - {item}")
        else:
            print(f"{key}: {value}")


try:
    app_module, config_module = _import_application_modules()

    DEFAULT_HOST = getattr(config_module, "DEFAULT_HOST", "0.0.0.0")
    DEFAULT_PORT = getattr(config_module, "DEFAULT_PORT", 5000)
    DEFAULT_LOG_LEVEL = getattr(config_module, "DEFAULT_LOG_LEVEL", "info")

    app = app_module.app

    def run(
        host: str = DEFAULT_HOST,
        port: int = DEFAULT_PORT,
        log_level: str = DEFAULT_LOG_LEVEL,
    ) -> None:
        """Run the ASGI application using Uvicorn."""

        import uvicorn

        uvicorn.run(app, host=host, port=port, log_level=log_level)

    __all__ = ["app", "run"]

    # if __name__ == "__main__":
    run()
except Exception:
    print("--- Fatal error during application startup ---")
    _emit_python_diagnostics()
    traceback.print_exc()
finally:
    print("--- Fin del Log de la aplicación ---", flush=True)
    sys.stdout = old_stdout
    sys.stderr = old_stderr
    if log_file:
        try:
            log_file.close()
        except Exception as e:
            old_stderr.write(f"Error closing log file '{_LOG_FILE_PATH}': {e}\n")
    sys.exit(0)