# Localization and Assets Guide

**Who:** Localization engineers, designers, and build engineers.
**Why:** Explain how Vidra manages translations, placeholder tracking, and media assets across 150+ locales.

## Localization pipeline

1. Source strings live in `lib/i18n/arb/` files (per locale) plus `i18n/locales/<code>/strings.json` for backend/UI hybrid messages.
2. Run `flutter gen-l10n` (hooked into `flutter pub get`) to regenerate Dart localization delegates.
3. Translation status tracked via `i18n/translation_progress.json` and `i18n/completed_locales.txt`.
4. Placeholder validation uses `python tool/fix_placeholder_tokens.py` (autocorrects `{name}` vs. `%s`) and `python tool/report_placeholder_issues.py` (reports mismatches).

### Automation scripts

| Script                                  | Purpose                                                                               |
| --------------------------------------- | ------------------------------------------------------------------------------------- |
| `tool/auto_translate_locales.py`        | Machine-translates missing strings using configured providers; writes to locale JSON. |
| `tool/generate_translation_progress.py` | Updates `translation_progress.json` summary (percentage per locale).                  |
| `tool/i18n_migration_runner.py`         | Applies batch renames/placeholder migrations across locales.                          |

> Always run `pre-commit` or the scripts above before submitting localization PRs to avoid breaking CI.

## Asset management

- Static icons under `assets/icon/`; animated Lottie files under `assets/animated/`.
- Declare every asset in `pubspec.yaml` to ship with Flutter builds.
- Flutter launcher icons regenerated via `dart run flutter_launcher_icons` using config in `pubspec.yaml`.
- Video thumbnails and other runtime assets are fetched through the backend and cached on disk; they are not part of the Flutter asset bundle.

## Localization workflow checklist

1. Edit source ARB/JSON files.
2. Run `python tool/fix_placeholder_tokens.py` to ensure consistent placeholders.
3. Regenerate progress metrics with `python tool/generate_translation_progress.py`.
4. Rebuild Flutter l10n via `flutter gen-l10n` (implicitly run by `flutter pub get`).
5. Update `i18n/translation_progress.json` in git; review `i18n/completed_locales.txt` if new locales reach 100%.

## Asset workflow checklist

1. Place new assets in the proper subfolder (`assets/icon/` vs. `assets/animated/`).
2. Compress/optimize images before committing.
3. Update `pubspec.yaml` asset list; keep alphabetical order for readability.
4. Run `flutter pub get` to ensure watcher picks up changes.
5. If assets affect installers, sync duplicates under `installer/assets/` (if applicable).

## See also

- `docs/client-architecture.md` for how localization delegates integrate with providers.
- `docs/packaging-and-release.md` for asset verification steps during builds.
- `docs/troubleshooting.md` for resolving placeholder mismatches or missing asset errors.
