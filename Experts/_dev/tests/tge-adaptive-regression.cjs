// 执行生产MQL函数体。仅替换MQL类型/输出引用和终端API，不连接账户、不发送交易。
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..');
const main=fs.readFileSync(path.join(root,'EA_T哥点位跟单.mq5'),'utf8');
const src=fs.readFileSync(path.join(root,'Include/Trading/TgeAdaptiveStrategy.mqh'),'utf8');
function body(name){
 const all=src+'\n'+main,re=new RegExp('^(?:void|bool|string|double) '+name+'\\(','m');
 const pos=all.search(re);assert(pos>=0,name);const start=all.indexOf('{',pos);let end=start+1,depth=1;
 for(;depth;end++){if(all[end]==='{')depth++;if(all[end]==='}')depth--;}
 return all.slice(start+1,end-1);
}
function install(x,name,args,outputs=[]){
 let s=body(name).replace(/CTrade (\w+);/g,'let $1=new CTrade();').replace(/\((?:int|uint|long|ulong|double|datetime)\)/g,'')
 .replace(/\b(?:MqlRates|MqlCalendarValue|AdaptiveEvent|AdaptiveResult|ulong|double) (\w+)\[(?:\d+)?\];/g,'let $1=[];')
 .replace(/double values\[\]=\{([^}]+)\};/g,'let values=[$1];')
 .replace('double ranges[14],total=0;','let ranges=[],total=0;')
 .replace('double fast[2],slow[2];','let fast=[],slow=[];')
 .replace(/\b(?:MqlCalendarEvent|MqlTick) (\w+);/g,'let $1={};')
 .replace(/\b(?:const )?(?:int|long|ulong|double|bool|string|datetime|ENUM_ORDER_TYPE|MqlRates|AdaptiveResult)\s+/g,'let ')
 .replace(/OrderCalcProfit\(([^;]+?),\s*(standard|loss|pnl)\)/g,(_,a,v)=>`((r)=>{${v}=r.value;return r.ok;})(OrderCalcProfit(${a}))`)
 .replace(/TickImpact\(([^,]+),([^,]+),(\w+),(\w+),(\w+)\)/g,(_,a,b,c,d,e)=>`((r)=>{${c}=r.speed;${d}=r.oneway;${e}=r.pullback;return r.ok;})(TickImpact(${a},${b}))`)
 .replace('AdaptiveNewsState(now,after)','((r)=>{after=r.confirmAfter;return r.result;})(AdaptiveNewsState(now))')
 .replace('AdaptiveEntryPrices(signal,q,sl,first,tp,structure)','((r)=>{sl=r.sl;first=r.first;tp=r.tp;structure=r.structure;return r.result;})(AdaptiveEntryPrices(signal,q,sl,first,tp,structure))');
 if(outputs.length) s=s.replace(/return ([^;]+);/g,(_,expr)=>`return {result:${expr},${outputs.join(',')}};`);
 vm.runInContext(`function ${name}(${args}){${s}}`,x);
}
function env(){
 let now=10000,selected=null,history=[],allDeals=[],positions=[];const memory={},calls=[];
 const x=vm.createContext({
   结构缓冲ATR倍数:.25,点位破位缓冲ATR倍数:.25,点位破位确认根数:2,点位刺穿冷却秒数:60,点位破位冷却秒数:180,最小结构风险距离:2,合计风险标准单倍数:2,减风险触发R:.5,保本触发R:1,保本缓冲价格:.2,
  无进展退出分钟:8,连亏区域冷却分钟:30,冲击冷却秒数:120,恢复确认秒数:180,
  启用消息日历:false,重点事件前后分钟:10,一般高重要性前后分钟:3,重点事件提前退出分钟:2,
  启用积极持单:true,保险价格距离:10,首批止盈价格距离:5,尾仓目标价格距离:10,每次开仓手数:.02,最大点差价格:.5,
  持单策略:1,TGE_HOLD_LEGACY:0,TGE_HOLD_STRUCTURE:1,TGE_HOLD_FIXED:2,
  adaptiveBars:Array.from({length:16},(_,i)=>({time:9900-i*60,open:100,close:100.5,low:99,high:101})),
  adaptiveATR:2,adaptiveBaseline:2,adaptiveTrend:0,adaptiveMarketReady:true,adaptiveMarketAt:now,
  adaptiveHistoryReady:true,adaptiveHistoryDirty:false,adaptiveHistoryAt:now,adaptiveResults:[],adaptiveEvents:[],
  adaptiveCalendarAt:now,adaptiveCalendarTry:0,adaptiveShockUntil:0,adaptiveRecoverUntil:0,adaptiveShockSave:0,
  adaptiveMinute:0,adaptiveRangeTriggered:0,adaptiveMinuteHigh:0,adaptiveMinuteLow:0,
  aiPlans:[{level:100,sign:1,id:'plan'}],levels:[],pending:{kind:0},prefix:'test.',stateOK:true,
  TEACHER_BAND:1,DBL_MAX:Number.MAX_VALUE,_Symbol:'XAUUSD',_Digits:2,EA魔法号:560056,
  TimeCurrent:()=>now,TimeGMT:()=>now,TickSize:()=>.01,MathMax:Math.max,MathMin:Math.min,MathAbs:Math.abs,MathIsValidNumber:Number.isFinite,
  IntegerToString:String,DoubleToString:(v,d)=>v.toFixed(d),Load:k=>memory[k]||0,Store:(k,v)=>{memory[k]=v;return true;},
  GlobalVariableSet:(k,v)=>{memory[k.replace('test.','')]=v;return true;},GlobalVariablesFlush:()=>{},
  ArraySize:a=>a.length,ArrayResize:(a,n)=>{while(a.length<n)a.push({});a.length=n;},ArraySort:a=>a.sort((a,b)=>a-b),ArraySetAsSeries:()=>{},
  Align:(v,sign)=>Number((sign>0?Math.ceil((v-1e-8)*100)/100:Math.floor((v+1e-8)*100)/100).toFixed(2)),
  LotDown:v=>Math.floor(v*100+1e-7)/100,SymbolInfoDouble:()=>.01,SYMBOL_VOLUME_MIN:1,
  PositionsTotal:()=>positions.length,PositionGetTicket:i=>{selected=positions[i];return selected.ticket;},
  PositionById:id=>{selected=positions.find(p=>p.id===id);return selected?.ticket||0;},OwnSelected:()=>selected?.own!==false,
  PositionGetInteger:k=>selected[k],PositionGetDouble:k=>selected[k],
  POSITION_IDENTIFIER:'id',POSITION_PRICE_OPEN:'open',POSITION_VOLUME:'volume',POSITION_SL:'sl',POSITION_TYPE:'type',POSITION_TYPE_BUY:0,
  ORDER_TYPE_BUY:0,ORDER_TYPE_SELL:1,OrderCalcProfit:(type,symbol,volume,entry,exit)=>({ok:true,value:(type===0?1:-1)*(exit-entry)*volume*100}),
  PlanSign:i=>x.aiPlans[i].sign,TickImpact:()=>({ok:true,speed:0,oneway:0,pullback:0}),reason:'',
  Stops:()=>true,Modify:(...a)=>{if(x.pending.kind||!x.stateOK)return;calls.push(['modify',...a]);x.pending={kind:3,position:a[1]};},
  RequestExit:(...a)=>{if(x.pending.kind||!x.stateOK)return;calls.push(['exit',...a]);x.pending={kind:2,position:a[1]};},
  PERIOD_M1:1,trendFastHandle:1,trendSlowHandle:2,
  CopyRates:(s,p,shift,count,out)=>{assert.equal(shift,1);return count;},CopyBuffer:(h,b,shift,count,out)=>{assert.equal(shift,1);out.splice(0,out.length,100,100);return count;},
  CalendarValueHistory:(out,from,to,country,currency)=>{assert.equal(currency,'USD');return 0;},CalendarEventById:()=>false,
  CALENDAR_IMPORTANCE_HIGH:3,CALENDAR_TIMEMODE_DATETIME:0,CALENDAR_SECTOR_JOBS:1,CALENDAR_SECTOR_PRICES:2,CALENDAR_SECTOR_MONEY:3,NULL:null,
  HistorySelect:()=>{history=allDeals;return true;},HistorySelectByPosition:id=>{history=allDeals.filter(d=>d.id===id);return true;},
  HistoryDealsTotal:()=>history.length,HistoryDealGetTicket:i=>history[i].ticket,
  HistoryDealGetInteger:(ticket,key)=>allDeals.find(d=>d.ticket===ticket)[key]||0,
  HistoryDealGetDouble:(ticket,key)=>allDeals.find(d=>d.ticket===ticket)[key]||0,
  HistoryDealGetString:(ticket,key)=>allDeals.find(d=>d.ticket===ticket)[key]||'',
  DEAL_POSITION_ID:'id',DEAL_ENTRY:'entry',DEAL_MAGIC:'magic',DEAL_SYMBOL:'symbol',DEAL_TYPE:'type',DEAL_TIME:'time',DEAL_ORDER:'order',
  DEAL_VOLUME:'volume',DEAL_PROFIT:'profit',DEAL_COMMISSION:'commission',DEAL_SWAP:'swap',DEAL_FEE:'fee',
  DEAL_ENTRY_IN:0,DEAL_ENTRY_OUT:1,DEAL_ENTRY_OUT_BY:2,DEAL_ENTRY_INOUT:3,DEAL_TYPE_BUY:0,
  FreshQuote:q=>Object.assign(q,{bid:100,ask:100.1}),CanExecute:()=>true,ExecutionBlock:()=>'',RefreshPlanValidity:()=>{},
  TeacherEntryAllowed:()=>true,Hash:()=>123,ExactLot:()=>true,InTeacherBand:()=>true,
  OrderCalcMargin:()=>true,AccountInfoDouble:()=>10000,ACCOUNT_MARGIN_FREE:1,
  ClearPending:()=>{x.pending={kind:0};},AIKeyFromHash:()=>'visit',SharedVisitKey:()=>'shared',ZeroMemory:p=>{for(const k of Object.keys(p))delete p[k];},MergeOpportunity:()=>{},LifeEntry:()=>{},DecisionLog:()=>{},EntryTag:()=>'entry',RecordResult:()=>{},
  CTrade:function(){return {SetExpertMagicNumber:()=>{},SetDeviationInPoints:()=>{},SetTypeFillingBySymbol:()=>{},SetAsyncMode:()=>{},PositionOpen:(...a)=>calls.push(['open',...a])};},
 });
 for(const [n,a,o] of [
  ['ExitKey','id'],['AdaptiveInputsValid',''],['InitAdaptive',''],['RefreshAdaptiveMarket',''],['AdaptiveMarketFresh',''],
  ['RefreshAdaptiveCalendar',''],['AdaptiveNewsState','now,confirmAfter=0',['confirmAfter']],['AdaptiveNewsExit','now'],
  ['UpdateAdaptiveShock','q'],['RefreshAdaptiveHistory',''],['AdaptiveConfirmed','sign,level,after'],['AdaptiveEntryStatus','i,q'],
  ['AdaptiveEntryPrices','signal,q,sl=0,first=0,tp=0,structure=0',['sl','first','tp','structure']],
  ['AdaptiveRiskAllowed','sign,entry,sl,volume'],['AdaptiveProtection','sign,open,risk,peak,reduced'],
  ['FirstExit','id,sign,open,tp'],['PartialRemaining','initial,closed,remaining'],
  ['ManageAdaptive','ticket,id,sign,open,volume,sl,tp,initial,closed,opened,q'],
  ['ManageFixedExit','ticket,id,sign,open,volume,sl,tp,q'],
  ['AbortUnsent','releaseVisit=false'],['SavePending',''],['RestorePending',''],['SaveEntryExits',''],['Open','signal']]) install(x,n,a,o);
 return {x,memory,calls,setNow:t=>now=t,setPositions:p=>positions=p,setDeals:d=>allDeals=d,
  fresh:t=>{now=t;x.adaptiveMarketAt=t;x.adaptiveHistoryAt=t;}};
}
let checks=0;function test(name,fn){fn();checks++;
console.log('PASS '+name);}
function seed(e,sign=1){Object.assign(e.memory,{'exit1.ready':1,'exit1.adaptive':1,'exit1.initialSL':100-sign*4,'exit1.sl':100-sign*4,'exit1.structure':100-sign*3,'exit1.first':100+sign*3,'exit1.tp':100+sign*10});}
function manage(e,sign,gain,opts={}){const price=100+sign*gain; e.x.ManageAdaptive(11,1,sign,100,opts.volume??.02,opts.sl??100-sign*4,100+sign*10,.02,opts.closed??0,opts.opened??9800,{bid:sign>0?price:price-.1,ask:sign>0?price+.1:price});}
test('参数非法拒绝，默认可用',()=>{const {x}=env();assert(x.AdaptiveInputsValid());x.保本触发R=.1;assert(!x.AdaptiveInputsValid());x.保本触发R=NaN;assert(!x.AdaptiveInputsValid());});
test('正常行情直接触价；趋势相反需M1',()=>{const {x}=env();assert.equal(x.AdaptiveEntryStatus(0,{}),'触价候选');x.adaptiveTrend=-1;x.adaptiveBars[0].close=99.8;assert.match(x.AdaptiveEntryStatus(0,{}),/M1/);x.adaptiveBars[0].close=100.5;assert.equal(x.AdaptiveEntryStatus(0,{}),'M1确认候选');});
test('M1未收回点位、未触及区域或未到确认时间均拒绝',()=>{const {x}=env();assert(x.AdaptiveConfirmed(1,100,9800));assert(!x.AdaptiveConfirmed(1,100,9901));assert(!x.AdaptiveConfirmed(-1,100,0));x.adaptiveBars[0].low=102;assert(!x.AdaptiveConfirmed(1,100,0));});
test('数据过期不使用旧结构，刷新只读取已收盘K',()=>{const {x,setNow}=env();setNow(10006);assert(!x.AdaptiveMarketFresh());x.RefreshAdaptiveMarket();assert(x.AdaptiveMarketFresh());x.adaptiveBars[3].time--;x.RefreshAdaptiveMarket();assert(!x.adaptiveMarketReady);});
test('消息窗口及恢复确认按服务器时间，重叠事件不提前解锁',()=>{const {x}=env();x.启用消息日历=true;x.adaptiveEvents=[{at:10000,core:true},{at:10600,core:false}];assert.match(x.AdaptiveNewsState(9400).result,/消息窗口/);x.adaptiveCalendarAt=10700;assert.match(x.AdaptiveNewsState(10700).result,/消息窗口/);assert.equal(x.AdaptiveNewsState(10781).confirmAfter,10780);x.adaptiveCalendarAt=10781;assert.equal(x.AdaptiveNewsState(10961).confirmAfter,0);});
test('日历失败不擦除已知事件，陈旧日历禁新单但已知消息仍主动退出',()=>{const {x,setNow}=env();x.启用消息日历=true;x.adaptiveEvents=[{at:10100,core:true}];x.CalendarValueHistory=()=>-1;x.RefreshAdaptiveCalendar();assert.equal(x.adaptiveEvents.length,1);setNow(10200);assert.match(x.AdaptiveNewsState(10200).result,/未就绪/);assert(x.AdaptiveNewsExit(10200));x.重点事件提前退出分钟=0;assert(!x.AdaptiveNewsExit(10200));});
test('空日历成功与失败明确区分；无精确时间不误放行',()=>{const {x}=env();x.启用消息日历=true;x.adaptiveCalendarAt=0;x.RefreshAdaptiveCalendar();assert.equal(x.adaptiveCalendarAt,10000);x.adaptiveCalendarTry=0;x.CalendarValueHistory=out=>{out.push({event_id:1,time:10100});return 1;};x.CalendarEventById=(id,o)=>Object.assign(o,{importance:3,time_mode:1});x.adaptiveCalendarAt=0;x.RefreshAdaptiveCalendar();assert.equal(x.adaptiveCalendarAt,0);});
test('冲击冷却跨重启保留，微小回拉不清零，冷却后需新M1',()=>{const e=env(),{x,memory}=e;x.TickImpact=()=>({ok:true,speed:2,oneway:1,pullback:0});x.UpdateAdaptiveShock({time:10000,time_msc:1e7,bid:100,ask:100.1});assert.equal(memory['ad.shockUntil'],10120);x.TickImpact=()=>({ok:true,speed:0,oneway:0,pullback:.4});x.UpdateAdaptiveShock({time:10000,time_msc:1e7+100,bid:100.4,ask:100.5});assert.equal(x.adaptiveShockUntil,10120);x.adaptiveShockUntil=0;x.InitAdaptive();assert.equal(x.adaptiveShockUntil,10120);e.fresh(10121);x.adaptiveBars[0].time=10060;assert.match(x.AdaptiveEntryStatus(0,{}),/等待M1/);});
test('单根大范围冲击只触发一次，双向tick和点差均能触发',()=>{for(const mode of ['range','up','spread']){const {x}=env();x.UpdateAdaptiveShock({time:10000,time_msc:1e7,bid:100,ask:100.1});if(mode==='up')x.TickImpact=s=>({ok:true,speed:s<0?2:-2,oneway:s<0?1:0,pullback:0});x.UpdateAdaptiveShock({time:10000,time_msc:1e7+200,bid:mode==='range'?107:100,ask:mode==='spread'?102:mode==='range'?107.1:100.1});assert(x.adaptiveShockUntil>10000);}});
test('本区域不叠仓；别的区域不受影响',()=>{const {x,setPositions}=env();setPositions([{ticket:1,id:9,open:101,own:true}]);assert.match(x.AdaptiveEntryStatus(0,{}),/已有持仓/);x.aiPlans[0].level=110;assert.equal(x.AdaptiveEntryStatus(0,{}),'触价候选');});
test('首次亏损转确认，连续两次仅冷却本区域；盈利重置',()=>{const {x}=env();x.adaptiveResults=[{sign:1,level:100,net:-1,closed:9901}];assert.match(x.AdaptiveEntryStatus(0,{}),/等待M1/);x.adaptiveResults.push({sign:1,level:100,net:-2,closed:9800});assert.match(x.AdaptiveEntryStatus(0,{}),/连续亏损/);x.aiPlans[0].level=110;assert.equal(x.AdaptiveEntryStatus(0,{}),'触价候选');x.aiPlans[0].level=100;x.adaptiveResults.unshift({sign:1,level:100,net:1,closed:9950});assert.equal(x.AdaptiveEntryStatus(0,{}),'触价候选');});
test('历史按真实完整平仓计亏损，计入手机退出和费用，排除部分平仓',()=>{const e=env();e.x.adaptiveHistoryDirty=true;for(const id of [1,2])Object.assign(e.memory,{['exit'+id+'.adaptive']:1,['exit'+id+'.level']:100});e.setDeals([
 {ticket:1,id:1,entry:0,magic:560056,symbol:'XAUUSD',volume:.02,type:0,time:8000,commission:-.5},
 {ticket:2,id:1,entry:1,magic:0,symbol:'XAUUSD',volume:.01,time:9000,profit:2},
 {ticket:3,id:1,entry:1,magic:0,symbol:'XAUUSD',volume:.01,time:9500,profit:-3,fee:-.1},
 {ticket:4,id:2,entry:0,magic:560056,symbol:'XAUUSD',volume:.02,type:0,time:8000},
 {ticket:5,id:2,entry:1,magic:0,symbol:'XAUUSD',volume:.01,time:9900,profit:-8}]);e.x.RefreshAdaptiveHistory();assert(e.x.adaptiveHistoryReady);assert.equal(e.x.adaptiveResults.length,1);assert.equal(e.x.adaptiveResults[0].net,-1.6);assert.equal(e.x.adaptiveResults[0].closed,9500);});
for(const sign of [1,-1]){
 test('结构SL、首批、尾仓顺序及最大风险 '+sign,()=>{const {x}=env();const s={direction:sign,level:100,exitSL:0,exitFirst:0,exitTP:0},q={ask:100.1,bid:100};let r=x.AdaptiveEntryPrices(s,q);assert(r.result);const entry=sign>0?q.ask:q.bid;assert(sign*(entry-r.sl)>0);assert(sign*(r.first-entry)>0);assert(sign*(r.tp-r.first)>.01);s.exitSL=entry-sign*11;assert(!x.AdaptiveEntryPrices(s,q).result);});
 test('风险金额上限与保护仓不抵消别单风险 '+sign,()=>{const {x,setPositions}=env();assert(x.AdaptiveRiskAllowed(sign,100,100-sign*5,.02));setPositions([{ticket:1,own:true,open:100,sl:90,volume:.02,type:0},{ticket:2,own:true,open:100,sl:90,volume:.02,type:0}]);assert(!x.AdaptiveRiskAllowed(sign,100,100-sign*5,.02));setPositions([{ticket:1,own:true,open:100,sl:105,volume:.02,type:0}]);assert(x.AdaptiveRiskAllowed(sign,100,100-sign*5,.02));x.OrderCalcProfit=()=>({ok:false});assert(!x.AdaptiveRiskAllowed(sign,100,100-sign*5,.02));});
 test('保护目标对称：0.5R减风险、1R保本、成交减半保本 '+sign,()=>{const {x}=env();assert.equal(x.AdaptiveProtection(sign,100,4,1,false),100-sign*4);assert.equal(x.AdaptiveProtection(sign,100,4,2,false),100-sign*2);assert.equal(x.AdaptiveProtection(sign,100,4,4,false),100+sign*.2);assert.equal(x.AdaptiveProtection(sign,100,4,0,true),100+sign*.2);});
 test('实际保护只收紧，风险基准不随SL移动 '+sign,()=>{const e=env();seed(e,sign);manage(e,sign,2.1);assert.equal(e.calls[0][0],'modify');assert.equal(e.calls[0][4],100-sign*2);assert.equal(e.memory['exit1.risk'],4);e.x.pending={kind:0};e.calls.length=0;manage(e,sign,2.2,{sl:100+sign});assert.equal(e.calls.length,0);assert.equal(e.memory['exit1.risk'],4);});
 test('先修改保护也保留首批到价；未收到成交不显示减半 '+sign,()=>{const e=env();seed(e,sign);manage(e,sign,3.1);assert.equal(e.memory['exit1.firstHit'],1);assert.equal(e.calls[0][0],'modify');e.x.pending={kind:0};e.calls.length=0;manage(e,sign,2.8,{sl:100-sign*2});assert.equal(e.calls[0][0],'exit');assert.equal(e.calls[0][3],.01);assert.equal(e.calls[0][4],false);assert.equal(e.memory['exit1.risk'],4);});
 test('实减半后才进入余仓保护，结构跟踪不放宽 '+sign,()=>{const e=env();seed(e,sign);e.x.adaptiveBars.forEach(b=>{b.low=sign>0?102:95;b.high=sign>0?105:98;});manage(e,sign,4.5,{volume:.01,closed:.01,opened:9500});assert.equal(e.calls[0][0],'modify');assert(sign*(e.calls[0][4]-100)>=.2-1e-8);});
 test('回撤越过获得保护位退出，不退回原SL '+sign,()=>{const e=env();seed(e,sign);e.memory['exit1.mfe']=4.1;manage(e,sign,.1);assert.equal(e.calls[0][0],'exit');assert.equal(e.calls[0][4],true);assert.match(e.calls[0][5],/保护位/);});
 test('单根反向K不退出，收破入场结构才退出 '+sign,()=>{const e=env();seed(e,sign);e.x.adaptiveBars[0].open=100+sign*2;e.x.adaptiveBars[0].close=100+sign;manage(e,sign,1);assert.equal(e.calls.length,0);e.x.adaptiveBars[0].close=100-sign*3.2;manage(e,sign,1);assert.match(e.calls[0][5],/入场结构/);});
 test('时间退出只作用于无进展且不盈利 '+sign,()=>{const e=env();seed(e,sign);manage(e,sign,.1,{opened:9000});assert.equal(e.calls.length,0);manage(e,sign,-.1,{opened:9000});assert.match(e.calls[0][5],/时间退出/);});
}
test('禁用新策略开关后既有新策略单仍保护，消息日历故障不阻止管理',()=>{const e=env();seed(e);e.x.启用积极持单=false;e.x.启用消息日历=true;e.x.adaptiveCalendarAt=0;manage(e,1,2.1);assert.equal(e.calls[0][0],'modify');});
test('重点事件主动退出优先于分批与修改',()=>{const e=env();seed(e);e.x.启用消息日历=true;e.x.adaptiveEvents=[{at:10100,core:true}];manage(e,1,4.1);assert.equal(e.calls[0][0],'exit');assert.equal(e.calls[0][4],true);assert.match(e.calls[0][5],/消息/);});
test('待确认请求阻止再发，状态写入失败不发送',()=>{const e=env();seed(e);e.x.pending={kind:2,position:1};manage(e,1,4.1);assert.equal(e.calls.length,0);e.x.pending={kind:0};e.x.Store=()=>{e.x.stateOK=false;return false;};manage(e,1,5);assert.equal(e.calls.length,0);});
test('pending结构计划跨重启恢复，旧pending默认legacy',()=>{const {x,memory}=env();x.pending={kind:1,order:7,position:0,at:9990,bar:9900,volume:.02,sl:96,tp:110,level:100,direction:1,fast:true,originHash:5,exitSL:96,exitFirst:103,exitBE:0,exitTP:110,adaptive:true,structure:97,entryAtr:2};x.SavePending();x.pending={};x.RestorePending();assert.equal(x.pending.adaptive,true);assert.equal(x.pending.structure,97);assert.equal(x.pending.entryAtr,2);delete memory.adaptive;x.RestorePending();assert.equal(x.pending.adaptive,false);});
test('计划只绑定实际本EA入场Deal，不提前标记首批完成',()=>{const e=env();const journal=[];e.x.LifeEntry=id=>journal.push(id);e.x.pending={order:7,originHash:5,exitSL:96,exitFirst:103,exitBE:0,exitTP:110,adaptive:true,sl:96,level:100,structure:97,entryAtr:2};assert(!e.x.SaveEntryExits());e.setDeals([{ticket:1,id:9,order:7,entry:0,magic:560056,symbol:'XAUUSD'}]);e.x.HistorySelect();assert(e.x.SaveEntryExits());assert.equal(e.memory['exit9.ready'],1);assert.equal(e.memory['exit9.adaptive'],1);assert.equal(e.memory['exit9.initialSL'],96);assert.equal(e.memory['exit9.firstHit'],undefined);assert.deepEqual(journal,[9]);});
test('完整开仓路径冻结结构计划并保持0.02手',()=>{const {x,calls}=env();x.Open({originHash:123,direction:1,level:100,bar:9900,method:'touch',exitSL:0,exitFirst:0,exitTP:0,exitBE:0});assert.equal(calls.length,1);assert.equal(calls[0][0],'open');assert.equal(calls[0][3],.02);assert.equal(x.pending.adaptive,true);assert(x.pending.structure>0);assert.equal(x.pending.exitSL,x.pending.sl);});
test('接管条件限定于成交标记；没有改旧单退出算法',()=>{assert.match(main,/Load\(key\+"ready"\)==1 && Load\(key\+"adaptive"\)==1/);assert.match(main,/int mode=ExitRhythm\(sign,opened\)/);assert.match(main,/RefreshAdaptiveCalendar\(\);\s*\}/);});
for(const sign of [1,-1]){
 test('固定模式开仓忽略老师退出覆盖，设置TP5/SL10 '+sign,()=>{
  const {x,calls}=env();x.持单策略=2;x.启用积极持单=false;x.aiPlans[0].sign=sign;
  x.Open({originHash:123,direction:sign,level:100,bar:9900,method:'touch',exitSL:sign>0?80:120,exitFirst:101,exitTP:sign>0?120:80,exitBE:101});
  assert.equal(calls.length,1);assert.equal(x.pending.fixedExit,true);assert.equal(x.pending.adaptive,false);
  const entry=sign>0?100.1:100;assert(Math.abs(sign*(entry-x.pending.sl)-10)<1e-8);
  assert(Math.abs(sign*(x.pending.tp-entry)-5)<1e-8);assert.equal(x.pending.exitFirst,0);assert.equal(x.pending.exitBE,0);
 });
 test('固定模式无分批保本，碰到TP/SL全平 '+sign,()=>{
  const e=env(),run=gain=>{const price=100+sign*gain;e.x.ManageFixedExit(11,1,sign,100,.02,100-sign*10,100+sign*5,{bid:sign>0?price:price-.1,ask:sign>0?price+.1:price});};
  run(4.9);assert.equal(e.calls.length,0);run(5);assert.equal(e.calls[0][0],'exit');assert.equal(e.calls[0][3],.02);assert.equal(e.calls[0][4],true);
  e.calls.length=0;e.x.pending={kind:0};run(-10);assert.equal(e.calls[0][4],true);
 });
 test('固定模式按实际成交均价校正，保留更紧SL且不受当前模式影响 '+sign,()=>{
  const {x,calls}=env();x.持单策略=1;
  x.ManageFixedExit(11,1,sign,100,.02,100-sign*4,100+sign*6,{bid:102,ask:102.1});
  assert.equal(calls[0][0],'modify');assert.equal(calls[0][4],100-sign*4);assert.equal(calls[0][5],100+sign*5);
 });
}
test('旧版分批模式保持老师退出价，不标成固定或结构',()=>{
 const {x,calls}=env();x.持单策略=0;x.启用积极持单=false;
 x.Open({originHash:123,direction:1,level:100,bar:9900,method:'touch',exitSL:95,exitFirst:104,exitTP:109,exitBE:103});
 assert.equal(calls.length,1);assert.equal(x.pending.fixedExit,false);assert.equal(x.pending.adaptive,false);
 assert.equal(x.pending.sl,95);assert.equal(x.pending.exitFirst,104);assert.equal(x.pending.tp,109);
});
test('固定模式标记跨pending重启并绑定真实成交，旧状态默认false',()=>{
 const e=env(),{x,memory}=e;x.持单策略=2;x.启用积极持单=false;
 x.Open({originHash:123,direction:1,level:100,bar:9900,method:'touch',exitSL:0,exitFirst:0,exitTP:0,exitBE:0});
 x.pending={};x.RestorePending();assert.equal(x.pending.fixedExit,true);
 x.pending.order=7;e.setDeals([{ticket:1,id:9,order:7,entry:0,magic:560056,symbol:'XAUUSD'}]);x.HistorySelect();
 assert(x.SaveEntryExits());assert.equal(memory['exit9.fixedExit'],1);assert.equal(memory['exit9.adaptive'],0);
 delete memory.fixedExit;x.RestorePending();assert.equal(x.pending.fixedExit,false);
});
test('持仓按已保存模式路由，固定退出在老师更新和两种持单算法之前',()=>{
 const s=body('Manage');assert(s.indexOf('ManageFixedExit')<s.indexOf('RefreshEntryExits'));
 assert(s.indexOf('ManageFixedExit')<s.indexOf('ManageAdaptive'));
 assert(!s.includes('持单策略'));assert.match(s,/Load\(key\+"fixedExit"\)==1/);
});
test('开仓保存期间权限变化不遗留虚假pending，也不调用券商',()=>{
 for(const stopAt of [2,3]){
  const {x,calls,memory}=env();let n=0;x.CanExecute=()=>++n<stopAt;
  x.MergeOpportunity=()=>{memory.shared=1;};
  x.Open({originHash:123,direction:1,level:100,bar:9900,method:'touch',exitSL:0,exitFirst:0,exitTP:0,exitBE:0});
  assert.equal(x.pending.kind,0);assert.equal(calls.length,0);
  if(stopAt===3)assert.equal(memory.shared,0);
 }
});
test('开仓意图保存失败不调用券商，保留写入中断标记',()=>{
 const {x,calls,memory}=env();x.Store=(k,v)=>{if(k==='sl'){x.stateOK=false;return false;}memory[k]=v;return true;};
 x.Open({originHash:123,direction:1,level:100,bar:9900,method:'touch',exitSL:0,exitFirst:0,exitTP:0,exitBE:0});
 assert.equal(calls.length,0);assert.equal(memory.kind,-1);assert.equal(x.stateOK,false);
});
test('开仓将当前局部交易对象交给结果记录，不读全局旧结果',()=>{
 const {x,calls}=env();let local;
 x.execution={PositionOpen:()=>{throw Error('must not use shared trade');}};
 x.CTrade=function(){local={SetExpertMagicNumber:()=>{},SetDeviationInPoints:()=>{},SetTypeFillingBySymbol:()=>{},SetAsyncMode:()=>{},PositionOpen:(...args)=>calls.push(['open',...args])};return local;};
 let recorded=false;x.RecordResult=trade=>{assert.equal(trade,local);recorded=true;};
 x.Open({originHash:123,direction:1,level:100,bar:9900,method:'touch',exitSL:0,exitFirst:0,exitTP:0,exitBE:0});
 assert(recorded);assert.equal(calls.length,1);
});
console.log(`${checks} adaptive regression checks passed`);
