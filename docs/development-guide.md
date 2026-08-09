# Development, Packaging, and Troubleshooting Guide

This document centralizes the guidelines for daily development, quality testing, the packaging flow for releases, and solutions to the most common issues in the Vidra development environment.

## 1. Full Local Compilation

To compile Vidra entirely from source and test it locally, you need to coordinate the Flutter client alongside the Python backend injected by `serious_python`.

### Environment Variables

The packaged backend requires certain variables to locate itself correctly when you run the project locally. In Visual Studio Code (via `launch.json`), these variables are usually configured automatically if you run the build tasks, but for manual execution in the console, you need to define them:

- `SERIOUS_PYTHON_SITE_PACKAGES`: Must point to the `.serious_python/site-packages` directory inside your local repository.
- `SERIOUS_PYTHON_APP`: Must point to `.serious_python/app`.

### Native Dependencies: FFmpeg and QuickJS

For proper development functionality, Vidra requires external executables (`ffmpeg`, `ffprobe`, and `quickjs`) that are automatically downloaded and managed during the CI/CD pipeline (GitHub Actions).

If you compile the application locally manually, make sure to provide these executables in the following paths depending on your operating system:

| Platform    | Target directory in the project                                                     |
| ----------- | ----------------------------------------------------------------------------------- |
| **Windows** | `windows/ffmpeg.exe`, `windows/ffprobe.exe`, `windows/quickjs.exe`                  |
| **Linux**   | `linux/ffmpeg`, `linux/ffprobe`, `linux/quickjs`                                    |
| **Android** | `android/app/src/main/jniLibs/<abi>/libffmpeg.so`, `libffprobe.so`, `libquickjs.so` |

_(Where `<abi>` can be `arm64-v8a`, `x86_64`, or `armeabi-v7a`)._

### Logic Packaging (serious_python)

If you make changes to the Python code inside `app/src` or prepare the environment for the first time, you need to re-package the engine before compiling Flutter:

```bash
dart run serious_python:main package app/src -r -r -r app/requirements/base.txt -r -r -r app/requirements/Windows.txt -p Windows --verbose
```

_(Change `Windows` and `Windows.txt` to your target platform: `Linux`, `Android`, etc.)_

### Run the Client

Once the backend is packaged and native dependencies are in place, the Flutter build engine will integrate it automatically:

```bash
flutter pub get
flutter run -d windows
# or linux, android, etc.
```

## 2. Testing Strategy

We maintain code quality by separating tests into different levels.

| Scope                  | Execution Command                         | Purpose                                                    |
| ---------------------- | ----------------------------------------- | ---------------------------------------------------------- |
| **Unit Tests**         | `flutter test`                            | Validate isolated Flutter logic, models, and utilities.    |
| **Integration Tests**  | `flutter test --tags integration`         | End-to-End: Ensure the UI interacts well with the Backend. |
| **Backend Tests (Py)** | `pytest` (inside `app/src` if applicable) | Ensure proper API parsing, yt-dlp, and ffmpeg.             |

**Log Isolation:**
During automated testing, it is recommended to export the `VIDRA_SERVER_DATA` variable pointing to a temporary directory (e.g., `/tmp/vidra_tests`). This ensures that the backend logs from tests do not collide with the logs from your daily use of the application.

## 3. Packaging and Releases

The official deployment process is automated via **GitHub Actions** (`.github/workflows/vidra-release.yml`).

### CI/CD Flow Overview

1. **Download backend source code:** Retrieves `app.zip` from the main backend repository.
2. **Fetch precompiled binaries:** Downloads FFmpeg and QuickJS binaries for each architecture (e.g., `x86_64`, `arm64-v8a`).
3. **Engine generation:** Runs `serious_python:main package` to inject everything into the binaries.
4. **Flutter compilation:** Calls `flutter build apk`, `flutter build windows`, `flutter build linux`, etc.
5. **Signing and Installer creation:** Generates `.deb`, `.AppImage`, `.exe` (via Inno Setup), and packages the APKs along with `SHA2-256SUMS.sig` signatures.

**Note:** If you are going to publish locally, you can replicate the Action commands by reading the YAML file step by step.

## 4. Troubleshooting

### The Backend server fails to start (SystemState remains in `startingBackend` or `fatalError`)

- **Possible Cause:** The Python application needs to be packaged, or native dependencies (FFmpeg/QuickJS) are not in the correct path.
- **Solution:** Re-run the `dart run serious_python:main package...` command and ensure you have copied `ffmpeg.exe` or `libffmpeg.so` to the paths specified in the `README.md`. Check the local log at `~/.cache/vidra/logs/server.log` (or its equivalent in AppData/Temp depending on the platform).

### Package version issues (`pub get` fails)

- **Possible Cause:** Strict dependency conflicts, especially if `serious_python` was updated.
- **Solution:** Run `flutter pub outdated` and evaluate. Delete `pubspec.lock` and attempt a clean `flutter pub get`.

### Video downloads fail inexplicably

- **Possible Cause:** YouTube or other portals frequently change their website structure.
- **Solution:** `yt-dlp` must be on the latest version. Update the backend by downloading the latest Python dependencies and injecting a new `app.zip`. If using a CI-generated installation, wait for the next OTA patch.

### The graphical interface does not respond

- **Possible Cause:** Expensive code blocking the Dart thread in the UI.
- **Solution:** HTTP network communication with localhost does not block the thread, but ensure you are not reading massive log files synchronously (`readFileSync`). All heavy I/O must be delegated asynchronously or managed directly by the backend Isolate.
