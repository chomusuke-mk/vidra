# Vidra Documentation Expansion Plan

_Last updated: 2025-11-25_

This plan enumerates the documentation deliverables needed to cover the full Vidra stack (Flutter desktop client + embedded Python backend + packaging toolchain). Each section lists the audience, relationship to existing material, and the key content blocks to author.

## 1. Core reference set

| Doc                                                          | Status                   | Audience                    | Purpose                                                                                                                                                 |
| ------------------------------------------------------------ | ------------------------ | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `README.md`                                                  | ✅ updated links         | New contributors, operators | Keep high-level overview; link to detailed docs below once they exist.                                                                                  |
| `docs/system-architecture.md`                                | ✅ authored              | Engineers (cross-stack)     | Explain how Flutter, FastAPI, yt-dlp, sockets, and `serious_python` interact at runtime; embed sequence diagrams for cold-start and steady-state flows. |
| `docs/typed-architecture.md`                                 | ✅ refreshed             | Backend engineers           | Update with latest package layout, add example dataclasses, clarify integration points with persistence and sockets.                                    |
| `docs/client-flows.md` (renamed from `flutter_use_cases.md`) | ✅ translated + expanded | Flutter team, QA            | Provide English descriptions of UI flows, map screens to REST + WebSocket endpoints, add context on caching/offline handling.                           |

## 2. Backend-focused guides

1. `docs/backend-job-lifecycle.md` (✅ new)

   - Describe job states (`queued`, `running`, `selection_required`, `paused`, `failed`, `completed`).
   - Map REST endpoints, Pydantic payloads, and socket events per transition.
   - Highlight hooks (`postprocessor`, `post_hook.jsonc`) and how they emit structured logs.

2. `docs/configuration-and-ops.md` (✅ new)

   - Enumerate environment variables (feature flags, ports, storage paths) with defaults.
   - Document logging destinations, metrics, and how to collect crash dumps (`temp/native-crash.txt`).
   - Include guidance for running backend standalone vs. embedded.

3. `docs/troubleshooting.md` (✅ new)
   - Symptom → cause → fix tables for packaging failures, socket disconnects, yt-dlp errors, localization mismatches.
   - Reference log locations and recommended CLI probes (`serious_python ... --verbose`, `flutter logs`).

## 3. Client & localization guides

1. `docs/client-architecture.md` (✅ new)

   - Summarize Flutter layer layout (`lib/config`, `lib/state`, `lib/ui`, etc.).
   - Detail state management pattern, caching strategy, offline mode, and how sockets update views.

2. `docs/localization-and-assets.md` (✅ new)
   - Explain translation files, completion tracking (`i18n/completed_locales.txt`, `translation_progress.json`).
   - Document tooling under `tool/` (`auto_translate_locales.py`, `report_placeholder_issues.py`).
   - Cover assets pipeline (`assets/animated`, `flutter_launcher_icons`).

## 4. Packaging, release, and testing

1. `docs/packaging-and-release.md` (✅ new)

   - Walk through `serious_python` packaging per platform, artifact placement (`app/app.zip`, hashes).
   - Map VS Code tasks (`Serious Python: Package <platform> App`, `Build Android APK`) to manual commands.
   - Describe installer generation (`installer.iss`) and third-party license bundling.

2. `docs/testing-strategy.md` (✅ new)
   - Enumerate Python pytest suites (`app/tests/*`), Flutter widget/integration tests, and end-to-end smoke flows.
   - Include guidance for tagging tests (`integration`, `backend`), using mock servers, and seeding sample job data.

## 5. Execution order & dependencies

1. Translate/expand `docs/flutter_use_cases.md` into `docs/client-flows.md` first to set the tone for the English rewrite.
2. Draft `docs/system-architecture.md` referencing the updated client/backend flow terms.
3. Produce backend deep-dives (`backend-job-lifecycle`, `typed-architecture` refresh) so the operations + troubleshooting docs can link to canonical definitions.
4. Write packaging/release and localization guides, which reuse terminology from the architecture pieces.
5. Finish with troubleshooting and testing strategy once the preceding references exist.

## 6. Acceptance criteria

- All docs written in English with consistent terminology (job, playlist, selection, socket event).
- Each doc starts with a "Who/Why" block and ends with "See also" cross-links.
- README and `CONTRIBUTING.md` link to the new documents where appropriate.
- Diagrams kept lightweight (Mermaid code blocks) so they can be regenerated without external tooling.
