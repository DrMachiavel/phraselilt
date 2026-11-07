# PhraseLilt

A local-first native macOS utility for practising the English sentences you actually use. **Source-available; free for noncommercial use.** Provisional name.

Speech recognition can understand you even when pronunciation differs from your chosen reference. PhraseLilt keeps the original audio so you can listen and practise. It does **not** equate recognition success with pronunciation correctness.

## Current capabilities

- One resizable native practice window. The menu-bar icon opens it; it no longer duplicates the review in a second popover.
- **Listen** plays the selected English reference, then your original audio, in one action. When existing timestamps precisely bound a complete sentence of at most 12 seconds, the companion offers that short excerpt; otherwise it keeps the full clip. The original recording stays available in Details. Edit wording only when recognition got it wrong.
- **Opt-in companion capture:** follow Wispr Flow's microphone activity without registering, observing or changing Fn. Granola is an experimental selectable source. Other microphone apps are separately opt-in and may include calls.
- Recording is a separate local microphone capture, not a recording imported from those apps. No private APIs, app databases, account connections, or transcript scraping are used.
- Only sources using the **current default input device** are eligible. Non-default or unidentified input streams are skipped. Changing the default device cancels capture.
- At most 30 seconds per automatic clip. It stops after the source becomes idle (with about 200 ms of dropout tolerance), on pause, interruption or quit. It cannot trigger itself, restart continuously from a held-open microphone, join an already-active source on enable/resume, or transfer an ongoing clip to another app.
- Local English transcription using Apple's SpeechTranscriber. Raw recognition, intended wording, original audio and reference variety remain separate. No cloud fallback.
- A quiet menu-bar cue, at most once a day, rather than notifications or automatic playback. No focus stealing or pasting.
- Import WAV/M4A copies without modifying originals. A manual practice recording and history remain under More. Limits: 25 MB, 0.2–60 seconds, one or two channels, 8–192 kHz; up to 100 clips.
- Unsaved clips expire after seven days by default (1/7/30 days in Settings); saved clips remain until deleted. Delete All also pauses companion capture.

**Companion compatibility is experimental.** Public Wispr microphone-activity reads, source-triggered recording and local transcription have been exercised on the development Mac. This does not establish absence of dictation/headset effects or complete capture of initial sounds. Audio begins after detection, so initial sounds can be missed. Some apps keep a microphone stream open even while idle; such apps may not provide usable dictation boundaries. No continuous listening or pre-roll is used to hide that limitation. Granola and other input devices require separate checks. See [compatibility notes](docs/COMPANION.md).

**Automatic pronunciation diagnosis remains unavailable.** Guided listening is available; no phoneme diagnosis, accent grade, confidence percentage or proficiency score is produced. Signal checks can flag near-silence or clipping, never an accent problem. [Assessment decisions](docs/MODELS.md).

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

1. Open Settings → Reference Voice & Offline Setup; prepare the selected English reference once if needed. This is one setup for the selected locale, not two models to manage in the practice flow.
2. Enable Companion Mode and allow Microphone. Wispr Flow is selected by default; Granola and Other Microphone Apps are off by default. Existing installations do not silently gain automatic recording.
3. Release your current dictation before testing. Use your usual Fn shortcut again. A short local clip should become available; choose **Listen** when convenient. The first capture is deliberately skipped if an app is already using the microphone when companion capture is enabled.
4. Check that Flow still inserts text normally and compare the beginning/end of both recordings. Keep companion capture paused if the source keeps its input stream open or the input device is unsupported.
5. Once speech assets and voices are installed, core features run locally. There is no cloud fallback, account, Accessibility permission, system audio capture or network-client entitlement.

Apple manages speech downloads, integrity, shared partial downloads and model updates. Installation is explicit and cancellable. Its API does not expose exact preflight sizes, stable model versions or app-verifiable hashes. Keep 2 GB free as a precaution, not a measured download-size claim. Download extra system voices through macOS Accessibility → Read & Speak. US and UK voices are General American-oriented and southern British-oriented references; neither covers every valid regional accent.

Developer diagnostics (never use private recordings in shared terminal logs):

```sh
swift run SpeechProbe
swift run SpeechProbe --install  # explicit US English asset setup
swift run SpeechProbe --observe-wispr  # 120 s, metadata only; never opens the microphone
swift run SpeechProbe /absolute/path/to/synthetic-test.wav  # prints recognition
```

On the development M5, a synthetic 2.10 s sentence transcribed correctly into seven timed segments: first measured call 2.37 s, warm call 0.36 s with process networking denied. The probe process peak RSS was about 18 MB; **this excludes Apple's speech service and shared model memory**. These are one-clip pipeline measurements, not accuracy or complete system-memory benchmarks. No consented human evaluation has been performed. Actual model bytes and total service memory remain unmeasured. See [evaluation requirements](docs/EVALUATION.md).

## Privacy and limitations

See [privacy and retention](docs/PRIVACY.md), [architecture](docs/ARCHITECTURE.md), [model decisions](docs/MODELS.md), and [signing](docs/BUILDING.md). Files use private app storage and file permissions, without application-level encryption. Backups may retain deleted material. No secure-erasure claim.

The native companion Settings, opt-in toggles, source-triggered recording/transcription, sanitized import and one-action Reference → You completion were exercised through accessibility automation. Updated light/dark and small-window layouts were visually inspected. Remaining verification includes real input-device and sleep/session interruption, unchanged Flow text insertion, headset behavior, Granola boundaries, full machine-network-disabled operation, VoiceOver auditory review and increased contrast/Reduce Motion checks. These checks do not establish validated pronunciation diagnosis; assessment remains unavailable.

## License

Copyright © 2026 Elliot Boucher. [PolyForm Noncommercial 1.0.0](LICENSE), unmodified. This is **source-available**, not OSI-approved open source. Its commercial-use restrictions are broader than a ban on selling competing apps, and may include internal commercial workplace use. No workplace exception is added. The original copyright holder retains rights to their own code; other contributors and dependencies retain theirs. See [third-party notices](THIRD_PARTY_NOTICES.md).
