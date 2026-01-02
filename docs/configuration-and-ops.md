# Configuration and Operations Guide

**Who:** Operators, SREs, power users packaging Vidra into desktop installers.
**Why:** Centralize environment variables, run modes, log locations, and operational playbooks for the embedded backend.

## Environment variables

| Variable                           | Default                          | Description                                                                                                                |
| ---------------------------------- | -------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `VIDRA_SERVER_DATA`                | `%LOCALAPPDATA%/Vidra` (Windows) | Root folder for logs, job snapshots, downloaded outputs, and crash dumps. Set to an absolute path when running standalone. |
| `VIDRA_SERVER_HOST`                | `127.0.0.1`                      | Bind address for FastAPI/Uvicorn. Desktop builds keep it loopback-only.                                                    |
| `VIDRA_SERVER_PORT`                | `5757`                           | REST/WebSocket port. Client reads it from `lib/config/runtime_config.dart`.                                                |
| `VIDRA_ENABLE_PREVIEW_API`         | `0`                              | Exposes `POST /api/preview` and `POST /api/jobs/dry-run`. Enable only for debugging.                                       |
| `VIDRA_ENABLE_DOWNLOAD_SOCKET`     | `1`                              | Enables legacy aggregate socket. Set to `0` to rely solely on per-job sockets.                                             |
| `VIDRA_MAX_CONCURRENT_JOBS`        | `3`                              | Worker pool width. Higher values increase disk/CPU pressure.                                                               |
| `VIDRA_RETENTION_DAYS`             | `30`                             | Automatic deletion window for `completed`/`cancelled` jobs.                                                                |
| `VIDRA_HOOK_ENV_FILE`              | `app/json/post_hook.jsonc`       | Optional env var override for hook definitions.                                                                            |
| `VIDRA_TLS_KEY` / `VIDRA_TLS_CERT` | unset                            | Provide both to expose HTTPS endpoints (useful when embedding behind reverse proxies).                                     |

> **Tip:** When launching the backend manually (`python -m app.main`), export these variables before starting Uvicorn so the same behavior matches the embedded runtime.

## Logging and telemetry

- All structured logs land in `<VIDRA_SERVER_DATA>/release_logs.txt` with JSON lines containing `ts`, `level`, `scope`, `message`, and `context`.
- Job-specific logs are mirrored to `<VIDRA_SERVER_DATA>/jobs/<job_id>.log` for quick per-job troubleshooting.
- yt-dlp stdout/stderr is routed through hook payloads and appears in both the global log and the job log (tagged `source=ytdlp`).
- Crash dumps (uncaught exceptions) yield `temp/native-crash.txt` on the Flutter side and `VIDRA_SERVER_DATA/crash_<timestamp>.log` on the backend.

## Deployment modes

| Mode                      | How                                                                                       | Notes                                                                                                               |
| ------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Embedded (default)        | Flutter desktop launches backend via `serious_python`                                     | Auto-manages virtualenv and env vars; ideal for production builds.                                                  |
| Standalone backend        | `cd app && python -m app.main`                                                            | Useful for backend-only development or remote deployments. Ensure `VIDRA_SERVER_HOST=0.0.0.0` if accessed remotely. |
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

- Set `VIDRA_EXTRA_LOG_FIELDS` (JSON string) to inject custom fields (e.g., deployment ID) into every log entry.
- Configure `app/json/post_hook.jsonc` to emit webhooks or desktop notifications upon job completion/failure.
- `app/json/postprocessor_hook.jsonc` defines chained postprocessors (e.g., transcoders). Each entry can declare `on_states` to limit execution to `completed` only.

## Maintenance windows

- During Flutter app upgrades, existing backend snapshots remain valid as long as `schema_version` does not change. If a breaking schema is introduced, ship a migration utility under `tool/` and document it here.
- Always regenerate `app/app.zip.hash` after packaging so the Flutter client can verify integrity before extraction.

## See also

- `docs/system-architecture.md` for how these variables feed into the runtime graph.
- `docs/packaging-and-release.md` for exact commands and VS Code tasks.
- `docs/troubleshooting.md` for user-facing playbooks keyed by symptoms.
