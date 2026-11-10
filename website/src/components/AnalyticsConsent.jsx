'use client';

import { useEffect, useState } from 'react';
import {
  syncOwnAnalyticsConsent,
  disposeOwnAnalytics,
} from '../lib/analyticsRuntime';
import {
  ANALYTICS_CONSENT_KEY,
  ANALYTICS_SETTINGS_EVENT,
  analyticsStorage,
  readAnalyticsConsent,
  saveAnalyticsConsent,
} from '../lib/analyticsConsent';
import { cleanupLegacyAnalytics } from '../lib/legacyAnalyticsCleanup';

/** Optional first-party consent owns the collector; tool inputs are never read. */
export default function AnalyticsConsent() {
  const copy = { title: 'Analytics consent', body: 'Optional analytics help us understand customer experience and improve our services. You can change your choice at any time.', allow: 'Allow analytics', deny: 'Continue without analytics', settings: 'Analytics settings', privacy: 'Privacy policy' };
  const [choice, setChoice] = useState(undefined);
  const [editing, setEditing] = useState(false);

  useEffect(() => {
    const apply = (next) => {
      setChoice(next);
      syncOwnAnalyticsConsent(next === 'allowed');
      cleanupLegacyAnalytics(window);
    };
    apply(readAnalyticsConsent(analyticsStorage(window)));
    const settings = () => setEditing(true);
    const storage = (event) => {
      if (event.key === ANALYTICS_CONSENT_KEY || event.key === null)
        apply(readAnalyticsConsent(analyticsStorage(window)));
    };
    window.addEventListener(ANALYTICS_SETTINGS_EVENT, settings);
    window.addEventListener('storage', storage);
    return () => {
      window.removeEventListener(ANALYTICS_SETTINGS_EVENT, settings);
      window.removeEventListener('storage', storage);
      disposeOwnAnalytics();
    };
  }, []);

  const choose = (allowed) => {
    const next = saveAnalyticsConsent(analyticsStorage(window), allowed);
    // Stop collection synchronously before updating the interface.
    syncOwnAnalyticsConsent(allowed);
    setChoice(next);
    setEditing(false);
    cleanupLegacyAnalytics(window);
  };

  if (choice === undefined || (choice !== null && !editing)) return null;
  const privacyPath = '/privacy';
  return (
    <section
      role="dialog"
      aria-modal="false"
      aria-labelledby="analytics-consent-title"
      aria-describedby="analytics-consent-body"
      data-testid="analytics-consent"
      className="fixed bottom-4 left-4 right-4 z-50 max-w-xl mx-auto p-5 bg-white border border-gray-200 rounded-xl shadow-lg text-primary"
    >
      <h2 id="analytics-consent-title" className="text-lg font-semibold mb-2">
        {copy.title}
      </h2>
      <p id="analytics-consent-body" className="text-sm mb-3">
        {copy.body}
      </p>
      <a href={privacyPath} className="text-sm underline">
        {copy.privacy}
      </a>
      <div className="flex flex-wrap gap-2 mt-4">
        <button
          type="button"
          className="bg-primary hover:opacity-90 text-white px-5 py-3 rounded-md font-semibold"
          data-testid="analytics-allow"
          onClick={() => choose(true)}
        >
          {copy.allow}
        </button>
        <button
          type="button"
          className="bg-white border border-gray-300 text-primary px-5 py-3 rounded-md"
          data-testid="analytics-deny"
          onClick={() => choose(false)}
        >
          {copy.deny}
        </button>
      </div>
    </section>
  );
}

export function AnalyticsSettingsButton() {
  return (
    <button
      type="button"
      className="underline cursor-pointer"
      data-testid="analytics-settings"
      onClick={() => window.dispatchEvent(new Event(ANALYTICS_SETTINGS_EVENT))}
    >
      Analytics settings
    </button>
  );
}
