// Production display functions in a virtual chart. No terminal connection.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync('EA_T哥点位跟单.mq5','utf8');
function body(name){
 const a=src.search(new RegExp('^(?:void|bool) '+name+'\\(','m'));assert(a>=0,name);
 const b=src.indexOf('{',a);let z=b+1,n=1;for(;n;z++){if(src[z]==='{')n++;if(src[z]==='}')n--;}return src.slice(b+1,z-1);
}
function install(x,name,args='',refs=false){
 let raw=body(name);if(refs)raw=raw.replace(/return ([^;]+);/g,'return {ok:$1,enter,leave};');
 let s=raw.replace(/\((?:int|double|datetime|ENUM_OBJECT)\)/g,'')
 .replace(/\bstring (\w+)\[\];/g,'let $1=[];')
 .replace(/\b(?:const )?(?:datetime|double|int|ulong|string|bool|ENUM_OBJECT)\s+/g,'let ')
 .replace(/HistoryClipEdge\(([^,]+),([^,]+),enter,leave\)/g,(_,a,b)=>'((r)=>{enter=r.enter;leave=r.leave;return r.ok;})(HistoryClipEdge('+a+','+b+',enter,leave))')
 .replace('HistoryPanelSpan(x1,y1,x2,y2,left,top,right,bottom,enter,leave)','((r)=>{enter=r.enter;leave=r.leave;return r.ok;})(HistoryPanelSpan(x1,y1,x2,y2,left,top,right,bottom))')
 .replace(/ChartTimePriceToXY\(0,0,(t[12]),(p[12]),(x[12]),(y[12])\)/g,(_,a,b,c,d)=>'((r)=>{'+c+'=r.x;'+d+'=r.y;return r.ok;})(ChartTimePriceToXY(0,0,'+a+','+b+'))');
 for(const [v,t,p] of [['from','start','low'],['to','end','high']]){
  const xy='0,MathRound(x1+(x2-x1)*'+v+'),MathRound(y1+(y2-y1)*'+v+')';
  s=s.replace('ChartXYToTimePrice('+xy+',window,'+t+','+p+')',
   '((r)=>{window=r.window;'+t+'=r.time;'+p+'=r.price;return r.ok;})(ChartXYToTimePrice('+xy+'))');
 }
 vm.runInContext('function '+name+'('+args+'){'+s+'}',x);
}
function env(){
 const objects=new Map(),writes=[],deletes=[];let time=1000,scan=0,failConversion=false;
 const chart={CHART_FIRST_VISIBLE_BAR:100,CHART_WIDTH_IN_PIXELS:1000,CHART_HEIGHT_IN_PIXELS:800,
 CHART_VISIBLE_BARS:100,CHART_SCALE:3,CHART_PRICE_MIN:0,CHART_PRICE_MAX:800};
 const props=['OBJPROP_BACK','OBJPROP_HIDDEN','OBJPROP_TYPE','OBJPROP_CREATETIME','OBJPROP_TIME','OBJPROP_PRICE',
 'OBJPROP_COLOR','OBJPROP_STYLE','OBJPROP_WIDTH','OBJPROP_TIMEFRAMES','OBJPROP_RAY_LEFT','OBJPROP_RAY_RIGHT',
 'OBJPROP_SELECTABLE','OBJPROP_ZORDER','OBJPROP_TOOLTIP'];
 const x=vm.createContext({
  MathAbs:Math.abs,MathMax:Math.max,MathMin:Math.min,MathRound:Math.round,IntegerToString:String,DoubleToString:(v,d)=>v.toFixed(d),
  ArraySize:a=>a.length,ArrayResize:(a,n)=>{while(a.length<n)a.push({});a.length=n;return n;},
  StringFind:(s,t)=>s.indexOf(t),StringLen:s=>s.length,StringSubstr:(s,a,n)=>s.slice(a,a+n),
  历史成交置于面板后方:true,panelReady:true,uiX:100,uiY:100,panelWidth:200,panelHeight:200,uiDragging:false,
  uiHistoryNextScan:0,uiHistoryLastScan:0,uiHistoryObjectCount:-1,uiHistoryGeometry:'',uiHistoryLayers:[],uiHistoryCopySerial:0,
  VIEW:'TGE_',_Digits:2,GetTickCount64:()=>time,ChartRedraw:()=>{},
  ...Object.fromEntries(Object.keys(chart).map(k=>[k,k])),...Object.fromEntries(props.map(k=>[k,k])),
  OBJ_TREND:1,OBJ_ARROW:2,OBJ_ARROW_BUY:3,OBJ_ARROW_SELL:4,
  ChartGetInteger:(id,k)=>chart[k],ChartGetDouble:(id,k)=>chart[k],
  ObjectsTotal:()=>objects.size,ObjectName:(id,i)=>{scan++;return [...objects.keys()][i];},
  ObjectFind:(id,n)=>objects.has(n)?0:-1,
  ObjectGetInteger:(id,n,k,index=0)=>{const o=objects.get(n);return k==='OBJPROP_TIME'?o.points[index][0]:o[k]||0;},
  ObjectGetDouble:(id,n,k,index=0)=>objects.get(n).points[index][1],
  ObjectSetInteger:(id,n,k,v)=>{writes.push([n,k,v]);objects.get(n)[k]=v;return true;},
  ObjectSetString:(id,n,k,v)=>{objects.get(n)[k]=v;return true;},
  ObjectCreate:(id,n,type,win,t1,p1,t2,p2)=>{objects.set(n,{OBJPROP_TYPE:type,points:[[t1,p1],[t2,p2]]});return true;},
  ObjectMove:(id,n,index,t,p)=>{objects.get(n).points[index]=[t,p];return true;},
  ObjectDelete:(id,n)=>{deletes.push(n);return objects.delete(n);},
  ChartTimePriceToXY:(id,w,t,p)=>({ok:true,x:t,y:p}),
  ChartXYToTimePrice:(id,a,b)=>({ok:!failConversion,window:0,time:a,price:b})
 });
 for(const[n,a,r]of [['IsNativeTradeHistory','name'],['HistoryClipEdge','p,q,enter,leave',true],
 ['HistoryPanelSpan','x1,y1,x2,y2,left,top,right,bottom,enter=0,leave=1',true],['HistoryDeleteCopies','base'],
 ['HistoryCopySegment','source,name,t1,p1,t2,p2,x1,y1,x2,y2,from,to'],['SyncHistoryLayer',''],['RestoreHistoryLayer','']])install(x,n,a,r);
 function add(name,points,patch={}){objects.set(name,{points,OBJPROP_TYPE:1,OBJPROP_BACK:false,OBJPROP_HIDDEN:true,
  OBJPROP_CREATETIME:1,OBJPROP_COLOR:1234,OBJPROP_STYLE:2,OBJPROP_WIDTH:1,OBJPROP_TIMEFRAMES:31,...patch});}
 return {x,objects,writes,deletes,chart,add,setTime:t=>time=t,getScan:()=>scan,setFail:f=>failConversion=f};
}
let cases=0;function test(n,f){f();cases++;console.log('PASS '+n);}
test('horizontal, vertical, diagonal, reversed and inside segments clip at panel edges',()=>{
 const {x}=env();
 for(const points of [[0,200,400,200],[200,0,200,400],[0,0,400,400],[400,200,0,200],[150,150,250,250]]){
  const r=x.HistoryPanelSpan(...points,100,100,300,300);assert(r.ok);assert(r.enter>=0&&r.leave<=1&&r.enter<=r.leave);
 }
 assert(!x.HistoryPanelSpan(0,20,400,20,100,100,300,300).ok);
 assert(!x.HistoryPanelSpan(350,0,350,500,100,100,300,300).ok);
});
test('crossing line keeps two foreground parts; original anchors and style are preserved',()=>{
 const e=env();e.add('autotrade #1',[[0,200],[500,200]]);e.x.SyncHistoryLayer();
 const native=e.objects.get('autotrade #1');assert(native.OBJPROP_BACK);assert.deepEqual(native.points,[[0,200],[500,200]]);
 const copies=[...e.objects.entries()].filter(([n])=>n.startsWith('TGE_HC'));assert.equal(copies.length,2);
 for(const [,o]of copies){assert.equal(o.OBJPROP_BACK,false);assert.equal(o.OBJPROP_COLOR,1234);assert.equal(o.OBJPROP_STYLE,2);assert.equal(o.OBJPROP_WIDTH,1);
  assert(o.points[1][0]<=88||o.points[0][0]>=312);assert.equal(o.OBJPROP_SELECTABLE,false);}
});
test('outside native lines stay foreground without copies',()=>{
 const e=env();e.add('autotrade #2',[[0,50],[900,50]]);e.x.SyncHistoryLayer();
 assert.equal(e.objects.get('autotrade #2').OBJPROP_BACK,false);assert.equal(e.objects.size,1);
});
test('collapse restores covered lines immediately, without five-second wait',()=>{
 const e=env();e.add('autotrade #3',[[0,200],[900,200]]);e.x.SyncHistoryLayer();assert.equal(e.objects.size,3);
 e.x.panelHeight=40;e.setTime(1001);e.x.SyncHistoryLayer();
 assert.equal(e.objects.get('autotrade #3').OBJPROP_BACK,false);assert.equal(e.objects.size,1);
});
test('drag/release repositions cuts without stale fragments',()=>{
 const e=env();e.add('autotrade #4',[[0,200],[900,200]]);e.x.SyncHistoryLayer();
 e.x.uiX=400;e.x.uiDragging=true;e.setTime(1050);e.x.SyncHistoryLayer();assert.equal(e.objects.get('TGE_HC1a').points[1][0],88);
 e.x.uiDragging=false;e.x.SyncHistoryLayer();assert.equal(e.objects.get('TGE_HC1a').points[1][0],388);assert.equal(e.objects.size,3);
});
test('arrows outside panel remain foreground; covered arrows return after panel moves',()=>{
 const e=env();e.add('autotrade #arrow',[[200,200]],{OBJPROP_TYPE:2});e.add('autotrade #outside',[[700,200]],{OBJPROP_TYPE:3});
 e.x.SyncHistoryLayer();assert(e.objects.get('autotrade #arrow').OBJPROP_BACK);assert(!e.objects.get('autotrade #outside').OBJPROP_BACK);
 e.x.uiY=400;e.x.SyncHistoryLayer();assert(!e.objects.get('autotrade #arrow').OBJPROP_BACK);
});
test('native history toggle off removes owned fragments with no ghosts',()=>{
 const e=env();e.add('autotrade #5',[[0,200],[900,200]]);e.x.SyncHistoryLayer();e.objects.delete('autotrade #5');e.x.SyncHistoryLayer();
 assert.equal(e.objects.size,0);assert.equal(e.x.uiHistoryLayers.length,0);
});
test('same-name native rebuild cleans fragments from old generation',()=>{
 const e=env();e.add('autotrade #6',[[0,200],[900,200]]);e.x.SyncHistoryLayer();
 e.add('autotrade #6',[[0,400],[900,400]],{OBJPROP_CREATETIME:2});e.x.uiHistoryNextScan=0;e.x.SyncHistoryLayer();
 assert.equal(e.objects.size,1);assert(!e.objects.get('autotrade #6').OBJPROP_BACK);
});
test('conversion failure keeps native line visible instead of silently losing segments',()=>{
 const e=env();e.add('autotrade #7',[[0,200],[900,200]]);e.setFail(true);e.x.SyncHistoryLayer();
 assert.equal(e.objects.size,1);assert(!e.objects.get('autotrade #7').OBJPROP_BACK);
});
test('unload restores originals, deletes owned fragments and preserves user background settings',()=>{
 const e=env();e.add('autotrade #8',[[0,200],[900,200]]);e.add('autotrade #bg',[[0,200],[900,200]],{OBJPROP_BACK:true});
 e.add('manual trend',[[0,200],[900,200]]);e.x.SyncHistoryLayer();e.x.RestoreHistoryLayer();
 assert.equal(e.objects.size,3);assert(!e.objects.get('autotrade #8').OBJPROP_BACK);assert(e.objects.get('autotrade #bg').OBJPROP_BACK);
 assert(!e.writes.some(a=>a[0]==='manual trend'||a[0]==='autotrade #bg'));
});
test('steady chart uses cache; scrolling and vertical scale invalidate it',()=>{
 const e=env();e.add('autotrade #9',[[0,50],[900,50]]);e.x.SyncHistoryLayer();const n=e.getScan();e.x.SyncHistoryLayer();assert.equal(e.getScan(),n);
 e.chart.CHART_FIRST_VISIBLE_BAR=120;e.x.SyncHistoryLayer();assert(e.getScan()>n);const m=e.getScan();
 e.chart.CHART_PRICE_MAX=900;e.x.SyncHistoryLayer();assert(e.getScan()>m);
});
test('button redraw and drag-release resync after final panel bounds without trade calls',()=>{
 assert.match(body('ViewAction'),/Panel\(\); uiHistoryNextScan=0; SyncHistoryLayer\(\); SaveView\(\);/);
 assert.match(body('OnChartEvent'),/uiDragging=false[\s\S]*?SyncHistoryLayer\(\)/);
 assert(!/OrderSend|PositionClose|PositionModify|ClearPending/.test(body('SyncHistoryLayer')));
});
console.log(cases+' history visibility regression cases passed');
