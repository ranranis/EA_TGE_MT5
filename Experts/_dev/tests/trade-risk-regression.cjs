// Executes extracted MQL bodies with deterministic terminal mocks. Not an MT5/backtest claim.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..');
const read=f=>fs.readFileSync(path.join(root,f),'utf8');
const main=read('EA_交易托管系统_v1.56.mq5');
const store=read('Include/Persistence/StateStore.mqh');
const journal=read('Include/Journal/TradeJournal.mqh');
const summary=read('Include/Journal/TradeSummary.mqh');
const marker=read('Include/Trading/MobileMarkerSafety.mqh');
const source=[main,store,journal,summary,marker].join('\n');
function body(name) {
  const re=new RegExp(`^(?:bool|void|int|double|string|ulong) ${name}\\([^;{}]*\\)\\s*\\{`,'m');
  const match=re.exec(source); assert(match,name);
  const at=source.indexOf('{',match.index);let end=at+1,depth=1;
  // Targeted bodies have no braces embedded in string literals.
  for(;depth;end++){if(source[end]==='{')depth++;if(source[end]==='}')depth--;}
  return source.slice(at+1,end-1);
}
function js(code) {
  return code.replace(/PerformanceScope \w+\([^;]+\);/g,'')
    .replace(/TicketState st = states\[stateIdx\];/g,'let st=structuredClone(states[stateIdx]);')
    .replace('(double)(uint)(st.teacherPlanSignature & 0xFFFFFFFF)','Number(BigInt(st.teacherPlanSignature)&0xFFFFFFFFn)')
    .replace('(double)(uint)(st.teacherPlanSignature >> 32)','Number(BigInt(st.teacherPlanSignature)>>32n)')
    .replace('((ulong)(uint)hi<<32)|(ulong)(uint)lo','(BigInt(hi)<<32n)|BigInt(lo)')
    .replace(/static ulong lastCheckMs=0;/,'if(typeof lastCheckMs==="undefined") lastCheckMs=0;')
    .replace(/\b(?:string|ulong|int|double) (\w+)\[\]\s*=\s*\{([^}]+)\};/g,'let $1=[$2];')
    .replace(/\b(?:string|ulong|int|double) (\w+)\[\];/g,'let $1=[];')
    .replace(/\((?:ENUM_\w+|double|int|uint|ulong|datetime|string|long)\)/g,'')
    .replace(/\b(?:ENUM_\w+|double|int|uint|ulong|datetime|string|long|bool)\s+(?=[\p{L}_])/gu,'let ');
}
const stateBlock=main.slice(main.indexOf('struct TicketState'),main.indexOf('void UpdateAllFloatingPnlTimings();'));
function state(overrides={}) {
  const s=Object.fromEntries([...stateBlock.matchAll(/\b(?:double|int|uint|ulong|datetime|long|bool)\s+(\w+)\s*;/g)].map(m=>[m[1],0]));
  return {...s,ticket:101,positionIdentifier:101,positionOpenTime:100,positionDirection:0,
    adoptedTemplate:2,shortStateManaged:true,initialVolume:1,lastKnownVolume:1,lastKnownOpenPrice:100,
    stateVersion:3,lastSavedVersion:2,stateDirty:true,...overrides};
}
function env() {
  const e={structuredClone,Math,Number,BigInt,now:1000,ms:100000,error:0,gv:new Map(),failKey:'',
    states:[state()],_Point:.01,_Digits:2,_Symbol:'TEST',login:77,connected:true,
    calls:[],selected:[],deals:new Map(),orders:new Map(),historyOrders:new Map(),live:new Set(),
    selectedOrder:0,positionSL:95,positionTP:0,fileRows:[],row:0,column:0,lastLineEnd:false,
    failWrite:false,failFlush:false,flushes:0,writes:0,processed:new Set(),deleteAccept:true};
  for(const m of source.matchAll(/(?:POSITION_|DEAL_|ORDER_STATE_|ORDER_|SYMBOL_|ACCOUNT_|TERMINAL_|SL来源_|TP来源_|待确认动作_|生命周期_|保护阶段_|浮动状态_)[\p{L}\p{N}_]+/gu))
    if(!(m[0] in e))e[m[0]]=m[0];
  Object.assign(e,{POSITION_TYPE_BUY:0,POSITION_TYPE_SELL:1,配置_黄金稳健托管:2,配置_黄金超短快保:1,
    老师点位辅助_仅TP:0,老师点位辅助_TP与突破保护SL:1,手机标记挂单Magic:900,
    启用交易生命周期记录:true,交易生命周期记录原始Deal:true,交易生命周期启动时导入终端历史:true,
    短线单分批最小间隔秒:20,短线单平仓确认超时秒数:5,短线单SLTP确认超时秒数:5,短线单平仓重试冷却秒数:1,
    TIME_DATE:1,TIME_SECONDS:2,INVALID_HANDLE:-1,SEEK_SET:0,SEEK_END:2});
  Object.assign(e,{
    ArraySize:a=>a.length,ArrayResize:(a,n)=>{a.length=n;return n;},ArrayInitialize:(a,v)=>a.fill(v),
    MathMax:Math.max,MathMin:Math.min,MathAbs:Math.abs,MathFloor:Math.floor,MathIsValidNumber:Number.isFinite,
    TimeCurrent:()=>e.now,GetTickCount64:()=>e.ms,ResetLastError:()=>{e.error=0;},GetLastError:()=>e.error,
    StringLen:s=>s.length,StringFind:(s,p)=>s.indexOf(p),StringSubstr:(s,start,count)=>s.slice(start,count===undefined?undefined:start+count),
    StringToInteger:s=>BigInt(s)>BigInt(Number.MAX_SAFE_INTEGER)?BigInt(s):Number(s),
    StringFormat:(fmt,...args)=>{let i=0;return fmt.replace(/%(?:I64)?[dus]|%\.\d+f/g,()=>String(args[i++]));},
    DoubleToString:(v,n)=>Number(v).toFixed(n),TimeToString:v=>String(v),
    AccountInfoInteger:()=>e.login,TerminalInfoInteger:()=>e.connected?1:0,
    SymbolInfoDouble:()=>.01,SymbolInfoInteger:()=>0,
    GlobalVariableCheck:k=>e.gv.has(k),GlobalVariableGet:k=>e.gv.get(k)??0,
    GlobalVariableSet:(k,v)=>{if(k===e.failKey)return 0;e.gv.set(k,v);return e.now;},
    GlobalVariableDel:k=>e.gv.delete(k),GlobalVariablesTotal:()=>e.gv.size,GlobalVariableName:i=>[...e.gv.keys()][i],
    GlobalVariablesFlush:()=>{e.flushes++;},
    PrintFormat:()=>{},PrintRateLimited:()=>{},
    PositionSelectByTicket:t=>e.live.has(t),FindOpenPositionTicketByIdentifier:id=>e.live.has(id)?id:0,
    PositionGetDouble:p=>p===e.POSITION_SL?e.positionSL:p===e.POSITION_TP?e.positionTP:p===e.POSITION_PRICE_OPEN?(e.currentOpen??100):(e.currentVolume??1),
    PositionGetInteger:p=>p===e.POSITION_IDENTIFIER?101:0,
    HistorySelect:()=>{e.selected=[...e.deals.keys()];return true;},
    HistorySelectByPosition:id=>{e.selected=[...e.deals].filter(([,d])=>d.id===id).map(([t])=>t);return !e.historyFail;},
    HistoryDealSelect:t=>{if(e.unreadable===t)return false;e.selected=e.deals.has(t)?[t]:[];return e.selected.length>0;},
    HistoryDealsTotal:()=>e.selected.length,HistoryDealGetTicket:i=>e.selected[i]??0,
    HistoryDealGetInteger:(t,p)=>{const d=e.deals.get(t)||{};return p===e.DEAL_POSITION_ID?d.id:p===e.DEAL_ENTRY?d.entry:p===e.DEAL_TIME?d.time:p===e.DEAL_REASON?0:0;},
    HistoryDealGetDouble:(t,p)=>{const d=e.deals.get(t)||{};return p===e.DEAL_VOLUME?d.volume:p===e.DEAL_PRICE?100:p===e.DEAL_PROFIT?(d.profit||0):0;},
    HistoryDealGetString:()=>e._Symbol,
    OrderSelect:t=>{e.selectedOrder=t;return e.orders.has(t);},
    HistoryOrderSelect:t=>e.historyOrders.has(t),
    HistoryOrderGetInteger:(t,p)=>{const o=e.historyOrders.get(t)||{};return p===e.ORDER_MAGIC?o.magic:p===e.ORDER_STATE?o.status:o.id;},
    HistoryOrderGetDouble:(t,p)=>{const o=e.historyOrders.get(t)||{};return p===e.ORDER_VOLUME_INITIAL?o.initial:o.remaining;},
    HistoryOrderGetString:(t,p)=>{const o=e.historyOrders.get(t)||{};return p===e.ORDER_SYMBOL?o.symbol:o.comment;},
    IsMobileMarkerTag:s=>s.startsWith('SMA_MARK_'),
    IsMobileMarkerOrderSelected:()=>{const o=e.orders.get(e.selectedOrder);return !!o&&o.magic===900&&o.symbol==='TEST'&&o.comment.startsWith('SMA_MARK_');},
    IsTradeRetcodeAccepted:r=>r===10009,
    markerTrade:{OrderDelete:t=>{e.calls.push(['delete',t]);return e.deleteAccept;},ResultRetcode:()=>e.deleteAccept?10009:10006,ResultComment:()=>''},
    老师点位最近错误码:0,老师点位最近错误:'',
    mobileMarkerDeleteTickets:[],mobileMarkerDeleteTrackingLoaded:false,
    FinalizeFloatingPnlTiming:()=>{},InvalidateStatsCache:()=>{},TradeJournalWriteLifecycle:()=>{},
    ClearPendingTradeAction:i=>{e.states[i].pendingAction=e.待确认动作_无;e.states[i].partialRequestPending=false;},
    MarkShortStateDirty:i=>{e.states[i].stateDirty=true;},
    TradeJournalOpen:()=>1,
    FileWrite:(handle,...fields)=>{e.writes++;if(e.failWrite)return 0;e.fileRows.push(fields.map(String));return 100;},
    FileFlush:()=>{if(e.failFlush)e.error=5001;},FileClose:()=>{},
    FileSeek:(h,offset,origin)=>{e.row=origin===e.SEEK_SET?0:e.fileRows.length;e.column=0;e.lastLineEnd=false;return true;},
    FileIsEnding:()=>e.row>=e.fileRows.length,
    FileReadString:()=>{const value=e.fileRows[e.row][e.column++];e.lastLineEnd=e.column===e.fileRows[e.row].length;if(e.lastLineEnd){e.row++;e.column=0;}return value;},
    FileIsLineEnding:()=>e.lastLineEnd,OrderCalcProfit:()=>false,
  });
  vm.createContext(e);
  e.install=(name,params,edit=x=>x)=>vm.runInContext(`function ${name}(${params}){${js(edit(body(name)))}}`,e);
  e.install('ShortStateKey','positionIdentifier,field');e.install('ShortStateRead','positionIdentifier,field');
  e.install('ShortStateWrite','positionIdentifier,field,value');e.install('ShortStateFieldsValid','id,fields');
  e.install('TrendLongSLIsRiskSide','type,openPrice,sl');
  e.install('ShortStateLoadProtectionFields','st');e.install('ShortStateSave','stateIdx');
  e.install('ShortStateLoad','stateIdx');e.install('ShortStateDelete','positionIdentifier');
  return e;
}
let checks=0;
function test(name,run){run();checks++;console.log('PASS '+name);}

test('fast protection rejects zero/negative/nonfinite server SL and target, both directions',()=>{
  for(const direction of [0,1])for(const [sl,target] of [[0,100],[-1,100],[NaN,100],[100,0],[100,NaN]]){
    const e=env();e.live.add(101);e.positionSL=sl;
    e.states[0]=state({positionDirection:direction,pendingAction:e.待确认动作_快速保护,pendingFastProtection:true,
      pendingFastProtectionSL:target,pendingRequestedSL:target,pendingRequestedTP:0});
    e.install('ReconcilePendingTradeAction','stateIdx');e.ReconcilePendingTradeAction(0);
    assert.equal(e.states[0].fastProtectionActivated,0);assert.notEqual(e.states[0].pendingAction,e.待确认动作_无);
  }
});
test('fast protection confirms reached/more protective SL; refuses weak SL',()=>{
  for(const direction of [0,1])for(const offset of [0,2,-2]){
    const e=env();e.live.add(101);e.positionSL=100+(direction===0?offset:-offset);
    e.states[0]=state({positionDirection:direction,pendingAction:e.待确认动作_快速保护,pendingFastProtection:true,
      pendingFastProtectionSL:100,pendingRequestedSL:100,pendingRequestedTP:0,pendingSLSource:e.SL来源_快速净保本});
    e.install('ReconcilePendingTradeAction','stateIdx');e.ReconcilePendingTradeAction(0);
    assert.equal(!!e.states[0].fastProtectionActivated,offset>=0);
  }
});
function savedEnv(){const e=env();e.states[0]=state({trendRiskReady:true,trendInitialRisk:10,trendInitialSL:90,trendHighSinceOpen:110,
  recoveryArmed:true,recoveryArmedTime:110,recoveryArmLossPrice:6,recoveryArmTrigger:5,
  teacherPlanInitialized:true,teacherPlanValid:true,teacherPlanSignature:0xfedcba9876543210n,
  teacherPlanMode:1,teacherPrimaryTP:120,teacherSecondaryTP:130});e.ShortStateSave(0);return e;}
test('V7 roundtrip preserves original trend R, recovery eligibility and 64-bit teacher plan',()=>{
  const e=savedEnv();assert.equal(e.ShortStateRead(101,'V'),7);assert.equal(e.ShortStateRead(101,'PC'),1);
  e.states[0]=state();e.positionSL=105;assert(e.ShortStateLoad(0));
  const s=e.states[0];assert(s.trendRiskReady);assert.equal(s.trendInitialRisk,10);assert.equal(s.trendInitialSL,90);
  assert(s.recoveryArmed);assert.equal(s.recoveryArmTrigger,5);assert(s.teacherPlanValid);
  assert.equal(s.teacherPlanSignature,0xfedcba9876543210n);assert.equal(s.teacherSecondaryTP,130);
});
test('legacy or uncommitted state does not infer original risk or reapply current teacher text',()=>{
  for(const [version,commit] of [[6,1],[7,0]]){const e=savedEnv();e.gv.set(e.ShortStateKey(101,'V'),version);e.gv.set(e.ShortStateKey(101,'PC'),commit);
    e.states[0]=state();assert(e.ShortStateLoad(0));const s=e.states[0];
    assert(!s.trendRiskReady&&s.trendRiskUnknown);assert(!s.recoveryArmed);assert(s.teacherPlanInitialized&&!s.teacherPlanValid);
    e.install('TrendFreezeInitialRiskFromServer','stateIdx,source');assert.equal(e.TrendFreezeInitialRiskFromServer(0,'restart'),false);
  }
});
test('missing/corrupt protection fields fail closed',()=>{
  const e=savedEnv();e.gv.delete(e.ShortStateKey(101,'TIR'));e.gv.set(e.ShortStateKey(101,'RAL'),1);e.gv.set(e.ShortStateKey(101,'TPT1'),90);
  e.states[0]=state();assert(e.ShortStateLoad(0));assert(!e.states[0].trendRiskReady);assert(e.states[0].trendRiskUnknown);
  assert(!e.states[0].recoveryArmed);assert(!e.states[0].teacherPlanValid);
});
test('write failure leaves dirty and uncommitted protection; retry commits; delete removes all new keys',()=>{
  const e=savedEnv();e.failKey=e.ShortStateKey(101,'TIR');e.ShortStateSave(0);assert(e.states[0].stateDirty);
  assert.equal(e.ShortStateRead(101,'PC'),0);e.failKey='';e.ShortStateSave(0);assert.equal(e.ShortStateRead(101,'PC'),1);
  e.ShortStateDelete(101);assert.equal(e.gv.size,0);
});
test('wrong lifecycle identity cannot restore saved fields',()=>{
  const e=savedEnv();e.states[0]=state({positionDirection:1});assert.equal(e.ShortStateLoad(0),false);
});
test('offline added volume or changed average invalidates restored protection only',()=>{
  for(const change of [{currentVolume:2},{currentOpen:102}]){
    const e=savedEnv();Object.assign(e,change);e.live.add(101);e.states[0]=state();assert(e.ShortStateLoad(0));
    assert(!e.states[0].trendRiskReady&&e.states[0].trendRiskUnknown);
    assert(!e.states[0].recoveryArmed&&!e.states[0].teacherPlanValid);
  }
});
test('normal partial reduction preserves frozen original R and teacher plan after restart',()=>{
  const e=savedEnv();e.currentVolume=.5;e.live.add(101);e.states[0]=state();assert(e.ShortStateLoad(0));
  assert(e.states[0].trendRiskReady&&e.states[0].teacherPlanValid);assert.equal(e.states[0].trendInitialRisk,10);
});

test('history snapshot survives selected-list replacement during every callback',()=>{
  const e=env();e.selected=[11,12,13];e.install('SnapshotSelectedDealTickets','tickets');const tickets=[];
  assert(e.SnapshotSelectedDealTickets(tickets));const seen=[];for(const t of tickets){seen.push(t);e.selected=[t];}
  assert.deepEqual(seen,[11,12,13]);
});
for(const name of ['ShortCheckPartialRequestTimeouts','ShortCheckPendingActionTimeouts'])test(name+' processes all deals; unreadable history retains pending',()=>{
  for(const unreadable of [0,12]){const e=env();for(const t of [11,12,13])e.deals.set(t,{id:101,entry:e.DEAL_ENTRY_OUT,time:900,volume:.1});
    e.unreadable=unreadable;e.states[0]=state({pendingAction:e.待确认动作_全部平仓,pendingActionTime:800,
      partialRequestPending:true,pendingPartialRequestTime:800,pendingPartialStartVolume:1,pendingPartialFilledVolume:0});
    if(name.includes('PartialRequest'))e.states[0].pendingAction=e.待确认动作_部分平仓;
    e.install('SnapshotSelectedDealTickets','tickets');e.ShortProcessedDealContains=t=>e.processed.has(t);
    e.ShortRecordDeal=t=>{e.selected=[t];e.calls.push(t);e.processed.add(t);if(t===13&&!unreadable){e.states[0].partialRequestPending=false;e.states[0].pendingAction=e.待确认动作_无;}return true;};
    e.ReconcilePendingTradeAction=()=>{};e.install(name,'');e[name]();
    assert.deepEqual(e.calls,unreadable?[11,13]:[11,12,13]);if(unreadable)assert(e.states[0].partialRequestPending);
  }
});
test('startup import captures all tickets and never commits a failed import',()=>{
  for(const failed of [0,12]){const e=env();for(const t of [11,12,13])e.deals.set(t,{id:101});
    e.install('SnapshotSelectedDealTickets','tickets');e.TradeJournalImportKey=()=> 'import';e.TradeJournalDealInScope=()=>true;
    e.TradeJournalWriteDeal=t=>{e.selected=[t];e.calls.push(t);return t!==failed;};e.install('TradeJournalImportAvailableHistory','');e.TradeJournalImportAvailableHistory();
    assert.deepEqual(e.calls,[11,12,13]);assert.equal(e.gv.has('import'),!failed);
  }
});
test('actual raw Deal writer marks seen only after successful write and flush',()=>{
  for(const failure of ['none','failWrite','failFlush']){
    const e=env();e.deals.set(11,{id:101,entry:e.DEAL_ENTRY_OUT,time:900,volume:1});
    if(failure!=='none')e[failure]=true;
    e.TradeJournalDealSeen=t=>e.processed.has(t);e.TradeJournalDealInScope=()=>true;
    e.TradeJournalMarkDealSeen=t=>e.processed.add(t);e.install('TradeJournalWriteDeal','dealTicket,source');
    assert.equal(e.TradeJournalWriteDeal(11,'test'),failure==='none');
    assert.equal(e.processed.has(11),failure==='none');
  }
});
test('empty or failed selected history cannot unlock a timed-out partial request',()=>{
  for(const failed of [false,true]){
    const e=env();e.historyFail=failed;
    e.states[0]=state({pendingAction:e.待确认动作_部分平仓,partialRequestPending:true,pendingPartialRequestTime:800});
    e.install('SnapshotSelectedDealTickets','tickets');e.install('ShortCheckPartialRequestTimeouts','');
    e.ShortCheckPartialRequestTimeouts();assert(e.states[0].partialRequestPending);
  }
});

function summaryEnv(){const e=env();e.deals.set(1,{id:101,entry:e.DEAL_ENTRY_IN,time:100,volume:1});
  e.deals.set(2,{id:101,entry:e.DEAL_ENTRY_OUT,time:900,volume:1});
  e.install('TradeSummaryKey','positionIdentifier');e.install('TradeJournalSummaryWritten','positionIdentifier');
  e.install('FindCompleteTradeSummaryRecord','handle,id,lastDeal,columns',c=>c.replace(/\bfound\b/g,'alreadyWritten'));
  e.install('FinalizeTradeLifecycle','stateIdx',c=>c.replace('bool alreadyWritten=false;','alreadyWritten=false;'));
  e.states[0].pendingAction=e.待确认动作_无;return e;}
test('incomplete exit, missing entry, and live position cannot finalize or write Summary',()=>{
  for(const mode of ['partial','missing','live']){const e=summaryEnv();if(mode==='partial')e.deals.get(2).volume=.4;
    if(mode==='missing')e.deals.delete(1);if(mode==='live')e.live.add(101);
    assert.equal(e.FinalizeTradeLifecycle(0),false);assert.equal(e.writes,0);assert(!e.gv.has(e.TradeSummaryKey(101)));
  }
});
test('complete multi-deal exit finalizes once, and only after successful flush',()=>{
  const e=summaryEnv();e.deals.get(2).volume=.4;e.deals.set(3,{id:101,entry:e.DEAL_ENTRY_OUT,time:901,volume:.6});
  assert(e.FinalizeTradeLifecycle(0));assert(e.states[0].tradeFinalized);assert.equal(e.writes,1);
  assert(e.FinalizeTradeLifecycle(0));assert.equal(e.writes,1);
});
test('Netting segment requires visible reversal entry and complete segment exit',()=>{
  for(const missing of [true,false]){
    const e=summaryEnv();e.states[0].nettingReversalDetected=true;e.states[0].lifecycleSegmentStartTime=100;
    if(!missing)e.deals.get(1).entry=e.DEAL_ENTRY_INOUT;
    assert.equal(e.FinalizeTradeLifecycle(0),!missing);
  }
});
test('failed Summary write or flush cannot set finalized/GV marker',()=>{
  for(const key of ['failWrite','failFlush']){const e=summaryEnv();e[key]=true;assert.equal(e.FinalizeTradeLifecycle(0),false);
    assert(!e.states[0].tradeFinalized);assert(!e.gv.has(e.TradeSummaryKey(101)));
  }
});
test('CSV-success/GV-failure retry finds complete row instead of duplicating Summary',()=>{
  const e=summaryEnv();e.failKey=e.TradeSummaryKey(101);assert.equal(e.FinalizeTradeLifecycle(0),false);assert.equal(e.writes,1);
  e.failKey='';assert(e.FinalizeTradeLifecycle(0));assert.equal(e.writes,1);
});
function markerEnv(){const e=env();for(const [name,args] of [['MobileMarkerDeletePrefix',''],['LoadMobileMarkerDeleteTracking',''],
  ['RequestMobileMarkerDelete','ticket'],['MobileMarkerOrderRetired','ticket'],['ReconcileMobileMarkerDeletes','']])e.install(name,args);
  return e;}
const order=(extra={})=>({magic:900,symbol:'TEST',comment:'SMA_MARK_R1',initial:.1,remaining:.1,id:501,...extra});
test('delete refusal/acceptance alone never permits replacement; canceled history does',()=>{
  for(const accepted of [false,true]){const e=markerEnv();e.deleteAccept=accepted;e.orders.set(1001,order());e.RequestMobileMarkerDelete(1001);
    assert(e.flushes>0);assert.equal(e.ReconcileMobileMarkerDeletes(),false);e.orders.delete(1001);e.ms+=1001;
    assert.equal(e.ReconcileMobileMarkerDeletes(),false);e.historyOrders.set(1001,order({status:e.ORDER_STATE_CANCELED}));e.ms+=1001;
    assert(e.ReconcileMobileMarkerDeletes());assert.equal(e.gv.size,0);
  }
});
test('restart reloads pending ticket above 2^53 without precision loss',()=>{
  const id=9007199254740993n,e=markerEnv();e.orders.set(id,order());e.RequestMobileMarkerDelete(id);
  const restarted=markerEnv();restarted.gv=new Map(e.gv);restarted.orders.set(id,order());assert(restarted.LoadMobileMarkerDeleteTracking());
  assert.equal(restarted.mobileMarkerDeleteTickets[0],id);assert.equal(restarted.ReconcileMobileMarkerDeletes(),false);
});
test('filled/part-filled marker remains blocked until its actual position and exits are reconciled',()=>{
  const e=markerEnv();e.orders.set(1001,order());e.RequestMobileMarkerDelete(1001);e.orders.clear();
  e.historyOrders.set(1001,order({status:e.ORDER_STATE_FILLED,remaining:0}));e.live.add(501);
  assert.equal(e.MobileMarkerOrderRetired(1001),false);e.live.clear();e.deals.set(1,{id:501,entry:e.DEAL_ENTRY_IN,time:100,volume:.1});
  e.deals.set(2,{id:501,entry:e.DEAL_ENTRY_OUT,time:101,volume:.04});assert.equal(e.MobileMarkerOrderRetired(1001),false);
  e.deals.set(3,{id:501,entry:e.DEAL_ENTRY_OUT,time:102,volume:.06});assert(e.MobileMarkerOrderRetired(1001));
});
test('marker safety refuses unrelated orders, disconnect, persistence failure; both creation paths gated',()=>{
  const e=markerEnv();e.orders.set(1001,order({magic:1}));assert.equal(e.RequestMobileMarkerDelete(1001),false);assert.equal(e.calls.length,0);
  e.orders.set(1001,order());e.failKey=e.MobileMarkerDeletePrefix()+'1001';assert.equal(e.RequestMobileMarkerDelete(1001),false);assert.equal(e.calls.length,0);
  e.connected=false;assert.equal(e.ReconcileMobileMarkerDeletes(),false);
  assert(body('SyncOneMobileMarker').includes('!ReconcileMobileMarkerDeletes()'));
  assert(body('SubmitTeacherMobileMarker').includes('!ReconcileMobileMarkerDeletes()'));
});
console.log(`${checks} trade-risk regression groups passed; no terminal/broker execution performed.`);
