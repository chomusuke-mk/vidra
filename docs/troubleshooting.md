# Troubleshooting Guide

**Who:** Support engineers, QA, and advanced users.
**Why:** Provide quick symptom → cause → fix lookups for the most common Vidra issues.

## Quick reference table

| Symptom                                               | Likely cause                                                           | Fix                                                                                                                                                                                    |
| ----------------------------------------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Flutter UI stuck on splash with "Backend unavailable" | Backend failed to bind port or crashed during bootstrap.               | Check `<VIDRA_SERVER_DATA>/release_logs.txt` for stack traces. Confirm `VIDRA_SERVER_PORT` is free, then restart the client (which respawns the backend).                              |
| Jobs queue empty even though API returns data         | Cached queue snapshot stale or sockets disconnected.                   | Pull-to-refresh triggers `GET /api/jobs`. If sockets drop repeatedly, inspect network layer or enable fallback polling in debug settings.                                              |
| Playlist dialog never leaves "Loading metadata"       | yt-dlp blocked by throttling or preview endpoints disabled.            | Enable `VIDRA_ENABLE_PREVIEW_API=1` for heavy debugging, verify playlist URL through `yt-dlp --dump-json` manually, and check backend logs for `ytdlp.extractor_error`.                |
| Dry-run / preview endpoints return 404                | Feature flag disabled.                                                 | Export `VIDRA_ENABLE_PREVIEW_API=1` before launching backend or set it in Flutter debug config.                                                                                        |
| Socket disconnect banner repeats every few seconds    | Antivirus/proxy interfering with localhost, backend crash, or port conflict. | Inspect `<VIDRA_SERVER_DATA>/release_logs.txt` for errors. Verify the configured host/port from `.env` is reachable, then restart the client. |
| Packaging task fails with `site-packages missing`     | `Serious Python: Package <platform>` task skipped prerequisite.        | Run VS Code task `Prepare: Create site-packages directory` first or manually create `build/site-packages`.                                                                             |
| Flutter build cannot find `app/app.zip`               | Bundle not regenerated after backend change or asset path missing.     | Re-run `dart run serious_python:main package ...` and ensure `pubspec.yaml` lists `app/app.zip` under `assets`.                                                                        |
| Localization placeholders appear in UI                | Locale not regenerated after copy edits.                               | Run `python tool/fix_placeholder_tokens.py` then `python tool/generate_translation_progress.py`. Commit updates to `i18n/locales/`.                                                    |
| Jobs stuck in `paused` even after resume              | State snapshot not updating (disk permission) or sockets suppressed.   | Verify `VIDRA_SERVER_DATA` write permissions. Use REST `GET /api/jobs/{id}` to confirm state; if still `paused`, issue `POST /api/jobs/{id}/resume` again and check for 409 conflicts. |
| Post-hooks not firing                                 | Backend did not emit hook events or job did not reach expected state.  | Check `<VIDRA_SERVER_DATA>/release_logs.txt` and the job's log stream in the UI; hook callbacks are internal (no `app/json/post_hook.jsonc` in this repo).                            |

## Diagnostic commands

```bash
# Tail backend logs (PowerShell example)
Get-Content "$env:VIDRA_SERVER_DATA/release_logs.txt" -Wait

# Validate yt-dlp arguments standalone
.venv/Scripts/python -m yt_dlp <URL> --simulate --print-json

# Sanity-check backend health (replace host/port as configured)
# curl http://127.0.0.1:59666/
```

## Escalation checklist

1. Collect `release_logs.txt` and `temp/native-crash.txt` (if UI crash involved). Include the job ID and any relevant log lines visible in the UI.
2. Export `flutter doctor -v` output.
3. Note feature flags/env vars in effect.
4. Reproduce with verbose backend logging (`VIDRA_SERVER_LOG_LEVEL=debug`) where possible.

## See also

- `docs/configuration-and-ops.md` for environment variable reference.
- `docs/client-flows.md` to map symptoms back to specific flows/endpoints.
- `docs/packaging-and-release.md` for build/publish issues.
