// 执行生产MQL函数体；合成tick/历史/券商桩，不连接终端、不产生真实订单。
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..');
const sources=['EA_T哥点位跟单.mq5','Include/Trading/TgeAISignals.mqh','Include/Trading/TgeTeacherLimits.mqh','Include/Trading/TgeMobileMarkers.mqh'].map(p=>fs.readFileSync(path.join(root,p),'utf8'));
function body(name){
 const re=new RegExp('^(?:void|bool|int|uint|ulong|double|string) '+name+'\\(','m');
 const src=sources.find(s=>re.test(s));assert(src,name);
 const start=src.indexOf('{',src.search(re));let end=start+1,n=1;
 for(;n;end++){if(src[end]==='{')n++;if(src[end]==='}')n--;}
 return src.slice(start+1,end-1);
}
function install(x,name,args='',ref=false){
 let s=body(name).replace('static double lastPriceMin=0,lastPriceMax=0;','').replace(/CTrade (\w+);/g,'let $1=new CTrade();').replace(/\((?:int|long|uint|ulong|double|datetime|ENUM_ORDER_TYPE)\)/g,'')
 .replace(/\b(?:string|double|bool|AIPlan|MqlRates) (\w+)\[\],(\w+)\[\];/g,'let $1=[], $2=[];')
 .replace(/\b(?:string|double|bool|AIPlan|MqlRates) (\w+)\[\];/g,'let $1=[];')
 .replace(/\b(?:MqlTick|Candidate) (\w+);/g,'let $1={};')
 .replace(/\b(?:const )?(?:bool|int|uint|ulong|long|ushort|double|string|datetime|ENUM_ORDER_TYPE)\s+/g,'let ')
 .replace('TickImpact(sign,q.time_msc,speed,oneway,pullback)',
  '((v)=>{speed=v.speed;oneway=v.oneway;pullback=v.pullback;return v.ok;})(TickImpact(sign,q.time_msc))')
 .replace('PositionVolumes(id,initial,closed)','((v)=>{initial=v.initial;closed=v.closed;return v.ok;})(PositionVolumes(id))');
 if(name==='Number')s=s.replace(/c([<>=!]+)'(.)'/g,(_,op,c)=>'c'+op+c.charCodeAt(0));
 if(ref)s=s.replace(/return false;/g,'return {ok:false,speed,oneway,pullback};').replace(/return true;/g,'return {ok:true,speed,oneway,pullback};');
 vm.runInContext(`function ${name}(${args}){${s}}`,x);
}
function plan(o={}){const confirmed=o.confirmed??990;const mode=o.mode??'REACTION';return {id:'direct-a',kind:'DIRECT',priority:8,sign:1,approach:0,level:4175,source:'teacher-a',created:confirmed,confirmed,expires:confirmed+(mode==='MARKET'?180:86400),evidenceCount:1,feedState:'READY',feedNote:'',sleeping:false,hardStopped:false,brokenAt:0,pierceUntil:0,structureUntil:0,loggedLife:'',mode,group:'one',lifeReason:'',sl:0,first:0,tp:0,breakeven:0,status:'',...o};}
function env(options={}){
 let now=1000;const memory=options.memory||{},calls=[];
 const x=vm.createContext({
   入场策略:0,TGE_ENTRY_COMPAT:0,TGE_ENTRY_TOUCH:1,TGE_ENTRY_ADAPTIVE:2,启用积极持单:false,adaptiveATR:0,持单策略:0,TGE_HOLD_FIXED:2,启用点位结构失效:false,点位破位缓冲ATR倍数:.25,点位破位确认根数:2,点位刺穿冷却秒数:60,点位破位冷却秒数:180,
  aiPlans:options.plans||[plan()],aiReady:true,aiGenerated:now,aiReason:'',aiMode:'SETUP',identity:'',aiIdentity:'TGA6',aiSource:'',aiSourceTime:990,
  DIRECT_MAX_AGE:86400,MARKET_MAX_AGE:180,healthOK:true,healthPaused:false,healthBeat:now,healthSync:now,healthCheckpoint:now,healthMaxAge:120,读取AI即时策略:true,
   每次开仓手数:.02,最大同时持仓:3,最大点差价格:.5,挂单最大离价:50,保险价格距离:10,首批止盈价格距离:5,尾仓目标价格距离:10,连亏区域冷却分钟:30,
  允许同机会重入:true,TEACHER_BAND:1,REARM_DISTANCE:4,REARM_SECONDS:5,冲击短窗毫秒:3000,逆向冲击速度:.6,冲击单向比例:.85,恢复回拉价格:.35,
  reason:'',entryView:{},pending:{kind:0},levels:[],sourceTime:0,sourceKind:'',sourceSender:'',feedStatus:'',feedTime:0,feedActive:false,
   fastTicks:Array.from({length:256},()=>({})),fastCount:0,fastCursor:0,fastLast:0,fastStarted:0,sharedVisits:[],teacherLimits:Array.from({length:4},()=>({state:0})),adaptiveBars:Array.from({length:16},(_,i)=>({time:900-i*60,open:4175,close:4175,low:4174,high:4176})),adaptiveATR:1,adaptiveMarketReady:true,adaptiveMarketAt:now,adaptiveHistoryReady:true,adaptiveHistoryDirty:false,adaptiveResults:[],AdaptiveMarketFresh:()=>true,
  TickSize:()=>.01,TimeCurrent:()=>now,TimeGMT:()=>now,MathMax:Math.max,MathMin:Math.min,MathAbs:Math.abs,MathIsValidNumber:Number.isFinite,
  DBL_MAX:Number.MAX_VALUE,_Digits:2,_Symbol:'XAUUSD.c',EA魔法号:560056,
  Hash:s=>{let h=2166136261;for(const c of s)h=Math.imul(h^c.charCodeAt(0),16777619)>>>0;return h;},
  IntegerToString:String,DoubleToString:(n,d)=>n.toFixed(d),StringLen:s=>s.length,StringGetCharacter:(s,n)=>s.charCodeAt(n),
  StringToInteger:Number,StringToDouble:Number,StringSplit:(s,sep,out)=>{out.splice(0,out.length,...s.split(sep));return out.length;},
  StringFind:(s,t)=>s.indexOf(t),StringSubstr:(s,n)=>s.slice(n),ArraySize:a=>a.length,ArrayResize:(a,n)=>{while(a.length<n)a.push({});a.length=n;},
  ArrayCopy:(a,b)=>a.splice(0,a.length,...b),ArraySort:a=>a.sort((a,b)=>a-b),
  lastPriceMin:0,lastPriceMax:0,CHART_PRICE_MIN:1,CHART_PRICE_MAX:2,ChartGetDouble:(id,k)=>k===1?4100:4200,Load:k=>memory[k]||0,Store:(k,v)=>{memory[k]=v;return true;},GlobalVariablesFlush:()=>{},DrawLevels:()=>{},ReplayAccepted:()=>{},Print:()=>{},
  ZeroMemory:p=>{for(const k of Object.keys(p))delete p[k];Object.assign(p,{kind:0,exitSL:0,exitFirst:0,exitTP:0,exitBE:0,valid:false});},
  FreshQuote:q=>Object.assign(q,{bid:4174.9,ask:4175,time_msc:now*1000}),
  CanExecute:()=>true,ExecutionBlock:()=>'',ExactLot:()=>true,Align:v=>v,Stops:()=>true,
  OrderCalcMargin:()=>true,AccountInfoDouble:()=>1000,ACCOUNT_MARGIN_FREE:1,ORDER_TYPE_BUY:1,ORDER_TYPE_SELL:2,
  SavePending:()=>true,DecisionLog:()=>{},EntryTag:()=>'TGsynthetic',RecordResult:()=>{},
  PositionSelectByTicket:()=>true,OwnSelected:()=>true,LimitEntryPending:()=>false,OrdersTotal:()=>0,PositionsTotal:()=>0,
  POSITION_VOLUME:'volume',POSITION_IDENTIFIER:'id',POSITION_TIME:'time',POSITION_TYPE:'type',POSITION_TYPE_BUY:0,
  POSITION_PRICE_OPEN:'open',POSITION_SL:'sl',POSITION_TP:'tp',POSITION_COMMENT:'comment',
  SymbolInfoDouble:()=>.01,SYMBOL_VOLUME_MIN:1,LotDown:v=>Math.floor(v*100+1e-7)/100,
  PERIOD_M1:1,PERIOD_M5:5,ArraySetAsSeries:()=>{},
  ExplicitReject:()=>false,PrintFormat:()=>{},HistoryDealSelect:()=>false,
  CTrade:function(){return {
    SetExpertMagicNumber:()=>{},SetDeviationInPoints:()=>{},SetTypeFillingBySymbol:()=>{},SetAsyncMode:()=>{},
    PositionOpen:(...a)=>calls.push(['open',...a]),
    PositionClose:(...a)=>{calls.push(['close',...a]);return true;},
    PositionClosePartial:(...a)=>{calls.push(['partial',...a]);return true;},
    ResultRetcode:()=>10009,ResultOrder:()=>700,ResultDeal:()=>0,ResultComment:()=>'synthetic'
  };},
  execution:{PositionOpen:(...a)=>calls.push(['open',...a]),PositionClose:(...a)=>calls.push(['close',...a]),PositionClosePartial:(...a)=>calls.push(['partial',...a])},
  INVALID_HANDLE:-1,CP_UTF8:65001,FILE_READ:1,FILE_TXT:2,FILE_ANSI:4,FILE_COMMON:8,FILE_SHARE_READ:16,
 });
 for(const [name,args,ref] of [
 ['Number','text,decimal=false'],['AIChannelReady',''],['InvalidAI','why'],['ReadAISetups',''],
 ['RememberFastTick','q'],['TickImpact','sign,now',true],['AIKeyFromHash','hash,level,sign'],
 ['SharedVisitKey','level,sign'],['SameOpportunity','sign,level'],['RememberSharedVisit','level,sign'],['UpdateSharedVisit','q'],['MergeOpportunity','sign,level'],
  ['PlanLifeKey','i'],['PlanLifeReason','i'],['PlanExecutable','i'],['StopPlanReference','i,why'],['RefreshPlanValidity','q,quoteOK,persist=false'],['RefreshPointStructure',''],['InTeacherBand','entry,level'],['PlanSign','i'],['PlanNear','i,q'],['ZonePriority','q'],['UpdateTeacherVisits','q'],['EffectiveEntryMethod',''],['EntrySourceReason','i'],['UnifiedEntryStatus','i,q,method,live'],['TeacherEntryAllowed','i,q'],
 ['AIMarketSignal','out'],['Open','signal'],['ExitCandles','bars,sign,opened,period,now'],['ExitRhythm','sign,opened'],
 ['ExitKey','id'],['FirstExit','id,sign,open,tp'],['PartialRemaining','initial,closed,remaining'],['RefreshEntryExits','key,sign'],['RequestExit','ticket,id,volume,full,why'],['Manage',''],['LegacyLimitsClear','']])install(x,name,args,ref);
 return {x,memory,calls,setNow:n=>now=n};
}
function ticks(x,prices,sign=1){
 const end=x.TimeGMT()*1000;
 prices.forEach((p,i)=>x.RememberFastTick({time_msc:end-(prices.length-1-i)*400,bid:sign>0?p-.1:p,ask:sign>0?p:p+.1}));
 const p=prices.at(-1);x.FreshQuote=q=>Object.assign(q,{bid:sign>0?p-.1:p,ask:sign>0?p:p+.1,time_msc:end});
}
let checks=0;function test(n,f){f();checks++;console.log('PASS '+n);}
for(const sign of [1,-1])for(const gap of [-1,1,-1.001,1.001])test(`触价边界 ${sign}/${gap}`,()=>{
 const {x}=env({plans:[plan({sign})]});ticks(x,Array(4).fill(4175+gap),sign);assert.equal(x.AIMarketSignal({}),Math.abs(gap)<=1);
});
test('入场和持单独立选择，提交前复核使用相同入场方式',()=>{
 const e=env();ticks(e.x,[4175,4175,4175,4175]);let checks=0;
 e.x.AdaptiveEntryStatus=()=>{checks++;return 'M1确认候选';};
 e.x.入场策略=2;const c={};assert(e.x.AIMarketSignal(c));e.x.Open(c);
 assert(checks>=2);assert.equal(e.calls[0][0],'open');assert.equal(e.x.pending.adaptive,false);
 const t=env();ticks(t.x,[4175,4175,4175,4175]);t.x.入场策略=1;t.x.启用积极持单=true;
 t.x.AdaptiveEntryStatus=()=>{throw Error('触价模式不调用入场行情检查');};assert(t.x.AIMarketSignal({}));
});
test('地图从上方跌向下沿做多，不等M1',()=>{const {x}=env({plans:[plan({kind:'MAP',priority:5,sign:0})]});x.UpdateTeacherVisits({bid:4179,ask:4179.1});ticks(x,[4175.8,4175.8,4175.7,4175.7]);const c={};assert(x.AIMarketSignal(c));assert.equal(c.direction,1);});
test('地图从下方涨向上沿做空',()=>{const {x}=env({plans:[plan({kind:'MAP',priority:5,sign:0})]});x.UpdateTeacherVisits({bid:4171,ask:4171.1});ticks(x,[4174.2,4174.3,4174.3,4174.4],-1);const c={};assert(x.AIMarketSignal(c));assert.equal(c.direction,-1);});
test('启动已在地图带内，不猜接近方向',()=>{const {x}=env({plans:[plan({kind:'MAP',priority:5,sign:0})]});ticks(x,[4175,4175,4175,4175]);assert(!x.AIMarketSignal({}));});
test('8优先于6和5；区间不覆盖老师相反明确方向',()=>{
 const {x}=env({plans:[plan({id:'map',kind:'MAP',priority:5,sign:0,approach:1}),plan({id:'range',kind:'INNER',priority:6}),plan({id:'direct',sign:-1})]});
 ticks(x,[4175,4175,4175,4175]);const c={};assert(x.AIMarketSignal(c));assert.equal(c.direction,-1);assert.equal(c.originHash,x.Hash('direct'));
});
test('远处8不阻塞附近6',()=>{const {x}=env({plans:[plan({level:4193}),plan({id:'range',kind:'INNER',priority:6})]});ticks(x,[4175,4175,4175,4175]);const c={};assert(x.AIMarketSignal(c));assert.equal(c.originHash,x.Hash('range'));});
test('同级相反且重叠区域不发双向单',()=>{const {x}=env({plans:[plan(),plan({id:'other',sign:-1})]});ticks(x,[4175,4175,4175,4175]);assert(!x.AIMarketSignal({}));assert.match(x.reason,/冲突/);});
test('逆向直线冲穿暂停，反弹恢复才可入场',()=>{const {x}=env();ticks(x,[4177,4176.5,4176,4175]);assert(!x.AIMarketSignal({}));x.fastCount=0;x.fastCursor=0;x.fastLast=0;ticks(x,[4176,4175,4174.5,4175]);assert(x.AIMarketSignal({}));});
test('普通短暂波动不要求EMA或K线确认',()=>{const {x}=env();ticks(x,[4175.3,4175.1,4175.2,4175.1]);assert(x.AIMarketSignal({}));});
test('一次触价只发0.02，重启复用消费不重单',()=>{const e=env();ticks(e.x,[4175,4175,4175,4175]);let c={};assert(e.x.AIMarketSignal(c));e.x.Open(c);assert.equal(e.calls.length,1);assert.equal(e.calls[0][3],.02);assert(!e.x.AIMarketSignal({}));const r=env({memory:e.memory});ticks(r.x,[4175,4175,4175,4175]);assert(!r.x.AIMarketSignal({}));});
test('消费后离开4点不足5秒不能重入，满5秒才解除',()=>{
 const {x,setNow}=env();x.MergeOpportunity(1,4175);x.UpdateSharedVisit({bid:4179,ask:4179.1});setNow(1004);x.UpdateSharedVisit({bid:4179,ask:4179.1});assert(x.SameOpportunity(1,4175));setNow(1005);x.UpdateSharedVisit({bid:4179,ask:4179.1});assert(!x.SameOpportunity(1,4175));
});
test('QUOTE断线、点差过大、陈旧健康状态均不入场',()=>{
 for(const stop of [x=>x.FreshQuote=()=>false,x=>x.最大点差价格=.01,x=>x.healthSync=1,x=>x.healthPaused=true]){
 const {x}=env();ticks(x,[4175,4175,4175,4175]);stop(x);assert(!x.AIMarketSignal({}));}
});
test('提交前价格离开±1则不发单',()=>{const {x,calls}=env();ticks(x,[4175,4175,4175,4175]);const c={};assert(x.AIMarketSignal(c));x.FreshQuote=q=>Object.assign(q,{bid:4178,ask:4178.1});x.Open(c);assert.equal(calls.length,0);});
test('有旧挂单等待迁移，绝不混用旧限价和新触价',()=>{const {x}=env();assert(x.LegacyLimitsClear());x.teacherLimits[0].state=3;assert(!x.LegacyLimitsClear());});
for(const sign of [1,-1])test(`M5干净与夹杂反向、十字 ${sign}`,()=>{
 const {x}=env();const clean=[{time:300,open:100,close:100+sign},{time:600,open:101,close:101+sign}];
 assert.equal(x.ExitCandles(clean,sign,300,300,900),1);
 assert.equal(x.ExitCandles([...clean,{time:900,open:102,close:102-sign}],sign,300,300,1200),0);
 assert.equal(x.ExitCandles([{time:300,open:100,close:100}],sign,300,300,600),0);
 assert.equal(x.ExitCandles(clean,sign,800,300,900),-1);
});
function position(e,{mode=1,closed=0,profit=5,sl=4165,sign=1}={}){
 const p={id:12,time:100,open:4175,sl,tp:4175+sign*10,volume:.02-closed,type:sign>0?0:1};
 e.x.PositionsTotal=()=>1;e.x.PositionGetTicket=()=>123;e.x.PositionGetInteger=k=>p[k];e.x.PositionGetDouble=k=>p[k];e.x.PositionGetString=()=>'';
 e.x.PositionVolumes=()=>({ok:true,initial:.02,closed});e.x.ExitRhythm=()=>mode;
 e.x.FreshQuote=q=>Object.assign(q,{bid:sign>0?4175+profit:4175-profit-.1,ask:sign>0?4175+profit+.1:4175-profit});
 e.x.Modify=(...a)=>{e.calls.push(['modify',...a]);e.x.pending.kind=3;};return p;
}
test('5点干净M5减半，提交阶段不标为已保护',()=>{const e=env();position(e);e.x.Manage();assert.equal(e.calls[0][0],'partial');assert.equal(e.calls[0][2],.01);assert.equal(e.x.pending.kind,2);assert(!e.calls.some(c=>c[0]=='modify'));});
test('5点犹豫M5全平',()=>{const e=env();position(e,{mode:0});e.x.Manage();assert.equal(e.calls[0][0],'close');});
test('快速盈利且M1顺畅继续持有，M1转犹豫即退出',()=>{const e=env();position(e,{mode:2});e.x.Manage();assert.equal(e.calls.length,0);position(e,{mode:0,profit:4});e.x.Manage();assert.equal(e.calls[0][0],'close');});
test('减半实际Deal确认后余仓请求保本',()=>{const e=env();position(e,{closed:.01});e.x.Manage();assert.equal(e.calls[0][0],'modify');assert.equal(e.calls[0][4],4175);});
test('保本距离不合法退出余仓，避免仍承担原10点风险',()=>{const e=env();position(e,{closed:.01,profit:.1});e.x.Stops=()=>false;e.x.Manage();assert.equal(e.calls[0][0],'close');});
test('已减半已保本不重复分批',()=>{const e=env();position(e,{closed:.01,sl:4175});e.x.Manage();assert.equal(e.calls.length,0);});
test('未到5点不减仓，断线不发管理请求',()=>{const e=env();position(e,{profit:4.9});e.x.Manage();assert.equal(e.calls.length,0);e.x.FreshQuote=()=>false;e.x.Manage();assert.equal(e.calls.length,0);});
test('补充统一目标只修改原计划持仓，不生成新机会',()=>{const e=env({plans:[plan({tp:4190})]});position(e,{profit:3});e.memory['exit12.origin']=e.x.Hash('direct-a');e.memory['exit12.ready']=1;e.x.Manage();assert.equal(e.calls[0][0],'modify');assert.equal(e.calls[0][5],4190);assert(!e.calls.some(c=>c[0]==='open'));});
test('其他计划的目标不串到已有持仓',()=>{const e=env({plans:[plan({id:'other',tp:4190})]});position(e,{profit:3});e.memory['exit12.origin']=e.x.Hash('direct-a');e.memory['exit12.ready']=1;e.x.Manage();assert.equal(e.calls.length,0);});
test('断流时离区计时清零，停机时间不算重新触价',()=>{const {x}=env();x.MergeOpportunity(1,4175);x.sharedVisits[0].left=990;x.fastLast=900000;x.RememberFastTick({time_msc:1000000,bid:4179,ask:4179.1});assert.equal(x.sharedVisits[0].left,0);});
// 由真实Python导出函数构造合成快照，送入生产MQL读取函数。
const csv=require('node:child_process').execFileSync('python',['-X','utf8','-c',
 'from test_execution_feed import ExecutionTests; import csv,io; t=ExecutionTests(); t.setUp(); t.c["symbols"][t.c["teacher_symbol"]]="XAUUSD.c"; t.scene(); t.feed(); rows=list(csv.reader(io.StringIO((t.home/\"common/FeishuMT5SignalMonitor/tge_execution_v9.csv\").read_text(encoding=\"utf-8\")))); s=io.StringIO(newline=""); w=csv.writer(s,lineterminator="\\n"); w.writerows(rows); print(s.getvalue(),end=""); t.tearDown()'],
 {cwd:path.join(root,'FeishuSignalMonitor'),encoding:'utf8'}).trim().split(/\r?\n/);
function file(x,lines){let at=0;x.FileOpen=()=>1;x.FileSize=()=>lines.join('\n').length;x.FileIsEnding=()=>at>=lines.length;x.FileReadString=()=>lines[at++];x.FileClose=()=>{};}
test('Python TGA9 -> MQL读取生命周期字段与优先级',()=>{const {x,setNow}=env();setNow(Number(csv[0].split(',')[2]));file(x,csv);assert(x.ReadAISetups());assert.equal(x.aiPlans.length,5);assert.equal(x.aiPlans.filter(p=>[90,95,100].includes(p.priority)).length,2);assert(x.aiPlans.every(p=>p.expires>p.confirmed&&p.evidenceCount>=1));});
test('重复心跳更新新鲜度但内容不变不重画点位线',()=>{
 const {x,setNow}=env();setNow(Number(csv[0].split(',')[2]));let draws=0;x.DrawLevels=()=>draws++;
 file(x,csv);assert(x.ReadAISetups());file(x,csv);assert(x.ReadAISetups());assert.equal(draws,1);
 x.ChartGetDouble=(id,k)=>k===1?4090:4200;file(x,csv);assert(x.ReadAISetups());assert.equal(draws,2);
 const paused=csv.map((r,i)=>{if(i!==0)return r;const f=r.split(',');f[3]='0';return f.join(',');});
 file(x,paused);assert(x.ReadAISetups());assert.equal(draws,3);
});
test('截断、错品种、错优先级快照停用且不替换旧计划',()=>{
 for(const lines of [csv.slice(0,-1),csv.map((r,i)=>i===0?r.replace('XAUUSD','EURUSD'):r),csv.map((r,i)=>i===1?r.replace(/DIRECT,(90|95|100)/,'DIRECT,70'):r)]){
 const {x,setNow}=env();setNow(Number(csv[0].split(',')[2]));file(x,lines);assert(!x.ReadAISetups());assert(!x.aiReady);assert.equal(x.aiPlans[0].id,'direct-a');}
});
test('完整空快照替换取消，不保留旧活动方向',()=>{const {x}=env();file(x,['TGA,9,1000,1,XAUUSD.c,0,已取消','END,0']);assert(x.ReadAISetups());assert.equal(x.aiPlans.length,0);});

test('即时计划24小时边界过期，引用仍保留且不抢低优先级',()=>{
 const e=env({plans:[plan({created:1,confirmed:1}),plan({id:'map',kind:'MAP',priority:5,sign:0,approach:1,confirmed:1,created:1,expires:172801})]});
 e.setNow(86401);for(const k of ['aiGenerated','healthBeat','healthSync','healthCheckpoint'])e.x[k]=86401;
 ticks(e.x,[4175,4175,4175,4175]);const c={};assert(e.x.AIMarketSignal(c));assert.equal(c.originHash,e.x.Hash('map'));
  assert.equal(e.x.aiPlans.length,2);assert.match(e.x.aiPlans[0].status,/期限/);
});
test('时间正常但距离超过50进入休眠，回近后可重新评估',()=>{
  const e=env();e.x.RefreshPlanValidity({bid:4226,ask:4226.1},true);assert(!e.x.PlanExecutable(0));
  assert.match(e.x.PlanLifeReason(0),/休眠/);ticks(e.x,[4175,4175,4175,4175]);assert(e.x.AIMarketSignal({}));
  const r=env({memory:e.memory});ticks(r.x,[4175,4175,4175,4175]);assert(r.x.AIMarketSignal({}));
  r.x.aiPlans[0].confirmed=1001;r.setNow(1002);ticks(r.x,[4175,4175,4175,4175]);assert(r.x.AIMarketSignal({}));
 });
test('距离恰好50不过期，51过期；SELL使用bid',()=>{
 const e=env({plans:[plan({sign:-1})]});e.x.RefreshPlanValidity({bid:4225,ask:4225.1},true);assert(e.x.PlanExecutable(0));
 e.x.RefreshPlanValidity({bid:4226,ask:4226.1},true);assert(!e.x.PlanExecutable(0));
});
test('整张地图内部远端点不失效，离开整体50进入休眠，回近后整组恢复',()=>{
 const e=env({plans:[4150,4160,4175,4190,4200,4220].map(p=>plan({id:'m'+p,kind:'MAP',priority:5,sign:0,level:p,group:'map',created:1,confirmed:1}))});
 e.x.RefreshPlanValidity({bid:4210,ask:4210.1},true);assert(e.x.aiPlans.every((_,i)=>e.x.PlanExecutable(i)));
 e.x.RefreshPlanValidity({bid:4271,ask:4271.1},true);assert(e.x.aiPlans.every((_,i)=>!e.x.PlanExecutable(i)));
  e.x.RefreshPlanValidity({bid:4175,ask:4175.1},true);assert(e.x.aiPlans.every((_,i)=>e.x.PlanExecutable(i)));
});
test('新区间确认独立刷新；各点回近后按当前行情重新评估',()=>{
 const e=env({plans:[plan({id:'direct'}),plan({id:'range',kind:'INNER',priority:6,group:'r',level:4175}),plan({id:'range2',kind:'INNER',priority:6,group:'r',level:4200,sign:-1})]});
 e.x.RefreshPlanValidity({bid:4251,ask:4251.1},true);assert(!e.x.PlanExecutable(0));assert(!e.x.PlanExecutable(1));
 e.x.aiPlans[1].confirmed=1001;e.setNow(1002);e.x.RefreshPlanValidity({bid:4175,ask:4175.1},true);
  assert(e.x.PlanExecutable(0));assert(e.x.PlanExecutable(1));assert(e.x.PlanExecutable(2));
});
test('坏报价/同步断开/异常点差不写永久失效记录',()=>{
 for(const mode of ['quote','health','spread']){
 const e=env();if(mode==='health')e.x.healthOK=false;
 e.x.RefreshPlanValidity({bid:4300,ask:mode==='spread'?4400:4300.1},mode!=='quote');
 assert.equal(Object.keys(e.memory).length,0);
 }
});
test('明确止损被触及时停止新单，但不发平仓或改单请求',()=>{
 const e=env({plans:[plan({sl:4165})]});e.x.RefreshPlanValidity({bid:4165,ask:4165.1},true);
 assert.match(e.x.PlanLifeReason(0),/止损/);assert.equal(e.calls.length,0);
 ticks(e.x,[4175,4175,4175,4175]);assert(!e.x.AIMarketSignal({}));
});
test('过期相反方向不造成同级冲突，近期同价计划正常',()=>{
 const e=env({plans:[plan({sign:-1,created:1,confirmed:1}),plan({id:'new',created:99990,confirmed:99990})]});e.setNow(100000);
 for(const k of ['aiGenerated','healthBeat','healthSync','healthCheckpoint'])e.x[k]=100000;
 ticks(e.x,[4175,4175,4175,4175]);const c={};assert(e.x.AIMarketSignal(c));assert.equal(c.direction,1);
});
test('市价提示仍仅3分钟；不延长为24小时',()=>{
 const e=env({plans:[plan({mode:'MARKET',created:820,confirmed:820})]});ticks(e.x,[4175,4175,4175,4175]);
 assert(!e.x.AIMarketSignal({}));assert.match(e.x.PlanLifeReason(0),/期限/);
});
test('提交前恰好到期阻断；已有仓位继续原分批管理',()=>{
 const e=env({plans:[plan({created:1,confirmed:1})]});ticks(e.x,[4175,4175,4175,4175]);const c={};assert(e.x.AIMarketSignal(c));
 e.setNow(86401);for(const k of ['aiGenerated','healthBeat','healthSync','healthCheckpoint'])e.x[k]=86401;
 ticks(e.x,[4175,4175,4175,4175]);e.x.Open(c);assert.equal(e.calls.length,0);
 position(e);e.x.Manage();assert.equal(e.calls[0][0],'partial');
});
test('篡改重申为未来/早于原消息、旧协议都拒绝',()=>{
  for(const lines of [csv.map((r,i)=>i===0?r.replace('TGA,9','TGA,8'):r),csv.map((r,i)=>{if(i!==1)return r;const a=r.split(',');a[14]=Number(csv[0].split(',')[2])+100;return a.join(',');}),
 csv.map((r,i)=>{if(i!==1)return r;const a=r.split(',');a[14]=1;return a.join(',');})]){
 const {x,setNow}=env();setNow(Number(csv[0].split(',')[2]));file(x,lines);assert(!x.ReadAISetups());
 }
});


// 手机TP：执行生产同步函数，所有券商动作均为本地桩。
function markerEnv(){
 const e=env(),x=e.x;
 Object.assign(x,{
  markerDirty:true,markerLastMs:0,markerStatus:'',markerUnexpectedPosition:false,
  tradeMode:true,markerLock:1,启用真实交易:true,启用手机标记挂单:true,uiMobileMarkers:true,
  手机标记挂单Magic:910406,手机标记挂单固定价格:100,TGE_MARKER_VOLUME:.01,TGE_MARKER_DANGER:20,
  GetTickCount64:()=>10000,TgeMarkerCanRequest:()=>true,ReconcileTgeMarkerCreation:()=>true,
  TgeMarkerHasOtherTrade:()=>false,ReconcileMobileMarkerDeletes:()=>true,
  CancelTgeMobileMarkers:()=>e.calls.push(['cancel']),
  SubmitTgeMobileMarker:(price,target)=>{e.calls.push(['marker',price,target]);return true;},
  SymbolInfoInteger:()=>1,SYMBOL_TRADE_STOPS_LEVEL:0,_Point:.01,
  SYMBOL_ORDER_MODE:1,SYMBOL_ORDER_LIMIT:1,SYMBOL_EXPIRATION_MODE:2,SYMBOL_EXPIRATION_GTC:1,
  NormalizeDouble:v=>v,MathRound:Math.round,ArrayInitialize:(a,v)=>a.fill(v),
  StringFormat:(s,...args)=>s.replace(/%d/g,()=>args.shift())
 });
 install(x,'SyncTgeMobileMarkers');return e;
}
test('执行暂停仍展示地图和方向点位，不发送策略开仓',()=>{
 const e=markerEnv();e.x.aiReady=false;e.x.feedActive=false;e.x.healthPaused=true;
 e.x.levels=[4150,4160];e.x.SyncTgeMobileMarkers();
 assert.deepEqual(e.calls,[['marker',100,4150],['marker',100,4160],['marker',100,4175]]);
});
test('只有方向点位、没有地图，手机展示也可同步',()=>{
 const e=markerEnv();e.x.aiReady=false;e.x.SyncTgeMobileMarkers();
 assert.deepEqual(e.calls,[['marker',100,4175]]);
});
test('快照读取失败保留最后已校验展示点位；策略继续阻断',()=>{
 const e=markerEnv();e.x.InvalidAI('坏快照');e.x.SyncTgeMobileMarkers();
 assert.deepEqual(e.calls,[['marker',100,4175]]);assert(!e.x.AIChannelReady());
});
test('已校验空快照撤掉旧标记，报告等待点位',()=>{
 const e=markerEnv();e.x.aiPlans=[];e.x.aiMode='WAIT';e.x.SyncTgeMobileMarkers();
 assert.deepEqual(e.calls,[['cancel']]);assert.equal(e.x.markerStatus,'等待已校验点位');
});
test('手机开关关闭仍撤标记，不重新补发',()=>{
 const e=markerEnv();e.x.uiMobileMarkers=false;e.x.SyncTgeMobileMarkers();
 assert.deepEqual(e.calls,[['cancel']]);assert.equal(e.x.markerStatus,'手机TP开关已关闭');
});
test('真实持仓或交易请求期间仍不挂提示单',()=>{
 for(const pending of [false,true]){
  const e=markerEnv();if(pending)e.x.pending.kind=1;else e.x.TgeMarkerHasOtherTrade=()=>true;
  e.x.SyncTgeMobileMarkers();assert.deepEqual(e.calls,[['cancel']]);
  assert.equal(e.x.markerStatus,pending?'交易请求待确认':'已有交易，标记已撤');
 }
});
test('交易权限关闭或报价失效时不发送标记请求',()=>{
 for(const mode of ['permission','quote']){
  const e=markerEnv();if(mode==='permission')e.x.TgeMarkerCanRequest=()=>false;else e.x.FreshQuote=()=>false;
  e.x.SyncTgeMobileMarkers();assert.equal(e.calls.length,0);
  assert.equal(e.x.markerStatus,mode==='permission'?'等待交易权限/状态':'等待新鲜报价，不创建标记');
 }
});

console.log(`${checks} checks passed (synthetic, no broker orders)`);
