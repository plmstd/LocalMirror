const LEGACY_COOKIES = [
  'datafast_visitor_id',
  'datafast_visitor_first_seen_at',
  'datafast_visitor_session_count',
  'datafast_session_id',
  'datafast_first_seen_at',
  'datafast_session_count',
];

/** Expire only retired tracker state; preserve own Analytics IDs, consent and tool preferences. */
export function cleanupLegacyAnalytics(window) {
  if (
    !window?.document ||
    !['localmirror.app', 'www.localmirror.app'].includes(window.location.hostname) ||
    window.location.protocol !== 'https:'
  )
    return;
  const domains = new Set([
    '',
    window.location.hostname,
    `.${window.location.hostname}`,
    'localmirror.app',
    '.localmirror.app',
  ]);
  const paths = new Set(['/']);
  const segments = window.location.pathname.split('/').filter(Boolean);
  for (let length = 1; length <= segments.length; length++) {
    const parent = `/${segments.slice(0, length).join('/')}`;
    paths.add(parent);
    paths.add(`${parent}/`);
  }
  for (const name of LEGACY_COOKIES)
    for (const domain of domains)
      for (const path of paths)
        window.document.cookie = `${name}=; path=${path}; max-age=0; SameSite=Lax${domain ? `; domain=${domain}` : ''}; Secure`;
  try {
    window.sessionStorage.removeItem('datafast_pageview_state');
  } catch {
    /* Browsers can disable storage without affecting consent or the tools. */
  }
}
