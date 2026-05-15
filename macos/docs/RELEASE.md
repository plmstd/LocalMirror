# Release Guide

## Requirements

- Xcode with a Developer ID-capable signing identity
- Apple notarization credentials configured for `notarytool`
- A clean working tree

## Release Checklist

1. Run `swift test`.
2. Run a local Debug build and verify the app reports the expected `/usr/bin/rsync` installation in the header or copied diagnostics output.
3. Build the signed Release app with `scripts/build-release.sh`.
4. Submit the app with `scripts/notarize-app.sh`.
5. Staple the notarization ticket.
6. Smoke-test the notarized app on a clean Mac:
   - first-time pair selection
   - safe no-op preflight
   - deletion-heavy preflight requiring typed confirmation
   - external drive unplugged/replugged validation
   - run cancellation and log opening

## Manual Acceptance Scenarios

- First-time pairing on a local folder target
- Repeat run with zero changes
- Run with planned deletions under the typed-confirm threshold
- Run with deletions over the typed-confirm threshold
- Source appears empty while target has deletions pending
- Saved external drive missing
- Different external drive mounted at the same path
- Permission-denied subtree in the source
- Cancel during an active clone run
- Open the full log after success, failure, and cancellation
- Reveal the logs directory and copy diagnostics after a failed run

## Signing and Notarization Notes

- The app is intended for direct download with hardened runtime enabled.
- v1 uses the macOS-provided `/usr/bin/rsync`; no helper binary is bundled in the app.
- If a later release introduces a custom helper, rebuild and re-notarize before distribution.
