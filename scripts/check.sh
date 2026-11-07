#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift format lint --strict --recursive Sources Tests
swift test
./scripts/build-app.sh
python3 scripts/review-dependencies.py
