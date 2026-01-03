# Testing Strategy

**Who:** Contributors writing backend or Flutter code, QA engineers, release managers.
**Why:** Describe the layered testing approach across Python, Flutter, and packaging to keep Vidra stable.

## Test layers

| Layer                     | Location                  | Tooling                                                     | Purpose                                                              |
| ------------------------- | ------------------------- | ----------------------------------------------------------- | -------------------------------------------------------------------- |
| Unit (backend)            | `app/tests/`              | `pytest`, `hypothesis`                                      | Validate typed models, download manager helpers, and hook utilities. |
| API/Integration (backend) | `app/tests/test_api_*.py` | `pytest` + `starlette.testclient`                           | Spin up Starlette app, cover endpoints + error handling.             |
| Widget (Flutter)          | `test/*.dart`             | `flutter test`                                              | Ensure widgets render correctly with mocked repositories.            |
| Integration (Flutter)     | `test/backend/`           | `flutter test --tags integration`                           | Drive flows end-to-end against fake backend.                         |
| E2E smoke                 | Manual / scripted         | `flutter drive` (optional)                                  | Launch packaged app, validate real backend interactions.             |
| Packaging checks          | VS Code tasks             | `dart run serious_python:main package`, `flutter build ...` | Ensure release artifacts build cleanly.                              |

## Backend testing tips

- Activate virtualenv before running tests (`cd app && . .venv/Scripts/activate`).
- Use `pytest -k job` to focus on job lifecycle tests.
- Mock yt-dlp at the domain boundary (e.g., `app/src/core/manager.py` / `app/src/core/downloader.py`) to emit synthetic payloads.
- Run `pyright` for static type enforcement of the typed architecture.

## Flutter testing tips

- Widget tests rely on fake repositories; update `test/utils/fake_api_client.dart` whenever new endpoints are introduced.
- Integration tests annotate `@Tags(['integration'])`; use `flutter test --tags integration` to run only those suites.
- For golden tests, keep reference images under `test/goldens/`. Update with `flutter test --update-goldens` when intentional UI changes occur.

## CI recommendations

1. `pytest` (backend)
2. `pyright` (typechecking)
3. `flutter test` (unit/widget)
4. `flutter test --tags integration`
5. Packaging smoke (`dart run serious_python:main package ...`)

Use caching for `.venv`, `.dart_tool`, and Flutter pub cache to reduce runtimes.

## Data seeding for manual QA

- Persisted state is stored in `<VIDRA_SERVER_DATA>/download_state.json`. For manual QA, prefer creating a few jobs through the UI to generate realistic snapshots.

## See also

- `docs/backend-job-lifecycle.md` to understand expected state transitions during tests.
- `docs/client-flows.md` for scenarios that integration tests must cover.
- `docs/packaging-and-release.md` for build validation steps tied to releases.
