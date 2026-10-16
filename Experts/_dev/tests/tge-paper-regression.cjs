// Executes production MQL bodies with synthetic quotes and in-memory files; never connects to a broker.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const paths=['EA_T哥点位跟单.mq5','Include/Trading/TgeAISignals.mqh','Include/View/TgeEntryObserver.mqh','Include/Trading/TgePaperTrading.mqh','Include/View/TgePaperHistory.mq5'];
const sources=paths.map(p=>fs.readFileSync(p,'utf8'));
function body(name){
 const re=new RegExp('^(?:void|bool|int|long|double|string) '+name+'\\(','m'),s=sources.find(v=>re.test(v));
 assert(s,name); const start=s.indexOf('{',s.search(re));let n=1,end=start+1;
 for(;n;end++){if(s[end]==='{')n++;if(s[end]==='}')n--;}
 return s.slice(start+1,end-1);
}
function install(x,name,args=''){
 let s=body(name).replace(/C'\d+,\d+,\d+'/g,'123').replace('double values[6],one[1];','let values=Array(6).fill(0),one=[0];').replace(/\((?:int|long|ulong|datetime|double)\)/g,'')
 .replace(/\b(?:string|MqlTick) (\w+)\[\];/g,'let $1=[];')
 .replace(/\b(?:PaperEvent|MqlTick) (\w+);/g,'let $1={};')
 .replace(/\bPaperEvent (\w+)=/g,'let $1=')
 .replace(/\b(?:MqlTick|PaperTrade|PaperScore|PaperSettlement|PaperDetail|TgeObservation|MqlRates|datetime|double|long|int|uint|bool|string)\s+/g,'let ');
 s=s.replace('paperSettlements[at]=paperSettlements[at-1]', 'paperSettlements[at]=structuredClone(paperSettlements[at-1])');
 s=s.replace('(PaperDetailCount()-1)/PAPER_PAGE_SIZE','Math.floor((PaperDetailCount()-1)/PAPER_PAGE_SIZE)');
 s=s.replace('(count+PAPER_PAGE_SIZE-1)/PAPER_PAGE_SIZE','Math.floor((count+PAPER_PAGE_SIZE-1)/PAPER_PAGE_SIZE)');
 if(name==='PaperClean')s=s.replace(/StringReplace\(text,([^;]+)\);/g,'text=StringReplace(text,$1);');
 s=s.replace('PaperExit(t,q,exit)', '((r)=>{exit=r.price;return r.why;})(PaperExit(t,q,exit))');
 s=s.replace('OrderCalcProfit(t.sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,t.volume,t.entry,exit,ending.gross)',
   '((r)=>{ending.gross=r.gross;return r.ok;})(OrderCalcProfit(t.sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,t.volume,t.entry,exit))');
 if(name==='PaperExit')s=s.replace('return why;','return {why,price};');
 s=s.replace('PaperExit(paperTrades[i],q,exit)',
   '((r)=>{exit=r.price;return r.why;})(PaperExit(paperTrades[i],q,exit))');
 s=s.replace('OrderCalcProfit(e.sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,e.volume,e.entry,e.exit,e.gross)',
   '((r)=>{e.gross=r.gross;return r.ok;})(OrderCalcProfit(e.sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,e.volume,e.entry,e.exit))');
 s=s.replace('e.msc/60000','Math.floor(e.msc/60000)').replaceAll('q.time_msc/60000','Math.floor(q.time_msc/60000)');
 vm.runInContext('function '+name+'('+args+'){'+s+'}',x);
}
const plan=(o={})=>({id:'p1',source:'group1',kind:'DIRECT',sign:1,approach:0,level:100,available:800,confirmed:800,
 expires:9000,priority:90,feedState:'READY',sleeping:false,hardStopped:false,...o});
function env(existing=''){
 let jobs=new Map(),jobId=0,history=[],historyError=0,quote={time:1000,time_msc:1000000,bid:99.9,ask:100},now=1000,file=existing,lines=[],at=0,fail=false,error=0;
 const x=vm.createContext({
  启用自动模拟对比:true,启用入场观察实验:true,每次开仓手数:.02,最大同时持仓:3,
  模拟每手往返费用:2,模拟单边滑点价格:0,最大点差价格:.5,挂单最大离价:50,启用消息日历:true,
  重点事件前后分钟:10,一般高重要性前后分钟:3,冲击冷却秒数:120,恢复确认秒数:180,
  读取AI即时策略:true,启用积极持单:false,入场策略:0,TGE_ENTRY_COMPAT:0,TGE_ENTRY_TOUCH:1,TGE_ENTRY_ADAPTIVE:2,
  TEACHER_BAND:1,REARM_DISTANCE:4,REARM_SECONDS:5,观察收回ATR倍数:.25,
  paperTrades:[],paperVisits:[],paperDetails:[],PAPER_ARMS:5,paperDetailArm:0,paperShowDetails:false,paperSelectedId:0,paperReviewId:0,paperReviewStamp:"",paperPressedId:0,paperRowIds:[0,0,0,0,0],uiHits:[],paperListPage:0,PAPER_PAGE_SIZE:5,paperSettlements:[],paperRepair:{},paperRepairId:0,paperRepairCursor:0,paperRepairRetry:0,paperHistoryHandle:-1,paperHistoryId:0,paperHistoryFrom:0,paperHistoryUntil:0,paperHistoryStarted:0,EMPTY_VALUE:2147483647,PERIOD_M1:1,replayHealth:"archive",adaptiveBars:[],adaptiveATR:2,adaptiveTrend:0,paperScores:Array.from({length:5},()=>({opened:0,closed:0,wins:0,losses:0,invalid:0,repaired:0,net:0,peak:0,drawdown:0})),
  paperSeq:0,paperLastTick:0,paperFile:-1,paperReady:false,paperPending:false,paperRestored:false,
  paperRetry:0,paperFrozen:{},paperPolicy:'',paperFilePath:'',paperLastLine:'',paperHealth:'',
  UI_HEADER:8,marks:new Map(),VIEW:'TEST_',OBJPROP_FONT:1,OBJPROP_FONTSIZE:2,OBJPROP_ANCHOR:3,ANCHOR_LEFT_UPPER:4,
   OBJ_TREND:5,OBJPROP_RAY_RIGHT:6,OBJPROP_RAY_LEFT:7,OBJPROP_COLOR:8,OBJPROP_STYLE:9,STYLE_DOT:10,OBJPROP_WIDTH:11,
   OBJPROP_BACK:12,OBJPROP_SELECTABLE:13,reviewNavTime:0,reviewNavAttempts:0,ReviewNavigate:()=>{},ReviewReturnLive:()=>{},
   ChartRedraw:()=>{},ObjectSetInteger:()=>{},ObjectSetString:()=>{},
   paperStatus:['','','','',''],paperLastResult:'',reviewNotice:'',paperDecisionMinute:[0,0,0,0,0],prefix:'test.',_Symbol:'XAUUSD.c',_Digits:2,
  observerLiveFrom:999,observerHasPending:false,entryObservations:[],adaptiveRecoverUntil:0,adaptiveShockUntil:0,
  aiPlans:[plan()],aiReady:true,DBL_MAX:Number.MAX_VALUE,
  MathRound:Math.round,MathMin:Math.min,MathMax:Math.max,MathAbs:Math.abs,MathIsValidNumber:Number.isFinite,
  TimeToString:()=>"2026.10.16 00:16:40",TIME_DATE:1,TIME_SECONDS:2,
  IntegerToString:String,DoubleToString:(v,n)=>Number(v).toFixed(n),StringLen:s=>s.length,
  StringGetCharacter:(s,n)=>s[n],StringSubstr:(s,n,len)=>len===undefined?s.slice(n):s.slice(n,n+len),
  StringToInteger:Number,StringToDouble:Number,StringSplit:(s,sep,out)=>{out.splice(0,out.length,...s.split(sep));return out.length;},
  StringReplace:(s,a,b)=>s.split(a).join(b),Number:(s,dec)=>dec?/^\d+(?:\.\d+)?$/.test(s):/^\d+$/.test(s),
  Hash:s=>{let h=2166136261;for(const c of s)h=Math.imul(h^c.charCodeAt(0),16777619)>>>0;return h;},
  ArrayInitialize:(a,v)=>a.fill(v),ArraySize:a=>a.length,ArrayResize:(a,n)=>{while(a.length<n)a.push(a===x.paperDetails?{entryEvent:{},endEvent:{}}:{});a.length=n;},
  ZeroMemory:o=>{if(o==null)return;for(const k of Object.keys(o))delete o[k];
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
  structuredClone, COPY_TICKS_ALL:0,CopyTicksRange:(symbol,out,flags,from,to)=>{error=historyError;out.push(...history.filter(q=>q.time_msc>=from&&q.time_msc<=to));return out.length;},
  ORDER_TYPE_BUY:0,ORDER_TYPE_SELL:1,OrderCalcProfit:(type,s,v,entry,exit)=>({ok:true,gross:(type===0?1:-1)*(exit-entry)*100*v})
 });
 const funcs=[
 ['PaperName','arm'],['PaperRule','arm'],['PaperBreakBar','level,sign,bars,volatility'],['PaperRangePeer','i,sign'],['PaperReaction','arm,level,messageSide,bars,volatility,trendValue'],['PaperDirection','arm,i'],['PaperReactionStatus','i,q,arm,after'],['EffectiveEntryMethod',''],['EntrySourceReason','i'],['UnifiedEntryStatus','i,q,method,live'],
 ['ObserverDirection','i'],['ObserverEntryStatus','i,q,after'],
 ['PaperClean','text'],['PaperDetailFind','id'],['PaperClearReview',''],['PaperSyncReview',''],['PaperDetailCount',''],['PaperDetailAction','action'],['PaperSettle','e'],['PaperRemember','e'],['PaperDetailPanel',''],['PaperMoment','msc'],['PaperPolicy',''],['PaperEncode','e'],['PaperParse','line,e'],
 ['PaperFind','id'],['PaperVisitIndex','arm,level'],['PaperEventValid','e'],['PaperApply','e'],
 ['PaperWrite','e'],['PaperEmit','e'],['InitPaper',''],['PaperFromTrade','t,q,e'],['PaperExit','t,q,price'],
 ['PaperReleaseHistory',''],['PaperHistoryStep','t,latest,ending'],['PaperRepairLegacy','q'],['PaperCount','arm'],['PaperAreaBusy','arm,level'],['PaperPoll',''],['StopPaper','']];
 funcs.forEach(([n,a])=>install(x,n,a));
 x.ReviewMark=(name,at,price,text)=>x.marks.set(name,{at,price,text});
 x.ObjectCreate=(id,name,type,...args)=>{x.marks.set(name,{type,args});return true;};
 x.ObjectsDeleteAll=(id,prefix)=>{for(const key of x.marks.keys())if(key.startsWith(prefix))x.marks.delete(key);};
 x.iCustom=(symbol,period,path,from,to,opened,entry,side,requireEnd)=>{
  const w=vm.createContext({...x,FromMSC:from,UntilMSC:to,OpenedMSC:opened,EntryPrice:entry,Side:side,RequireEnd:requireEnd,
   historyState:0,historyTime:0,historyExit:0,historyMfe:0,historyMae:0,historyReason:0,historyRetry:0});
  install(w,'HistoryScan');jobs.set(++jobId,w);return jobId;
 };
 x.BarsCalculated=()=>1;x.IndicatorRelease=h=>jobs.delete(h);
 x.CopyBuffer=(h,b,a,n,out)=>{const w=jobs.get(h);w.HistoryScan();
  out[0]=[w.historyState,w.historyTime,w.historyExit,w.historyMfe,w.historyMae,w.historyReason][b];return 1;};
 x.InitPaper();
 return {x,history,setHistoryError:v=>historyError=v,get file(){return file;},setFail:v=>fail=v,setNow:n=>now=n,
  tick:(bid,ask=bid+.1,dt=1)=>{now+=dt;quote={bid,ask,time:now,time_msc:now*1000};history.push({...quote});x.PaperPoll();},
  quote:()=>quote};
}
function observe(e,sign=1){
 const bar=Math.floor(e.quote().time/60)*60-60;
 e.x.adaptiveBars=[{time:bar,open:100.75,close:100.8,low:100,high:101},
  {time:bar-60,open:100.8,close:100.8,low:100.5,high:101},
  {time:bar-120,open:100.8,close:100.8,low:100.5,high:101}];
 e.x.aiPlans.push(plan({id:'upper',level:110,sign:-1}));
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
 const e=env();observe(e);e.tick(100.7,100.8);assert.equal(e.x.paperTrades.length,3);
 for(let i=0;i<3;i++)e.tick(100.6,100.7);assert.equal(e.x.paperTrades.length,3);assert.deepEqual(Array.from(e.x.paperScores,s=>s.opened).slice(0,2),[1,1]);
});
test('B不使用未来收盘、过期行情、晚到消息或相反消息方向',()=>{
 for(const type of ['future','old','late','direction']){
  const e=env();observe(e);const b=e.x.adaptiveBars[0];
  if(type==='future')b.time=e.x.TimeCurrent();
  if(type==='old')b.time-=120;
  if(type==='late')e.x.aiPlans[0].available=1000;
  if(type==='direction')e.x.aiPlans[0].sign=-1;
  e.tick(100.7,100.8);assert.equal(e.x.paperScores[1].opened,0,type);
 }
});
test('新消息替换后等待新K反应，不能复用到达之前的K线',()=>{
 const e=env();observe(e);e.x.aiPlans[0].available=1000;
 e.tick(100.7,100.8);assert.equal(e.x.paperScores[1].opened,0);
 e.setNow(1080);e.x.adaptiveBars[0].time=1020;
 e.tick(100.7,100.8);assert.equal(e.x.paperScores[1].opened,1);
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
 e.x.adaptiveShockUntil=0;e.tick(100.7,100.8);assert.equal(e.x.paperTrades.length,3);
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
test('重启保留未结束单，历史完整才恢复或平仓',()=>{
 const e=env();e.tick(99.9,100);const r=env(e.file);r.history.push(...e.history);
 r.tick(101,101.1,2);assert.equal(r.x.paperScores[0].invalid,0);assert.equal(r.x.paperTrades.length,1);
 assert(!r.x.paperTrades[0].recovering);r.tick(105,105.1);
 assert.equal(r.x.paperScores[0].closed,1);assert.equal(r.x.paperDetails[0].endEvent.kind,'CLOSE');
 const replay=env(r.file);assert.equal(replay.x.paperScores[0].closed,1);
});
test('超过5秒先核对历史，先触SL再回到盈利价仍记亏',()=>{
 const e=env();e.tick(99.9,100);
 e.history.push({bid:89,ask:89.1,time:1003,time_msc:1003000});
 e.tick(106,106.1,10);assert.equal(e.x.paperScores[0].closed,1);
 assert.equal(e.x.paperScores[0].losses,1);assert.equal(e.x.paperScores[0].invalid,0);
 assert.equal(e.x.paperDetails[0].endEvent.exit,89);
});
test('历史部分返回或下载失败保留持仓，重试不虚构退出',()=>{
 const e=env();e.tick(99.9,100);e.setHistoryError(4403);e.tick(106,106.1,10);
 assert.equal(e.x.paperScores[0].closed,0);assert.equal(e.x.paperScores[0].invalid,0);assert(e.x.paperTrades[0].recovering);
 e.setHistoryError(0);e.tick(101,101.1,11);assert.equal(e.x.paperScores[0].closed,1);
 assert.equal(e.x.paperDetails[0].endEvent.exit,105);
});
test('重启历史缺少入场锚点时不能拿当前价格补造盈亏',()=>{
 const e=env();e.tick(99.9,100);const r=env(e.file);r.tick(106,106.1,20);
 assert.equal(r.x.paperTrades.length,1);assert.equal(r.x.paperScores[0].closed,0);assert(r.x.paperTrades[0].recovering);
});
test('保存失败冻结同一事件，恢复后只提交一次并继续核对',()=>{
 const e=env();e.setFail(true);e.tick(99.9,100);
 assert(e.x.paperPending);assert.equal(e.x.paperTrades.length,0);
 e.setFail(false);e.tick(105,105.1,11);
 assert(!e.x.paperPending);assert.equal(e.x.paperScores[0].opened,1);
 assert.equal(e.x.paperScores[0].closed,1);assert.equal(e.x.paperScores[0].invalid,0);
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
 assert.equal(e.file.split('\tWAIT\t').length-1,5);assert.equal(e.x.paperScores[0].opened,0);
});
test('收益换算失败保留单据重试，不作废也不伪造收益',()=>{
 const e=env();e.tick(99.9,100);const calc=e.x.OrderCalcProfit;
 e.x.OrderCalcProfit=()=>({ok:false,gross:0});e.tick(105,105.1);
 assert.equal(e.x.paperScores[0].closed,0);assert.equal(e.x.paperScores[0].invalid,0);
 e.x.OrderCalcProfit=calc;e.tick(100,100.1,11);assert.equal(e.x.paperScores[0].closed,1);
});
test('60分钟规则对多空一致，费用为零时页面明确告知未扣佣金',()=>{
 const e=env();const t={sign:1,entry:100,opened:1};
 const out=e.x.PaperExit(t,{bid:101,ask:101.1,time_msc:3600001},0);assert.equal(out.why,'满60分钟退出');assert.equal(out.price,101);
 assert(body('PaperPanel').includes('费用尚未配置'));assert(body('PaperPanel').includes('每秒采样'));assert(body('PaperPanel').includes('查看本组模拟单'));
});
test('成绩单布局和明细按钮在固定面板内，不覆盖切换',()=>{
 const e=env(),bounds=[],buttons=[];install(e.x,'PaperPanel');
 Object.assign(e.x,{tradeMode:false,UI_TEXT:0,UI_WARN:1,UI_ACCENT:2,UI_ROW:3,UI_MUTED:4,UI_DIM:5,UI_GAIN:6,UI_LOSS:7,
  UIText:(t,x,y,w,size)=>bounds.push([x,y,w,size+4]),UICard:(x,y,w,h)=>bounds.push([x,y,w,h]),
  UIButton:(t,x,y,w,id)=>buttons.push({x,y,w,id}),panelCanvas:{Update:()=>{}}});
 e.x.PaperPanel();assert(bounds.every(([x,y,w,h])=>x>=0&&x+w<=560&&y>=0&&y+h<=654));
 assert.equal(buttons[0].id,205);assert.equal(buttons.filter(b=>b.id>=210&&b.id<215).length,5);
});

test('C轻收回，D保留明确趋势方向，E支持突破后回踩',()=>{
 const e=env(),b=[{time:900,open:100.1,close:100.8,low:100,high:101},
 {time:840,open:99.9,close:101,low:99.8,high:101.2},{time:780,open:99,close:99.5,low:98.5,high:100}];
 assert.equal(e.x.PaperReaction(2,100,1,b,2,0),1);
 assert.equal(e.x.PaperReaction(3,100,1,b,2,-1),0);
 assert.equal(e.x.PaperReaction(3,100,1,b,2,1),1);
 assert.equal(e.x.PaperReaction(4,100,0,b,2,1),1);
 assert.equal(e.x.PaperReaction(4,100,-1,b,2,1),0);
 b[2].close=101;assert.equal(e.x.PaperReaction(4,100,0,b,2,1),0);
});
test('C/D/E空头完全对称，冲击K线或离点过远不给候选',()=>{
 const e=env(),b=[{time:900,open:99.9,close:99.2,low:99,high:100},
 {time:840,open:100.1,close:99,low:98.8,high:100.2},{time:780,open:101,close:100.5,low:100,high:101.5}];
 for(const a of [2,3,4])assert.equal(e.x.PaperReaction(a,100,-1,b,2,-1),-1);
 b[0].low=90;for(const a of [2,3,4])assert.equal(e.x.PaperReaction(a,100,-1,b,2,-1),0);
});
test('晚收到的消息不能回看旧K触发C/D/E，收到时间不由原文时间冒充',()=>{
 const e=env();e.x.adaptiveBars=[{time:900,open:100.1,close:100.8,low:100,high:101},{time:840,open:99.9,close:101,low:99.8,high:101.2},{time:780,close:99}];
 e.x.adaptiveTrend=1;e.x.aiPlans[0].available=1000;
 for(const arm of [2,3,4])assert.match(e.x.PaperReactionStatus(0,{time:1001,ask:100.8,bid:100.7},arm,0),/尚未收到/);
 e.x.aiPlans[0].available=800;e.x.aiPlans[0].confirmed=800;
 assert.equal(e.x.PaperReactionStatus(0,{time:1001,ask:100.8,bid:100.7},2,0),'区间反应候选');
 assert.match(e.x.PaperReactionStatus(0,{time:1001,ask:100.8,bid:100.7},4,0),/尚未收到/);
});
test('模拟单列表固定布局并提供真正的分页入口',()=>{
 const e=env();e.tick(99.9,100);install(e.x,'PaperDetailPanel');
 const bounds=[],buttons=[];
 Object.assign(e.x,{UI_TEXT:0,UI_WARN:1,UI_ACCENT:2,UI_ROW:3,UI_MUTED:4,UI_DIM:5,UI_GAIN:6,UI_LOSS:7,
  UIText:(t,x,y,w,size)=>bounds.push([x,y,w,size+4]),UICard:(x,y,w,h)=>bounds.push([x,y,w,h]),
  UIButton:(t,x,y,w,id)=>buttons.push({x,y,w,id}),panelCanvas:{Update:()=>{}}});
 e.tick(105,105.1);e.x.PaperDetailPanel();
 assert(bounds.every(([x,y,w,h])=>x>=0&&x+w<=560&&y>=0&&y+h<=654));
 assert.deepEqual(buttons.slice(-3).map(b=>b.id),[216,217,218]);
});
test('模拟单明细随开平仓更新，并可从账本恢复',()=>{
 const e=env();e.tick(99.9,100);
 assert.equal(e.x.paperDetails.length,1);
 assert.equal(e.x.paperDetails[0].entryEvent.arm,0);
 assert.equal(e.x.paperDetails[0].endEvent.kind,'');
 e.tick(105,105.1);
 assert.equal(e.x.paperDetails[0].endEvent.kind,'CLOSE');
 assert.equal(e.x.paperDetails[0].endEvent.why,'止盈');
 const r=env(e.file);assert.equal(r.x.paperDetails.length,1);
 assert.equal(r.x.paperDetails[0].endEvent.kind,'CLOSE');
});
test('五组同一轮运行各自开仓与恢复，展示选择不改变策略',()=>{
 const e=env();e.x.aiPlans[0].confirmed=700;e.x.aiPlans[0].available=700;observe(e);
 e.x.adaptiveBars=[{time:900,open:100.1,close:100.8,low:100,high:101},
 {time:840,open:99.9,close:101,low:99.8,high:101.2},{time:780,close:99.5}];e.x.adaptiveTrend=1;
 e.tick(100.7,100.8);assert.equal(e.x.paperTrades.length,5);
 assert.deepEqual(Array.from(e.x.paperScores,s=>s.opened),[1,1,1,1,1]);
 const r=env(e.file);assert.equal(r.x.paperTrades.length,5);
 r.history.push(...e.history);r.tick(120,120.1,5);
 for(let i=0;i<4;i++)r.tick(120,120.1);
 assert.deepEqual(Array.from(r.x.paperScores,s=>s.invalid),[0,0,0,0,0]);
 assert.deepEqual(Array.from(r.x.paperScores,s=>s.closed),[1,1,1,1,1]);
});
test('旧GAP追加补算事件，重启和重复尾行不重复计账',()=>{
 const e=env();e.tick(99.9,100);
 const t=e.x.paperTrades[0],gap={};e.x.PaperFromTrade(t,{time_msc:1002000},gap);
 gap.kind='GAP';gap.why='old gap';assert(e.x.PaperEmit(gap));e.x.paperRepairRetry=0;
 e.tick(105,105.1,2);
 assert.equal(e.x.paperScores[0].closed,1);assert.equal(e.x.paperScores[0].repaired,1);
 assert.equal(e.x.paperScores[0].invalid,0);assert.match(e.file,/\tGAP\t/);assert.match(e.file,/\tREPAIR\t/);
 const last=e.file.trim().split(/\r?\n/).filter(Boolean).at(-1);
 const r=env(e.file+'\r\n'+last+'\r\n');
 assert(r.x.paperReady);assert.equal(r.x.paperScores[0].closed,1);assert.equal(r.x.paperScores[0].invalid,0);
});
test('补算按历史结束顺序重算回撤，不按修复写入顺序算',()=>{
 const x=env().x;
 x.PaperSettle({id:2,msc:200,arm:0,gross:-10,fee:0});
 x.PaperSettle({id:1,msc:100,arm:0,gross:20,fee:0});
 assert.equal(x.paperScores[0].net,10);assert.equal(x.paperScores[0].peak,20);assert.equal(x.paperScores[0].drawdown,10);
});
test('列表超过一页可见全部记录，切组不串单，不创建任何图像',()=>{
 const x=env().x, texts=[],buttons=[];
 for(let i=1;i<=12;i++)x.PaperRemember({kind:'OPEN',id:i,arm:i===12?1:0,sign:1,msc:i*1000,entry:100,volume:.02,level:100});
 Object.assign(x,{UI_TEXT:0,UI_WARN:1,UI_GAIN:2,UI_LOSS:3,UI_MUTED:4,UI_DIM:5,UI_ROW:6,
  UIText:t=>texts.push(t),UICard:()=>{},UIButton:(t,a,b,c,id)=>buttons.push(id),panelCanvas:{Update:()=>{}}});
 x.PaperDetailPanel();assert(texts.some(t=>t.startsWith('BUY #11')));assert(!texts.some(t=>t.startsWith('BUY #6 ')));
 x.PaperDetailAction(217);texts.length=0;x.PaperDetailPanel();assert(texts.some(t=>t.startsWith('BUY #6 ')));
 x.PaperDetailAction(217);texts.length=0;x.PaperDetailPanel();assert(texts.some(t=>t.startsWith('BUY #1 ')));
 x.PaperDetailAction(217);assert.equal(x.paperListPage,2);x.PaperDetailAction(216);assert.equal(x.paperListPage,1);
 assert(!/ReviewNavigate|ObjectCreate/.test(body('PaperDetailPanel')));
});

test('异步历史任务不会被后加入的模拟仓抢占卡死',()=>{
 const e=env(),x=e.x;e.tick(99.9,100);
 x.BarsCalculated=()=>0;e.tick(106,106.1,6);const owner=x.paperHistoryId;assert(owner>0);
 for(let n=0;n<3;n++)assert(x.PaperEmit({kind:'OPEN',id:0,arm:1,sign:1,msc:1007000,bar:0,level:110+n*3,
  entry:110,volume:.02,gross:0,fee:0,mfe:0,mae:0,exit:0,source:'test',why:'test'}));
 x.BarsCalculated=()=>1;e.tick(106,106.1,6);
 assert.equal(x.PaperFind(owner),-1);assert.equal(x.paperScores[0].closed,1);
});

test('只隐藏GAP，正常亏损保留；点选一单只画小字入出，翻页清除',()=>{
 const x=env().x;
 for(let id=1;id<=3;id++){
  x.PaperRemember({kind:'OPEN',id,arm:0,sign:1,msc:id*1000,entry:100,volume:.02,level:100});
  x.PaperRemember({kind:id===1?'GAP':'CLOSE',id,arm:0,msc:id*1000+500,exit:90,gross:-10,fee:0});
 }
 assert.equal(x.PaperDetailCount(),2);
 x.paperRowIds=[3,2,0,0,0];x.PaperDetailAction(220);
 assert.equal(x.paperReviewId,3);assert.equal(x.marks.size,3);
 assert.deepEqual([...x.marks.values()].filter(m=>m.text).map(m=>m.text),['入','出']);
 x.PaperDetailAction(221);assert.equal(x.paperReviewId,2);assert.equal(x.marks.size,3);
 x.PaperDetailAction(221);assert.equal(x.paperReviewId,0);assert.equal(x.marks.size,0);
 x.PaperDetailAction(220);x.PaperDetailAction(217);assert.equal(x.marks.size,0);
 x.paperPressedId=2;x.PaperDetailAction(220);assert.equal(x.paperReviewId,0);
 assert(!sources[3].includes('OBJ_ARROW'));
});

test('B不再要求历史两端反复触碰，但另一端必须有效且当时已收到',()=>{
 for(const type of ['valid','cancel','watch','late','same','none']){
  const e=env();observe(e);
  if(type==='cancel')e.x.aiPlans[1].feedState='CANCELLED';
  if(type==='watch')e.x.aiPlans[1].kind='WATCH';
  if(type==='late')e.x.aiPlans[1].available=1000;
  if(type==='same')e.x.aiPlans[1].sign=1;
  if(type==='none')e.x.aiPlans.pop();
  e.tick(100.7,100.8);
  assert.equal(e.x.paperScores[1].opened,type==='valid'?1:0,type);
 }
});
test('C接受轻收回、小实体和有限刺穿，多空对称；超出区域仍拒绝',()=>{
 const x=env().x;
 for(const sign of [1,-1]){
  const map=p=>100+sign*(p-100);
  const b=[{time:900,open:map(100.3),close:map(100.2),low:sign>0?98.7:99.5,high:sign>0?100.5:101.3},{time:840,close:100},{time:780,close:100}];
  assert.equal(x.PaperReaction(2,100,sign,b,2,0),sign);
  b[0].close=map(102.1);assert.equal(x.PaperReaction(2,100,sign,b,2,0),0);
 }
});
test('D在M5中性时可按连续M1推进开单，明确反向M5仍不做',()=>{
 for(const sign of [1,-1]){
  const e=env(),map=p=>100+sign*(p-100);
  e.x.aiPlans=[plan({sign,available:700,confirmed:700})];
  e.x.adaptiveBars=[{time:900,open:map(100.5),close:map(100.6),low:sign>0?100:99.2,high:sign>0?100.8:100},
   {time:840,close:map(100.2)},{time:780,close:map(99.9)}];
  e.tick(sign>0?100.5:99.4,sign>0?100.6:99.5);
  assert.equal(e.x.paperScores[3].opened,1);
  e.x.adaptiveTrend=-sign;assert.equal(e.x.PaperDirection(3,0),0);
 }
});
test('E刚收盘突破可跟进，无需等下一根；不追超过两点的价格',()=>{
 for(const sign of [1,-1]){
  const e=env(),map=p=>100+sign*(p-100);
  e.x.aiPlans=[plan({sign,confirmed:700,available:700})];
  e.x.adaptiveBars=[{time:900,open:map(99.8),close:map(100.8),low:99,high:101},
   {time:840,close:map(99.8)},{time:780,close:map(99.5)}];
  assert.equal(e.x.PaperBreakBar(100,sign,e.x.adaptiveBars,2),0);
  assert.match(e.x.PaperReactionStatus(0,{time:1001,bid:102.1,ask:102.2},4,0),/不追价/);
  e.tick(sign>0?100.7:99.2,sign>0?100.8:99.3);
  assert.equal(e.x.paperScores[4].opened,1);
 }
});
test('E第三根回踩仍可进，第四根、途中失守或消息前的突破不复用',()=>{
 const e=env(),x=e.x;x.aiPlans=[plan({confirmed:600,available:600,sign:1})];
 x.adaptiveBars=[
  {time:900,open:100.7,close:100.8,low:100.1,high:101},
  {time:840,close:101,low:100.8,high:101.5},
  {time:780,close:101.3,low:101,high:101.5},
  {time:720,open:99.8,close:100.8,low:99.7,high:101},
  {time:660,close:99.8}];
 assert.equal(x.PaperBreakBar(100,1,x.adaptiveBars,2),3);
 assert.equal(x.PaperReactionStatus(0,{time:1001,bid:100.7,ask:100.8},4,0),'区间反应候选');
 x.aiPlans[0].available=700;
 assert.match(x.PaperReactionStatus(0,{time:1001,bid:100.7,ask:100.8},4,0),/尚未收到/);
 x.aiPlans[0].available=600;
 assert.match(x.PaperReactionStatus(0,{time:1001,bid:100.7,ask:100.8},4,700),/消息或冲击/);
 x.adaptiveBars[1].close=100.1;assert.equal(x.PaperDirection(4,0),0);
 x.adaptiveBars[1].close=101;
 x.adaptiveBars.unshift({time:960,open:100.7,close:100.8,low:100,high:101});
 assert.equal(x.PaperDirection(4,0),0);
});
test('放宽B-E仍受参考点、消息、冲击和点差门槛约束',()=>{
 for(const type of ['watch','news','shock','spread']){
  const e=env();observe(e);
  e.x.aiPlans[0].available=700;e.x.aiPlans[0].confirmed=700;e.x.adaptiveTrend=1;
  e.x.adaptiveBars[1]={time:840,open:99.8,close:100.8,low:99.5,high:101};
  e.x.adaptiveBars[2]={time:780,close:99.5};
  if(type==='watch')e.x.aiPlans[0].kind='WATCH';
  if(type==='news')e.x.AdaptiveNewsState=()=>'消息窗口';
  if(type==='shock')e.x.adaptiveShockUntil=1100;
  e.tick(100.7,type==='spread'?101.7:100.8);
  assert.deepEqual(Array.from(e.x.paperScores,s=>s.opened),[0,0,0,0,0],type);
 }
});
test('新策略使用独立账本版本，不把旧策略盈亏混入',()=>{
 assert(env().x.PaperPolicy().startsWith('P3/five-arms-v1.79/'));
});
console.log(checks+' paper checks passed; synthetic quotes/files, no broker trading, no profitability claim');
