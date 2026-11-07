# Contributing

Keep the core practice loop small, native and offline. Discuss any model, networking or license change before implementation. Contributions use this repository's PolyForm Noncommercial 1.0.0 terms; do not assume a commercial workplace grant.

Use Xcode 26 / Swift 6.2+, run `./scripts/check.sh`, and exercise the packaged app on macOS. Tests should verify meaningful behavior rather than mirror code. Add lifecycle/cancellation and privacy checks when changing audio or async processing. Keep external action references immutable and CI permissions minimal.

Never submit personal recordings, transcripts, model caches, credentials, signing keys, task-specific audit reports or QA screenshots. Use invented text and generated signals. Report issues with sanitized reproduction steps and platform information. No diagnosis may be inferred from recognition alone, forced-alignment output or synthetic waveform similarity. Keep the assessment release gate documented in docs/EVALUATION.md.

Companion capture must remain opt-in, bounded, source/device-scoped, and independent of Fn or private third-party data. Changes to activity detection require policy/lifecycle tests and an honest device-specific compatibility check. Do not label metadata observation as an audio integration.
