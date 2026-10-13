const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync('Include/Journal/TgeStatistics.mqh','utf8');
function body(name){
 const def=src.search(new RegExp('^(?:int|bool|void|datetime|string|color) '+name+'\\(','m'));assert(def>=0,name);
 const start=src.indexOf('{',def);let end=start+1,n=1;
 for(;n;end++){if(src[end]==='{')n++;if(src[end]==='}')n--;}return src.slice(start+1,end-1);
}
function convert(s){
 return s.replace('},filters[3]={','}; string filters[3]={').replace(/\bstring (\w+)\[\d+\]=\{([\s\S]*?)\};/g,'let $1=[$2];')
 .replace('datetime start,end; StatsRange(start,end);','let [start,end]=StatsRange();')
 .replace(/MqlDateTime (\w+);/g,'let $1={};').replace(/TgeStatsTrade (\w+);/g,'let $1=trade();')
 .replace(/\bTgeStatsTrade\s+/g,'let ')
 .replace(/\b(?:ulong|double|int) (\w+)\[\];/g,'let $1=[];')
 .replace(/\((?:datetime|int|double|ulong|long)\)/g,'')
 .replace(/\b(?:datetime|ulong|long|double|int|bool|string|color)\s+/g,'let ')
 .replace('(n+1)/2','Math.trunc((n+1)/2)').replace('months/12','Math.trunc(months/12)')
 .replace(/\bMathMax\b/g,'Math.max').replace(/\bMathMin\b/g,'Math.min').replace(/\bMathAbs\b/g,'Math.abs').replace(/\bMathRound\b/g,'Math.round');
}
function trade(){return {id:0,lastDeal:0,openTime:0,closeTime:0,magic:0,direction:0,entryDeals:0,exitDeals:0,mixed:false,reversed:false,
 entryVolume:0,exitVolume:0,entryValue:0,exitValue:0,gross:0,commission:0,swap:0,fee:0,net:0};}
function summary(){return Object.fromEntries(('trades wins losses breakevens exitDeals buyTrades sellTrades lossStreak maxLossStreak winningHolds losingHolds net volume gains lossesMoney avgWin avgLoss pf payoff best worst commission swap fee buyNet sellNet holdMinutes maxHold winningMinutes losingMinutes peak maxDrawdown').split(' ').map(k=>[k,0]));}
const start=Date.UTC(2026,9,10)/1000;let now=start+12*3600,clock=10000,history=[],selected=[],live=[],selection={},connected=true,failRange=false,failed=new Set(),rangeQueries=0;
function deal(id,entry,time,volume=.02,price=4100,opts={}){
 return {ticket:history.length+1,id,entry,time,volume,price,type:entry===0?0:1,magic:entry===0?560056:0,symbol:'XAUUSD.c',profit:0,commission:0,swap:0,fee:0,...opts};
}
function add(id,entry,time,volume=.02,price=4100,opts={}){const d=deal(id,entry,time,volume,price,opts);history.push(d);return d;}
const integers={DEAL_POSITION_ID:'id',DEAL_TYPE:'type',DEAL_ENTRY:'entry',DEAL_MAGIC:'magic',DEAL_TIME:'time'};
const doubles={DEAL_VOLUME:'volume',DEAL_PRICE:'price',DEAL_PROFIT:'profit',DEAL_COMMISSION:'commission',DEAL_SWAP:'swap',DEAL_FEE:'fee'};
const cx=vm.createContext({Math,trade,statsPeriod:0,statsOffsets:[0,0,0],statsFilter:0,statsReview:0,statsDirty:true,statsOK:false,
 statsRangeStart:0,statsRangeEnd:0,statsLastAttempt:0,statsSkipped:0,statsStatus:'',statsTrades:[],statsSummary:summary(),EA魔法号:560056,_Symbol:'XAUUSD.c',
 POSITION_TYPE_BUY:0,POSITION_TYPE_SELL:1,DEAL_TYPE_BUY:0,DEAL_TYPE_SELL:1,
 DEAL_ENTRY_IN:0,DEAL_ENTRY_OUT:1,DEAL_ENTRY_INOUT:2,DEAL_ENTRY_OUT_BY:3,SYMBOL_VOLUME_STEP:'step',TERMINAL_CONNECTED:1,
 ...Object.fromEntries(Object.keys(integers).map(k=>[k,k])),...Object.fromEntries(Object.keys(doubles).map(k=>[k,k])),
 DEAL_SYMBOL:'symbol',POSITION_IDENTIFIER:'id',POSITION_SYMBOL:'symbol',
 TimeTradeServer:()=>now,GetTickCount64:()=>clock,TerminalInfoInteger:()=>connected,
 TimeToStruct:(seconds,dt)=>{const d=new Date(seconds*1000);Object.assign(dt,{year:d.getUTCFullYear(),mon:d.getUTCMonth()+1,day:d.getUTCDate(),hour:d.getUTCHours(),min:d.getUTCMinutes(),sec:d.getUTCSeconds(),day_of_week:d.getUTCDay()});},
 StructToTime:dt=>Date.UTC(dt.year,dt.mon-1,dt.day,dt.hour,dt.min,dt.sec)/1000,
 HistorySelect:(a,b)=>{rangeQueries++;selected=history.filter(d=>d.time>=a&&d.time<=b);return !failRange;},
 HistorySelectByPosition:id=>{selected=history.filter(d=>d.id===id);return !failed.has(id);},
 HistoryDealsTotal:()=>selected.length,HistoryDealGetTicket:i=>selected[i].ticket,
 HistoryDealGetInteger:(t,p)=>history.find(d=>d.ticket===t)?.[integers[p]]||0,
 HistoryDealGetDouble:(t,p)=>history.find(d=>d.ticket===t)?.[doubles[p]]||0,
 HistoryDealGetString:(t,p)=>history.find(d=>d.ticket===t)?.[p]||'',
 PositionsTotal:()=>live.length,PositionGetTicket:i=>{selection=live[i];return selection.ticket;},
 PositionGetInteger:p=>selection[p],PositionGetString:p=>selection[p],SymbolInfoDouble:()=>.01,
 GetLastError:()=>77,IntegerToString:String,ArraySize:a=>a.length,ArrayResize:(a,n)=>{while(a.length<n)a.push(0);a.length=n;},ArraySort:a=>a.sort((x,y)=>x-y),
 ZeroMemory:a=>{for(const k of Object.keys(a))a[k]=typeof a[k]==='boolean'?false:0;}
});
for(const [name,args] of [['StatsMonth','date,offset'],['StatsRange',''],['StatsPositionOpen','id'],
 ['StatsReadTrade','id,start,end,tr'],['StatsAccumulate','tr,st'],['StatsRefresh','']]){
 let text=body(name);if(name==='StatsRange')text=text.replace('   MqlDateTime','   datetime start,end;\n   MqlDateTime')+'\nreturn [start,end];';
 vm.runInContext('function '+name+'('+args+'){'+convert(text)+'}',cx);
}
let checks=0;
function check(name,fn){history=[];selected=[];live=[];failed=new Set();connected=true;failRange=false;now=start+12*3600;clock+=40000;
 Object.assign(cx,{statsPeriod:0,statsOffsets:[0,0,0],statsFilter:0,statsDirty:true,statsLastAttempt:0,statsRangeStart:0,statsRangeEnd:0,statsReview:0});
 fn();checks++;console.log('PASS '+name);}
check('two partial exits form one trade with entry/exit fees and swap',()=>{
 add(100,0,start-3600,.02,4100,{commission:-2,fee:-.1});
 add(100,1,start+60,.01,4105,{profit:5,commission:-1});add(100,1,start+600,.01,4110,{profit:10,commission:-1,swap:-.5,fee:-.1});
 cx.StatsRefresh();assert.equal(cx.statsSummary.trades,1);assert.equal(cx.statsSummary.exitDeals,2);
 assert(Math.abs(cx.statsSummary.net-10.3)<1e-8);assert.equal(cx.statsTrades[0].exitValue/cx.statsTrades[0].exitVolume,4107.5);
});
check('still-open runner cannot inflate win rate',()=>{
 add(101,0,start,.02);add(101,1,start+60,.01,4105,{profit:5});live=[{ticket:555,id:101,symbol:'XAUUSD.c'}];
 cx.StatsRefresh();assert.equal(cx.statsSummary.trades,0);
});
check('missing residual exit is skipped even if position list is empty',()=>{
 add(102,0,start,.02);add(102,1,start+60,.01);cx.StatsRefresh();assert.equal(cx.statsSummary.trades,0);assert.equal(cx.statsSkipped,1);
});
check('manual close Magic=0 remains attributed to original EA entry',()=>{
 add(103,0,start);add(103,1,start+120,.02,4110,{magic:0,profit:20});cx.StatsRefresh();assert.equal(cx.statsSummary.trades,1);assert.equal(cx.statsSummary.net,20);
});
check('cross-period partial exits are assigned only to actual final-close period',()=>{
 add(104,0,start-3*86400);add(104,1,start-86400,.01,4105,{profit:5});add(104,1,start+60,.01,4110,{profit:10});
 cx.statsOffsets[0]=-1;cx.StatsRefresh();assert.equal(cx.statsSummary.trades,0);
 cx.statsOffsets[0]=0;cx.StatsRefresh();assert.equal(cx.statsSummary.trades,1);assert.equal(cx.statsSummary.net,15);
});
check('entries older than 90 days are queried by position and retain costs',()=>{
 add(105,0,start-200*86400,.02,4100,{commission:-1});add(105,1,start+100,.02,4110,{profit:10});cx.StatsRefresh();assert.equal(cx.statsSummary.net,9);
});
check('same-symbol manual/EA/all filters use entry Magic',()=>{
 add(106,0,start,.02,4100,{magic:0});add(106,1,start+200,.02,4110,{profit:1});
 add(107,0,start);add(107,1,start+100,.02,4110,{profit:2});
 cx.StatsRefresh();assert.equal(cx.statsSummary.trades,1);
 cx.statsFilter=1;cx.statsDirty=true;clock+=1000;cx.StatsRefresh();assert.equal(cx.statsSummary.net,1);
 cx.statsFilter=2;cx.statsDirty=true;clock+=1000;cx.StatsRefresh();assert.equal(cx.statsSummary.trades,2);
});
check('other symbols and deposits cannot enter statistics',()=>{
 add(108,0,start,.02,4100,{symbol:'EURUSD'});add(108,1,start+100,.02,4110,{symbol:'EURUSD',profit:999});
 add(0,1,start+100,0,0,{type:2,profit:10000});cx.StatsRefresh();assert.equal(cx.statsSummary.trades,0);
});
check('history-query failure is unavailable rather than false zero profit',()=>{
 failRange=true;cx.StatsRefresh();assert.equal(cx.statsOK,false);assert(cx.statsStatus.includes('失败'));
});
check('one failed position query cannot publish incomplete totals',()=>{
 add(109,0,start);add(109,1,start+100,.02,4110,{profit:10});failed.add(109);cx.StatsRefresh();assert.equal(cx.statsOK,false);assert.equal(cx.statsTrades.length,0);
});
check('netting reversal is explicitly skipped',()=>{
 cx.statsFilter=2;add(110,0,start);add(110,2,start+100,.04,4110,{profit:10});cx.StatsRefresh();assert.equal(cx.statsSkipped,1);assert.equal(cx.statsSummary.trades,0);
});
check('zero baseline captures initial losing trade drawdown',()=>{
 const st=summary();for(const net of [-10,5,-7])cx.StatsAccumulate({...trade(),net,openTime:1,closeTime:61},st);
 assert.equal(st.net,-12);assert.equal(st.maxDrawdown,12);assert.equal(st.maxLossStreak,1);
});
check('wins/losses/breakevens and loss streaks use full net result',()=>{
 const st=summary();for(const net of [10,-5,-5,0,-2])cx.StatsAccumulate({...trade(),net,openTime:1,closeTime:61},st);
 assert.deepEqual([st.wins,st.losses,st.breakevens,st.lossStreak,st.maxLossStreak],[1,3,1,1,2]);assert(Math.abs(st.pf-10/12)<1e-8);
});
check('future period shows no records without invalid range query',()=>{
 const calls=rangeQueries;cx.statsOffsets[0]=1;cx.StatsRefresh();assert.equal(cx.statsOK,true);assert.equal(rangeQueries,calls);assert(cx.statsStatus.includes('尚未'));
});
check('month navigation crosses year and leap month correctly',()=>{
 const jan=Date.UTC(2026,0,25)/1000;assert.equal(cx.StatsMonth(jan,-1),Date.UTC(2025,11,1)/1000);
 assert.equal(cx.StatsMonth(Date.UTC(2024,1,15)/1000,1),Date.UTC(2024,2,1)/1000);
 cx.statsPeriod=1;now=Date.UTC(2026,9,11,12)/1000;assert.deepEqual(Array.from(cx.StatsRange()),[Date.UTC(2026,9,5)/1000,Date.UTC(2026,9,12)/1000]);
});
check('unchanged page uses cache; deal dirty refresh and periodic fallback work',()=>{
 add(111,0,start);add(111,1,start+100,.02,4110,{profit:10});cx.StatsRefresh();const calls=rangeQueries;
 clock+=1000;cx.StatsRefresh();assert.equal(rangeQueries,calls);
 cx.statsDirty=true;cx.StatsRefresh();assert.equal(rangeQueries,calls+1);
 clock+=30000;cx.StatsRefresh();assert.equal(rangeQueries,calls+2);
});
check('position query changing global history cannot lose other IDs or duplicate exits',()=>{
 for(let i=0;i<55;i++){add(200+i,0,start,.02);add(200+i,1,start+100,.01,4105,{profit:1});add(200+i,1,start+200,.01,4110,{profit:2});}
 cx.StatsRefresh();assert.equal(cx.statsSummary.trades,55);assert.equal(cx.statsSummary.exitDeals,110);assert.equal(cx.statsSummary.net,165);
});
check('no real trading or transaction-state mutation in statistics module',()=>{
 assert(!/\b(?:OrderSend|PositionOpen|PositionClose|PositionModify|Store|SavePending|ClearPending|Open|Manage)\s*\(/.test(src));assert(!/\bexecution\s*\./.test(src));
});
console.log(checks+' production-source statistics offline checks passed');

// 直接执行生产绘图函数，用示例成交检查坐标/空态，并可导出离线预览。
let ops=[],hits=[];
const main=fs.readFileSync('EA_T哥点位跟单.mq5','utf8');
for(const m of main.matchAll(/(UI_[A-Z]+)=C'(\d+),(\d+),(\d+)'/g))cx[m[1]]=[+m[2],+m[3],+m[4]];
function format(s,...a){let i=0;return s.replace(/%([-+]?)(?:\.(\d+))?([sdf])/g,(_,sign,p,t)=>{const v=a[i++];return t==='s'?String(v):t==='d'?String(Math.trunc(v)):Number(v).toFixed(Number(p||6));});}
Object.assign(cx,{
 _Digits:2,TIME_DATE:1,TIME_MINUTES:2,ACCOUNT_CURRENCY:0,
 DoubleToString:(v,d)=>Number(v).toFixed(d),StringFormat:format,
 StringFind:(s,t)=>s.indexOf(t),StringSubstr:(s,i,n)=>n===undefined?s.slice(i):s.slice(i,i+n),
 TimeToString:(s,flags)=>new Date(s*1000).toISOString().slice(0,flags===1?10:16).replace('T',' '),
 AccountInfoString:()=>'USC',UIPx:v=>Math.round(v),UIInk:v=>v,
 UIRound:(x,y,w,h,c)=>ops.push({op:'rect',x,y,w,h,color:c,r:8}),
 UICard:(x,y,w,h,c)=>ops.push({op:'rect',x,y,w,h,color:c,r:8}),
 UIText:(text,x,y,w,size,color,right=false)=>ops.push({op:'text',text:String(text),x,y,w,size,color,right}),
 UIButton:(text,x,y,w,action,active=false)=>{
  hits.push({x,y,w,h:27,action});cx.UIRound(x,y,w,27,active?[30,65,62]:cx.UI_HEADER);cx.UIText(text,x+8,y+5,w-16,9,active?cx.UI_ACCENT:cx.UI_MUTED);
 },
 panelCanvas:{
  LineAA:(x,y,x2,y2,color)=>ops.push({op:'line',x,y,x2,y2,color}),
  Line:(x,y,x2,y2,color)=>ops.push({op:'line',x,y,x2,y2,color}),
  FillRectangle:(x,y,x2,y2,color)=>ops.push({op:'rect',x,y,w:x2-x+1,h:y2-y+1,color,r:0}),
  FillCircle:(x,y,r,color)=>ops.push({op:'circle',x,y,r,color}),Update:()=>{}
 }
});
for(const [name,args] of [['StatsMoney','value'],['StatsInk','value'],['StatsLine','row,left,right'],['StatsDrawCurve',''],['StatsPanel','']])
 vm.runInContext('function '+name+'('+args+'){'+convert(body(name))+'}',cx);
cx.StatsRefresh=()=>{};
function sample(values){
 cx.statsTrades=values.map((net,i)=>({...trade(),id:820100+i,net,gross:net+.2,commission:-.2,direction:i%2,entryVolume:.02,exitVolume:.02,
  entryValue:82,exitValue:82.1,exitDeals:2,openTime:start+i*600,closeTime:start+i*600+300}));
 cx.statsSummary=summary();for(const t of cx.statsTrades)cx.StatsAccumulate(t,cx.statsSummary);
 Object.assign(cx,{statsOK:true,statsSkipped:0,statsStatus:values.length?'按完整平仓统计':'此区间没有符合筛选的完整平仓记录',statsRangeStart:start,statsRangeEnd:start+86400,statsReview:0});
}
function render(detail){
 cx.statsDetail=detail;ops=[];hits=[];
 const height=detail===2?650:570;
 cx.UIRound(0,0,560,height,cx.UI_ROOT);cx.UIRound(0,0,560,40,cx.UI_HEADER);
 cx.UIText('XAUUSD.c · 交易统计',16,10,222,11,cx.UI_TEXT);cx.UIText('v1.28',242,13,40,8,cx.UI_DIM);
 cx.UIText('09:42:16',286,12,100,10,cx.UI_MUTED,true);cx.UIText('交易模式',434,13,110,9,cx.UI_ACCENT,true);
 ['监控','统计','看盘'].forEach((s,i)=>cx.UIButton(s,12+i*76,49,68,2+i,i===1));
 cx.UIButton('手机TP开',240,49,100,28,true);cx.UIText('已同步5条',350,56,110,8.5,cx.UI_DIM);cx.UIButton('点位线开',462,49,82,27,true);
 cx.StatsPanel();
 for(const o of ops){
  for(const k of ['x','y','x2','y2','w','h','r'])if(k in o)assert(Number.isFinite(o[k]),'finite '+k);
  assert(o.x>=0&&o.y>=0&&o.x<560&&o.y<height,'origin within canvas');
  if(o.op==='rect')assert(o.w>0&&o.h>0&&o.x+o.w<=560&&o.y+o.h<=height,'rectangle bounds');
  if(o.op==='line')assert(o.x2>=0&&o.x2<560&&o.y2>=0&&o.y2<height,'line bounds');
 }
 for(let i=0;i<hits.length;i++)for(let j=i+1;j<hits.length;j++){const a=hits[i],b=hits[j];assert(a.x+a.w<=b.x||b.x+b.w<=a.x||a.y+a.h<=b.y||b.y+b.h<=a.y,'distinct button targets');}
 return {width:560,height,ops,hits};
}
check('curve and profit bars render mixed, all-loss, zero, single and dense samples without changing totals',()=>{
 for(const values of [[10,-4,7,-2,3],[-4,-8,-1],[0,0,0],[8],Array.from({length:500},(_,i)=>i%3-1)]){
  sample(values);const before=JSON.stringify([cx.statsTrades,cx.statsSummary]);render(2);
  assert.equal(JSON.stringify([cx.statsTrades,cx.statsSummary]),before);
  assert(ops.some(o=>o.text==='累计净收益'));assert(ops.some(o=>o.text==='每笔盈亏'));
  assert(ops.some(o=>o.text==='最新 '+cx.StatsMoney(values.reduce((a,b)=>a+b,0))));
 }
});
check('all statistics pages and empty/error states publish bounded controls and honest captions',()=>{
 sample([12,-3,5]);for(let d=0;d<4;d++)render(d);
 sample([]);render(2);assert(!ops.some(o=>o.text==='累计净收益'));
 cx.statsOK=false;cx.statsStatus='历史查询失败';render(0);assert(ops.some(o=>o.text==='历史查询失败'));assert(ops.filter(o=>o.text==='--').length===4);
});
if(process.env.TGE_STATS_PREVIEW){
 fs.mkdirSync(process.env.TGE_STATS_PREVIEW,{recursive:true});
 sample([8.6,-3.4,12.2,-5.8,4.6,9.1,-2.3,6.8,-4.2,11.7,-3.6,5.4]);
 for(const [name,d] of [['overview',0],['performance',1],['trend',2],['review',3]])
  fs.writeFileSync(process.env.TGE_STATS_PREVIEW+'/'+name+'.json',JSON.stringify(render(d),null,2));
 sample([]);fs.writeFileSync(process.env.TGE_STATS_PREVIEW+'/empty.json',JSON.stringify(render(2),null,2));
}
console.log(checks+' statistics data/render checks passed; native MT5 clicks not exercised.');
