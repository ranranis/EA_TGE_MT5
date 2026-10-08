// Offline tests of extracted code. No terminal, orders, or broker timing claims.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const mainFile = fs.readFileSync(path.join(root, 'EA_交易托管系统_v1.56.mq5'), 'utf8');
const main = [mainFile, fs.readFileSync(path.join(root, 'Include/UI/CanvasPanel.mqh'), 'utf8'),
  fs.readFileSync(path.join(root, 'Include/Trading/TeacherAuto.mqh'), 'utf8')].join('\n');
const sr = fs.readFileSync(path.join(root, 'Include/Market/SupportResistance.mqh'), 'utf8');
const indicators = fs.readFileSync(path.join(root, 'Include/Market/IndicatorHandles.mqh'), 'utf8');
function body(source, name) {
  const at = source.search(new RegExp(`(?:bool|void|int|string) ${name}\\(`));
  assert(at >= 0, name);
  const start = source.indexOf('{', at);
  let end = start + 1, depth = 1;
  for (; depth && end < source.length; end++) {
    if (source[end] === '{') depth++;
    if (source[end] === '}') depth--;
  }
  return source.slice(start + 1, end - 1);
}
function translate(code) {
  return code.replace(/\b(?:int|double|MqlRates) (\w+)\[\];/g, 'let $1=[];')
    .replace(/\((?:int|long|double)\)/g, '')
    .replace(/\b(?:int|long|double|bool)\s+/g, 'let ');
}
let checks = 0;
function test(name, run) { run(); checks++; console.log(`PASS ${name}`); }
const density = body(sr, 'AddDensityLevelsByM1PriceBuckets');
const block = density.slice(density.indexOf('double buckets[];'), density.indexOf('int maxCandidates'));
const optimized = new Function('rates', 'bucketSize', 'ArrayResize', `
  const copied=rates.length, ArraySize=a=>a.length, ArrayInitialize=(a,v)=>a.fill(v);
  const MathFloor=Math.floor, MathMin=Math.min, MathMax=Math.max, MathAbs=Math.abs;
  ${translate(block)}
  return {buckets,counts};
`);
const resize = (a,n) => { a.length=n; return n; };
function original(rates, size) {
  const buckets=[], counts=[];
  for (const bar of rates) {
    for (let b=Math.floor(bar.low/size); b<=Math.floor(bar.high/size); b++) {
      const center=(b+.5)*size;
      const at=buckets.findIndex(v=>Math.abs(v-center)<size*.1);
      if(at<0) { buckets.push(center); counts.push(1); } else counts[at]++;
    }
  }
  return {buckets,counts};
}
let seed=156;
function random() { seed=(Math.imul(seed,1664525)+1013904223)>>>0; return seed/2**32; }
test('density: 1000 deterministic sets preserve counts, prices and tie order', () => {
  for(let n=0;n<1000;n++) {
    const size=[.1,.25,1,3.7][n%4], rates=[];
    for(let i=0;i<1+n%60;i++) {
      const low=(random()-.5)*40+3000;
      rates.push({low,high:low+random()*5});
    }
    assert.deepEqual(optimized(rates,size,resize),original(rates,size));
  }
});
test('density: negatives, exact boundaries, ties and fallback', () => {
  for(const rates of [
    [{low:-1,high:0},{low:0,high:1}],
    [{low:1,high:1},{low:0,high:0}],
    [{low:0,high:1},{low:300000,high:300001}],
  ]) assert.deepEqual(optimized(rates,1,resize),original(rates,1));
  const rates=[{low:0,high:2},{low:1,high:3}];
  const allocationFailure=(a,n)=>n===4 && a.length===0 ? -1 : resize(a,n);
  assert.deepEqual(optimized(rates,1,allocationFailure),original(rates,1));
});
test('indicator resources: reuse, key isolation, failure retry and cleanup', () => {
  const acquire=translate(body(indicators,'GetManagedIndicatorHandle'));
  const release=translate(body(indicators,'ReleaseManagedIndicatorHandles'));
  const execute=new Function(`
    const MANAGED_EMA=0,MANAGED_ATR=1,MANAGED_ADX=2,INVALID_HANDLE=-1;
    const _Symbol='TEST',MODE_EMA=1,PRICE_CLOSE=1,MathMax=Math.max;
    let next=10,fail=false,allocFail=false,created=0;
    const managedIndicatorHandles=[],freed=[];
    const ArraySize=a=>a.length;
    const ArrayResize=(a,n)=>{if(allocFail&&n>0)return -1; while(a.length<n)a.push({});a.length=n;return n;};
    const IndicatorRelease=h=>freed.push(h);
    const iMA=()=>{created++;return fail?-1:next++;},iATR=iMA,iADX=iMA;
    const get=(kind,timeframe,period)=>{${acquire}};
    const clear=()=>{${release}};
    const a=get(0,5,20),same=get(0,5,20),b=get(0,60,20),c=get(1,5,20);
    fail=true;const failed=get(2,5,14);fail=false;const retried=get(2,5,14);
    allocFail=true;const allocationFailed=get(1,60,14);allocFail=false;
    clear();clear();
    return {a,same,b,c,failed,retried,allocationFailed,created,freed};
  `)();
  assert.equal(execute.a,execute.same);
  assert.notEqual(execute.a,execute.b);
  assert.notEqual(execute.a,execute.c);
  assert.equal(execute.failed,-1);
  assert.equal(execute.allocationFailed,-1);
  assert(execute.retried>=0);
  assert.equal(execute.created,6);
  assert.equal(execute.freed.length,5);
  assert.equal(new Set(execute.freed).size,5);
});
test('Tick: data-only structure calls, unchanged management entrypoints', () => {
  const tick=body(main,'OnTick');
  assert(!/RefreshPanel\(|ChartRedraw\(/.test(tick));
  for(const call of tick.matchAll(/RefreshMarketStructureCaches\(([^)]*)\)/g))
    assert.equal(call[1].replace(/\s/g,''),'false,false');
  for(const name of ['ManagePosition','ManageNewsHedge','ShortEmergencyRiskManagement','ManageTeacherAutoReversal','ManageMobileMarkerOrders'])
    assert(tick.includes(name+'('),name);
  assert(body(main,'OnTimer').includes('RefreshPanel(false)'));
});
test('template: retain old cache, defer only marker synchronization', () => {
  const change=body(main,'ApplyPanelConfigTemplate');
  assert(!change.includes('ArrayResize'));
  assert(!change.includes('ManageMobileMarkerOrders('));
  assert(change.includes('手机标记环境Dirty=true'));
  assert(change.includes('保存当前配置模板()'));
  assert(change.includes('RefreshMarketStructureCaches(false)'));
  assert(!body(main,'RebuildATRHandleForCurrentTemplate').includes('IndicatorRelease'));
  assert(!body(main,'TrendLongCopyBufferValue').includes('IndicatorRelease'));
  assert(body(main,'OnDeinit').indexOf('ReleaseManagedIndicatorHandles()') < body(main,'OnDeinit').indexOf('return'));
});
test('ellipsis: extracted binary search agrees with original width scan', () => {
  const code=translate(body(main,'Ellipsize'))
    .replace(/\bstring\s+/g,'let ')
    .replace('low+(high-low+1)/2','Math.floor(low+(high-low+1)/2)');
  const fn=new Function('text','maxWidth','m_canvas',`
    const fontName='test',fontSize=12,StringLen=s=>s.length;
    const StringSubstr=(s,start,count)=>count===undefined?s.slice(start):s.slice(start,start+count);
    ${code}
  `);
  const width=s=>Array.from(s).reduce((sum,c)=>sum+(c.charCodeAt(0)>127?12:6),0);
  const canvas={FontSet:()=>true,TextWidth:width};
  for(const text of ['', 'short', 'long text '.repeat(50), '中文持仓信息'.repeat(50)]) {
    for(let limit=0;limit<150;limit++) {
      let expected=text;
      if(limit<=0) expected='';
      else if(width(text)>limit) {
        if(width('...')>limit) expected='';
        else { while(expected.length && width(expected+'...')>limit) expected=expected.slice(0,-1); expected+='...'; }
      }
      assert.equal(fn(text,limit,canvas),expected);
    }
  }
});
test('default automatic entry remains gated by existing strategy checks', () => {
  assert(/input bool\s+启用老师点位自动反转短线\s*=\s*true\s*;/.test(mainFile));
  assert(/input bool\s+老师自动使用积极策略\s*=\s*true\s*;/.test(mainFile));
  const auto=body(main,'ManageTeacherAutoReversal');
  for(const gate of ['!启用老师点位自动反转短线','!currentTickHasNewM1Bar','TeacherActiveCanOpen()',
    'TeacherActivePlanValid()','teacherActiveHistoryReady','MQL_TRADE_ALLOWED','TERMINAL_TRADE_ALLOWED'])
    assert(auto.includes(gate),gate);
  assert(/input string\s+老师点位文本\s*=\s*""/.test(mainFile));
});
test('SR classification: share complete bars; retry partial history; skip unused reads', () => {
  const reaction=new Function('lv','resistance','rates','copied',`
    const MathMin=Math.min,MathMax=Math.max,MathAbs=Math.abs;
    ${translate(body(sr,'HasM1ReactionAtLevel'))}
  `);
  const code=translate(body(sr,'ClassifySRTradingIntent')).replace('GetATRPrice(atr)','(atr=2,true)');
  const classify=new Function('arr','highVol','history','reaction',`
    let reads=0;
    const resistance=true,refPrice=100,trendRegime=0;
    const MathMin=Math.min,MathMax=Math.max,MathAbs=Math.abs,ArraySize=a=>a.length;
    const ArraySetAsSeries=()=>{},_Symbol='TEST',PERIOD_M1=1;
    const SR_TF_M5=2,SR_TF_M15=4,SRRoundLevelBonus=()=>0;
    const 支撑压力合并距离价格=1,支撑压力最大交易显示距离价格=20;
    const 支撑压力A级线最低分=20,支撑压力B级线最低分=15,支撑压力可交易线最低分=10;
    const 支撑压力最小有效反应价格=1,支撑压力启用到位提示=true,支撑压力接近距离价格=2;
    const CopyRates=(symbol,tf,shift,count,out)=>{
      if(shift!==1||count!==4)throw Error('must read closed M1 bars');
      const rows=history[Math.min(reads++,history.length-1)];
      out.splice(0,out.length,...rows);return rows.length;
    };
    const HasM1ReactionAtLevel=reaction;
    ${code}
    return reads;
  `);
  const levels=()=>Array.from({length:12},()=>({price:100,tradeScore:30,strength:5,
    boxBoundary:true,tfMask:2,touches:3}));
  const bars=Array.from({length:4},()=>({open:100.2,close:99.9,high:100.5,low:99.8}));
  const full=levels();assert.equal(classify(full,false,[bars],reaction),1);
  assert(full.every(l=>l.statusText==='空头反应'));
  assert.equal(classify(levels(),true,[bars],reaction),0);
  assert.equal(classify([],false,[bars],reaction),0);
  assert.equal(classify(levels(),false,[bars.slice(0,1),bars],reaction),2);
  assert.equal(reaction({price:100},true,bars,1),false);
});
if(process.argv[2]) test('module extraction: expanded main differs only in authorized default', () => {
  const baseline=fs.readFileSync(path.resolve(root,process.argv[2]),'utf8').replace(/\r\n/g,'\n');
  let expanded=mainFile.replace(/\r\n/g,'\n');
  for(const file of ['Include/Trading/TeacherAuto.mqh','Include/UI/CanvasPanel.mqh']) {
    const module=fs.readFileSync(path.join(root,file),'utf8').replace(/\r\n/g,'\n');
    const contents=module.replace(/^#ifndef [^\n]+\n#define [^\n]+\n\n/,'').replace(/#endif\s*$/,'');
    expanded=expanded.replace(`#include "${file}"\n\n`,contents);
  }
  const normalize=s=>s.replace(/^input bool\s+启用老师点位自动反转短线\s*=.*$/m,'AUTHORIZED_AUTO_DEFAULT');
  assert.equal(normalize(expanded),normalize(baseline));
});
test('density workload: indexed results equal original on 240 bars', () => {
  const rates=Array.from({length:240},(_,i)=>({low:2900+i*.3,high:2910+i*.3}));
  const begin=performance.now(),oldResult=original(rates,.1),oldMs=performance.now()-begin;
  const start=performance.now(),newResult=optimized(rates,.1,resize),newMs=performance.now()-start;
  assert.deepEqual(newResult,oldResult);
  console.log(`JS model only: density old=${oldMs.toFixed(2)}ms new=${newMs.toFixed(2)}ms; not MT5 latency`);
});
console.log(`${checks} performance regression groups passed`);
