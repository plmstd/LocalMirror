# LocalMirror Website

This is the Next.js website for LocalMirror. It provides the public project page, download entry point, screenshots, and contributor-facing links.

## Development

Install dependencies:

```bash
npm ci
```

Run the local dev server:

```bash
npm run dev
```

Open `http://localhost:3000`.

## Useful Files

- `src/app/page.js` - homepage layout.
- `src/content/HomeMainContent.js` - main public copy.
- `src/consts/urls.js` - GitHub and release API URLs.
- `public/images` - screenshots used by the site.

## Validation

Before changing website behavior, run:

```bash
npm run build
```

## Own Analytics

The public website uses the first-party Analytics site `7676c8b289f2e47b`
(`localmirror.app`, Europe/Berlin, USD). Own collection begins on
10 November 2026 at 08:00 UTC, after explicit optional agreement. The footer
always opens Analytics settings; refusal leaves the website and downloads usable.

Only known public page paths and visible time are measured. Query strings,
fragments, unknown paths, form/file contents and identities are excluded.
Outbound capture, payment claims and identify are disabled. DNT, automated
browsers, preview hosts and `ml_ignore` are excluded. Consent lasts 180 days;
consented `ml_vid`/`ml_sid` cookies last up to one year/30 minutes. Withdrawal
stops collection synchronously and clears identifiers.

Source files: `src/lib/analyticsRuntime.js`, `analyticsConsent.js`,
`analyticsPaths.js`, `legacyAnalyticsCleanup.js` and `src/components/AnalyticsConsent.jsx`.
The temporary consent-gated DataFast bridge is removed only after the separately
verified native history import; the operator has approved importing the available
individual records and explicitly documenting DataFast's unavailable source history.
No macOS app files, sync behavior or release configuration are changed.

Validation: `node specs/analytics.test.mjs` and `npm run build` from `website/`.
Browser QA must use an isolated staging Analytics site, preserve genuine live
visits and avoid downloading/running the app. Detailed migration coverage and
acceptance are recorded in the private Analytics service repository.
