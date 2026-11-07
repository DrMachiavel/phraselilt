# Build and distribution

Select Xcode 26+ in Xcode Settings → Locations, then run `./scripts/check.sh`. Swift 6.2 and macOS 26 SDK are required. No package resolution or external model weights are needed to build. `swift format` ships in the toolchain. The package has no external dependencies; adding one requires updating the explicit dependency review gate and notices.

`./scripts/build-app.sh` assembles `dist/PhraseLilt.app`, supplies usage strings/entitlements and signs ad hoc (`-`). This is for local development only. Developer ID credentials are not present or assumed; no signed/notarized downloadable release is claimed.

To prepare a Developer ID build on a properly provisioned developer Mac:

```sh
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' ./scripts/build-app.sh
ditto -c -k --keepParent dist/PhraseLilt.app dist/PhraseLilt.zip
# Store notarization credentials privately using Apple's supported keychain flow first.
xcrun notarytool submit dist/PhraseLilt.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/PhraseLilt.app
xcrun stapler validate dist/PhraseLilt.app
codesign --verify --strict --verbose=2 dist/PhraseLilt.app
spctl --assess --type execute --verbose=2 dist/PhraseLilt.app
```

Never commit signing credentials, keychain profiles or archives. Verify microphone, imported-file sandbox access, Carbon shortcut registration, Settings and offline readiness with the final signature; changing signatures may change permission identity. Apple assets/voices remain system managed and separately licensed. No App Store readiness or notarization is implied by a passing ad hoc build.

For a local rendered-interface check only, build with `PHRASELILT_BUILD_CONFIGURATION=debug ./scripts/build-app.sh` and launch with `open dist/PhraseLilt.app --args --ui-check-light --ui-check-small`. Debug-only flags select Aqua and a 380 × 420 pt content size within this process; they do not change system appearance. Rebuild normally afterwards.
