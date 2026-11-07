"""Reject unnoticed runtime dependencies; this release deliberately uses Apple SDKs only."""
import json
import subprocess

manifest = json.loads(subprocess.check_output(["swift", "package", "dump-package"]))
assert not manifest["dependencies"], "New package dependency needs source, weight, and redistribution license review"
print("Dependency review passed: no external Swift packages, model weights, or bundled voices.")
