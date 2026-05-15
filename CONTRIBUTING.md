# Contributing to LocalMirror

Thanks for helping improve LocalMirror. This project is intentionally small, safety-focused, and easy to review.

## Good First Contributions

- Fix unclear user-facing copy or documentation.
- Improve the website copy or screenshots.
- Add parser tests for real `rsync` output.
- Add tests for path validation and high-risk preflight behavior.
- Improve diagnostics, log messages, or error states.
- Polish UI details without changing clone behavior.

For larger feature ideas, open an issue first so the expected safety behavior is clear before implementation starts.

## Development Setup

Clone the repository, then open the macOS app in Xcode:

```bash
open macos/LocalMirror.xcodeproj
```

Run the core Swift tests:

```bash
cd macos
swift test
```

Run the website:

```bash
cd website
npm ci
npm run dev
```

## Safety Expectations

LocalMirror can delete files from the selected target. Contributions must keep that risk visible and controlled.

- Do not bypass the preflight review.
- Do not weaken source/target path validation without a strong reason.
- Treat target deletions as high-risk behavior.
- Keep typed confirmation for first runs and deletion-heavy runs.
- Preserve clear failure, cancellation, and partial-sync messaging.
- Add tests when changing validation, preflight, parser, storage, or run lifecycle code.

## Pull Request Guidelines

- Keep changes focused.
- Match the existing code style and structure.
- Prefer local utilities and existing patterns over new dependencies.
- Include screenshots for visible UI changes.
- Include the checks you ran, such as `swift test`, an Xcode build, or `npm run build`.
- Avoid committing local build output, private logs, generated app archives, or personal Xcode state.

## Bug Reports

Useful bug reports include:

- macOS version.
- LocalMirror version.
- Whether the source and target are local folders, external drives, or network volumes.
- What the preflight review showed.
- Whether the run completed, failed, cancelled, or finished partially.
- Relevant diagnostics copied from the app.

Remove private file names or paths from logs before sharing them publicly.
