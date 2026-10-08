// Offline boundary tests: execute extracted MQL expressions with deterministic broker mocks.
// Does not start MT5, send orders, or claim to test MQL event/terminal semantics.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const source = ['EA_交易托管系统_v1.56.mq5', 'Include/Trading/TeacherAuto.mqh']
  .map(file => fs.readFileSync(path.join(root, file), 'utf8')).join('\n');
function body(name) {
  const definition = source.search(new RegExp(`^(?:bool|void|double|datetime|int|ulong|string) ${name}\\(`, 'm'));
  assert(definition >= 0, name);
  const start = source.indexOf('{', definition);
  assert(start >= 0, name);
  let depth = 1, end = start + 1;
  for (; depth; end++) { if (source[end] === '{') depth++; if (source[end] === '}') depth--; }
  return source.slice(start + 1, end - 1);
}
function translate(code) {
  return code.replace(/\(ENUM_POSITION_TYPE\)/g, '')
    .replace(/\((?:double|int|long|ulong|datetime)\)/g, '')
    .replace(/MqlRates (\w+)\[\];/g, 'let $1=[];')
    .replace(/\b(?:double|int|bool|datetime|long|ulong|string|ENUM_POSITION_TYPE|ENUM_ORDER_TYPE)\s+/g, 'let ');
}
const ArraySize = a => a.length;
const PeriodSeconds = () => 300;
const PERIOD_M5 = 5, PERIOD_M1 = 1;
const trigger = new Function('bar', 'previous', 'level', 'directionSign', 'nearDistance', 'penetration', translate(body('TeacherActiveM1Trigger')));
const breakout = new Function('m5', 'level', 'sign', 'buffer', 'ArraySize', 'PeriodSeconds', 'PERIOD_M5', translate(body('TeacherActiveBreakout')));
let checks = 0;
function test(name, run) { run(); checks++; console.log(`PASS ${name}`); }
const buyBar = { open: 100.1, close: 100.4, low: 99.9, high: 100.5 };
test('buy pullback accepts small wick (no duplicate M5 requirement)', () => assert(trigger(buyBar, {close:100.5}, 100, 1, .25, .15)));
test('reject deep penetration', () => assert(!trigger({...buyBar,low:99.8}, {close:100.5},100,1,.25,.15)));
test('reject not reclaimed', () => assert(!trigger({...buyBar,close:99.95}, {close:100.5},100,1,.25,.15)));
test('reject approached from wrong side', () => assert(!trigger(buyBar,{close:99.5},100,1,.25,.15)));
test('sell symmetry', () => assert(trigger({open:99.9,close:99.6,high:100.1,low:99.5},{close:99.5},100,-1,.25,.15)));
const bars = [ {time:900,close:100.4}, {time:600,close:100.3}, {time:300,close:99.9}, {time:0,close:99.8} ];
const detect = (b,sign=1) => breakout(b,100,sign,.15,ArraySize,PeriodSeconds,PERIOD_M5);
test('breakout timestamp is close, not open', () => assert.equal(detect(bars),900));
test('failed breakout invalidates retest', () => assert.equal(detect([{time:900,close:99.7},...bars.slice(1)]),0));
test('old sustained trend is not fresh breakout', () => assert.equal(detect(bars.map(b=>({...b,close:100.4}))),0));
test('sell breakout symmetry', () => assert.equal(detect(bars.map(b=>({...b,close:200-b.close})),-1),900));

// Use the actual sizing/SL/TP body; only MQL out-arguments are adapted to JS assignments.
let orderBody = translate(body('TeacherActiveBuildOrder'))
  .replace(/OrderCalcProfit\(([^\n]+?),\s*(loss|profit|slippage)\)/g, '($2=CalcProfit($1),true)')
  .replace(/OrderCalcMargin\(([^()\n]+),\s*(margin)\)/g, '($2=CalcMargin($1),true)');
function build(options={}) {
  const direction = options.direction ?? 0, level=100, atr=1, mode=options.mode ?? 1;
  let sl=0,tp=0,volume=0;
  const POSITION_TYPE_BUY=0, ORDER_TYPE_BUY=0, ORDER_TYPE_SELL=1;
  const SYMBOL_BID='bid',SYMBOL_ASK='ask',SYMBOL_TRADE_STOPS_LEVEL='stops',SYMBOL_TRADE_FREEZE_LEVEL='freeze';
  const SYMBOL_VOLUME_MIN='min',SYMBOL_VOLUME_MAX='max',SYMBOL_VOLUME_STEP='step';
  const ACCOUNT_EQUITY='equity',ACCOUNT_MARGIN_FREE='free';
  const _Symbol='TEST',_Point=.01;
  const props={bid:direction===0?100.1:99.8,ask:direction===0?100.2:99.9,min:.01,max:10,step:.01,stops:0,freeze:0,...options.props};
  const SymbolInfoDouble=(_,key)=>props[key],SymbolInfoInteger=SymbolInfoDouble;
  const AccountInfoDouble=key=>key==='equity'?(options.equity??1000):(options.free??100000);
  const 老师自动追价上限M5ATR=.50,老师自动止损缓冲M5ATR=.15,老师自动最低净盈亏比=1.5;
  const 老师点位自动短线固定手数=.01;
  const TeacherAutoStrictFixedVolume=()=>eval(`(()=>{${translate(body('TeacherAutoStrictFixedVolume'))}})()`);
  const 老师自动每手往返费用=options.fees??0,老师自动顺势风险百分比=.35,老师自动逆势风险百分比=.175;
  const 缓存老师点位=options.levels??[100,105,95];
  const teacherActiveDayHigh=110,teacherActiveDayLow=90,teacherActiveFiveHigh=115,teacherActiveFiveLow=85;
  const MathMax=Math.max,MathMin=Math.min,MathAbs=Math.abs,MathFloor=Math.floor,MathRound=Math.round;
  const NormalizeDouble=(v,n)=>Number(v.toFixed(n)),ShortTeacherTickSize=()=>.01;
  const TeacherAutoAlignTradePrice=(v,type,isSL)=>Number((type===0?Math.floor(v*100+1e-9):Math.ceil(v*100-1e-9))/100);
  const SLTPValid=(type,s,t)=>type===0?s<props.bid&&t>props.ask:s>props.ask&&t<props.bid;
  const CopyRates=(_,tf,shift,count,out)=>{ assert.equal(shift,1); out.push({low:99.9,high:100.1}); return 1; };
  const CalcProfit=(type,sym,v,entry,exit)=>(type===0?1:-1)*(exit-entry)*100*v;
  const CalcMargin=(type,sym,v,entry)=>v*100;
  const accepted=eval(`(()=>{${orderBody}})()`);
  return {accepted,sl,tp,volume,props};
}
test('buy order uses fixed 0.01 volume',()=>{const r=build();assert(r.accepted);assert(r.sl<r.props.bid);assert(r.tp>r.props.ask);assert.equal(r.volume,.01);});
test('sell order symmetry',()=>{const r=build({direction:1});assert(r.accepted);assert(r.sl>r.props.ask);assert(r.tp<r.props.bid);});
test('countertrend also uses fixed volume',()=>assert.equal(build({mode:3}).volume,.01));
test('minimum volume never rounded up',()=>assert(!build({props:{min:.1}}).accepted));
test('near obstacle rejects inadequate reward',()=>assert(!build({levels:[100,100.6,95]}).accepted));
test('commission affects net reward gate',()=>assert(!build({fees:100}).accepted));
test('insufficient margin rejects',()=>assert(!build({free:0}).accepted));
test('chasing beyond entry zone rejects',()=>assert(!build({props:{bid:100.5,ask:100.6}}).accepted));
test('larger broker stop never increases fixed volume',()=>{const r=build({props:{stops:60}});assert(r.accepted);assert(r.props.bid-r.sl>=.60);assert.equal(r.volume,.01);});
const riskBody = translate(body('TeacherActiveRefreshRisk'))
  .replace(/\((?:datetime|ulong)\)/g,'')
  .replace(/\b(?:ulong|long)\s+/g,'let ')
  .replace(/let (\w+)\[\];/g,'let $1=[];');
function riskCheck(deals, options={}) {
  const day=86400,now=day+1000;
  const 老师自动使用积极策略=true,启用老师点位自动反转短线=true;
  const 老师自动日内亏损上限百分比=1.5,老师自动连续止损上限=3,老师自动止损冷却秒=60;
  const MAX_TEACHER_MARKER_LEVELS=20,ACCOUNT_EQUITY=0,SYMBOL_VOLUME_STEP=0;
  const DEAL_ENTRY='entry',DEAL_SYMBOL='symbol',DEAL_POSITION_ID='id',DEAL_MAGIC='magic';
  const DEAL_VOLUME='volume',DEAL_TIME='time',DEAL_REASON='reason';
  const DEAL_PROFIT='profit',DEAL_COMMISSION='commission',DEAL_SWAP='swap',DEAL_FEE='fee';
  const DEAL_ENTRY_IN=0,DEAL_ENTRY_OUT=1,DEAL_ENTRY_OUT_BY=2,DEAL_ENTRY_INOUT=3,DEAL_REASON_SL=1;
  const TEACHER_AUTO_SHORT_MAGIC=99,_Symbol='TEST';
  let teacherActiveHistoryDirty=true,teacherActiveHistoryReady=false,teacherActiveHistoryTime=0;
  let teacherActiveLatestDeal=options.latest??0,teacherActiveLastStop=0;
  const saved={AD:options.previousDay??day,AE:1000,AH:options.halted??0};
  const TeacherAutoStateRead=k=>saved[k]??0,TeacherAutoStateKey=k=>k;
  const GlobalVariableSet=(k,v)=>saved[k]=v,GlobalVariableDel=k=>delete saved[k];
  const TeacherActiveHalt=()=>saved.AH=1;
  const TimeCurrent=()=>now,TeacherActiveDay=()=>day;
  const AccountInfoDouble=()=>options.equity??1000,SymbolInfoDouble=()=>.01;
  const IntegerToString=String,MathMax=Math.max,ArrayResize=(a,n)=>a.length=n;
  let selected=[];
  const HistorySelect=(from,to)=>{selected=deals.filter(d=>d.time>=from&&d.time<=to);return true;};
  const HistoryDealSelect=t=>deals.some(d=>d.ticket===t);
  const HistorySelectByPosition=id=>{selected=deals.filter(d=>d.id===id);return true;};
  const HistoryDealsTotal=()=>selected.length,HistoryDealGetTicket=i=>selected[i].ticket;
  const HistoryDealGetInteger=(t,k)=>deals.find(d=>d.ticket===t)[k]??0;
  const HistoryDealGetDouble=HistoryDealGetInteger,HistoryDealGetString=HistoryDealGetInteger;
  const FindOpenPositionTicketByIdentifier=id=>(options.live??[]).includes(id)?1:0;
  eval(`(()=>{${riskBody}})()`);
  return {saved,ready:teacherActiveHistoryReady,lastStop:teacherActiveLastStop};
}
function trade(id,profit=-2,reason=1,magic=99,time=86700+id*100) {
  return [
    {ticket:id*10,id,entry:0,magic,symbol:'TEST',volume:.01,time:time-10,profit:0},
    {ticket:id*10+1,id,entry:1,magic:0,symbol:'TEST',volume:.01,time,profit,reason}
  ];
}
test('three full stopouts halt even with exit Magic zero',()=>assert.equal(riskCheck([1,2,3].flatMap(i=>trade(i))).saved.AH,1));
test('profitable lifecycle closed by SL breaks loss streak',()=>assert.equal(riskCheck([...trade(1),...trade(2,5),...trade(3)]).saved.AH,0));
test('partial exit is not final loss',()=>assert.equal(riskCheck([1,2,3].flatMap(i=>trade(i)),{live:[3]}).saved.AH,0));
test('unrelated manual losses excluded',()=>assert.equal(riskCheck([1,2,3].flatMap(i=>trade(i,-2,1,0))).saved.AH,0));
test('equity cap latches',()=>assert.equal(riskCheck([],{equity:984}).saved.AH,1));
test('existing halt survives recovered equity',()=>assert.equal(riskCheck([],{halted:1,equity:1100}).saved.AH,1));
test('new day resets halt and baseline',()=>{const r=riskCheck([],{previousDay:0,halted:1,equity:984});assert.equal(r.saved.AH,0);assert.equal(r.saved.AE,984);});
test('unreadable latest deal prevents new entry',()=>assert(!riskCheck([],{latest:999}).ready));
test('prior-day stop retained for cross-midnight cooldown',()=>{const r=riskCheck(trade(1,-2,1,99,86390));assert.equal(r.lastStop,86390);assert.equal(r.saved.AH,0);});
function manage(options={}) {
  const ticket=1,stateIdx=0,type=0,openPrice=100,profitPrice=options.profit??1.2;
  const states=[{shortRiskReady:true,partialRequestPending:false,pendingAction:0,shortInitialRisk:1,initialVolume:.10,partialTPStage:0,...options.state}];
  const POSITION_TYPE_BUY=0,POSITION_VOLUME=0,POSITION_SL=1,POSITION_TP=2,SYMBOL_VOLUME_MIN=0;
  const 待确认动作_无=0,退出意图_紧急风控=1,退出意图_分批止盈=2,SL来源_其他=1,TP来源_无=0;
  const _Symbol='TEST',短线单绝对最大风险R=1.5,老师自动止损缓冲M5ATR=.15;
  const 老师自动贪婪首段R=2.5,老师自动贪婪保护R=1.5;
  const currentTickHasNewM1Bar=options.newBar??true;
  const PositionSelectByTicket=()=>true,PositionGetDouble=k=>k===0?(options.volume??.1):k===1?(options.sl??99):103;
  const SymbolInfoDouble=()=>.01,MathMax=Math.max,MathMin=Math.min;
  const ShortStageFilledVolume=()=>options.filled??0,NormalizeVolumeDown=v=>Math.floor(v*100+1e-8)/100;
  const CopyRates=(_,tf,shift,count,out)=>{assert.equal(shift,1);for(let i=0;i<count;i++)out.push({low:options.structure??101.5,high:102.5});return count;};
  const ArraySetAsSeries=()=>{},CurrentSpreadPrice=()=>.1;
  const TeacherAutoAlignTradePrice=v=>Math.floor(v*100+1e-8)/100;
  const MoreProtective=(t,c,s)=>c>s,SLTPValid=()=>true;
  const actions=[];
  const SubmitManagedFullClose=(...args)=>actions.push(['full',...args]);
  const SubmitManagedPartialClose=(...args)=>actions.push(['partial',...args]);
  const SubmitManagedPositionModify=(...args)=>actions.push(['modify',...args]);
  const code=translate(body('ManageTeacherActivePosition')).replace('TeacherActiveContext(atr)','(atr=1,true)');
  eval(`(()=>{${code}})()`);
  return actions;
}
test('unconfirmed initial risk cannot advance exits',()=>assert.equal(manage({profit:2,state:{shortRiskReady:false}}).length,0));
test('pending partial prevents duplicate request',()=>assert.equal(manage({profit:2,state:{partialRequestPending:true}}).length,0));
test('2.5R requests half without marking completed',()=>{const a=manage({profit:2.5});assert.equal(a[0][0],'partial');assert.equal(a[0][3],.05);});
test('partial remainder subtracts confirmed fills',()=>assert.equal(manage({profit:2.5,filled:.02})[0][3],.03));
test('minimum-lot position trails instead of closing',()=>{const a=manage({profit:2.5,volume:.01,state:{initialVolume:.01}});assert.equal(a[0][0],'modify');});
test('weak structure cannot force breakeven',()=>assert.equal(manage({structure:99.5}).length,0));
test('confirmed partial switches to wider structural trailing',()=>assert.equal(manage({profit:2,state:{partialTPStage:1}})[0][3],101.25));
test('trailing never loosens current stop',()=>assert.equal(manage({profit:2,sl:101.6,state:{partialTPStage:1}}).length,0));
function portfolio(options={}) {
  const _Symbol='TEST',TEACHER_AUTO_SHORT_MAGIC=99,手机标记挂单Magic=88;
  const 老师自动同时最大持仓=options.limit??5,老师自动使用积极策略=true;
  const ACCOUNT_MARGIN_MODE=0,ACCOUNT_MARGIN_MODE_RETAIL_HEDGING=2;
  const POSITION_SYMBOL='symbol',POSITION_MAGIC='magic',POSITION_IDENTIFIER='id';
  const POSITION_COMMENT='comment',POSITION_TYPE='type',POSITION_TIME='time',POSITION_PRICE_OPEN='open';
  const ORDER_SYMBOL='symbol',ORDER_MAGIC='magic',ORDER_COMMENT='comment';
  const DEAL_POSITION_ID='id';
  const teacherAutoEntryState={pending:false,pendingMode:1,pendingDirection:0,pendingRequestTime:1000,pendingSignalBarTime:960,pendingDeal:0,lastLevel:100,...options.pending};
  const positions=options.positions??[],orders=options.orders??[];
  let selected=null,orderSelected=null;
  const PositionsTotal=()=>positions.length,OrdersTotal=()=>orders.length;
  const PositionGetTicket=i=>{selected=positions[i];return selected.ticket;};
  const PositionSelectByTicket=t=>{selected=positions.find(p=>p.ticket===t);return !!selected;};
  const PositionGetString=k=>selected[k],PositionGetInteger=k=>selected[k],PositionGetDouble=k=>selected[k]??0;
  const OrderGetTicket=i=>{orderSelected=orders[i];return orderSelected.ticket;};
  const OrderGetString=k=>orderSelected[k],OrderGetInteger=k=>orderSelected[k];
  const AccountInfoInteger=()=>options.hedging===false?0:2;
  const MathMin=Math.min,IntegerToString=String,StringFind=(s,q)=>s.indexOf(q);
  const HistoryDealSelect=d=>!!options.deal;
  const HistoryDealGetInteger=(d,k)=>options.deal[k];
  const TeacherAutoPendingComment=()=>eval(`(()=>{${translate(body('TeacherAutoPendingComment'))}})()`);
  const TeacherActiveLiveCount=()=>eval(`(()=>{${translate(body('TeacherActiveLiveCount'))}})()`);
  const TeacherAutoFindPendingPosition=()=>eval(`(()=>{${translate(body('TeacherAutoFindPendingPosition'))}})()`);
  const TeacherAutoPendingOrderStillActive=()=>orders.length>0;
  const TeacherActiveRecordTouch=()=>{},TeacherAutoStateSave=()=>{},PrintFormat=()=>{};
  const TeacherAutoClearPendingStateFields=()=>{teacherAutoEntryState.pending=false;teacherAutoEntryState.pendingMode=0;};
  if(options.confirm) {
    eval(`(()=>{${translate(body('TeacherAutoConfirmLivePosition'))}})()`);
    return teacherAutoEntryState;
  }
  if(options.find) return TeacherAutoFindPendingPosition();
  return eval(`(()=>{${translate(body('TeacherActiveCanOpen'))}})()`);
}
const pos=(ticket,type=0,extra={})=>({ticket,id:ticket,magic:99,symbol:'TEST',comment:'TEACHER_ACTIVE_1_900',type,time:940,open:100,...extra});
test('four positions allow fifth request',()=>assert(portfolio({positions:[1,2,3,4].map(t=>pos(t))})));
test('five positions block sixth',()=>assert(!portfolio({positions:[1,2,3,4,5].map(t=>pos(t))})));
test('mixed long/short count shares same five-slot cap',()=>assert(!portfolio({positions:[1,2,3,4,5].map(t=>pos(t,t%2))})));
test('pending fifth occupies capacity before visible fill',()=>assert(!portfolio({positions:[1,2,3,4].map(t=>pos(t)),pending:{pending:true}})));
test('server residual order prevents next request',()=>assert(!portfolio({positions:[pos(1)],orders:[{ticket:9,magic:99,symbol:'TEST'}]})));
test('netting never opens opposing/multiple teacher positions',()=>assert(!portfolio({hedging:false})));
test('manual position remains isolated',()=>assert(!portfolio({positions:[pos(1,0,{magic:0})]})));
test('marker order remains outside trade quota',()=>assert(portfolio({orders:[{ticket:9,magic:88,symbol:'TEST',comment:'SMA_MARK_K01'}]})));
test('other symbols do not consume current-symbol slots',()=>assert(portfolio({positions:[1,2,3,4,5].map(t=>pos(t,0,{symbol:'OTHER'}))})));
test('old open position cannot confirm newer pending',()=>assert.equal(portfolio({find:true,pending:{pending:true},positions:[pos(1)]}),0));
test('nonce matches exact new position',()=>assert.equal(portfolio({find:true,pending:{pending:true},positions:[pos(1),pos(2,0,{comment:'TEACHER_ACTIVE_1_960',time:1000})]}),2));
test('deal position id binds even if broker alters comment',()=>assert.equal(portfolio({find:true,pending:{pending:true,pendingDeal:55},deal:{id:2},positions:[pos(1),pos(2,0,{comment:'changed'})]}),2));
test('matching partial fill does not clear pending with residual order',()=>assert(portfolio({confirm:true,pending:{pending:true},positions:[pos(2,0,{comment:'TEACHER_ACTIVE_1_960'})],orders:[{ticket:3}]}).pending));
test('exact fill clears only its pending after order terminal',()=>assert(!portfolio({confirm:true,pending:{pending:true},positions:[pos(2,0,{comment:'TEACHER_ACTIVE_1_960'})]}).pending));

function rangeCheck(m5) {
  let low=0,high=0;
  const atr=1,老师自动允许震荡双向=true,MathMin=Math.min,MathMax=Math.max,MathAbs=Math.abs;
  return eval(`(()=>{${translate(body('TeacherActiveRange'))}})()`);
}
const rangeBars=Array.from({length:13},(_,i)=>({low:99,high:101,close:i%2?99.6:100.4}));
test('oscillating bounded M5 range recognized',()=>assert(rangeCheck(rangeBars)));
test('directional sequence not classified as range',()=>assert(!rangeCheck(rangeBars.map((b,i)=>({...b,close:100-i*.1})))));
test('closed breakout disables range fading',()=>assert(!rangeCheck([{...rangeBars[0],close:101.2},...rangeBars.slice(1)])));
test('range detection needs full closed-bar lookback',()=>assert(!rangeCheck(rangeBars.slice(0,12))));
test('daily count and first-retest gates removed from candidate',()=>{const b=body('TeacherActiveFindCandidate');assert(!b.includes('"AC"'));assert(!b.includes('"AB"'));assert(b.includes('candidateMode=4'));});
test('new request checks capacity again before send',()=>assert(body('SubmitTeacherAutoReversal').includes('activeMode>0 && !TeacherActiveCanOpen()')));
function settled(deals,filled=true,live=false) {
  const order=7,_Symbol='TEST',SYMBOL_VOLUME_STEP=0;
  const DEAL_ORDER='order',DEAL_ENTRY='entry',DEAL_POSITION_ID='id',DEAL_VOLUME='volume';
  const DEAL_ENTRY_IN=0,DEAL_ENTRY_OUT=1,DEAL_ENTRY_OUT_BY=2,DEAL_ENTRY_INOUT=3;
  const teacherAutoEntryState={};
  const HistoryDealsTotal=()=>deals.length,HistoryDealGetTicket=i=>i+1;
  const HistoryDealGetInteger=(t,k)=>deals[t-1][k],HistoryDealGetDouble=HistoryDealGetInteger;
  const TeacherAutoStateSave=()=>{},TeacherActiveRecordTouch=()=>{};
  const FindOpenPositionTicketByIdentifier=()=>live?123:0;
  const HistorySelectByPosition=()=>true,SymbolInfoDouble=()=>.01;
  return eval(`(()=>{${translate(body('TeacherAutoFinalOrderReconciled'))}})()`);
}
const filledEntry={order:7,entry:0,id:123,volume:.01};
test('FILLED order without Deal keeps pending slot',()=>assert(!settled([])));
test('canceled unfilled order releases pending slot',()=>assert(settled([],false)));
test('entry with missing position/exit cannot release slot',()=>assert(!settled([filledEntry])));
test('visible position routes back to precise live confirmation',()=>assert(!settled([filledEntry],true,true)));
test('fast open-close releases only after complete exit volume',()=>assert(settled([filledEntry,{order:8,entry:1,id:123,volume:.01}])));
console.log(`${checks} offline checks passed; terminal execution/backtesting not performed.`);
