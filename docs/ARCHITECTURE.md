# Architecture

Swift package with three small parts: `PracticeCore`, the SwiftUI/AppKit menu-bar app, and a developer-only `SpeechProbe`. No server or plugin system.

`PracticeSession` is a main-actor state owner. It holds recording/request/processing state and a selected clip. `Recording`, `Transcribing` and `ReferenceSpeaking` provide replaceable boundaries. Replay alignment is a `WordSegment` value from recognition; it is not forced alignment and there is no separate aligner runtime. Acoustic assessment intentionally has no model implementation. The signal gate is isolated in `AudioValidator`.

`MicrophoneRecorder` requests permission only on explicit start, and writes mono AAC to private temporary managed storage. Both recorder and session invalidate pending permission requests on release/cancel. AVAudioRecorder's duration limit and a session deadline stop before 60 seconds. Carbon RegisterEventHotKey receives press/release without Accessibility or an event tap; a key-state watchdog recovers missing release events. Registration conflicts are visible. AppKit observes sleep/session deactivation and default-input changes to cancel. Native controls remain usable without the shortcut.

`PracticeSession` assigns every transcription a clip ID, revision UUID and reference variety. Deletion, edits, reference changes, selection changes and replacement invalidate/cancel work. Results must still match before saving. Task cancellation calls `SpeechAnalyzer.cancelAndFinishNow`. Intent and raw results persist separately; retries carry a snapshot of confirmed wording and group ID, not findings or recognition.

`ClipStore` is main-actor serialized, capped at 100 clips and a bounded JSON index. Imports are validated and copied under UUID filenames; original paths are not persisted. Writes are atomic; index corruption fails closed instead of silently resetting history. Startup removes orphan recording/import files. A clip's audio is removed before index removal; failed deletion remains retryable. Sudden termination can leave a metadata/audio discrepancy; it does not produce a secure-erasure guarantee. Retention runs on launch, settings changes and hourly while open.

SwiftUI provides native controls, labels, scrollable content, resizable practice and keyboard focus behavior. AppKit creates the practice window explicitly because menu-bar-only launch semantics do not guarantee a SwiftUI Window scene opens. Dock presence is limited to the open practice window. Recording completion never opens or activates a window. Playback stops before recording, switching clips, changing reference/wording or deletion. User speech and system speech never produce an objective comparison score.

No audio or transcript is logged by the app. The developer probe deliberately prints synthetic-test results and must not be used for private recordings in shared logs.
