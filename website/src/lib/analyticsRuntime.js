import { ANALYTICS_PUBLIC_PATHS } from './analyticsPaths.js';

export const OWN_ANALYTICS_SITE_ID = '7676c8b289f2e47b';
export const OWN_ANALYTICS_ACTIVE_FROM = '2026-11-10T08:00:00.000Z';
const OWN_ANALYTICS_ORIGIN = 'https://analytics.palmstudio.io';
const OWN_ANALYTICS_COOKIE_DOMAIN = 'localmirror.app';
const OWN_ANALYTICS_PRODUCTION_HOSTS = ['localmirror.app', 'www.localmirror.app'];
const QUEUE_MS = 30_000;
const QUEUE_LIMIT = 100;
const WEB_PATHS = new Set(ANALYTICS_PUBLIC_PATHS);

/** Only known public routes can leave the browser. All search, campaign and fragment values stay local. */
export function sanitizeOwnAnalyticsUrl(href) {
  try {
    const original = new URL(href);
    if (
      original.protocol !== 'https:' ||
      original.port ||
      original.username ||
      original.password ||
      !OWN_ANALYTICS_PRODUCTION_HOSTS.includes(original.hostname)
    )
      return null;
    let path = original.pathname;
    if (path.length > 1) path = path.replace(/\/+$/, '');
    if (!WEB_PATHS.has(path)) path = '/[redacted]';
    return new URL(path, original.origin).toString();
  } catch {
    return null;
  }
}

function referrerOrigin(document) {
  try {
    const url = new URL(document.referrer);
    return /^https?:$/.test(url.protocol) ? `${url.origin}/` : '';
  } catch {
    return '';
  }
}

/** Browser-owned lifecycle; injectable clock/window keep privacy tests independent of real services. */
export function createOwnAnalyticsRuntime({
  getWindow = () => (typeof window === 'undefined' ? null : window),
  now = () => Date.now(),
  isProduction = () => process.env.NODE_ENV === 'production',
  activeFrom = Date.parse(OWN_ANALYTICS_ACTIVE_FROM),
} = {}) {
  let allowed = false;
  let state = 'off';
  let script = null;
  let sdk = null;
  let generation = 0;
  let pending = [];
  let lastView = null;
  let lastPathname = null;
  let lastSdkView = null;
  let loadTimer = null;
  let activationTimer = null;
  let startedAt = 0;
  let retryAfter = 0;
  let restores = [];
  let disposeGeneration = 0;

  function clearTimer(window, timer) {
    if (timer !== null) window?.clearTimeout(timer);
  }

  function clearCookies(window) {
    if (!window?.document) return;
    const domains = new Set([
      '',
      window.location.hostname,
      `.${window.location.hostname}`,
      OWN_ANALYTICS_COOKIE_DOMAIN,
      `.${OWN_ANALYTICS_COOKIE_DOMAIN}`,
    ]);
    const paths = new Set(['/']);
    const segments = window.location.pathname.split('/');
    for (let i = 1; i < segments.length; i++) {
      paths.add(segments.slice(0, i + 1).join('/') || '/');
      paths.add(`${segments.slice(0, i + 1).join('/')}/`);
    }
    for (const name of ['ml_vid', 'ml_sid', 'ml_t'])
      for (const domain of domains)
        for (const path of paths)
          window.document.cookie = `${name}=; path=${path}; max-age=0; SameSite=Lax${domain ? `; domain=${domain}` : ''}; Secure`;
  }

  function eligible(window) {
    try {
      if (
        !window?.document ||
        !(typeof isProduction === 'function' ? isProduction() : isProduction) ||
        !sanitizeOwnAnalyticsUrl(window.location.href) ||
        window.navigator?.webdriver
      )
        return false;
      const dnt =
        window.navigator?.doNotTrack ??
        window.doNotTrack ??
        window.navigator?.msDoNotTrack;
      if (['1', 'yes'].includes(String(dnt).toLowerCase())) return false;
      const ignore = new URL(window.location.href).searchParams.get(
        'ml_ignore',
      );
      if (ignore === 'true') window.localStorage.setItem('ml_ignore', '1');
      if (ignore === 'false') window.localStorage.removeItem('ml_ignore');
      return window.localStorage.getItem('ml_ignore') !== '1';
    } catch {
      return false;
    }
  }

  function stop(clear = false) {
    const window = getWindow();
    generation++;
    clearTimer(window, loadTimer);
    clearTimer(window, activationTimer);
    loadTimer = activationTimer = null;
    pending = [];
    lastView = lastSdkView = lastPathname = null;
    const owned =
      sdk ?? (window?.minilytics?.script === script ? window.minilytics : null);
    try {
      owned?.destroy?.({ clearCookies: clear });
    } catch {
      /* Best-effort shutdown still clears local state. */
    }
    if (window && owned && window.minilytics === owned) {
      try {
        delete window.minilytics;
      } catch {
        window.minilytics = undefined;
      }
    }
    if (script) {
      script.onload = script.onerror = null;
      script.remove();
    }
    script = sdk = null;
    state = 'off';
    restores.forEach((restore) => {
      try {
        restore();
      } catch {
        /* A different router may already have replaced its wrapper. */
      }
    });
    restores = [];
    if (clear) clearCookies(window);
  }

  function send(command) {
    if (!allowed) return;
    if (!eligible(getWindow()) || now() < activeFrom) {
      stop(true);
      return;
    }
    if (!sdk) return;
    if (
      lastSdkView !== command.url ||
      (command.type === 'view' && command.force)
    ) {
      sdk.pageview({
        url: command.url,
        referrer: command.referrer ?? '',
        ...(command.force ? { force: true } : {}),
      });
      lastSdkView = command.url;
    }
  }

  function enqueue(command) {
    const entry = { ...command, expiresAt: now() + QUEUE_MS };
    if (state === 'ready') send(entry);
    else if (state === 'loading') {
      pending = pending.filter((item) => item.expiresAt > now());
      pending.push(entry);
      if (pending.length > QUEUE_LIMIT) pending.shift();
    }
  }

  function recordView() {
    const window = getWindow();
    if (!allowed || !eligible(window) || now() < activeFrom) {
      if (allowed) stop(true);
      return false;
    }
    const url = sanitizeOwnAnalyticsUrl(window.location.href);
    const pathname = window.location.pathname;
    const force = url === lastView && pathname !== lastPathname;
    if (url === lastView && !force) return true;
    const first = lastView === null;
    lastView = url;
    lastPathname = pathname;
    enqueue({
      type: 'view',
      url,
      referrer: first ? referrerOrigin(window.document) : '',
      ...(force ? { force: true } : {}),
    });
    return true;
  }

  function observeRoutes(window) {
    for (const name of ['pushState', 'replaceState']) {
      const original = window.history?.[name];
      if (typeof original !== 'function') continue;
      const wrapped = function (...args) {
        const result = original.apply(this, args);
        try {
          recordView();
        } catch {
          /* A tracker never interferes with navigation. */
        }
        return result;
      };
      window.history[name] = wrapped;
      restores.push(() => {
        if (window.history[name] === wrapped) window.history[name] = original;
      });
    }
    const onRoute = () => {
      try {
        recordView();
      } catch {
        /* Navigation remains independent. */
      }
    };
    window.addEventListener('popstate', onRoute);
    restores.push(() => window.removeEventListener('popstate', onRoute));
  }

  function start() {
    const window = getWindow();
    if (!allowed || !eligible(window)) {
      stop(true);
      return false;
    }
    if (now() < activeFrom) {
      if (activationTimer === null)
        activationTimer = window.setTimeout(
          () => {
            activationTimer = null;
            if (allowed) start();
          },
          Math.min(2_147_483_647, activeFrom - now()),
        );
      return false;
    }
    if (state === 'ready' || state === 'loading') return recordView();
    if (state === 'failed' && now() < retryAfter) return false;
    state = 'loading';
    startedAt = now();
    const currentGeneration = ++generation;
    script = window.document.createElement('script');
    script.src = `${OWN_ANALYTICS_ORIGIN}/js/script.js?v=localmirror-20261110`;
    script.async = true;
    script.referrerPolicy = 'no-referrer';
    for (const [key, value] of Object.entries({
      'data-website-id': OWN_ANALYTICS_SITE_ID,
      'data-api': `${OWN_ANALYTICS_ORIGIN}/api/event`,
      'data-domain': OWN_ANALYTICS_COOKIE_DOMAIN,
      'data-manual': 'true',
      'data-track-time': 'true',
      'data-track-outbound': 'false',
      'data-disable-payments': 'true',
      'data-disable-identify': 'true',
    }))
      script.setAttribute(key, value);
    const failed = () => {
      if (generation !== currentGeneration) return;
      stop(false);
      state = 'failed';
      retryAfter = now() + QUEUE_MS;
    };
    script.onerror = failed;
    script.onload = () => {
      try {
        if (generation !== currentGeneration) return;
        if (!allowed || !eligible(window) || now() < activeFrom) {
          stop(true);
          return;
        }
        if (now() - startedAt >= QUEUE_MS) {
          failed();
          return;
        }
        const loaded = window.minilytics;
        if (
          typeof loaded !== 'function' ||
          loaded.script !== script ||
          typeof loaded.pageview !== 'function' ||
          typeof loaded.destroy !== 'function'
        ) {
          failed();
          return;
        }
        sdk = loaded;
        state = 'ready';
        clearTimer(window, loadTimer);
        loadTimer = null;
        const commands = pending.filter((item) => item.expiresAt > now());
        pending = [];
        for (const command of commands) send(command);
        recordView();
      } catch {
        failed();
      }
    };
    loadTimer = window.setTimeout(failed, QUEUE_MS);
    observeRoutes(window);
    recordView();
    window.document.head.appendChild(script);
    return true;
  }

  /** Apply an explicit consent decision synchronously; load errors never escape to product flows. */
  function syncOwnAnalyticsConsent(value) {
    disposeGeneration++;
    allowed = value === true;
    try {
      if (!allowed) {
        stop(true);
        return false;
      }
      return start();
    } catch {
      try {
        stop(false);
      } catch {
        /* A locked-down document can refuse cleanup. */
      }
      return false;
    }
  }

  /** Stop this runtime without revoking an existing cookie decision or its shared visitor ID. */
  function disposeOwnAnalytics() {
    allowed = false;
    const current = ++disposeGeneration;
    // React StrictMode tears down and re-subscribes in the same turn. Keep the
    // consented SDK until that turn ends so the remount cannot duplicate a view.
    Promise.resolve().then(() => {
      if (allowed || current !== disposeGeneration) return;
      try {
        stop(false);
      } catch {
        /* Application teardown must remain safe. */
      }
    });
  }

  return {
    syncOwnAnalyticsConsent,
    disposeOwnAnalytics,
  };
}

const runtime = createOwnAnalyticsRuntime();
export const syncOwnAnalyticsConsent = runtime.syncOwnAnalyticsConsent;
export const disposeOwnAnalytics = runtime.disposeOwnAnalytics;
