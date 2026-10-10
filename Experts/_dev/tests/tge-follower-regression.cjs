// Execute extracted production MQL functions with deterministic broker mocks.
// Offline boundary checks, not a broker event test or profitability backtest.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync(path.join(__dirname,'../../EA_T哥点位跟单.mq5'),'utf8');
function body(name) {
  const def=src.search(new RegExp('^(?:bool|void|double|int|string|ulong) '+name+'\\(','m'));
  assert(def>=0,name); const start=src.indexOf('{',def); let end=start+1,depth=1;
  for(;depth;end++) {if(src[end]==='{')depth++;if(src[end]==='}')depth--;}
  return src.slice(start+1,end-1);
}
function translate(text) {
  return text.replace(/\((?:ENUM_ORDER_STATE|ENUM_ORDER_TYPE|double|long|ulong|int|datetime)\)/g,'')
    .replace(/\b(?:double|string|MqlRates) (\w+)\[\],(\w+)\[\];/g,'let $1=[], $2=[];')
    .replace(/\b(?:double|string) (\w+)\[\];/g,'let $1=[];')
    .replace(/\bMqlTick (\w+);/g,'let $1={};')
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
    MathMin:Math.min,MathMax:Math.max,MathAbs:Math.abs,MathFloor:Math.floor,MathCeil:Math.ceil,
    NormalizeDouble:(v,n)=>+v.toFixed(n),TickSize:()=>.01,
    SYMBOL_VOLUME_MIN:1,SYMBOL_VOLUME_STEP:2,SYMBOL_VOLUME_MAX:3,
    SymbolInfoDouble:(_,k)=>({1:.01,2:.01,3:100})[k],_Symbol:'XAUUSD',_Digits:2,
    LotDown:v=>Math.floor(v/.01+1e-8)*.01,ArraySize:a=>a.length,
    首批止盈价格距离:5,保险价格距离:10,尾仓目标价格距离:10,
    TimeCurrent:()=>1000,TimeTradeServer:()=>1000,
    PrintFormat:()=>{},GlobalVariablesFlush:()=>{},CanExecute:()=>true,
    pending:{kind:0},reason:'',TerminalInfoInteger:()=>true,TERMINAL_CONNECTED:1,
    Store:()=>true,ClearPending:()=>{e.pending={kind:0};},SavePending:()=>{},
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
function quote(at,connected=true) {
 const x=env();x.TerminalInfoInteger=()=>connected;x.SymbolInfoTick=(_,q)=>Object.assign(q,{bid:100,ask:100.1,time_msc:at});
 install(x,'FreshQuote','q');return x.FreshQuote({});
}
test('stale ticks cannot trade',()=>assert(!quote(990000)));
test('fresh ticks accepted',()=>assert(quote(999000)));
test('disconnected terminal cannot trade',()=>assert(!quote(999000,false)));
test('future clock mismatch rejected',()=>assert(!quote(1010000)));
function signal(options={}) {
 const x=env(),memory=options.memory??{},store=[];
 const m1=[{time:1740,...b},{time:1680,...p}];
 const m5=Array.from({length:7},(_,i)=>({time:1500-i*300,open:100.3,close:100.5,low:100.1,high:100.8}));
 const ma=[100,99.8,99.7,99.6,99.5,99.4,99.3];
 if(options.weave) for(let i=3;i<7;i++)m5[i].close=ma[i]+(i%2?.5:-.5);
 if(options.broken) {m5[0].close=99.5;m5[0].low=99;ma[0]=ma[1];}
 if(options.newLow)m1[0].low=99.8;
 if(options.remote)m1[0].close=102;
 Object.assign(x,{
  levels:[90,100,110],feedActive:true,FreshQuote:q=>Object.assign(q,{bid:100.4,ask:100.45}),
  最大点差价格:.5,允许震荡点位反应:!options.noReaction,
  maHandle:1,atrHandle:2,PERIOD_M1:1,PERIOD_M5:5,
  TimeCurrent:()=>1810,readyFrom:options.fence??1000,trend:0,atr:0,DBL_MAX:Number.MAX_VALUE,
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
function management({initial=.02,closed=0,remaining=.02,bid=105.1,sl=90,can=true}={}) {
 const x=env(),events=[];
 Object.assign(x,{CanExecute:()=>can,FreshQuote:q=>Object.assign(q,{bid,ask:bid+.02}),
  PositionsTotal:()=>1,PositionGetTicket:()=>7,OwnSelected:()=>true,
  POSITION_IDENTIFIER:1,POSITION_TYPE:2,POSITION_TYPE_BUY:0,
  POSITION_PRICE_OPEN:3,POSITION_VOLUME:4,POSITION_SL:5,POSITION_TP:6,
  PositionGetInteger:k=>k===1?700:0,
  PositionGetDouble:k=>({3:100,4:remaining,5:sl,6:110})[k],
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

test('source only has three guarded trading call sites',()=>{
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
test('level persistence independent from snapshot age',()=>{
 assert(!/TimeGMT\(\)\s*-\s*|86400/.test(body('ReadFeed')));
 assert(src.includes('tge_levels.csv'));assert(!src.includes('teacher_levels.csv'));
});
test('historical tester cannot use today Common file',()=>assert(src.includes('if(MQLInfoInteger(MQL_TESTER))')));
console.log(checks+' production-source offline checks passed');
