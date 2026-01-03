# Backend: launch, token, and state synchronization

This document describes (based on the current repository code) how Vidra launches the embedded backend (Python via `serious_python`), how the access token is handled, and which files are used to persist/restore state across sessions.

## 1) Backend launch (Flutter → Serious Python)

### 1.1 Startup flow from Flutter

Startup happens in `lib/main.dart`:

- `.env` is loaded via `flutter_dotenv`.
- Backend configuration (`BackendConfig.fromEnv()`) and the auth token (`BackendAuthToken.resolve(dotenv)`) are resolved.
- Platform directories are computed using:
  - `getApplicationSupportDirectory()` → persistent support directory.
  - `getApplicationCacheDirectory()` → cache directory.
- A `backendDataDir` is created under support: `<support>/backend`.
- Launcher/backend file paths are defined under that directory:
  - `startup_status.json`
  - `vidra.start.lock`
  - `release_logs.txt`
- The launcher is invoked:

```dart
SeriousPythonServerLauncher.instance.ensureStarted(
  extraEnvironment: {
    'VIDRA_SERVER_DATA': backendDataDir,
    'VIDRA_SERVER_CACHE': '<cache>/backend',
    'VIDRA_SERVER_LOG_LEVEL': 'info',
    'VIDRA_SERVER_STATUS_FILE': backendStatusFile,
    'VIDRA_SERVER_LOCK_FILE': backendLockFile,
    'VIDRA_SERVER_LOG_FILE': backendLogFile,
    ...
  },
)
```

### 1.2 What `SeriousPythonServerLauncher` does

The core logic lives in `lib/state/serious_python_server_launcher.dart`.

High level:

1. Merge environment variables:
  - `dotenv.env` (from `.env`).
  - `extraEnvironment` (provided by `main.dart`).
2. Prepare paths under the support directory and set (if missing) these variables:
  - `VIDRA_SERVER_STATUS_FILE`
  - `VIDRA_SERVER_LOCK_FILE`
  - `VIDRA_SERVER_LOG_FILE`
3. Try to **reuse** an already running backend:
  - Check whether the port is open.
  - Call the health check and validate the `service` field matches `VIDRA_SERVER_NAME`.
  - If it matches, mark backend as `running` and do not relaunch.
4. Prevent simultaneous launches via a file lock (`vidra.start.lock`).
5. Decide whether the embedded backend needs extracting by comparing the asset hash (`app/app.zip.hash`) with the persisted hash on disk.
6. Launch the backend via `SeriousPython.run(...)`:

```dart
SeriousPython.run(
  'app/app.zip',
  appFileName: 'main.py',
  environmentVariables: env,
  sync: false,
)
```

7. Wait until the backend is ready by **monitoring the TCP port** (not just the process).
8. Write `startup_status.json` with phases like `starting`, `success`, `error`, `reused`.

## 2) Token handling (frontend and backend)

### 2.1 How Flutter resolves the token

In `lib/config/backend_auth_token.dart`:

- In **debug/profile**: requires `VIDRA_SERVER_TOKEN` in `.env` (throws if missing).
- In **release**: generates a random in-memory token (base64url).

That value (`BackendAuthToken.value`) is injected into the `DownloadController` and used to authenticate against the backend.

### 2.2 How the token is sent to the backend

In the frontend:

- HTTP: `lib/data/services/download_service.dart` adds headers when a token is present:
  - `Authorization: Bearer <token>`
  - `X-API-Token: <token>`

- WebSocket: `lib/state/download_controller.dart` appends `?token=<token>` to socket URLs (overview/job sockets).

### 2.3 How the backend validates the token

In the Python backend:

- `app/src/security/tokens.py`:
  - Reads the expected token from `VIDRA_SERVER_TOKEN` (environment variable) **at import time**.
  - Accepts tokens from:
    - `Authorization: Bearer ...`
    - `X-API-Token: ...`
    - Query param `?token=...` (for websockets)
  - Validation is strict equality: `candidate == EXPECTED_SERVER_TOKEN`.

- HTTP: `app/src/api/http.py` installs an `enforce_token` middleware:
  - Allows health-check and `OPTIONS` requests without a token.
  - For everything else: missing/mismatched token returns `401` with code `token_missing_or_invalid`.

- WebSockets: `app/src/api/websockets.py` validates the token before accepting:
  - Reads `?token=` or headers.
  - On failure: closes the socket with code `1008`.

### 2.4 Token consistency (critical)

The backend expects `VIDRA_SERVER_TOKEN` in its environment.

At the same time, the frontend uses `BackendAuthToken.value` to sign requests.

For the system to work, the token that:

- the backend expects (`VIDRA_SERVER_TOKEN` in the environment used to run `main.py`)

MUST be the same token that:

- the frontend sends (headers/query).

The launcher builds the backend environment from `dotenv.env` + `extraEnvironment`. If the token differs between both sides, the backend will return 401 / close websockets.

## 3) Persistence/state across sessions

Here, “session-to-session synchronization” means: **persisting state to disk so it can be restored on the next startup**.

### 3.1 Base directories

The backend reads two required paths from environment variables (see `app/src/config/environment.py`):

- `VIDRA_SERVER_DATA` → persistent data folder.
- `VIDRA_SERVER_CACHE` → cache folder.

In Flutter (see `lib/main.dart`) these are typically set to:

- `VIDRA_SERVER_DATA = <ApplicationSupport>/backend`
- `VIDRA_SERVER_CACHE = <ApplicationCache>/backend`

### 3.2 State files that are restored

In `app/src/download/manager.py`, `DownloadManager` initializes stores under `DATA_FOLDER`:

- `download_state.json`
  - Persisted by `DownloadStateStore` (`app/src/download/state_store.py`).
  - Contains a snapshot of jobs: `{ "jobs": [ ... ] }`.
  - Written atomically using `*.tmp` + `replace()`.

- `playlist_entries/<job_id>.json`
  - Persisted by `PlaylistEntryStore`.
  - Contains `{ "version": <ms>, "entries": [...] }`.

- `job_options/<job_id>.json`
  - Persisted by `JobOptionsStore`.
  - Contains `{ "version": <ms>, "options": {...} }`.

- `job_logs/<job_id>.json`
  - Persisted by `JobLogStore`.
  - Contains `{ "version": <ms>, "logs": [...] }`.

On startup, `_restore_persisted_jobs()`:

- Loads `download_state.json`.
- Rehydrates jobs.
- Emits websocket events with reason `RESTORED`.
- Persists again to normalize the snapshot.

### 3.3 Startup/diagnostics files

In addition to job state, the following files are used for lifecycle diagnostics:

- `startup_status.json`
  - Written by Flutter (`SeriousPythonServerLauncher`) and by the backend (`app/src/main.py`).
  - Includes phase (`starting`, `success`, `error`, `reused`), timestamps, and (on the launcher side) may include `token`.

- `release_logs.txt`
  - In `app/src/main.py`, `stdout`/`stderr` are redirected to this file (or the path pointed by `VIDRA_SERVER_LOG_FILE`).

### 3.4 How the token relates to persisted state

The token is **not** used to build file paths (there are no “per-token” directories in persistence code).

The token's role is:

- Protect backend access (HTTP/WS).
- Prevent a client without the correct token from reading/modifying persisted state.

Practical consequence:

- If the backend keeps `VIDRA_SERVER_DATA` across sessions, state is restored.
- If the expected token changes between sessions, state still exists on disk, but the client cannot access it until it uses the correct token again.

## 4) Quick debugging hints

- If the backend does not start:
  - Check `startup_status.json` and `release_logs.txt` under `VIDRA_SERVER_DATA`.
  - Verify `VIDRA_SERVER_TOKEN` is present in the backend environment.

- If you see 401 responses or websockets closing:
  - Verify the token sent by the frontend matches the token expected by the backend.
