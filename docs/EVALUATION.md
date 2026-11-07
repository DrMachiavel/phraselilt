# Evidence and assessment release gate

Current status: working local replay/reference/practice loop; **zero validated diagnostic findings**. Recognition-correct synthetic speech verifies data flow and approximate timing only. No consented human speech set has been evaluated, so false corrections, usefulness, pronunciation coverage and human-set abstention are **not measured**. Assessment always abstains from diagnosis. No educational efficacy claim.

Before enabling acoustic diagnosis, collect consented clips outside the repository with separate permission for evaluation/storage, and human-reviewed intent and pronunciation expectations. Keep names and recordings private. Include:

- Clearly spoken spontaneous work sentences and retries with known wording.
- Recognition-correct clips with human-audible differences in sounds or stress.
- Legitimate General American, southern British and regional variants; accepted alternatives should not trigger correction.
- Ambiguous intended words such as browser/brother, confirmed by the speaker before assessment.
- Silence, clipping, low volume, background noise, input failures and difficult microphone conditions.
- Work vocabulary, acronyms, unfamiliar names and unseen speakers/language backgrounds.

Have qualified reviewers independently label supported corrections, acceptable variants, unclear evidence and useful practice targets. Resolve disagreement; do not force a single accent norm. Split development and held-out speakers. Evaluate the actual selected weights and acoustic feature pipeline, not just a scorer on precomputed features. Independently audit all source/model/dataset licenses and checkpoint loading safety.

Track per category: false corrections among acceptable variants; supported/useful suggestions rated by reviewers; missed supported opportunities; abstentions and reasons; end-to-end latency; peak app plus worker/system-service memory; model disk and download size. Preserve denominators and disagreement; do not invent confidence percentages or generalize from a tiny sample. Choose acceptance criteria with reviewers before viewing held-out results. If any category lacks evidence, abstain for it.

A synthetic pipeline sentence (“Please open the browser before the meeting.”) was correctly transcribed with seven timing segments on the development M5. First measured latency was 2.37 s, warm 0.36 s. A process-network-denied run succeeded with installed assets. The observed ~18 MB probe RSS excludes the speech daemon and shared model footprint; it is not total memory usage. This does not constitute a machine-wide offline test or coaching evaluation.

Release verification still needs human VoiceOver listening/focus review, real input-device changes, sleep/lock interruption, parallel-capture and source-boundary checks, noisy human speech, and a full machine-network-disabled run. Keep assessment unavailable while the acoustic gate remains unresolved.

Companion capture adds an independent release gate: public activity readability alone is insufficient. Validate concurrent input with the actual dictation app and hardware; assess onset truncation, trailing cutoff, standby microphone state, headset profiles and unchanged text insertion. See COMPANION.md. Audio from these checks stays outside the repository and CI.
