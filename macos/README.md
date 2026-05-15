# LocalMirror

LocalMirror is a macOS **clone backup** utility for local folders and external drives. It keeps the target as an immediately usable copy of the source, including deletions, and routes every run through a structured preflight review before the destructive phase begins.

## What Changed

- System `/usr/bin/rsync` health-check at startup instead of bundling a helper in the app.
- File-backed persistence under `~/Library/Application Support/LocalMirror/` for settings, saved pairs, run history, and full logs.
- Mandatory preflight review for **every** clone run.
- Canonical-path validation to block unsafe selections such as same-folder, nested-folder, home-folder, or protected top-level targets.
- Target-volume identity validation for external drives.
- Target capability tracking for filesystem type, APFS readiness, read-only state, and future history support.
- Typed confirmation for high-risk destructive runs.
- Structured run lifecycle with explicit `preflighting`, `review`, `running`, `cancelling`, `completed`, `failed`, and `cancelled` states.
- Full log retention on disk with in-app log reveal and support diagnostics actions.
- A no-op snapshot service boundary so APFS clone history can be added in a later release without another architecture rewrite.

## Safety Model

LocalMirror is intentionally conservative:

- It is **clone-only** in v1.
- The target **will be made to match the source**.
- Files missing from the source **will be removed from the target**.
- Every run starts with a dry-run preflight that computes the planned changes.
- Runs are blocked if the selected target is unsafe or the mounted target drive does not match the saved drive identity.
- High-risk runs require the user to type the target volume or folder name exactly before the clone phase can start.
- APFS history is not enabled yet, but the app records target filesystem capabilities so that dedicated APFS targets can support clone history later.

Network shares are currently treated as **best effort only**. The hardened workflow is optimized for local folders and removable drives.

## App Layout

- `LocalMirror/Core`
  - Shared models, path validation, volume identity resolution, rsync output parsing, orchestrator, snapshot-service abstraction.
- `LocalMirror/Services`
  - System-rsync discovery and the concrete `RsyncSyncEngine`.
- `LocalMirror/Storage`
  - File-backed persistence and migration from the previous `@AppStorage` layout.
- `LocalMirror/App`
  - The app model and System Settings helper.
- `Tests/LocalMirrorCoreTests`
  - Parser, validator, store, and orchestrator tests via SwiftPM.

## Local Development

Build the app from Xcode or from the command line:

```bash
xcodebuild -project LocalMirror.xcodeproj -scheme LocalMirror -configuration Debug -derivedDataPath /tmp/LocalMirrorDerived CODE_SIGNING_ALLOWED=NO build
```

Run the fast core test suite:

```bash
swift test
```

## Releasing

The project ships as a direct-download macOS app, not a Mac App Store app.

- Release build helper: [`scripts/build-release.sh`](scripts/build-release.sh)
- Notarization helper: [`scripts/notarize-app.sh`](scripts/notarize-app.sh)
- End-to-end release notes: [`docs/RELEASE.md`](docs/RELEASE.md)

## Important Notes

- Full Disk Access may still be required for some source trees or destination volumes. The app no longer hard-blocks folder selection when FDA is missing; instead, it reports permission issues during preflight.
- Cancelling a run does not guarantee a clean rollback. A cancelled clone run should be treated as a partially synced target until the next successful preflight and clone run completes.
- v1 intentionally uses the macOS-provided `/usr/bin/rsync`. If a future release ships a pinned custom engine, the startup health-check and diagnostics already surface which binary is active.
