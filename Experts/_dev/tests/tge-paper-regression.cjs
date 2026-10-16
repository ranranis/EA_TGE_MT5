// Executes production MQL bodies with synthetic quotes and in-memory files; never connects to a broker.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const paths=['EA_T哥点位跟单.mq5','Include/Trading/TgeAISignals.mqh','Include/View/TgeEntryObserver.mqh','Include/Trading/TgePaperTrading.mqh'];
const sources=paths.map(p=>fs.readFileSync(p,'utf8'));
function body(name){
 const re=new RegExp('^(?:void|bool|int|long|double|string) '+name+'\\(','m'),s=sources.find(v=>re.test(v));
 assert(s,name); const start=s.indexOf('{',s.search(re));let n=1,end=start+1;
 for(;n;end++){if(s[end]==='{')n++;if(s[end]==='}')n--;}
 return s.slice(start+1,end-1);
}
function install(x,name,args=''){
 let s=body(name).replace(/\((?:int|long|datetime)\)/g,'')
 .replace(/\bstring (\w+)\[\];/g,'let $1=[];')
 .replace(/\b(?:PaperEvent|MqlTick) (\w+);/g,'let $1={};')
 .replace(/\b(?:PaperTrade|PaperScore|TgeObservation|datetime|double|long|int|uint|bool|string)\s+/g,'let ');
 if(name==='PaperClean')s=s.replace(/StringReplace\(text,([^;]+)\);/g,'text=StringReplace(text,$1);');
 if(name==='PaperExit')s=s.replace('return why;','return {why,price};');
 s=s.replace('PaperExit(paperTrades[i],q,exit)',
   '((r)=>{exit=r.price;return r.why;})(PaperExit(paperTrades[i],q,exit))');
 s=s.replace('OrderCalcProfit(e.sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,e.volume,e.entry,e.exit,e.gross)',
   '((r)=>{e.gross=r.gross;return r.ok;})(OrderCalcProfit(e.sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,e.volume,e.entry,e.exit))');
 s=s.replace('e.msc/60000','Math.floor(e.msc/60000)').replaceAll('q.time_msc/60000','Math.floor(q.time_msc/60000)');
 vm.runInContext('function '+name+'('+args+'){'+s+'}',x);
}
const plan=(o={})=>({id:'p1',source:'group1',kind:'DIRECT',sign:1,approach:0,level:100,confirmed:900,
 expires:9000,priority:90,feedState:'READY',sleeping:false,hardStopped:false,...o});
function env(existing=''){
 let quote={time:1000,time_msc:1000000,bid:99.9,ask:100},now=1000,file=existing,lines=[],at=0,fail=false,error=0;
 const x=vm.createContext({
  启用自动模拟对比:true,启用入场观察实验:true,每次开仓手数:.02,最大同时持仓:3,
  模拟每手往返费用:2,模拟单边滑点价格:0,最大点差价格:.5,挂单最大离价:50,启用消息日历:true,
  重点事件前后分钟:10,一般高重要性前后分钟:3,冲击冷却秒数:120,恢复确认秒数:180,
  读取AI即时策略:true,启用积极持单:false,入场策略:0,TGE_ENTRY_COMPAT:0,TGE_ENTRY_TOUCH:1,TGE_ENTRY_ADAPTIVE:2,
  TEACHER_BAND:1,REARM_DISTANCE:4,REARM_SECONDS:5,观察收回ATR倍数:.25,
  paperTrades:[],paperVisits:[],paperScores:Array.from({length:2},()=>({opened:0,closed:0,wins:0,losses:0,invalid:0,net:0,peak:0,drawdown:0})),
  paperSeq:0,paperLastTick:0,paperFile:-1,paperReady:false,paperPending:false,paperRestored:false,
  paperRetry:0,paperFrozen:{},paperPolicy:'',paperFilePath:'',paperLastLine:'',paperHealth:'',
  paperStatus:['',''],paperLastResult:'',paperDecisionMinute:[0,0],prefix:'test.',_Symbol:'XAUUSD.c',_Digits:2,
  observerLiveFrom:999,observerHasPending:false,entryObservations:[],adaptiveRecoverUntil:0,adaptiveShockUntil:0,
  aiPlans:[plan()],aiReady:true,DBL_MAX:Number.MAX_VALUE,
  MathMin:Math.min,MathMax:Math.max,MathAbs:Math.abs,MathIsValidNumber:Number.isFinite,
  IntegerToString:String,DoubleToString:(v,n)=>Number(v).toFixed(n),StringLen:s=>s.length,
  StringGetCharacter:(s,n)=>s[n],StringSubstr:(s,n,len)=>len===undefined?s.slice(n):s.slice(n,n+len),
  StringToInteger:Number,StringToDouble:Number,StringSplit:(s,sep,out)=>{out.splice(0,out.length,...s.split(sep));return out.length;},
  StringReplace:(s,a,b)=>s.split(a).join(b),Number:(s,dec)=>dec?/^\d+(?:\.\d+)?$/.test(s):/^\d+$/.test(s),
  Hash:s=>{let h=2166136261;for(const c of s)h=Math.imul(h^c.charCodeAt(0),16777619)>>>0;return h;},
  ArraySize:a=>a.length,ArrayResize:(a,n)=>{while(a.length<n)a.push({});a.length=n;},
  ZeroMemory:o=>{for(const k of Object.keys(o))delete o[k];
   Object.assign(o,{seq:0,id:0,msc:0,bar:0,arm:0,sign:0,level:0,entry:0,exit:0,volume:0,gross:0,fee:0,mfe:0,mae:0,kind:'',source:'',why:''});},
  TickSize:()=>.01,Align:(p,side)=>Number(((side>0?Math.ceil(p*100-1e-8):Math.floor(p*100+1e-8))/100).toFixed(2)),
  TimeGMT:()=>now,TimeCurrent:()=>now,FreshQuote:q=>{Object.assign(q,quote);return true;},
  AIChannelReady:()=>x.aiReady,AdaptiveNewsState:()=>'',AdaptiveMarketFresh:()=>true,AdaptiveConfirmed:()=>true,
  ObserverPolicy:()=>'O1/test',PlanSign:i=>x.aiPlans[i].sign||x.aiPlans[i].approach,
  InTeacherBand:(p,l)=>Math.abs(p-l)<=1,
  FILE_READ:1,FILE_WRITE:2,FILE_TXT:4,FILE_ANSI:8,FILE_COMMON:16,FILE_SHARE_READ:32,CP_UTF8:65001,
  INVALID_HANDLE:-1,SEEK_END:2,ACCOUNT_CURRENCY:1,AccountInfoString:()=>'USD',
  FolderCreate:()=>true,FileOpen:()=>{lines=file.split(/\r?\n/);at=0;return 1;},
  FileIsEnding:()=>at>=lines.length,FileReadString:()=>lines[at++],FileSeek:()=>true,FileFlush:()=>{},
  FileWriteString:(h,s)=>{if(fail){error=1;return 0;}file+=s;return Buffer.byteLength(s);},
  ResetLastError:()=>{error=0;},GetLastError:()=>error,FileClose:()=>{},
  ORDER_TYPE_BUY:0,ORDER_TYPE_SELL:1,OrderCalcProfit:(type,s,v,entry,exit)=>({ok:true,gross:(type===0?1:-1)*(exit-entry)*100*v})
 });
 const funcs=[
 ['EffectiveEntryMethod',''],['EntrySourceReason','i'],['UnifiedEntryStatus','i,q,method,live'],
 ['ObserverDirection','i'],['ObserverEntryStatus','i,q,after'],
 ['PaperClean','text'],['PaperPolicy',''],['PaperEncode','e'],['PaperParse','line,e'],
 ['PaperFind','id'],['PaperVisitIndex','arm,level'],['PaperEventValid','e'],['PaperApply','e'],
 ['PaperWrite','e'],['PaperEmit','e'],['InitPaper',''],['PaperFromTrade','t,q,e'],['PaperExit','t,q,price'],
 ['PaperInvalidate','q'],['PaperCount','arm'],['PaperAreaBusy','arm,level'],['PaperPoll',''],['StopPaper','']];
 funcs.forEach(([n,a])=>install(x,n,a));
 x.InitPaper();
 return {x,get file(){return file;},setFail:v=>fail=v,setNow:n=>now=n,
  tick:(bid,ask=bid+.1,dt=1)=>{now+=dt;quote={bid,ask,time:now,time_msc:now*1000};x.PaperPoll();},
  quote:()=>quote};
}
function observe(e,sign=1){
 const p=e.x.aiPlans[0],bar=Math.floor(e.quote().time/60)*60-60;
 e.x.entryObservations=[{sign,bar,utc:e.x.TimeGMT(),lower:100,upper:110,atr:2,why:'wait',
  lowerEvidence:p.kind+'/'+p.sign+'/'+p.id+'/'+p.source,upperEvidence:p.kind+'/'+p.sign+'/'+p.id+'/'+p.source,
  lowerConfirmed:p.confirmed,upperConfirmed:p.confirmed}];
}
let checks=0;function test(n,fn){fn();checks++;console.log('PASS '+n);}
test('兼容模式保持旧行为；指定入场方式不随持单策略变化',()=>{
 const e=env(),x=e.x;assert.equal(x.EffectiveEntryMethod(),0);x.启用积极持单=true;assert.equal(x.EffectiveEntryMethod(),1);
 x.入场策略=1;assert.equal(x.EffectiveEntryMethod(),0);x.入场策略=2;x.启用积极持单=false;assert.equal(x.EffectiveEntryMethod(),1);
});
test('有效点位开虚拟单，保留原消息方向；未确认的新方法不入场',()=>{
 const e=env();e.tick(99.9,100);assert.equal(e.x.paperTrades.length,1);assert.equal(e.x.paperTrades[0].arm,0);
 assert.equal(e.x.paperScores[0].opened,1);assert.match(e.file,/B当时/);
});
test('已收盘反应可自动启动B，两组账本独立且同次触及不重复',()=>{
 const e=env();observe(e);e.tick(100.7,100.8);assert.equal(e.x.paperTrades.length,2);
 for(let i=0;i<3;i++)e.tick(100.6,100.7);assert.equal(e.x.paperTrades.length,2);assert.deepEqual(Array.from(e.x.paperScores,s=>s.opened),[1,1]);
});
test('新判断不使用未来收盘、过期判断、旧启动记录或相反消息方向',()=>{
 for(const type of ['future','old','restart','direction']){
  const e=env();observe(e);const r=e.x.entryObservations[0];
  if(type==='future')r.bar=e.x.TimeCurrent();
  if(type==='old')r.bar-=120;
  if(type==='restart')r.utc=1;
  if(type==='direction')e.x.aiPlans[0].sign=-1;
  e.tick(100.7,100.8);assert.equal(e.x.paperScores[1].opened,0,type);
 }
});
test('新消息替换来源后旧研判不触发；暂停后可用新反应恢复',()=>{
 const e=env();observe(e);e.x.aiPlans[0].confirmed=901;e.tick(100.7,100.8);assert.equal(e.x.paperScores[1].opened,0);
 observe(e);e.tick(100.7,100.8);assert.equal(e.x.paperScores[1].opened,1);
});
test('断开的消息、撤销、到期以及异常点差不产生新模拟',()=>{
 for(const type of ['feed','cancel','expiry','spread']){
  const e=env();if(type==='feed')e.x.aiReady=false;if(type==='cancel')e.x.aiPlans[0].feedState='CANCELLED';
  if(type==='expiry')e.x.aiPlans[0].expires=1;e.tick(99.9,type==='spread'?101:100);
  assert.equal(e.x.paperTrades.length,0,type);
 }
});
test('两组共享消息窗口与冲击暂停，恢复不永久卡死',()=>{
 const e=env();observe(e);e.x.AdaptiveNewsState=()=>'消息窗口';e.tick(100.7,100.8);assert.equal(e.x.paperTrades.length,0);
 e.x.AdaptiveNewsState=()=>'';e.x.adaptiveShockUntil=1100;e.tick(100.7,100.8);assert.equal(e.x.paperTrades.length,0);
 e.x.adaptiveShockUntil=0;e.tick(100.7,100.8);assert.equal(e.x.paperTrades.length,2);
});
test('BUY用Ask入Bid出，TP不取得跳空额外利润并扣费用',()=>{
 const e=env();e.tick(99.9,100);e.tick(106,106.1);
 assert.equal(e.x.paperScores[0].closed,1);assert(Math.abs(e.x.paperScores[0].net-9.96)<1e-9);
 assert.equal(e.x.paperScores[0].wins,1);
});
test('SELL用Bid入Ask出，SL承担更差报价和双边不利滑点',()=>{
 const e=env();e.x.模拟单边滑点价格=.2;e.x.aiPlans[0].sign=-1;e.tick(100,100.1);e.tick(111,111.1);
 assert.equal(e.x.paperScores[0].closed,1);assert(Math.abs(e.x.paperScores[0].net-(-23.04))<1e-8);
 assert(e.x.paperScores[0].drawdown>23);
});
test('原始群消息撤销后已有模拟单仍正常退出',()=>{
 const e=env();e.tick(99.9,100);e.x.aiReady=false;e.tick(105,105.1);assert.equal(e.x.paperScores[0].closed,1);
});
test('同区域有仓不叠加；离开4点不足5秒不得重入',()=>{
 const e=env();e.tick(99.9,100);e.x.aiPlans.push(plan({id:'p2',level:101}));e.tick(100,100.1);assert.equal(e.x.paperTrades.length,1);
 e.x.aiPlans.pop();e.tick(105,105.1);
 for(let i=0;i<4;i++)e.tick(105,105.1);
 assert(e.x.paperVisits.length>0);e.tick(105,105.1);assert.equal(e.x.paperVisits.length,0);
 e.tick(99.9,100);assert.equal(e.x.paperScores[0].opened,2);
});
test('每组持仓上限独立，不读取真实账户消费或持仓',()=>{
 const e=env();e.x.最大同时持仓=1;e.tick(99.9,100);e.x.aiPlans=[plan({id:'p2',level:103})];e.tick(102.9,103);
 assert.equal(e.x.paperTrades.length,1);
 const s=sources[3];assert(!/\b(?:OrderSend|PositionOpen|PositionClose|Store|MergeOpportunity|SavePending)\s*\(/.test(s));
 assert(!s.includes('pending.kind'));assert(!s.includes('PositionsTotal'));
});
test('正常重启恢复已结束成绩；未结束单排除而不猜盈利',()=>{
 const e=env();e.tick(99.9,100);e.tick(105,105.1);
 const r=env(e.file);assert.equal(r.x.paperScores[0].closed,1);assert.equal(r.x.paperScores[0].net,e.x.paperScores[0].net);
 const o=env();o.tick(99.9,100);const restart=env(o.file);restart.tick(120,120.1,5);
 assert.equal(restart.x.paperScores[0].closed,0);assert.equal(restart.x.paperScores[0].invalid,1);
});
test('报价缺口超过5秒的持仓不计盈亏，不事后补造触价',()=>{
 const e=env();e.tick(99.9,100);e.tick(120,120.1,10);
 assert.equal(e.x.paperScores[0].closed,0);assert.equal(e.x.paperScores[0].invalid,1);assert.equal(e.x.paperTrades.length,0);
});
test('保存失败不推进状态；冻结同一意图重试且缺失样本排除',()=>{
 const e=env();e.setFail(true);e.tick(99.9,100);assert(e.x.paperPending);assert.equal(e.x.paperTrades.length,0);
 assert.equal(e.x.paperScores[0].opened,0);e.setFail(false);e.tick(120,120.1,11);
 assert(!e.x.paperPending);assert.equal(e.x.paperScores[0].opened,1);assert.equal(e.x.paperScores[0].invalid,1);
 assert.equal(e.x.paperScores[0].closed,0);
});
test('完整事件重复写入恢复只计一次；截断尾行不计事件',()=>{
 const e=env();e.tick(99.9,100);
 const lines=e.file.trim().split(/\r?\n/).filter(Boolean),last=lines.at(-1);
 const r=env(e.file+'\r\n'+last+'\r\nP1\ttruncated');assert(r.x.paperReady);assert.equal(r.x.paperScores[0].opened,1);
});
test('损坏完整事件或费用策略不一致则停止，保留文件',()=>{
 const e=env();e.tick(99.9,100);
 assert(!env(e.file.replace('碰价基准','被篡改')).x.paperReady);
 const wrong=e.file.replace('fee2.00000000','fee9.00000000');assert(!env(wrong).x.paperReady);
});
test('WAIT原因限每分钟每组一条并持久化，不能冒充交易笔数',()=>{
 const e=env();e.x.aiPlans[0].feedState='CANCELLED';for(let i=0;i<4;i++)e.tick(100,100.1);
 assert.equal(e.file.split('\tWAIT\t').length-1,2);assert.equal(e.x.paperScores[0].opened,0);
});
test('收益换算失败不能伪造净收益，下次排除过程不完整样本',()=>{
 const e=env();e.tick(99.9,100);e.x.OrderCalcProfit=()=>({ok:false,gross:0});e.tick(105,105.1);e.tick(105,105.1);
 assert.equal(e.x.paperScores[0].closed,0);assert.equal(e.x.paperScores[0].invalid,1);
});
test('60分钟规则对多空一致，费用为零时页面明确告知未扣佣金',()=>{
 const e=env();const t={sign:1,entry:100,opened:1};
 const out=e.x.PaperExit(t,{bid:101,ask:101.1,time_msc:3600001},0);assert.equal(out.why,'满60分钟退出');assert.equal(out.price,101);
 assert(body('PaperPanel').includes('费用尚未配置'));assert(body('PaperPanel').includes('每秒采样'));
});
test('成绩单布局和明细按钮在固定面板内，不覆盖切换',()=>{
 const e=env(),bounds=[],buttons=[];install(e.x,'PaperPanel');
 Object.assign(e.x,{tradeMode:false,UI_TEXT:0,UI_WARN:1,UI_ACCENT:2,UI_ROW:3,UI_MUTED:4,UI_DIM:5,
  UIText:(t,x,y,w,size)=>bounds.push([x,y,w,size+4]),UICard:(x,y,w,h)=>bounds.push([x,y,w,h]),
  UIButton:(t,x,y,w,id)=>buttons.push({x,y,w,id}),panelCanvas:{Update:()=>{}}});
 e.x.PaperPanel();assert(bounds.every(([x,y,w,h])=>x>=0&&x+w<=560&&y>=0&&y+h<=654));
 assert.equal(buttons[0].id,205);
});
console.log(checks+' paper checks passed; synthetic quotes/files, no broker trading, no profitability claim');
