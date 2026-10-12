// Extract production MQL functions; fake broker only. Never connects or sends actual orders.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..');
const main=fs.readFileSync(path.join(root,'EA_T哥点位跟单.mq5'),'utf8');
const limit=fs.readFileSync(path.join(root,'Include/Trading/TgeLimitOrders.mqh'),'utf8');
const ai=fs.readFileSync(path.join(root,'Include/Trading/TgeAISignals.mqh'),'utf8');
function body(name){
 for(const s of [main,limit,ai]){
  const pos=s.search(new RegExp('^(?:bool|void|double|int|string|ulong) '+name+'\\(','m'));
  if(pos<0)continue;const begin=s.indexOf('{',pos);let end=begin+1,depth=1;
  for(;depth;end++){if(s[end]==='{')depth++;if(s[end]==='}')depth--;}
  return s.slice(begin+1,end-1);
 }throw Error(name);
}
function translate(s){
 return s.replace(/\((?:ENUM_ORDER_STATE|ENUM_ORDER_TYPE|double|long|ulong|int|datetime)\)/g,'')
  .replace(/\bdouble (\w+)\[\],(\w+)\[\];/g,'let $1=[], $2=[];')
  .replace(/\b(?:double|MqlRates) (\w+)\[\];/g,'let $1=[];')
  .replace(/\bMqlTick (\w+);/g,'let $1={};')
  .replace(/\b(?:double|long|ulong|int|datetime|bool|string|uint|ENUM_ORDER_STATE|ENUM_ORDER_TYPE)\s+/g,'let ')
  .replace(/Target\((price|entry),sign,tp\)/g,'(tp=$1+sign*10,Target($1,sign))')
  .replace(/OrderCalcMargin\(type,_Symbol,每次开仓手数,price,margin\)/g,'(margin=1,OrderCalcMargin(type,_Symbol,每次开仓手数,price))');
}
function install(e,name,args=''){vm.runInContext('function '+name+'('+args+'){'+translate(body(name))+'}',e);}
function env(){
 const memory={},orders=[],history=[],deals=[],calls=[];
 let selected=null,historySelected=null;
 const e=vm.createContext({
  MathMin:Math.min,MathMax:Math.max,MathAbs:Math.abs,MathIsValidNumber:Number.isFinite,
  ArraySize:a=>a.length,ArraySetAsSeries:()=>{},IntegerToString:String,DoubleToString:(v,n)=>v.toFixed(n),
  StringFind:(a,b)=>a.indexOf(b),Hash:s=>[...s].reduce((h,c)=>(h*31+c.charCodeAt(0))>>>0,0),
  _Symbol:'XAUUSD',_Digits:2,_Point:.01,EA魔法号:560056,每次开仓手数:.02,最大同时持仓:3,
  保险价格距离:10,首批止盈价格距离:5,尾仓目标价格距离:10,点位提前容差:3,最大点差价格:.5,
  启用趋势提前挂单:true,读取AI即时策略:true,feedActive:true,aiReady:true,aiMode:'SETUP',aiIdentity:'source1',aiSource:'source1',
  aiGenerated:1000,aiSourceTime:900,aiTrend:1,aiTrendReady:true,atr:2,maHandle:1,atrHandle:2,
  aiPlans:[{sign:1,level:100,market:false},{sign:-1,level:120,market:false}],
  stateOK:true,pending:{kind:0},reason:'',entryView:{},EMPTY_VALUE:Number.MAX_VALUE,
  TimeGMT:()=>1000,TimeCurrent:()=>1000,TimeTradeServer:()=>1000,iTime:(_,tf)=>tf===5?900:940,
  PERIOD_M1:1,PERIOD_M5:5,CanExecute:()=>e.allowed,allowed:true,
  TerminalInfoInteger:()=>true,TERMINAL_CONNECTED:1,
  Target:()=>e.targetOK,targetOK:true,Align:v=>Math.round(v*100)/100,TickSize:()=>.01,
  ExactLot:v=>v===.02,FreshQuote:q=>e.fresh&&Object.assign(q,e.quote),fresh:true,quote:{bid:107,ask:107.1},
  OwnCount:()=>e.positionCount,positionCount:0,ExecutionBlock:()=>e.pending.kind?'pending':e.OwnCount()+e.AILimitCount()>=3?'capacity':'',
  SymbolInfoInteger:(_,k)=>k==='SYMBOL_ORDER_MODE'?2:k==='SYMBOL_EXPIRATION_MODE'?1:0,
  OrderCalcMargin:()=>e.marginOK,marginOK:true,AccountInfoDouble:()=>100,ACCOUNT_MARGIN_FREE:1,
  Load:k=>memory[k]||0,Store:(k,v)=>{memory[k]=v;calls.push(['save',k,v]);return true;},
  GlobalVariablesFlush:()=>{},ZeroMemory:o=>{for(const k of Object.keys(o))o[k]=0;Object.assign(o,{kind:0,order:0,position:0,sourceHash:0,at:0,bar:0,volume:0,sl:0,tp:0,level:0,direction:0});},
  DecisionLog:(...a)=>calls.push(['log',...a]),PrintFormat:()=>{},
  OrdersTotal:()=>orders.length,OrderGetTicket:i=>{selected=orders[i];return selected?.ticket||0;},
  OrderSelect:t=>{selected=orders.find(o=>o.ticket===t);return !!selected;},
  OrderGetString:k=>selected?.[k]||'',OrderGetInteger:k=>selected?.[k]||0,OrderGetDouble:k=>selected?.[k]||0,
  HistoryOrderSelect:t=>{historySelected=history.find(o=>o.ticket===t);return !!historySelected;},
  HistoryOrderGetInteger:(t,k)=>history.find(o=>o.ticket===t)?.[k]||0,
  HistoryOrderGetDouble:(t,k)=>history.find(o=>o.ticket===t)?.[k]||0,
  HistoryOrderGetString:(t,k)=>history.find(o=>o.ticket===t)?.[k]||'',
  HistoryOrdersTotal:()=>history.length,HistoryOrderGetTicket:i=>history[i]?.ticket||0,
  HistorySelect:(start,end)=>{e.range=[start,end];return e.historyOK;},historyOK:true,
  HistoryDealsTotal:()=>deals.length,HistoryDealGetTicket:i=>i,
  HistoryDealGetInteger:(i,k)=>deals[i]?.[k]||0,HistoryDealGetDouble:(i,k)=>deals[i]?.[k]||0,
  HistoryDealSelect:()=>false,HistorySelectByPosition:()=>false,PositionById:()=>0,
  retcode:9999,resultOrder:0,
  execution:{
   SetTypeFilling:p=>calls.push(['fill',p]),SetTypeFillingBySymbol:()=>calls.push(['fill','symbol']),
   BuyLimit:(...a)=>calls.push(['buyLimit',...a]),SellLimit:(...a)=>calls.push(['sellLimit',...a]),
   OrderDelete:t=>calls.push(['delete',t]),
   ResultRetcode:()=>e.retcode,ResultOrder:()=>e.resultOrder,ResultDeal:()=>0,ResultComment:()=> 'test'
  }
 });
 for(const k of new Set((main+limit).match(/\b(?:ORDER_[A-Z_]+|SYMBOL_[A-Z_]+|DEAL_[A-Z_]+|TRADE_RETCODE_[A-Z_]+)\b/g)))e[k]=k;
 for(const [k,v] of Object.entries({SYMBOL_ORDER_LIMIT:2,SYMBOL_EXPIRATION_GTC:1}))e[k]=v;
 for(const [n,a] of [
 ['IsAILimitSelected',''],['AILimitCount',''],['AILimitTag','source,level,sign'],['HasAILimit','level,sign'],
 ['AIVisitKey','level,sign'],['AIAdvanceReady',''],['AITrendEntry','out'],['RefreshAITrend',''],
 ['SavePending',''],['ClearPending',''],['RestorePending',''],['EntryTag',''],['ExplicitReject','code'],
 ['RecordResult',''],['FinalOrderConfirmed','order'],['ReconcileAILimitCreation',''],['Reconcile',''],
 ['AILimitStillValid',''],['SyncAILimits',''],['SubmitAILimit','sign,level'],['PrepareAILimit','']])install(e,n,a);
 function order({ticket=71,source=e.aiIdentity,sign=1,level=100,magic=560056,tag,price=103}={}){
  return {ticket,ORDER_SYMBOL:'XAUUSD',ORDER_MAGIC:magic,ORDER_COMMENT:tag||e.AILimitTag(e.Hash(source),level,sign),
   ORDER_TYPE:sign===1?'ORDER_TYPE_BUY_LIMIT':'ORDER_TYPE_SELL_LIMIT',ORDER_PRICE_OPEN:price,
   ORDER_SL:price-sign*10,ORDER_TP:price+sign*10,ORDER_VOLUME_CURRENT:.02,ORDER_VOLUME_INITIAL:.02,ORDER_TIME_SETUP:100};
 }
 return {e,memory,orders,history,deals,calls,order};
}
let checks=0;function test(name,fn){fn();checks++;console.log('PASS '+name);}
test('same direction and within three price units can enter before M1 reaction',()=>{
 const {e}=env();e.quote={bid:102.8,ask:102.9};const out={};assert(e.AITrendEntry(out));assert.equal(out.direction,1);
 assert.equal(out.bar,940);e.quote={bid:103.1,ask:103.2};assert(!e.AITrendEntry({}));
});
test('sell early entry is symmetric and opposite trend never chases',()=>{
 const {e}=env();e.aiTrend=-1;e.quote={bid:117.1,ask:117.2};assert(e.AITrendEntry({}));
 e.aiTrend=1;assert(!e.AITrendEntry({}));e.aiTrend=0;assert(!e.AITrendEntry({}));
});
test('missing trend data, dead feed, spread, old quote and consumed visit block early entry',()=>{
 for(const change of [e=>e.aiTrendReady=false,e=>e.aiGenerated=980,e=>e.feedActive=false,
  e=>e.fresh=false,e=>e.quote={bid:101,ask:102},e=>e.Load=()=>990]){
  const {e}=env();e.quote={bid:102,ask:102.1};change(e);assert(!e.AITrendEntry({}));
 }
});
test('forward candles do not create early candidates',()=>{
 const {e}=env();e.quote={bid:102,ask:102.1};e.iTime=()=>1000;assert(!e.AITrendEntry({}));
});
test('M5 trend uses closed bars, slope and avoids frequent MA crossings',()=>{
 const {e}=env();e.CopyRates=(_s,_tf,shift,n,out)=>{assert.equal(shift,1);for(let i=0;i<n;i++)out.push({time:600-i*300,close:102});return n;};
 e.CopyBuffer=(h,b,shift,n,out)=>{assert.equal(shift,1);for(let i=0;i<n;i++)out.push(h===2?2:101-i*.1);return n;};
 assert(e.RefreshAITrend());assert.equal(e.aiTrend,1);
 e.CopyRates=()=>0;assert(!e.RefreshAITrend());assert.equal(e.aiTrendReady,false);assert.equal(e.aiTrend,0);
});
test('buy limit gets +3 early price, 10 SL, 10 TP and .02 lots',()=>{
 const {e,calls}=env();assert(e.SubmitAILimit(1,100));
 const c=calls.find(c=>c[0]==='buyLimit');assert.deepEqual(c.slice(1,6),[.02,103,'XAUUSD',93,113]);
 assert.equal(e.pending.kind,4);assert(calls.findIndex(c=>c[0]==='save')<calls.findIndex(c=>c[0]==='buyLimit'));
 assert(calls.some(c=>c[0]==='fill'&&c[1]==='ORDER_FILLING_RETURN'));assert.equal(calls.at(-2)?.[0],'save');
});
test('sell limit uses -3 early price and opposite SL TP',()=>{
 const {e,calls}=env();e.aiTrend=-1;e.quote={bid:110,ask:110.1};assert(e.SubmitAILimit(-1,120));
 assert.deepEqual(calls.find(c=>c[0]==='sellLimit').slice(1,6),[.02,117,'XAUUSD',127,107]);
});
test('capacity includes strategy pending orders but excludes phone and manual orders',()=>{
 const {e,orders,order}=env();orders.push(order(),order({ticket:72,magic:910406,tag:'TGE_MARK_1'}),order({ticket:73,magic:0,tag:'manual'}));
 assert.equal(e.AILimitCount(),1);e.positionCount=2;assert(!e.SubmitAILimit(1,100));
});
test('no duplicate while pending, consumed, existing limit, insufficient margin or unsupported GTC',()=>{
 for(const change of [e=>e.pending.kind=4,e=>e.Load=()=>990,e=>e.marginOK=false,e=>e.fresh=false,
  e=>e.SymbolInfoInteger=()=>0,e=>e.aiTrend=-1,e=>e.allowed=false]){
  const {e,calls}=env();change(e);assert(!e.SubmitAILimit(1,100));assert(!calls.some(c=>c[0].endsWith('Limit')));
 }
 const {e,orders,order}=env();orders.push(order());assert(!e.SubmitAILimit(1,100));
});
test('live confirmed limit releases request lock without reporting a fill',()=>{
 const {e,orders,order,calls}=env();e.SubmitAILimit(1,100);orders.push(order());e.Reconcile();
 assert.equal(e.pending.kind,0);assert.equal(orders.length,1);assert(calls.some(c=>c[0]==='log'&&c[1]==='LIMIT_CONFIRMED'));
});
test('live partial limit also releases creation lock but remains counted',()=>{
 const {e,orders,order}=env();e.SubmitAILimit(1,100);orders.push({...order(),ORDER_VOLUME_CURRENT:.01});e.Reconcile();
 assert.equal(e.pending.kind,0);assert.equal(e.AILimitCount(),1);
});
test('unknown creation stays blocked after restart and never blindly retries',()=>{
 const {e,calls}=env();e.SubmitAILimit(1,100);e.pending={kind:0};e.RestorePending();
 e.Reconcile();assert.equal(e.pending.kind,4);assert.equal(e.pending.order,0);e.PrepareAILimit();
 assert.equal(calls.filter(c=>c[0]==='buyLimit').length,1);
});
test('torn persistence keeps creation locked',()=>{
 const {e,memory}=env();memory.kind=-1;e.RestorePending();e.Reconcile();e.PrepareAILimit();assert.equal(e.pending.kind,-1);
});
test('new reference or reversed trend requests cancellation, unaffected orders isolated',()=>{
 for(const change of [e=>e.aiIdentity='source2',e=>e.aiTrend=-1,e=>e.aiReady=false,e=>e.启用趋势提前挂单=false]){
  const {e,orders,order,calls}=env();orders.push(order(),order({ticket:72,magic:910406,tag:'TGE_MARK_1'}));
  change(e);e.SyncAILimits();assert.deepEqual(calls.find(c=>c[0]==='delete'),['delete',71]);assert.equal(e.pending.kind,5);
 }
});
test('unchanged source survives hours and neutral trend does not churn the pending order',()=>{
 const {e,orders,order,calls}=env();orders.push(order());e.aiSourceTime=1;e.aiTrend=0;e.SyncAILimits();
 assert(!calls.some(c=>c[0]==='delete'));assert.equal(e.pending.kind,0);
});
test('accepted delete preserves original ticket and waits for actual disappearance',()=>{
 const {e,orders,order}=env();orders.push(order());e.aiIdentity='next';e.SyncAILimits();
 assert.equal(e.pending.order,71);e.Reconcile();assert.equal(e.pending.kind,5);
});
test('cancel fill race requires terminal state and actual filled volume before unlocking',()=>{
 const {e,orders,history,deals,order}=env();orders.push(order());e.aiIdentity='next';e.SyncAILimits();orders.pop();
 history.push({...order(),ORDER_STATE:'ORDER_STATE_FILLED',ORDER_VOLUME_CURRENT:0});e.Reconcile();assert.equal(e.pending.kind,5);
 deals.push({DEAL_ORDER:71,DEAL_VOLUME:.02});e.Reconcile();assert.equal(e.pending.kind,0);
});
test('old partial fills remain included in cancellation reconciliation',()=>{
 const {e,orders,history,deals,order}=env();orders.push(order());e.aiIdentity='next';e.SyncAILimits();orders.pop();
 history.push({...order(),ORDER_STATE:'ORDER_STATE_CANCELED',ORDER_VOLUME_CURRENT:.01});
 deals.push({DEAL_ORDER:71,DEAL_VOLUME:.01});e.Reconcile();assert.equal(e.range[0],40);assert.equal(e.pending.kind,0);
});
test('failed history read does not unlock vanished order',()=>{
 const {e,orders,history,order}=env();orders.push(order());e.aiReady=false;e.SyncAILimits();orders.pop();
 history.push({...order(),ORDER_STATE:'ORDER_STATE_CANCELED'});e.historyOK=false;e.Reconcile();assert.equal(e.pending.kind,5);
});
test('explicit broker rejection clears only intent while opportunity stays consumed',()=>{
 const {e,calls}=env();e.retcode='TRADE_RETCODE_INVALID_STOPS';e.SubmitAILimit(1,100);
 assert.equal(e.pending.kind,0);e.PrepareAILimit();assert.equal(calls.filter(c=>c[0]==='buyLimit').length,1);
});
test('source and side tagged independently, restart preserves source hash',()=>{
 const {e}=env();assert.notEqual(e.AILimitTag(1,100,1),e.AILimitTag(1,100,-1));assert.notEqual(e.AILimitTag(1,100,1),e.AILimitTag(2,100,1));
 e.SubmitAILimit(1,100);const hash=e.pending.sourceHash;e.pending={kind:0};e.RestorePending();assert.equal(e.pending.sourceHash,hash);
});
test('live order cannot be duplicated via closed M1 or early market path',()=>{
 const {e,orders,order}=env();orders.push(order());e.quote={bid:102,ask:102.1};assert(!e.AITrendEntry({}));
 assert(body('AISignal').includes('!HasAILimit(level,sign)'));assert(body('Open').includes('HasAILimit(signal.level,signal.direction)'));
});
test('completed M1 id remains valid through whole current minute; stale ids wait',()=>{
 const {e}=env();e.quote={bid:102,ask:102.1};e.iTime=()=>900;assert(e.AITrendEntry({}));
 e.iTime=()=>880;assert(!e.AITrendEntry({}));
});
test('server live order must match direction, pending price and protections to release request',()=>{
 for(const changed of [{ORDER_PRICE_OPEN:104},{ORDER_TYPE:'ORDER_TYPE_SELL_LIMIT'},{ORDER_SL:0}]){
  const {e,orders,order}=env();e.SubmitAILimit(1,100);orders.push({...order(),...changed});e.Reconcile();
  assert.equal(e.pending.kind,4);
 }
});
console.log(checks+' production-source advance/limit checks passed; no broker requests.');
