"""Allow only the reviewed, immutable optional sound-inference dependency."""
import json
import subprocess
from pathlib import Path

manifest = json.loads(subprocess.check_output(["swift", "package", "dump-package"]))
assert len(manifest["dependencies"]) == 1, "Unexpected dependency: review source, weights and notices"
lock = json.loads(Path("Package.resolved").read_text())
assert len(lock["pins"]) == 1
pin = lock["pins"][0]
assert pin["identity"] == "onnxruntime-swift-package-manager"
assert pin["location"] == "https://github.com/microsoft/onnxruntime-swift-package-manager"
assert pin["state"]["revision"] == "b7fb7f7dea8a2469e6335d95a61b8f36d0dc83b2"
for notice in ["ONNXRuntime-LICENSE.txt", "ONNXRuntime-ThirdPartyNotices.txt", "Wav2Vec2-APACHE-2.0.txt"]:
    assert (Path("ThirdParty") / notice).is_file()
assert not list(Path("Sources").rglob("*.onnx")), "Do not commit model weights"
print("Dependency review passed: pinned Microsoft ONNX Runtime, preserved notices; no bundled model weights or voices.")
