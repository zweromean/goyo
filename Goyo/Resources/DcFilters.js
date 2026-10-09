(function () {
  'use strict';
  if (!['m.dcinside.com', 'gall.dcinside.com'].includes(location.hostname)) return;
  const policy = window.GoyoDcPolicy;
  let settings = window.__goyoSettings || {}, frame = 0, lastIDs = '', veil;
  function cover(text) {
    if (!veil) {
      veil = document.createElement('div');
      veil.style.cssText = 'position:fixed;inset:0;z-index:2147483647;background:#1e1e1e;color:#fff;display:grid;place-items:center;padding:32px;text-align:center;font:18px system-ui';
      (document.body || document.documentElement).appendChild(veil);
    }
    if (veil.textContent !== text) veil.textContent = text;
  }
  function isRecommendedTab() {
    return Array.from(document.querySelectorAll('a,button')).some(a => {
      if (a.textContent.trim() !== '개념글') return false;
      return !!a.closest('.on,.sel,.selected,.active,[aria-current="page"],[aria-selected="true"]');
    });
  }
  function scan() {
    frame = 0;
    const route = policy.parse(location.href);
    if (!route || !policy.allows(route.gallery, settings)) { cover('허용되지 않은 갤러리 또는 페이지입니다.'); return; }
    if (!route.post && settings.dcRecommendedOnly) {
      if (!route.recommended) { cover('개념글 목록으로 이동합니다.'); location.replace(policy.recommendedList(location.href)); return; }
      // Fail closed when the server did not select the recommended tab.
      // Only list-row anchors qualify; sidebar, notices and links inside posts do not.
      if (!isRecommendedTab()) { cover('개념글 목록을 확인하지 못했습니다. 새로고침하거나 갤러리 주소를 확인해주세요.'); return; }
      const ids = [];
      document.querySelectorAll('.gall-detail-lst > li a[href], .gall_list tbody tr a[href]').forEach(a => {
        let r; try { r = policy.parse(new URL(a.getAttribute('href'), location.href).href); } catch (_) { return; }
        if (!r || r.gallery !== route.gallery || !r.post || a.closest('.notice,.ub-notice,[data-type="notice"]')) return;
        if (a.closest('tr')?.querySelector('.gall_num')?.textContent.trim() === '공지') return;
        ids.push(r.post);
      });
      const unique = Array.from(new Set(ids)).slice(0, 500), signature = unique.join(',');
      if (signature !== lastIDs && unique.length) {
        lastIDs = signature;
        window.webkit?.messageHandlers?.goyo?.postMessage({ kind: 'dcRecommended', gallery: route.gallery, ids: unique });
      }
    }
    if (veil) { veil.remove(); veil = null; }
    document.querySelectorAll('a[href]').forEach(a => {
      let r; try { r = policy.parse(new URL(a.getAttribute('href'), location.href).href); } catch (_) { return; }
      const hidden = r && (!policy.allows(r.gallery, settings) || (settings.dcRecommendedOnly && r.gallery === route.gallery && !r.post && !r.recommended));
      if (hidden) a.setAttribute('data-goyo-dc-hidden', '');
      else a.removeAttribute('data-goyo-dc-hidden');
    });
  }
  function schedule() { if (!frame) frame = requestAnimationFrame(scan); }
  const style = document.createElement('style');
  style.textContent = '[data-goyo-dc-hidden]{display:none!important}';
  (document.head || document.documentElement).appendChild(style);
  new MutationObserver(schedule).observe(document.documentElement, { subtree: true, childList: true });
  document.addEventListener('DOMContentLoaded', schedule);
  window.GoyoDcFilter = { update(next) { settings = next; lastIDs = ''; schedule(); } };
  schedule();
})();
