// Execute extracted production MQL functions with deterministic broker mocks.
// Offline boundary checks, not a broker event test or profitability backtest.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync(path.join(__dirname,'../../EA_T哥点位跟单.mq5'),'utf8');
function body(name) {
  const def=src.search(new RegExp('^(?:bool|void|double|int|string|ulong) '+name+'\\(','m'));
  if(def<0){
    const extra=fs.readFileSync(path.join(__dirname,'../../Include/Trading/TgeAISignals.mqh'),'utf8');
    const pos=extra.search(new RegExp('^(?:bool|void|double|int|string|ulong) '+name+'\\(','m'));
    assert(pos>=0,name);const start=extra.indexOf('{',pos);let end=start+1,depth=1;
    for(;depth;end++){if(extra[end]==='{')depth++;if(extra[end]==='}')depth--;}
    return extra.slice(start+1,end-1);
  }
  const start=src.indexOf('{',def); let end=start+1,depth=1;
  for(;depth;end++) {if(src[end]==='{')depth++;if(src[end]==='}')depth--;}
  return src.slice(start+1,end-1);
}
function translate(text) {
  return text.replace(/\bstatic\s+/g,'').replace(/\((?:ENUM_ORDER_STATE|ENUM_ORDER_TYPE|double|long|ulong|int|datetime)\)/g,'')
    .replace(/\b(?:double|string|MqlRates) (\w+)\[\],(\w+)\[\];/g,'let $1=[], $2=[];')
    .replace(/\b(?:double|string|AIPlan) (\w+)\[\];/g,'let $1=[];')
    .replace(/\b(?:MqlTick|Candidate|MqlRates) (\w+);/g,'let $1={};')
    .replace(/\b(?:double|long|ulong|int|datetime|bool|string|uint|ushort|ENUM_ORDER_STATE|ENUM_ORDER_TYPE)\s+/g,'let ')
    .replace(/PositionVolumes\(id,initial,closed\)/g,'((r)=>{initial=r.initial;closed=r.closed;return r.ok;})(PositionVolumes(id))');
}
function install(e,name,args) {
  vm.runInContext('function '+name+'('+args+'){'+translate(body(name))+'}',e);
}
let checks=0;
function test(name,fn) {fn();checks++;console.log('PASS '+name);}
function env() {
  const e=vm.createContext({
    点位提前容差:3,HasAILimit:()=>false,AILimitCount:()=>0,RefreshAITrend:()=>{},SyncAILimits:()=>{},AITrendEntry:()=>false,PrepareAILimit:()=>{},ReconcileAILimitCreation:()=>false,ORDER_TIME_SETUP:900,
    读取AI即时策略:false,aiReady:false,aiMode:"WAIT",ReadAISetups:()=>{},AIMarketSignal:()=>false,MathMin:Math.min,MathMax:Math.max,MathAbs:Math.abs,MathFloor:Math.floor,MathCeil:Math.ceil,
    NormalizeDouble:(v,n)=>+v.toFixed(n),TickSize:()=>.01,
    SYMBOL_VOLUME_MIN:1,SYMBOL_VOLUME_STEP:2,SYMBOL_VOLUME_MAX:3,
    SymbolInfoDouble:(_,k)=>({1:.01,2:.01,3:100})[k],_Symbol:'XAUUSD',_Digits:2,
    LotDown:v=>Math.floor(v/.01+1e-8)*.01,ArraySize:a=>a.length,
    首批止盈价格距离:5,保险价格距离:10,尾仓目标价格距离:10,
    TimeCurrent:()=>1000,TimeTradeServer:()=>1000,
    PrintFormat:()=>{},GlobalVariablesFlush:()=>{},CanExecute:()=>true,SyncTgeMobileMarkers:()=>{},
    pending:{kind:0},reason:'',TerminalInfoInteger:()=>true,TERMINAL_CONNECTED:1,
    entryView:{},checkingMinute:0,signalRetry:false,EMPTY_VALUE:Number.MAX_VALUE,
    ZeroMemory:p=>{for(const k of Object.keys(p))delete p[k];},DecisionLog:()=>{},ExecutionBlock:()=>'',
    StringFind:(a,b)=>a.indexOf(b),Store:()=>true,ClearPending:()=>{e.pending={kind:0};},SavePending:()=>{},
    HistoryDealSelect:()=>false,EA魔法号:560056,DEAL_ORDER:10,
    execution:{ResultRetcode:()=>0,ResultOrder:()=>0,ResultDeal:()=>0,ResultComment:()=>''}
  });
  const constants=[...new Set(src.match(/\bTRADE_RETCODE_[A-Z_]+\b/g))];
  constants.forEach((k,i)=>e[k]=100+i);
  return e;
}
const e=env();
install(e,'Reaction','bar,previous,level,sign,tolerance,escape');
install(e,'Trend','last,previous,ma0,ma1');
install(e,'BreakRetest','last,breakbar,before,level,sign,tolerance,escape');
install(e,'PartialRemaining','initial,closed,remaining');
install(e,'ExactLot','volume');
const b={open:100.1,close:100.4,low:99.9,high:100.5},p={open:100.5,close:100.2,low:99.85,high:100.6};
test('closed minute stops making lows',()=>assert(e.Reaction(b,p,100,1,.25,.05)));
test('new low rejects bullish bar',()=>assert(!e.Reaction({...b,low:99.8},p,100,1,.25,.05)));
test('deep prior penetration rejects bounce',()=>assert(!e.Reaction(b,{...p,low:98},100,1,.25,.05)));
test('unrelated remote candles reject',()=>assert(!e.Reaction({...b,low:100.3},{...p,low:100.3},100,1,.25,.05)));
test('no reclaim rejects',()=>assert(!e.Reaction({...b,close:100.02},p,100,1,.25,.05)));
const invert=x=>({open:200-x.open,close:200-x.close,low:200-x.high,high:200-x.low});
test('sell reaction is symmetric',()=>assert(e.Reaction(invert(b),invert(p),100,-1,.25,.05)));
test('MA full candle detachment required',()=>assert.equal(e.Trend({close:101},{low:99.9,high:101},100.5,100),0));
test('MA rising detached candle buys',()=>assert.equal(e.Trend({close:101},{low:100.1,high:101},100.5,100),1));
test('MA falling detached candle sells',()=>assert.equal(e.Trend({close:99},{high:99.9,low:99},99.5,100),-1));
test('failed MA hold not trend',()=>assert.equal(e.Trend({close:100.4},{low:100.1},100.5,100),0));
test('break and retest accepted',()=>assert(e.BreakRetest({low:100.1,close:100.3},{close:100.8},{close:99.8},100,1,.25,.05)));
test('old trend is not a fresh breakout',()=>assert(!e.BreakRetest({low:100.1,close:100.3},{close:100.8},{close:100.2},100,1,.25,.05)));
test('deep broken retest rejected',()=>assert(!e.BreakRetest({low:99.5,close:100.3},{close:100.8},{close:99.8},100,1,.25,.05)));
test('.02 first partial is .01',()=>assert.equal(e.PartialRemaining(.02,0,.02),.01));
test('restart after half closed never repeats partial',()=>assert.equal(e.PartialRemaining(.02,.01,.01),0));
test('minimum lot cannot be accidentally closed as a partial',()=>assert.equal(e.PartialRemaining(.01,0,.01),0));
test('partial fills only request outstanding quantity',()=>assert.equal(e.PartialRemaining(.04,.01,.03),.01));
test('fixed .02 lot accepted without resizing',()=>assert(e.ExactLot(.02)));
test('off-step lot rejected rather than rounded',()=>assert(!e.ExactLot(.025)));
function target(levels,entry=100,sign=1) {
 const x=env();x.levels=levels;x.tp=0;x.Align=(v,d)=>(d>0?Math.ceil(v/.01-1e-8):Math.floor(v/.01+1e-8))*.01;
 install(x,'Target','entry,sign');return {ok:x.Target(entry,sign),tp:x.tp};
}
test('tail target capped at 10 even when next level remote',()=>assert.equal(target([90,100,150]).tp,110));
test('near obstacle trims target',()=>assert.equal(target([90,100,108]).tp,107.8));
test('less than 5 point profit space blocks entry',()=>assert(!target([90,100,104]).ok));
test('sell target symmetric',()=>assert.equal(target([92,100,110],100,-1).tp,92.2));
function feed(options={}) {
 const x=env(),rows=options.rows??[
  'TGE,1,'+(options.generated??1000)+','+(options.active??1)+','+(options.symbol??'XAUUSD')+',message,rev,3,900,teacher,ou_teacher',
  'LEVEL,100','LEVEL,110','LEVEL,120','END,3'];
 let pos=0;
 Object.assign(x,{FEED:'test',FILE_READ:1,FILE_TXT:2,FILE_ANSI:4,FILE_COMMON:8,FILE_SHARE_READ:16,
   CP_UTF8:65001,INVALID_HANDLE:-1,FileOpen:()=>options.missing?-1:1,FileSize:()=>1000,
   FileIsEnding:()=>pos>=rows.length,FileReadString:()=>rows[pos++],FileClose:()=>{},
   StringSplit:(s,sep,out)=>{out.length=0;out.push(...s.split(sep));return out.length;},
   StringToInteger:Number,StringToDouble:Number,StringLen:s=>s.length,StringGetCharacter:(s,i)=>s[i],
   ArrayResize:(a,n)=>a.length=n,ArrayCopy:(a,b)=>{a.length=0;a.push(...b);},MathIsValidNumber:Number.isFinite,
   TimeGMT:()=>2000,Print:()=>{},DrawLevels:()=>{},levels:[50,60,70],identity:'old|rev',
   feedActive:true,readyFrom:0,sourceKind:'',sourceSender:'',feedTime:0,sourceTime:0,feedStatus:''});
 install(x,'Number','text,decimal=false');install(x,'ReadFeed','');return {ok:x.ReadFeed(),x};
}
test('old but intact point map remains active',()=>{const r=feed();assert(r.ok&&r.x.feedActive);assert.equal(r.x.levels[0],100);});
test('different chart symbol cannot overwrite map',()=>{const r=feed({symbol:'EURUSD'});assert(!r.ok);assert.equal(r.x.levels[0],50);});
test('partial CSV cannot overwrite map',()=>assert(!feed({rows:['TGE,1,1000,1,XAUUSD,message,rev,3,900,teacher,ou_teacher','LEVEL,100']}).ok));
test('pause snapshot disables trading but preserves visible levels',()=>{
 const r=feed({rows:['TGE,1,1000,0,XAUUSD,message,rev,0,900,teacher,ou_teacher','END,0']});
 assert(r.ok&&!r.x.feedActive);assert.equal(r.x.levels[0],50);
});
test('missing snapshot retains last complete map',()=>{const r=feed({missing:true});assert(!r.ok&&r.x.feedActive);assert.equal(r.x.levels[0],50);});
test('future snapshot cannot replace map',()=>assert(!feed({generated:2010}).ok));
test('new map establishes startup fence',()=>assert.equal(feed().x.readyFrom,1000));
function quote(at,connected=true,observedServer=1000,estimatedServer=1000) {
 const x=env();x.TimeCurrent=()=>observedServer;x.TimeTradeServer=()=>estimatedServer;x.TerminalInfoInteger=()=>connected;x.SymbolInfoTick=(_,q)=>Object.assign(q,{bid:100,ask:100.1,time_msc:at});
 install(x,'FreshQuote','q');return x.FreshQuote({});
}
test('stale ticks cannot trade',()=>assert(!quote(990000)));
test('fresh ticks accepted',()=>assert(quote(999000)));
test('disconnected terminal cannot trade',()=>assert(!quote(999000,false)));
test('future clock mismatch rejected',()=>assert(!quote(1010000)));
test('broker clock ahead of local estimate still accepts current tick',()=>assert(quote(1003450,true,1003,1000)));
test('millisecond part of an observed server second stays valid',()=>assert(quote(1003999,true,1003,1000)));
test('estimated server time continues aging a tick when observed server time stops',()=>assert(!quote(1003450,true,1003,1009)));
test('later Market Watch tick still detects stale chart-symbol quote',()=>assert(!quote(1000000,true,1006,1000)));
test('future tick without matching broker time remains rejected',()=>assert(!quote(1010000,true,1003,1000)));
test('five-second quote freshness limit is retained',()=>{
 assert(quote(995000));assert(!quote(994999));
});

function signal(options={}) {
 const x=env(),memory=options.memory??{},store=[],now=options.now??1810;
 const m1time=Math.floor(now/60)*60-60,currentM5=Math.floor(now/300)*300;
 const m1=[{time:m1time,...b},{time:m1time-60,...p}];
 const m5=Array.from({length:7},(_,i)=>({time:currentM5-300-i*300,open:100.3,close:100.5,low:100.1,high:100.8}));
 const ma=[100,99.8,99.7,99.6,99.5,99.4,99.3];
 if(options.weave) for(let i=3;i<7;i++)m5[i].close=ma[i]+(i%2?.5:-.5);
 if(options.broken) {m5[0].close=99.5;m5[0].low=99;ma[0]=ma[1];}
 if(options.newLow)m1[0].low=99.8;
 if(options.remote)m1[0].close=102;
 Object.assign(x,{
  levels:[90,100,110],feedActive:true,FreshQuote:q=>Object.assign(q,{bid:100.4,ask:100.45}),
  最大点差价格:.5,允许震荡点位反应:!options.noReaction,
  maHandle:1,atrHandle:2,PERIOD_M1:1,PERIOD_M5:5,
  TimeCurrent:()=>now,TimeTradeServer:()=>now,iTime:(_s,tf,shift)=>tf===5?currentM5:shift===1?m1time:m1time+60,readyFrom:options.fence??1000,trend:0,atr:0,DBL_MAX:Number.MAX_VALUE,
  ArraySetAsSeries:()=>{},CopyRates:(_,tf,_shift,_count,out)=>{out.push(...(tf===1?m1:m5));return out.length;},
  CopyBuffer:(h,_buf,_shift,_count,out)=>{out.push(...(h===1?ma:[2]));return out.length;},
  MathIsValidNumber:Number.isFinite,DoubleToString:(v,n)=>v.toFixed(n),
  Load:k=>memory[k]??0,Store:(k,v)=>{memory[k]=v;store.push([k,v]);},
  Align:v=>v,tp:0
 });
 for(const [name,args] of [['Reaction','bar,previous,level,sign,tolerance,escape'],['Trend','last,previous,ma0,ma1'],
  ['BreakRetest','last,breakbar,before,level,sign,tolerance,escape'],['Target','entry,sign'],['VisitKey','level'],['Signal','out']])install(x,name,args);
 const out={};return {ok:x.Signal(out),out,x,store};
}
test('complete production candidate selects MA5 pullback',()=>{const r=signal();assert(r.ok);assert.equal(r.out.method,'M5 MA5顺势回踩');});
test('valid closed M5 is usable in every minute of its five-minute cycle',()=>{
 for(const phase of [1,61,121,181,241]){
  const r=signal({now:1800+phase});assert(r.ok,'valid M5 blocked at cycle second '+phase);
  assert.equal(r.out.bar,Math.floor((1800+phase)/60)*60-60);
 }
});
test('missing current M5 timestamp retries without producing a candidate',()=>{
 const {x}=signal();x.iTime=()=>0;assert(!x.Signal({}));assert.equal(x.signalRetry,true);
});
test('unclosed or future M5 cannot be used as the latest completed candle',()=>{
 const {x}=signal();const copy=x.CopyRates;
 x.CopyRates=(s,tf,a,b,out)=>{const n=copy(s,tf,a,b,out);if(tf===5)out.forEach(v=>v.time+=300);return n;};
 assert(!x.Signal({}));assert.equal(x.signalRetry,true);
});
test('full candidate rejects still-making-low minute',()=>assert(!signal({newLow:true}).ok));
test('full candidate rejects startup historical bars',()=>assert(!signal({fence:1741}).ok));
test('full candidate rejects consumed visit after restart',()=>assert(!signal({memory:{'visit100.00':1740}}).ok));
test('three MA crossings disable trend-only entry',()=>assert(!signal({weave:true,noReaction:true}).ok));
test('broken M5 side cannot be bought as a neutral reaction',()=>assert(!signal({broken:true}).ok));

test('observation gate prevents ALL position management',()=>{
 const x=env();x.CanExecute=()=>false;x.PositionsTotal=()=>{throw Error('should return before position management');};
 install(x,'Manage','');x.Manage();
});
test('pending request prevents duplicate management',()=>{
 const x=env();x.pending={kind:2};x.PositionsTotal=()=>{throw Error('duplicate');};
 install(x,'Manage','');x.Manage();
});
function management({initial=.02,closed=0,remaining=.02,bid=105.1,sl=90,can=true,tp=110,tag="",sign=1}={}) {
 const x=env(),events=[];
 Object.assign(x,{CanExecute:()=>can,FreshQuote:q=>Object.assign(q,{bid,ask:bid+.02}),
  PositionsTotal:()=>1,PositionGetTicket:()=>7,OwnSelected:()=>true,
  POSITION_IDENTIFIER:1,POSITION_TYPE:2,POSITION_TYPE_BUY:0,
  POSITION_PRICE_OPEN:3,POSITION_VOLUME:4,POSITION_SL:5,POSITION_TP:6,
  PositionGetInteger:k=>k===1?700:sign>0?0:1,
  POSITION_COMMENT:7,PositionGetString:()=>tag,
  PositionGetDouble:k=>({3:100,4:remaining,5:sl,6:tp})[k],
  PositionVolumes:()=>({initial,closed,ok:true}),PositionSelectByTicket:()=>true,
  Align:(v)=>v,Modify:(...a)=>{events.push(['modify',...a]);x.pending.kind=3;},
  ZeroMemory:p=>{for(const k of Object.keys(p))delete p[k];},
  SavePending:()=>events.push(['persist']),RecordResult:()=>events.push(['result'])
 });
 x.execution.PositionClosePartial=(...a)=>events.push(['partial',...a]);
 install(x,'PartialRemaining','initial,closed,remaining');install(x,'Manage','');x.Manage();
 return events;
}
test('actual .02 position closes .01 after +5',()=>{
 const events=management();assert.equal(events[1][0],'partial');assert.equal(events[1][2],.01);assert.equal(events[0][0],'persist');
});
test('no partial before +5',()=>assert.equal(management({bid:104.99}).length,0));
test('restart + confirmed half -> only break-even',()=>{
 const events=management({closed:.01,remaining:.01,bid:103});assert.equal(events[0][0],'modify');assert.equal(events[0][4],100);
 assert(!events.some(x=>x[0]==='partial'));
});
test('confirmed half with BE already applied is unchanged',()=>{
 assert.equal(management({closed:.01,remaining:.01,bid:106,sl:100}).length,0);
});
test('more protective server SL is never loosened',()=>{
 assert.equal(management({closed:.01,remaining:.01,bid:106,sl:102}).length,0);
});
test('history/position mismatch never trades',()=>{
 assert.equal(management({closed:.01,remaining:.02}).length,0);
});
test('indivisible lot uses +5 full TP',()=>{
 const a=management({initial:.01,remaining:.01});assert.equal(a[0][0],'modify');assert.equal(a[0][5],105);
});
test('favorable limit fills cap BUY and SELL tail targets from actual price',()=>{
 const buy=management({bid:101,tp:113,tag:'TGLbuy'});assert.equal(buy[0][5],110);
 const sell=management({bid:99,sl:110,tp:87,tag:'TGLsell',sign:-1});assert.equal(sell[0][5],90);
 assert.equal(management({bid:101,tp:108,tag:'TGLbuy'}).length,0);
});
test('delayed partial remains pending on unknown retcode',()=>{
 const x=env();x.pending={kind:2};install(x,'ExplicitReject','code');install(x,'RecordResult','');x.RecordResult();assert.equal(x.pending.kind,2);
});
test('accepted request does not declare partial completed',()=>{
 const x=env();x.pending={kind:2};x.execution.ResultRetcode=()=>9999;
 install(x,'ExplicitReject','code');install(x,'RecordResult','');x.RecordResult();assert.equal(x.pending.kind,2);
});
test('explicit server rejection clears only pending intent',()=>{
 const x=env();x.pending={kind:2};x.execution.ResultRetcode=()=>x.TRADE_RETCODE_INVALID_VOLUME;
 install(x,'ExplicitReject','code');install(x,'RecordResult','');x.RecordResult();assert.equal(x.pending.kind,0);
});
test('unknown request is not unlocked by elapsed time',()=>{
 const x=env();x.pending={kind:2,at:1,order:0,position:77};
 x.HistorySelectByPosition=()=>false;
 install(x,'Reconcile','');x.Reconcile();assert.equal(x.pending.kind,2);assert(x.reason.includes('对账'));
});
test('torn persistent intent remains blocked',()=>{
 const x=env();x.pending={kind:-1};install(x,'Reconcile','');x.Reconcile();assert.equal(x.pending.kind,-1);
});
function reconcileOrder({visible=false,history=true,state=1,filled=.02,actual=.02}={}) {
 const x=env();
 Object.assign(x,{OrderSelect:()=>visible,HistoryOrderSelect:()=>history,HistoryOrderGetInteger:()=>state,
   ORDER_STATE_FILLED:1,ORDER_STATE_CANCELED:2,ORDER_STATE_REJECTED:3,ORDER_STATE_EXPIRED:4,ORDER_STATE:10,
   ORDER_VOLUME_INITIAL:11,ORDER_VOLUME_CURRENT:12,HistoryOrderGetDouble:(_,k)=>k===11?.02:.02-filled,
   HistorySelect:()=>true,HistoryDealsTotal:()=>1,HistoryDealGetTicket:()=>88,
   HistoryDealGetInteger:()=>7,HistoryDealGetDouble:()=>actual,DEAL_VOLUME:13,pending:{at:900}});
 install(x,'FinalOrderConfirmed','order');return x.FinalOrderConfirmed(7);
}
test('FILLED without deal stays blocked',()=>assert(!reconcileOrder({actual:0})));
test('all fills reconciled unlocks',()=>assert(reconcileOrder()));
test('live server order stays blocked',()=>assert(!reconcileOrder({visible:true})));
test('canceled remainder still needs executed volume reconciled',()=>assert(!reconcileOrder({state:2,filled:.01,actual:0})));
test('canceled untouched order can unlock',()=>assert(reconcileOrder({state:2,filled:0,actual:0})));

test('core strategy retains its three guarded trading call sites',()=>{
 const calls=[...src.matchAll(/execution\.(PositionOpen|PositionClosePartial|PositionModify)\(/g)];
 assert.equal(calls.length,3);
 for(const name of ['Open','Manage','Modify']) assert(body(name).includes('!CanExecute()'));
 assert(!/\bOrderSend(?:Async)?\s*\(/.test(src));
});
test('closed candle indices and startup fence retained',()=>{
 assert(body('Signal').includes('PERIOD_M1,1,2'));assert(body('Signal').includes('PERIOD_M5,1,7'));
 assert(body('Signal').includes('m1[0].time<readyFrom'));
 assert(body('Signal').includes('Load(VisitKey(level))>0'));
});
test('data unavailable retries same candle then evaluates only once',()=>{
 const r=signal(),x=r.x;let pulls=0,opens=0,logs=0;
 const copy=x.CopyRates;
 Object.assign(x,{busy:false,lastMinute:0,ReadFeed:()=>{},ReadHealth:()=>{},UpdateDay:()=>{},Reconcile:()=>{},Manage:()=>{},Panel:()=>{},
   iTime:(_s,tf)=>tf===5?1800:1740,Open:()=>opens++,DecisionLog:()=>logs++,TimeTradeServer:()=>1810,
   CopyRates:(...a)=>++pulls===1?0:copy(...a)});
 install(x,'OnTimer','');x.OnTimer();assert.equal(x.lastMinute,0);assert.equal(opens,0);
 x.OnTimer();assert.equal(x.lastMinute,1740);assert.equal(opens,1);
 x.OnTimer();assert.equal(opens,1);assert.equal(logs,2);
});
test('retry deadline ends even when data remains unavailable',()=>{
 const {x}=signal();x.checkingMinute=1740;x.TimeTradeServer=()=>1831;x.CopyRates=()=>0;
 assert(!x.Signal({}));assert.equal(x.signalRetry,false);assert(x.reason.includes('窗口已结束'));
});
test('strategy rejection and large spread do not retry old bar',()=>{
 const {x}=signal({newLow:true});assert.equal(x.signalRetry,false);
 x.FreshQuote=q=>Object.assign(q,{bid:100,ask:101});x.Signal({});assert.equal(x.signalRetry,false);
});
test('quote disconnect waits but startup fence still rejects historical bar',()=>{
 const {x}=signal({fence:1741});const fresh=x.FreshQuote;x.FreshQuote=()=>false;
 x.Signal({});assert.equal(x.signalRetry,true);
 x.FreshQuote=fresh;assert(!x.Signal({}));assert.equal(x.signalRetry,false);
});
test('candidate card explains exact selected point and M1',()=>{
 const {x,out}=signal();assert.equal(x.entryView.level,out.level);assert.equal(x.entryView.direction,out.direction);
 assert(x.entryView.reaction);assert.equal(x.entryView.method,out.method);assert(Math.abs(x.entryView.space-9.55)<1e-8);
});
test('consumed point explains wait without silently rearming',()=>{
 const r=signal({memory:{'visit100.00':1740}});assert(!r.ok);assert(r.x.reason.includes('已消费'));assert.equal(r.store.length,0);
});
test('execution block records reason without making request',()=>{
 const {x,out}=signal();x.ExecutionBlock=()=> '本EA持仓已达上限';install(x,'Open','signal');
 x.Open(out);assert.equal(x.reason,'本EA持仓已达上限');assert.equal(x.pending.kind,0);
});
test('same-bar attempt guard still stops a duplicate request',()=>{
 const {x,out}=signal({memory:{attemptBar:1740}});install(x,'Open','signal');
 x.Open(out);assert.equal(x.reason,'本根M1已发送过请求');assert.equal(x.pending.kind,0);
});
function progress({closed=0,remaining=.02,sl=90,pending={kind:0},history=true,quote=true}={}) {
 const x=env();Object.assign(x,{pending,PositionVolumes:()=>({initial:.02,closed,ok:history}),
  FreshQuote:q=>quote&&Object.assign(q,{bid:103,ask:103.02}),DoubleToString:(v,n)=>v.toFixed(n)});
 install(x,'PositionProgress','id,sign,open,remaining,sl');return x.PositionProgress(7,1,100,remaining,sl);
}
test('progress measures remaining first target distance',()=>assert(progress().includes('还差 2.00')));
test('pending partial never displays a confirmed reduction',()=>{
 const s=progress({pending:{kind:2,position:7}});assert(s.includes('已减 0.00'));assert(s.includes('待确认'));
});
test('confirmed partial with unapplied SL remains awaiting BE',()=>{
 const s=progress({closed:.01,remaining:.01,pending:{kind:3,position:7}});assert(s.includes('已减 0.01'));assert(s.includes('保本请求待确认'));
});
test('only actual protective SL displays confirmed BE',()=>assert(progress({closed:.01,remaining:.01,sl:100}).includes('保本已确认')));
test('history mismatch and quote loss never invent progress',()=>{
 assert(progress({remaining:.01}).includes('历史待核对'));assert(progress({quote:false}).includes('不可用'));
});
function health(row='HEALTH,1,2000,1990,1980,1,0,120,END',now=2000) {
 const x=feed().x;Object.assign(x,{healthBeat:0,healthSync:0,healthCheckpoint:0,healthOK:false,healthPaused:false,healthMaxAge:120,
  TimeGMT:()=>now,FileSize:()=>100,FileReadString:()=>row});
 install(x,'ReadHealth','');install(x,'SyncStatus','');x.ReadHealth();return x;
}
test('health describes online sync independently from old valid map',()=>{
 const x=health();assert(x.SyncStatus().includes('同步正常'));assert(x.feedActive);
});
test('dead exporter heartbeat is distinct from failed Feishu sync',()=>{
 assert(health(undefined,2011).SyncStatus().includes('心跳中断'));
 assert(health('HEALTH,1,2000,1990,1980,0,0,120,END').SyncStatus().includes('同步失败'));
});
test('lagged checkpoint warns but does not expire points',()=>{
 const x=health('HEALTH,1,2000,1990,1800,1,0,120,END');assert(x.SyncStatus().includes('延迟'));assert(x.feedActive);
});
test('partial and future health snapshots are ignored',()=>{
 assert.equal(health('HEALTH,1,2000').healthBeat,0);
 assert.equal(health('HEALTH,1,2010,1990,1980,1,0,120,END').healthBeat,0);
});
test('delayed latest M5 is retried within the same M1 window',()=>{
 const {x}=signal();const copy=x.CopyRates;
 x.CopyRates=(s,tf,a,b,out)=>{const n=copy(s,tf,a,b,out);if(tf===5)out.forEach(v=>v.time-=300);return n;};
 assert(!x.Signal({}));assert.equal(x.signalRetry,true);
});
test('order request and successful reconciliation are separate journal events',()=>{
 const x=env(),events=[];x.DecisionLog=(...a)=>events.push(a);
 x.pending={kind:1,at:900,order:7};x.execution.ResultOrder=()=>7;
 x.execution.ResultRetcode=()=>9999;
 install(x,'ExplicitReject','code');install(x,'RecordResult','');install(x,'Reconcile','');
 x.RecordResult();assert.equal(events[0][0],'REQUEST_RESULT');assert.equal(x.pending.kind,1);
 x.FinalOrderConfirmed=()=>false;x.Reconcile();assert.equal(events.length,1);
 x.FinalOrderConfirmed=()=>true;x.Reconcile();assert.equal(events[1][0],'ORDER_RECONCILED');assert.equal(x.pending.kind,0);
});
test('decision CSV deduplicates retries and retains request correlation',()=>{
 const x=env(),rows=[];Object.assign(x,{identity:'msg|revision',sourceKind:'teacher',sourceSender:'teacher-test',sourceTime:800,
  entryView:{bar:900,level:100,direction:1,distance:.5,space:9.5,ma:100,m1close:100.3,crossings:0,reaction:true,method:'pullback'},
  checkingMinute:900,atr:2,trend:1,lastDecisionKey:'',prefix:'test.',
  pending:{kind:1,at:970,bar:900,level:100,order:71,position:0,volume:.02,sl:90,tp:110},
  IntegerToString:String,FolderCreate:()=>true,TimeGMT:()=>1000,TimeToString:()=> '2026.10.10',StringReplace:()=>{},
  TIME_DATE:1,FILE_READ:1,FILE_WRITE:2,FILE_CSV:4,FILE_ANSI:8,FILE_COMMON:16,FILE_SHARE_READ:32,CP_UTF8:65001,INVALID_HANDLE:-1,SEEK_END:2,
  FileOpen:()=>1,FileSize:()=>rows.length,FileWrite:(_, ...a)=>{rows.push(a);return 1;},FileSeek:()=>true,FileFlush:()=>{},FileClose:()=>{}});
 install(x,'DecisionLog','event,detail,retcode=0,deal=0');
 x.DecisionLog('EVALUATE','waiting');x.DecisionLog('EVALUATE','waiting');assert.equal(rows.length,2);
 x.DecisionLog('EVALUATE','ready');x.DecisionLog('REQUEST_RESULT','accepted',10009,88);
 const header=rows[0],record=rows.at(-1);assert.equal(record.length,header.length);
 for(const [key,value] of [['context_identity','msg|revision'],['request_bar',900],['order',71],['retcode',10009],['deal',88]])
  assert.equal(record[header.indexOf(key)],value);
 x.FileOpen=()=>-1;x.GetLastError=()=>5004;x.Print=()=>{};x.DecisionLog('EVALUATE','write fail');
 assert.equal(x.pending.order,71);assert(!x.lastDecisionKey.includes('write fail'));
});
test('real execution diagnostics keep pending and position limits blocked',()=>{
 const x=env();Object.assign(x,{启用真实交易:true,stateOK:true,lockHandle:1,INVALID_HANDLE:-1,
  accountLogin:7,accountServer:'test',ACCOUNT_LOGIN:1,ACCOUNT_SERVER:2,ACCOUNT_MARGIN_MODE:3,ACCOUNT_MARGIN_MODE_RETAIL_HEDGING:4,
  ACCOUNT_TRADE_ALLOWED:5,ACCOUNT_TRADE_EXPERT:6,TERMINAL_TRADE_ALLOWED:7,MQL_TRADE_ALLOWED:8,
  AccountInfoInteger:k=>k===1?7:k===3?4:1,AccountInfoString:()=> 'test',MQLInfoInteger:()=>true,
  dayStopped:false,最大同时持仓:3,OwnCount:()=>0});
 install(x,'ExecutionBlock','');assert.equal(x.ExecutionBlock(),'');
 x.pending={kind:1};assert(x.ExecutionBlock().includes('待服务器确认'));
 x.pending={kind:0};x.OwnCount=()=>3;assert(x.ExecutionBlock().includes('上限'));
 x.OwnCount=()=>0;x.TerminalInfoInteger=k=>k!==7;assert(x.ExecutionBlock().includes('算法交易未开启'));
});
test('changed map clears previous candle explanation',()=>{
 const r=feed();assert.equal(r.x.entryView.ready,undefined);assert(r.x.reason.includes('等待随后完整M1'));
});
test('level persistence independent from snapshot age',()=>{
 assert(!/TimeGMT\(\)\s*-\s*|86400/.test(body('ReadFeed')));
 assert(src.includes('tge_levels.csv'));assert(!src.includes('teacher_levels.csv'));
});
test('historical tester cannot use today Common file',()=>assert(src.includes('if(MQLInfoInteger(MQL_TESTER))')));
test('one-percent daily equity lock removed even when legacy stopped GV exists',()=>{
 assert(!src.includes('每日权益回撤上限百分比'));assert(!src.includes('dayStopped'));assert(!src.includes('UpdateDay()'));
 assert(!body('ExecutionBlock').includes('回撤限制'));assert(!body('OnInit').includes('Load("stopped")'));
});

function aiEnv(options={}){
 const x=env(),memory={};Object.assign(x,{读取AI即时策略:true,aiReady:true,aiMode:'SETUP',
  aiPlans:options.plans||[{sign:1,level:100,market:false},{sign:-1,level:112,market:false}],
  feedActive:true,aiIdentity:'msg-new',aiSource:'msg-new',aiSourceTime:990,aiGenerated:1000,TimeGMT:()=>1000,
  atr:2,atrHandle:2,MathIsValidNumber:Number.isFinite,tp:0,DBL_MAX:Number.MAX_VALUE,levels:[90,100,104],最大点差价格:.5,Hash:s=>[...s].reduce((a,v)=>a+v.charCodeAt(0),0),
  点位提前容差:1.5,IntegerToString:String,DoubleToString:(v,n)=>v.toFixed(n),Align:v=>v,
  Load:k=>memory[k]||0,Store:(k,v)=>memory[k]=v,ArraySetAsSeries:()=>{},
  FreshQuote:q=>Object.assign(q,{bid:100.4,ask:100.45}),CopyBuffer:(_h,_b,shift,n,out)=>{out.push(2);return 1;}});
 for(const [name,args] of [['Target','entry,sign'],['AIVisitKey','level,sign'],['AISignal','bar,q,out'],['AIMarketSignal','out']])install(x,name,args);
 return {x,memory};
}
test('authoritative AI BUY uses one completed M1 reaction without opposite MA veto',()=>{
 const {x}=aiEnv();x.trend=-1;const out={};
 assert(x.AISignal({...b,time:990},{bid:100.4,ask:100.45},out));assert.equal(out.direction,1);assert.equal(out.ai,true);
 assert(out.method.includes('msg-new'));
});
test('near/prefix wording allows a bounded price zone instead of missing an integer not exactly touched',()=>{
 const {x}=aiEnv({plans:[{sign:1,level:100,market:false,near:true},{sign:-1,level:120,market:false}]});
 const bar={time:990,open:106,low:104.6,high:109,close:108};
 assert(x.AISignal(bar,{bid:108,ask:108.05},{}));
 x.aiPlans[0].near=false;assert(!x.AISignal(bar,{bid:108,ask:108.05},{}));
 x.aiPlans[0].near=true;assert(!x.AISignal(bar,{bid:110,ask:110.05},{}));
});
test('advance zone cannot rearm a consumed opportunity while still inside three units',()=>{
 const {x,memory}=aiEnv();x.点位提前容差=3;const key=x.AIVisitKey(100,1);memory[key]=990;
 x.AISignal({time:1000,open:102,low:101.5,high:103,close:102.5},{bid:102.5,ask:102.55},{});
 assert.equal(memory[key],990);
 x.AISignal({time:1000,open:103,low:103,high:104,close:104},{bid:104,ask:104.05},{});
 assert.equal(memory[key],0);
});
test('AI SELL reference is not mistaken for a bidirectional neutral level',()=>{
 const {x}=aiEnv({plans:[{sign:-1,level:100,market:false},{sign:1,level:88,market:false}]});
 const out={};assert(x.AISignal({...invert(b),time:990},{bid:99.55,ask:99.6},out));assert.equal(out.direction,-1);
});
test('AI reaction still rejects a red buy bar or missing reclaim',()=>{
 const {x}=aiEnv();assert(!x.AISignal({...b,time:990,close:100.05},{bid:100.4,ask:100.45},{}));
 assert(!x.AISignal({...b,time:990,open:100.5},{bid:100.4,ask:100.45},{}));
});
test('new AI range controls target instead of obsolete morning obstacle',()=>{
 const {x}=aiEnv();assert.equal(x.Target(100,1),true);assert.equal(x.tp,110);
});
test('AI visit keys separate source and direction and prevent repeated same opportunity',()=>{
 const {x,memory}=aiEnv();const first=x.AIVisitKey(100,1);memory[first]=990;
 assert(!x.AISignal({...b,time:990},{bid:100.4,ask:100.45},{}));
 assert.notEqual(x.AIVisitKey(100,-1),first);x.aiIdentity='another';
 assert.notEqual(x.AIVisitKey(100,1),first);assert(x.AISignal({...b,time:990},{bid:100.4,ask:100.45},{}));
});
test('explicit AI market hint has live TTL and needs fresh quote and ATR',()=>{
 const {x}=aiEnv({plans:[{sign:1,level:100,market:true},{sign:-1,level:112,market:false}]});
 const out={};assert(x.AIMarketSignal(out));assert.equal(out.ai,true);assert(out.method.includes('市价'));
 x.aiSourceTime=800;assert(!x.AIMarketSignal({}));x.aiSourceTime=990;x.FreshQuote=()=>false;assert(!x.AIMarketSignal({}));
});
test('AI market path cannot bypass withdrawn map or dead bridge',()=>{
 const {x}=aiEnv({plans:[{sign:1,level:100,market:true}]});
 x.feedActive=false;assert(!x.AIMarketSignal({}));x.feedActive=true;x.aiGenerated=980;assert(!x.AIMarketSignal({}));
});
test('market hints are not rearmed merely because price moved away',()=>{
 const {x,memory}=aiEnv({plans:[{sign:1,level:100,market:true}]});
 memory[x.AIVisitKey(100,1)]=990;
 assert(!x.AISignal({...b,time:1000,close:105},{bid:100.4,ask:100.45},{}));assert.equal(memory[x.AIVisitKey(100,1)],990);
});
test('AI instant updates only use candle that finishes after activation',()=>{
 assert(body('Signal').includes('m1[0].time+60>readyFrom'));
 assert(body('OnTimer').includes('AIMarketSignal(immediate)'));
 assert(body('ReadAISetups').includes('lastMinute=0'));
});

function aiFeed(rows){
 const x=feed().x;let pos=0;
 Object.assign(x,{aiReady:true,aiMode:'SETUP',aiIdentity:'old',aiReason:'',aiPlans:[{sign:1,level:90}],lastMinute:88,
  FileReadString:()=>rows[pos++],FileIsEnding:()=>pos>=rows.length,
  FileSize:()=>rows.join('\n').length,ArrayResize:(a,n)=>{while(a.length<n)a.push({});a.length=n;},
  TimeGMT:()=>2000});
 install(x,'ReadAISetups','');const ok=x.ReadAISetups();return {ok,x};
}
test('AI snapshot validates symbol, footer, heartbeat and provenance before activation',()=>{
 const valid=['TGA,1,2000,1,XAUUSD,msg,revision,1900,2,SETUP,ok','SETUP,BUY,100,REACTION,POINT','SETUP,SELL,112,REACTION,POINT','END,2'];
 const r=aiFeed(valid);assert(r.ok);assert(r.x.aiReady);assert.equal(r.x.aiPlans[1].sign,-1);assert.equal(r.x.readyFrom,1000);
 for(const rows of [valid.slice(0,3),valid.map(v=>v.replace('XAUUSD','EURUSD')),
  valid.map(v=>v.replace(',2000,',',1980,')),valid.map(v=>v.replace('SELL','EXECUTE')),
  valid.map(v=>v.replace('END,2','END,1'))]){
  const f=aiFeed(rows);assert(!f.ok);assert.equal(f.x.aiReady,false);
 }
});
test('AI WAIT snapshot clears execution readiness while keeping reference data separate',()=>{
 const r=aiFeed(['TGA,1,2000,0,XAUUSD,msg,revision,1900,0,WAIT,pause','END,0']);
 assert(r.ok);assert.equal(r.x.aiReady,false);assert.equal(r.x.aiMode,'WAIT');assert.equal(r.x.aiPlans.length,0);
});
console.log(checks+' production-source offline checks passed');
