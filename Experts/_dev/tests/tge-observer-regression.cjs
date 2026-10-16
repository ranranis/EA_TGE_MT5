// Runs production observer bodies with frozen synthetic closed bars. No terminal/order API.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync('Include/View/TgeEntryObserver.mqh','utf8');
const main=fs.readFileSync('EA_T哥点位跟单.mq5','utf8');
function body(name){
 const re=new RegExp('^(?:void|bool|string) '+name+'\\(','m'),at=src.search(re);assert(at>=0,name);
 const start=src.indexOf('{',at);let end=start+1,n=1;
 for(;n;end++){if(src[end]==='{')n++;if(src[end]==='}')n--;}
 return src.slice(start+1,end-1);
}
const x=vm.createContext({MathMax:Math.max,MathMin:Math.min,MathAbs:Math.abs,MathIsValidNumber:Number.isFinite,
 ArraySize:a=>a.length,TickSize:()=>.01,TEACHER_BAND:1,最大点差价格:.5,观察收回ATR倍数:.25,
 观察最小区间ATR倍数:2,观察边界最少反应次数:2,entryObservations:[],_Symbol:'XAUUSD.c',
 Number:(s,decimal)=>decimal?/^\d+(?:\.\d+)?$/.test(s):/^\d+$/.test(s),
 StringToDouble:Number,StringToInteger:Number,StringSplit:(s,sep,out)=>{out.push(...s.split(sep));return out.length;}
});
function install(n,args){
 const s=body(n).replace(/\((?:int|datetime)\)/g,'').replace(/string f\[\];/g,'let f=[];')
 .replace(/int numeric\[\]=\{([^}]+)\};/g,'let numeric=[$1];')
 .replace(/\b(?:int|bool|double|string|long|TgeObservation)\s+/g,'let ');
 vm.runInContext('function '+n+'('+args+'){'+s+'}',x);
}
install('ObserverClassify','bars,lower,upper,atrValue,spread,out');
install('ObserverDeduplicate','bars,r');install('ObserverParse','line,r');
function bars(){
 const b=Array.from({length:20},(_,i)=>({time:10000-i*60,open:105,high:106,low:104,close:105}));
 for(const i of [5,9])Object.assign(b[i],{open:101,low:100.2,high:102,close:101});
 for(const i of [7,12])Object.assign(b[i],{open:109,low:108,high:109.8,close:109});
 return b;
}
function run(b=bars(),lower=100,upper=110,atr=2,spread=.1){
 const r={};x.ObserverClassify(b,lower,upper,atr,spread,r);return r;
}
let checks=0;function test(name,fn){fn();checks++;console.log('PASS '+name);}
test('中部不产生方向；两侧分别统计历史反应',()=>{const r=run();assert.equal(r.state,'WAIT');assert.equal(r.sign,0);assert.equal(r.lowerHits,2);assert.equal(r.upperHits,2);});
test('只有下沿有效反弹才出现多头观察',()=>{const b=bars();Object.assign(b[0],{open:100.3,low:100,high:101,close:100.8});assert.equal(run(b).state,'BUY_WATCH');});
test('上沿有效回落对称地产生空头观察',()=>{const b=bars();Object.assign(b[0],{open:109.7,low:109,high:110,close:109.2});assert.equal(run(b).sign,-1);});
test('相邻点位没有历史反应，不强造区间',()=>{const b=bars();b[5].low=b[9].low=104;assert.equal(run(b).state,'UNPROVEN');});
test('连续K反复贴边不计作多次独立反应',()=>{const b=bars();b[9].low=104;b[6]={...b[5],time:b[6].time};assert.equal(run(b).state,'UNPROVEN');});
test('两根收盘确认破位，旧反应不能覆盖',()=>{const b=bars();b[0].close=99;b[1].close=99;assert.equal(run(b).state,'BROKEN');assert.equal(run(b).sign,0);});
test('单根跌破不冒充两根确认，不产生候选',()=>{const b=bars();Object.assign(b[0],{open:100,close:99,low:98,high:101});const r=run(b);assert.notEqual(r.state,'BROKEN');assert.equal(r.sign,0);});
test('同根扫两端与超大波幅均放弃',()=>{const b=bars();b[0].low=100;b[0].high=110;assert.equal(run(b).state,'CROSS');b[0].high=108;assert.equal(run(b).state,'IMPULSE');});
test('点差异常以及窄区间不发布信号',()=>{assert.equal(run(bars(),100,110,2,.6).state,'SPREAD');const b=bars();b[0].close=102;b[1].close=102;assert.equal(run(b,100,103,2,.1).state,'SPACE');});
test('空数组/无区间不访问不存在的K线',()=>{assert.equal(run([]).state,'NO_RANGE');assert.equal(run(bars(),0,0).sign,0);});
test('未收回或收回太远不追价',()=>{const b=bars();Object.assign(b[0],{open:100.1,low:100,high:101,close:100.2});assert.equal(run(b).sign,0);b[0].close=103;b[0].high=103;assert.equal(run(b).sign,0);});
test('三根单向推进到边界不因一根小反弹立即逆向',()=>{const b=bars();b[3].close=106;b[2].close=104;b[1].close=102;Object.assign(b[0],{open:100.3,low:100,high:101,close:100.8});assert.equal(run(b).state,'IMPULSE');});
test('同次触及去重；新收盘远离后可形成新的观察',()=>{
 const b=bars(),r={sign:1,lower:100,upper:110,atr:2};x.entryObservations=[{bar:9940,lower:100,upper:110,sign:1}];
 x.ObserverDeduplicate(b,r);assert.equal(r.state,'SEEN');
 const next={sign:1,lower:100,upper:110,atr:2};x.entryObservations[0].bar=9880;
 x.ObserverDeduplicate(b,next);assert.equal(next.sign,1);x.entryObservations=[];
});
test('恢复格式拒绝截断、未来收盘与其他品种',()=>{
 const f=['O1','1000','2000','1060','100','110','1','BUY_WATCH','reason','a','b','2','101','101.1','100','102','99.5','101','2','2','policy','100','100','5000','5000','ohlc','XAUUSD.c','END'];
 assert(x.ObserverParse(f.join('\t'),{}));assert(!x.ObserverParse(f.slice(0,-1).join('\t'),{}));
 f[3]='1059';assert(!x.ObserverParse(f.join('\t'),{}));f[3]='1060';f[26]='OTHER';assert(!x.ObserverParse(f.join('\t'),{}));
});
test('观察旁路没有交易API，不写策略或请求状态',()=>{
 assert(!/\b(?:CTrade|PositionOpen|RequestExit|Modify|MergeOpportunity|Store|SavePending|OrderSend)\s*\(/.test(src));
 assert(!/\bpending\s*[.=]/.test(src));
 const tick=main.slice(main.indexOf('void OnTick()'),main.indexOf('void OnTradeTransaction'));
 assert(!tick.includes('Observer'));assert(src.includes('CopyRates(_Symbol,PERIOD_M1,1,观察回看分钟,bars)'));
 assert(src.includes('aiPlans[i].confirmed+offset>bar'));assert(src.includes('aiPlans[i].expires<=r.utc'));
 assert(body('RefreshObserver').includes('observerPending=r; observerHasPending=true;'));
 assert(body('RefreshObserver').indexOf('if(observerHasPending')<body('RefreshObserver').indexOf('CopyRates'));
});

test('写入失败不发布，重试发布冻结的快照',()=>{
 install('ObserverFlush','');
 let writes=0,remembered=[],marks=[];
 Object.assign(x,{observerHasPending:true,observerPending:{bar:1000,cl:100.8},observerRetry:0,
   observerOffset:0,observerLastBar:0,observerHealth:'',TimeGMT:()=>2000,
   ObserverAppend:()=>++writes>1,ObserverRemember:r=>{remembered.push({...r});x.entryObservations.push({...r});},
   ObserverMark:r=>marks.push({...r})});
 x.entryObservations=[];assert(!x.ObserverFlush());assert.equal(marks.length,0);assert.equal(x.observerLastBar,0);
 assert.equal(x.observerPending.cl,100.8);assert(x.ObserverFlush());assert.equal(marks.length,1);
 assert.equal(remembered[0].cl,100.8);assert.equal(x.observerLastBar,1000);assert(!x.observerHasPending);
});
test('实际研判页面空态/历史态布局和操作不重叠',()=>{
 install('ObserverLabel','r');install('ObserverEvidenceLabel','evidence');install('ObserverPage','');
 let bounds=[],buttons=[],texts=[];
 Object.assign(x,{tradeMode:false,uiPaperSummary:false,observerOffset:0,observerHealth:'ready',reviewNotice:'',
   UI_TEXT:0,UI_WARN:1,UI_ACCENT:2,UI_ROW:3,UI_MUTED:4,UI_DIM:5,UI_SELL:6,
   _Digits:2,IntegerToString:String,DoubleToString:(v,n)=>v.toFixed(n),
   TIME_DATE:1,TIME_MINUTES:2,TimeToString:()=> '2026.10.16 12:00',
   UIText:(t,a,b,w,size)=>{texts.push(t);bounds.push([a,b,w,size+4]);},
   UICard:(a,b,w,h)=>bounds.push([a,b,w,h]),
   UIButton:(t,a,b,w,id)=>{buttons.push([a,b,w,27,id]);bounds.push([a,b,w,27]);},panelCanvas:{Update:()=>{}}});
 for(const count of [0,1,120]){
   bounds=[];buttons=[];texts=[];
   x.entryObservations=Array.from({length:count},()=>({bar:1000,sign:1,state:'BUY_WATCH',
     lower:100,upper:110,lowerHits:2,upperHits:2,atr:2,bid:100.7,ask:100.8,
     op:100.3,hi:101,lo:100,cl:100.8,why:'测试',lowerEvidence:'ROLE/1/id/source',upperEvidence:'ROLE/-1/id/source'}));
   x.ObserverPage();assert(bounds.every(([a,b,w,h])=>a>=0&&a+w<=560&&b>=0&&b+h<=654));
   for(let i=0;i<buttons.length;i++)for(let j=i+1;j<buttons.length;j++){
     const a=buttons[i],b=buttons[j];assert(a[0]+a[2]<=b[0]||b[0]+b[2]<=a[0]||a[1]+a[3]<=b[1]||b[1]+b[3]<=a[1]);
   }
   if(count)assert(texts.some(t=>t.includes('非订单')));
 }
});
console.log(checks+' observer checks passed; synthetic, no trading and no profitability claim');
