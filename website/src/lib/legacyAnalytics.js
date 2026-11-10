let legacyScript = null;
/** Temporary consent-gated collector; remove after accepted native history. */
export function allowLegacyAnalytics(allowed) {
  if (!['www.localmirror.app','localmirror.app'].includes(window.location.hostname)||window.location.protocol!=='https:') return;
  if (!allowed) { if(legacyScript){ legacyScript.remove(); legacyScript=null; window.location.reload(); } return; }
  if(legacyScript||window.navigator.webdriver||['1','yes'].includes(String(window.navigator.doNotTrack).toLowerCase()))return;
  try{if(window.localStorage.getItem('ml_ignore')==='1')return;}catch{return;}
  legacyScript=window.document.createElement('script');legacyScript.src='https://datafa.st/js/script.js';legacyScript.defer=true;
  legacyScript.setAttribute('data-website-id','dfid_xltNNhntkEpvH9oOlho2Q');legacyScript.setAttribute('data-domain','www.localmirror.app');window.document.head.appendChild(legacyScript);
}
