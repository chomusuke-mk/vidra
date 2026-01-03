# GPU-Aware Recoding Upgrade Plan

Plan to add a `use_gpu: bool` option in incoming requests that enables GPU-accelerated codecs during audio/video recoding when available (Android/Windows/Linux). Keep current behavior when false; auto-fallback to CPU when a suitable GPU path is unavailable.

## Goals and Constraints
- Maintain backward compatibility: default remains CPU paths unless `use_gpu` is true.
- Prefer hardware-backed codecs when possible; otherwise, transparently fall back to existing software codecs.
- Keep per-platform safety checks (capability detection, ffmpeg availability, hardware present).
- Preserve deterministic behavior: no silent degradation beyond the defined fallbacks.

## Implementation Steps
1) **Extend API contract**
   - Add `use_gpu: bool` to incoming request schemas (HTTP and websocket requests, Marshmallow schemas, dataclass models, TypedDict payloads).
   - Update validation defaults to `False`; reject non-bool inputs.
   - Document the new field in API docs and examples.

2) **Plumb option through job creation**
   - Carry `use_gpu` from request parsing into `CreateJobRequest` / job metadata and persisted state.
   - Ensure serializers/deserializers include the field so restarts keep the intent.

3) **Define platform capability detection**
   - Implement a helper that evaluates the runtime platform and available ffmpeg encoders/decoders.
   - Suggested checks:
     - Android: prefer `h264_mediacodec` if `ffmpeg -encoders` lists it and the device reports MediaCodec hardware; similarly `hevc_mediacodec` when input is HEVC or target is H.265.
     - Windows: prefer `h264_amf` / `hevc_amf` when AMD GPU present; `h264_nvenc` / `hevc_nvenc` when NVIDIA GPU present; `h264_qsv` / `hevc_qsv` when Intel QuickSync present.
     - Linux: prefer `h264_vaapi` / `hevc_vaapi` when VAAPI is available (GPU + drivers) and `ffmpeg` exposes them; consider `h264_nvenc` / `hevc_nvenc` when NVIDIA stack present.
   - Cache capability probing to avoid repeated `ffmpeg` invocations.

4) **Map software codecs to GPU variants**
   - Create a mapping layer: when the pipeline requests `libx264`/`libx265` (or analogous software codecs), replace with the best supported GPU encoder if `use_gpu` is true and detection succeeded.
   - Preserve audio: use hardware-accelerated audio filters/codecs only if safe; otherwise leave audio on CPU to avoid regressions.

5) **Build GPU-aware ffmpeg command options**
   - When a GPU encoder is selected, adjust required flags (examples):
     - `h264_mediacodec`: add `-hwaccel mediacodec` if needed; ensure pixel format compatibility (e.g., `-pix_fmt nv12` when required).
     - `h264_nvenc`/`hevc_nvenc`: set `-hwaccel cuda` or `-hwaccel_output_format cuda`, configure rate control (`-rc:v vbr`), and tune preset/profile.
     - `h264_qsv`/`hevc_qsv`: add `-hwaccel qsv`, map formats to `qsv` requirements.
     - `h264_vaapi`/`hevc_vaapi`: add `-hwaccel vaapi -vaapi_device /dev/dri/renderD128`, use `-vf format=nv12,hwupload` when needed.
   - Enforce compatibility between input formats and chosen encoder; if constraints fail, fall back to CPU.

6) **Fallback and safety logic**
   - If `use_gpu` is false: keep current CPU paths.
   - If true but no supported GPU encoder is available, log a structured warning and revert to CPU codec automatically.
   - Add timeouts/guards for capability probes to avoid blocking on misconfigured systems.

7) **Surfacing in job state and logs**
   - Record chosen encoder (gpu vs cpu) in job metadata and logs for observability.
   - Expose in progress/preview payloads a simple flag like `gpu_accel: bool` and the encoder name used.

8) **Configuration overrides (optional)**
   - Allow advanced per-platform overrides (e.g., force `nvenc`, disable `vaapi`) via server config/env for troubleshooting.

9) **Testing plan**
   - Unit tests: request parsing and propagation of `use_gpu`; codec selection mapping given mocked capability data; fallback behavior when no GPU encoders are available.
   - Integration tests: ffmpeg command assembly for representative cases (Android mediacodec, Windows NVENC, Linux VAAPI) using mocked capability probes.
   - Regression: ensure `use_gpu=False` produces identical commands to current behavior.

10) **Documentation and migration notes**
    - Update README/API docs with the new option, platform notes, and fallback rules.
    - Provide a brief troubleshooting section (how to confirm ffmpeg exposes the needed encoders, how to disable GPU if unstable).
