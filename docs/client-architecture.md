# Client Architecture

**Who:** Flutter engineers and reviewers.
**Why:** Describe how the Vidra desktop client is organized, how it manages state, and how it talks to the embedded backend.

## Project layout

```
lib/
├── main.dart               # entrypoint, sets up providers, routing
├── config/                 # runtime config, feature flags, API endpoints
├── constants/              # colors, spacing, typography
├── data/                   # services + models for REST access
├── i18n/                   # localization delegates + generated strings
├── models/                 # plain Dart models mirroring backend payloads
├── state/                  # ChangeNotifiers/controllers + backend bootstrap
├── ui/                     # widgets grouped by feature (home, detail, settings)
├── utils/                  # formatters, error mappers
└── share/                  # share-intent/desktop share helpers
```

## State management

- Uses `provider` + `ChangeNotifier` for app-wide stores.
- Each domain (jobs, playlist, settings) has:
  - `Service` (HTTP calls via `lib/data/services/download_service.dart`).
  - `Controller/Store` (ChangeNotifier / controller) exposing derived view models.
- Error handling is centralized so snackbars/toasts share consistent copy.

## Networking stack

| Layer                     | Responsibility                                                                      |
| ------------------------- | ----------------------------------------------------------------------------------- |
| `data/services/download_service.dart` | Wraps `http` package, handles redirects, errors, and decoding.             |
| `state/download_controller.dart`      | Manages WebSocket lifecycle (overview + per-job) and keeps UI state in sync. |
| `models/*`                            | Model classes for decoding JSON payloads from REST/sockets.                 |

### Socket lifecycle

1. Job store subscribes when a job appears in the visible list.
2. Each socket heartbeat updates progress/log state; reconnection uses exponential backoff.
3. When a job hits a terminal state, the store disposes the channel and removes cached listeners to prevent leaks.

## Caching strategy

- User settings (theme, language, defaults) are stored via `shared_preferences`.
- Network-heavy UI elements (e.g., thumbnails) rely on the standard Flutter image caching stack (e.g., `cached_network_image`).

## Offline/resilience behavior

- If REST calls fail due to `SocketException`, stores surface cached data with a `STALE` badge so users know they are offline.
- Actions (pause/cancel) use optimistic updates. If backend rejects the change, the store rolls the UI back and shows an error toast referencing `request_id` from the backend response.

## Background services

- `serious_python` is used during startup to ensure the embedded backend is available before the main UI flow proceeds.
- Release update information is cached (see `lib/state/release_update_cache.dart`) to avoid repeated network calls.

## Testing approach

- Widget tests live under `test/` (e.g., `home_screen_test.dart`, `settings_screen_test.dart`).
- Integration tests under `test/backend/` spin up a fake backend that mirrors key endpoints. Use them when adding new flows in `docs/client-flows.md`.

## See also

- `docs/client-flows.md` for the user-facing flow map.
- `docs/system-architecture.md` for how the client interacts with the backend and packaging layers.
- `docs/testing-strategy.md` for specifics on Flutter vs. backend test coverage.
