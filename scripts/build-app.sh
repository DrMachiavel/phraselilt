#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
build_configuration="${PHRASELILT_BUILD_CONFIGURATION:-release}"
swift build -c "$build_configuration" --product PhraseLilt
APP="$PWD/dist/PhraseLilt.app"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$build_configuration/PhraseLilt" "$APP/Contents/MacOS/PhraseLilt"
mkdir -p "$APP/Contents/Resources/ThirdParty"
cp ThirdParty/*.txt "$APP/Contents/Resources/ThirdParty/"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/ThirdParty/"
cp App/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "${SIGNING_IDENTITY:--}" --options runtime --entitlements App/PhraseLilt.entitlements "$APP"
codesign --verify --strict "$APP"
printf 'Built %s\n' "$APP"
