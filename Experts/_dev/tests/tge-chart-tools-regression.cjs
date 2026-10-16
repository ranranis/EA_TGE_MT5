const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync(process.argv[2]||'EA_T哥点位跟单.mq5','utf8')+'\n'+fs.readFileSync('Include/Trading/TgeMobileMarkers.mqh','utf8');
function body(name) {
 const def=src.search(new RegExp('^(?:int|uint|double|bool|void|string) '+name+'\\(','m'));
 assert(def>=0,name);const start=src.indexOf('{',def);let end=start+1,depth=1;
 for(;depth;end++){if(src[end]==='{')depth++;if(src[end]==='}')depth--;}
 return src.slice(start+1,end-1);
}
function convert(s) {
 return s.replace(/\(planCount\+1\)\/2/g,'Math.floor((planCount+1)/2)').replace(/\(ArraySize\(levels\)\+5\)\/6/g,'Math.floor((ArraySize(levels)+5)/6)').replace(/i\/([236])/g,'Math.floor(i/$1)').replace(/C'(\d+),(\d+),(\d+)'/g,'[$1,$2,$3]').replace(/\((?:int|double|long|ulong)\)/g,'')
 .replace(/\b(?:string|int) (\w+)\[\d+\]=\{([\s\S]*?)\};/g,'let $1=[$2];')
 .replace(/\b(?:int|string) (\w+)\[\d+\];/g,'let $1=[];')
 .replace(/\b(?:double|MqlRates) (\w+)\[\];/g,'let $1=[];')
 .replace(/\b(?:int|uint|bool|color|ulong|double|string|long|datetime|ENUM_LINE_STYLE|ENUM_TIMEFRAMES|ENUM_MA_METHOD)\s+/g,'let ')
 .replace(/\bMathMax\b/g,'Math.max').replace(/\bMathMin\b/g,'Math.min').replace(/\bMathRound\b/g,'Math.round');
}
const props=new Map([['scale',3],['follow',true],['grid',false],['shift',true],['mode',1],['scroll',true],['move',false],['width',1000],['height',1000]]);
const indicatorWindows=[[]],indicatorHandles=new Map(),released=[];
let nextHandle=100,failCreate=false,failAdd=false,failDelete=false;
const objects=new Map(),globals=new Map(),periods=[],navigation=[];let paint=0,drawLevels=0,checks=0;
const cx=vm.createContext({Math,FollowCaption:()=>'起飞跟随 · 等待消息',
 看盘均线1周期:5,看盘均线2周期:10,看盘均线3周期:20,看盘均线4周期:50,看盘均线5周期:100,看盘均线6周期:200,
 看盘主均线算法:0,看盘辅助均线算法:1,看盘指标计算价格:1,看盘布林周期:20,看盘布林标准差:2,
 看盘ADX周期:14,看盘ADX参考线:25,看盘KD周期:9,看盘KD平滑:3,看盘KD信号:3,看盘RSI周期:14,看盘MACD快线:12,看盘MACD慢线:26,看盘MACD信号线:9,看盘ATR周期:14,
 STYLE_SOLID:0,STYLE_DASH:1,STYLE_DOT:2,MODE_SMA:0,
 看盘面板宽度:560,看盘框体周期:5,看盘近期框根数:5,看盘震荡最少根数:12,看盘震荡ATR倍数:1.5,看盘收缩比较根数:100,看盘收缩低位百分比:20,
 EnumToString:()=> 'PERIOD_M5',StringReplace:()=>0,
 uiObserver:false,uiPositions:false,uiPositionPage:0,uiClickTracked:false,uiPaperSummary:true,
 paperPressedId:0,paperRowIds:[1,2,3,4,5],PAPER_PAGE_SIZE:5,PAPER_ARMS:5,paperDetailArm:0,paperListPage:0,
 statsPressedId:0,statsSelectedId:0,PaperClearReview:()=>{},PaperDetailAction:()=>{},ObserverAction:()=>{},ToggleTradeMode:()=>{},
 uiHistoryNextScan:0,SyncHistoryLayer:()=>{},
 StatsAction:a=>{if(a===43)cx.statsReview=Math.min(cx.statsTrades.length-1,cx.statsReview+1);if(a===44)cx.statsReview=Math.max(0,cx.statsReview-1);},
MODE_EMA:1,MODE_SMMA:2,MODE_LWMA:3,
 clrWhite:'white',clrOrangeRed:'red',clrGold:'gold',clrOrange:'orange',clrMediumTurquoise:'teal',clrDeepSkyBlue:'blue',clrMediumPurple:'purple',clrHotPink:'pink',uiX:8,uiY:24,panelWidth:560,panelHeight:565,panelScale:1,uiPrefix:'TGUI.42.',
 uiIndicatorLabels:['MA5','EMA20','布林','RSI','MACD','ATR','MA10','MA50','MA100','MA200','M5·MA5','M15·MA5','确认拐点','昨高低','ADX','随机KD','近期K线框','震荡箱体','波动收缩','框宽/ATR'],uiIndicatorHandles:Array(20).fill(-1),uiIndicatorNotice:'',INVALID_HANDLE:-1,
 uiWatchTab:0,uiUndoMask:-1,uiCollapsed:false,uiPointLines:true,uiStatistics:false,uiIndicators:false,statsPeriod:0,statsOffsets:[0,0,0],statsFilter:0,statsDetail:0,statsReview:0,statsDirty:true,statsLastAttempt:0,statsTrades:[],uiHits:[],uiPeriods:[1,5,15,30,16385,16388,16408],
 uiInitialized:false,uiOldMouseMove:false,uiDragging:false,uiOldScroll:false,uiLeftWasDown:false,uiPressedAction:0,uiDragDX:0,uiDragDY:0,panelReady:true,
 读取AI即时策略:false,每次开仓手数:.02,aiReady:false,aiMode:'WAIT',aiPlans:[],aiSourceTime:0,AIPlanCaption:()=>'AI等待',VIEW:'TGE_',_Symbol:'XAUUSD.c',UI_HEADER:0,UI_ACCENT:1,UI_MUTED:2,UI_DIM:3,
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
 ObjectsDeleteAll:()=>0,ChartID:()=>42,ChartSetSymbolPeriod:(_,symbol,period)=>{periods.push([symbol,period]);return true;},
 ChartNavigate:(_,mode,pos)=>{navigation.push([mode,pos]);return true;},ChartRedraw:()=>{},
 ObjectGetInteger:(_,name,p)=>objects.get(p)||0,ObjectSetInteger:(_,name,p,v)=>{objects.set(p,v);return true;},
 GlobalVariableSet:(k,v)=>{globals.set(k,v);return 1;},GlobalVariableCheck:k=>globals.has(k),GlobalVariableGet:k=>globals.get(k)||0,
 IntegerToString:String,StringToInteger:Number,GetLastError:()=>0,Print:()=>{},
 UIRound:()=>{},UICard:()=>{},UIText:()=>{},Panel:()=>paint++,DrawLevels:()=>drawLevels++,
 ArraySize:a=>a.length,ArrayResize:(a,n)=>{while(a.length<n)a.push({});a.length=n;}
});
for(const [name,args] of [['UIWidthFactor',''],['UIXPx','value'],['UIIndicatorBit','index'],['UIViewMask',''],['UIPresetMask','preset'],['UIPresetLabel','preset'],['UICombinationText','mask'],['UISetMask','mask'],['UIApplyMask','mask'],['UIFavorite','slot,save'],['UIIndicatorPeriod','index'],['UIIsMovingAverage','index'],['UIIsOscillator','index'],['UIIndicatorLabel','index'],['UIMovingAverageGroup','trendGroup'],['UIIndicatorName','index'],['UIIndicatorWindow','index'],['UIIndicatorSet','index,enabled'],['CloseViewIndicators',''],['UIPx','value'],['SaveView',''],['InitView',''],['MovePanel',''],
 ['UIButton','text,x,y,w,action,active=false'],['ChartTools','y'],['HitAction','mouseX,mouseY'],
 ['ToggleTgeMobileMarkers',''],['ViewAction','action'],['OnChartEvent','id,lparam,dparam,sparam']])
 vm.runInContext('function '+name+'('+args+'){'+convert(body(name))+'}',cx);
function check(name,fn){fn();checks++;console.log('PASS '+name);}
check('removed timeframe and generic chart actions do not change chart state',()=>{
 const old=[...props];for(let i=10;i<=26;i++)cx.ViewAction(i);
 assert.deepEqual([...props],old);assert.equal(periods.length,0);assert.equal(navigation.length,0);
 assert(!/ChartSetSymbolPeriod|CHART_SCALE|CHART_AUTOSCROLL|CHART_SHOW_GRID|CHART_SHIFT|CHART_MODE/.test(body('ChartTools')+body('ViewAction')));
});
check('indicator sections contain averages, structure and momentum without timeframe tools',()=>{
 cx.uiHits=[];cx.ChartTools(88);
 assert.deepEqual(Array.from(cx.uiHits,h=>h.action),[50,56,51,57,58,59,60,61,70,71,72,73,52,53,54,55,74,75]);
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
   assert(h.x+h.w<=548);assert(h.y+h.h<=y+229);
  }
  assert.equal(cx.HitAction(cx.uiX-1,cx.uiY-1),0);
 }
});

function resetHits(){
 cx.panelScale=1;cx.uiX=8;cx.uiY=24;cx.uiDragging=false;cx.uiLeftWasDown=false;cx.uiPressedAction=0;cx.uiClickTracked=false;
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
check('native Canvas clicks work without mouse state notifications',()=>{
 resetHits();cx.uiPointLines=true;const [x,y]=point(27);
 cx.OnChartEvent(2,x,y,'TGE_CANVAS');assert.equal(cx.uiPointLines,false);
 cx.OnChartEvent(1,x,y,'');assert.equal(cx.uiPointLines,false);
 cx.OnChartEvent(2,x,y,'TGE_CANVAS');assert.equal(cx.uiPointLines,true);
 cx.OnChartEvent(2,x,y,'user.drawing');assert.equal(cx.uiPointLines,true);
});
check('all rendered button hit areas follow panel width and display scaling',()=>{
 for(const width of [560,760,1000])for(const scale of [.45,1,1.5]){
  cx.看盘面板宽度=width;cx.panelScale=scale;cx.uiHits=[];
  for(let action=1;action<=8;action++)cx.UIButton('button',12+(action-1)*66,49,58,action);
  for(const h of cx.uiHits)
   assert.equal(cx.HitAction(cx.uiX+(h.x+h.w/2)*scale*width/560,cx.uiY+(h.y+13)*scale),h.action);
 }
 cx.看盘面板宽度=560;cx.panelScale=1;
});
check('holding mouse and repeated movements do not repeatedly execute button',()=>{
 resetHits();cx.uiPointLines=true;const [x,y]=point(27);
 cx.OnChartEvent(3,x,y,'1');for(let i=0;i<20;i++)cx.OnChartEvent(3,x+1,y+1,'1');
 assert.equal(cx.uiPointLines,true);cx.OnChartEvent(3,x,y,'0');assert.equal(cx.uiPointLines,true);
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
 assert.equal(globals.get('TGM.test.panelEnabled'),0);
 gesture(28);assert.equal(cx.uiMobileMarkers,true);assert.equal(globals.get('TGM.test.panelEnabled'),1);
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
 assert.deepEqual(JSON.parse(JSON.stringify(indicatorHandles.get(cx.uiIndicatorHandles[6]).parameters)),[13,2,5,2.5,[153,76,0],0,2]);
 assert.deepEqual(JSON.parse(JSON.stringify(indicatorHandles.get(cx.uiIndicatorHandles[0]).parameters)),[5,0,5,2.5,[46,99,142],0,1]);
 assert.deepEqual(JSON.parse(JSON.stringify(indicatorHandles.get(cx.uiIndicatorHandles[2]).parameters)),[25,2,5,2.5,[70,83,96],0,2]);
 // Replaced oscillator handles are released; recorded creation arguments still prove each native input.
 for(const [kind,p] of [[0,8],[1,10],[2,10]]){
  const d=[...indicatorHandles.values()].find(d=>d.path.includes('Oscillator')&&d.kind===kind);
  assert.deepEqual(d.parameters,[p,8,21,5,5,3,3,25]);
 }
 assert.equal(new Set([0,6,1,7,8,9].map(i=>JSON.stringify(indicatorHandles.get(cx.uiIndicatorHandles[i]).parameters[4]))).size,6);
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
  time:[],ArraySetAsSeries:()=>{},PaintNames:()=>{},calculated:100,copyFailure:false,BarsCalculated:()=>x.calculated,
  CopyBuffer:(_handle,buffer,start,count)=>{calls.push([buffer,start,count]);return x.copyFailure?-1:count;}});
 vm.runInContext('function calculate(rates_total,prev_calculated,time=Array(rates_total).fill(0)){'+convert(implementation)+'}',x);
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


check('six exact presets replace EA indicators without accumulating or deleting manual indicators',()=>{
 resetIndicators();cx.uiPointLines=false;
 const expected=[[0,1,13],[0,1,3,6],[1,7,9,14],[2,3,13],[0,1,4],[10,12,13,15]];
 for(let p=0;p<6;p++){
  cx.ViewAction(82+p);
  assert.deepEqual(Array.from({length:16},(_,i)=>i).filter(i=>cx.UIIndicatorWindow(i)>=0),expected[p]);
  assert.equal(cx.uiPointLines,true);assert.equal(cx.UIViewMask(),cx.UIPresetMask(p));
  assert(indicatorWindows[0].some(v=>v.name==='Manual MA5'));
 }
});
check('favorite combinations survive reinitialization, include lines and report empty slots',()=>{
 resetIndicators();cx.uiPointLines=false;cx.UIIndicatorSet(7,true);cx.UIIndicatorSet(15,true);
 const mask=cx.UIViewMask();cx.ViewAction(94);cx.ViewAction(82);cx.CloseViewIndicators();cx.InitView();
 cx.ViewAction(88);assert.equal(cx.UIViewMask(),mask);assert.equal(cx.uiPointLines,false);
 globals.delete(cx.uiPrefix+'favorite1');cx.ViewAction(89);assert.equal(cx.UIViewMask(),mask);
 assert(cx.uiIndicatorNotice.includes('尚未保存'));
});
check('clear preserves point lines, undo restores actual combination and is consumed',()=>{
 resetIndicators();cx.ViewAction(84);const mask=cx.UIViewMask();cx.ViewAction(93);
 assert.equal(cx.UIViewMask(),1<<16);assert.equal(cx.uiUndoMask,mask);
 cx.ViewAction(92);assert.equal(cx.UIViewMask(),mask);assert.equal(cx.uiUndoMask,-1);
 cx.ViewAction(92);assert.equal(cx.UIViewMask(),mask);
});
check('failed preset creation or removal does not claim success and preserves recoverable old state',()=>{
 resetIndicators();cx.UIIndicatorSet(7,true);cx.uiPointLines=false;const old=cx.UIViewMask();
 failCreate=true;assert.equal(cx.UIApplyMask(cx.UIPresetMask(0)),false);failCreate=false;
 assert.equal(cx.UIViewMask(),old);assert(cx.uiIndicatorNotice.includes('已恢复'));
 failDelete=true;assert.equal(cx.UIApplyMask(cx.UIPresetMask(1)),false);failDelete=false;
 assert(cx.uiIndicatorNotice.includes('未完成'));assert(cx.UIIndicatorWindow(7)>=0);
 assert.equal(cx.UIApplyMask(old),true);
});
check('combo captions follow configured MA periods and templates never set chart timeframe',()=>{
 cx.看盘均线3周期=34;
 assert(cx.UICombinationText(cx.UIPresetMask(2)).includes('EMA34'));cx.看盘均线3周期=20;
 for(const name of ['UIViewMask','UIPresetMask','UISetMask','UIApplyMask','UIFavorite'])
  assert(!/\bexecution\s*\.|\b(?:Open|Manage|Store|OrderSend|ChartSetSymbolPeriod)\s*\(/.test(body(name)));
});

// Current page layouts and statistics/replay controls are checked by their dedicated suites.
check('native clicks retain the pressed simulated-order identity across a refresh',()=>{
 resetHits();cx.uiHits=[];cx.UIButton('paper row',12,400,400,220);cx.paperRowIds[0]=11;
 const [x,y]=point(220);cx.OnChartEvent(3,x,y,'1');cx.paperRowIds[0]=22;
 cx.OnChartEvent(3,x,y,'0');let captured;
 cx.PaperDetailAction=()=>captured=cx.paperPressedId;
 cx.OnChartEvent(2,x,y,'TGE_CANVAS');assert.equal(captured,11);
 // A native-only click captures the row actually visible at click time.
 cx.OnChartEvent(2,x,y,'TGE_CANVAS');assert.equal(captured,22);
});
check('all five primary pages remain mutually exclusive through native clicks',()=>{
 resetHits();cx.uiHits=[];
 for(const [action,x] of [[2,12],[5,78],[3,144],[4,210],[9,276]])cx.UIButton('page',x,210,58,action);
 for(const action of [2,5,3,4,9,2]){
  gesture(action);
  assert.equal(cx.uiPositions,action===5);assert.equal(cx.uiStatistics,action===3);
  assert.equal(cx.uiIndicators,action===4);assert.equal(cx.uiObserver,action===9);
 }
});

check('closing point lines deletes all owned lines and price labels, and timer redraw cannot restore them',()=>{
 const drawn=new Map([['user.support',{}],['autotrade #1',{}]]);
 const x=vm.createContext({uiPointLines:true,levels:[4175,4182,4190,4222],VIEW:'TGE_',feedActive:false,
  _Symbol:'XAUUSD.c',_Period:5,_Digits:2,ArraySize:a=>a.length,IntegerToString:String,DoubleToString:(v,n)=>v.toFixed(n),
  OBJ_HLINE:1,OBJ_LABEL:2,OBJPROP_COLOR:3,OBJPROP_STYLE:4,STYLE_SOLID:0,OBJPROP_WIDTH:5,
  OBJPROP_BACK:6,OBJPROP_SELECTABLE:7,OBJPROP_TIMEFRAMES:8,OBJ_ALL_PERIODS:2097151,
  OBJPROP_TEXT:9,OBJPROP_CORNER:10,CORNER_RIGHT_UPPER:1,OBJPROP_ANCHOR:11,ANCHOR_RIGHT_LOWER:2,
  OBJPROP_XDISTANCE:12,OBJPROP_YDISTANCE:13,OBJPROP_FONTSIZE:14,OBJPROP_FONT:15,OBJPROP_TOOLTIP:16,
  CHART_HEIGHT_IN_PIXELS:1,ChartGetInteger:()=>1000,iTime:()=>1,
  ChartTimePriceToXY:()=>({x:500,y:100,ok:true}),
  ObjectFind:(_,n)=>drawn.has(n)?0:-1,ObjectCreate:(_,n,t)=>{drawn.set(n,{type:t});return true;},
  ObjectDelete:(_,n)=>drawn.delete(n),ObjectMove:(_,n,i,t,p)=>{drawn.get(n).price=p;return true;},
  ObjectSetInteger:(_,n,p,v)=>{drawn.get(n)[p]=v;return true;},
  ObjectSetString:(_,n,p,v)=>{drawn.get(n)[p]=v;return true;}
 });
 const code=convert(body('DrawLevels')).replace(
  'ChartTimePriceToXY(0,0,iTime(_Symbol,_Period,0),levels[i],px,py)',
  '((r)=>{px=r.x;py=r.y;return r.ok;})(ChartTimePriceToXY())');
 vm.runInContext('function DrawLevels(){'+code+'}',x);
 x.DrawLevels();assert.equal(drawn.size,10);
 x.uiPointLines=false;x.DrawLevels();assert.equal(drawn.size,2);
 x.levels.push(4160);x.DrawLevels();x.DrawLevels();assert.equal(drawn.size,2);
 x.uiPointLines=true;x.DrawLevels();assert.equal(drawn.size,12);
 assert(drawn.has('TGE_L4'));assert(drawn.has('TGE_PRICE4'));
 assert.equal(drawn.get('TGE_L4').price,4160);
 x.levels=[];x.DrawLevels();assert.equal(drawn.size,2);
 assert(drawn.has('user.support'));assert(drawn.has('autotrade #1'));
});

console.log(checks+' production-source chart UI checks passed; native MT5 clicks not exercised.');
