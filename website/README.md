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
