export const ANALYTICS_CONSENT_KEY = 'localmirror_analytics_consent_v1';
export const ANALYTICS_SETTINGS_EVENT = 'localmirror:analytics-settings';
const CHOICE_MS = 180 * 24 * 60 * 60 * 1000;

/** Browser privacy modes can refuse even access to the storage property. */
export function analyticsStorage(window) {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

/** A missing, expired or malformed preference never enables collection. */
export function readAnalyticsConsent(storage, now = Date.now()) {
  try {
    const saved = JSON.parse(storage.getItem(ANALYTICS_CONSENT_KEY));
    if (
      !saved ||
      !['allowed', 'denied'].includes(saved.choice) ||
      !Number.isFinite(saved.expiresAt) ||
      saved.expiresAt <= now ||
      saved.expiresAt > now + CHOICE_MS
    )
      return null;
    return saved.choice;
  } catch {
    return null;
  }
}

/** Persist only the optional consent choice, never tool data or an identifier. */
export function saveAnalyticsConsent(storage, allowed, now = Date.now()) {
  const choice = allowed === true ? 'allowed' : 'denied';
  try {
    storage.setItem(
      ANALYTICS_CONSENT_KEY,
      JSON.stringify({ choice, expiresAt: now + CHOICE_MS }),
    );
  } catch {
    /* The in-memory choice still works when browser storage is disabled. */
  }
  return choice;
}

