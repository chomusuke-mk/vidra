# Packaging and Release Guide

**Who:** Release engineers and contributors building installers/binaries.
**Why:** Provide a reproducible checklist for packaging the Python backend via `serious_python`, bundling it with Flutter builds, and producing signed installers.

## Prerequisites

- Dart SDK (the repo uses `dart run serious_python:main ...` via the dependency declared in `pubspec.yaml`).
- Flutter SDK ≥ 3.9 with desktop platforms enabled.
- Python 3.12 (used to resolve backend dependencies before packaging).
- Inno Setup (for Windows installer; see `installer.iss`).

## Packaging the backend

```bash
# 1. Ensure virtualenv is ready
cd app
python -m venv .venv
. .venv/Scripts/activate  # PowerShell: .venv\Scripts\Activate.ps1
pip install -r requirements.txt -r requirements.dev.txt

# 2. Create platform bundle
cd ..
dart run serious_python:main package app/src \
  --requirements -r app/requirements.txt \
  -p Windows --verbose \
  --output app/app.zip

# 3. (Optional) Build additional platforms
# Replace -p Windows with Android/Linux/MacOS as needed
```

Artifacts:

- `app/app.zip`: zipped site-packages + entrypoint.
- `app/app.zip.hash`: generated automatically; must ship with the bundle.

> VS Code task **Serious Python: Package <Platform> App** wraps the same command and automatically creates `build/site-packages` via the `Prepare` task dependency.

## Integrating with Flutter

1. Confirm `app/app.zip` and `app/app.zip.hash` appear under `flutter: assets:` in `pubspec.yaml`.
2. Run `flutter pub get` so the build picks up asset changes.
3. Trigger the desired build:
   - `flutter build windows --release`
   - `flutter build macos --release`
   - `flutter build linux --release`
4. Validate the artifact launches, unpacks the backend, and passes the smoke test (create/cancel job).

## Installer/signing (Windows)

1. Build the Flutter Windows bundle (`build/windows/runner/Release`).
2. Run Inno Setup with `installer.iss` to generate the installer. The script copies:
   - Flutter binaries
   - `app/app.zip` + hash
   - `third_party_licenses/*`
   - Config files (`LICENSE`, `README.md`)
3. Sign binaries/installer if certificates are available.

## Release checklist

1. **Tag**: create semantic tag `vX.Y.Z` once release commit is ready.
2. **Changelog**: update `CHANGELOG.md` (if present) or the GitHub Release notes.
3. **Artifacts**: attach Windows/Linux builds, backend zip (if distributing separately), and the installer to the release page.
4. **Validation**:
   - Run `pytest` and `flutter test` in CI.
   - Execute manual smoke test per platform (queue job, pause, resume, delete).
   - Verify locale coverage via `python tool/generate_translation_progress.py` (no regressions).
5. **Licenses**: ensure `THIRD_PARTY_LICENSES.md` and `third_party_licenses/*` are up-to-date.

## Automation hooks

- GitHub Actions (if configured) can run `dart run serious_python:main package ...` as part of release pipelines; cache `.dart_tool` and `.venv` to speed up builds.
- Use artifact retention settings to keep zipped bundles available for future installers.

## See also

- `docs/system-architecture.md` for how the bundle fits into runtime.
- `docs/configuration-and-ops.md` for environment variable expectations post-install.
- `docs/troubleshooting.md` for resolving packaging failures or hash mismatches.
