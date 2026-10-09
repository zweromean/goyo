const assert = require('node:assert/strict'), fs = require('node:fs'), vm = require('node:vm'), path = require('node:path');
const policy = require('../Resources/DcPolicy.js');
let count = 0;
function check(value, label) { assert(value, label); count++; }
check(policy.galleryID(' ABC_123 ') === 'abc_123', 'Normalize ID');
for (const id of ['', '../test', '한글', 'a?x', 'x'.repeat(81)]) check(policy.galleryID(id) === null, `Reject invalid ID: ${id}`);
for (const prefix of ['board', 'mini']) {
  const r = policy.parse(`https://m.dcinside.com/${prefix}/test/123?recommend=1`);
  check(r.gallery === 'test' && r.post === '123' && r.recommended, `Mobile ${prefix} post`);
}
for (const prefix of ['', 'mgallery/', 'mini/']) {
  const r = policy.parse(`https://gall.dcinside.com/${prefix}board/lists/?id=test&exception_mode=recommend&page=2`);
  check(r.gallery === 'test' && r.post === null && r.recommended, `Desktop ${prefix} list`);
  check(policy.parse(`https://gall.dcinside.com/${prefix}board/view/?id=test&no=123`).post === '123', 'Desktop post ID');
}
for (const url of ['https://evil.test/board/test/1', 'https://m.dcinside.com.evil.test/board/test', 'javascript:alert(1)', 'https://m.dcinside.com/board/test/write', 'https://gall.dcinside.com/board/view/?id=test', 'https://gall.dcinside.com/board/view/?id=test&no=../3', 'https://gall.dcinside.com/something/board/list/?id=test']) check(policy.parse(url) === null, `Reject unsupported route ${url}`);
check(policy.allows('test', { dcGalleryMode: 'allow', dcGalleryIDs: ['test'] }), 'Allow configured gallery');
check(!policy.allows('other', { dcGalleryMode: 'allow', dcGalleryIDs: ['test'] }), 'Block unlisted gallery');
check(!policy.allows('test', { dcGalleryMode: 'allow', dcGalleryIDs: [] }), 'Empty allow list blocks all');
check(!policy.allows('test', { dcGalleryMode: 'block', dcGalleryIDs: ['test'] }), 'Block configured gallery');
check(policy.allows('other', { dcGalleryMode: 'block', dcGalleryIDs: ['test'] }), 'Unblocked gallery preserved');
check(policy.allows('test', { dcGalleryMode: 'none', dcGalleryIDs: ['test'] }), 'Disabled restriction');
const mobile = new URL(policy.recommendedList('https://m.dcinside.com/board/test/123?page=2&recommend=0'));
check(mobile.pathname === '/board/test' && mobile.searchParams.get('recommend') === '1' && mobile.searchParams.get('page') === '2', 'Mobile canonical recommended list');
const desktop = new URL(policy.recommendedList('https://gall.dcinside.com/mgallery/board/view/?id=test&no=123&exception_mode=notice&page=4'));
check(desktop.pathname === '/mgallery/board/lists/' && !desktop.searchParams.has('no') && desktop.searchParams.get('exception_mode') === 'recommend', 'Desktop canonical list');

const script = fs.readFileSync(path.join(__dirname, '../Resources/DcFilters.js'), 'utf8');
function fixture(url, settings = {}, selected = true) {
  const messages = [], replacements = [], nodes = [], queued = [], anchors = [], list = [];
  let tabSelected = selected;
  function node() { return { style: {}, textContent: '', isConnected: false, setAttribute(){}, removeAttribute(){}, remove() { this.isConnected = false; } }; }
  const host = { appendChild(n) { nodes.push(n); n.isConnected = true; } };
  const tab = { textContent: '개념글', closest() { return tabSelected ? {} : null; }, getAttribute() { return null; }, setAttribute(){}, removeAttribute(){} };
  const document = { body: host, documentElement: host, head: host, createElement: node, addEventListener(){},
    querySelectorAll(selector) {
      if (selector === 'a,button') return [tab];
      if (selector.startsWith('.gall-detail-lst')) return list;
      return anchors;
    }
  };
  const location = new URL(url); location.replace = value => replacements.push(value);
  const context = { document, location, URL, GoyoDcPolicy: policy, __goyoSettings: { dcRecommendedOnly: true, ...settings },
    MutationObserver: class { observe(){} }, requestAnimationFrame(fn) { queued.push(fn); return queued.length; },
    webkit: { messageHandlers: { goyo: { postMessage(value) { messages.push(value); } } } } };
  context.window = context; vm.createContext(context); vm.runInContext(script, context);
  function flush() { while (queued.length) queued.shift()(); }
  function link(href, { notice = false, desktopNotice = false, inList = true } = {}) {
    const attrs = new Set();
    const a = { getAttribute() { return href; }, setAttribute(name) { attrs.add(name); }, removeAttribute(name) { attrs.delete(name); },
      closest(selector) { if (selector === 'tr') return { querySelector() { return { textContent: desktopNotice ? '공지' : '100' }; } }; return notice ? {} : null; }, attrs };
    anchors.push(a); if (inList) list.push(a); return a;
  }
  return { context, messages, replacements, nodes, flush, link, selectTab(value) { tabSelected = value; }, update(next) { context.GoyoDcFilter.update(next); flush(); }, veil() { return nodes.find(n => n.isConnected && n.style.cssText); } };
}
const h = fixture('https://m.dcinside.com/board/test?recommend=1');
h.link('/board/test/100?recommend=1'); h.link('/board/test/100?recommend=1');
h.link('/board/test/101', { notice: true }); h.link('/board/test/102', { desktopNotice: true });
h.link('/board/other/103?recommend=1'); h.link('/board/test/104', { inList: false });
h.link('http://['); // malformed href must not stop the filter
const general = h.link('/board/test'); h.flush();
check(h.messages.length === 1 && h.messages[0].ids.join(',') === '100', 'Only deduplicated same-gallery list posts approved; notices/sidebar/malformed href excluded');
check(general.attrs.has('data-goyo-dc-hidden'), 'General-list tab hidden');
check(!h.veil(), 'Verified selected recommended list visible');
h.update({ dcRecommendedOnly: false });
check(!general.attrs.has('data-goyo-dc-hidden'), 'General-list tab restored when disabled');
const stale = fixture('https://m.dcinside.com/board/test?recommend=1', {}, false); stale.link('/board/test/1'); stale.flush();
check(stale.messages.length === 0 && !!stale.veil(), 'Query flag alone is insufficient without selected recommended tab');
stale.selectTab(true); stale.update({ dcRecommendedOnly: true });
check(stale.messages.length === 1 && !stale.veil(), 'Later DOM tab confirmation lifts veil');
const redirect = fixture('https://m.dcinside.com/board/test?page=3'); redirect.flush();
check(redirect.replacements.length === 1 && new URL(redirect.replacements[0]).searchParams.get('recommend') === '1', 'General list redirected');
const denied = fixture('https://m.dcinside.com/board/other?recommend=1', { dcGalleryMode: 'allow', dcGalleryIDs: ['test'] }); denied.flush();
check(!!denied.veil() && denied.messages.length === 0, 'Disallowed gallery blocked in DOM');
const post = fixture('https://m.dcinside.com/board/test/100?recommend=1'); post.link('/board/test/999'); post.flush();
check(post.messages.length === 0, 'Post-body links cannot authorize another post');
console.log(`PASS: ${count} DC route and mocked DOM checks; native WebKit policy requires device validation.`);
