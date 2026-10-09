(function (root) {
  'use strict';
  const galleryID = value => /^[a-z0-9_]{1,80}$/.test(String(value).trim().toLowerCase()) ? String(value).trim().toLowerCase() : null;
  function parse(value) {
    let u; try { u = new URL(value); } catch (_) { return null; }
    if (!['http:', 'https:'].includes(u.protocol)) return null;
    const p = u.pathname.split('/').filter(Boolean), q = u.searchParams;
    if (u.hostname === 'm.dcinside.com' && [2, 3].includes(p.length) && ['board', 'mini'].includes(p[0])) {
      const gallery = galleryID(p[1]), post = p[2] || null;
      return gallery && (!post || /^\d+$/.test(post)) ? { gallery, post, recommended: q.get('recommend') === '1' } : null;
    }
    const i = p.indexOf('board');
    if (u.hostname === 'gall.dcinside.com' && i === p.length - 2 && (i === 0 || (i === 1 && ['mgallery', 'mini'].includes(p[0])))) {
      const action = p[i + 1], gallery = galleryID(q.get('id') || ''), post = action === 'view' ? q.get('no') : null;
      if (!gallery || !['list', 'lists', 'view'].includes(action) || (action === 'view' && (!post || !/^\d+$/.test(post)))) return null;
      return { gallery, post, recommended: q.get('exception_mode') === 'recommend' };
    }
    return null;
  }
  function allows(gallery, settings) {
    const ids = new Set((settings.dcGalleryIDs || []).map(galleryID).filter(Boolean));
    return settings.dcGalleryMode === 'allow' ? ids.has(gallery) : settings.dcGalleryMode === 'block' ? !ids.has(gallery) : true;
  }
  function recommendedList(value) {
    const u = new URL(value), r = parse(value), mobile = u.hostname === 'm.dcinside.com';
    u.searchParams.delete('no');
    if (r && r.post) u.pathname = mobile ? `/${u.pathname.startsWith('/mini/') ? 'mini' : 'board'}/${r.gallery}` : u.pathname.replace('/view', '/lists');
    u.searchParams.set(mobile ? 'recommend' : 'exception_mode', mobile ? '1' : 'recommend');
    return u.href;
  }
  const policy = { galleryID, parse, allows, recommendedList };
  root.GoyoDcPolicy = policy;
  if (typeof module !== 'undefined' && module.exports) module.exports = policy;
})(typeof globalThis !== 'undefined' ? globalThis : window);
