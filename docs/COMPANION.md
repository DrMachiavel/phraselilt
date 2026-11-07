# Companion capture

The companion follows public Core Audio process input-activity metadata. It does not intercept Fn or import audio from Wispr Flow or Granola. Both the existing app and PhraseLilt independently use the microphone after the user opts in and grants microphone permission.

`CoreAudioInputActivity` reads the public process list, PID, bundle ID, active-input flag and input-device list. It polls approximately every 100 ms while enabled. This was verified read-only on the development M5 / macOS 26.2; a 120-second run observed Wispr active/idle transitions without opening a microphone. Metadata inspection alone is not proof of successful simultaneous audio recording. Subsequent source-triggered microphone clips and local transcription were exercised on the same built-in-input setup. Unchanged text insertion, onset completeness and headset behavior still need user/hardware verification.

`CapturePolicy` handles edges and ownership. On enable, resume or scope change, current sources are blocked until idle. Only a selected source using the current default device may start capture. Own PID and own bundle/helper IDs are excluded even in generic mode. Explicitly excluded Wispr/Granola sources cannot be reclassified as generic apps. A clip stays bound to its triggering source and device. Overlapping apps cannot extend it or take ownership. An active source is latched after the 30-second limit or any manual stop; it must become idle before another clip can begin. Pausing, uncertain metadata, input changes and session interruptions cancel owned work.

The companion tolerates approximately 200 ms of missing source activity before ending capture, to avoid splitting clips on brief dropouts. Both the recorder's own duration limit and the session deadline bound automatic recordings to 30 seconds. No pre-roll or permanently running microphone is used. Detection and recorder startup can miss initial sounds; polling, service latency and audio-device startup are distinct delays. The diagnostic start delay measures **after detection**, not the gap relative to the first original audio sample.

Default scope: companion off; Wispr selected; Granola off; other apps off. Granola identification uses the `ai.granola` bundle family and remains unverified on the development machine. Generic mode follows identifiable audio processes and may include calls; it is not automatically enabled as a fallback. Non-default inputs and unidentified streams are skipped rather than recorded from an assumed device. This limitation should remain visible until device-specific capture is implemented and tested without changing system routes.

Compatibility checklist before recommending unattended use:

- Use normal Fn dictation with a non-sensitive test sentence. Verify normal text insertion, no focus/shortcut changes and a usable local recording.
- Compare first and last sounds, onset/duration, and speech/noise quality with human review. Never grade pronunciation on truncated or uncertain audio.
- Verify the app really closes its microphone between dictations. A continuously open stream cannot reliably expose dictation boundaries.
- Test built-in mic, USB and Bluetooth headsets separately, including route/profile changes. Concurrent input support is device-dependent; do not promise zero impact based on metadata alone.
- Exercise short/long dictations, cancellation, source crash, device unplug, sleep, session switching, disabled microphone permission and low storage.
- Granola meeting microphone behavior needs a separate test. Microphone sampling does not isolate the speaker, and system/remote participant audio is not directly captured.

The native Settings Compatibility Check reports completed local captures and recorder startup after detection without logging recordings or transcripts. Validated diagnosis remains unavailable. Main review plays Reference independently; Hear My Recording is optional. Experimental sound checking runs automatically after preparation when enabled and the model is installed, without opening the popover or changing dictation. Changing clip/wording/variety or beginning capture cancels pending hints.

Sources: [Apple process input activity](https://developer.apple.com/documentation/coreaudio/kaudioprocesspropertyisrunninginput), [Apple capture permission](https://developer.apple.com/documentation/bundleresources/requesting-authorization-for-media-capture-on-macos), [Wispr's normal dictation flow](https://docs.wisprflow.ai/articles/6409258247-flow-bubble-requirements), [Granola's no-stored-audio policy](https://www.granola.ai/security). Public cloud transcription APIs are not used by this app.

New clips display the full recognized recording; there is no automatic first-sentence selection. Earlier versions selected a short complete sentence while retaining full audio/raw text. Untouched automatic excerpts now expand on launch, with confirmation reset for the newly displayed full wording; edited wording is preserved. The stored recording may still be bounded by the 30-second companion limit and source activity boundaries. “Full clip” means that managed capture, not a guarantee of complete upstream dictation.
