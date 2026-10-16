// Production MQL bodies with an isolated virtual terminal/filesystem; never connects to MT5.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const life=fs.readFileSync('Include/Journal/TgeLifecycle.mqh','utf8'),stats=fs.readFileSync('Include/Journal/TgeStatistics.mqh','utf8');
function body(src,name){
 const a=src.search(new RegExp('^(?:void|bool|string) '+name+'\\(','m'));assert(a>=0,name);
 const b=src.indexOf('{',a);let z=b+1,n=1;for(;n;z++){if(src[z]==='{')n++;if(src[z]==='}')n--;}return src.slice(b+1,z-1);
}
function install(x,src,name,args=''){
 let s=body(src,name).replace(/C'(\d+),(\d+),(\d+)'/g,'"$1,$2,$3"')
 .replace(/\((?:ulong|uint|long|int|datetime|ENUM_TIMEFRAMES)\)/g,'')
 .replace(/\b(?:TgeLifeEvent|MqlRates|string) (\w+)\[\];/g,'let $1=[];')
 .replace(/\b(?:TgeLifeEvent|MqlTick) (\w+);/g,'let $1={};')
 .replace(/\b(?:const )?(?:TgeLifeEvent|ulong|uint|datetime|double|int|long|string|bool)\s+/g,'let ')
 .replace(/StringReplace\(text,([^;]+)\);/g,'text=text.replaceAll($1);')
 .replace('(ArraySize(reviewEvents)-1)/4','Math.floor((ArraySize(reviewEvents)-1)/4)');
 vm.runInContext('function '+name+'('+args+'){'+s+'}',x);
}
function env(){
 let now=1000,clock=10000,micro=0,error=0,fail=false,reads=0,selected;
 let positions=[{id:77,open:100,sl:90,tp:110,volume:.02,type:0,own:true}],quote={bid:101,ask:101.1},deals=[];
 const disk=new Map(),handles=new Map(),chartCalls=[];let next=1,first=120,historyOK=true;
 const x=vm.createContext({
  Math,MathMax:Math.max,MathMin:Math.min,MathAbs:Math.abs,MathRound:Math.round,MathIsValidNumber:Number.isFinite,
  lifeQueue:[],lifeWatch:[],lifeRevision:0,lifeRetryAt:0,lifeStatus:'',lifeEntryContext:'',
  prefix:'account.symbol.magic.',lockHandle:1,accountLogin:1,accountServer:'server',ACCOUNT_LOGIN:1,ACCOUNT_SERVER:2,
  AccountInfoInteger:()=>1,AccountInfoString:()=>'server',_Digits:2,_Symbol:'XAUUSD.c',_Period:5,VIEW:'TGE_',
  TimeCurrent:()=>now,GetTickCount64:()=>clock,GetMicrosecondCount:()=>++micro,IntegerToString:String,DoubleToString:(v,d)=>v.toFixed(d),
  StringToInteger:Number,StringToDouble:Number,StringSplit:(s,sep,a)=>{a.splice(0,a.length,...s.split(sep));return a.length;},
  Number:(s,decimal)=>decimal?/^-?\d+(\.\d+)?$/.test(s):/^\d+$/.test(s),
  ArraySize:a=>a.length,ArrayResize:(a,n)=>{while(a.length<n)a.push({});a.length=n;},
  ZeroMemory:e=>{for(const k of ['id','order','deal','at','price','volume','sl','tp','mfe','mae','sign','open','saved'])e[k]=0;for(const k of ['key','kind','detail'])e[k]='';e.seen=false;},
  FILE_COMMON:1,FILE_READ:2,FILE_WRITE:4,FILE_TXT:8,FILE_ANSI:16,FILE_SHARE_READ:32,CP_UTF8:65001,INVALID_HANDLE:-1,SEEK_END:2,
  FileIsExist:p=>disk.has(p),FolderCreate:()=>true,ResetLastError:()=>error=0,GetLastError:()=>error,
  FileOpen:(p,flags)=>{if(!disk.has(p)){if(!(flags&4))return -1;disk.set(p,'');}let h=next++;handles.set(h,{p,at:0});return h;},
  FileIsEnding:h=>{const o=handles.get(h);return o.at>=disk.get(o.p).length;},
  FileReadString:h=>{reads++;const o=handles.get(h),s=disk.get(o.p);let z=s.indexOf('\n',o.at);if(z<0)z=s.length;let line=s.slice(o.at,z).replace(/\r$/,'');o.at=z+1;return line;},
  FileSeek:h=>{const o=handles.get(h);o.at=disk.get(o.p).length;},
  FileWriteString:(h,s)=>{if(fail){error=5000;return 0;}const o=handles.get(h);disk.set(o.p,disk.get(o.p)+s);return Buffer.byteLength(s);},
  FileFlush:()=>{},FileClose:h=>handles.delete(h),
  TerminalInfoInteger:()=>true,TERMINAL_CONNECTED:1,FreshQuote:q=>Object.assign(q,quote),TickSize:()=>.01,
  PositionsTotal:()=>positions.length,PositionGetTicket:i=>{selected=positions[i];return selected.id;},OwnSelected:()=>selected.own,
  PositionGetInteger:k=>selected[k],PositionGetDouble:k=>selected[k],POSITION_IDENTIFIER:'id',POSITION_PRICE_OPEN:'open',
  POSITION_SL:'sl',POSITION_TP:'tp',POSITION_VOLUME:'volume',POSITION_TYPE:'type',POSITION_TYPE_BUY:0,
  pending:{kind:1,position:0,at:900,order:88,level:100,volume:.02,sl:90,tp:110,originHash:123,exitFirst:105,entryAtr:2,adaptive:true},
  reviewEvents:[],reviewId:0,reviewStatsRevision:0,reviewLifeRevision:0,reviewRetryAt:0,reviewPage:0,
  reviewProcess:false,reviewReady:false,reviewChartActive:false,reviewOldAuto:false,reviewNavTime:0,reviewNavAttempts:0,reviewNotice:'',
  statsRevision:1,StatsExitText:r=>['桌面','手机','EA','SL','TP'][r]||'其他',StatsMoney:v=>v.toFixed(2),
  HistorySelectByPosition:()=>historyOK,HistoryDealsTotal:()=>deals.length,HistoryDealGetTicket:i=>deals[i].deal,
  HistoryDealGetInteger:(t,k)=>deals.find(d=>d.deal===t)[k]||0,HistoryDealGetString:(t,k)=>deals.find(d=>d.deal===t)[k]||'',
  HistoryDealGetDouble:(t,k)=>deals.find(d=>d.deal===t)[k]||0,
  DEAL_POSITION_ID:'id',DEAL_SYMBOL:'symbol',DEAL_TYPE:'type',DEAL_ENTRY:'entry',DEAL_TIME:'at',DEAL_ORDER:'order',
  DEAL_PRICE:'price',DEAL_VOLUME:'volume',DEAL_PROFIT:'profit',DEAL_COMMISSION:'commission',DEAL_SWAP:'swap',DEAL_FEE:'fee',
  DEAL_REASON:'reason',DEAL_TYPE_BUY:0,DEAL_TYPE_SELL:1,DEAL_ENTRY_IN:0,DEAL_ENTRY_OUT:1,DEAL_ENTRY_OUT_BY:3,
  CHART_AUTOSCROLL:1,CHART_WIDTH_IN_PIXELS:2,CHART_VISIBLE_BARS:3,CHART_FIRST_VISIBLE_BAR:4,CHART_END:1,
  ChartGetInteger:(id,k)=>({1:1,2:1920,3:150,4:first})[k],
  ChartSetInteger:(...a)=>{chartCalls.push(['set',...a]);return true;},
  ChartNavigate:(id,base,delta)=>{chartCalls.push(['navigate',id,base,delta]);first=120-delta;return true;},ChartRedraw:()=>{},
  CopyRates:(symbol,period,at,count,out)=>{out.push({time:Math.floor(at/300)*300});return 1;},
  iBarShift:()=>300,PeriodSeconds:()=>300,uiX:8,panelWidth:760,
  ObjectCreate:()=>true,ObjectMove:()=>true,ObjectSetInteger:()=>true,ObjectSetString:()=>true,
  ObjectsDeleteAll:(...a)=>chartCalls.push(['delete',...a]),OBJ_VLINE:1,OBJPROP_COLOR:1,OBJPROP_STYLE:2,OBJPROP_WIDTH:3,
  OBJPROP_BACK:4,OBJPROP_SELECTABLE:5,OBJPROP_TOOLTIP:6,STYLE_DASH:1,TIME_DATE:1,TIME_SECONDS:2,TimeToString:String
 });
 for(const [n,a]of [['LifePath','id'],['LifeClean','text'],['LifeParse','line,id,e'],['LifeRead','id,rows'],['LifeAppend','e'],['LifeEnqueue','e'],['LifeDecision','event,detail,retcode,deal'],['LifeEntry','id'],['LifeFlush',''],['LifePoll','']])install(x,life,n,a);
 for(const [n,a]of [['ReviewKind','kind'],['ReviewLoad','tr'],['ReviewClearMarkers',''],['ReviewNavigate',''],['ReviewReturnLive','navigate=true']])install(x,stats,n,a);
 return {x,disk,chartCalls,getReads:()=>reads,setNow:t=>{now=t;clock=t*1000;},setFailure:f=>fail=f,setPositions:p=>positions=p,
  setQuote:q=>quote=q,setDeals:d=>deals=d,setHistory:b=>historyOK=b,positions};
}
let checks=0;function test(n,f){f();checks++;console.log('PASS '+n);}
test('framed UTF8 journal round trips Chinese; newline/tab payload cannot forge rows',()=>{
 const {x,disk}=env();x.lifeEntryContext='中文\t原判断\nEND';x.LifeEntry(77);x.LifeFlush();
 const rows=[];assert(x.LifeRead(77,rows));assert.equal(rows.length,1);assert.equal(rows[0].id,77);assert(rows[0].detail.includes('中文 原判断 END'));
 const key=x.LifePath(77);disk.set(key,disk.get(key)+'\nL1\tbroken');
 const r=[];x.LifeRead(77,r);assert.equal(r.length,1);
});
test('PLAN retries, partial fill repeated binding and process restart are idempotent',()=>{
 const e=env();e.x.LifeEntry(77);e.x.LifeEntry(77);assert.equal(e.x.lifeQueue.length,1);e.x.LifeFlush();
 e.x.LifeEntry(77);e.x.LifeFlush();const rows=[];e.x.LifeRead(77,rows);assert.equal(rows.length,1);
 const f=env();for(const [k,v]of e.disk)f.disk.set(k,v);f.x.LifeEntry(77);f.x.LifeFlush();const restored=[];f.x.LifeRead(77,restored);assert.equal(restored.length,1);
});
test('write failure retains bounded queue and retries without changing trade pending',()=>{
 const e=env();const before=JSON.stringify(e.x.pending);e.setFailure(true);e.x.LifeEntry(77);e.x.LifeFlush();
 assert.equal(e.x.lifeQueue.length,1);assert(e.x.lifeStatus.includes('失败'));assert.equal(JSON.stringify(e.x.pending),before);
 e.setFailure(false);e.setNow(1020);e.x.LifeFlush();assert.equal(e.x.lifeQueue.length,0);
});
test('journal flush budget is eight records and full queue explicitly reports gaps',()=>{
 const {x}=env();for(let i=0;i<520;i++)x.LifeEnqueue({id:77,key:'k'+i,kind:'SAMPLE',at:1,order:0,deal:0,price:0,volume:0,sl:0,tp:0,mfe:0,mae:0,detail:''});
 assert.equal(x.lifeQueue.length,512);assert(x.lifeStatus.includes('缺失'));x.LifeFlush();assert.equal(x.lifeQueue.length,504);
});
test('actual SL/volume observation and sampled excursions survive restart; requests remain distinct',()=>{
 const e=env();e.x.LifePoll();assert.equal(e.x.lifeWatch[0].mfe,1);
 e.setNow(1001);e.setQuote({bid:98,ask:98.1});e.positions[0].sl=99;e.positions[0].volume=.01;e.x.LifePoll();
 const rows=[];e.x.LifeRead(77,rows);assert.equal(rows.length,2);assert.equal(rows[1].kind,'POSITION');assert.equal(rows[1].mae,2);
 const f=env();for(const [k,v]of e.disk)f.disk.set(k,v);f.x.LifePoll();assert.equal(f.x.lifeWatch[0].mae,2);
 e.setPositions([]);e.setNow(1002);e.x.LifePoll();const ended=[];e.x.LifeRead(77,ended);
 assert.equal(ended.at(-1).kind,'OBSERVE_END');assert(!ended.some(r=>r.kind==='POSITION_CLOSED'));
});
test('unchanged one-second samples do not write a new row until 60 seconds',()=>{
 const {x,setNow}=env();x.LifePoll();for(let t=1001;t<1060;t++){setNow(t);x.LifePoll();}
 const rows=[];x.LifeRead(77,rows);assert.equal(rows.length,1);setNow(1060);x.LifePoll();const r=[];x.LifeRead(77,r);assert.equal(r.length,2);
});
test('duplicate instance and changed account cannot journal under another lifecycle scope',()=>{
 for(const mode of ['lock','account']){const {x,disk}=env();if(mode==='lock')x.lockHandle=-1;else x.AccountInfoInteger=()=>2;x.LifePoll();assert.equal(disk.size,0);}
});
test('review uses every actual partial deal, including manual exit; scoped cache skips repeat file reads',()=>{
 const e=env();e.x.LifeEntry(77);e.x.LifeFlush();
 e.setDeals([
 {id:77,symbol:'XAUUSD.c',deal:1,order:11,type:0,entry:0,at:900,price:100,volume:.02,commission:-.2,reason:2},
 {id:77,symbol:'XAUUSD.c',deal:2,order:12,type:1,entry:1,at:950,price:105,volume:.01,profit:5,reason:2},
 {id:77,symbol:'XAUUSD.c',deal:3,order:13,type:1,entry:1,at:980,price:108,volume:.01,profit:8,reason:1},
 {id:99,symbol:'XAUUSD.c',deal:4,type:1,entry:1,at:990,volume:5}
 ]);
 e.x.ReviewLoad({id:77});assert.equal(e.x.reviewEvents.filter(r=>r.kind==='DEAL_OUT').length,2);
 assert(e.x.reviewEvents.find(r=>r.deal===3).detail.includes('手机'));const reads=e.getReads();e.x.ReviewLoad({id:77});assert.equal(e.getReads(),reads);
 assert(e.x.reviewReady);assert.equal(e.x.reviewEvents.length,4);
});
test('failed history is retried after delay instead of publishing invented empty lifecycle',()=>{
 const e=env();e.setHistory(false);e.x.ReviewLoad({id:77});assert(!e.x.reviewReady);e.setHistory(true);e.setNow(1006);e.x.ReviewLoad({id:77});assert(e.x.reviewReady);
});
test('historical navigation lands right of panel and restoring live preserves auto-scroll preference',()=>{
 const {x,chartCalls}=env();x.reviewNavTime=900;x.ReviewNavigate();assert(x.reviewChartActive);assert.equal(x.reviewNavTime,0);
 const nav=chartCalls.filter(c=>c[0]==='navigate');assert.equal(nav.length,2);assert(nav[1][3]<0);
 assert.equal(x.reviewOldAuto,true);x.ReviewReturnLive();assert(!x.reviewChartActive);assert(chartCalls.some(c=>c[0]==='set'&&c[3]===true));
});
test('missing candles have bounded retries, no jump to a nearby day, no trade state changes',()=>{
 const {x,chartCalls}=env();x.CopyRates=()=>0;x.reviewNavTime=900;
 const before=JSON.stringify(x.pending);for(let i=0;i<10;i++)x.ReviewNavigate();
 assert.equal(x.reviewNavTime,0);assert(x.reviewNotice.includes('不可用'));assert.equal(chartCalls.length,0);assert.equal(JSON.stringify(x.pending),before);
});
test('journal/review source cannot send broker requests or clear trade pending',()=>{
 for(const s of [life,stats.slice(stats.indexOf('TgeLifeEvent reviewEvents'),stats.indexOf('void StatsAction'))]){
 assert(!/OrderSend|PositionOpen|PositionClose|PositionModify|ClearPending|Store\(/.test(s));
 }
});

console.log(checks+' lifecycle journal/review regression cases passed');
