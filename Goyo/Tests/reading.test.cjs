const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict'),path=require('node:path');
const script=fs.readFileSync(path.join(__dirname,'../Resources/Filters.js'),'utf8');
function harness() {
  let now=0,nextTimer=0,observer;
  const timers=new Map(),messages=[],nodes={},listeners={};
  const articles=[];
  const document={visibilityState:'visible',
    documentElement:{appendChild(n){n.isConnected=true;nodes[n.id]=n}},
    createElement(){return {style:{},children:[],append(){},addEventListener(){},remove(){this.isConnected=false;delete nodes[this.id]}}},
    querySelectorAll(s){return s==='main article'?articles:[]},
    addEventListener(name,fn){listeners[name]=fn}};
  const location=new URL('https://www.instagram.com/profile/');
  const context={document,location,URL,
    history:{pushState(_a,_b,url){location.href=new URL(url,location).href},replaceState(_a,_b,url){location.href=new URL(url,location).href}},
    MutationObserver:class{observe(){}},
    IntersectionObserver:class{constructor(cb){this.cb=cb;this.targets=new Set();observer=this}observe(a){this.targets.add(a)}unobserve(a){this.targets.delete(a)}disconnect(){this.targets.clear()}},
    setTimeout(fn,ms){const id=++nextTimer;timers.set(id,{fn,at:now+ms});return id},clearTimeout(id){timers.delete(id)},
    getComputedStyle(a){return {display:a.hidden?'none':'block'}},addEventListener(){},
    webkit:{messageHandlers:{goyo:{postMessage(m){messages.push(m)}}}}};
  context.window=context;vm.createContext(context);vm.runInContext(script,context);
  function article(id,labels=[]) {
    const value={isConnected:true,dataset:{},id,hidden:false,
      querySelector(){return this.id?{href:'https://www.instagram.com/p/'+this.id+'/'}:null},
      querySelectorAll(){return labels.map(textContent=>({textContent}))},
      hasAttribute(name){return this.dataset[name==='data-goyo-ad'?'goyoAd':'goyoSuggested']!==undefined},
      removeAttribute(name){delete this.dataset[name==='data-goyo-ad'?'goyoAd':'goyoSuggested']}};
    articles.push(value);context.GoyoFilter.update({});return value;
  }
  function advance(ms){const end=now+ms;while(true){const due=[...timers].filter(([,t])=>t.at<=end).sort((a,b)=>a[1].at-b[1].at)[0];if(!due)break;now=due[1].at;timers.delete(due[0]);due[1].fn()}now=end}
  function intersect(a,ratio){observer.cb([{target:a,isIntersecting:ratio>0,intersectionRatio:ratio}])}
  return {context,messages,article,advance,intersect,get observer(){return observer}};
}
let n=0;function check(value,label){assert(value,label);n++}
const h=harness();let a=h.article('one');
check(h.observer.targets.has(a),'Unique article is observed');
h.intersect(a,0.4);h.advance(1200);check(h.messages.length===0,'Under half visible does not count');
h.intersect(a,0.7);h.advance(999);check(h.messages.length===0,'Dwell shorter than one second does not count');
h.advance(1);check(h.messages.length===1,'One second visible counts');
h.intersect(a,0.7);h.advance(1000);check(h.messages.length===1,'Same article deduplicated');
a=h.article('two');h.intersect(a,0.7);h.advance(500);h.intersect(a,0);h.advance(1000);check(h.messages.length===1,'Leaving viewport cancels pending dwell');
h.intersect(a,0.7);h.context.GoyoFilter.setResting(true);h.advance(2000);check(h.messages.length===1,'Rest clears pending dwell');
h.context.GoyoFilter.setResting(false);h.intersect(a,0.7);h.advance(1000);check(h.messages.length===2,'Rest finish observes posts again');
a.id='three';h.context.GoyoFilter.update({});h.intersect(a,0.7);h.advance(1000);check(h.messages.length===3,'Reused DOM article with new permalink counts');
a=h.article('sponsored',['Sponsored']);h.intersect(a,0.9);h.advance(1000);check(h.messages.length===3,'Sponsored card not counted');
a=h.article('suggested',['Suggested for you']);h.intersect(a,0.9);h.advance(1000);check(h.messages.length===3,'Hidden recommended card not counted');
a=h.article(null);h.intersect(a,0.9);h.advance(1000);check(h.messages.length===3,'No stable permalink is not counted');
a=h.article('hidden');a.hidden=true;h.intersect(a,0.9);h.advance(1000);check(h.messages.length===3,'CSS hidden card not counted');
a=h.article('offscreen');h.context.document.visibilityState='hidden';h.intersect(a,0.9);h.advance(1000);check(h.messages.length===3,'Background article not counted');
h.context.document.visibilityState='visible';h.context.history.pushState({},'', '/direct/inbox/');a=h.article('dm');h.intersect(a,0.9);h.advance(1000);check(h.messages.length===3,'DM content is not counted as feed');
console.log(`PASS: ${n} mocked IntersectionObserver/dwell/counter tests; not an actual browser runtime.`);
