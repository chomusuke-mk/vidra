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
| Socket disconnect banner repeats every few seconds    | TLS mismatch, antivirus intercepting localhost, or backend CPU pegged. | Inspect `status:cancelled` vs. network errors in logs. Consider raising `VIDRA_MAX_CONCURRENT_JOBS` only if CPU bound, otherwise reduce concurrent jobs to keep event loop responsive. |
| Packaging task fails with `site-packages missing`     | `Serious Python: Package <platform>` task skipped prerequisite.        | Run VS Code task `Prepare: Create site-packages directory` first or manually create `build/site-packages`.                                                                             |
| Flutter build cannot find `app/app.zip`               | Bundle not regenerated after backend change or asset path missing.     | Re-run `dart run serious_python:main package ...` and ensure `pubspec.yaml` lists `app/app.zip` under `assets`.                                                                        |
| Localization placeholders appear in UI                | Locale not regenerated after copy edits.                               | Run `python tool/fix_placeholder_tokens.py` then `python tool/generate_translation_progress.py`. Commit updates to `i18n/locales/`.                                                    |
| Jobs stuck in `paused` even after resume              | State snapshot not updating (disk permission) or sockets suppressed.   | Verify `VIDRA_SERVER_DATA` write permissions. Use REST `GET /api/jobs/{id}` to confirm state; if still `paused`, issue `POST /api/jobs/{id}/resume` again and check for 409 conflicts. |
| Post-hooks not firing                                 | `post_hook.jsonc` syntax error or hook env not in bundle.              | Validate JSONC via VS Code, confirm `VIDRA_HOOK_ENV_FILE` path, and check logs for `post_hook_error`.                                                                                  |

## Diagnostic commands

```bash
# Tail backend logs (PowerShell example)
Get-Content "$env:VIDRA_SERVER_DATA/release_logs.txt" -Wait

# Validate yt-dlp arguments standalone
.venv/Scripts/python -m yt_dlp <URL> --simulate --print-json

# List running sockets from Flutter debug console
dart devtools socket-status
```

## Escalation checklist

1. Collect `release_logs.txt`, `jobs/<job_id>.log`, and `temp/native-crash.txt` (if UI crash involved).
2. Export `flutter doctor -v` output.
3. Note feature flags/env vars in effect.
4. Reproduce with verbose backend logging (`VIDRA_LOG_LEVEL=DEBUG`) where possible.

## See also

- `docs/configuration-and-ops.md` for environment variable reference.
- `docs/client-flows.md` to map symptoms back to specific flows/endpoints.
- `docs/packaging-and-release.md` for build/publish issues.
