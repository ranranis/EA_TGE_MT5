// Execute extracted production MQL functions with synthetic ticks and broker mocks.
// No terminal, live orders, real signals or claimed profit backtest.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'../..');
const main=fs.readFileSync(path.join(root,'EA_T哥点位跟单.mq5'),'utf8');
const extra=fs.readFileSync(path.join(root,'Include/Trading/TgeAISignals.mqh'),'utf8');
function body(name){
 const src=[main,extra].find(s=>new RegExp('^(?:bool|void|double|int|string|ulong) '+name+'\\(','m').test(s));assert(src,name);
 const at=src.search(new RegExp('^(?:bool|void|double|int|string|ulong) '+name+'\\(','m')),start=src.indexOf('{',at);
 let end=start+1,depth=1;for(;depth;end++){if(src[end]==='{')depth++;if(src[end]==='}')depth--;}
 return src.slice(start+1,end-1);
}
function translate(s){
 return s.replace(/\((?:uint|double|long|ulong|int|datetime|ENUM_ORDER_TYPE)\)/g,'')
  .replace(/\bstring (\w+)\[\],(\w+)\[\],(\w+)\[\];/g,'let $1=[], $2=[], $3=[];')
  .replace(/\bstring (\w+)\[\],(\w+)\[\];/g,'let $1=[], $2=[];')
  .replace(/\b(?:string|AIPlan|FollowMember) (\w+)\[\];/g,'let $1=[];')
  .replace(/\b(?:MqlTick|MqlRates|Candidate) (\w+);/g,'let $1={exitSL:0,exitFirst:0,exitTP:0,exitBE:0};')
  .replace(/\b(?:double|long|int|bool|datetime|string|uint|ulong|ENUM_ORDER_TYPE)\s+/g,'let ')
  .replace(/!TickImpact\(aiPlans\[i\].sign,q.time_msc,speed,oneway,pullback\)/g,
   '!((r)=>{speed=r.speed;oneway=r.oneway;pullback=r.pullback;return r.ok;})(TickImpact(aiPlans[i].sign,q.time_msc))')
  .replace(/!Target\((aiPlans\[i\].sign>0 \? q.ask : q.bid),aiPlans\[i\].sign,tp,false,aiPlans\[i\].level\)/g,
   '!((r)=>{tp=r.tp;return r.ok;})(Target($1,aiPlans[i].sign,false,aiPlans[i].level))')
  .replace(/targetOK=Target\(entry,sign,tp,!signal.ai,signal.ai \? signal.level : 0\)/g,
   'targetOK=((r)=>{tp=r.tp;return r.ok;})(Target(entry,sign,!signal.ai,signal.ai ? signal.level : 0))');
}
function install(x,name,args='',ref=false){
 let s=translate(body(name));
 if(ref)s=s.replace(/return false;/g,'return {ok:false,speed,oneway,pullback};').replace(/return true;/g,'return {ok:true,speed,oneway,pullback};');
 if(name==='Manage')s=s.replace('PositionVolumes(id,initial,closed)','((r)=>{initial=r.initial;closed=r.closed;return r.ok;})(PositionVolumes(id))');
 if(name==='MapReaction')s=s.replace('!Target(entry,sign,tp,true)','!Target(entry,sign,true).ok');
 if(name==='Target')s='let tp=0;'+s.replace(/return false;/g,'return {ok:false,tp};').replace(/return true;/g,'return {ok:true,tp};');
 vm.runInContext('function '+name+'('+args+'){'+s+'}',x);
}
let checks=0;function test(name,fn){fn();checks++;console.log('PASS '+name);}
function env(options={}){
 const memory=options.memory||{},calls=[],now=options.now||1000;
 const x=vm.createContext({
  TEACHER_BAND:2,REARM_DISTANCE:4,REARM_SECONDS:5,冲击短窗毫秒:3000,逆向冲击速度:.6,冲击单向比例:.85,恢复回拉价格:.35,
  允许同机会重入:true,允许地图趋势过滤:true,启用真实交易:true,读取AI即时策略:true,启用起飞跟随:true,启用其他学生跟随:true,起飞最大追价价格差:2,
  首批止盈价格距离:5,保险价格距离:10,尾仓目标价格距离:10,每次开仓手数:.02,最大点差价格:.5,
  aiReady:true,aiMode:'SETUP',aiIdentity:'teacher',aiSource:'teacher',aiGenerated:now,aiSourceTime:now-10,
  aiPlans:options.plans||[{sign:1,level:4175,market:false,origin:'buy-source|rev|SETUP',created:now-10,status:'',left:0}],
  aiReason:'',levels:[4105,4120,4170,4193],entryView:{},reason:'',_Digits:2,_Symbol:'XAUUSD',checkingMinute:0,
  pending:{kind:0},followMembers:[],followIndex:-1,followReady:true,followGenerated:now,followReason:'',sharedVisits:[],
  fastTicks:Array.from({length:256},()=>({})),fastCount:0,fastCursor:0,fastLast:0,fastStarted:0,DBL_MAX:Number.MAX_VALUE,
  Hash:s=>{let h=2166136261;for(const ch of s)h=Math.imul(h^ch.charCodeAt(0),16777619)>>>0;return h;},
  TickSize:()=>.01,TimeGMT:()=>now,TimeCurrent:()=>now,OwnCount:()=>0,GlobalVariablesFlush:()=>{},
  MathMax:Math.max,MathMin:Math.min,MathAbs:Math.abs,IntegerToString:String,DoubleToString:(v,n)=>v.toFixed(n),
  MathIsValidNumber:Number.isFinite,ArraySize:a=>a.length,ArrayResize:(a,n)=>{while(a.length<n)a.push({});a.length=n;},
  Load:k=>memory[k]||0,Store:(k,v)=>{memory[k]=v;return true;},ZeroMemory:p=>{for(const k of Object.keys(p))delete p[k];},
  FreshQuote:q=>Object.assign(q,{bid:4174.9,ask:4175,time_msc:now*1000}),Align:v=>v,
  Stops:()=>true,ExactLot:()=>true,CanExecute:()=>true,ExecutionBlock:()=>'',
  ORDER_TYPE_BUY:1,ORDER_TYPE_SELL:2,ACCOUNT_MARGIN_FREE:1,AccountInfoDouble:()=>10000,OrderCalcMargin:()=>true,
  EntryTag:()=>'synthetic',SavePending:()=>{},SaveEntryExits:()=>true,DecisionLog:()=>{},signalRetry:false,
  healthOK:true,healthPaused:false,healthBeat:now,healthSync:now,healthCheckpoint:now,healthMaxAge:120,
  execution:{PositionOpen:(...a)=>calls.push(a),ResultRetcode:()=>0,ResultOrder:()=>123,ResultDeal:()=>0,ResultComment:()=>''},
  PrintFormat:()=>{},HistoryDealSelect:()=>false,ExplicitReject:()=>false,ClearPending:()=>{x.pending={kind:0};},RecordResult:()=>{}
 });
 for(const [name,args,ref] of [
  ['AIChannelReady',''],['KeepCachedAI','why'],['InvalidAI','why'],['RememberFastTick','q'],['TickImpact','sign,now',true],['InTeacherBand','entry,level'],['LiveTeacherPlan','i'],
  ['TeacherOwnsZone','q'],['AIKeyFromHash','originHash,level,sign'],['AIVisitKey','level,sign'],
  ['TeacherEntryAllowed','i,q'],['UpdateTeacherVisits','q'],['AISignal','bar,q,out'],['AIMarketSignal','out'],
  ['Target','entry,sign,mapOnly=false,reference=0'],['FollowVisitKey','index=-1'],['FollowMissKey','index=-1'],
  ['FollowEnabled','i'],['FollowPriceAllowed','q,index=-1'],['SharedVisitKey','level,sign'],['SameOpportunity','sign,level'],['RememberSharedVisit','level,sign'],
  ['UpdateSharedVisit','q'],['MergeOpportunity','sign,level'],['MemberFollowSignal','out'],
  ['FollowMemberCaption','i'],['FollowCaption',''],['Open','signal']])install(x,name,args,ref);
 return {x,memory,calls};
}
function ticks(x,prices,step=400,side='BUY'){
 const end=x.TimeGMT()*1000;
 for(let i=0;i<prices.length;i++){
  const p=prices[i];x.RememberFastTick({time_msc:end-(prices.length-1-i)*step,bid:side==='BUY'?p-.1:p,ask:side==='BUY'?p:p+.1});
 }
 const p=prices.at(-1);x.FreshQuote=q=>Object.assign(q,{bid:side==='BUY'?p-.1:p,ask:side==='BUY'?p:p+.1,time_msc:end});
}
function member(id,price=4175,sign=1,source=id){return {sender:id,name:id,source,revision:'v1',price,sign,created:990,expiry:1290,ttl:300,adverse:2,ready:true,reason:''};}
for(const sign of [1,-1])for(const delta of [-2,2,-2.0001,2.0001])test('inclusive ±2 boundary sign='+sign+' delta='+delta,()=>{
 const {x}=env({plans:[{sign,level:4175,market:false,origin:'plan',created:990,left:0,status:''}]});
 ticks(x,Array(4).fill(4175+delta),400,sign>0?'BUY':'SELL');assert.equal(x.AIMarketSignal({}),Math.abs(delta)<=2);
});
test('BUY checks Ask even when Bid is inside',()=>{const {x}=env();ticks(x,Array(4).fill(4177.1));x.FreshQuote=q=>Object.assign(q,{bid:4176.9,ask:4177.1,time_msc:1000000});assert(!x.AIMarketSignal({}));});
test('SELL checks Bid even when Ask is inside',()=>{const {x}=env({plans:[{sign:-1,level:4175,market:false,origin:'s',created:990,left:0,status:''}]});ticks(x,Array(4).fill(4172.9),400,'SELL');assert(!x.AIMarketSignal({}));});
test('normal approach needs no completed candle or ATR buffer',()=>{const {x}=env();ticks(x,[4176,4175.8,4175.6,4175.4]);x.CopyRates=()=>{throw Error('must not wait candles');};x.CopyBuffer=x.CopyRates;const c={};assert(x.AIMarketSignal(c));assert(c.ai);});
test('startup insufficient samples is explicit sampling state',()=>{const {x}=env();ticks(x,[4175]);assert(!x.AIMarketSignal({}));assert(x.aiPlans[0].status.includes('采样'));});
test('three samples cannot pretend absence of impact',()=>{const {x}=env();ticks(x,[4175,4175,4175],600);assert(!x.AIMarketSignal({}));});
test('late gap restarts short sampling',()=>{const {x}=env();ticks(x,[4175,4175,4175,4175]);x.RememberFastTick({time_msc:1002000,bid:4174.9,ask:4175});assert.equal(x.fastCount,1);});
test('high frequency ticks retain at least one second of window',()=>{const {x}=env();for(let ms=0;ms<=3000;ms+=2)x.RememberFastTick({time_msc:997000+ms,bid:4174.9,ask:4175});assert(x.fastCount<256);assert(x.TickImpact(1,1000000).ok);});
test('reverse continuous downward crossing defers BUY',()=>{const {x}=env();ticks(x,[4176,4175.7,4175.4,4175.1]);assert(!x.AIMarketSignal({}));assert(x.aiPlans[0].status.includes('暂缓'));});
test('reverse continuous upward crossing defers SELL symmetrically',()=>{const {x}=env({plans:[{sign:-1,level:4175,market:false,origin:'s',created:990,left:0,status:''}]});ticks(x,[4174,4174.3,4174.6,4174.9],400,'SELL');assert(!x.AIMarketSignal({}));});
test('fast favorable movement is allowed for BUY',()=>{const {x}=env();ticks(x,[4173.5,4174,4174.5,4175]);assert(x.AIMarketSignal({}));});
test('fast favorable movement is allowed for SELL',()=>{const {x}=env({plans:[{sign:-1,level:4175,market:false,origin:'s',created:990,left:0,status:''}]});ticks(x,[4176.5,4176,4175.5,4175],400,'SELL');assert(x.AIMarketSignal({}));});
test('pullback inside band restores a deferred opportunity',()=>{
 const {x}=env();ticks(x,[4176,4175.7,4175.4,4175.1]);assert(!x.AIMarketSignal({}));
 x.TimeGMT=()=>1001;ticks(x,[4174.8,4175.2,4175.5,4175.5],400);assert(x.AIMarketSignal({}));
});
test('slowing down after short window restores without candle close',()=>{const {x}=env();ticks(x,[4176,4175.7,4175.4,4175.1]);assert(!x.AIMarketSignal({}));x.TimeGMT=()=>1004;x.aiGenerated=1004;ticks(x,Array(4).fill(4175));assert(x.AIMarketSignal({}));});
test('recovered direction outside ±2 never chases',()=>{const {x}=env();ticks(x,[4177.2,4177.3,4177.4,4177.5]);assert(!x.AIMarketSignal({}));assert(x.aiPlans[0].status.includes('离开'));});
test('spread and stale quote block immediate candidate',()=>{const {x}=env();ticks(x,Array(4).fill(4175));x.FreshQuote=q=>Object.assign(q,{bid:4174,ask:4175,time_msc:1000000});assert(!x.AIMarketSignal({}));x.FreshQuote=()=>false;assert(!x.AIMarketSignal({}));});
test('invalid source or expired transport never trades',()=>{const {x}=env();ticks(x,Array(4).fill(4175));x.aiReady=false;assert(!x.AIMarketSignal({}));x.aiReady=true;x.aiGenerated=879;assert(!x.AIMarketSignal({}));});
test('condition plan is persistent but MARKET has exact 180-second boundary',()=>{const {x}=env();ticks(x,Array(4).fill(4175));x.aiPlans[0].created=1;assert(x.AIMarketSignal({}));x.aiPlans[0].market=true;x.aiPlans[0].created=821;assert(x.AIMarketSignal({}));x.aiPlans[0].created=820;assert(!x.AIMarketSignal({}));});
test('fresh map is unnecessary for a valid explicit teacher plan',()=>{const {x}=env();ticks(x,Array(4).fill(4175));x.feedActive=false;assert(x.AIMarketSignal({}));});
test('favorable half of band does not use own reference as TP obstacle',()=>{const {x}=env();ticks(x,Array(4).fill(4173));assert(x.AIMarketSignal({}));assert.equal(x.Target(4173,1,false,4175).tp,4183);});
test('different-price dual directions are not treated as global conflict',()=>{const {x}=env();x.aiPlans.push({sign:-1,level:4193,market:false,origin:'sell',created:990,left:0,status:''});ticks(x,Array(4).fill(4175));assert(x.AIMarketSignal({}));});
test('same zone consumption survives restart and does not rearm after stop-loss',()=>{
 const {x,memory}=env();ticks(x,Array(4).fill(4175));const c={};assert(x.AIMarketSignal(c));x.Open(c);assert(x.pending.kind===1);
 const r=env({memory});ticks(r.x,Array(4).fill(4175));assert(!r.x.AIMarketSignal({}));r.x.UpdateTeacherVisits({bid:4174.9,ask:4175});assert(memory[c.aiKey]>0);
});
test('teacher requests preserve .02 and original 10/5 exit template',()=>{const {x,calls}=env();ticks(x,Array(4).fill(4175));const c={};assert(x.AIMarketSignal(c));x.Open(c);assert.equal(calls.length,1);assert.equal(calls[0][2],.02);assert.equal(calls[0][4],4165);assert.equal(calls[0][5],4185);});
test('send-time quote outside band cancels candidate',()=>{const {x,calls}=env();ticks(x,Array(4).fill(4175));const c={};assert(x.AIMarketSignal(c));x.FreshQuote=q=>Object.assign(q,{bid:4177.1,ask:4177.2,time_msc:1000000});x.Open(c);assert.equal(calls.length,0);});
test('send-time direction/source changes cancel candidate',()=>{const {x,calls}=env();ticks(x,Array(4).fill(4175));const c={};assert(x.AIMarketSignal(c));x.aiPlans[0].origin='new-source';x.Open(c);assert.equal(calls.length,0);});
test('pending confirmation blocks repeat sends',()=>{const {x,calls}=env();ticks(x,Array(4).fill(4175));const c={};assert(x.AIMarketSignal(c));x.ExecutionBlock=()=>x.pending.kind?'previous request pending':'';x.Open(c);x.Open(c);assert.equal(calls.length,1);});
test('teacher explicit rejection retries only after 5 seconds, unknown remains pending',()=>{
 const {x,memory}=env();ticks(x,Array(4).fill(4175));const c={};assert(x.AIMarketSignal(c));x.Open(c);
 install(x,'RecordResult');x.ExplicitReject=()=>true;x.RecordResult();assert.equal(x.pending.kind,0);assert.equal(memory[c.aiKey],0);assert(!x.AIMarketSignal({}));
 x.TimeGMT=()=>1005;x.aiGenerated=1005;ticks(x,Array(4).fill(4175));assert(x.AIMarketSignal({}));
});
test('leave 4.00 for 5 seconds rearms condition',()=>{
 const {x,memory}=env();const key=x.AIVisitKey(4175,1);memory[key]=990;
 x.UpdateTeacherVisits({ask:4179,bid:4178.9});x.TimeGMT=()=>1004;x.UpdateTeacherVisits({ask:4179,bid:4178.9});assert(memory[key]>0);
 x.TimeGMT=()=>1005;x.UpdateTeacherVisits({ask:4179,bid:4178.9});assert.equal(memory[key],0);
});
test('inside 4.00, disabled reentry and pending prevent rearm',()=>{
 for(const mode of ['close','disabled','pending']){const {x,memory}=env();const key=x.AIVisitKey(4175,1);memory[key]=990;if(mode==='disabled')x.允许同机会重入=false;if(mode==='pending')x.pending.kind=1;
 const q={ask:mode==='close'?4178.9:4179,bid:4178.8};x.UpdateTeacherVisits(q);x.TimeGMT=()=>1006;x.UpdateTeacherVisits(q);assert(memory[key]>0);}
});
test('MARKET cannot rearm by leaving after consumption',()=>{const {x,memory}=env();x.aiPlans[0].market=true;const key=x.AIVisitKey(4175,1);memory[key]=990;x.UpdateTeacherVisits({ask:4180,bid:4179.9});x.TimeGMT=()=>1006;x.UpdateTeacherVisits({ask:4180,bid:4179.9});assert(memory[key]>0);});
for(const sign of [1,-1])test('student adverse >=2 permanently missed, favorable allowed sign='+sign,()=>{
 const {x,memory}=env({plans:[]});x.followMembers=[member('first',4175,sign)];x.followIndex=0;
 assert(x.FollowPriceAllowed(sign>0?{ask:4173,bid:4172.9}:{bid:4177,ask:4177.1}));
 assert(!x.FollowPriceAllowed(sign>0?{ask:4177,bid:4176.9}:{bid:4173,ask:4173.1}));
 assert(!x.FollowPriceAllowed({ask:4175,bid:4175}));assert.equal(memory[x.FollowMissKey()],1);
});
test('one missed member never blocks the other member',()=>{const {x}=env({plans:[]});x.followMembers=[member('first',4170),member('second',4175)];const c={};assert(x.MemberFollowSignal(c));assert(c.method.startsWith('second'));});
test('five-minute expiry is exclusive and uses original message time',()=>{const {x}=env({plans:[]});x.followMembers=[member('first')];x.TimeGMT=()=>1289;x.followGenerated=1289;x.healthBeat=x.healthSync=x.healthCheckpoint=1289;assert(x.MemberFollowSignal({}));x.TimeGMT=()=>1290;assert(!x.MemberFollowSignal({}));});
test('student attempts and misses persist across edit and restart',()=>{const {x,memory}=env({plans:[]});x.followMembers=[member('first')];x.followIndex=0;memory[x.FollowVisitKey()]=1;memory[x.FollowMissKey()]=1;const r=env({plans:[],memory});r.x.followMembers=[{...member('first'),revision:'edited'}];assert(!r.x.MemberFollowSignal({}));});
test('student source and TTL rechecked before request',()=>{const {x,calls}=env({plans:[]});x.followMembers=[member('first')];const c={};assert(x.MemberFollowSignal(c));x.followMembers[0].source='changed';x.Open(c);assert.equal(calls.length,0);});
test('student explicit broker rejection is still one attempted follow',()=>{const {x,calls}=env({plans:[]});x.followMembers=[member('first')];const c={};assert(x.MemberFollowSignal(c));install(x,'RecordResult');x.ExplicitReject=()=>true;x.Open(c);assert.equal(x.pending.kind,0);assert.equal(calls.length,1);assert(!x.MemberFollowSignal({}));});
test('teacher zone owns priority during impulse defer against student or normal map',()=>{const {x}=env();x.followMembers=[member('opposite',4175,-1)];ticks(x,[4176,4175.7,4175.4,4175.1]);assert(!x.AIMarketSignal({}));assert(x.TeacherOwnsZone({bid:4175,ask:4175.1}));assert(!x.MemberFollowSignal({}));assert(x.followMembers[0].reason.includes('老师'));});
test('same direction and price merges sources without a second trade',()=>{
 const {x,memory}=env();x.followMembers=[member('first'),member('second')];x.MergeOpportunity(1,4175);
 assert.equal(memory[x.FollowVisitKey(0)],2);assert.equal(memory[x.FollowVisitKey(1)],2);assert(memory[x.AIVisitKey(4175,1)]>0);
});
test('different prices and directions remain independent opportunities',()=>{const {x,memory}=env();x.followMembers=[member('first',4175),member('different',4176),member('opposite',4175,-1)];x.MergeOpportunity(1,4175);assert.equal(memory[x.FollowVisitKey(0)],2);assert(!memory[x.FollowVisitKey(1)]);assert(!memory[x.FollowVisitKey(2)]);});
test('same source merge ends after actual leave then reentry, old student stays consumed',()=>{
 const {x,memory}=env();x.followMembers=[member('first')];x.MergeOpportunity(1,4175);assert(x.SameOpportunity(1,4175));
 x.UpdateSharedVisit({ask:4179,bid:4178.9});x.TimeGMT=()=>1005;x.UpdateSharedVisit({ask:4179,bid:4178.9});assert(!x.SameOpportunity(1,4175));assert(memory[x.FollowVisitKey(0)]>0);
});
test('legacy and multi-account snapshots parsed with footer, freshness and TTL checks',()=>{
 const {x}=env({plans:[]});let rows=[],pos=0;
 Object.assign(x,{FILE_READ:1,FILE_TXT:2,FILE_ANSI:4,FILE_COMMON:8,FILE_SHARE_READ:16,CP_UTF8:65001,INVALID_HANDLE:-1,
  FileOpen:name=>name.includes('follows')?1:-1,FileSize:()=>1000,FileIsEnding:()=>pos>=rows.length,FileReadString:()=>rows[pos++],FileClose:()=>{},
  StringSplit:(s,sep,out)=>{out.length=0;out.push(...s.split(sep));return out.length;},StringToInteger:Number,StringToDouble:Number,
  Number:(s,decimal=false)=>new RegExp(decimal?'^[0-9]+(?:\\.[0-9]+)?$':'^[0-9]+$').test(s)});
 install(x,'ReadMemberFollow');install(x,'ReadLegacyFollow');
 rows=['TGF,2,1000,XAUUSD,2','MEMBER,first,起飞,1,receipt1,rev,990,1290,300,2,BUY,4175,ready','MEMBER,second,登登,1,receipt2,rev,995,1295,300,2,SELL,4193,ready','END,2'];
 assert(x.ReadMemberFollow());assert.equal(x.followMembers.length,2);assert.equal(x.followMembers[1].sign,-1);
 pos=0;rows[2]=rows[2].replace('1295','1300');assert(!x.ReadMemberFollow());assert(!x.followReady);
 x.FileOpen=name=>name.includes('follows')?-1:1;pos=0;rows=['TGF,1,1000,1,XAUUSD,receipt,rev,990,1290,first,1,ready','FOLLOW,BUY,4175','END,1'];assert(x.ReadMemberFollow());assert.equal(x.followMembers.length,1);
});
test('tick path never reads files, calls AI or scans history before entry',()=>{const s=body('OnTick');assert(!/ReadFeed|ReadAISetups|History|CopyRates|CopyBuffer|FileOpen/.test(s));assert(s.includes('AIMarketSignal'));});
test('startup cannot replay a preexisting MARKET hint but keeps conditions',()=>{
 const {x}=env();ticks(x,Array(4).fill(4175));x.fastStarted=1000;x.aiPlans[0].market=true;assert(!x.AIMarketSignal({}));
 x.aiPlans[0].created=1000;assert(!x.AIMarketSignal({}));
 x.aiPlans[0].market=false;assert(x.AIMarketSignal({}));
});
test('quote movement during margin check cancels send at final check',()=>{
 const {x,calls}=env();ticks(x,Array(4).fill(4175));const c={};assert(x.AIMarketSignal(c));
 x.OrderCalcMargin=()=>{x.FreshQuote=q=>Object.assign(q,{ask:4177.1,bid:4177,time_msc:1000000});return true;};x.Open(c);assert.equal(calls.length,0);
});
test('close but distinct stated prices are not permanently merged',()=>{
 const {x,memory}=env();x.followMembers=[member('same',4175),member('different',4175.1)];x.MergeOpportunity(1,4175);
 assert.equal(memory[x.FollowVisitKey(0)],2);assert(!memory[x.FollowVisitKey(1)]);
});
test('restart reconciliation merges a filled request before unlocking pending',()=>{
 const {x,memory}=env();x.followMembers=[member('first')];
 x.pending={kind:1,order:123,at:990,bar:990,direction:1,level:4175,fast:true,originHash:x.Hash(x.aiPlans[0].origin)};
 Object.assign(x,{TERMINAL_CONNECTED:1,TerminalInfoInteger:()=>true,FinalOrderConfirmed:()=>true,
  ORDER_VOLUME_INITIAL:1,ORDER_VOLUME_CURRENT:2,HistoryOrderGetDouble:(_,k)=>k===1?.02:0});
 install(x,'Reconcile');x.Reconcile();assert.equal(x.pending.kind,0);assert.equal(memory[x.FollowVisitKey(0)],2);assert(x.SameOpportunity(1,4175));
});
test('multiple same-direction prices keep separate dedup records',()=>{
 const {x}=env();x.MergeOpportunity(1,4175);x.MergeOpportunity(1,4193);
 assert(x.SameOpportunity(1,4175));assert(x.SameOpportunity(1,4193));assert(!x.SameOpportunity(1,4180));
});

test('conditions survive AI transport delay only while sync remains healthy',()=>{
 const {x}=env();ticks(x,Array(4).fill(4175));x.aiGenerated=960;assert(x.AIMarketSignal({}));
 for(const flag of ['healthOK','healthPaused','healthSync','healthBeat','healthCheckpoint']){
  const old=x[flag];x[flag]=flag==='healthOK'?false:flag==='healthPaused'?true:879;
  assert(!x.AIMarketSignal({}),flag);x[flag]=old;
 }
 x.aiGenerated=1006;assert(!x.AIMarketSignal({}));
});
test('missing file cache cannot override pause or a malformed/canceled source',()=>{
 const {x}=env();x.aiPlanCached=true;x.aiReady=false;assert(x.KeepCachedAI('file busy'));
 x.healthPaused=true;assert(!x.KeepCachedAI('file busy'));x.healthPaused=false;
 assert(!x.InvalidAI('bad source'));assert(!x.KeepCachedAI('file busy'));
});
test('existing position does not prevent fresh revisit, brief return resets countdown',()=>{
 const {x,memory}=env();x.OwnCount=()=>1;const key=x.AIVisitKey(4175,1);memory[key]=990;
 x.UpdateTeacherVisits({ask:4179,bid:4178.9});x.TimeGMT=()=>1004;
 x.UpdateTeacherVisits({ask:4176,bid:4175.9});x.TimeGMT=()=>1005;x.UpdateTeacherVisits({ask:4179,bid:4178.9});
 x.TimeGMT=()=>1009;x.UpdateTeacherVisits({ask:4179,bid:4178.9});assert(memory[key]>0);
 x.TimeGMT=()=>1010;x.UpdateTeacherVisits({ask:4179,bid:4178.9});assert.equal(memory[key],0);
 ticks(x,Array(4).fill(4175));assert(x.AIMarketSignal({}));
 x.ExecutionBlock=()=>'持仓已达上限';const c={};x.AIMarketSignal(c);x.Open(c);assert.equal(x.pending.kind,0);
});
test('near target stays ahead of obstacle instead of rejecting a sub-five move or using ten',()=>{
 const {x,calls}=env();x.aiPlans.push({sign:-1,level:4178,market:false,origin:'s',created:990,left:0,status:''});
 ticks(x,Array(4).fill(4175));const c={};assert(x.AIMarketSignal(c));x.Open(c);
 assert.equal(calls.length,1);assert.equal(calls[0][5],4177.8);
});
test('explicit teacher SL/TP are used, crossed first-exit prevents entry',()=>{
 const {x,calls}=env();Object.assign(x.aiPlans[0],{sl:4168,first:4180,tp:4190,breakeven:4178});
 ticks(x,Array(4).fill(4175));const c={};assert(x.AIMarketSignal(c));x.Open(c);
 assert.equal(calls[0][4],4168);assert.equal(calls[0][5],4190);assert.equal(x.pending.exitFirst,4180);assert.equal(x.pending.exitBE,4178);
 const r=env();Object.assign(r.x.aiPlans[0],{sl:4168,first:4174,tp:4190});ticks(r.x,Array(4).fill(4175));
 const bad={};assert(r.x.AIMarketSignal(bad));r.x.Open(bad);assert.equal(r.calls.length,0);
});
test('map reactions follow M5 direction unless the dedicated switch is off',()=>{
 const {x}=env({plans:[]});Object.assign(x,{允许震荡点位反应:true,levels:[4175],atr:4,trend:-1,
  readyFrom:0,VisitKey:l=>'map'+l,Reaction:()=>true,entryView:{}});
 install(x,'MapReaction','bar,previous,m5,quote,out');
 const bar={time:1000,close:4175.5},m5={low:4175,high:4177,close:4176};
 assert(!x.MapReaction(bar,bar,m5,{ask:4175.5,bid:4175.4},{}));
 x.允许地图趋势过滤=false;assert(x.MapReaction(bar,bar,m5,{ask:4175.5,bid:4175.4},{}));
});
test('persist explicit exits by confirmed position and never clear pending on failed persistence',()=>{
 const {x,memory}=env();install(x,'ExitKey','id');install(x,'SaveEntryExits');
 Object.assign(x,{EA魔法号:560056,DEAL_ORDER:1,DEAL_ENTRY:2,DEAL_ENTRY_IN:0,DEAL_MAGIC:3,DEAL_SYMBOL:4,DEAL_POSITION_ID:5,
  HistoryDealsTotal:()=>1,HistoryDealGetTicket:()=>9,HistoryDealGetString:()=> 'XAUUSD',
  HistoryDealGetInteger:(_,k)=>({1:123,2:0,3:560056,5:999})[k]});
 x.pending={kind:1,order:123,exitSL:4168,exitFirst:4180,exitBE:4178};
 assert(x.SaveEntryExits());assert.equal(memory['exit999.ready'],1);assert.equal(memory['exit999.first'],4180);
 x.Store=(k,v)=>{if(k==='exit999.first')return false;memory[k]=v;return true;};
 assert(!x.SaveEntryExits());assert.equal(memory['exit999.ready'],0);
});
test('partial target restores from position id and near server TP is kept',()=>{
 const {x,memory}=env();install(x,'ExitKey','id');install(x,'FirstExit','id,sign,open,tp');
 assert.equal(x.FirstExit(1,1,4175,4177.8),4177.8);
 memory['exit1.ready']=1;memory['exit1.first']=4182;
 assert.equal(x.FirstExit(1,1,4175,4190),4182);assert.equal(x.FirstExit(2,1,4175,4190),4180);
 memory['exit3.ready']=1;memory['exit3.first']=4168;
 assert.equal(x.FirstExit(3,-1,4175,4160),4168);
});

test('TGA3 exits round trip with TGA2 compatibility and immediate cancel invalidation',()=>{
 const {x}=env({plans:[]});let rows=[],pos=0;
 Object.assign(x,{FILE_READ:1,FILE_TXT:2,FILE_ANSI:4,FILE_COMMON:8,FILE_SHARE_READ:16,CP_UTF8:65001,INVALID_HANDLE:-1,
  FileOpen:()=>1,FileSize:()=>1000,FileIsEnding:()=>pos>=rows.length,FileReadString:()=>rows[pos++],FileClose:()=>{},
  StringSplit:(s,sep,out)=>{out.length=0;out.push(...s.split(sep));return out.length;},StringToInteger:Number,StringToDouble:Number,
  Number:(s,decimal=false)=>new RegExp(decimal?'^[0-9]+(?:\\.[0-9]+)?$':'^[0-9]+$').test(s),lastMinute:0,readyFrom:0});
 install(x,'ReadAISetups');
 const v3=['TGA,3,1000,1,XAUUSD,entry,rev,990,1,SETUP,ready','SETUP,BUY,4175,REACTION,POINT,entry,rev,990,4168,4180,4190,4178','END,1'];
 rows=[...v3];assert(x.ReadAISetups());assert.equal(x.aiPlans[0].sl,4168);assert.equal(x.aiPlans[0].first,4180);
 assert(x.AIChannelReady());pos=0;rows=['TGA,3,1000,0,XAUUSD,cancel,rev2,1000,0,WAIT,canceled','END,0'];
 assert(x.ReadAISetups());assert(!x.AIChannelReady());assert(!x.KeepCachedAI('busy'));
 pos=0;rows=[...v3];rows[1]=rows[1].replace('4168','4186');assert(!x.ReadAISetups());assert(!x.aiPlanCached);
 pos=0;rows=['TGA,2,1000,1,XAUUSD,entry,rev,990,1,SETUP,ready',v3[1].split(',').slice(0,8).join(','),'END,1'];
 assert(x.ReadAISetups());assert.equal(x.aiPlans[0].sl,0);assert.equal(x.aiPlans[0].tp,0);
});
test('pending exit fields survive interrupted execution restart and explicit clear',()=>{
 const {x,memory}=env();install(x,'SavePending');install(x,'RestorePending');
 x.pending={kind:1,order:123,position:0,at:1000,bar:1000,volume:.02,sl:4168,tp:4190,level:4175,direction:1,fast:true,originHash:1,
  exitSL:4168,exitFirst:4182,exitTP:4190,exitBE:4178};
 x.SavePending();const r=env({memory});install(r.x,'RestorePending');r.x.RestorePending();
 assert.equal(r.x.pending.exitFirst,4182);assert.equal(r.x.pending.exitTP,4190);
 install(r.x,'SavePending');install(r.x,'ClearPending');r.x.ZeroMemory=p=>Object.keys(p).forEach(k=>p[k]=0);
 r.x.ClearPending();assert.equal(memory.exitFirst,0);assert.equal(memory.kind,0);
});
function managed(memory={},position={}){
 const {x}=env({memory}),actions=[];
 const p={open:4175,sl:4168,tp:4190,volume:.02,closed:0,bid:4180,...position};
 Object.assign(x,{PositionsTotal:()=>1,PositionGetTicket:()=>11,OwnSelected:()=>true,
  POSITION_IDENTIFIER:1,POSITION_TYPE:2,POSITION_TYPE_BUY:0,POSITION_PRICE_OPEN:3,POSITION_VOLUME:4,POSITION_SL:5,POSITION_TP:6,
  SYMBOL_VOLUME_MIN:7,PositionGetInteger:k=>k===1?999:0,
  PositionGetDouble:k=>({3:p.open,4:p.volume,5:p.sl,6:p.tp})[k],SymbolInfoDouble:()=>.01,
  PositionVolumes:()=>({ok:true,initial:.02,closed:p.closed}),LotDown:n=>Math.round(n*1e8)/1e8,
  PositionSelectByTicket:()=>true,FreshQuote:q=>Object.assign(q,{bid:p.bid,ask:p.bid+.1}),
  Modify:(ticket,id,sign,sl,tp)=>{actions.push({modify:true,sl,tp});x.pending.kind=3;},
  execution:{PositionClosePartial:(ticket,volume)=>actions.push({partial:true,volume})}});
 for(const [n,args] of [['ExitKey','id'],['FirstExit','id,sign,open,tp'],['PartialRemaining','initial,closed,remaining'],['Manage','']])install(x,n,args);
 return {x,actions,p};
}
test('management honors stored first exit and real partial deals after restart',()=>{
 const memory={'exit999.ready':1,'exit999.sl':4168,'exit999.first':4182,'exit999.tp':4190,'exit999.be':0};
 const a=managed(memory);a.x.Manage();assert.equal(a.actions.length,0);
 const b=managed(memory,{bid:4182});b.x.Manage();assert.deepEqual(b.actions,[{partial:true,volume:.01}]);
 const c=managed(memory,{bid:4182,volume:.01,closed:.01});c.x.Manage();assert.equal(c.actions[0].sl,4175);
 const d=managed(memory,{bid:4183,sl:4175,volume:.01,closed:.01});d.x.Manage();assert.equal(d.actions.length,0);
});
test('management keeps tightened SL, respects explicit BE trigger, restores missing final target',()=>{
 const memory={'exit999.ready':1,'exit999.sl':4162,'exit999.first':4182,'exit999.tp':4190,'exit999.be':4178};
 const a=managed(memory,{sl:4176,bid:4177});a.x.Manage();assert.equal(a.actions.length,0);
 const b=managed(memory,{sl:4162,bid:4178});b.x.Manage();assert.equal(b.actions[0].sl,4175);
 const c=managed(memory,{sl:4162,bid:4177,tp:0});c.x.Manage();assert.equal(c.actions[0].tp,4190);
});
test('near final TP avoids premature half-close and unsplittable explicit final stays intact',()=>{
 const a=managed({}, {sl:4165,tp:4177.8,bid:4177.9});a.x.Manage();assert.equal(a.actions.length,0);
 const b=managed({'exit999.ready':1,'exit999.sl':4168,'exit999.tp':4190},{volume:.01,bid:4181});
 b.x.PositionVolumes=()=>({ok:true,initial:.01,closed:0});b.x.Manage();assert.equal(b.actions.length,0);
});
console.log(checks+' production-source near-entry checks passed');
