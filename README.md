# LocalMirror

LocalMirror is a free, open source macOS app for manual clone backups between local folders and external drives. A simple graphical `rsync` wrapper, with a preflight review before every clone run.

LocalMirror is for people who want an immediately usable mirror of one folder or drive on another drive. It does not run in the background, upload files, schedule backups, or replace Time Machine.

## Use With Caution

LocalMirror is a clone backup tool. The target is made to match the source.

- Files that are new in the source are copied to the target.
- Files that changed in the source are updated on the target.
- Files that exist only in the target are deleted from the target.

Deletions are permanent. Always double-check the selected source and target before starting a clone run, and keep another backup of important data.

## Features

- Graphical interface for macOS clone backups using `/usr/bin/rsync`.
- Dry-run preflight review before every clone run.
- Planned creates, updates, and deletions shown before anything is changed.
- Conservative path validation for same-folder, nested-folder, home-folder, and protected top-level targets.
- Target drive identity checks for saved external-drive backup pairs.
- Target filesystem and read-only capability checks.
- Typed confirmation for first runs and high-risk deletion-heavy runs.
- Saved source/target pairs with last-run status.
- Run progress, cancellation, full logs, and copyable support diagnostics.
- File-backed app state under `~/Library/Application Support/LocalMirror/`.

## Install

Requirements:

- macOS 15.1 or newer.
- The macOS-provided `/usr/bin/rsync`.

Steps:

1. Download the latest `LocalMirror.app` from [GitHub Releases](https://github.com/plmstd/LocalMirror/releases).
2. Move `LocalMirror.app` to your Applications folder.
3. Launch the app.
4. Grant Full Disk Access if you plan to back up protected folders or external drives:
   - Open System Settings.
   - Go to Privacy & Security -> Full Disk Access.
   - Add `LocalMirror.app` and enable it.
5. Select a source folder or drive.
6. Select a target folder or drive.
7. Click `Start Clone Backup`.
8. Review the preflight report carefully, then approve the run only if the planned changes are correct.

## How A Clone Run Works

1. LocalMirror resolves the saved source and target permissions.
2. It validates that the source and target are available and safe to use.
3. It runs `rsync` in dry-run mode to calculate planned changes.
4. It opens a preflight review showing transfer and deletion counts.
5. If the run is risky, it requires typed confirmation using the target folder or volume name.
6. After approval, it runs the clone with `rsync --delete-delay`.
7. It records the result and stores a full log on disk.

## Important Limits

- LocalMirror is clone-only in v1. It does not keep historical snapshots.
- A cancelled run can leave the target partially synced. Run a fresh preflight before trying again.
- Network shares may work, but they are best effort and depend on the network filesystem.
- Full Disk Access may be required for folders macOS protects.
- LocalMirror uses the system `rsync`; behavior follows the macOS version available at `/usr/bin/rsync`.

## Contributing

Contributions are welcome. The most useful contributions are bug fixes, improvements, parser tests, UI polish, clearer docs, and release workflow improvements.

Start with [CONTRIBUTING.md](CONTRIBUTING.md). In general:

- Keep pull requests focused and easy to review.
- Be conservative around destructive behavior.
- Add or update tests when changing validation, preflight, parsing, storage, or run-state behavior.
- Do not add production dependencies unless they are clearly justified.
- Include the validation you ran in the pull request description.

## Local Development

Requirements:

- Xcode with macOS development tools.
- Swift 5.10 or newer.
- Node.js and npm for the website.

Open the macOS app in Xcode:

```bash
open macos/LocalMirror.xcodeproj
```

Build the app from the command line:

```bash
xcodebuild -project macos/LocalMirror.xcodeproj -scheme LocalMirror -configuration Debug -derivedDataPath /tmp/LocalMirrorDerived CODE_SIGNING_ALLOWED=NO build
```

Run the fast core test suite:

```bash
cd macos
swift test
```

Run the website locally:

```bash
cd website
npm ci
npm run dev
```

## Project Layout

- `macos/LocalMirror/Core` - shared models, path validation, volume identity, parser, and orchestrator.
- `macos/LocalMirror/Services` - system `rsync` discovery and sync execution.
- `macos/LocalMirror/Storage` - file-backed app state, saved pairs, run history, and logs.
- `macos/LocalMirror/App` - app model and macOS System Settings helper.
- `macos/Tests/LocalMirrorCoreTests` - SwiftPM tests for core behavior.
- `macos/docs/RELEASE.md` - release checklist and notarization notes.
- `website` - Next.js site for downloads and public project information.

## Releasing

LocalMirror ships as a direct-download macOS app, not a Mac App Store app.

- Release build helper: [`macos/scripts/build-release.sh`](macos/scripts/build-release.sh)
- Notarization helper: [`macos/scripts/notarize-app.sh`](macos/scripts/notarize-app.sh)
- Release checklist: [`macos/docs/RELEASE.md`](macos/docs/RELEASE.md)

## License

LocalMirror is available under the [MIT License](LICENSE).
