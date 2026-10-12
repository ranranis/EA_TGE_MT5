#ifndef SMA_TRADING_MOBILE_MARKER_SAFETY_MQH
#define SMA_TRADING_MOBILE_MARKER_SAFETY_MQH

// Ticket stays in the key (not a double), so outstanding cancellations survive restart.
ulong mobileMarkerDeleteTickets[];
bool mobileMarkerDeleteTrackingLoaded=false;

string MobileMarkerDeletePrefix()
{
   return StringFormat("S55.MD.%I64d.%I64d.%s.",AccountInfoInteger(ACCOUNT_LOGIN),手机标记挂单Magic,_Symbol);
}

bool LoadMobileMarkerDeleteTracking()
{
   if(mobileMarkerDeleteTrackingLoaded) return true;
   ArrayResize(mobileMarkerDeleteTickets,0);
   string deletePrefix=MobileMarkerDeletePrefix();
   for(int i=0;i<GlobalVariablesTotal();i++)
   {
      string key=GlobalVariableName(i);
      if(StringFind(key,deletePrefix)!=0) continue;
      ulong ticket=(ulong)StringToInteger(StringSubstr(key,StringLen(deletePrefix)));
      if(ticket==0) continue;
      int n=ArraySize(mobileMarkerDeleteTickets);
      if(ArrayResize(mobileMarkerDeleteTickets,n+1,32)!=n+1) return false;
      mobileMarkerDeleteTickets[n]=ticket;
   }
   mobileMarkerDeleteTrackingLoaded=true;
   return true;
}

bool RequestMobileMarkerDelete(ulong ticket)
{
   if(!LoadMobileMarkerDeleteTracking() || !OrderSelect(ticket) || !IsMobileMarkerOrderSelected()) return false;
   string key=MobileMarkerDeletePrefix()+(string)ticket;
   datetime now=TimeCurrent();
   if(now<=0) return false;
   bool tracked=false;
   for(int i=0;i<ArraySize(mobileMarkerDeleteTickets);i++)
      if(mobileMarkerDeleteTickets[i]==ticket) { tracked=true; break; }
   if(!tracked)
   {
      int n=ArraySize(mobileMarkerDeleteTickets);
      if(ArrayResize(mobileMarkerDeleteTickets,n+1,32)!=n+1) return false;
      mobileMarkerDeleteTickets[n]=ticket;
   }
   if(!GlobalVariableCheck(key))
   {
      if(GlobalVariableSet(key,0.0)==0) return false;
   }
   datetime last=(datetime)GlobalVariableGet(key);
   if(last>0 && now>=last && now-last<5) return false;
   if(GlobalVariableSet(key,(double)now)==0) return false;
   ResetLastError();
   GlobalVariablesFlush(); // Persist intent before every server request, including retries.
   if(GetLastError()!=0) return false;
   bool sent=markerTrade.OrderDelete(ticket);
   uint retcode=markerTrade.ResultRetcode();
   bool accepted=sent && IsTradeRetcodeAccepted(retcode);
   if(!accepted)
   {
      老师点位最近错误码=retcode;
      老师点位最近错误=markerTrade.ResultComment();
      PrintRateLimited("marker_delete:"+(string)ticket,10,
                       StringFormat("[手机标记] 撤单未确认 ticket=%I64u ret=%u %s",ticket,retcode,markerTrade.ResultComment()));
   }
   return accepted; // Acceptance does not remove the tracking record.
}

bool MobileMarkerOrderRetired(ulong ticket)
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || OrderSelect(ticket) || !HistoryOrderSelect(ticket)) return false;
   if(HistoryOrderGetString(ticket,ORDER_SYMBOL)!=_Symbol ||
      HistoryOrderGetInteger(ticket,ORDER_MAGIC)!=手机标记挂单Magic ||
      !IsMobileMarkerTag(HistoryOrderGetString(ticket,ORDER_COMMENT))) return false;
   ENUM_ORDER_STATE status=(ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket,ORDER_STATE);
   bool canceled=(status==ORDER_STATE_CANCELED || status==ORDER_STATE_EXPIRED || status==ORDER_STATE_REJECTED);
   if(!canceled && status!=ORDER_STATE_FILLED) return false;
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double initial=HistoryOrderGetDouble(ticket,ORDER_VOLUME_INITIAL);
   double remaining=HistoryOrderGetDouble(ticket,ORDER_VOLUME_CURRENT);
   if(step<=0.0 || initial<=0.0) return false;
   if(canceled && MathAbs(initial-remaining)<=step*0.5) return true;
   // Cancellation raced a fill: keep replacement blocked until that position is closed.
   ulong id=(ulong)HistoryOrderGetInteger(ticket,ORDER_POSITION_ID);
   if(id==0 || FindOpenPositionTicketByIdentifier(id)>0 || !HistorySelectByPosition(id)) return false;
   double entered=0.0,exited=0.0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol ||
         (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=id) return false;
      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_INOUT) return false;
      if(entry==DEAL_ENTRY_IN) entered+=HistoryDealGetDouble(deal,DEAL_VOLUME);
      else if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY) exited+=HistoryDealGetDouble(deal,DEAL_VOLUME);
   }
   return entered>0.0 && MathAbs(entered-exited)<=step*0.5 &&
          entered+step*0.5>=initial-remaining;
}

bool ReconcileMobileMarkerDeletes()
{
   if(!LoadMobileMarkerDeleteTracking()) return false;
   if(ArraySize(mobileMarkerDeleteTickets)==0) return TerminalInfoInteger(TERMINAL_CONNECTED)!=0;
   // History reconciliation is not a tick-price protection task. CloseMobileMarkerPositions
   // still runs on every enabled management pass, independently of this one-second poll.
   static ulong lastCheckMs=0;
   ulong nowMs=GetTickCount64();
   if(lastCheckMs>0 && nowMs-lastCheckMs<1000) return false;
   lastCheckMs=nowMs;
   for(int i=ArraySize(mobileMarkerDeleteTickets)-1;i>=0;i--)
   {
      ulong ticket=mobileMarkerDeleteTickets[i];
      if(OrderSelect(ticket)) { RequestMobileMarkerDelete(ticket); continue; }
      if(!MobileMarkerOrderRetired(ticket)) continue;
      string key=MobileMarkerDeletePrefix()+(string)ticket;
      if(GlobalVariableCheck(key) && !GlobalVariableDel(key)) continue;
      int last=ArraySize(mobileMarkerDeleteTickets)-1;
      mobileMarkerDeleteTickets[i]=mobileMarkerDeleteTickets[last];
      ArrayResize(mobileMarkerDeleteTickets,last);
   }
   return ArraySize(mobileMarkerDeleteTickets)==0 && TerminalInfoInteger(TERMINAL_CONNECTED)!=0;
}

#endif
