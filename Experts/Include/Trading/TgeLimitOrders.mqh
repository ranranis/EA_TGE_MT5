#ifndef TGE_LIMIT_ORDERS_MQH
#define TGE_LIMIT_ORDERS_MQH
// 仅T哥已校验方向 + 已收M5趋势使用提前入场；挂单成交仍由原Manage管理。
// 与100价手机TP标记隔离，采用策略Magic，和开仓/分批复用同一pending请求锁。
bool IsAILimitSelected()
{
   long type=OrderGetInteger(ORDER_TYPE);
   return OrderGetString(ORDER_SYMBOL)==_Symbol && (ulong)OrderGetInteger(ORDER_MAGIC)==EA魔法号 &&
          StringFind(OrderGetString(ORDER_COMMENT),"TGL")==0 &&
          (type==ORDER_TYPE_BUY_LIMIT || type==ORDER_TYPE_SELL_LIMIT);
}
int AILimitCount()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderGetTicket(i)>0 && IsAILimitSelected()) count++;
   return count;
}
string AILimitTag(const long source,const double level,const int sign)
{
   return "TGL"+IntegerToString(source)+"_"+IntegerToString((long)Hash(DoubleToString(level,_Digits)))+"_"+(sign>0 ? "B" : "S");
}
bool HasAILimit(const double level,const int sign)
{
   string tag=AILimitTag((long)Hash(aiIdentity),level,sign);
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderGetTicket(i)>0 && IsAILimitSelected() && OrderGetString(ORDER_COMMENT)==tag) return true;
   return false;
}
bool RefreshAITrend()
{
   aiTrend=0; aiTrendReady=false;
   MqlRates bars[]; double ma[],vol[];
   ArraySetAsSeries(bars,true); ArraySetAsSeries(ma,true);
   datetime current=iTime(_Symbol,PERIOD_M5,0);
   if(current<=0 || current>TimeTradeServer() || TimeTradeServer()-current>=300 ||
      CopyRates(_Symbol,PERIOD_M5,1,7,bars)!=7 || CopyBuffer(maHandle,0,1,7,ma)!=7 ||
      CopyBuffer(atrHandle,0,1,1,vol)!=1 || bars[0].time+300!=current) return false;
   if(!MathIsValidNumber(vol[0]) || vol[0]<=TickSize()) return false;
   int crossings=0;
   for(int i=0;i<7;i++)
   {
      if(!MathIsValidNumber(ma[i]) || ma[i]==EMPTY_VALUE || ma[i]<=0 ||
         !MathIsValidNumber(bars[i].close) || bars[i].close<=0) return false;
      if(i<6)
      {
         if(bars[i].time-bars[i+1].time!=300) return false;
         if((bars[i].close-ma[i])*(bars[i+1].close-ma[i+1])<0) crossings++;
      }
   }
   atr=vol[0]; aiTrendReady=true;
   if(crossings<3)
   {
      if(bars[0].close>ma[0] && ma[0]-ma[1]>=TickSize()) aiTrend=1;
      if(bars[0].close<ma[0] && ma[1]-ma[0]>=TickSize()) aiTrend=-1;
   }
   return true;
}
bool AIAdvanceReady()
{
   return 启用趋势提前挂单 && 读取AI即时策略 && feedActive && aiReady && aiMode=="SETUP" &&
          aiGenerated<=TimeGMT()+5 && TimeGMT()-aiGenerated<=10 && aiTrendReady;
}
bool AITrendEntry(Candidate &out)
{
   if(!AIAdvanceReady() || aiTrend==0 || AILimitCount()>0) return false;
   MqlTick q;
   if(!FreshQuote(q) || q.ask-q.bid>最大点差价格) return false;
   datetime minute=iTime(_Symbol,PERIOD_M1,1);
   if(minute<=0 || minute+60>TimeTradeServer() || TimeTradeServer()-minute>=120) return false;
   for(int i=0;i<ArraySize(aiPlans);i++)
   {
      int sign=aiPlans[i].sign; double level=aiPlans[i].level;
      if(aiPlans[i].market || sign!=aiTrend || Load(AIVisitKey(level,sign))>0) continue;
      double entry=sign>0 ? q.ask : q.bid,tp;
      if(MathAbs(entry-level)>点位提前容差 || !Target(entry,sign,tp)) continue;
      out.valid=true; out.ai=true; out.direction=sign; out.level=level; out.bar=minute;
      out.method="T哥顺趋势提前入场["+aiSource+"]";
      entryView.ready=true; entryView.direction=sign; entryView.level=level;
      entryView.bar=minute; entryView.distance=MathAbs(entry-level); entryView.method=out.method;
      reason=out.method; return true;
   }
   return false;
}
bool ReconcileAILimitCreation()
{
   if(pending.kind!=4) return false;
   string tag=EntryTag();
   if(pending.order==0)
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         ulong ticket=OrderGetTicket(i);
         if(ticket>0 && IsAILimitSelected() && OrderGetString(ORDER_COMMENT)==tag)
         { pending.order=ticket; SavePending(); break; }
      }
   if(pending.order>0 && OrderSelect(pending.order) && IsAILimitSelected() &&
      OrderGetString(ORDER_COMMENT)==tag &&
      OrderGetInteger(ORDER_TYPE)==(pending.direction>0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT) &&
      MathAbs(OrderGetDouble(ORDER_PRICE_OPEN)-Align(pending.level+pending.direction*点位提前容差,-pending.direction))<TickSize()*0.5 &&
      MathAbs(OrderGetDouble(ORDER_SL)-pending.sl)<TickSize()*0.5 &&
      MathAbs(OrderGetDouble(ORDER_TP)-pending.tp)<TickSize()*0.5 &&
      OrderGetDouble(ORDER_VOLUME_CURRENT)>0 &&
      OrderGetDouble(ORDER_VOLUME_CURRENT)<=pending.volume+1e-8)
   {
      DecisionLog("LIMIT_CONFIRMED","服务器限价单已可读；不代表成交");
      ClearPending(); reason="趋势限价单已确认，等待成交"; return true;
   }
   return false;
}
bool AILimitStillValid()
{
   if(!AIAdvanceReady()) return false;
   int sign=OrderGetInteger(ORDER_TYPE)==ORDER_TYPE_BUY_LIMIT ? 1 : -1;
   if(aiTrend!=0 && aiTrend!=sign) return false;
   string tag=OrderGetString(ORDER_COMMENT);
   double price=OrderGetDouble(ORDER_PRICE_OPEN);
   for(int i=0;i<ArraySize(aiPlans);i++)
   {
      if(aiPlans[i].market || aiPlans[i].sign!=sign) continue;
      if(tag!=AILimitTag((long)Hash(aiIdentity),aiPlans[i].level,sign)) continue;
      double wanted=Align(aiPlans[i].level+sign*点位提前容差,-sign);
      if(MathAbs(price-wanted)<TickSize()*0.5) return true;
   }
   return false;
}
void SyncAILimits()
{
   if(!CanExecute() || pending.kind!=0) return;
   // 无效旧单先撤并读回终态/实际Deal，才能按新参考发出订单。
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || !IsAILimitSelected() || AILimitStillValid()) continue;
      string retry="lc"+IntegerToString((long)ticket);
      if(TimeCurrent()-(datetime)Load(retry)<10) return;
      Store(retry,(double)TimeCurrent());
      ZeroMemory(pending); pending.kind=5; pending.order=ticket; pending.at=TimeCurrent();
      SavePending(); if(!CanExecute()) return;
      DecisionLog("LIMIT_CANCEL_INTENT","来源/趋势/配置变化，申请撤销旧策略挂单");
      execution.OrderDelete(ticket); RecordResult(); return;
   }
}
bool SubmitAILimit(const int sign,const double level)
{
   if(!AIAdvanceReady() || aiTrend!=sign || !CanExecute() || ExecutionBlock()!="" ||
      AILimitCount()>0 || HasAILimit(level,sign) || Load(AIVisitKey(level,sign))>0) return false;
   if((SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE)&SYMBOL_ORDER_LIMIT)==0 ||
      (SymbolInfoInteger(_Symbol,SYMBOL_EXPIRATION_MODE)&SYMBOL_EXPIRATION_GTC)==0) return false;
   MqlTick q;
   if(!FreshQuote(q) || q.ask-q.bid>最大点差价格 || !ExactLot(每次开仓手数)) return false;
   double price=Align(level+sign*点位提前容差,-sign);
   double distance=MathMax((double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                           (double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point+TickSize();
   double gap=sign*((sign>0 ? q.ask : q.bid)-price);
   double sl=Align(price-sign*保险价格距离,sign),tp;
   if(gap<distance || gap>保险价格距离*2 || !Target(price,sign,tp) ||
      sign*(price-sl)<distance || sign*(tp-price)<distance) return false;
   double margin=0;
   ENUM_ORDER_TYPE type=sign>0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   if(!OrderCalcMargin(type,_Symbol,每次开仓手数,price,margin) ||
      margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) return false;
   // 先消费来源/方向机会并持久化意图；超时、重启、未知结果均不能重复创建。
   Store(AIVisitKey(level,sign),(double)TimeCurrent());
   ZeroMemory(pending); pending.kind=4; pending.at=TimeCurrent(); pending.bar=pending.at;
   pending.sourceHash=(long)Hash(aiIdentity); pending.level=level; pending.direction=sign;
   pending.volume=每次开仓手数; pending.sl=sl; pending.tp=tp;
   SavePending(); if(!CanExecute()) return false;
   DecisionLog("LIMIT_INTENT","顺趋势提前限价["+aiSource+"]");
   // MT5挂单使用RETURN填充；市场开仓仍沿用原品种填充配置。
   execution.SetTypeFilling(ORDER_FILLING_RETURN);
   if(sign>0) execution.BuyLimit(每次开仓手数,price,_Symbol,sl,tp,ORDER_TIME_GTC,0,EntryTag());
   else execution.SellLimit(每次开仓手数,price,_Symbol,sl,tp,ORDER_TIME_GTC,0,EntryTag());
   execution.SetTypeFillingBySymbol(_Symbol); RecordResult(); return true;
}
void PrepareAILimit()
{
   if(!AIAdvanceReady() || aiTrend==0 || pending.kind!=0 || AILimitCount()>0) return;
   for(int i=0;i<ArraySize(aiPlans);i++)
      if(!aiPlans[i].market && aiPlans[i].sign==aiTrend && SubmitAILimit(aiTrend,aiPlans[i].level)) return;
}
#endif
