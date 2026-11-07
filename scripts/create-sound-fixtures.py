"""Create invented synthetic test fixtures outside Git. Not coaching-accuracy evidence.

Usage: python3 scripts/create-sound-fixtures.py /absolute/private/evidence-dir
Copy the pinned model/vocabulary from your explicit setup into that directory.
"""
import random
import struct
import subprocess
import sys
import wave
from pathlib import Path

root = Path(sys.argv[1]).expanduser().resolve()
repository = Path(__file__).resolve().parent.parent
assert not root.is_relative_to(repository), "Keep generated evidence outside the repository"
root.mkdir(parents=True, exist_ok=True, mode=0o700)
for name, text, voice in [
    ("clear", "I think three things are ready.", "Samantha"),
    ("substituted", "I sink free sings are ready.", "Samantha"),
    ("british", "I think three things are ready.", "Daniel"),
]:
    subprocess.run(["/usr/bin/say", "-v", voice, "-o", str(root / (name + ".aiff")), text], check=True)
    subprocess.run(["/usr/bin/afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(root / (name + ".aiff")), str(root / (name + ".wav"))], check=True)
randomizer = random.Random(1)
for name in ["silence", "noise"]:
    with wave.open(str(root / (name + ".wav")), "wb") as output:
        output.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        values = [0 if name == "silence" else max(-32768, min(32767, int(randomizer.gauss(0, 0.03) * 32767))) for _ in range(32000)]
        output.writeframes(struct.pack("<32000h", *values))
print("Created synthetic fixtures. Human pronunciation accuracy remains unmeasured.")
