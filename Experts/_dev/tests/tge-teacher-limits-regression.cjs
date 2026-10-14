// Executes extracted production limit-order functions with a fake broker only.
const assert=require('node:assert/strict');
const savedLog=console.log;console.log=()=>{};
const {env,install,body}=require('./tge-near-entry-regression.cjs');console.log=savedLog;
let checks=0;function test(name,fn){fn();checks++;console.log('LIMIT PASS '+name);}
const zero=()=>({state:0,sign:0,order:0,source:0,at:0,retry:0,level:0,sl:0,tp:0,first:0,be:0,finalTP:0});
function broker(options={}){
 const base=env({plans:options.plans||[{sign:1,level:4175,origin:'teacher-new',created:990,market:false,derived:false}],memory:options.memory});
 const {x,memory}=base,orders=new Map(),history=new Map(),deals=[],calls=[];
 let selected=0,result=0,code=10008,next=200;
 const keys=['ORDER_MAGIC','ORDER_TYPE','ORDER_TIME_SETUP','ORDER_STATE','ORDER_VOLUME_INITIAL','ORDER_VOLUME_CURRENT',
 'ORDER_SYMBOL','ORDER_COMMENT','DEAL_ORDER','DEAL_ENTRY','DEAL_MAGIC','DEAL_POSITION_ID','DEAL_VOLUME','DEAL_SYMBOL'];
 const enums=Object.fromEntries(keys.map((k,i)=>[k,i+10]));
 Object.assign(x,enums,{挂单最大离价:50,TEACHER_LIMIT_LOTS:.02,teacherLimits:Array.from({length:4},zero),最大同时持仓:3,
  EA魔法号:560056,_Point:.01,SYMBOL_ORDER_MODE:1,SYMBOL_ORDER_LIMIT:2,SYMBOL_TRADE_STOPS_LEVEL:3,SYMBOL_TRADE_FREEZE_LEVEL:4,
  ORDER_TYPE_BUY_LIMIT:5,ORDER_TYPE_SELL_LIMIT:6,ORDER_TIME_GTC:0,ORDER_STATE_FILLED:7,ORDER_STATE_CANCELED:8,ORDER_STATE_REJECTED:9,ORDER_STATE_EXPIRED:10,
  DEAL_ENTRY_IN:0,SymbolInfoInteger:(_,k)=>k===1?2:0,
  StringFind:(s,t)=>s.indexOf(t),StringLen:s=>s.length,StringSubstr:(s,n)=>s.slice(n),
  PrintFormat:()=>{},HistorySelect:()=>true,OrdersTotal:()=>orders.size,HistoryOrdersTotal:()=>history.size,HistoryDealsTotal:()=>deals.length,
  OrderGetTicket:n=>{selected=[...orders.keys()][n];return selected;},
  OrderSelect:t=>{selected=t;return orders.has(t);},
  OrderGetInteger:k=>orders.get(selected)?.[k]||0,OrderGetString:k=>orders.get(selected)?.[k]||'',
  HistoryOrderSelect:t=>history.has(t),HistoryOrderGetTicket:n=>[...history.keys()][n],
  HistoryOrderGetInteger:(t,k)=>history.get(t)?.[k]||0,HistoryOrderGetDouble:(t,k)=>history.get(t)?.[k]||0,
  HistoryOrderGetString:(t,k)=>history.get(t)?.[k]||'',
  HistoryDealGetTicket:n=>n,HistoryDealGetInteger:(n,k)=>deals[n]?.[k]||0,
  HistoryDealGetDouble:(n,k)=>deals[n]?.[k]||0,HistoryDealGetString:(n,k)=>deals[n]?.[k]||'',
  ExplicitReject:c=>c===10015,
  ZeroMemory:o=>{for(const k of Object.keys(o))o[k]=0;},
  FreshQuote:q=>Object.assign(q,{ask:4176.1,bid:4176,time_msc:1000000})
 });
 function record(type,volume,price,symbol,sl,tp,time,expiry,tag){
  calls.push({type,volume,price,sl,tp,tag});const ticket=next++;
  const row={[enums.ORDER_MAGIC]:560056,[enums.ORDER_TYPE]:type,[enums.ORDER_TIME_SETUP]:1000,
  [enums.ORDER_VOLUME_INITIAL]:volume,[enums.ORDER_VOLUME_CURRENT]:volume,[enums.ORDER_SYMBOL]:symbol,[enums.ORDER_COMMENT]:tag};
  if(!options.unknown&&!options.reject)orders.set(ticket,row);
  result=options.lostResult||options.unknown||options.reject?0:ticket;
  code=options.reject?10015:options.unknown?10012:10008;
 }
 function finish(ticket,filled=.02,delayed=false,state=x.ORDER_STATE_FILLED){
  const row=orders.get(ticket);orders.delete(ticket);
  history.set(ticket,{...row,[enums.ORDER_STATE]:state,[enums.ORDER_VOLUME_CURRENT]:.02-filled});
  if(filled&&!delayed)deals.push({[enums.DEAL_ORDER]:ticket,[enums.DEAL_ENTRY]:0,[enums.DEAL_MAGIC]:560056,[enums.DEAL_POSITION_ID]:900+ticket,[enums.DEAL_VOLUME]:filled,[enums.DEAL_SYMBOL]:'XAUUSD'});
 }
 x.execution={BuyLimit:(...a)=>record(x.ORDER_TYPE_BUY_LIMIT,...a),SellLimit:(...a)=>record(x.ORDER_TYPE_SELL_LIMIT,...a),
  ResultOrder:()=>result,ResultRetcode:()=>code,
  OrderDelete:t=>{calls.push({cancel:t});finish(t,options.cancelRace?.02:0,false,options.cancelRace?x.ORDER_STATE_FILLED:x.ORDER_STATE_CANCELED);},
  PositionOpen:()=>{throw Error('market trading forbidden');}};
 for(const [n,a] of [['ExitKey','id'],['LimitTag','source'],['LimitSource','i'],['LimitDoneKey','source'],['SaveLimitSlot','i'],
  ['RestoreTeacherLimits',''],['LimitPlanIndex','source'],['LimitEntryPending','comment'],['BindLimitDeals','i,expected'],
  ['ReconcileLimitSlot','i'],['LimitPrices','i'],['LimitParametersMatch','slot,plan'],['LimitTooFar','level,sign,q'],['SyncTeacherLimits','']])install(x,n,a);
 return {...base,orders,history,deals,calls,finish};
}
test('BUY plan places exactly .02 limit with protective SL/TP; awaiting order does not lock management',()=>{
 const b=broker();b.x.SyncTeacherLimits();assert.equal(b.calls.length,1);assert.equal(b.calls[0].type,5);assert.equal(b.calls[0].volume,.02);
 assert.equal(b.calls[0].price,4175);assert.equal(b.calls[0].sl,4165);assert.equal(b.calls[0].tp,4185);assert.equal(b.x.pending.kind,0);
 b.x.SyncTeacherLimits();assert.equal(b.calls.length,1);assert.equal(b.x.teacherLimits[0].state,2);
});
test('SELL plan is symmetric',()=>{
 const b=broker({plans:[{sign:-1,level:4175,origin:'short',market:false,created:990}]});
 b.x.FreshQuote=q=>Object.assign(q,{ask:4174.1,bid:4174});b.x.SyncTeacherLimits();
 assert.equal(b.calls[0].type,6);assert.equal(b.calls[0].sl,4185);assert.equal(b.calls[0].tp,4165);
});
test('crossed price or spread never converts to market/stop order',()=>{
 for(const q of [{ask:4174.1,bid:4174},{ask:4176,bid:4174}]){
  const b=broker();b.x.FreshQuote=out=>Object.assign(out,q);b.x.SyncTeacherLimits();assert.equal(b.calls.length,0);
 }
});
test('restart restores accepted pending order and never duplicates',()=>{
 const b=broker();b.x.SyncTeacherLimits();b.x.teacherLimits=Array.from({length:4},zero);
 b.x.RestoreTeacherLimits();b.x.SyncTeacherLimits();assert.equal(b.calls.length,1);assert.equal(b.orders.size,1);
});
test('unknown create result remains unresolved across restart, no duplicate',()=>{
 const b=broker({unknown:true});b.x.SyncTeacherLimits();b.x.teacherLimits=Array.from({length:4},zero);b.x.RestoreTeacherLimits();
 b.x.SyncTeacherLimits();assert.equal(b.calls.length,1);assert.equal(b.x.teacherLimits[0].state,1);
});
test('lost result finds exact broker tag after restart',()=>{
 const b=broker({lostResult:true});b.x.SyncTeacherLimits();assert.equal(b.x.teacherLimits[0].order,0);
 b.x.teacherLimits=Array.from({length:4},zero);b.x.RestoreTeacherLimits();b.x.SyncTeacherLimits();
 assert.equal(b.calls.length,1);assert.equal(b.x.teacherLimits[0].order,200);
});
test('cancellation removes only module pending order and waits confirmation',()=>{
 const b=broker();b.x.SyncTeacherLimits();b.x.aiMode='WAIT';b.x.aiPlans=[];
 b.x.SyncTeacherLimits();assert.equal(b.calls[1].cancel,200);assert.equal(b.x.teacherLimits[0].state,3);
 b.x.SyncTeacherLimits();assert.equal(b.x.teacherLimits[0].state,0);assert.equal(b.orders.size,0);
});
test('changed price cancels old order before new order is placed',()=>{
 const b=broker();b.x.SyncTeacherLimits();b.x.aiPlans[0].level=4173;
 b.x.SyncTeacherLimits();assert.equal(b.calls.length,2);assert(b.calls[1].cancel);
 b.x.SyncTeacherLimits();assert.equal(b.calls[2].price,4173);assert.equal(b.orders.size,1);
});
test('filled order is bound to real position and consumed only after Deal confirmation',()=>{
 const b=broker();b.x.SyncTeacherLimits();b.finish(200,.02,true);b.x.SyncTeacherLimits();
 assert.equal(b.x.teacherLimits[0].state,1);assert.equal(b.calls.length,1);
 b.deals.push({[b.x.DEAL_ORDER]:200,[b.x.DEAL_ENTRY]:0,[b.x.DEAL_MAGIC]:560056,[b.x.DEAL_POSITION_ID]:1100,[b.x.DEAL_VOLUME]:.02,[b.x.DEAL_SYMBOL]:'XAUUSD'});
 b.x.SyncTeacherLimits();assert.equal(b.x.teacherLimits[0].state,0);assert.equal(b.memory['exit1100.ready'],1);assert.equal(b.memory['exit1100.sl'],4165);
 b.x.SyncTeacherLimits();assert.equal(b.calls.length,1);
});
test('cancel-fill race and partially-filled canceled order preserve real fill and do not rehang',()=>{
 for(const partial of [false,true]){
  const b=broker({cancelRace:!partial});b.x.SyncTeacherLimits();
  if(partial)b.finish(200,.01,false,b.x.ORDER_STATE_CANCELED);
  else {b.x.aiMode='WAIT';b.x.SyncTeacherLimits();}
  b.x.aiMode='SETUP';b.x.SyncTeacherLimits();assert.equal(b.x.teacherLimits[0].state,0);
  assert.equal(b.memory['exit1100.ready'],1);b.x.SyncTeacherLimits();
  assert.equal(b.calls.filter(c=>c.volume).length,1);
 }
});
test('explicit rejection has a five-second retry cooldown',()=>{
 const b=broker({reject:true});b.x.SyncTeacherLimits();b.x.SyncTeacherLimits();assert.equal(b.calls.length,1);
 b.x.TimeCurrent=()=>1005;b.x.SyncTeacherLimits();assert.equal(b.calls.length,2);
});
test('derived range plans and inactive sources cannot create pending order',()=>{
 for(const mode of ['derived','offline']){
  const b=broker();if(mode==='derived')b.x.aiPlans[0].derived=true;else b.x.aiReady=false;
  b.x.SyncTeacherLimits();assert.equal(b.calls.length,0);
 }
});
test('pending orders plus positions respect the existing capacity',()=>{
 const b=broker({plans:[{sign:1,level:4175,origin:'a',created:990},{sign:1,level:4173,origin:'b',created:990}]});
 b.x.OwnCount=()=>2;b.x.SyncTeacherLimits();b.x.SyncTeacherLimits();assert.equal(b.calls.length,1);
});
test('explicit teacher SL and first/final TP survive fill',()=>{
 const b=broker({plans:[{sign:1,level:4175,origin:'a',created:990,sl:4168,first:4180,tp:4190,breakeven:4178}]});
 b.x.SyncTeacherLimits();assert.equal(b.calls[0].sl,4168);assert.equal(b.calls[0].tp,4190);
 b.finish(200);b.x.SyncTeacherLimits();assert.equal(b.memory['exit1100.first'],4180);assert.equal(b.memory['exit1100.be'],4178);
});
test('interrupted persistence sends no order; restored uncertain state blocks',()=>{
 const b=broker();b.x.Store=()=>false;b.x.SyncTeacherLimits();assert.equal(b.calls.length,0);
 b.memory['tl0.state']=-1;b.x.RestoreTeacherLimits();assert.equal(b.x.stateOK,false);
});
test('event entry graph calls limit sync only; legacy signal methods cannot execute',()=>{
 const timer=body('OnTimer'),tick=body('OnTick');
 assert(timer.includes('SyncTeacherLimits()'));for(const x of ['AIMarketSignal','MemberFollowSignal','Signal(candidate)','Open('])assert(!timer.includes(x));
 assert(!tick.includes('Open('));assert(!tick.includes('AIMarketSignal'));
});
test('distance boundary uses Ask for BUY and Bid for SELL; configurable ceiling',()=>{
 for(const sign of [1,-1])for(const gap of [49.99,50,50.01]){
  const b=broker({plans:[{sign,level:4175,origin:'distance',created:990}]});
  b.x.FreshQuote=q=>Object.assign(q,sign>0?{ask:4175+gap,bid:4174.9+gap}:{bid:4175-gap,ask:4175.1-gap});
  b.x.SyncTeacherLimits();assert.equal(b.calls.length,gap<=50?1:0);
  if(gap>50)assert.match(b.x.aiPlans[0].status,/暂不挂单/);
 }
 const b=broker();b.x.挂单最大离价=1;b.x.SyncTeacherLimits();assert.equal(b.calls.length,0);
});
test('far pending is canceled, reconciled, and may rehang only after returning near',()=>{
 for(const sign of [1,-1]){
  const b=broker({plans:[{sign,level:4175,origin:'return',created:990}]});
  const near=q=>Object.assign(q,sign>0?{ask:4176.1,bid:4176}:{ask:4174.1,bid:4174});
  b.x.FreshQuote=near;b.x.SyncTeacherLimits();
  b.x.FreshQuote=q=>Object.assign(q,sign>0?{ask:4225.1,bid:4225}:{ask:4125,bid:4124.9});
  b.x.SyncTeacherLimits();assert.equal(b.calls[1].cancel,200);assert.equal(b.x.teacherLimits[0].state,3);
  b.x.SyncTeacherLimits();assert.equal(b.calls.length,2);assert.equal(b.x.teacherLimits[0].state,0);
  b.x.FreshQuote=near;b.x.SyncTeacherLimits();assert.equal(b.calls.length,3);
 }
});
test('stale quote cannot cause distance cancellation or new orders',()=>{
 const b=broker();b.x.SyncTeacherLimits();
 b.x.FreshQuote=q=>{Object.assign(q,{ask:4300,bid:4299.9});return false;};
 b.x.SyncTeacherLimits();assert.equal(b.calls.length,1);assert.equal(b.orders.size,1);
});
test('submit-time quote crossing distance ceiling prevents new request',()=>{
 const b=broker();let n=0;
 b.x.FreshQuote=q=>Object.assign(q,++n===1?{ask:4176.1,bid:4176}:{ask:4225.1,bid:4225});
 b.x.SyncTeacherLimits();assert.equal(b.calls.length,0);
});
test('distance cancel racing a fill preserves position exit binding and consumed plan',()=>{
 const b=broker({cancelRace:true});b.x.SyncTeacherLimits();
 b.x.FreshQuote=q=>Object.assign(q,{ask:4225.1,bid:4225});b.x.SyncTeacherLimits();b.x.SyncTeacherLimits();
 assert.equal(b.memory['exit1100.ready'],1);assert.equal(b.calls.filter(c=>c.volume).length,1);
});
console.log(checks+' teacher-only limit checks passed');
