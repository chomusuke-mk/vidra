# Typed Model Architecture

**Who:** Backend engineers, reviewers, and tooling authors.
**Why:** Define the canonical typed models, allowed untyped boundaries, and refactor plan so the backend stays schema-safe.

This document captures the target state for eliminating ad-hoc `dict`/`Any`
payloads inside the Vidra backend. Only two boundaries are allowed to deal with
untyped mappings, and both are wrapped behind explicit adapters:

1. `app/src/core/downloader.py` + `app/src/core/contract/*`: upstream yt-dlp
   objects can change shape at runtime, so this layer keeps working with
   `Mapping[str, Any]` and converts payloads into normalized models.
2. The HTTP/WebSocket adapters (`app/src/api` and `app/src/socket_manager.py`):
   they accept raw JSON from clients, validate it, and immediately translate it
   into the typed domain models described below.

Every other module should prefer typed models under `app/src/models/` and the
normalized contract layer under `app/src/core/contract/`.

## Package layout

```
app/src/models/
├── __init__.py
├── base.py          # cross-cutting aliases/utilities (ISO timestamps, IDs)
├── json_types.py    # JSON-compatible recursive aliases
├── download/        # Download job models and persistence payloads
├── api/             # Request/response payload models
└── socket/          # Dataclasses for websocket payloads
```

Each dataclass exposes:

- Typed attributes matching the domain fields.
- `from_json`/`to_json` helpers to bridge with persistence or client payloads.
- `merge_with`/`update_from` helpers when incremental updates are required (for
  example, when playlist entries stream in progressively).

```python
@dataclass(slots=True)
class JobMetadata(JsonMixin):
   job_id: str
   kind: Literal["video", "playlist"]
   url: HttpUrl
   owner: str
   created_at: datetime
   options: JobOptions

   @classmethod
   def from_json(cls, payload: JsonObject) -> "JobMetadata":
      return cls(
         job_id=payload["job_id"],
         kind=payload["kind"],
         url=HttpUrl(payload["url"]),
         owner=payload.get("owner", "anonymous"),
         created_at=parse_iso(payload["created_at"]),
         options=JobOptions.from_json(payload["options"]),
      )
```

> All dataclasses inherit lightweight mixins (e.g., `JsonMixin`, `MergeMixin`)
> so persistence, API formatting, and socket serialization never reimplement
> codecs or merge logic.

## Flow overview

1. **Client → API**: the Starlette layer parses/validates JSON via Marshmallow schemas into request payloads,
   `PlaylistSelectionPayload`, etc. Those are converted into domain models such
   as `DownloadJobSpec` and handed to `DownloadManager`.
2. **DownloadManager / Mixins**: internal state uses `DownloadJobState`, which
   embeds `JobMetadata`, `PlaylistState`, `ProgressSnapshot`, etc. No ad-hoc
   dictionaries remain—helpers operate over dataclasses and return lightweight
   DTOs for sockets.
3. **Persistence**: `DownloadStateStore` reads/writes persisted job state to
   `<VIDRA_SERVER_DATA>/download_state.json`.
4. **Sockets**: `app/src/models/socket/*` expose dataclasses for outbound
   payloads; emitting code should avoid passing raw dicts across domain layers.
5. **yt-dlp**: `core/manager.py` and `download/hook_payloads.py` are updated to
   convert `Mapping[str, Any]` inputs into `Info`, `ProgressUpdate`, and
   `PostprocessorUpdate` dataclasses defined under `types/`. The rest of the
   application works exclusively with those models; when yt-dlp evolves its
   payloads, only the adapter requires touch-ups.

## Refactor stages

1. **Expand typed models/contracts** under `app/src/models` and
   `app/src/core/contract` and update `DownloadJob` plus persistence/state-store
   helpers to rely on them.
2. **Refactor download mixins/manager** to construct/manipulate these models
   instead of raw dictionaries, ensuring playlist/preview/progress helpers return
   typed DTOs.
3. **Update socket/API layers** to validate input JSON into typed request models
   before passing them to managers; reuse the same DTOs for responses.
4. **Sweep remaining modules** (options, utils, hooks) to replace `Any`/`Dict`
   usage with the canonical aliases or typed classes, keeping generics only at
   the two sanctioned boundaries. Add a CI/Pyright check that fails when new
   modules import `typing.Any` without a justification comment.

The refactor proceeds module-by-module; new features should reuse existing
models/contracts instead of introducing ad-hoc dict schemas.

## See also

- `docs/backend-job-lifecycle.md` for how these types flow through job states.
- `docs/system-architecture.md` for the client/backend packaging context.
- `docs/testing-strategy.md` for pyright/pytest coverage expectations on typed modules.
