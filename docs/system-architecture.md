# System Architecture

**Who:** Engineers working across Flutter, Python, and packaging layers.
**Why:** Understand how Vidra stitches together the Flutter desktop client, embedded Starlette backend, yt-dlp workers, sockets, and packaging pipeline so changes remain coherent.

## Components at a glance

| Layer            | Location                       | Responsibilities                                | Notes                                                                 |
| ---------------- | ------------------------------ | ----------------------------------------------- | --------------------------------------------------------------------- |
| Flutter client   | `lib/`                         | UI, state management, caching, localization     | Uses `provider` and the `serious_python` plugin to bootstrap backend. |
| Embedded backend | `app/src/`                     | REST + WebSocket API, job orchestration, hooks  | Starlette + Uvicorn + yt-dlp. Request/response validation uses Marshmallow schemas under `app/src/models/api/`. |
| Packaging bundle | `app/app.zip`                  | Distributable Python environment                | Built via `serious_python`. Extracted on first run.                   |
| Native shell     | `windows/`, `macos/`, `linux/` | Platform embedding for Flutter                  | Launch script sets env vars (`VIDRA_SERVER_DATA`, etc.).              |
| Ops tooling      | `tool/`, `docs/`, `scripts`    | Localization, translation, packaging automation | Scripts are Python or Dart CLIs.                                      |

## Runtime flow

```mermaid
flowchart LR
    subgraph Client[Flutter Client]
        UI[Widgets]
        State[State stores]
        Cache[Disk cache]
    end
    subgraph Backend[Embedded Starlette]
        API[REST + WebSockets]
        Manager[DownloadManager]
        Store[DownloadStateStore]
        Hooks[Hook runners]
    end
    subgraph Engine[yt-dlp]
        Core[yt-dlp binary]
    end
    subgraph Packaging[serious_python runtime]
        Venv[Embedded virtualenv]
    end

    UI -->|User actions| State
    State -->|HTTP| API
    API --> Manager
    Manager --> Store
    Manager --> Hooks
    Hooks --> Core
    Core --> Manager
    Manager -->|Socket events| State
    Cache <-->|Snapshots| Store
    Packaging --> Backend
```

### Cold-start sequence

1. Flutter launcher unzips `app/app.zip` (if necessary) to the platform app-support directory via the `serious_python` plugin.
2. Plugin spawns the Python entrypoint (`src/main.py`) with the environment derived from the embedded `.env` plus runtime overrides.
3. The Starlette app boots, restores persisted job state, and opens WebSocket endpoints (`/ws/...`).
4. Flutter UI renders splash, pings the health endpoint (default `/`) and then `GET /api/jobs` to bootstrap the queue.
5. Once healthy, widgets transition to the queue view and subscribe to sockets per job.

### Steady-state interactions

- **Commands:** UI invokes REST endpoints (`POST /api/jobs`, `POST /api/jobs/{id}/pause`, etc.). These map to typed request models and feed the `DownloadManager`.
- **Streaming updates:** Each job exposes a dedicated WebSocket that emits `JobProgressEvent`, `PlaylistUpdateEvent`, and `LogEvent` objects.
- **Persistence:** `DownloadStateStore` writes JSON snapshots (`DownloadJobSnapshot`) to disk. On restart, the backend rehydrates state before reopening sockets.
- **Hooks and automation:** Download/postprocessor hooks are internal callbacks that turn yt-dlp events into log/socket payloads.

### Packaging pipeline overview

```mermaid
sequenceDiagram
  participant Dev
  participant SeriousPython as serious_python CLI
  participant Bundle as app/app.zip
  participant Flutter as Flutter build
  participant Installer
  Dev->>SeriousPython: dart run serious_python:main package app/src -p <platform>
  SeriousPython-->>Bundle: zip runtime + hashes
  Dev->>Flutter: flutter build windows/macos/linux
  Flutter-->>Installer: desktop binary + assets (including app/app.zip)
  Installer-->>User: Deploy + configure shortcuts
```

Key artifacts:

- `app/app.zip` and `app/app.zip.hash`: embedded backend bundle.
- Flutter assets manifest (`pubspec.yaml`) lists the bundle and ensures it ships with every build.
- Windows installer (Inno Setup, `installer.iss`) copies third-party licenses from `third_party_licenses/`.

## Dependencies between domains

| Dependency                     | Direction             | Reason                                                |
| ------------------------------ | --------------------- | ----------------------------------------------------- |
| Flutter → backend              | REST, sockets         | Command/control plane.                                |
| Backend → yt-dlp               | CLI invocation        | Actual downloads and metadata extraction.             |
| Backend ↔ Hooks                | JSON config           | Extensibility for notifications, post-processing.     |
| Flutter ↔ Localization scripts | JSON exports          | Ensure UI strings stay in sync with translation data. |
| Packaging → Ops docs           | Build reproducibility | Release engineers rely on docs to package correctly.  |

## Failure domains & mitigation

- **Backend crash**: Flutter detects socket drop + failed health check, surfaces restart CTA. Logs under `<VIDRA_SERVER_DATA>/release_logs.txt`.
- **Bundle mismatch**: `serious_python` validates `app/app.zip.hash`. Rebuild via VS Code task if hash mismatch occurs.
- **Socket churn**: Client throttles reconnect attempts and falls back to polling `GET /api/jobs/{id}` if sockets fail repeatedly.
- **yt-dlp schema drift**: backend normalizes raw yt-dlp output before exposing it to the client; treat raw payloads as unstable.

## See also

- `docs/client-architecture.md` for Flutter-specific layout and state patterns.
- `docs/backend-job-lifecycle.md` for the detailed state machine powering the manager.
- `docs/packaging-and-release.md` for exact commands, VS Code tasks, and signing steps.
