# PhraseLilt

A local-first native macOS utility for practising the English sentences you actually use. **Source-available; free for noncommercial use.** Provisional name.

Speech recognition can understand you even when pronunciation differs from your chosen reference. PhraseLilt keeps the original audio so you can listen and practise. It does **not** equate recognition success with pronunciation correctness.

## Current capabilities

- Menu-bar review, resizable practice window and native Settings; system light/dark appearance.
- Hold Control–Option–Space (or choose R/P) to record; release to stop. Clickable Record, Stop and Cancel are available. No automatic pasting or focus change when a clip finishes.
- Local English transcription using Apple's SpeechTranscriber. Confirm or edit intended wording separately from raw recognition. Transcription is optional: enter wording yourself if the model is unavailable.
- You / Reference playback, timed segment selection when wording matches the recognition, whole-sentence playback after edits, and retries grouped for comparison. Timing is approximate and is not pronunciation assessment.
- US or UK system voice references. US voices are General American-oriented; UK voices are southern British-oriented. Neither represents all legitimate accents. Listen to the named installed voice in Settings; names and unfamiliar vocabulary may be pronounced poorly.
- WAV/M4A import copies the original into managed storage. Limit: 25 MB, 0.2–60 seconds, one or two channels, 8–192 kHz. At most 100 clips.
- Seven-day default deletion of unsaved clips; saved clips stay until deleted. Settings offers 1/7/30 days and Delete All.

**Automatic pronunciation assessment is experimental and unavailable.** No phoneme diagnosis, accent grade, confidence percentage or proficiency score is produced. The initial tip is explicitly general practice advice. Acoustic signal checks can flag near-silence or clipping, never an accent problem. [Why assessment is withheld](docs/MODELS.md).

## Build and launch

Requires **Apple Silicon, macOS 26+, Xcode 26 with Swift 6.2+**, and Command Line Tools selected for Xcode. Development baseline: M5 / 32 GB / macOS 26.2 / Xcode 26.3. Intel and older macOS are unsupported. M1/8 GB is a compatibility target, not a tested performance promise.

```sh
./scripts/build-app.sh
open dist/PhraseLilt.app
```

The script creates an app bundle and signs it ad hoc for local use. It is **not Developer ID signed or notarized**. Builds stay in ignored `dist/`. No external Swift packages are required.

```sh
./scripts/check.sh
# Individual checks:
swift test
swift format lint --strict --recursive Sources Tests
python3 scripts/review-dependencies.py
```

CI uses a macOS 26 runner, minimal read permissions and an immutable checkout action revision. It runs the same formatting, unit/integration, dependency and packaged-build checks. Compiler/SDK and system assets can vary across Xcode/macOS updates; bit-for-bit binary or model reproducibility is not claimed.

## First run and offline use

1. Open Settings; choose American or British reference and a shortcut.
2. Click **Download English Model** if needed. This explicitly asks macOS to install that locale's local assets. The API does not expose a preflight byte count. Keep **2 GB free as a precaution**, not a measured download-size claim. Cancellation is available; macOS controls shared partial downloads and resumption.
3. Choose an installed reference voice. Download additional voices in System Settings → Accessibility → Read & Speak if necessary. Voice/model storage is shared and OS-managed, outside the app's retention controls.
4. Allow Microphone when you first record. No screen recording, Accessibility, broad file access, account, backend, telemetry or cloud inference is used.
5. Test Reference and a clip once. Once assets are installed, core operation uses local APIs. There is no cloud fallback. The app has no network-client entitlement.

The developer probe can inspect model readiness without recording:

```sh
swift run SpeechProbe
# Explicit OS asset installation for US English:
swift run SpeechProbe --install
# Synthetic/non-sensitive local file only; probe prints recognition to the terminal:
swift run SpeechProbe /absolute/path/to/test.wav
```

On the development M5, a synthetic 2.10 s sentence transcribed correctly into seven timed segments: first measured call 2.37 s, warm call 0.36 s with process networking denied. The probe process peak RSS was about 18 MB; **this excludes Apple's speech service and shared model memory**. These are one-clip pipeline measurements, not accuracy or complete system-memory benchmarks. No consented human evaluation has been performed. Actual model bytes and total service memory remain unmeasured. See [evaluation requirements](docs/EVALUATION.md).

## Privacy and limitations

See [privacy and retention](docs/PRIVACY.md), [architecture](docs/ARCHITECTURE.md), [model decisions](docs/MODELS.md), and [signing](docs/BUILDING.md). Files use private app storage and file permissions, without application-level encryption. Backups may retain deleted material. No secure-erasure claim.

The rendered empty/review/Settings states, import and model setup, wording confirmation and playback controls were exercised through native accessibility automation. Dark appearance and a debug-only light/small-window configuration were visually inspected. Remaining verification includes real hardware input changes and sleep/lock interruption, global shortcut behavior across other applications, offline operation with all device networking disabled, VoiceOver auditory review, and increased contrast/Reduce Motion checks. Synthetic fixtures cannot establish useful pronunciation coaching. Assessment must stay unavailable until a relevant, consented and reviewed evaluation supports it.

## License

Copyright © 2026 Elliot Boucher. [PolyForm Noncommercial 1.0.0](LICENSE), unmodified. This is **source-available**, not OSI-approved open source. Its commercial-use restrictions are broader than a ban on selling competing apps, and may include internal commercial workplace use. No workplace exception is added. The original copyright holder retains rights to their own code; other contributors and dependencies retain theirs. See [third-party notices](THIRD_PARTY_NOTICES.md).
