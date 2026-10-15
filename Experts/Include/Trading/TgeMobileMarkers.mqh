#ifndef TGE_MOBILE_MARKERS_MQH
#define TGE_MOBILE_MARKERS_MQH

// 手机显示需要真实服务器挂单；与策略execution、Magic及pending完全分开。
const long 手机标记挂单Magic=910406;
const double TGE_MARKER_VOLUME=0.01,TGE_MARKER_DANGER=20.0;
CTrade markerTrade;
int markerLock=INVALID_HANDLE;
string markerPrefix="",markerStatus="等待初始化";
long markerSequence=0;
datetime markerCreateAt=0;
bool markerStateOK=true,markerDirty=true,markerUnexpectedPosition=false;
ulong markerLastMs=0;
uint 老师点位最近错误码=0;
string 老师点位最近错误="";

bool IsMobileMarkerTag(const string tag) { return StringFind(tag,"TGE_MARK_")==0; }
bool IsMobileMarkerOrderSelected(const string tag="")
{
   string comment=OrderGetString(ORDER_COMMENT);
   return OrderGetString(ORDER_SYMBOL)==_Symbol && OrderGetInteger(ORDER_MAGIC)==手机标记挂单Magic &&
          IsMobileMarkerTag(comment) && (tag=="" || tag==comment);
}
ulong FindOpenPositionTicketByIdentifier(const ulong id)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==id) return ticket;
   }
   return 0;
}
bool IsTradeRetcodeAccepted(const uint code)
{
   return code==TRADE_RETCODE_DONE || code==TRADE_RETCODE_PLACED || code==TRADE_RETCODE_DONE_PARTIAL;
}
void PrintRateLimited(const string key,const int seconds,const string message)
{
   static datetime last=0;
   if(last==0 || TimeCurrent()-last>=seconds) { Print(message); last=TimeCurrent(); }
}
// 复用原系统已持久化、按订单终态及真实Deal确认的撤单实现。
#include "MobileMarkerSafety.mqh"

bool TgeMarkerCanRequest()
{
   return markerLock!=INVALID_HANDLE && EA魔法号!=(ulong)手机标记挂单Magic && CanExecute();
}
bool TgeMarkerWrite(const string name,const double value)
{
   if(GlobalVariableSet(markerPrefix+name,value)==0) { markerStateOK=false; return false; }
   return true;
}
void InitTgeMobileMarkers()
{
   markerPrefix="TGM."+IntegerToString((long)Hash(accountServer+"|"+IntegerToString(accountLogin)+"|"+_Symbol))+".";
   if(GlobalVariableCheck(markerPrefix+"enabled")) uiMobileMarkers=GlobalVariableGet(markerPrefix+"enabled")>0;
   markerSequence=(long)GlobalVariableGet(markerPrefix+"sequence");
   markerCreateAt=(datetime)GlobalVariableGet(markerPrefix+"create");
   markerLock=FileOpen("FeishuMT5SignalMonitor\\"+markerPrefix+"lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(markerLock==INVALID_HANDLE) { markerStatus="其他实例正在管理标记"; return; }
   markerTrade.SetExpertMagicNumber(手机标记挂单Magic);
   markerTrade.SetTypeFillingBySymbol(_Symbol); markerTrade.SetAsyncMode(false);
   LoadMobileMarkerDeleteTracking();
}
string TgeMarkerCreationTag() { return "TGE_MARK_"+IntegerToString(markerSequence); }
bool ReconcileTgeMarkerCreation()
{
   if(!markerStateOK || markerCreateAt<0) { markerStatus="标记意图写入中断，待核对"; return false; }
   if(markerCreateAt==0) return true;
   string tag=TgeMarkerCreationTag();
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket>0 && IsMobileMarkerOrderSelected(tag))
      {
         if(!TgeMarkerWrite("create",0)) return false;
         GlobalVariablesFlush(); markerCreateAt=0; return true; // 真实挂单已可读。
      }
   }
   if(HistorySelect(markerCreateAt-60,TimeCurrent()+1))
      for(int i=HistoryOrdersTotal()-1;i>=0;i--)
      {
         ulong ticket=HistoryOrderGetTicket(i);
         if(HistoryOrderGetString(ticket,ORDER_SYMBOL)!=_Symbol ||
            HistoryOrderGetInteger(ticket,ORDER_MAGIC)!=手机标记挂单Magic ||
            HistoryOrderGetString(ticket,ORDER_COMMENT)!=tag) continue;
         if(!MobileMarkerOrderRetired(ticket)) break;
         if(!TgeMarkerWrite("create",0)) return false;
         GlobalVariablesFlush(); markerCreateAt=0; return true;
      }
   markerStatus="挂单结果待服务器确认，不重复补发";
   return false;
}
void CancelTgeMobileMarkers()
{
   if(!TgeMarkerCanRequest()) return;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket>0 && IsMobileMarkerOrderSelected()) RequestMobileMarkerDelete(ticket);
   }
}
bool TgeMarkerHasOtherTrade()
{
   // 延续原系统行为：当前品种开始真实交易后，撤掉提示挂单。
   bool hasPosition=false; markerUnexpectedPosition=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      hasPosition=true;
      if(PositionGetInteger(POSITION_MAGIC)==手机标记挂单Magic && IsMobileMarkerTag(PositionGetString(POSITION_COMMENT)))
         markerUnexpectedPosition=true;
   }
   if(hasPosition) return true;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && !IsMobileMarkerOrderSelected()) return true;
   return false;
}
bool TgeMarkerMatches(const double level,const double price)
{
   return IsMobileMarkerOrderSelected() && OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_BUY_LIMIT &&
          MathAbs(OrderGetDouble(ORDER_PRICE_OPEN)-price)<TickSize()*0.5 &&
          MathAbs(OrderGetDouble(ORDER_TP)-level)<TickSize()*0.5 && OrderGetDouble(ORDER_SL)==0 &&
          MathAbs(OrderGetDouble(ORDER_VOLUME_CURRENT)-TGE_MARKER_VOLUME)<1e-8;
}
bool SubmitTgeMobileMarker(const double price,const double target)
{
   if(!TgeMarkerCanRequest() || !markerStateOK || markerCreateAt!=0 || !ReconcileMobileMarkerDeletes()) return false;
   MqlTick q; double distance=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   if(!FreshQuote(q) || !ExactLot(TGE_MARKER_VOLUME) || q.bid-price<=MathMax(TGE_MARKER_DANGER,distance) ||
      q.ask-price<MathMax(distance,TickSize()) || target-price<MathMax(distance,TickSize()))
   { markerStatus="提交前报价/价格校验未通过"; return false; }
   // 先落盘唯一comment及意图；超时/断线/结果不明时，重启也不重复创建。
   markerCreateAt=-1;
   if(!TgeMarkerWrite("create",-1)) return false;
   GlobalVariablesFlush();
   long sequence=markerSequence+1; datetime now=TimeCurrent();
   if(!TgeMarkerWrite("sequence",(double)sequence) || !TgeMarkerWrite("create",(double)now)) return false;
   GlobalVariablesFlush(); markerSequence=sequence; markerCreateAt=now;
   markerTrade.BuyLimit(TGE_MARKER_VOLUME,price,_Symbol,0,target,ORDER_TIME_GTC,0,TgeMarkerCreationTag());
   uint code=markerTrade.ResultRetcode();
   PrintFormat("[手机TP标记] 创建请求 TP=%.2f ret=%u order=%I64u %s",target,code,markerTrade.ResultOrder(),markerTrade.ResultComment());
   if(ExplicitReject(code) || code==TRADE_RETCODE_INVALID_EXPIRATION || code==TRADE_RETCODE_INVALID_ORDER ||
      code==TRADE_RETCODE_LIMIT_ORDERS)
   {
      if(TgeMarkerWrite("create",0)) { markerCreateAt=0; GlobalVariablesFlush(); }
      markerStatus="挂单被拒绝："+markerTrade.ResultComment(); return false;
   }
   return ReconcileTgeMarkerCreation();
}
void SyncTgeMobileMarkers()
{
   ulong ms=GetTickCount64();
   if(!markerDirty && markerLastMs>0 && ms-markerLastMs<5000) return;
   markerLastMs=ms; markerDirty=false;
   if(!TgeMarkerCanRequest())
   {
      markerStatus=!tradeMode ? "观察模式不挂单" : markerLock==INVALID_HANDLE ? "等待标记实例锁" :
                   EA魔法号==(ulong)手机标记挂单Magic ? "标记Magic冲突" : "等待交易权限/状态";
      return;
   }
   bool createReady=ReconcileTgeMarkerCreation();
   double markerLevels[]; ArrayCopy(markerLevels,levels);
   // aiPlans/levels仅在完整快照校验成功后替换；执行暂停时仍展示最后一份已校验点位。
   if(读取AI即时策略 && aiMode=="SETUP")
      for(int i=0;i<ArraySize(aiPlans);i++)
      {
         bool exists=false;
         for(int j=0;j<ArraySize(markerLevels);j++) if(MathAbs(markerLevels[j]-aiPlans[i].level)<TickSize()*0.5) exists=true;
         if(!exists) { int n=ArraySize(markerLevels); ArrayResize(markerLevels,n+1); markerLevels[n]=aiPlans[i].level; }
      }
   // 手机标记属于展示，不使用策略入场的feedActive/有效期门槛。
   bool enabled=启用手机标记挂单 && uiMobileMarkers && ArraySize(markerLevels)>0;
   bool otherTrade=TgeMarkerHasOtherTrade();
   MqlTick q; bool fresh=FreshQuote(q);
   double price=TickSize()>0 ? NormalizeDouble(MathRound(手机标记挂单固定价格/TickSize())*TickSize(),_Digits) : 0;
   double stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   bool safe=StringFind(_Symbol,"XAUUSD")==0 && price>0 && ExactLot(TGE_MARKER_VOLUME) &&
             (SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE)&SYMBOL_ORDER_LIMIT)!=0 &&
             (SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE)&SYMBOL_EXPIRATION_GTC)!=0;
   if(!enabled || otherTrade || pending.kind!=0 || !safe || (fresh && q.bid-price<=MathMax(TGE_MARKER_DANGER,stops)))
   {
      CancelTgeMobileMarkers();
      bool retired=ReconcileMobileMarkerDeletes();
      markerStatus=markerUnexpectedPosition ? "标记意外成交，需人工核对" : !retired || !createReady ? "正在撤销/核对标记" : !启用手机标记挂单 || !uiMobileMarkers ? "手机TP开关已关闭" :
                   ArraySize(markerLevels)==0 ? "等待已校验点位" :
                   otherTrade ? "已有交易，标记已撤" : pending.kind!=0 ? "交易请求待确认" : "品种/价格/手数不适合标记";
      return;
   }
   if(!fresh) { markerStatus="等待新鲜报价，不创建标记"; return; }
   if(!createReady || !ReconcileMobileMarkerDeletes()) return;
   bool matched[]; ArrayResize(matched,ArraySize(markerLevels)); ArrayInitialize(matched,false);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || !IsMobileMarkerOrderSelected()) continue;
      int index=-1;
      for(int j=0;j<ArraySize(markerLevels);j++)
         if(!matched[j] && TgeMarkerMatches(NormalizeDouble(MathRound(markerLevels[j]/TickSize())*TickSize(),_Digits),price)) { index=j; break; }
      if(index<0) RequestMobileMarkerDelete(ticket); else matched[index]=true;
   }
   if(!ReconcileMobileMarkerDeletes()) { markerStatus="等待旧标记撤销确认"; return; }
   for(int i=0;i<ArraySize(markerLevels);i++)
   {
      if(matched[i]) continue;
      double target=NormalizeDouble(MathRound(markerLevels[i]/TickSize())*TickSize(),_Digits);
      if(target-price<MathMax(stops,TickSize()) || q.ask-price<MathMax(stops,TickSize()))
      { markerStatus="TP/挂单距离不符合券商规格"; return; }
      if(!SubmitTgeMobileMarker(price,target)) return;
   }
   int actual=0;
   for(int i=0;i<ArraySize(markerLevels);i++)
      for(int j=OrdersTotal()-1;j>=0;j--)
         if(OrderGetTicket(j)>0 && TgeMarkerMatches(NormalizeDouble(MathRound(markerLevels[i]/TickSize())*TickSize(),_Digits),price)) { actual++; break; }
   markerStatus=StringFormat("已同步%d/%d",actual,ArraySize(markerLevels));
}
void StopTgeMobileMarkers()
{
   CancelTgeMobileMarkers(); // 撤销意图由原模块持久化；卸载时不宣称已撤销。
   if(markerLock!=INVALID_HANDLE) { FileClose(markerLock); markerLock=INVALID_HANDLE; }
}
#endif
