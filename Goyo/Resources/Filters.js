(function () {
  'use strict';
  const initial = {shorts:true,reels:true,ads:true,recommendations:true,youtubeFeed:true,instagramFeed:true,stories:false,instagramRecommendations:true,grayscale:false,postAlarm:true,restScreen:true};
  let settings = Object.assign({}, initial, window.__goyoSettings || {});
  const youtube = /(^|\.)youtube\.com$/.test(location.hostname);
  const instagram = /(^|\.)instagram\.com$/.test(location.hostname);
  if (!youtube && !instagram) return;
  let style, panel, scheduled = false;
  let suspended = false;
  let countObserver;
  let tracked = new WeakMap();
  const dwell = new WeakMap();
  const seenHere = new Set();

  function report(id) {
    if (suspended || document.visibilityState === 'hidden' || (!settings.postAlarm && !settings.restScreen) || seenHere.has(id)) return;
    if (routeIsBlocked(location.pathname) || (instagram && /^\/direct(?:\/|$)/.test(location.pathname))) return;
    seenHere.add(id);
    const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.goyo;
    if (handler) handler.postMessage({kind:'post', id:id.slice(0,512)});
  }
  function postID(article) {
    const link = article.querySelector('a[href^="/p/"],a[href^="/reel/"]');
    return link ? new URL(link.href, location.href).pathname : null;
  }
  function observePosts() {
    if (!instagram || typeof IntersectionObserver === 'undefined') return;
    if (!countObserver) countObserver = new IntersectionObserver(entries => {
      entries.forEach(entry => {
        const article = entry.target;
        if (dwell.has(article)) { clearTimeout(dwell.get(article)); dwell.delete(article); }
        if (!entry.isIntersecting || entry.intersectionRatio < 0.5 || article.dataset.goyoAd === 'true' || article.dataset.goyoSuggested === 'true' || suspended) return;
        const id = postID(article);
        if (!id) return; // No permalink means no trustworthy unique post identifier.
        const timer = setTimeout(() => {
          dwell.delete(article);
          if (article.isConnected && postID(article) === id && getComputedStyle(article).display !== 'none') report('instagram:' + id);
        }, 1000);
        dwell.set(article, timer);
      });
    }, {threshold:[0,0.5,1]});
    if (!/^\/direct(?:\/|$)/.test(location.pathname)) document.querySelectorAll('main article').forEach(article => {
      const id = postID(article);
      if (!tracked.has(article) || tracked.get(article) !== id) {
        if (dwell.has(article)) { clearTimeout(dwell.get(article)); dwell.delete(article); }
        countObserver.unobserve(article);
        tracked.set(article, id); countObserver.observe(article);
      }
    });
  }

  function routeIsBlocked(path) {
    return (youtube && settings.shorts && /^\/shorts(?:\/|$)/.test(path)) ||
      (instagram && settings.reels && /^\/reels?(?:\/|$)/.test(path)) ||
      (instagram && settings.stories && /^\/stories(?:\/|$)/.test(path)) ||
      (instagram && settings.instagramFeed && /^\/explore(?:\/|$)/.test(path));
  }
  function css() {
    let rules = [];
    const hide = selectors => rules.push(selectors.join(',') + '{display:none!important}');
    if (youtube) {
      if (settings.shorts) hide([
        'ytd-reel-shelf-renderer','ytm-reel-shelf-renderer','ytm-shorts-lockup-view-model',
        'ytd-rich-shelf-renderer[is-shorts]','ytm-shorts-lockup-view-model-v2',
        'ytm-shorts-lockup-view-model-v3','ytd-rich-item-renderer:has(a[href^="/shorts/"])',
        'ytd-grid-video-renderer:has(a[href^="/shorts/"])','ytm-pivot-bar-item-renderer:has(a[href^="/shorts"])',
        'a[href^="/shorts/"]','a[href="/shorts"]','ytd-guide-entry-renderer:has(a[href^="/shorts"])'
      ]);
      if (settings.recommendations) hide([
        'ytd-watch-next-secondary-results-renderer','ytm-watch-next-secondary-results-renderer',
        'ytm-item-section-renderer[section-identifier="related-items"]',
        'ytm-watch-next-feed','ytm-watch-next-feed-renderer',
        'ytd-compact-autoplay-renderer','.ytp-endscreen-content','.ytp-ce-element'
      ]);
      if (settings.youtubeFeed && (location.pathname === '/' || location.pathname === '/feed/trending')) hide([
        'ytd-browse[page-subtype="home"] #contents','ytm-browse[tab-identifier="FEwhat_to_watch"]',
        'ytm-rich-grid-renderer','ytm-section-list-renderer',
        'ytd-rich-grid-renderer','ytm-rich-item-renderer'
      ]);
      if (settings.ads) hide([
        'ytd-ad-slot-renderer','ytm-ad-slot-renderer','ytd-display-ad-renderer',
        'ytm-promoted-sparkles-web-renderer','ytd-promoted-sparkles-web-renderer',
        'ytd-in-feed-ad-layout-renderer','ytm-companion-ad-renderer',
        '#player-ads','.ytp-ad-overlay-container','ytd-action-companion-ad-renderer'
      ]);
    }
    if (instagram) {
      if (settings.reels) hide(['a[href^="/reels/"]','a[href="/reels/"]','a[href="/reels"]','a[href^="/reel/"]']);
      if (settings.stories) hide(['a[href^="/stories/"]','[role="list"]:has(a[href^="/stories/"])','[data-testid="story-tray"]']);
      if (settings.instagramRecommendations) hide(['[data-goyo-suggested="true"]']);
      if (settings.instagramFeed) {
        hide(['a[href^="/explore/"]']);
        if (location.pathname === '/') hide(['main article','main [role="feed"]','main [role="presentation"] article']);
      }
      if (settings.ads) rules.push('[data-goyo-ad="true"]{display:none!important}');
    }
    if (settings.grayscale) rules.push('html{-webkit-filter:grayscale(1)!important;filter:grayscale(1)!important}');
    return rules.join('\n');
  }
  function scanInstagramAds() {
    if (!instagram) return;
    // Mark individual cards; never hide the containing main element or inbox.
    document.querySelectorAll('main article').forEach(article => {
      const sponsored = settings.ads && [...article.querySelectorAll('span,a')].some(el =>
        /^(Sponsored|광고|Gesponsert|Sponsorisé|Patrocinado)$/i.test(el.textContent.trim()));
      if (sponsored && article.dataset.goyoAd !== 'true') article.dataset.goyoAd = 'true';
      if (!sponsored && article.hasAttribute('data-goyo-ad')) article.removeAttribute('data-goyo-ad');
      const suggested = settings.instagramRecommendations && [...article.querySelectorAll('span,h2,h3')].some(el =>
        /^(Suggested for you|회원님을 위한 추천|추천 회원)$/i.test(el.textContent.trim()));
      if (suggested && article.dataset.goyoSuggested !== 'true') article.dataset.goyoSuggested = 'true';
      if (!suggested && article.hasAttribute('data-goyo-suggested')) article.removeAttribute('data-goyo-suggested');
    });
  }
  function apply() {
    scheduled = false;
    if (!document.documentElement) return;
    if (!style || !style.isConnected) {
      style = document.createElement('style'); style.id = 'goyo-filter-style';
      document.documentElement.appendChild(style);
    }
    const next = css();
    if (style.textContent !== next) style.textContent = next;
    scanInstagramAds();
    observePosts();
    const blocked = routeIsBlocked(location.pathname);
    if (blocked && (!panel || !panel.isConnected)) {
      panel = document.createElement('div'); panel.id = 'goyo-route-shield';
      panel.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#0a192e;color:white;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:32px;box-sizing:border-box;font:18px -apple-system,BlinkMacSystemFont,sans-serif;text-align:center;gap:24px';
      const title = document.createElement('h2'); title.textContent = '이 화면은 차단되어 있습니다.';
      const text = document.createElement('p'); text.textContent = '필터에서 차단을 끄거나 필요한 화면으로 돌아가세요.';
      const button = document.createElement('button'); button.textContent = youtube ? '유튜브 검색으로' : '메시지로';
      button.style.cssText = 'padding:16px 24px;background:#6ee7b7;border:0;border-radius:14px;font:inherit;color:#081b2a';
      button.addEventListener('click', () => location.replace(youtube ? 'https://m.youtube.com/results?search_query=' : 'https://www.instagram.com/direct/inbox/'));
      panel.append(title, text, button); document.documentElement.appendChild(panel);
      document.querySelectorAll('video,audio').forEach(v => v.pause());
    }
    if (!blocked && panel) { panel.remove(); panel = null; }
  }
  function schedule() { if (!scheduled) { scheduled = true; setTimeout(apply, 50); } }
  window.GoyoFilter = {
    update(value) { settings = Object.assign({}, initial, value); apply(); },
    isBlocked: routeIsBlocked,
    setResting(value) {
      suspended = Boolean(value);
      if (suspended) {
        document.querySelectorAll('video,audio').forEach(v => v.pause());
        document.querySelectorAll('main article').forEach(article => {
          if (dwell.has(article)) { clearTimeout(dwell.get(article)); dwell.delete(article); }
        });
      } else if (countObserver) {
        countObserver.disconnect(); tracked = new WeakMap(); observePosts();
      }
    }
  };
  new MutationObserver(schedule).observe(document, {childList:true,subtree:true});
  ['pushState','replaceState'].forEach(name => {
    const original = history[name];
    history[name] = function () { const result = original.apply(this, arguments); schedule(); return result; };
  });
  addEventListener('popstate', schedule);
  addEventListener('yt-navigate-finish', schedule);
  document.addEventListener('play', event => {
    if ((suspended || routeIsBlocked(location.pathname)) && event.target.pause) event.target.pause();
  }, true);
  document.addEventListener('timeupdate', event => {
    if (!youtube || event.target.tagName !== 'VIDEO' || event.target.currentTime < 2 || event.target.paused || event.target.closest('.ad-showing')) return;
    const url = new URL(location.href);
    const videoID = url.pathname === '/watch' ? url.searchParams.get('v') : null;
    if (videoID) report('youtube:' + videoID);
  }, true);
  document.addEventListener('click', event => {
    const link = event.target.closest && event.target.closest('a[href]');
    if (!link) return;
    try {
      const url = new URL(link.href, location.href);
      if (url.hostname === location.hostname && routeIsBlocked(url.pathname)) {
        event.preventDefault(); event.stopImmediatePropagation();
      }
    } catch (_) {}
  }, true);
  apply();
})();
