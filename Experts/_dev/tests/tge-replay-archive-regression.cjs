// Production archive bodies, synthetic in-memory files. No broker access.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const source=fs.readFileSync('Include/Journal/TgeReplayArchive.mqh','utf8');
function body(name){
 const at=source.search(new RegExp('^(?:void|bool|string) '+name+'\\(','m'));
 assert(at>=0,name);let start=source.indexOf('{',at),end=start+1,n=1;
 for(;n;end++){if(source[end]==='{')n++;if(source[end]==='}')n--;}
 return source.slice(start+1,end-1);
}
function env(){
 let now=1000,mono=1000000,file='',fail=false,error=0,opens=0;
 const x=vm.createContext({
  启用历史归档:true,replayStarted:true,replayQuotes:Array.from({length:4096},()=>({})),
  replayQuoteCount:0,replayFile:-1,replaySequence:0,replayDropped:0,replayPreviousMSC:0,
  replayBar:0,replayRetry:0,replayBuffer:'',replayDay:'',replaySession:'session',
  replayFeed:'',replayState:'',replayHealth:'',prefix:'test.',adaptiveBars:[],aiPlans:[],
  adaptiveShockUntil:0,adaptiveRecoverUntil:0,adaptiveTrend:0,adaptiveATR:2,aiReason:'ready',
  TimeGMT:()=>now,TimeCurrent:()=>now,GetTickCount64:()=>mono,
  StringReplace:(s,a,b)=>s.split(a).join(b),StringLen:s=>s.length,
  StringSplit:(s,d,a)=>{a.splice(0,a.length,...s.split(d));return a.length;},
  ArraySize:a=>a.length,IntegerToString:String,DoubleToString:(n,d)=>n.toFixed(d),
  TimeToString:()=>now<2000?'2026.10.16':'2026.10.17',TIME_DATE:1,
  FILE_READ:1,FILE_WRITE:2,FILE_TXT:4,FILE_ANSI:8,FILE_COMMON:16,FILE_SHARE_READ:32,
  CP_UTF8:65001,INVALID_HANDLE:-1,SEEK_END:2,
  Hash:s=>{let h=2166136261;for(const c of s)h=Math.imul(h^c.charCodeAt(0),16777619)>>>0;return h;},
  FolderCreate:()=>true,FileOpen:()=>{opens++;return 1;},FileSeek:()=>true,
  ResetLastError:()=>{error=0;},GetLastError:()=>error,FileFlush:()=>{},
  FileWriteString:(h,s)=>{file+=s;if(fail)error=1;return Buffer.byteLength(s);},
  FileClose:()=>{},AdaptiveMarketFresh:()=>true,AdaptiveNewsState:()=>'',
  AIChannelReady:()=>true,PaperPolicy:()=>'five',PlanLifeReason:()=>'',Print:()=>{}
 });
 for(const [name,args] of [['ReplayEscape','text'],['ReplayRecord','kind,payload,marketMSC,utc,mono'],
 ['ReplayCapture','q'],['ReplayAccepted','lines'],['ReplayFlush',''],['ReplayPoll',''],['StopReplay','']]){
  let s=body(name).replace(/\((?:int|long)\)/g,'')
   .replace(/\bstring (\w+)\[\];/g,'let $1=[];')
   .replace(/\b(?:string|int|uint|long|datetime|MqlTick|MqlRates)\s+/g,'let ')
   .replace(/StringReplace\((text|day),([^;]+)\);/g,'$1=StringReplace($1,$2);')
   .replace('replayQuotes[replayQuoteCount].q=q','replayQuotes[replayQuoteCount].q={...q}');
  vm.runInContext('function '+name+'('+args+'){'+s+'}',x);
 }
 return {x,get file(){return file;},get opens(){return opens;},fail:v=>fail=v,time:n=>{now=n;mono=n*1000;}};
}
function records(file){return file.split(/\r?\n/).filter(Boolean).map(l=>{
 const f=l.split('\t');assert.equal(f.length,9);assert.equal(f[8],'END');return f;
});}
let count=0;function test(name,fn){fn();count++;console.log('PASS '+name);}
test('Unicode and embedded separators remain one checksummed record',()=>{
 const e=env();e.x.ReplayRecord('TEST','点位\t4180\n方向\\BUY\r',0,1000,1);
 const r=records(e.x.replayBuffer)[0];assert.equal(r[6],'点位\\t4180\\n方向\\\\BUY\\r');
 assert.equal(+r[7],e.x.Hash(r.slice(0,7).join('\t')));
});
test('Accepted versions deduplicate heartbeat, retain change and cancellation',()=>{
 const e=env(),snap=(t,active,row)=>['TGA,9,'+t+','+active+',XAUUSD.c,1,note',row,'END,1'];
 e.x.ReplayAccepted(snap(1,1,'4180,BUY'));e.x.ReplayAccepted(snap(2,1,'4180,BUY'));
 e.x.ReplayAccepted(snap(3,1,'4180,SELL'));e.x.ReplayAccepted(snap(4,0,'4180,SELL'));
 assert.equal(records(e.x.replayBuffer).length,3);
});
test('Ambiguous write retries retain sequence/content; consumer can deduplicate',()=>{
 const e=env();e.x.ReplayRecord('TEST','one',0,1000,1);const frozen=e.x.replayBuffer;
 e.fail(true);assert.equal(e.x.ReplayFlush(),false);assert.equal(e.x.replayBuffer,frozen);
 e.fail(false);assert.equal(e.x.ReplayFlush(),false);e.time(1010);
 assert.equal(e.x.ReplayFlush(),true);assert.equal(e.x.replayBuffer,'');
 const r=records(e.file);assert.equal(r.length,2);assert.deepEqual(r[0],r[1]);
});
test('Quote capture has no disk calls and bounded overflow emits GAP',()=>{
 const e=env(),q={time_msc:1000000,bid:100,ask:100.1,last:100,volume:1,flags:2,volume_real:1};
 for(let i=0;i<4097;i++)e.x.ReplayCapture(q);
 q.bid=200;assert.equal(e.x.replayQuotes[0].q.bid,100);assert.equal(e.opens,0);
 assert.equal(e.x.replayQuoteCount,4096);assert.equal(e.x.replayDropped,1);
 e.x.ReplayPoll();const r=records(e.file);
 assert.equal(r.filter(v=>v[2]==='QUOTE').length,4096);
 assert(r.some(v=>v[2]==='GAP'&&v[6].includes('dropped=1')));
});
test('Quote gaps, closed bar gaps and local observation times stay explicit',()=>{
 const e=env(),q=t=>({time_msc:t,bid:100,ask:100.1,last:100,volume:1,flags:2,volume_real:1});
 e.x.replayPreviousMSC=990000;e.x.replayBar=780;
 e.x.adaptiveBars=[{time:900,open:100,high:102,low:99,close:101,tick_volume:10,spread:10,real_volume:0}];
 e.x.ReplayCapture(q(1000000));e.x.ReplayPoll();e.x.ReplayPoll();
 const r=records(e.file);assert.equal(r.filter(v=>v[2]==='CLOSED_M1').length,1);
 assert.equal(r.filter(v=>v[2]==='GAP').length,2);
 const b=r.find(v=>v[2]==='CLOSED_M1');assert.equal(+b[3],1000);assert.equal(+b[5],900000);
});
test('Full buffer rejects version advance, rotation and session end remain recoverable',()=>{
 const e=env();e.x.replayBuffer='x'.repeat(2000001);
 e.x.ReplayAccepted(['TGA,9,1,1,XAUUSD.c,0,note','END,0']);
 assert.equal(e.x.replayFeed,'');assert.equal(e.x.replayDropped,1);
 e.x.replayBuffer='';e.x.ReplayFlush();e.time(2000);
 e.x.ReplayRecord('TEST','day',0,2000,1);e.x.ReplayFlush();assert.equal(e.x.replayFile,-1);
 e.x.StopReplay();assert.equal(e.opens,2);assert.equal(e.x.replayStarted,false);
 assert(records(e.file).some(v=>v[2]==='SESSION_END'));
});
assert(!/File(?:Open|Write|Flush)|CopyTicks|CopyRates/.test(body('ReplayCapture')));
console.log(count+' archive checks passed; synthetic files only');
