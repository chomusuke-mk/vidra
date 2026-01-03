# Configuration and Operations Guide

**Who:** Operators, SREs, power users packaging Vidra into desktop installers.
**Why:** Centralize environment variables, run modes, log locations, and operational playbooks for the embedded backend.

## Environment variables

| Variable                       | Default                            | Description                                                                                                                        |
| ------------------------------ | ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `VIDRA_SERVER_DATA`            | (required)                         | Root folder for backend logs/state. In dev, `.env` points to `./temp/data`. Must be an absolute path when running standalone.     |
| `VIDRA_SERVER_CACHE`           | (required)                         | Cache folder used by the backend. In dev, `.env` points to `./temp/cache`. Must be an absolute path when running standalone.      |
| `VIDRA_SERVER_HOST`            | `0.0.0.0` (backend default)         | Bind address for the ASGI server (Uvicorn). Embedded Flutter runtime typically overrides to `127.0.0.1` via `.env`.               |
| `VIDRA_SERVER_PORT`            | `5000` (backend default)            | REST/WebSocket port. The embedded `.env` currently sets `59666`.                                                                |
| `VIDRA_SERVER_LOG_LEVEL`       | `info`                              | Uvicorn log level (`critical|error|warning|info|debug|trace`).                                                                  |
| `VIDRA_ENABLE_PREVIEW_API`     | `0`                                 | Exposes `POST /api/preview` and `POST /api/jobs/dry-run` (useful for debugging).                                                |
| `VIDRA_SERVER_TOKEN`           | unset (dev `.env` defines one)      | Optional bearer-like token used by the client/backends for local auth/handshakes (depends on client configuration).             |
| `VIDRA_SERVER_TIMEOUT_SECONDS` | `30`                                | Backend timeout defaults (used for outbound operations).                                                                          |

> **Tip:** When launching the backend manually (`python -m src.main`), export `VIDRA_SERVER_DATA` and `VIDRA_SERVER_CACHE` (and optionally host/port) so behavior matches the embedded runtime.

## Logging and telemetry

- All structured logs land in `<VIDRA_SERVER_DATA>/release_logs.txt` with JSON lines containing `ts`, `level`, `scope`, `message`, and `context`.
- yt-dlp stdout/stderr is routed through hook payloads and appears in both the global log and the job log (tagged `source=ytdlp`).
- Crash dumps (uncaught exceptions) yield `temp/native-crash.txt` on the Flutter side and `VIDRA_SERVER_DATA/crash_<timestamp>.log` on the backend.

## Deployment modes

| Mode                      | How                                                                                       | Notes                                                                                                               |
| ------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Embedded (default)        | Flutter desktop launches backend via `serious_python`                                     | Auto-manages virtualenv and env vars; ideal for production builds.                                                  |
| Standalone backend        | `cd app && python -m src.main`                                                            | Useful for backend-only development. You must set `VIDRA_SERVER_DATA` and `VIDRA_SERVER_CACHE` before launching.    |
| Remote backend + local UI | Point the Flutter app to remote host via debug settings (`lib/config/debug_options.dart`) | Secure the channel (TLS + auth) before exposing beyond localhost.                                                   |

## Operational runbooks

### Rotating logs

1. Stop the backend (or pause new jobs).
2. Move `release_logs.txt` to an archive location (e.g., `release_logs-2025-11-25.txt`).
3. Restart the backend; it recreates the file automatically.

### Clearing stuck jobs

1. Inspect `docs/backend-job-lifecycle.md` to identify current state.
2. Use `POST /api/jobs/{id}/cancel` if the job is still `running`/`paused`.
3. Delete residual snapshots (`jobs/<id>.json` + `.log`) only if you are sure the job is defunct.

### Updating yt-dlp

1. Edit `app/requirements.txt` to bump `yt-dlp`.
2. Re-run `pip install -r requirements.txt` inside `app/.venv`.
3. Execute `dart run serious_python:main package app/src -p <platform>` to bake the new version into `app/app.zip`.
4. Run regression tests (`pytest`, `flutter test`) before shipping.

## Observability hooks

- Backend logging is controlled primarily via `VIDRA_SERVER_LOG_LEVEL` and the on-disk `release_logs.txt` stream.
- Postprocessor/post-hook events are emitted by the backend as socket/log payloads; there is no `app/json/*.jsonc` configuration directory in this repository.

## Maintenance windows

- During Flutter app upgrades, existing backend snapshots remain valid as long as `schema_version` does not change. If a breaking schema is introduced, ship a migration utility under `tool/` and document it here.
- Always regenerate `app/app.zip.hash` after packaging so the Flutter client can verify integrity before extraction.

## See also

- `docs/system-architecture.md` for how these variables feed into the runtime graph.
- `docs/packaging-and-release.md` for exact commands and VS Code tasks.
- `docs/troubleshooting.md` for user-facing playbooks keyed by symptoms.
