(function () {
  'use strict';
  let settings = Object.assign({hideInstallPrompts:true}, window.__goyoSettings || {});
  let style, scheduled = false;
  const containers = 'ytm-app-promo-renderer,ytm-app-install-banner-renderer,ytm-app-install-prompt-renderer,ytm-promo-renderer,ytm-mobile-app-promo-renderer,ytm-open-app-banner-renderer,ytm-bottom-sheet-renderer,[role="dialog"],[data-testid="app-banner"],[data-testid="download-app-banner"],.app-install-banner,.smart-banner';
  const fixed = ['ytm-app-promo-renderer','ytm-app-install-banner-renderer','ytm-app-install-prompt-renderer','ytm-mobile-app-promo-renderer','ytm-open-app-banner-renderer','[data-testid="app-banner"]','[data-testid="download-app-banner"]','.app-install-banner','.smart-banner','[data-goyo-install-prompt="true"]'];
  function isInstallLink(value) {
    try {
      const url = new URL(value, location.href);
      return ['itms-apps:','itms-services:','intent:','youtube:','vnd.youtube:','instagram:'].includes(url.protocol) ||
        ['apps.apple.com','itunes.apple.com','play.google.com'].includes(url.hostname);
    } catch (_) { return false; }
  }
  function installOnlyText(text) {
    return /(?:open\s+(?:in\s+)?(?:the\s+)?(?:youtube|instagram|dcinside)?\s*app|(?:get|download|install)\s+(?:the\s+)?app|앱(?:에서|으로)\s*열기|앱\s*(?:설치|다운로드)|(?:유튜브|인스타그램|디시인사이드)\s*앱\s*열기)/i.test(text);
  }
  function apply() {
    scheduled = false;
    if (!document.documentElement) return;
    if (!style || !style.isConnected) {
      style = document.createElement('style'); style.id = 'goyo-install-prompt-style'; document.documentElement.appendChild(style);
    }
    const css = settings.hideInstallPrompts ? fixed.join(',') + '{display:none!important}' : '';
    if (style.textContent !== css) style.textContent = css;
    if (!settings.hideInstallPrompts) return;
    // A login dialog without an install CTA remains available.
    document.querySelectorAll(containers).forEach(container => {
      const links = [...container.querySelectorAll('a[href]')];
      const buttons = [...container.querySelectorAll('button,[role="button"]')];
      const install = links.some(link => isInstallLink(link.href)) || buttons.some(button => installOnlyText(button.textContent || ''));
      if (install && container.dataset.goyoInstallPrompt !== 'true') container.dataset.goyoInstallPrompt = 'true';
      if (!install && container.hasAttribute('data-goyo-install-prompt')) container.removeAttribute('data-goyo-install-prompt');
    });
  }
  function schedule() { if (!scheduled) { scheduled = true; setTimeout(apply, 50); } }
  window.GoyoInstallPrompts = {update(value) { settings = Object.assign({hideInstallPrompts:true}, value); apply(); }, isInstallLink, installOnlyText};
  new MutationObserver(schedule).observe(document, {childList:true, subtree:true});
  addEventListener('popstate', schedule);
  addEventListener('yt-navigate-finish', schedule);
  document.addEventListener('click', event => {
    if (!settings.hideInstallPrompts) return;
    const link = event.target.closest && event.target.closest('a[href]');
    if (link && isInstallLink(link.href)) { event.preventDefault(); event.stopImmediatePropagation(); }
  }, true);
  apply();
})();
