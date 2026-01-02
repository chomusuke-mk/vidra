# Vidra

[![Flutter 3.9+](https://img.shields.io/badge/Flutter-3.9%2B-blue)](https://flutter.dev)
[![Python 3.12](https://img.shields.io/badge/Python-3.12-blueviolet)](https://www.python.org/)
[![License](https://img.shields.io/badge/Licensing-THIRD__PARTY__LICENSES-informational)](THIRD_PARTY_LICENSES.md)

> Vidra is a desktop-grade video/job manager that marries a Flutter UI with an embedded Python backend (FastAPI + yt-dlp). The project is fully localized, scriptable, and ready for packaging via `serious_python`.

## Highlights

- **Full-stack packaging** – The Python backend is zipped and shipped inside the Flutter assets and unbundled at runtime via `serious_python`.
- **Modern client** – A Flutter desktop app with caching, offline awareness, theming, and localization coverage for 150+ locales.
- **Battle-tested backend** – FastAPI + Uvicorn + yt-dlp provide resumable downloads, queue orchestration, and hook-based automation.
- **Ops-friendly** – Feature flags, structured logging, translation tooling, and ready-made VS Code tasks keep operations predictable.

## Architecture

| Layer | Responsibilities | Key tech |
| --- | --- | --- |
| Python backend (`app/src`) | REST + WebSocket API, job orchestration, yt-dlp integration, hook execution. | FastAPI, Uvicorn, Pydantic, yt-dlp, Redis-compatible sockets |
| Embedded runtime (`app/app.zip`) | Self-contained Python env extracted by `serious_python` for each platform. | serious_python, pip, uvicorn |
| Flutter client (`lib/`) | Multi-platform UI, caching, notifications, i18n, persistence. | Flutter 3.9, provider, cached_network_image, serious_python plugin |
| Tooling (`tool/`, `docs/`) | Localization scripts, translation diffing, typed architecture notes. | Dart CLI, Python scripts |

## Prerequisites

- Flutter SDK ≥ 3.9.2 (desktop platforms enabled for Windows/Mac/Linux builds).
- Dart ≥ 3.9.
- Python 3.12 (used for backend development and unit tests).
- Android/iOS toolchains (optional, only if targeting mobile builds).
- `serious_python` CLI (installed via `dart pub global activate serious_python`).

### FFmpeg / ffprobe binaries (required)

This repository does **not** ship FFmpeg binaries anymore. To run Vidra you must provide `ffmpeg` and `ffprobe` yourself.

Recommended source: https://github.com/chomusuke-mk/vidra-ffmpeg

Place the files with **exact** names in the following locations:

- **Windows**
	- `windows/ffmpeg/ffmpeg.exe`
	- `windows/ffmpeg/ffprobe.exe`

- **Linux**
	- `linux/ffmpeg/ffmpeg`
	- `linux/ffmpeg/ffprobe`
	- Ensure they are executable: `chmod +x linux/ffmpeg/ffmpeg linux/ffmpeg/ffprobe`

## Quick start

### 1. Bootstrap the Python backend

```bash
cd app
python -m venv .venv
. .venv/Scripts/activate  # PowerShell: .venv\Scripts\Activate.ps1
pip install -r requirements.txt -r requirements.dev.txt
```

### 2. Bootstrap the Flutter workspace

```bash
flutter pub get
dart run flutter_launcher_icons  # optional, regenerates icons
```

## Running the stack locally

### Backend API

```bash
cd app
export VIDRA_SERVER_DATA="p:/vidra/temp"  # log/output location (set to an absolute path)
python -m app.main
```

This boots FastAPI with the default host/port declared in `app/src/config`. All stdout/stderr is redirected to `release_logs.txt` inside `VIDRA_SERVER_DATA` for easier troubleshooting.

### Flutter desktop client

```bash
flutter run -d windows  # or macos / linux
```

The client automatically unpacks `app/app.zip` using the `serious_python` plugin, talks to the local FastAPI instance, and streams job updates through per-job WebSockets.

### Android share target

On Android you can now push URLs straight into Vidra from any app that exposes the standard `Share` menu:

1. Choose **Vidra** in the share sheet to open a translucent overlay with quick presets (Video · Best, Video · H264, Audio · Best, Audio · Speech).
2. Tap one of the presets to enqueue the new job immediately, or pick **Other downloads** to open the regular quick-options sheet with your full preference controls. The shared URLs are prefilled in the Home screen textbox.
3. Android's Direct Share row (long-press suggestions) exposes the same presets so you can jump directly into the desired format without opening the overlay.

Each shared job is tagged with metadata (`share_intent`) so you can audit where it came from on the backend.

## Packaging & distribution

1. Ensure the backend bundle inside `app/app.zip` is current:

	 ```bash
	 dart run serious_python:main package app/src \
		 --requirements -r app/requirements.txt \
		 -p Windows --verbose \
		 --output app/app.zip
	 ```

	 (Use `Android`, `Linux`, or `MacOS` for the `-p` flag as needed.)

2. Copy `app/app.zip` and the generated hash (`app/app.zip.hash`) into the Flutter assets list (already declared in `pubspec.yaml`).

3. Build your target artifact (`flutter build windows`, `flutter build macos`, etc.).

The repository includes VS Code tasks (`Serious Python: Package <platform> App`, `Build Android APK (Flutter)`) that wrap the same commands.

## Feature flags

- `VIDRA_ENABLE_PREVIEW_API=1` exposes `POST /api/preview` and `POST /api/jobs/dry-run`. Disabled by default to reduce attack surface.
- `VIDRA_ENABLE_DOWNLOAD_SOCKET=1` re-enables the legacy `/ws/downloads` channel; the new per-job sockets stay enabled regardless.

## Localization & assets

- Translations live under `i18n/locales/<iso-code>/`. Use the helper scripts in `tool/` (e.g., `auto_translate_locales.py`, `generate_translation_progress.py`) to keep locales in sync.
- The `assets/` directory holds icons, animations, and `.env` templates. All referenced assets are declared in `pubspec.yaml`.

## Testing & QA

| Scope | Command |
| --- | --- |
| Python backend | `cd app && pytest` (or `python -m pytest`) |
| Flutter widget/unit tests | `flutter test` |
| Integration smoke test | `flutter test --tags integration` (tests under `test/` and `test/backend/`) |

Use `VIDRA_SERVER_DATA` to point tests at a temporary directory so logs are isolated per run.

## Documentation & troubleshooting

- `docs/system-architecture.md` – end-to-end overview of the Flutter client, FastAPI backend, sockets, and packaging flow.
- `docs/client-flows.md` – English descriptions of UI flows mapped to REST/WebSocket contracts.
- `docs/typed-architecture.md` – explains the typed model refactor and state layers inside the backend.
- `docs/backend-job-lifecycle.md` – canonical reference for job states, transitions, and related endpoints.
- `docs/configuration-and-ops.md` – environment variables, logging targets, and ops runbooks.
- `docs/troubleshooting.md` – symptom → cause → fix catalog for packaging, sockets, and localization failures.
- `temp/native-crash.txt` – crash dump location; include it with bug reports.
- Structured logs are written to `<VIDRA_SERVER_DATA>/release_logs.txt` automatically at runtime.

## Contributing & security

- Read `CONTRIBUTING.md` for coding standards, branching strategy, and review expectations.
- Vulnerability disclosures go through `SECURITY.md`.
- Please keep `git` history clean and avoid force-pushing to `main`.

## Licensing & attribution

- Project licensing follows the root `LICENSE` file.
- Every third-party dependency (Python + Flutter) is documented in [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md), with verbatim license texts stored under `third_party_licenses/` for inclusion in installers.
- Remember that `mutagen` is GPL-2.0-or-later; distributing Vidra to end users requires shipping the corresponding backend sources to satisfy GPL obligations. 