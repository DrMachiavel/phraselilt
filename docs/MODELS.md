# Speech and assessment decisions

## Selected runtime

Apple SpeechAnalyzer / SpeechTranscriber, macOS 26+. Its documented on-device transcription and audio-time attributes provide recognition and replay locations, **not phoneme assessment**. The installed SDK declarations and actual local-file execution were checked. The app uses only the local SpeechTranscriber module; no SFSpeechRecognizer server mode exists in the code.

Apple's AssetInventory handles installation, shared assets, integrity and OS updates. The app checks `.installed` before transcription and never downloads during recording/recognition. Installation is explicit in Settings, has progress/cancel, requires a precautionary 2 GB free storage, and reports failures with a retry action. The API does not expose stable model versions, cryptographic digests or an exact preflight download size. **App-controlled pinned/checksummed downloads are therefore not fulfilled by this implementation.** No downloaded executable code or third-party checkpoint deserialization occurs.

Reference speech uses installed AVSpeechSynthesizer voices filtered by en-US/en-GB, excluding personal and novelty voices. No voice files are redistributed. A regional label is not a phonetic specification or a promise of dialect coverage. The exact installed voice name is selectable. Kokoro is unnecessary for the replay/practice fallback and is not bundled, downloaded or licensed here.

## Alternatives investigated

[WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) now lives in argmax-oss-swift. Source/package/license were inspected at `9f99b5cb6a907730543823ad271b82532782a899`: MIT source, Swift package dependencies and separately acquired models. It remains a possible route for older systems and controlled model manifests. It was not installed or benchmarked, and no performance comparison is claimed. Neither Whisper nor WhisperKit is a pronunciation assessor.

[GOPT](https://github.com/YuanGongND/gopt) was inspected at `bed909daf8eca035095871e51642525acc5b9b55`: actual `src/models/gopt.py`, license, inference tutorial and research paper. Its BSD-3-Clause source depends on PyTorch/NumPy; waveform-to-GOP features require a Kaldi-based acoustic pipeline, not phonemization of a transcript. The tutorial requires substantial dataset preparation. The project warns of a reported inference bug; its latest push was February 2023 at inspection. Weights, upstream acoustic models, datasets and borrowed component notices require separate audits. No weights were loaded. The model is rejected for v1 integration, not declared generally ineffective.

The [GOPT paper](https://arxiv.org/abs/2205.03432) evaluates scoring correlations on SpeechOcean762. Those aggregate results do not establish safe word-specific correction of spontaneous workplace speech across US/UK variants. Dataset and language-background coverage matter. No relevant consented real-clip set was available to validate it here; the riskiest assumption remains unresolved. We do not pretend a README, synthetic clip or transcript match closes this gate.

## Sound-level highlighting investigation

[OpenPronounce](https://github.com/Halleck45/OpenPronounce/tree/74bc17ea406e6f057f15eea0e70951e1931af868) was inspected at `74bc17ea406e6f057f15eea0e70951e1931af868`: MIT LICENSE, pyproject dependencies, `phones.py`, `speech.py`, and the published benchmark results. It uses a direct Wav2Vec2 phone recognizer with expected-phone alignment and hand-set error thresholds. This is acoustic evidence, but its “confidence” values are not demonstrated calibrated diagnostic probabilities. Its [0.3.0 benchmark](https://github.com/Halleck45/OpenPronounce/blob/74bc17ea406e6f057f15eea0e70951e1931af868/benchmarks/README.md) reports word-level precision 0.196 and recall 0.732 on 500 SpeechOcean762 utterances under its stated human word-accuracy cutoff. This is insufficient evidence for marking individual letters as errors in this app, and it does not establish performance on spontaneous French-accented workplace English or accepted British variants.

The overall score also mixes transcript error rate and distance to synthetic speech, which does not meet this product's assessment contract. Default TTS uses network gTTS; its two checkpoints are fetched without app-pinned revisions in the inspected loaders. The source license does not resolve separate weight/voice/dataset and dependency redistribution obligations. No package, weights or worker were installed, and no local latency or accuracy result is claimed. Do not adopt its default score or networking behavior.

Sound-level coaching remains technically plausible with a validated acoustic assessor. UI should underline a supported sound's letter group (not rely on color alone), offer one short reviewed tip, and abstain on weak evidence. English sounds do not map one-to-one to letters; a phone-to-grapheme mapping is required in addition to phone timing. Never manufacture highlights from transcript differences, successful recognition, or the user's screenshot. Current live text therefore has no diagnostic highlights.

## Assessment contract

Original audio, raw recognition, confirmed intent, timings, reference variety and assessment status remain distinct. Successful recognition never triggers a “correct pronunciation” finding. A mismatch never triggers a correction. Browser/brother ambiguity is handled by confirming intent. After text edits, old word timings cannot be used for targeted playback. Practice retries inherit confirmed intent but receive independent recognition.

The sole acoustic analysis currently measures signal RMS and clipped-sample fraction to flag near-silence or possible distortion. Thresholds are conservative engineering heuristics, not validated microphone-quality classification; a quiet legitimate recording may be rejected. No noise classifier, substitution detector, stress detector or tongue-position diagnosis is implemented. General listening guidance is reviewed/static and labelled as advice, independent of recording and recognition. No text-only LLM is used.

Future assessment must accept actual sound evidence plus confirmed intent and accepted variants, emit supported findings or abstention, and clear the human evaluation gate in EVALUATION.md before any diagnostic UI is enabled. Any worker must use private pipes or a Unix socket and bounded safe model formats. Do not add a public HTTP listener.

Primary documentation: [Apple speech session](https://developer.apple.com/videos/play/wwdc2025/277/), [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber), [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory), [macOS HIG](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos).
