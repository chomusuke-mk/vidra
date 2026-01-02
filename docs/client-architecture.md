# Client Architecture

**Who:** Flutter engineers and reviewers.
**Why:** Describe how the Vidra desktop client is organized, how it manages state, and how it talks to the embedded backend.

## Project layout

```
lib/
├── main.dart               # entrypoint, sets up providers, routing
├── config/                 # runtime config, feature flags, API endpoints
├── constants/              # colors, spacing, typography
├── data/                   # repositories for REST/WebSocket access
├── i18n/                   # localization delegates + generated strings
├── models/                 # freezed data classes mirroring backend DTOs
├── state/                  # providers/notifiers with caching + reducers
├── ui/                     # widgets grouped by feature (home, detail, settings)
├── utils/                  # formatters, error mappers
└── serious_python/         # platform channel glue for backend bootstrap
```

## State management

- Uses `provider` + `ChangeNotifier` for app-wide stores and `riverpod`-style selectors for view-specific derivations.
- Each domain (jobs, playlist, settings) has:
  - `Repository` (REST/WebSocket calls via `data/api_client.dart`).
  - `Cache` (disk-backed using `hive` for queue snapshots and playlist entries).
  - `Store` (ChangeNotifier) exposing derived view models.
- Structured error handling via `VidraFailure` sealed class ensures snackbars/toasts share copy.

## Networking stack

| Layer                     | Responsibility                                                                      |
| ------------------------- | ----------------------------------------------------------------------------------- |
| `data/api_client.dart`    | Wraps `http` package, injects auth headers (if any), retries idempotent calls.      |
| `data/socket_client.dart` | Manages WebSocket lifecycle per job; uses `stream_channel` to broadcast updates.    |
| `models/*`                | `freezed` classes for decoding JSON/Socket payloads (mirroring backend typed DTOs). |
| `state/jobs_store.dart`   | Orchestrates REST bootstrap + socket subscriptions.                                 |

### Socket lifecycle

1. Job store subscribes when a job appears in the visible list.
2. Each socket heartbeat updates progress/log state; reconnection uses exponential backoff.
3. When a job hits a terminal state, the store disposes the channel and removes cached listeners to prevent leaks.

## Caching strategy

- Queue snapshots saved under `%APPDATA%/Vidra/cache/jobs.json` to render instantly after relaunch.
- Playlist caches keyed by job ID; entries expire when backend signals `playlist.selection.confirmed` or `status:completed`.
- User settings (theme, default output folder) stored via `shared_preferences`.

## Offline/resilience behavior

- If REST calls fail due to `SocketException`, stores surface cached data with a `STALE` badge so users know they are offline.
- Actions (pause/cancel) use optimistic updates. If backend rejects the change, the store rolls the UI back and shows an error toast referencing `request_id` from the backend response.

## Background services

- `serious_python` plugin runs during `main()` bootstrap, ensuring backend is up before showing the home screen.
- `NotificationService` (Windows toast integration) fires when jobs complete or fail while the app is backgrounded.
- `UpdateChecker` polls GitHub releases (if enabled) and surfaces a non-blocking banner.

## Testing approach

- Widget tests live under `test/` (e.g., `home_screen_test.dart`, `settings_screen_test.dart`) and mock the repositories using `mocktail`.
- Integration tests under `test/backend/` spin up a fake backend that mirrors key endpoints. Use them when adding new flows in `docs/client-flows.md`.

## See also

- `docs/client-flows.md` for the user-facing flow map.
- `docs/system-architecture.md` for how the client interacts with the backend and packaging layers.
- `docs/testing-strategy.md` for specifics on Flutter vs. backend test coverage.
