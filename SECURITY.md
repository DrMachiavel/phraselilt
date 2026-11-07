# Security

Do not post sensitive recordings, transcripts, personal paths or credentials in issues. Use GitHub's private vulnerability reporting for this repository when available; otherwise open a minimal public issue asking for a private reporting channel without exploit details or sensitive material.

Version 0.2 is an early personal utility; there is no promised response SLA. Reports involving unintended recording, stale audio/findings, path handling, import resource exhaustion, file exposure or unsafe model downloads are priorities. Include affected commit, macOS version, sanitized reproduction and expected result. Do not include other people's speech without consent.

The sandboxed build requests audio input and user-selected file reads only. No cloud inference, HTTP service or remote executable model loading is implemented. Files are protected by local permissions, not app encryption. See docs/PRIVACY.md for storage, retention, backups and deletion limits.
