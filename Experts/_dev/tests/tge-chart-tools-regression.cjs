const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync(process.argv[2],'utf8');
function body(name) {
 const def=src.search(new RegExp('^(?:int|uint|bool|void|string) '+name+'\\(','m'));
 assert(def>=0,name);const start=src.indexOf('{',def);let end=start+1,depth=1;
 for(;depth;end++){if(src[end]==='{')depth++;if(src[end]==='}')depth--;}
 return src.slice(start+1,end-1);
}
function convert(s) {
 return s.replace(/C'(\d+),(\d+),(\d+)'/g,'[$1,$2,$3]').replace(/\((?:int|double|long|ulong)\)/g,'')
 .replace(/\b(?:string|int) (\w+)\[\d+\]=\{([\s\S]*?)\};/g,'let $1=[$2];')
 .replace(/\b(?:int|string) (\w+)\[\d+\];/g,'let $1=[];')
 .replace(/\b(?:double|MqlRates) (\w+)\[\];/g,'let $1=[];')
 .replace(/\b(?:int|uint|bool|color|ulong|double|string|long|ENUM_TIMEFRAMES|ENUM_MA_METHOD)\s+/g,'let ')
 .replace(/\bMathMax\b/g,'Math.max').replace(/\bMathMin\b/g,'Math.min').replace(/\bMathRound\b/g,'Math.round');
}
const props=new Map([['scale',3],['follow',true],['grid',false],['shift',true],['mode',1],['scroll',true],['move',false],['width',1000],['height',1000]]);
const indicatorWindows=[[]],indicatorHandles=new Map(),released=[];
let nextHandle=100,failCreate=false,failAdd=false,failDelete=false;
const objects=new Map(),globals=new Map(),periods=[],navigation=[];let paint=0,drawLevels=0,checks=0;
const cx=vm.createContext({Math,
 看盘均线1周期:5,看盘均线2周期:10,看盘均线3周期:20,看盘均线4周期:50,看盘均线5周期:100,看盘均线6周期:200,
 看盘主均线算法:0,看盘辅助均线算法:1,看盘指标计算价格:1,看盘布林周期:20,看盘布林标准差:2,
 看盘ADX周期:14,看盘ADX参考线:25,看盘KD周期:9,看盘KD平滑:3,看盘KD信号:3,看盘RSI周期:14,看盘MACD快线:12,看盘MACD慢线:26,看盘MACD信号线:9,看盘ATR周期:14,
 MODE_SMA:0,MODE_EMA:1,MODE_SMMA:2,MODE_LWMA:3,
 clrWhite:'white',clrOrangeRed:'red',clrGold:'gold',clrOrange:'orange',clrMediumTurquoise:'teal',clrDeepSkyBlue:'blue',clrMediumPurple:'purple',clrHotPink:'pink',uiX:8,uiY:24,panelWidth:560,panelHeight:565,panelScale:1,uiPrefix:'TGUI.42.',
 uiIndicatorLabels:['MA5','EMA20','布林','RSI','MACD','ATR','MA10','MA50','MA100','MA200','M5·MA5','M15·MA5','确认拐点','昨高低','ADX','随机KD'],uiIndicatorHandles:Array(16).fill(-1),uiIndicatorNotice:'',INVALID_HANDLE:-1,
 uiCollapsed:false,uiPointLines:true,uiStatistics:false,uiIndicators:false,statsPeriod:0,statsOffsets:[0,0,0],statsFilter:0,statsDetail:0,statsReview:0,statsDirty:true,statsLastAttempt:0,statsTrades:[],uiHits:[],uiPeriods:[1,5,15,30,16385,16388,16408],
 uiInitialized:false,uiOldMouseMove:false,uiDragging:false,uiOldScroll:false,uiLeftWasDown:false,uiPressedAction:0,uiDragDX:0,uiDragDY:0,panelReady:true,
 读取AI即时策略:false,每次开仓手数:.02,aiReady:false,AIPlanCaption:()=>'AI等待',VIEW:'TGE_',_Symbol:'XAUUSD.c',UI_HEADER:0,UI_ACCENT:1,UI_MUTED:2,UI_DIM:3,
 uiMobileMarkers:true,启用手机标记挂单:true,markerStatus:'等待同步',markerPrefix:'TGM.test.',markerDirty:false,GlobalVariablesFlush:()=>{},
 CHART_SCALE:'scale',CHART_AUTOSCROLL:'follow',CHART_SHOW_GRID:'grid',CHART_SHIFT:'shift',CHART_MODE:'mode',
 CHART_MOUSE_SCROLL:'scroll',CHART_EVENT_MOUSE_MOVE:'move',CHART_WIDTH_IN_PIXELS:'width',CHART_HEIGHT_IN_PIXELS:'height',
 CHART_WINDOWS_TOTAL:'windows',
 ChartIndicatorsTotal:(_,w)=>indicatorWindows[w]?.length||0,ChartIndicatorName:(_,w,i)=>indicatorWindows[w]?.[i]?.name||'',
 iCustom:(symbol,period,path,kind,name,...parameters)=>{if(failCreate)return -1;const h=nextHandle++;indicatorHandles.set(h,{name,symbol,period,path,kind,parameters});return h;},
 IndicatorRelease:h=>{released.push(h);return true;},
 ChartIndicatorAdd:(_,w,h)=>{if(failAdd)return false;while(indicatorWindows.length<=w)indicatorWindows.push([]);indicatorWindows[w].push({handle:h,...indicatorHandles.get(h)});return true;},
 ChartIndicatorDelete:(_,w,name)=>{if(failDelete)return false;const i=indicatorWindows[w]?.findIndex(v=>v.name===name)??-1;if(i<0)return false;indicatorWindows[w].splice(i,1);if(w>0&&!indicatorWindows[w].length)indicatorWindows.splice(w,1);return true;},
 CHART_CANDLES:1,CHART_BARS:0,CHART_LINE:2,CHART_END:3,OBJPROP_XDISTANCE:'x',OBJPROP_YDISTANCE:'y',
 CHARTEVENT_CLICK:1,CHARTEVENT_OBJECT_CLICK:2,CHARTEVENT_MOUSE_MOVE:3,CHARTEVENT_CHART_CHANGE:4,
 ChartGetInteger:(_,p)=>p==='windows'?indicatorWindows.length:props.get(p),ChartSetInteger:(_,p,v)=>{props.set(p,v);return true;},ChartPeriod:()=>5,
 ChartID:()=>42,ChartSetSymbolPeriod:(_,symbol,period)=>{periods.push([symbol,period]);return true;},
 ChartNavigate:(_,mode,pos)=>{navigation.push([mode,pos]);return true;},ChartRedraw:()=>{},
 ObjectGetInteger:(_,name,p)=>objects.get(p)||0,ObjectSetInteger:(_,name,p,v)=>{objects.set(p,v);return true;},
 GlobalVariableSet:(k,v)=>{globals.set(k,v);return 1;},GlobalVariableCheck:k=>globals.has(k),GlobalVariableGet:k=>globals.get(k)||0,
 IntegerToString:String,StringToInteger:Number,GetLastError:()=>0,Print:()=>{},
 UICard:()=>{},UIText:()=>{},Panel:()=>paint++,DrawLevels:()=>drawLevels++,
 ArraySize:a=>a.length,ArrayResize:(a,n)=>{while(a.length<n)a.push({});a.length=n;}
});
for(const [name,args] of [['UIIndicatorPeriod','index'],['UIIsMovingAverage','index'],['UIIsOscillator','index'],['UIIndicatorLabel','index'],['UIMovingAverageGroup','trendGroup'],['UIIndicatorName','index'],['UIIndicatorWindow','index'],['UIIndicatorSet','index,enabled'],['CloseViewIndicators',''],['UIPx','value'],['SaveView',''],['InitView',''],['MovePanel',''],
 ['UIButton','text,x,y,w,action,active=false'],['ChartTools','y'],['HitAction','mouseX,mouseY'],
 ['ViewAction','action'],['OnChartEvent','id,lparam,dparam,sparam']])
 vm.runInContext('function '+name+'('+args+'){'+convert(body(name))+'}',cx);
function check(name,fn){fn();checks++;console.log('PASS '+name);}
check('removed timeframe and generic chart actions do not change chart state',()=>{
 const old=[...props];for(let i=10;i<=26;i++)cx.ViewAction(i);
 assert.deepEqual([...props],old);assert.equal(periods.length,0);assert.equal(navigation.length,0);
 assert(!/ChartSetSymbolPeriod|CHART_SCALE|CHART_AUTOSCROLL|CHART_SHOW_GRID|CHART_SHIFT|CHART_MODE/.test(body('ChartTools')+body('ViewAction')));
});
check('three toolbar rows contain six averages and relevant context indicators without timeframe tools',()=>{
 cx.uiHits=[];cx.ChartTools(88);
 assert.deepEqual(Array.from(cx.uiHits,h=>h.action),[50,56,51,57,58,59,52,53,54,55,60,61,70,71,72,73,74,75]);
});
check('point line visibility redraws objects and persists independently',()=>{
 cx.ViewAction(27);assert.equal(cx.uiPointLines,false);assert.equal(drawLevels,1);assert.equal(globals.get('TGUI.42.lines'),0);
 cx.ViewAction(27);assert.equal(cx.uiPointLines,true);
});
check('collapse preference restores across native period reinitialization',()=>{
 cx.ViewAction(1);cx.uiX=120;cx.uiY=70;cx.SaveView();
 cx.uiCollapsed=false;cx.uiX=8;cx.uiY=24;cx.uiPointLines=false;cx.InitView();
 assert.equal(cx.uiCollapsed,true);assert.equal(cx.uiX,120);assert.equal(cx.uiY,70);assert.equal(cx.uiPointLines,true);
 assert.equal(props.get('move'),true);
});
check('hit mapping follows panel position and DPI in both layouts',()=>{
 for(const scale of [.45,.85,1,1.5]) for(const y of [49,88]){
  cx.panelScale=scale;cx.uiHits=[];cx.UIButton('+',396,7,30,1);cx.ChartTools(y);
  assert.equal(cx.uiHits.length,19);
  for(const h of cx.uiHits){
   assert.equal(cx.HitAction(cx.uiX+(h.x+h.w/2)*scale,cx.uiY+(h.y+h.h/2)*scale),h.action);
   assert(h.x+h.w<=548);assert(h.y+h.h<=y+95);
  }
  assert.equal(cx.HitAction(cx.uiX-1,cx.uiY-1),0);
 }
});

function resetHits(){
 cx.panelScale=1;cx.uiX=8;cx.uiY=24;cx.uiDragging=false;cx.uiLeftWasDown=false;cx.uiPressedAction=0;
 cx.uiHits=[];cx.UIButton('-',396,7,30,1);cx.UIButton('点位线',462,49,82,27);cx.ChartTools(88);
}
function point(action){const h=cx.uiHits.find(h=>h.action===action);return [cx.uiX+h.x+10,cx.uiY+h.y+10];}
function gesture(action,notifications=true){
 const [x,y]=point(action);cx.OnChartEvent(3,x,y,'1');cx.OnChartEvent(3,x,y,'0');
 if(notifications){cx.OnChartEvent(2,x,y,'TGE_CANVAS');cx.OnChartEvent(1,x,y,'');}
}
check('one mouse gesture plus object/chart notifications toggles point lines exactly once',()=>{
 resetHits();cx.uiPointLines=false;gesture(27);assert.equal(cx.uiPointLines,true);
});
check('notification order before/after release cannot reverse a toggle',()=>{
 for(const before of [1,2]){
  resetHits();cx.uiPointLines=true;const [x,y]=point(27);
  cx.OnChartEvent(3,x,y,'1');cx.OnChartEvent(before,x,y,before===2?'TGE_CANVAS':'');
  cx.OnChartEvent(3,x,y,'0');cx.OnChartEvent(before===1?2:1,x,y,before===1?'TGE_CANVAS':'');
  assert.equal(cx.uiPointLines,false);
 }
});
check('rapid separate clicks remain separate without debounce delay',()=>{
 resetHits();cx.uiPointLines=false;gesture(27);gesture(27);assert.equal(cx.uiPointLines,false);
});
check('holding mouse and repeated movements do not repeatedly execute button',()=>{
 resetHits();cx.uiPointLines=true;const [x,y]=point(27);
 cx.OnChartEvent(3,x,y,'1');for(let i=0;i<20;i++)cx.OnChartEvent(3,x+1,y+1,'1');
 assert.equal(cx.uiPointLines,true);cx.OnChartEvent(3,x,y,'0');assert.equal(cx.uiPointLines,false);
 cx.OnChartEvent(1,x,y,'');cx.OnChartEvent(2,x,y,'TGE_CANVAS');assert.equal(cx.uiPointLines,false);
});
check('release outside pressed button cancels operation',()=>{
 resetHits();cx.uiPointLines=true;const [x,y]=point(27);
 cx.OnChartEvent(3,x,y,'1');cx.OnChartEvent(3,cx.uiX+3,cx.uiY+200,'0');
 assert.equal(cx.uiPointLines,true);assert.equal(cx.uiPressedAction,0);
});
check('duplicate notifications cannot re-expand a collapsed panel',()=>{
 resetHits();cx.uiCollapsed=false;gesture(1);assert.equal(cx.uiCollapsed,true);
});
check('drag requires a new header press and restores original chart scrolling',()=>{
 resetHits();props.set('scroll',true);
 cx.OnChartEvent(3,900,900,'1');cx.OnChartEvent(3,100,40,'1');assert.equal(cx.uiDragging,false);
 cx.OnChartEvent(3,100,40,'0');cx.OnChartEvent(3,100,40,'1');assert.equal(cx.uiDragging,true);assert.equal(props.get('scroll'),false);
 cx.OnChartEvent(3,220,120,'1');assert.equal(cx.uiX,128);assert.equal(cx.uiY,104);
 cx.OnChartEvent(3,220,120,'0');assert.equal(cx.uiDragging,false);assert.equal(props.get('scroll'),true);
 assert.equal(globals.get('TGUI.42.x'),128);assert.equal(cx.uiPressedAction,0);
});

check('holding/statistics page buttons are display-only and repeat notifications cannot undo them',()=>{
 resetHits();cx.UIButton('持仓',12,49,68,2);cx.UIButton('统计',88,49,68,3);
 cx.uiStatistics=false;gesture(3);assert.equal(cx.uiStatistics,true);gesture(2);assert.equal(cx.uiStatistics,false);
});
check('monitor, statistics and watch pages are mutually exclusive',()=>{
  cx.uiStatistics=false;cx.uiIndicators=false;cx.ViewAction(4);
  assert.equal(cx.uiIndicators,true);assert.equal(cx.uiStatistics,false);
  cx.ViewAction(3);assert.equal(cx.uiIndicators,false);assert.equal(cx.uiStatistics,true);
  cx.ViewAction(2);assert.equal(cx.uiIndicators,false);assert.equal(cx.uiStatistics,false);
});
check('phone TP button saves preference once and defers requests to timer',()=>{
 resetHits();cx.UIButton('手机TP开',240,49,100,28);cx.uiMobileMarkers=true;cx.markerDirty=false;
 gesture(28);assert.equal(cx.uiMobileMarkers,false);assert.equal(cx.markerDirty,true);
 assert.equal(globals.get('TGM.test.enabled'),0);
 gesture(28);assert.equal(cx.uiMobileMarkers,true);assert.equal(globals.get('TGM.test.enabled'),1);
 assert(!/CancelTgeMobileMarkers|SubmitTgeMobileMarker|SyncTgeMobileMarkers/.test(body('ViewAction')));
});
check('statistics dates, periods, filters and review arrows stay within display state',()=>{
 cx.statsPeriod=0;cx.statsOffsets=[0,0,0];cx.ViewAction(33);assert.equal(cx.statsOffsets[0],-1);
 cx.ViewAction(31);cx.ViewAction(35);assert.equal(cx.statsPeriod,1);assert.equal(cx.statsOffsets[1],1);
 cx.ViewAction(34);assert.equal(cx.statsOffsets[1],0);cx.ViewAction(42);assert.equal(cx.statsFilter,2);assert.equal(cx.statsLastAttempt,0);
 cx.ViewAction(39);assert.equal(cx.statsDetail,3);cx.statsTrades=[{},{}];cx.statsReview=0;
 cx.ViewAction(43);cx.ViewAction(43);assert.equal(cx.statsReview,1);cx.ViewAction(44);assert.equal(cx.statsReview,0);
 cx.SaveView();cx.statsPeriod=0;cx.statsFilter=0;cx.statsDetail=0;cx.InitView();
 assert.equal(cx.statsPeriod,1);assert.equal(cx.statsFilter,2);assert.equal(cx.statsDetail,3);
});
check('panel is clamped into resized chart boundaries',()=>{
 props.set('width',600);props.set('height',600);cx.uiX=999;cx.uiY=-5;cx.MovePanel();assert.equal(cx.uiX,36);assert.equal(cx.uiY,0);
 props.set('width',100);props.set('height',100);cx.MovePanel();assert.equal(cx.uiX,0);assert.equal(cx.uiY,0);
});
check('UI callbacks cannot send requests or alter core trading state directly',()=>{
 for(const name of ['ViewAction','OnChartEvent','SaveView','InitView','MovePanel','HitAction','ChartTools','UIButton'])
  assert(!/\bexecution\s*\.|\b(?:Open|Manage|Reconcile|Store|SavePending|ClearPending|Signal)\s*\(/.test(body(name)),name);
});

function resetIndicators(){
 cx.CloseViewIndicators();indicatorWindows.length=1;indicatorWindows[0]=[{name:'Manual MA5',handle:9000}];
 indicatorHandles.clear();released.length=0;failCreate=false;failAdd=false;failDelete=false;
 cx.uiIndicatorHandles=Array(16).fill(-1);
 for(let i=0;i<16;i++) globals.delete(cx.uiPrefix+'indicator'+i);
}
check('sixteen indicator toggles use chart timeframe and embedded read-only resources',()=>{
 resetIndicators();
 for(let i=0;i<16;i++){
  const action=i<10?50+i:60+i;cx.ViewAction(action);assert(cx.UIIndicatorWindow(i)>=0);
  const def=indicatorHandles.get(cx.uiIndicatorHandles[i]);assert.equal(def.symbol,'XAUUSD.c');assert.equal(def.period,5);
  assert.equal(def.kind,i>=14?i-11:i>=10?i-7:i>=6?1:i%3);assert(def.path.startsWith('::Include\\View\\'));
  cx.ViewAction(action);assert.equal(cx.UIIndicatorWindow(i),-1);
 }
 assert.equal(indicatorWindows.length,1);assert.equal(indicatorWindows[0][0].name,'Manual MA5');
});
check('configured periods methods prices and colors reach native display components',()=>{
 resetIndicators();cx.看盘均线2周期=13;cx.看盘辅助均线算法=2;cx.看盘指标计算价格=5;
 cx.看盘布林周期=25;cx.看盘布林标准差=2.5;cx.看盘RSI周期=8;
 cx.看盘MACD快线=8;cx.看盘MACD慢线=21;cx.看盘MACD信号线=5;cx.看盘ATR周期=10;
 for(const i of [0,6,1,7,8,9,2,3,4,5])cx.UIIndicatorSet(i,true);
 assert.deepEqual(indicatorHandles.get(cx.uiIndicatorHandles[6]).parameters,[13,2,5,2.5,'orange']);
 assert.deepEqual(indicatorHandles.get(cx.uiIndicatorHandles[0]).parameters,[5,0,5,2.5,'gold']);
 assert.deepEqual(indicatorHandles.get(cx.uiIndicatorHandles[2]).parameters,[25,2,5,2.5,'pink']);
 // Replaced oscillator handles are released; recorded creation arguments still prove each native input.
 for(const [kind,p] of [[0,8],[1,10],[2,10]]){
  const d=[...indicatorHandles.values()].find(d=>d.path.includes('Oscillator')&&d.kind===kind);
  assert.deepEqual(d.parameters,[p,8,21,5,5,3,3,25]);
 }
 assert.equal(new Set([0,6,1,7,8,9].map(i=>indicatorHandles.get(cx.uiIndicatorHandles[i]).parameters[4])).size,6);
 cx.看盘均线2周期=10;cx.看盘辅助均线算法=1;cx.看盘指标计算价格=1;
 cx.看盘布林周期=20;cx.看盘布林标准差=2;cx.看盘RSI周期=14;
 cx.看盘MACD快线=12;cx.看盘MACD慢线=26;cx.看盘MACD信号线=9;cx.看盘ATR周期=14;
});
check('average buttons reflect configured period and all four calculation methods',()=>{
 const name=cx.UIIndicatorName(1);cx.看盘均线3周期=55;
 for(const [mode,label] of [[0,'MA55'],[1,'EMA55'],[2,'SMMA55'],[3,'LWMA55']]){
  cx.看盘辅助均线算法=mode;assert.equal(cx.UIIndicatorLabel(1),label);assert.equal(cx.UIIndicatorName(1),name);
 }
 cx.看盘均线3周期=20;cx.看盘辅助均线算法=1;
});
check('short and trend groups replace only their own moving averages',()=>{
 resetIndicators();cx.ViewAction(52);cx.ViewAction(53);cx.ViewAction(58);cx.ViewAction(60);
 assert.deepEqual([0,6,1,7,8,9].filter(i=>cx.UIIndicatorWindow(i)>=0),[0,6,1]);
 assert.equal(cx.UIIndicatorWindow(2),0);assert.equal(cx.UIIndicatorWindow(3),1);
 cx.ViewAction(61);assert.deepEqual([0,6,1,7,8,9].filter(i=>cx.UIIndicatorWindow(i)>=0),[1,7,9]);
 assert.equal(cx.UIIndicatorWindow(2),0);assert.equal(cx.UIIndicatorWindow(3),1);
});
check('group creation failure preserves existing averages and independent indicators',()=>{
 resetIndicators();cx.ViewAction(57);cx.ViewAction(52);cx.ViewAction(55);failCreate=true;
 assert.equal(cx.UIMovingAverageGroup(false),false);assert.equal(cx.UIIndicatorWindow(7),0);
 assert.equal(cx.UIIndicatorWindow(2),0);assert.equal(cx.UIIndicatorWindow(5),1);failCreate=false;
});
check('newly added averages save and restore without duplicating manual indicators',()=>{
 resetIndicators();for(const i of [6,7,8,9])cx.UIIndicatorSet(i,true);cx.SaveView();cx.CloseViewIndicators();cx.InitView();
 for(const i of [6,7,8,9])assert.equal(cx.UIIndicatorWindow(i),0);
 assert.equal(indicatorWindows[0].filter(d=>d.name==='Manual MA5').length,1);
});
check('overlay indicators can coexist and each closes independently',()=>{
 resetIndicators();for(let i=0;i<3;i++)cx.ViewAction(50+i);
 assert.deepEqual([0,1,2].map(i=>cx.UIIndicatorWindow(i)),[0,0,0]);
 cx.ViewAction(51);assert.equal(cx.UIIndicatorWindow(1),-1);assert.equal(cx.UIIndicatorWindow(0),0);assert.equal(cx.UIIndicatorWindow(2),0);
});
check('RSI MACD ATR replace only own oscillator and follow shifted subwindows',()=>{
 resetIndicators();indicatorWindows.push([{name:'Manual RSI(14)',handle:9001}]);
 for(let i=3;i<6;i++){
  cx.ViewAction(50+i);assert.equal(cx.UIIndicatorWindow(i),2);
  for(let j=3;j<6;j++)if(j!==i)assert.equal(cx.UIIndicatorWindow(j),-1);
  assert.equal(indicatorWindows.length,3);assert.equal(indicatorWindows[1][0].name,'Manual RSI(14)');
 }
 cx.CloseViewIndicators();assert.equal(indicatorWindows.length,2);
});
check('failed creation or attachment preserves previous oscillator and releases temporary handles',()=>{
 resetIndicators();cx.ViewAction(53);const old=cx.uiIndicatorHandles[3];
 failCreate=true;cx.ViewAction(54);assert.equal(cx.UIIndicatorWindow(3),1);assert.equal(cx.UIIndicatorWindow(4),-1);
 failCreate=false;failAdd=true;cx.ViewAction(54);assert.equal(cx.UIIndicatorWindow(3),1);assert.equal(cx.uiIndicatorHandles[3],old);
 assert(released.length>0);failAdd=false;
});
check('failed removal keeps displayed indicator and handle until deletion succeeds',()=>{
 resetIndicators();cx.ViewAction(50);const h=cx.uiIndicatorHandles[0];
 failDelete=true;cx.ViewAction(50);assert.equal(cx.UIIndicatorWindow(0),0);assert.equal(cx.uiIndicatorHandles[0],h);assert(!released.includes(h));
 failDelete=false;cx.ViewAction(50);assert.equal(cx.UIIndicatorWindow(0),-1);assert(released.includes(h));
});
check('manual deletion can be reopened without leaking the stale display handle',()=>{
 resetIndicators();cx.ViewAction(50);const h=cx.uiIndicatorHandles[0];
 cx.ChartIndicatorDelete(0,0,cx.UIIndicatorName(0));cx.ViewAction(50);
 assert.equal(cx.UIIndicatorWindow(0),0);assert(released.includes(h));assert.notEqual(cx.uiIndicatorHandles[0],h);
});
check('saved indicator combination restores once across EA cycle with fresh chart period',()=>{
 resetIndicators();cx.ViewAction(50);cx.ViewAction(52);cx.ViewAction(54);cx.SaveView();
 const h=cx.uiIndicatorHandles.slice();cx.CloseViewIndicators();assert(h.filter(v=>v>=0).every(v=>released.includes(v)));
 cx.ChartPeriod=()=>15;cx.InitView();assert.equal(cx.UIIndicatorWindow(0),0);assert.equal(cx.UIIndicatorWindow(2),0);assert.equal(cx.UIIndicatorWindow(4),1);
 assert.equal(indicatorHandles.get(cx.uiIndicatorHandles[0]).period,15);
 const n=indicatorWindows[0].length;cx.InitView();assert.equal(indicatorWindows[0].length,n);
 cx.ChartPeriod=()=>5;
});
check('one indicator click plus duplicate chart notifications toggles exactly once',()=>{
 resetIndicators();resetHits();gesture(53);assert.equal(cx.UIIndicatorWindow(3),1);
 gesture(53);assert.equal(cx.UIIndicatorWindow(3),-1);
});
check('all display helpers are isolated from requests and trading persistence',()=>{
 for(const name of ['UIIndicatorSet','CloseViewIndicators','UIIndicatorWindow','UIIndicatorName','UIIndicatorPeriod','UIIndicatorLabel','UIIsMovingAverage','UIIsOscillator','UIMovingAverageGroup'])
  assert(!/\bexecution\s*\.|\b(?:Open|Manage|Reconcile|Store|SavePending|ClearPending|Signal)\s*\(/.test(body(name)),name);
 assert(src.includes('#resource "Include\\\\View\\\\TgeChartOverlay.ex5"'));
 assert(src.includes('#resource "Include\\\\View\\\\TgeChartOscillator.ex5"'));
 const deinit=body('OnDeinit');assert(deinit.indexOf('SaveView()')<deinit.indexOf('CloseViewIndicators()'));
});


check('failed EA initialization cannot delete indicators before view namespace exists',()=>{
 resetIndicators();indicatorWindows[0].push({name:'V0 MA5',handle:9002});cx.uiPrefix='';
 cx.CloseViewIndicators();assert(indicatorWindows[0].some(v=>v.name==='V0 MA5'));
 cx.uiPrefix='TGUI.42.';assert.equal(cx.UIIndicatorWindow(-1),-1);assert.equal(cx.UIIndicatorWindow(16),-1);
});
check('context averages and structural overlays coexist with configured averages',()=>{
 resetIndicators();for(const i of [10,11,12,13])cx.ViewAction(60+i);cx.ViewAction(61);
 for(const i of [10,11,12,13])assert.equal(cx.UIIndicatorWindow(i),0);
 assert.equal(cx.UIIndicatorLabel(10),'M5·MA5');assert.equal(cx.UIIndicatorPeriod(10),5);
 assert.equal(cx.UIIndicatorLabel(11),'M15·MA5');assert.equal(cx.UIIndicatorPeriod(11),5);
});
check('ADX and KD replace only own oscillator while keeping manual chart indicators',()=>{
 resetIndicators();indicatorWindows.push([{name:'Manual RSI(14)',handle:9001}]);
 for(const action of [53,74,75,54,55,74]){
  cx.ViewAction(action);const index=action<60?action-50:action-60;
  assert.equal(cx.UIIndicatorWindow(index),2);assert.equal(indicatorWindows.length,3);
  for(const i of [3,4,5,14,15])if(i!==index)assert.equal(cx.UIIndicatorWindow(i),-1);
 }
 assert.equal(indicatorWindows[1][0].name,'Manual RSI(14)');
});
check('new context display preferences restore across chart reinitialization',()=>{
 resetIndicators();for(const i of [10,11,12,13,14])cx.UIIndicatorSet(i,true);cx.SaveView();cx.CloseViewIndicators();cx.InitView();
 for(const i of [10,11,12,13])assert.equal(cx.UIIndicatorWindow(i),0);assert.equal(cx.UIIndicatorWindow(14),1);
});
check('ADX and KD configurable inputs are passed to their own components',()=>{
 resetIndicators();cx.看盘ADX周期=10;cx.看盘ADX参考线=22;cx.看盘KD周期=14;cx.看盘KD平滑=5;cx.看盘KD信号=4;
 cx.ViewAction(74);assert.deepEqual(indicatorHandles.get(cx.uiIndicatorHandles[14]).parameters,[10,12,26,9,1,4,5,22]);
 cx.ViewAction(75);assert.deepEqual(indicatorHandles.get(cx.uiIndicatorHandles[15]).parameters,[14,12,26,9,1,4,5,22]);
 cx.看盘ADX周期=14;cx.看盘ADX参考线=25;cx.看盘KD周期=9;cx.看盘KD平滑=3;cx.看盘KD信号=3;
});
for(const file of ['TgeChartOverlay.mq5','TgeChartOscillator.mq5']){
 const indicator=fs.readFileSync('Include/View/'+file,'utf8');
 const begin=indicator.indexOf('{',indicator.indexOf('int OnCalculate(')),end=indicator.indexOf('\nvoid OnDeinit(',begin);
 const implementation=indicator.slice(begin+1,indicator.lastIndexOf('}',end));
 const calls=[];
 const x=vm.createContext({viewHandle:1,ViewKind:0,line0:[],line1:[],line2:[],INVALID_HANDLE:-1,
  calculated:100,copyFailure:false,BarsCalculated:()=>x.calculated,
  CopyBuffer:(_handle,buffer,start,count)=>{calls.push([buffer,start,count]);return x.copyFailure?-1:count;}});
 vm.runInContext('function calculate(rates_total,prev_calculated){'+convert(implementation)+'}',x);
 check(file+' waits for native data and rebuilds full history after reset',()=>{
  x.calculated=99;assert.equal(x.calculate(100,80),80);assert.equal(calls.length,0);
  x.calculated=100;assert.equal(x.calculate(100,0),100);assert.deepEqual(calls.pop(),[0,0,100]);
  assert.equal(x.calculate(100,120),100);assert.deepEqual(calls.pop(),[0,0,100]);
 });
 check(file+' updates current/new candle only and retries failed copies',()=>{
  assert.equal(x.calculate(100,100),100);assert.deepEqual(calls.pop(),[0,0,1]);
  assert.equal(x.calculate(100,99),100);assert.deepEqual(calls.pop(),[0,0,2]);
  x.copyFailure=true;assert.equal(x.calculate(100,99),0);x.copyFailure=false;calls.length=0;
  x.ViewKind=file.includes('Overlay')?2:1;assert.equal(x.calculate(100,99),100);
  assert.equal(calls.length,file.includes('Overlay')?3:2);assert(calls.every(v=>v[2]===2));
 });
 if(file.includes('Overlay')){
  const f=indicator.indexOf('int MapClosedView('),start=indicator.indexOf('{',f);let end=start+1,depth=1;
  for(;depth;end++){if(indicator[end]==='{')depth++;if(indicator[end]==='}')depth--;}
  const source=[{time:900,high:999,low:1},{time:600,high:150,low:120},{time:300,high:130,low:100},{time:0,high:110,low:90}];
  const data=[999,140,120,100];let unavailable=false;
  Object.assign(x,{_Symbol:'XAUUSD.c',ArraySetAsSeries:()=>{},PERIOD_M5:5,PERIOD_M15:15,PERIOD_D1:1440,
   Bars:()=>source.length,MathIsValidNumber:Number.isFinite,EMPTY_VALUE:-99999,
   iBarShift:(_s,_p,t)=>source.findIndex(b=>b.time<=t),
   CopyRates:(_s,_p,_start,n,out)=>{if(unavailable)return -1;out.push(...source.slice(0,n));return n;},
   CopyBuffer:(_h,_b,_start,n,out)=>{if(unavailable)return -1;out.push(...data.slice(0,n));return n;}});
  vm.runInContext('function MapClosedView(rates_total,from,time){'+convert(indicator.slice(start+1,end-1))+'}',x);
  check('M5 and M15 projection uses completed source bars without current-bar or future values',()=>{
   for(const kind of [3,4]){
    x.ViewKind=kind;x.line0=[];x.line1=[];x.line2=[];
    assert.equal(x.MapClosedView(6,0,[0,300,600,660,840,900]),6);
    assert.deepEqual(Array.from(x.line0),[-99999,100,120,120,120,140]);assert(!x.line0.includes(999));
   }
  });
  check('previous-day levels exclude current D1 extremes and respect history availability',()=>{
   x.ViewKind=6;assert.equal(x.MapClosedView(4,0,[300,600,840,900]),4);
   assert.deepEqual(Array.from(x.line0).slice(0,4),[110,130,130,150]);
   assert.deepEqual(Array.from(x.line1).slice(0,4),[90,100,100,120]);
   assert.equal(x.MapClosedView(1,0,[-1]),1);assert.equal(x.line0[0],-99999);
  });
  check('cross-period display waits on failed rates/buffer reads without fabricated values',()=>{
   unavailable=true;x.ViewKind=3;assert.equal(x.MapClosedView(1,0,[900]),0);
   x.ViewKind=6;assert.equal(x.MapClosedView(1,0,[900]),0);unavailable=false;
  });
  check('confirmed fractals hide current and two recent bars and refresh new confirmation',()=>{
   x.ViewKind=5;x.line0=Array(10).fill(100);x.line1=Array(10).fill(90);
   x.CopyBuffer=(_h,_b,_s,n,out)=>{for(let i=10-n;i<10;i++)out[i]=_b===0?100:90;return n;};
   assert.equal(x.calculate(10,9),10);assert.equal(x.line0[6],100);assert.equal(x.line1[6],90);
   for(const i of [7,8,9])assert.equal(x.line0[i],-99999);
   for(const i of [7,8,9])assert.equal(x.line1[i],-99999);
  });
 } else {
  check('ADX copies ADX plusDI minusDI and KD copies both stochastic lines',()=>{
   calls.length=0;x.ViewKind=3;assert.equal(x.calculate(100,99),100);
   assert.deepEqual(calls.map(c=>c[0]),[0,1,2]);
   calls.length=0;x.ViewKind=4;assert.equal(x.calculate(100,99),100);assert.deepEqual(calls.map(c=>c[0]),[0,1]);
  });
 }
 assert(!/\b(?:OrderSend|CTrade|execution)\b/.test(indicator));assert(indicator.includes('IndicatorRelease(viewHandle)'));
}


// 使用生产Panel与IndicatorPage，分别记录内存绘制和Update发布，防止“画了但没显示”。
resetIndicators();resetHits();props.set('width',1000);props.set('height',1000);
let backBuffer=[],frames=[];
Object.assign(cx,{
 uiCollapsed:false,uiIndicators:false,uiStatistics:false,levels:[],启用真实交易:false,
 UI_ROOT:3,UI_CARD:4,UI_ROW:5,UI_TEXT:6,UI_DIM:7,UI_WARN:8,UI_BORDER:9,UI_GAIN:10,UI_LOSS:11,UI_SELL:12,
 PositionsTotal:()=>0,EnsurePanel:h=>{cx.panelHeight=h;return true;},UIInk:v=>v,UIRound:()=>{},
 panelCanvas:{Erase:()=>{backBuffer=[];},FillRectangle:()=>{},Update:()=>{frames.push(backBuffer.slice());}},
 UIText:text=>backBuffer.push(String(text)),ObjectSetString:()=>true,OBJPROP_TOOLTIP:0,
 TimeGMT:()=>0,TimeToString:()=>'',TIME_SECONDS:1,TIME_DATE:2,TIME_MINUTES:4,
 feedStatus:'等待',sourceSender:'',identity:'',healthBeat:0,healthSync:0,sourceTime:0,sourceKind:'',
 feedActive:false,dayStopped:false,entryView:{ready:false},trend:0,reason:'等待点位',
 pending:{kind:0},每日权益回撤上限百分比:1,最大点差价格:0.5,_Digits:2,
 DoubleToString:(v,n)=>v.toFixed(n),AccountInfoString:()=>'USD',ACCOUNT_CURRENCY:0,
 StringFormat:(s,...values)=>s.replace(/%\.\df|%d|%s/g,()=>String(values.shift())),
 SyncStatus:()=>'等待同步',ExecutionBlock:()=>'观察模式'
});
for(const [name,args] of [['PageTabs','y'],['IndicatorPage',''],['Panel','']]){
 const code=convert(body(name)).replace(/let (\w+)\[\];/g,'let $1=[];').replace(/MqlTick (\w+);/g,'let $1={};');
 vm.runInContext('function '+name+'('+args+'){'+code+'}',cx);
}
const displayed=()=>frames.at(-1)||[];
check('actual watch-tab click publishes the new bitmap before returning',()=>{
 cx.Panel();assert(displayed().includes('当前没有本EA持仓'));
 const before=frames.length;gesture(4);
 assert.equal(cx.uiIndicators,true);assert.equal(cx.uiStatistics,false);
 assert.equal(frames.length,before+1,'watch page must call Canvas.Update');
 assert(displayed().includes('看盘设置'));assert(displayed().includes('MA5关'));
 assert(!displayed().includes('当前没有本EA持仓'));
 assert.equal(cx.uiHits.length,24);assert.equal(globals.get(cx.uiPrefix+'page'),2);
});
check('watch indicator clicks and redraws publish matching state without toggling back',()=>{
 const before=frames.length;gesture(50);
 assert.equal(frames.length,before+1);assert.equal(cx.UIIndicatorWindow(0),0);
 assert(displayed().includes('MA5开'));assert(!displayed().includes('MA5关'));
 cx.OnChartEvent(4,0,0,'');cx.Panel();
 assert.equal(cx.uiIndicators,true);assert.equal(cx.UIIndicatorWindow(0),0);assert(displayed().includes('MA5开'));
 gesture(50);assert.equal(cx.UIIndicatorWindow(0),-1);assert(displayed().includes('MA5关'));
});
check('returning from monitor or restored watch page publishes only current-page buttons',()=>{
 for(let i=0;i<3;i++){
  gesture(2);assert(displayed().includes('当前没有本EA持仓'));assert.equal(cx.uiHits.length,6);
  gesture(4);assert(displayed().includes('看盘设置'));assert.equal(cx.uiHits.length,24);
 }
 cx.SaveView();cx.uiIndicators=false;cx.uiStatistics=true;cx.InitView();
 const before=frames.length;cx.Panel();assert.equal(frames.length,before+1);
 assert.equal(cx.uiIndicators,true);assert.equal(cx.uiStatistics,false);assert(displayed().includes('看盘设置'));
});
check('collapsed watch page removes hidden indicator hit targets and expands with refreshed state',()=>{
 gesture(1);assert.equal(cx.uiCollapsed,true);assert.equal(cx.uiHits.length,6);
 assert(!displayed().includes('MA5关'));assert(displayed().includes('看盘页 · 指标显示设置'));
 gesture(1);assert.equal(cx.uiCollapsed,false);assert.equal(cx.uiHits.length,24);assert(displayed().includes('MA5关'));
});

check('monitor page presents AI reference independently of the old map and daily-limit caption',()=>{
 cx.读取AI即时策略=true;cx.aiReady=true;cx.AIPlanCaption=()=>'AI即时：BUY 4160 / SELL 4175';
 cx.ViewAction(2);assert(displayed().includes('AI即时：BUY 4160 / SELL 4175'));
 assert(!displayed().some(v=>v.includes('日亏损上限')));
});
console.log(checks+' production-source chart UI checks passed; native MT5 clicks not exercised.');
