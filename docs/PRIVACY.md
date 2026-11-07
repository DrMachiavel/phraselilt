# Privacy and retention

The packaged app is sandboxed with only audio-input and user-selected read-only file entitlements. It requests Microphone when the user enables companion capture or starts a manual recording. Speech usage text is included for platform compatibility; the app uses local SpeechTranscriber. There is no keyboard shortcut registration, Accessibility event tap, screen recording, full-disk permission, account, network client entitlement, analytics, ads, crash uploader or backend. macOS may perform its own diagnostics and speech-asset/voice downloads under system settings.

Managed files live under the sandbox's Application Support/PhraseLilt directory. Direct unsandboxed development runs instead use the user's Application Support directory. Folder permissions are 0700 and audio/index permissions 0600. This is **not application-level encryption**. FileVault, account security and OS backups are separate protections controlled by the user. Time Machine and other backups may include recordings and survive app deletion.

The index stores clip UUID, attempt group, date, duration, raw recognition, intended wording, confirmation, save status, timestamps and reference variety. Original imported filenames/paths are not retained. No models or personal audio belong in the repository. Manual imports are copied and originals remain untouched. Audio is restricted to 25 MB / 60 s / two channels and validated before processing.

Unsaved clips expire after seven days by default; Settings offers 1, 7 or 30 days. Expiry runs on launch, when retention changes, and hourly while open. Saved clips remain until deleted. Delete Clip and Delete All cancel pending work and remove managed audio, index content, timing and assessment status. There are no extra feature caches. Playback is stopped before UI deletion. OS-managed shared speech assets/voices are not deleted by these actions.

Deletion is ordinary filesystem deletion, **not secure erasure** of SSD blocks, swap, backups or OS diagnostic records. Cancelled or crashed recording files are removed immediately when possible or recovered as orphan files on the next successful launch. Disk/permission failures are shown rather than claiming deletion succeeded.

Do not include recordings, intended text, personal paths or diagnostic archives in public issues. Only sanitized invented text and redistributable fixtures may be used in screenshots/CI.

Companion capture is off by default and must be enabled explicitly. It follows only selected app activity using public Core Audio metadata, with Other Microphone Apps separately off by default. Selected sources receive separate local microphone recordings of at most 30 seconds. This is not audio synchronization or a connection to another app account. Only source labels such as “Wispr Flow” are retained with clips; per-process IDs and raw bundle metadata are transient. Generic mode may include calls. No continuously active microphone/pre-roll is used, and ongoing sessions are skipped on enable/resume. Delete All pauses companion capture before removing history.

A short practice excerpt is a timestamp range within the same managed original, not a second audio file. Raw recognition is retained independently of the displayed excerpt wording. Deletion removes both its metadata and the full managed recording.
