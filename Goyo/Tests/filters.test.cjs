// DOM tests use synthetic fixtures, never a signed-in social account.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const script = fs.readFileSync(path.join(__dirname, '../Resources/Filters.js'), 'utf8');
const defaults = {shorts:true,reels:true,ads:true,recommendations:true,youtubeFeed:true,instagramFeed:true};

(async () => {
  const browser = await chromium.launch({headless:true});
  const page = await browser.newPage({viewport:{width:390,height:844}});
  let count = 0;
  async function fixture(url, html, options={}) {
    await page.unroute('**/*');
    await page.route('**/*', route => route.fulfill({contentType:'text/html',body:'<!DOCTYPE html><html><body>'+html+'</body></html>'}));
    await page.goto(url);
    await page.evaluate(value => window.__goyoSettings=value, {...defaults,...options});
    await page.evaluate(script);
  }
  async function visible(selector, expected, title) {
    assert.equal(await page.locator(selector).isVisible(), expected, title); count++;
  }
  try {
    await fixture('https://m.youtube.com/results?search_query=math', '<ytm-video-with-context-renderer id="search">Math lesson</ytm-video-with-context-renderer><ytm-reel-shelf-renderer id="shorts">Shorts</ytm-reel-shelf-renderer>');
    await visible('#search',true,'YouTube ordinary search survives');
    await visible('#shorts',false,'Shorts shelf hidden');
    await page.evaluate(() => GoyoFilter.update({...window.__goyoSettings,shorts:false}));
    await visible('#shorts',true,'Shorts restored when disabled');
    await fixture('https://m.youtube.com/watch?v=test', '<video id="player" controls></video><ytm-watch-next-secondary-results-renderer id="related">Recommendations</ytm-watch-next-secondary-results-renderer><ytd-ad-slot-renderer id="ad">Ad</ytd-ad-slot-renderer>');
    await visible('#player',true,'Main video remains available');
    await visible('#related',false,'Recommendations hidden');
    await visible('#ad',false,'Ad slot hidden');
    await page.evaluate(() => GoyoFilter.update({...window.__goyoSettings,recommendations:false,ads:false}));
    await visible('#related',true,'Recommendations restored');
    await visible('#ad',true,'Ads restored');
    await fixture('https://m.youtube.com/', '<header id="searchbar">Search</header><ytm-rich-grid-renderer id="feed">Home</ytm-rich-grid-renderer>');
    await visible('#searchbar',true,'Home search survives feed filtering');
    await visible('#feed',false,'YouTube home feed hidden');
    await page.evaluate(() => GoyoFilter.update({...window.__goyoSettings,youtubeFeed:false}));
    await visible('#feed',true,'Home feed restored');
    await fixture('https://m.youtube.com/shorts/abc', '<video id="short-player" controls></video>');
    await visible('#goyo-route-shield',true,'Direct Shorts route shielded');
    await page.evaluate(() => GoyoFilter.update({...window.__goyoSettings,shorts:false}));
    assert.equal(await page.locator('#goyo-route-shield').count(),0,'Route shield removed when disabled'); count++;
    await fixture('https://m.youtube.com/watch?v=abc', '<div id="ordinary">Watch</div>');
    await page.evaluate(() => history.pushState({},'', '/shorts/spa'));
    await page.waitForSelector('#goyo-route-shield'); count++;
    await page.evaluate(() => history.pushState({},'', '/watch?v=abc'));
    await page.waitForSelector('#goyo-route-shield',{state:'detached'}); count++;
    await fixture('https://www.instagram.com/', '<nav id="dm">Messages</nav><main><article id="feed">Feed post</article></main>');
    await visible('#dm',true,'DM navigation survives');
    await visible('#feed',false,'Instagram home post hidden');
    await page.evaluate(() => GoyoFilter.update({...window.__goyoSettings,instagramFeed:false}));
    await visible('#feed',true,'Instagram feed restored');
    await fixture('https://www.instagram.com/direct/inbox/', '<main><div id="inbox">Your conversation</div><article id="ordinary-post">Shared normal post</article></main>');
    await visible('#inbox',true,'Instagram inbox remains available');
    await visible('#ordinary-post',true,'Shared post in inbox not mistaken for home feed');
    await fixture('https://www.instagram.com/some_profile/', '<main><article id="sponsor"><span>Sponsored</span>Ad</article><article id="normal">Normal photo</article></main>');
    await visible('#sponsor',false,'Sponsored card hidden');
    await visible('#normal',true,'Normal profile card survives');
    await page.evaluate(() => GoyoFilter.update({...window.__goyoSettings,ads:false}));
    await visible('#sponsor',true,'Sponsored card restored');
    await fixture('https://www.instagram.com/reel/abc/', '<main>Reel</main>');
    await visible('#goyo-route-shield',true,'Direct Instagram Reel blocked');
    await fixture('https://www.instagram.com/explore/', '<main>Explore</main>');
    await visible('#goyo-route-shield',true,'Instagram explore blocked');
    await fixture('https://example.com/shorts/test', '<main id="other">Other website</main>');
    await visible('#other',true,'Unrelated site unaffected');
    assert.equal(await page.locator('#goyo-filter-style').count(),0,'No filtering on unrelated domain'); count++;
    const rules = JSON.parse(fs.readFileSync(path.join(__dirname,'../Resources/AdRules.json'),'utf8'));
    for (const rule of rules) assert.doesNotThrow(() => new RegExp(rule.trigger['url-filter']));
    assert(rules.some(r => new RegExp(r.trigger['url-filter']).test('https://googleads.g.doubleclick.net/pagead/id'))); count++;
    assert(!rules.some(r => new RegExp(r.trigger['url-filter']).test('https://m.youtube.com/watch?v=math'))); count++;
    console.log(`PASS: ${count} filter/route/network checks. Chromium synthetic DOM only; iPhone testing still required.`);
  } finally { await browser.close(); }
})().catch(error => {console.error(error);process.exitCode=1;});
