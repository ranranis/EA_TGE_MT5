// 从生产源码提取标记与撤单函数；服务器、历史及重启由确定性mock提供。
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const src=fs.readFileSync('Include/Trading/TgeMobileMarkers.mqh','utf8')+'\n'+fs.readFileSync('Include/Trading/MobileMarkerSafety.mqh','utf8');
function body(name){
 const def=src.search(new RegExp('^(?:bool|void|ulong|string) '+name+'\\(','m'));assert(def>=0,name);
 const start=src.indexOf('{',def);let end=start+1,depth=1;
 for(;depth;end++){if(src[end]==='{')depth++;if(src[end]==='}')depth--;}return src.slice(start+1,end-1);
}
function convert(s){return s.replace(/\bstatic\s+/g,'').replace(/\(string\)(\w+)/g,'String($1)')
 .replace(/\((?:long|ulong|int|double|datetime|ENUM_ORDER_STATE)\)/g,'')
 .replace(/\bMqlTick (\w+);/g,'let $1={};').replace(/\bbool (\w+)\[\];/g,'let $1=[];')
 .replace(/\b(?:ulong|long|int|double|datetime|string|bool|uint|ENUM_ORDER_STATE)\s+/g,'let ');}
let count=0;function check(name,f){f();count++;console.log('PASS '+name);}
function env(memory=new Map()){
 let selected={},pos={},deals=[];
 const orders=[],history=[],positions=[],allDeals=[],calls=[];
 const cx=vm.createContext({
  Math,MathAbs:Math.abs,MathMax:Math.max,MathRound:Math.round,NormalizeDouble:(v,n)=>+v.toFixed(n),
  StringFind:(s,q)=>s.indexOf(q),StringSubstr:(s,n)=>s.slice(n),StringLen:s=>s.length,StringToInteger:Number,
  IntegerToString:String,StringFormat:(s,...a)=>s.replace(/%I64d|%d|%s/g,()=>String(a.shift())),
  ArraySize:a=>a.length,ArrayResize:(a,n)=>{while(a.length<n)a.push(0);a.length=n;return n;},
  ArrayInitialize:(a,v)=>a.fill(v),TimeCurrent:()=>cx.now,GetTickCount64:()=>cx.now*1000,
  now:1000,_Symbol:'XAUUSD.c',_Point:.01,_Digits:2,TickSize:()=>.01,
  markerLock:1,markerPrefix:'TGM.77.',markerStatus:'',markerSequence:0,markerCreateAt:0,markerStateOK:true,
  markerDirty:true,markerLastMs:0,markerUnexpectedPosition:false,uiMobileMarkers:true,启用手机标记挂单:true,启用真实交易:true,
  手机标记挂单Magic:910406,手机标记挂单固定价格:100,TGE_MARKER_VOLUME:.01,TGE_MARKER_DANGER:20,
  EA魔法号:560056,accountServer:'test',accountLogin:7,Hash:()=>77,
  pending:{kind:0},levels:[3900,4000,4100],feedActive:true,
  mobileMarkerDeleteTickets:[],mobileMarkerDeleteTrackingLoaded:false,
  老师点位最近错误码:0,老师点位最近错误:'',
  permission:true,connected:true,fresh:true,exactLot:true,bid:4050,ask:4050.2,stops:50,orderMode:63,expirationMode:1,
  createAcknowledged:true,deleteAcknowledged:true,createCode:10009,deleteCode:10009,historyReadable:true,
  CanExecute:()=>cx.permission&&cx.connected&&cx.启用真实交易,TerminalInfoInteger:()=>cx.connected,
  FreshQuote:q=>cx.connected&&cx.fresh&&Object.assign(q,{bid:cx.bid,ask:cx.ask}),
  ExactLot:v=>cx.exactLot&&v===.01,
  SYMBOL_TRADE_STOPS_LEVEL:'stops',SYMBOL_ORDER_MODE:'orderMode',SYMBOL_EXPIRATION_MODE:'expirationMode',
  SYMBOL_ORDER_LIMIT:2,SYMBOL_EXPIRATION_GTC:1,SymbolInfoInteger:(_,k)=>cx[k],
  SYMBOL_VOLUME_STEP:'step',SymbolInfoDouble:()=>.01,
  ACCOUNT_LOGIN:1,AccountInfoInteger:()=>7,TERMINAL_CONNECTED:1,
  INVALID_HANDLE:-1,FILE_READ:1,FILE_WRITE:2,FILE_BIN:4,FILE_COMMON:8,
  FileOpen:()=>1,FileClose:()=>{},Print:()=>{},PrintFormat:()=>{},ResetLastError:()=>{},GetLastError:()=>0,
  GlobalVariableCheck:k=>memory.has(k),GlobalVariableGet:k=>memory.get(k)||0,
  GlobalVariableSet:(k,v)=>{memory.set(k,v);return 1;},GlobalVariableDel:k=>memory.delete(k),
  GlobalVariablesTotal:()=>memory.size,GlobalVariableName:i=>[...memory.keys()][i],GlobalVariablesFlush:()=>{},
  OrdersTotal:()=>orders.length,OrderGetTicket:i=>{selected=orders[i]||{};return selected.ticket||0;},
  OrderSelect:tk=>{selected=orders.find(o=>o.ticket===tk)||{};return !!selected.ticket;},
  OrderGetString:k=>selected[k]||'',OrderGetInteger:k=>selected[k]||0,OrderGetDouble:k=>selected[k]||0,
  PositionsTotal:()=>positions.length,PositionGetTicket:i=>{pos=positions[i]||{};return pos.ticket||0;},
  PositionGetString:k=>pos[k]||'',PositionGetInteger:k=>pos[k]||0,
  HistorySelect:()=>cx.historyReadable,HistoryOrdersTotal:()=>history.length,HistoryOrderGetTicket:i=>history[i].ticket,
  HistoryOrderSelect:tk=>cx.historyReadable&&history.some(o=>o.ticket===tk),
  HistoryOrderGetString:(tk,k)=>history.find(o=>o.ticket===tk)?.[k]||'',
  HistoryOrderGetInteger:(tk,k)=>history.find(o=>o.ticket===tk)?.[k]||0,
  HistoryOrderGetDouble:(tk,k)=>history.find(o=>o.ticket===tk)?.[k]||0,
  HistorySelectByPosition:id=>{deals=allDeals.filter(d=>d.DEAL_POSITION_ID===id);return cx.historyReadable;},
  HistoryDealsTotal:()=>deals.length,HistoryDealGetTicket:i=>deals[i]?.ticket||0,
  HistoryDealGetString:(tk,k)=>deals.find(d=>d.ticket===tk)?.[k]||'',
  HistoryDealGetInteger:(tk,k)=>deals.find(d=>d.ticket===tk)?.[k]||0,
  HistoryDealGetDouble:(tk,k)=>deals.find(d=>d.ticket===tk)?.[k]||0,
  ORDER_TYPE_BUY_LIMIT:2,ORDER_TIME_GTC:0,ORDER_STATE_CANCELED:4,ORDER_STATE_EXPIRED:5,ORDER_STATE_REJECTED:6,ORDER_STATE_FILLED:7,
  DEAL_ENTRY_IN:0,DEAL_ENTRY_OUT:1,DEAL_ENTRY_OUT_BY:2,DEAL_ENTRY_INOUT:3,
  TRADE_RETCODE_DONE:10009,TRADE_RETCODE_PLACED:10008,TRADE_RETCODE_DONE_PARTIAL:10010,
  TRADE_RETCODE_INVALID_EXPIRATION:10022,TRADE_RETCODE_INVALID_ORDER:10035,TRADE_RETCODE_LIMIT_ORDERS:10033,
  ExplicitReject:code=>code===10018
 });
 for(const key of ['ORDER_SYMBOL','ORDER_MAGIC','ORDER_COMMENT','ORDER_TYPE','ORDER_PRICE_OPEN','ORDER_TP','ORDER_SL','ORDER_VOLUME_CURRENT',
  'ORDER_VOLUME_INITIAL','ORDER_STATE','ORDER_POSITION_ID','POSITION_SYMBOL','POSITION_IDENTIFIER','POSITION_MAGIC','POSITION_COMMENT','DEAL_SYMBOL','DEAL_POSITION_ID','DEAL_ENTRY','DEAL_VOLUME'])cx[key]=key;
 let lastResult=0;
 const row=(ticket,tp,comment='TGE_MARK_'+ticket,magic=910406)=>({
  ticket,ORDER_SYMBOL:'XAUUSD.c',ORDER_MAGIC:magic,ORDER_COMMENT:comment,ORDER_TYPE:2,
  ORDER_PRICE_OPEN:100,ORDER_TP:tp,ORDER_SL:0,ORDER_VOLUME_CURRENT:.01,ORDER_VOLUME_INITIAL:.01
 });
 const retire=(ticket)=>{const i=orders.findIndex(o=>o.ticket===ticket);if(i>=0)history.push({...orders.splice(i,1)[0],ORDER_STATE:4});};
 cx.markerTrade={
  SetExpertMagicNumber:()=>{},SetTypeFillingBySymbol:()=>{},SetAsyncMode:()=>{},
  BuyLimit:(vol,price,symbol,sl,tp,mode,expiry,tag)=>{
   assert.equal(memory.get(cx.markerPrefix+'create'),cx.now,'intent must be saved first');
   calls.push(['create',vol,price,symbol,sl,tp,mode,expiry,tag]);
   lastResult=cx.createCode;
   if(cx.createAcknowledged&&lastResult===10009){const r=row(100+calls.length,tp,tag);r.ORDER_PRICE_OPEN=price;orders.push(r);}
   return lastResult===10009;
  },
  OrderDelete:ticket=>{
   assert(memory.has(cx.MobileMarkerDeletePrefix()+String(ticket)),'delete intent persisted before request');
   calls.push(['delete',ticket]);lastResult=cx.deleteCode;
   if(cx.deleteAcknowledged&&lastResult===10009)retire(ticket);
   return lastResult===10009;
  },
  ResultRetcode:()=>lastResult,ResultOrder:()=>orders.at(-1)?.ticket||0,ResultComment:()=>'broker result'
 };
 for(const [n,a] of [
  ['IsMobileMarkerTag','tag'],['IsMobileMarkerOrderSelected','tag=""'],['FindOpenPositionTicketByIdentifier','id'],
  ['IsTradeRetcodeAccepted','code'],['PrintRateLimited','key,seconds,message'],
  ['MobileMarkerDeletePrefix',''],['LoadMobileMarkerDeleteTracking',''],['RequestMobileMarkerDelete','ticket'],
  ['MobileMarkerOrderRetired','ticket'],['ReconcileMobileMarkerDeletes',''],
  ['TgeMarkerCanRequest',''],['TgeMarkerWrite','name,value'],['InitTgeMobileMarkers',''],
  ['TgeMarkerCreationTag',''],['ReconcileTgeMarkerCreation',''],['CancelTgeMobileMarkers',''],
  ['TgeMarkerHasOtherTrade',''],['TgeMarkerMatches','level,price'],['SubmitTgeMobileMarker','price,target'],
  ['SyncTgeMobileMarkers',''],['StopTgeMobileMarkers','']])
  vm.runInContext('function '+n+'('+a+'){'+convert(body(n))+'}',cx);
 const sync=()=>{cx.now+=5;cx.SyncTgeMobileMarkers();};
 return {cx,orders,history,positions,allDeals,calls,memory,row,retire,sync};
}
check('100-price .01 Buy Limits draw one TP per teacher level using independent Magic',()=>{
 const {cx,orders,calls,sync}=env();sync();assert.equal(orders.length,3);assert.equal(cx.markerStatus,'已同步3/3');
 assert.deepEqual(orders.map(o=>o.ORDER_TP),[3900,4000,4100]);
 for(const c of calls){assert.equal(c[0],'create');assert.equal(c[1],.01);assert.equal(c[2],100);assert.equal(c[4],0);}
 assert(orders.every(o=>o.ORDER_MAGIC===910406));assert.equal(cx.pending.kind,0);
 sync();assert.equal(calls.length,3);assert.equal(orders.length,3);
});
check('level edit replaces only the changed TP after confirmed retirement',()=>{
 const x=env();x.sync();const keep=x.orders.filter(o=>o.ORDER_TP!==4000).map(o=>o.ticket);
 x.cx.levels=[3900,4020,4100];x.sync();
 assert.deepEqual(x.orders.map(o=>o.ORDER_TP).sort(),[3900,4020,4100]);assert(keep.every(t=>x.orders.some(o=>o.ticket===t)));
 assert.equal(x.calls.filter(c=>c[0]==='delete').length,1);
});
check('accepted cancellation without disappearance never creates a replacement',()=>{
 const x=env();x.sync();const old=x.orders.find(o=>o.ORDER_TP===4000).ticket;
 x.cx.deleteAcknowledged=false;x.cx.levels=[3900,4020,4100];x.sync();x.sync();
 assert.equal(x.calls.filter(c=>c[0]==='create').length,3);assert(x.orders.some(o=>o.ticket===old));
 x.retire(old);x.sync();assert(x.orders.some(o=>o.ORDER_TP===4020));
});
check('disappeared order with unavailable history keeps replacement blocked across restart',()=>{
 const x=env();x.sync();const old=x.orders.find(o=>o.ORDER_TP===4000).ticket;
 x.cx.deleteAcknowledged=false;x.cx.levels=[3900,4020,4100];x.sync();x.retire(old);x.cx.historyReadable=false;x.sync();
 assert.equal(x.calls.filter(c=>c[0]==='create').length,3);
 const restarted=env(x.memory);restarted.cx.historyReadable=false;restarted.cx.InitTgeMobileMarkers();restarted.sync();
 assert.equal(restarted.calls.filter(c=>c[0]==='create').length,0);
});
check('unknown creation result is not resent after polling or process restart',()=>{
 const x=env();x.cx.levels=[4000];x.cx.createAcknowledged=false;x.cx.createCode=10012;x.sync();x.sync();
 assert.equal(x.calls.length,1);assert(x.cx.markerCreateAt>0);
 const restarted=env(x.memory);restarted.cx.levels=[4000];restarted.cx.InitTgeMobileMarkers();restarted.sync();
 assert.equal(restarted.calls.length,0);
 restarted.orders.push(restarted.row(500,4000,x.calls[0][8]));restarted.sync();
 assert.equal(restarted.calls.length,0);assert.equal(restarted.cx.markerCreateAt,0);
});
check('explicit rejection unlocks only marker intent and can retry on the next refresh',()=>{
 const x=env();x.cx.levels=[4000];x.cx.createCode=10018;x.sync();
 assert.equal(x.cx.markerCreateAt,0);assert.equal(x.cx.pending.kind,0);
 x.cx.createCode=10009;x.sync();assert.equal(x.orders.length,1);
});
check('torn creation record prevents fresh requests',()=>{
 const x=env(new Map([['TGM.77.create',-1]]));x.cx.InitTgeMobileMarkers();x.sync();assert.equal(x.calls.length,0);
});
check('disabled phone marks withdraw owned orders and preserve ordinary/legacy orders',()=>{
 const x=env();x.sync();x.orders.push(x.row(900,4500,'Manual',0),x.row(901,4200,'SMA_MARK_K01',910405));
 x.cx.uiMobileMarkers=false;x.sync();assert.deepEqual(x.orders.map(o=>o.ticket),[900,901]);
 assert(!x.calls.some(c=>c[0]==='delete'&&c[1]>=900));
});
check('existing real position withdraws markers without changing or closing that position',()=>{
 const x=env();x.sync();x.positions.push({ticket:700,POSITION_SYMBOL:'XAUUSD.c',POSITION_IDENTIFIER:770});
 x.sync();assert.equal(x.orders.length,0);assert.equal(x.positions.length,1);assert.equal(x.cx.pending.kind,0);
});
check('accidentally filled marker is reported and never treated as an ordinary strategy position',()=>{
 const x=env();x.sync();x.positions.push({ticket:700,POSITION_SYMBOL:'XAUUSD.c',POSITION_IDENTIFIER:770,
  POSITION_MAGIC:910406,POSITION_COMMENT:'TGE_MARK_1'});
 x.sync();assert.equal(x.orders.length,0);assert.equal(x.positions.length,1);
 assert.equal(x.cx.markerStatus,'标记意外成交，需人工核对');assert.equal(x.cx.pending.kind,0);
});
check('core pending order stops markers independently without clearing core pending',()=>{
 const x=env();x.sync();x.cx.pending={kind:1};x.sync();assert.equal(x.orders.length,0);assert.equal(x.cx.pending.kind,1);
});
check('danger distance withdraws all owned marks before they can approach trigger price',()=>{
 const x=env();x.sync();x.cx.bid=120;x.cx.ask=120.2;x.sync();assert.equal(x.orders.length,0);
 assert.equal(x.calls.filter(c=>c[0]==='create').length,3);
});
check('disconnection, stale quote, disabled permissions and observation cannot create markers',()=>{
 for(const change of [x=>x.connected=false,x=>x.fresh=false,x=>x.permission=false,x=>{x.启用真实交易=false;x.InitTgeMobileMarkers();}]){
  const x=env();change(x.cx);x.sync();assert.equal(x.calls.length,0);
 }
});
check('wrong symbol, undersized lot, unsupported pending/expiry and Magic collision cannot create marks',()=>{
 for(const change of [x=>x._Symbol='EURUSD',x=>x.exactLot=false,x=>x.orderMode=0,x=>x.expirationMode=0,x=>x.EA魔法号=910406]){
  const x=env();change(x.cx);x.sync();assert.equal(x.calls.length,0);
 }
});
check('price and target are checked against tick precision and broker stops',()=>{
 const x=env();x.cx.levels=[100.1];x.sync();assert.equal(x.calls.length,0);
 const y=env();y.cx.手机标记挂单固定价格=100.006;y.cx.levels=[4000.006];y.sync();
 assert.equal(y.orders[0].ORDER_PRICE_OPEN,100.01);assert.equal(y.orders[0].ORDER_TP,4000.01);
});
check('deinitialization records cancellation intentions for every owned marker',()=>{
 const x=env();x.sync();x.cx.deleteAcknowledged=false;x.cx.StopTgeMobileMarkers();
 assert.equal(x.calls.filter(c=>c[0]==='delete').length,3);assert.equal(x.cx.markerLock,-1);
 assert.equal(x.cx.mobileMarkerDeleteTickets.length,3);
});
check('cancel/fill race cannot retire until position is gone and actual exit Deals balance entry',()=>{
 const x=env();x.history.push({...x.row(800,4000),ORDER_STATE:7,ORDER_VOLUME_CURRENT:0,ORDER_POSITION_ID:880});
 x.positions.push({ticket:801,POSITION_IDENTIFIER:880,POSITION_SYMBOL:'XAUUSD.c'});
 assert.equal(x.cx.MobileMarkerOrderRetired(800),false);x.positions.length=0;
 x.allDeals.push({ticket:900,DEAL_SYMBOL:'XAUUSD.c',DEAL_POSITION_ID:880,DEAL_ENTRY:0,DEAL_VOLUME:.01});
 assert.equal(x.cx.MobileMarkerOrderRetired(800),false);
 x.allDeals.push({ticket:901,DEAL_SYMBOL:'XAUUSD.c',DEAL_POSITION_ID:880,DEAL_ENTRY:1,DEAL_VOLUME:.01});
 assert.equal(x.cx.MobileMarkerOrderRetired(800),true);
});
check('filled creation result cannot unlock using broker acceptance alone',()=>{
 const x=env();x.cx.markerSequence=1;x.cx.markerCreateAt=990;
 x.history.push({...x.row(800,4000,'TGE_MARK_1'),ORDER_STATE:7,ORDER_VOLUME_CURRENT:0,ORDER_POSITION_ID:880});
 assert.equal(x.cx.ReconcileTgeMarkerCreation(),false);assert.equal(x.cx.markerCreateAt,990);
});
check('actual BuyLimit and cancellation are confined to separate marker object and guarded entry',()=>{
 assert(body('SubmitTgeMobileMarker').includes('!TgeMarkerCanRequest()'));
 assert(body('CancelTgeMobileMarkers').includes('!TgeMarkerCanRequest()'));
 assert(!/\bexecution\s*\./.test(src));assert(!/PositionOpen|PositionClose|OrderSend/.test(src));
});
console.log(count+' production-source marker checks passed; no broker requests or mobile display exercised.');
