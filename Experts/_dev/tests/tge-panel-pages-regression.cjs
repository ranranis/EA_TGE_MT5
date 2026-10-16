// Execute production layout with local positions; no terminal or trade requests.
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync('EA_T哥点位跟单.mq5','utf8');
function body(name){
 const at=src.indexOf('{',src.search(new RegExp('^(?:void|int) '+name+'\\(','m')));
 let end=at+1,depth=1;for(;depth;end++){if(src[end]==='{')depth++;if(src[end]==='}')depth--;}
 return src.slice(at+1,end-1);
}
function convert(s){return s.replace(/C'\d+,\d+,\d+'/g,'0')
 .replace(/\((count|directRows)\+([23])\)\/([34])/g,'Math.floor(($1+$2)/$3)')
 .replace(/\(ArraySize\(levels\)\+4\)\/5/g,'Math.floor((ArraySize(levels)+4)/5)')
 .replace(/card\/3/g,'Math.floor(card/3)')
 .replace(/\b(?:ulong|double) (\w+)\[\];/g,'let $1=[];')
 .replace(/\bstring (\w+)\[3\]=\{([\s\S]*?)\};/g,'let $1=[$2];')
 .replace(/\((?:int|long|ulong)\)/g,'')
 .replace(/\b(?:int|double|bool|color|string|ulong)\s+/g,'let ');}
let selected=0,positions=[],texts=[],buttons=[],bounds=[],dims=[];
const cx=vm.createContext({Math,MathMax:Math.max,MathMin:Math.min,MathRound:Math.round,
 ArraySize:a=>a.length,ArrayResize:(a,n)=>a.length=n,ArraySort:a=>a.sort((a,b)=>a-b),ArrayReverse:a=>a.reverse(),
 uiObserver:false,ObserverPage:()=>{},uiPositionPage:0,uiPositions:false,uiStatistics:false,uiIndicators:false,uiCollapsed:false,uiHits:[],
 uiMobileMarkers:false,uiPointLines:true,markerStatus:'手机TP关',tradeMode:false,
 入场策略:0,TGE_ENTRY_COMPAT:0,EffectiveEntryMethod:()=>1,启用积极持单:true,持单策略:1,TGE_HOLD_FIXED:2,AdaptiveCaption:()=>'结构持单',
 aiPlans:[{kind:'DIRECT',sign:1,level:4120,priority:90,confirmed:1,status:'等待触价'},
 {kind:'DIRECT',sign:-1,level:4180,priority:90,confirmed:1,status:'等待触价'},
 {kind:'ROLE',sign:-1,level:4170,priority:55,confirmed:1,status:'等待触价'}],
 levels:[4100,4120,4130,4145,4162,4170,4180,4190,4200,4222],feedActive:true,aiReason:'正常',
 PlanExecutable:()=>true,PlanAgeCaption:()=>'参考',AIChannelReady:()=>true,AIPlanCaption:()=>'同步正常',
 PointRoleCaption:()=>'参考',MapLifeCaption:()=>'地图参考',StringFind:(s,q)=>s.indexOf(q),
 TimeToString:()=>'00:40',TimeGMT:()=>0,TIME_SECONDS:1,TIME_MINUTES:2,
 IntegerToString:String,DoubleToString:(v,n)=>v.toFixed(n),StringFormat:()=>'参考点位',
 _Symbol:'XAUUSD.c',_Digits:2,VIEW:'TGE_',OBJPROP_TOOLTIP:1,ACCOUNT_CURRENCY:1,AccountInfoString:()=>'USC',
 PositionsTotal:()=>positions.length,PositionGetTicket:i=>{selected=i;return positions[i];},OwnSelected:()=>true,
 PositionSelectByTicket:t=>{selected=positions.indexOf(t);return selected>=0;},
 POSITION_VOLUME:1,POSITION_PROFIT:2,POSITION_SWAP:3,POSITION_SL:4,POSITION_TP:5,
 POSITION_TYPE:6,POSITION_TYPE_BUY:0,POSITION_PRICE_OPEN:7,POSITION_IDENTIFIER:8,
 PositionGetDouble:k=>({1:.02,2:1.25,3:0,4:4100,5:4120,7:4110})[k],PositionGetInteger:k=>k===6?0:positions[selected],
 PositionProgress:()=>'尚未减仓',entryView:{ready:false},reason:'等待触价',pending:{kind:0},
 ExecutionBlock:()=>'观察模式',LegacyLimitsClear:()=>true,SyncStatus:()=>'同步正常',
 EnsurePanel:(h,s)=>{dims=[h,s];return true;},ObjectSetString:()=>{},
 UIInk:v=>v,UIPx:v=>v,UIXPx:v=>v*760/560,
 UIRound:(x,y,w,h)=>bounds.push([y,h]),UICard:(x,y,w,h)=>bounds.push([y,h]),
 UIText:(s,x,y,w,size)=>{texts.push(String(s));bounds.push([y,size+4]);},
 UIButton:(s,x,y,w,a)=>{buttons.push({s,x,y,w,a});bounds.push([y,27]);},
 StatsPanel:()=>{},IndicatorPage:()=>{},panelCanvas:{Erase:()=>{},FillRectangle:()=>{},Update:()=>{}}
});
for(const key of [...src.matchAll(/\b(UI_[A-Z]+)=C'/g)].map(m=>m[1]))cx[key]=0;
for(const name of ['PageTabs','Panel'])vm.runInContext('function '+name+'('+(name==='PageTabs'?'y':'')+'){'+convert(body(name))+'}',cx);
function render(count,page){positions=Array.from({length:count},(_,i)=>100+i);cx.uiPositionPage=page;texts=[];buttons=[];bounds=[];cx.Panel();
 assert(bounds.every(([y,h])=>y>=0&&y+h<=dims[0]),'content outside canvas');
 for(let i=0;i<buttons.length;i++)for(let j=i+1;j<buttons.length;j++){
  const a=buttons[i],b=buttons[j];assert(a.x+a.w<=b.x||b.x+b.w<=a.x||a.y+27<=b.y||b.y+27<=a.y,'overlapping controls');}
 return texts.filter(t=>t.startsWith('#')).map(t=>+t.match(/^#(\d+)/)[1]);}
let planDims;
for(const count of [0,1,4,5,10]){cx.uiPositions=false;assert.deepEqual(render(count,0),[]);assert(texts.includes('点位计划'));
 assert(buttons.some(b=>b.a===8&&b.s==='编辑点位'));
 if(planDims)assert.deepEqual(dims,planDims);else planDims=[...dims];
 cx.uiPositions=true;let seen=[];for(let p=0;p<Math.max(1,Math.ceil(count/4));p++){
  seen.push(...render(count,p));assert(!texts.includes('点位计划'));assert.equal(dims[0],654);assert.equal(dims[1],planDims[1]);}
 assert.deepEqual(seen,Array.from({length:count},(_,i)=>99+count-i));}
cx.uiPositions=true;render(1,2);assert.equal(cx.uiPositionPage,0);assert(texts.some(t=>t.startsWith('#100')));
render(0,2);assert(texts.includes('当前没有本EA持仓'));
cx.aiPlans[0].source='MANUAL';cx.uiPositions=false;render(0,0);assert(texts.includes('点位计划 · 含手动修正'));
cx.uiObserver=true;render(0,0);assert(buttons.some(b=>b.a===9));assert.equal(dims[0],654);
console.log('PASS separate pages, stable sizing, 0/1/4/5/10 positions, complete pagination, page clamp, control/layout bounds');
