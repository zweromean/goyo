const fs = require('node:fs'), path = require('node:path'), vm = require('node:vm'), assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const code = fs.readFileSync(path.join(__dirname, '../Resources/InstallPrompts.js'), 'utf8');
let checks = 0;
const nodes = {}, listeners = {};
function node() { return {isConnected: false, textContent: '', append(){}, addEventListener(){}}; }
const document = {documentElement: {appendChild(el){el.isConnected=true; nodes[el.id]=el;}}, createElement: node, querySelectorAll:()=>[], addEventListener(name, fn){listeners[name]=fn;}};
const context = {document, location: new URL('https://m.youtube.com/watch?v=lesson'), URL, MutationObserver:class{observe(){}}, setTimeout(fn){fn();}, addEventListener(){}};
context.window = context; vm.createContext(context); vm.runInContext(code, context);
const filter = context.GoyoInstallPrompts;
function check(value, expected, label){assert.equal(value, expected, label); checks++;}
function visible(html, id, expected, label) {
  const css = nodes['goyo-install-prompt-style'].textContent;
  const value = JSON.parse(execFileSync('python3', [path.join(__dirname, 'css_visibility.py')], {input:JSON.stringify({css, html, id}), encoding:'utf8'}));
  check(value, expected, label);
}
check(filter.isInstallLink('https://apps.apple.com/kr/app/id1'), true, 'Apple store blocked');
check(filter.isInstallLink('intent://watch#Intent;scheme=youtube;end'), true, 'Android intent blocked');
check(filter.isInstallLink('youtube://watch?v=x'), true, 'Native app link blocked');
check(filter.isInstallLink('https://m.youtube.com/watch?v=math'), false, 'Video web link preserved');
check(filter.isInstallLink('https://accounts.google.com/ServiceLogin'), false, 'Login preserved');
check(filter.isInstallLink('https://apps.apple.com.evil.invalid/'), false, 'Hostname matched exactly');
check(filter.installOnlyText('앱에서 열기'), true, 'Korean open app CTA');
check(filter.installOnlyText('앱 다운로드'), true, 'Korean install CTA');
check(filter.installOnlyText('Open in the YouTube app'), true, 'English native app CTA');
check(filter.installOnlyText('Continue with Google'), false, 'Login button preserved');
check(filter.installOnlyText('닫기'), false, 'Close button preserved');
const html = '<ytm-app-install-banner-renderer id="install">Install</ytm-app-install-banner-renderer><video id="video"></video><div role="dialog" id="login">Log in</div><div role="dialog" id="installDialog" data-goyo-install-prompt="true">App</div>';
visible(html, 'install', false, 'App banner removed');
visible(html, 'video', true, 'Video preserved');
visible(html, 'login', true, 'Unmarked login dialog preserved');
visible(html, 'installDialog', false, 'Marked install dialog removed');
filter.update({hideInstallPrompts:false});
visible(html, 'install', true, 'Banner restore');
visible(html, 'installDialog', true, 'Dialog restore');
filter.update({hideInstallPrompts:true});
let prevented = false, stopped = false;
listeners.click({target:{closest(){return {href:'https://apps.apple.com/app/id1'};}}, preventDefault(){prevented=true;}, stopImmediatePropagation(){stopped=true;}});
check(prevented && stopped, true, 'Install link click intercepted');
console.log(`PASS: ${checks} install-prompt classification and synthetic DOM/CSS checks; not live WebKit.`);
