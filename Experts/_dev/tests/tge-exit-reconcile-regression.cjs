// Execute production exit/reconciliation bodies against isolated server snapshots.
// No MT5 connection, account mutation, order submission or live pending reset.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync('EA_T哥点位跟单.mq5','utf8');
function body(name){
 const def=src.search(new RegExp('^(?:void|bool|string) '+name+'\\(','m'));
 assert(def>=0,name); const start=src.indexOf('{',def);let end=start+1,depth=1;
 for(;depth;end++){if(src[end]==='{')depth++;if(src[end]==='}')depth--;}
 return src.slice(start+1,end-1);
}
function install(x,name,args=''){
 const s=body(name).replace(/MqlTick (\w+);/g,'let $1={};').replace(/CTrade (\w+);/g,'let $1=new CTrade();')
 .replace(/\((?:ulong|datetime|uint|double|int)\)/g,'')
 .replace(/\b(?:const )?(?:ulong|double|int|long|bool|string|uint|datetime)\s+/g,'let ');
 vm.runInContext('function '+name+'('+args+'){'+s+'}',x);
}
function env(opts={}){
 const logs=[],memory={},sent=[];
 const IN=0,OUT=1,OUTBY=2,INOUT=3,BUY=0,SELL=1;
 let selectedDeal,selectedOrder;
 let deals=opts.deals||[
  {ticket:100,position:77,symbol:'XAUUSD.c',entry:IN,type:SELL,magic:560056,volume:.02,time:700,order:10},
  {ticket:101,position:77,symbol:'XAUUSD.c',entry:OUT,type:BUY,magic:0,volume:.02,time:900,order:20}
 ];
 const orders=opts.orders||{
  10:{symbol:'XAUUSD.c',position:77,magic:560056,type:SELL,time:700},
  20:{symbol:'XAUUSD.c',position:77,magic:560056,type:BUY,time:900}
 };
 let remaining=opts.remaining||0;
 const x=vm.createContext({
  pending:{kind:2,position:77,at:900,order:10,volume:.02,...opts.pending},
  stateOK:true,reason:'',_Symbol:'XAUUSD.c',EA魔法号:560056,
  DEAL_POSITION_ID:'position',DEAL_SYMBOL:'symbol',DEAL_ENTRY:'entry',DEAL_TYPE:'type',
  DEAL_MAGIC:'magic',DEAL_VOLUME:'volume',DEAL_TIME:'time',DEAL_ORDER:'order',
  DEAL_ENTRY_IN:IN,DEAL_ENTRY_OUT:OUT,DEAL_ENTRY_OUT_BY:OUTBY,DEAL_ENTRY_INOUT:INOUT,
  DEAL_TYPE_BUY:BUY,ORDER_TYPE_BUY:BUY,ORDER_TYPE_SELL:SELL,
  ORDER_SYMBOL:'symbol',ORDER_POSITION_ID:'position',ORDER_MAGIC:'magic',ORDER_TIME_SETUP:'time',ORDER_TYPE:'type',
  POSITION_VOLUME:'volume',TERMINAL_CONNECTED:1,
  TerminalInfoInteger:()=>true,TimeCurrent:()=>1000,MathAbs:Math.abs,
  HistorySelectByPosition:id=>id===77 && opts.history!==false,
  HistoryDealsTotal:()=>deals.length,
  HistoryDealGetTicket:i=>{selectedDeal=deals[i];return selectedDeal.ticket;},
  HistoryDealGetInteger:(ticket,k)=>deals.find(d=>d.ticket===ticket)?.[k]??0,
  HistoryDealGetString:(ticket,k)=>deals.find(d=>d.ticket===ticket)?.[k]??'',
  HistoryDealGetDouble:(ticket,k)=>deals.find(d=>d.ticket===ticket)?.[k]??0,
  HistoryDealSelect:ticket=>deals.some(d=>d.ticket===ticket),
  OrderSelect:ticket=>opts.liveOrder===ticket,
  HistoryOrderSelect:ticket=>{selectedOrder=orders[ticket];return !!selectedOrder;},
  HistoryOrderGetString:(ticket,k)=>orders[ticket]?.[k]??'',
  HistoryOrderGetInteger:(ticket,k)=>orders[ticket]?.[k]??0,
  PositionById:()=>remaining>0?7:0,
  PositionGetDouble:()=>remaining,
  FinalOrderConfirmed:order=>{sent.push(['checkFinal',order]);return opts.final!==false;},
  LifeEntry:()=>{},DecisionLog:(...args)=>logs.push(args),
  SavePending:()=>{Object.assign(memory,x.pending);return true;},
  ClearPending:()=>{x.pending={kind:0};Object.assign(memory,{kind:0});},
  CanExecute:()=>true,PositionSelectByTicket:()=>true,OwnSelected:()=>true,ExactLot:()=>true,
  ZeroMemory:p=>{for(const key of Object.keys(p))delete p[key];},
  ExplicitReject:code=>code===10014,PrintFormat:()=>{},
  // Global execution deliberately contains a stale entry result. Exit must never read it.
  execution:{ResultOrder:()=>10,ResultDeal:()=>100,ResultRetcode:()=>10009},
  CTrade:function(){
   sent.push(['fresh']);
   return {
    SetExpertMagicNumber:v=>sent.push(['magic',v]),SetDeviationInPoints:()=>{},
    SetTypeFillingBySymbol:()=>{},SetAsyncMode:()=>{},
    PositionModify:(...args)=>{sent.push(['modify',...args]);return opts.result?.ok??false;},
    PositionClose:(...args)=>{sent.push(['full',...args]);return opts.result?.ok??false;},
    PositionClosePartial:(...args)=>{sent.push(['partial',...args]);return opts.result?.ok??false;},
    ResultRetcode:()=>opts.result?.code??0,ResultOrder:()=>opts.result?.order??0,
    ResultDeal:()=>opts.result?.deal??0,ResultComment:()=>'synthetic'
   };
  }
 });
 Object.assign(x,{
  FreshQuote:q=>Object.assign(q,{bid:100,ask:100.1}),Stops:()=>true,TickSize:()=>.01,
  POSITION_SL:'sl',POSITION_TP:'tp',TimeGMT:()=>1000,GlobalVariablesFlush:()=>{},
  AIKeyFromHash:()=>'visit',SharedVisitKey:()=>'shared',MergeOpportunity:()=>sent.push(['merge']),
  Store:(k,v)=>{memory[k]=v;return true;},Load:k=>memory[k]||0,
  HistorySelect:()=>opts.history!==false,HistoryOrdersTotal:()=>Object.keys(orders).length,
  HistoryOrderGetTicket:i=>Number(Object.keys(orders)[i]),ORDER_COMMENT:'comment',EntryTag:()=>'same-tag',
  ORDER_VOLUME_INITIAL:'initial',ORDER_VOLUME_CURRENT:'remaining',
  HistoryOrderGetDouble:(t,k)=>orders[t]?.[k]??0,SaveEntryExits:()=>true,
 });
 const codes={REQUOTE:10004,REJECT:10006,CANCEL:10007,PLACED:10008,DONE:10009,DONE_PARTIAL:10010,
 ERROR:10011,TIMEOUT:10012,INVALID:10013,INVALID_VOLUME:10014,INVALID_PRICE:10015,INVALID_STOPS:10016,
 TRADE_DISABLED:10017,MARKET_CLOSED:10018,NO_MONEY:10019,PRICE_CHANGED:10020,PRICE_OFF:10021,
 INVALID_EXPIRATION:10022,ORDER_CHANGED:10023,TOO_MANY_REQUESTS:10024,NO_CHANGES:10025,
 SERVER_DISABLES_AT:10026,CLIENT_DISABLES_AT:10027,LOCKED:10028,FROZEN:10029,INVALID_FILL:10030,
 CONNECTION:10031,ONLY_REAL:10032,LIMIT_ORDERS:10033,LIMIT_VOLUME:10034,INVALID_ORDER:10035,
 POSITION_CLOSED:10036,INVALID_CLOSE_VOLUME:10038,CLOSE_ORDER_EXIST:10039,LIMIT_POSITIONS:10040,
 REJECT_CANCEL:10041,LONG_ONLY:10042,SHORT_ONLY:10043,CLOSE_ONLY:10044,FIFO_CLOSE:10045,HEDGE_PROHIBITED:10046};
 for(const [k,v]of Object.entries(codes))x['TRADE_RETCODE_'+k]=v;
 install(x,'ExplicitReject','code');install(x,'RecordResult','requestTrade');
 install(x,'AbortUnsent','releaseVisit=false');install(x,'EntryOrderMatches','order');
 install(x,'Modify','ticket,id,sign,sl,tp');install(x,'ReconcileExit');install(x,'Reconcile');install(x,'RequestExit','ticket,id,volume,full,why');
 return {x,logs,sent,memory,setDeals:v=>deals=v,setRemaining:v=>remaining=v};
}
let count=0;
function test(name,fn){fn();count++;console.log('PASS '+name);}
test('saved entry-order bug recovers only from full real lifecycle, including server SL magic 0',()=>{
 const {x,logs,memory}=env();x.Reconcile();
 assert.equal(x.pending.kind,0);assert.equal(memory.kind,0);
 assert.equal(logs[0][0],'POSITION_CLOSED');
});
test('missing position without matching exit volume remains pending',()=>{
 const e=env();e.setDeals([{ticket:100,position:77,symbol:'XAUUSD.c',entry:0,type:1,magic:560056,volume:.02,time:700,order:10}]);
 e.x.Reconcile();assert.equal(e.x.pending.kind,2);assert(e.x.reason.includes('对账'));
});
test('unavailable history and disconnection cannot unlock',()=>{
 for(const opts of [{history:false},{history:true}]){
  const {x}=env(opts);if(opts.history)x.TerminalInfoInteger=()=>false;
  x.Reconcile();assert.equal(x.pending.kind,2);
 }
});
test('delayed exit arrives on later timer and then recovers',()=>{
 const e=env();const exit={ticket:101,position:77,symbol:'XAUUSD.c',entry:1,type:0,magic:0,volume:.02,time:900,order:20};
 const entry={ticket:100,position:77,symbol:'XAUUSD.c',entry:0,type:1,magic:560056,volume:.02,time:700,order:10};
 e.setDeals([entry]);e.x.Reconcile();assert.equal(e.x.pending.kind,2);
 e.setDeals([entry,exit]);e.x.Reconcile();assert.equal(e.x.pending.kind,0);
});
test('other symbol, position, owner and netting reversal never confirm',()=>{
 for(const patch of [{symbol:'EURUSD'},{position:88},{magic:99},{entry:3}]){
  const e=env();e.setDeals([{ticket:100,position:77,symbol:'XAUUSD.c',entry:0,type:1,magic:560056,volume:.02,time:700,order:10,...patch},
  {ticket:101,position:77,symbol:'XAUUSD.c',entry:1,type:0,magic:0,volume:.02,time:900,order:20}]);
  e.x.Reconcile();assert.equal(e.x.pending.kind,2);
 }
});
test('live server order prevents even full-volume unlock',()=>{
 const {x}=env({liveOrder:10});x.Reconcile();assert.equal(x.pending.kind,2);
});
test('partial exit rebinds stale entry order and checks remaining position',()=>{
 const {x,sent}=env({remaining:.01,deals:[
  {ticket:100,position:77,symbol:'XAUUSD.c',entry:0,type:1,magic:560056,volume:.02,time:700,order:10},
  {ticket:101,position:77,symbol:'XAUUSD.c',entry:1,type:0,magic:560056,volume:.01,time:900,order:20}]});
 x.Reconcile();assert.equal(x.pending.kind,0);assert.deepEqual(sent,[['checkFinal',20]]);
});
test('partial fill on unfinished server order stays pending; no close is retried',()=>{
 const e=env({remaining:.01,pending:{order:20},final:false,deals:[
  {ticket:100,position:77,symbol:'XAUUSD.c',entry:0,type:1,magic:560056,volume:.02,time:700,order:10},
  {ticket:101,position:77,symbol:'XAUUSD.c',entry:1,type:0,magic:560056,volume:.01,time:900,order:20}]});
 e.x.Reconcile();assert.equal(e.x.pending.kind,2);assert.equal(e.sent.filter(a=>a[0]==='fresh').length,0);
});
test('ambiguous exit orders do not rebind unknown request',()=>{
 const e=env({remaining:.01,deals:[
  {ticket:100,position:77,symbol:'XAUUSD.c',entry:0,type:1,magic:560056,volume:.02,time:700,order:10},
  {ticket:101,position:77,symbol:'XAUUSD.c',entry:1,type:0,magic:560056,volume:.005,time:900,order:20},
  {ticket:102,position:77,symbol:'XAUUSD.c',entry:1,type:0,magic:560056,volume:.005,time:901,order:21}]});
 e.x.Reconcile();assert.equal(e.x.pending.kind,2);
});
test('position/history volume mismatch stays blocked',()=>{
 const {x}=env({remaining:.01});x.Reconcile();assert.equal(x.pending.kind,2);
});
test('immediate close failure cannot reuse cached global entry response',()=>{
 const e=env({remaining:.02,pending:{kind:0}});
 e.x.RequestExit(7,77,.02,true,'synthetic');
 assert.equal(e.x.pending.kind,2);assert.equal(e.x.pending.order,0);
 assert.equal(e.memory.order,0);assert(e.sent.some(a=>a[0]==='fresh'));
});
test('fresh close deal binds actual exit order instead of entry order',()=>{
 const e=env({remaining:.02,pending:{kind:0},result:{ok:true,code:10009,order:20,deal:101}});
 e.x.RequestExit(7,77,.01,false,'synthetic');
 assert.equal(e.x.pending.kind,2);assert.equal(e.x.pending.order,20);
 assert(e.sent.some(a=>a[0]==='partial'&&a[2]===.01));
});
test('explicit rejection clears intent but unknown response stays pending',()=>{
 for(const code of [10014,0,10012]){
  const e=env({remaining:.02,pending:{kind:0},result:{code}});
  e.x.RequestExit(7,77,.02,true,'synthetic');
  assert.equal(e.x.pending.kind,code===10014?0:2);
 }
});

test('new explicit refusal codes release all request kinds, never clear ambiguous replies',()=>{
 const definite=[10022,10024,10026,10027,10029,10032,10033,10035,10038,10040,10042,10043,10044,10045,10046];
 const uncertain=[0,10008,10009,10010,10011,10012,10023,10028,10031,10036,10039];
 for(const kind of [1,2,3])for(const code of [...definite,...uncertain]){
  const {x}=env({pending:{kind,order:0,fast:true,level:100,direction:1}});
  x.RecordResult({ResultRetcode:()=>code,ResultOrder:()=>0,ResultDeal:()=>0,ResultComment:()=>'test'});
  assert.equal(x.pending.kind,definite.includes(code)?0:kind,kind+'/'+code);
 }
});
test('NO_CHANGES is a completed no-op only for a modification, not an entry',()=>{
 for(const kind of [1,3]){
  const {x}=env({pending:{kind,order:0}});
  x.RecordResult({ResultRetcode:()=>10025,ResultOrder:()=>0,ResultDeal:()=>0,ResultComment:()=>'no change'});
  assert.equal(x.pending.kind,kind===3?0:1);
 }
});
test('modify uses its fresh response when position disappears inside CTrade',()=>{
 const {x,sent,memory}=env({remaining:.02,pending:{kind:0}});
 x.Modify(7,77,1,99,110);
 assert(sent.some(c=>c[0]==='modify'));assert.equal(x.pending.kind,3);
 assert.equal(x.pending.order,0);assert.equal(memory.order,0);
});
test('modify already closed position reconciles only after real exit arrives',()=>{
 const e=env({pending:{kind:3,order:0}});e.x.Reconcile();assert.equal(e.x.pending.kind,0);
 const f=env({pending:{kind:3,order:0}});f.setDeals([{ticket:100,entry:0,volume:.02}]);
 f.x.Reconcile();assert.equal(f.x.pending.kind,3);
});
test('permission lost before send clears unsent modify/close; no broker call',()=>{
 for(const modify of [false,true]){
  const {x,sent}=env({remaining:.02,pending:{kind:0}});let n=0;x.CanExecute=()=>++n===1;
  if(modify)x.Modify(7,77,1,99,110);else x.RequestExit(7,77,.02,true,'test');
  assert.equal(x.pending.kind,0);assert(!sent.some(c=>c[0]==='fresh'));
 }
});
test('failed persistence cannot submit close or modify',()=>{
 for(const modify of [false,true]){
  const {x,sent}=env({remaining:.02,pending:{kind:0}});x.SavePending=()=>{x.stateOK=false;return false;};
  if(modify)x.Modify(7,77,1,99,110);else x.RequestExit(7,77,.02,true,'test');
  assert(!sent.some(c=>c[0]==='fresh'));assert.notEqual(x.pending.kind,0);
 }
});
test('aborted consumed entry releases its visit; failed storage keeps recovery evidence',()=>{
 const {x,memory}=env({pending:{kind:1,fast:true}});memory.visit=1;memory.shared=1;
 x.AbortUnsent(true);assert.equal(x.pending.kind,0);assert.equal(memory.visit,0);assert.equal(memory.shared,0);
 const e=env({pending:{kind:1,fast:true}});e.x.stateOK=false;e.x.AbortUnsent(true);assert.equal(e.x.pending.kind,1);
});
test('pending commits only after every field write succeeds; torn save survives restart as -1',()=>{
 for(let fail=1;fail<=21;fail++){
  const {x,memory}=env();memory.kind=2;let n=0;
  x.Store=(k,v)=>{if(++n===fail){x.stateOK=false;return false;}memory[k]=v;return true;};
  install(x,'SavePending');install(x,'RestorePending');
  assert.equal(x.SavePending(),false);assert.equal(n,fail);
  assert.equal(memory.kind,fail===1?2:-1);
  x.RestorePending();assert.equal(x.pending.kind,fail===1?2:-1);
 }
 const e=env();install(e.x,'SavePending');install(e.x,'RestorePending');
 assert.equal(e.x.SavePending(),true);e.x.pending={};e.x.RestorePending();
 assert.equal(e.x.pending.kind,2);assert.equal(e.x.pending.position,77);assert.equal(e.x.pending.order,10);
});
function entryOrders(extra={}){
 return {20:{symbol:'XAUUSD.c',magic:560056,type:0,time:900,comment:'same-tag',initial:.02,remaining:0,...extra}};
}
test('entry recovery rejects old same-tag orders, wrong direction, owner and symbol',()=>{
 for(const patch of [{time:899},{type:1},{magic:5},{symbol:'EURUSD'}]){
  const {x,sent}=env({pending:{kind:1,order:0,direction:1},orders:entryOrders(patch)});
  x.Reconcile();assert.equal(x.pending.kind,1);assert(!sent.some(c=>c[0]==='checkFinal'));
 }
});
test('unique matching entry rebinds stale order and confirms; multiple candidates never guess',()=>{
 const e=env({pending:{kind:1,order:10,direction:1},orders:entryOrders()});
 e.x.Reconcile();assert.equal(e.x.pending.kind,0);assert(e.sent.some(c=>c[0]==='checkFinal'&&c[1]===20));
 const orders=entryOrders();orders[21]={...orders[20]};
 const f=env({pending:{kind:1,order:0,direction:1},orders});
 f.x.Reconcile();assert.equal(f.x.pending.kind,1);assert(!f.sent.some(c=>c[0]==='checkFinal'));
});
test('terminal order still waits for every filled lot to appear as a deal',()=>{
 const e=env({pending:{kind:1,order:20,direction:1},orders:entryOrders({state:4})});
 Object.assign(e.x,{ORDER_STATE:'state',ORDER_STATE_FILLED:4,ORDER_STATE_CANCELED:2,ORDER_STATE_REJECTED:3,ORDER_STATE_EXPIRED:5});
 // Translate MQL enum cast locally, leaving the production reconciliation unchanged.
 const s=body('FinalOrderConfirmed').replace(/\(ENUM_ORDER_STATE\)/g,'')
 .replace(/\((?:ulong|double)\)/g,'').replace(/\b(?:ENUM_ORDER_STATE|double|int|ulong)\s+/g,'let ');
 vm.runInContext('function FinalOrderConfirmed(order){'+s+'}',e.x);
 e.setDeals([{ticket:1,order:20,volume:.01}]);e.x.Reconcile();assert.equal(e.x.pending.kind,1);
 e.setDeals([{ticket:1,order:20,volume:.01},{ticket:2,order:20,volume:.01}]);
 e.x.Reconcile();assert.equal(e.x.pending.kind,0);
});
console.log('PASS '+count+' lifecycle regression cases');

