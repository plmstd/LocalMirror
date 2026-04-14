# YeOldBackup

YeOldBackup is a macOS **mirror backup** utility for local folders and external drives. It keeps the target in sync with the source, including deletions, but now routes every run through a structured preflight review before the destructive phase begins.

## What Changed

- Bundled `rsync` helper inside the app instead of depending on the live `/usr/bin/rsync` path at runtime.
- File-backed persistence under `~/Library/Application Support/YeOldBackup/` for settings, saved pairs, run history, and full logs.
- Mandatory preflight review for **every** mirror run.
- Canonical-path validation to block unsafe selections such as same-folder, nested-folder, home-folder, or protected top-level targets.
- Target-volume identity validation for external drives.
- Typed confirmation for high-risk destructive runs.
- Structured run lifecycle with explicit `preflighting`, `review`, `running`, `cancelling`, `completed`, `failed`, and `cancelled` states.
- Full log retention on disk with an in-app “Open Full Log” action.

## Safety Model

YeOldBackup is intentionally conservative:

- It is **mirror-only**.
- The target **will be made to match the source**.
- Files missing from the source **will be removed from the target**.
- Every run starts with a dry-run preflight that computes the planned changes.
- Runs are blocked if the selected target is unsafe or the mounted target drive does not match the saved drive identity.
- High-risk runs require the user to type the target volume or folder name exactly before the mirror phase can start.

Network shares are currently treated as **best effort only**. The hardened workflow is optimized for local folders and removable drives.

## App Layout

- `YeOldBackup/Core`
  - Shared models, path validation, volume identity resolution, rsync output parsing, orchestrator.
- `YeOldBackup/Services`
  - Bundled-rsync discovery and the concrete `RsyncSyncEngine`.
- `YeOldBackup/Storage`
  - File-backed persistence and migration from the previous `@AppStorage` layout.
- `YeOldBackup/App`
  - The app model and System Settings helper.
- `Tests/YeOldBackupCoreTests`
  - Parser, validator, store, and orchestrator tests via SwiftPM.

## Local Development

Build the app from Xcode or from the command line:

```bash
xcodebuild -project YeOldBackup.xcodeproj -scheme YeOldBackup -configuration Debug -derivedDataPath /tmp/YeOldBackupDerived CODE_SIGNING_ALLOWED=NO build
```

Run the fast core test suite:

```bash
swift test
```

## Releasing

The project ships as a direct-download macOS app, not a Mac App Store app.

- Release build helper: [`scripts/build-release.sh`](/Users/benny/Desktop/projects/YeOldBackup/YeOldApp/scripts/build-release.sh)
- Notarization helper: [`scripts/notarize-app.sh`](/Users/benny/Desktop/projects/YeOldBackup/YeOldApp/scripts/notarize-app.sh)
- End-to-end release notes: [`docs/RELEASE.md`](/Users/benny/Desktop/projects/YeOldBackup/YeOldApp/docs/RELEASE.md)

## Important Notes

- Full Disk Access may still be required for some source trees or destination volumes. The app no longer hard-blocks folder selection when FDA is missing; instead, it reports permission issues during preflight.
- Cancelling a run does not guarantee a clean rollback. A cancelled mirror run should be treated as a partially synced target until the next successful preflight and mirror run completes.
- The vendored helper in this repo is the current environment’s universal `rsync` binary. If you want a newer pinned release later, replace `YeOldBackup/Helpers/rsync` and re-run the signing/notarization flow.
