const fs=require('node:fs'),path=require('node:path');
let base=fs.readFileSync(path.join(__dirname,'tge-chart-tools-regression.cjs'),'utf8').split("check('removed timeframe")[0];
base=base.replace('uiIndicatorHandles:Array(16)','uiIndicatorHandles:Array(20)')
.replace("'ADX','随机KD']","'ADX','随机KD','近期K线框','震荡箱体','波动收缩','框宽/ATR']")
.replace("['UIViewMask','']","['UIIndicatorBit','index'],['UIViewMask','']")
.replace('ENUM_TIMEFRAMES|ENUM_MA_METHOD','datetime|ENUM_LINE_STYLE|ENUM_TIMEFRAMES|ENUM_MA_METHOD')
.replace('MODE_SMA:0,','STYLE_SOLID:0,STYLE_DASH:1,STYLE_DOT:2,看盘框体周期:5,看盘近期框根数:5,看盘震荡最少根数:12,看盘震荡ATR倍数:1.5,看盘收缩比较根数:100,看盘收缩低位百分比:20,EnumToString:()=> "PERIOD_M5",StringReplace:()=>0,MODE_SMA:0,');
const cases=`
// IndicatorRelease deliberately does not run OnDeinit: chart objects have an independent lifetime.
const structureObjects=new Set(),redrawObjects=[];
cx.ObjectsDeleteAll=(_,prefix)=>{
 let count=0;for(const name of structureObjects)if(name.startsWith(prefix)){structureObjects.delete(name);count++;}
 return count;
};
cx.ChartRedraw=()=>redrawObjects.push([...structureObjects]);
check('four buttons attach distinct display resources; teacher bit is unchanged',()=>{
 cx.uiPointLines=true;
 for(let i=0;i<4;i++){
   cx.ViewAction(100+i);assert(cx.UIIndicatorWindow(16+i)>=0);
   const h=indicatorHandles.get(cx.uiIndicatorHandles[16+i]);
   assert(h.path.includes('TgeChartStructure.ex5'));assert.equal(h.kind,i);
   assert.deepEqual(Array.from(h.parameters),[5,5,12,1.5,14,20,2,100,20]);
 }
 const mask=(1<<16)|(1<<17)|(1<<18)|(1<<19)|(1<<20);
 assert.equal(cx.UIViewMask(),mask);
 cx.UIFavorite(0,true);cx.ViewAction(93);assert.equal(cx.UIViewMask(),1<<16);
 cx.UIFavorite(0,false);assert.equal(cx.UIViewMask(),mask);
});
check('undo restores structure selection and old favorites retain legacy meaning',()=>{
 cx.ViewAction(100);assert(cx.UIIndicatorWindow(16)<0);cx.ViewAction(92);assert(cx.UIIndicatorWindow(16)>=0);
 const old=(1<<0)|(1<<6)|(1<<16);
 assert(cx.UIApplyMask(old));assert.equal(cx.UIViewMask(),old);
 assert.equal(cx.UIIndicatorWindow(16),-1);assert.equal(cx.uiPointLines,true);
});
check('structure tab and indicator choices restore without trading calls',()=>{
 cx.ViewAction(98);cx.ViewAction(101);cx.SaveView();
 cx.CloseViewIndicators();cx.uiWatchTab=0;cx.InitView();
 assert.equal(cx.uiWatchTab,2);assert(cx.UIIndicatorWindow(17)>=0);
 for(const name of ['UIIndicatorSet','ViewAction','UISetMask'])
 assert(!/\\b(?:execution|Open|Manage|OrderSend)\\b/.test(body(name)));
});
check('load failure retains existing views; removing structure releases handles',()=>{
 const before=cx.UIViewMask();failCreate=true;
 assert.equal(cx.UIIndicatorSet(18,true),false);assert.equal(cx.UIViewMask(),before);failCreate=false;
 const h=cx.uiIndicatorHandles[17];cx.UIIndicatorSet(17,false);
 assert(released.includes(h));assert.equal(cx.UIIndicatorWindow(17),-1);
});
check('one click removes every owned structure object before redraw, preserving other drawings',()=>{
 cx.CloseViewIndicators();structureObjects.clear();
 const foreign=['user.box','TGUI.99.V16 近期K线框.S.box',cx.UIIndicatorName(16)+'.S-other'];
 foreign.forEach(name=>structureObjects.add(name));
 const suffixes=['box','mid','high','low','confirmed','readout','note0','note1','note2'];
 for(let i=16;i<20;i++){
  cx.ViewAction(i+84);assert(cx.UIIndicatorWindow(i)>=0);
  suffixes.forEach(suffix=>structureObjects.add(cx.UIIndicatorName(i)+'.S.'+suffix));
 }
 for(let i=16;i<20;i++){
  const prefix=cx.UIIndicatorName(i)+'.S.',handle=cx.uiIndicatorHandles[i];
  redrawObjects.length=0;cx.ViewAction(i+84);
  assert.equal(cx.UIIndicatorWindow(i),-1);assert.equal(cx.uiIndicatorHandles[i],-1);assert(released.includes(handle));
  assert(![...structureObjects].some(name=>name.startsWith(prefix)),'first OFF must remove drawings');
  assert(redrawObjects.length>0);assert(redrawObjects.every(frame=>!frame.some(name=>name.startsWith(prefix))),'no stale OFF frame');
  for(let j=i+1;j<20;j++)assert(structureObjects.has(cx.UIIndicatorName(j)+'.S.box'));
  foreign.forEach(name=>assert(structureObjects.has(name)));
 }
});
check('failed detach preserves drawings; disabling an already detached helper cleans orphans',()=>{
 cx.UIIndicatorSet(17,true);
 const name=cx.UIIndicatorName(17)+'.S.box',handle=cx.uiIndicatorHandles[17];structureObjects.add(name);
 failDelete=true;assert.equal(cx.UIIndicatorSet(17,false),false);failDelete=false;
 assert(cx.UIIndicatorWindow(17)>=0);assert.equal(cx.uiIndicatorHandles[17],handle);
 assert(structureObjects.has(name));assert(!released.includes(handle));
 assert(cx.UIIndicatorSet(17,false));assert(!structureObjects.has(name));
 structureObjects.add(name);assert(cx.UIIndicatorSet(17,false));assert(!structureObjects.has(name));
});
check('clear indicators uses the same synchronous structure cleanup',()=>{
 for(let i=16;i<20;i++){cx.UIIndicatorSet(i,true);structureObjects.add(cx.UIIndicatorName(i)+'.S.note0');}
 cx.ViewAction(93);
 for(let i=16;i<20;i++){
  assert.equal(cx.UIIndicatorWindow(i),-1);
  assert(!structureObjects.has(cx.UIIndicatorName(i)+'.S.note0'));
 }
});

check('moving average styles include named width and pattern parameters',()=>{
 for(const i of [0,6,1,7,8,9,10,11]){
  assert(cx.UIIndicatorSet(i,true));const p=indicatorHandles.get(cx.uiIndicatorHandles[i]).parameters;
  assert.equal(p.length,7);assert(p[6]>=1&&p[6]<=3);
 }
 assert.equal(indicatorHandles.get(cx.uiIndicatorHandles[10]).parameters[5],1);
 assert.equal(indicatorHandles.get(cx.uiIndicatorHandles[11]).parameters[5],2);
});

check('structure page buttons fit without overlap',()=>{
 Object.assign(cx,{UI_CARD:4,UI_TEXT:6,UI_BORDER:7,UI_ROOT:8,panelCanvas:{Update:()=>{}},uiWatchTab:2});
 vm.runInContext('function IndicatorPage(){'+convert(body('IndicatorPage'))+'}',cx);
 cx.uiHits=[];cx.IndicatorPage();
 for(const action of [98,100,101,102,103])assert(cx.uiHits.some(h=>h.action===action));
 for(const a of cx.uiHits)assert(a.x>=0&&a.y>=0&&a.x+a.w<=548&&a.y+a.h<=502);
 for(let i=0;i<cx.uiHits.length;i++)for(let j=i+1;j<cx.uiHits.length;j++){
  const a=cx.uiHits[i],b=cx.uiHits[j];
  assert(a.x+a.w<=b.x||b.x+b.w<=a.x||a.y+a.h<=b.y||b.y+b.h<=a.y);
 }
});
const structure=fs.readFileSync('Include/View/TgeChartStructure.mq5','utf8');
function sb(name){
 const start=structure.indexOf('{',structure.search(new RegExp('^(?:int|bool|double|void) '+name+'\\\\(','m')));
 let end=start+1,depth=1;for(;depth;end++){if(structure[end]==='{')depth++;if(structure[end]==='}')depth--;}
 return structure.slice(start+1,end-1);
}
function cv(s){return convert(s).replace(/MqlRates (\\w+)\\[\\];/g,'let $1=[];').replace(/\\bdatetime\\s+/g,'let ');}
let boxes=[],notes=[],deleted=[],copies=0;
const sc=vm.createContext({
 Math,MathAbs:Math.abs,MathPow:Math.pow,MathSqrt:Math.sqrt,MathFloor:Math.floor,MathIsValidNumber:Number.isFinite,
 RangeBars:12,RangeATR:1.5,ATRBars:14,BandBars:20,BandDeviation:2,CompareBars:100,LowPercent:20,BoxBars:5,
 rangeStart:0,rangeConfirmed:0,rangeEnd:0,rangeProcessed:0,rangeBreak:0,rangeHigh:0,rangeLow:0,rangeActive:false,rangeState:'',
 INVALID_HANDLE:-1,EMPTY_VALUE:Number.MAX_VALUE,ORANGE:1,BLUE:2,PURPLE:3,INK:4,STYLE_SOLID:0,STYLE_DASH:1,STYLE_DASHDOT:3,
 TIME_DATE:1,TIME_MINUTES:2,OBJ_TREND:1,OBJPROP_RAY_LEFT:1,OBJPROP_RAY_RIGHT:2,objectPrefix:'fixture.',
 TimeToString:String,IntegerToString:String,DoubleToString:(x,n)=>x.toFixed(n),EnumToString:()=> 'PERIOD_M5',StringReplace:()=>0,
 DrawBox:(...v)=>boxes.push(v),Readout:(...v)=>notes.push(v),ObjectsDeleteAll:(...v)=>deleted.push(v),
 ObjectDelete:(...v)=>deleted.push(v),ObjectFind:()=>-1,ObjectCreate:()=>true,ObjectMove:()=>true,StyleObject:()=>{},ObjectSetInteger:()=>{},
 ArrayResize:(a,n)=>a.length=n,ArraySort:a=>a.sort((x,y)=>x-y),ArrayInitialize:(a,v)=>a.fill(v),ArraySetAsSeries:()=>{},
 _Symbol:'TEST',SourcePeriod:5,atrHandle:1,drawnBar:0,ViewKind:0,ChartRedraw:()=>{},PeriodSeconds:()=>300,
});
for(const [name,args] of [['RangeBox','bars,atr,n,seconds'],['BandWidth','bars,at'],['Contracted','widths,at'],['OnCalculate','rates_total,prev_calculated,time,open,high,low,close,tick_volume,volume,spread']])
 vm.runInContext('function '+name+'('+args+'){'+cv(sb(name))+'}',sc);
const bars=(n,value=100)=>Array.from({length:n},(_,i)=>({time:300*(i+1),open:value,close:value,high:value+1,low:value-1}));
check('range confirmation uses available evidence and continuation keeps frozen borders',()=>{
 const b=bars(30),a=Array(30).fill(1);sc.RangeBox(b,a,b.length,300);
 assert.equal(sc.rangeConfirmed,4800);assert.equal(sc.rangeHigh,101.5);assert.equal(sc.rangeLow,98.5);
 const start=sc.rangeStart,confirm=sc.rangeConfirmed;
 const more=bars(31);more[30].close=101;sc.RangeBox(more.slice(1),Array(30).fill(4),30,300);
 assert.equal(sc.rangeHigh,101.5);assert.equal(sc.rangeStart,start);assert.equal(sc.rangeConfirmed,confirm);
});
check('closed breakout fixes the old end; new range waits for a fresh complete window',()=>{
 const b=bars(32);b[31].close=104;sc.RangeBox(b,Array(32).fill(1),32,300);
 assert.equal(sc.rangeState,'收盘上破');assert.equal(sc.rangeActive,false);assert.equal(sc.rangeHigh,101.5);
 const after=bars(43);after[31].close=104;sc.RangeBox(after,Array(43).fill(1),43,300);
 assert.equal(sc.rangeActive,false);assert.equal(sc.rangeEnd,9900);
 const ready=bars(44);ready[31].close=104;sc.RangeBox(ready,Array(44).fill(1),44,300);
 assert.equal(sc.rangeActive,true);assert.equal(sc.rangeStart,9900);assert.equal(sc.rangeConfirmed,13500);
});
check('BBW width and percentile use preceding observations',()=>{
 const b=bars(25);assert.equal(sc.BandWidth(b,24),0);
 for(let i=5;i<25;i++)b[i].close=i%2?101:99;
 assert(Math.abs(sc.BandWidth(b,24)-4)<1e-10);
 const widths=Array(101).fill(2);widths[100]=1;assert(sc.Contracted(widths,100));
 widths[100]=3;assert(!sc.Contracted(widths,100));
});
check('calculate excludes open candle and skips same-source-bar recomputation',()=>{
 let history=bars(301);history[299].high=110;history[300].high=99999;
 Object.assign(sc,{
  Bars:()=>history.length,BarsCalculated:()=>history.length,
  iTime:()=>history.at(-1).time,
  CopyRates:(symbol,tf,shift,n,out)=>{assert.equal(shift,1);copies++;out.push(...history.slice(-n-1,-1));return n;},
  CopyBuffer:(handle,buffer,shift,n,out)=>{assert.equal(shift,1);out.push(...Array(n).fill(2));return n;}
 });
 sc.OnCalculate(400,0,[],[],[],[],[],[],[],[]);assert.equal(boxes.at(-1)[2],110);
 assert.equal(copies,1);sc.OnCalculate(400,400,[],[],[],[],[],[],[],[]);assert.equal(copies,1);
 history.push({time:90600,high:120,low:99,close:100});
 sc.OnCalculate(401,400,[],[],[],[],[],[],[],[]);assert.equal(copies,2);assert.equal(boxes.at(-1)[2],99999);
});
check('cleanup is restricted to owned objects even after invalid initialization',()=>{
 sc.IndicatorRelease=()=>{};sc.objectPrefix='';deleted=[];
 vm.runInContext('function OnDeinit(reason){'+cv(sb('OnDeinit'))+'}',sc);
 sc.OnDeinit(0);assert.equal(deleted.length,0);
 sc.objectPrefix='fixture.';sc.OnDeinit(0);assert.deepEqual(deleted,[[0,'fixture.']]);
});
check('mode switch persists without clearing pending and refuses unsupported accounts',()=>{
 let saved=[],flushes=0;
 Object.assign(cx,{tradeMode:true,markerDirty:false,reason:'',ACCOUNT_MARGIN_MODE:1,ACCOUNT_MARGIN_MODE_RETAIL_HEDGING:2,
 AccountInfoInteger:()=>2,Store:(k,v)=>{saved.push([k,v]);return true;},GlobalVariablesFlush:()=>flushes++,DecisionLog:()=>{}});
 vm.runInContext('function ToggleTradeMode(){'+body('ToggleTradeMode').replace('bool enabled=','let enabled=')+'}',cx);
 cx.ViewAction(29);assert.equal(cx.tradeMode,false);assert.deepEqual(saved.pop(),['tradeMode',0]);
 cx.ViewAction(29);assert.equal(cx.tradeMode,true);assert.deepEqual(saved.pop(),['tradeMode',1]);
 cx.tradeMode=false;cx.AccountInfoInteger=()=>0;cx.ToggleTradeMode();assert.equal(cx.tradeMode,false);assert.equal(saved.length,0);
 cx.AccountInfoInteger=()=>2;cx.Store=()=>false;cx.ToggleTradeMode();assert.equal(cx.tradeMode,false);
 assert.equal(flushes,2);assert(!/ClearPending|ZeroMemory|OrderSend|execution/.test(body('ToggleTradeMode')));
 assert(body('CanExecute').includes('return tradeMode && stateOK'));
 assert(body('ExecutionBlock').includes('if(!tradeMode)'));
 assert(!body('OnInit').includes('prefix+="obs"'));
 assert(body('OnInit').includes('tradeMode=启用真实交易 &&'));
});
console.log(checks+' structure/view production-source checks passed.');

if(process.env.TGE_UI_PREVIEW){
 const out=process.env.TGE_UI_PREVIEW;fs.mkdirSync(out,{recursive:true});
 for(const m of src.matchAll(/(UI_[A-Z]+)=C'(\\d+),(\\d+),(\\d+)'/g))cx[m[1]]=[+m[2],+m[3],+m[4]];
 let ops=[];
 Object.assign(cx,{
 UIRound:(x,y,w,h,color,r=8)=>ops.push({op:'rect',x,y,w,h,color,r}),
 UICard:(x,y,w,h,color)=>ops.push({op:'rect',x,y,w,h,color,r:8,border:cx.UI_BORDER}),
 UIText:(text,x,y,w,size,color,right=false)=>ops.push({op:'text',text:String(text),x,y,w,size,color,right}),
 uiWatchTab:2,uiIndicatorNotice:'结构辅助 · M5 已收盘 · 白底高对比配色'
 });
 cx.uiHits=[];cx.IndicatorPage();
 fs.writeFileSync(out+'/structure-page.json',JSON.stringify({width:560,height:592,ops}));
}
`;
new Function("require","process",base+cases)(require,process);
