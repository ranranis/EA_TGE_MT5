#ifndef TGE_TEACHER_LIMITS_MQH
#define TGE_TEACHER_LIMITS_MQH
// 仅T哥直接计划：固定0.02限价；不调用市价开仓，不从地图或学生生成委托。
const double TEACHER_LIMIT_LOTS=0.02;
struct TeacherLimitSlot
{
   int state,sign; // -1写入中断；1创建待对账；2服务器挂单；3撤单待确认
   ulong order;
   uint source;
   datetime at,retry;
   double level,sl,tp,first,be,finalTP;
};
TeacherLimitSlot teacherLimits[4];
string LimitTag(const uint source) { return "TGL"+IntegerToString((long)source); }
uint LimitSource(const int i)
{
   return Hash(aiPlans[i].origin+"|"+DoubleToString(aiPlans[i].level,_Digits)+"|"+IntegerToString(aiPlans[i].sign));
}
string LimitDoneKey(const uint source) { return "tlDone"+IntegerToString((long)source); }
bool SaveLimitSlot(const int i)
{
   string k="tl"+IntegerToString(i)+".";
   if(!Store(k+"state",-1)) return false;
   GlobalVariablesFlush();
   if(!Store(k+"order",(double)teacherLimits[i].order) || !Store(k+"source",(double)teacherLimits[i].source) ||
      !Store(k+"sign",teacherLimits[i].sign) || !Store(k+"at",(double)teacherLimits[i].at) ||
      !Store(k+"retry",(double)teacherLimits[i].retry) || !Store(k+"level",teacherLimits[i].level) ||
      !Store(k+"sl",teacherLimits[i].sl) || !Store(k+"tp",teacherLimits[i].tp) ||
      !Store(k+"first",teacherLimits[i].first) || !Store(k+"be",teacherLimits[i].be) ||
      !Store(k+"finalTP",teacherLimits[i].finalTP) || !Store(k+"state",teacherLimits[i].state)) return false;
   GlobalVariablesFlush(); return true;
}
void RestoreTeacherLimits()
{
   for(int i=0;i<4;i++)
   {
      string k="tl"+IntegerToString(i)+".";
      teacherLimits[i].state=(int)Load(k+"state"); teacherLimits[i].order=(ulong)Load(k+"order");
      teacherLimits[i].source=(uint)Load(k+"source"); teacherLimits[i].sign=(int)Load(k+"sign");
      teacherLimits[i].at=(datetime)Load(k+"at"); teacherLimits[i].retry=(datetime)Load(k+"retry");
      teacherLimits[i].level=Load(k+"level"); teacherLimits[i].sl=Load(k+"sl"); teacherLimits[i].tp=Load(k+"tp");
      teacherLimits[i].first=Load(k+"first"); teacherLimits[i].be=Load(k+"be"); teacherLimits[i].finalTP=Load(k+"finalTP");
      if(teacherLimits[i].state<0) { stateOK=false; reason="老师挂单状态写入中断，待核对"; }
   }
}
int LimitPlanIndex(const uint source)
{
   if(!AIChannelReady() || aiMode!="SETUP") return -1;
   for(int i=0;i<ArraySize(aiPlans);i++)
      if(!aiPlans[i].derived && LiveTeacherPlan(i) && LimitSource(i)==source) return i;
   return -1;
}
bool LimitEntryPending(const string comment)
{
   if(StringFind(comment,"TGL")!=0) return false;
   for(int i=0;i<4;i++)
      if(teacherLimits[i].state!=0 && LimitTag(teacherLimits[i].source)==comment) return true;
   return false;
}
bool BindLimitDeals(const int i,const double expected)
{
   if(!HistorySelect(teacherLimits[i].at-60,TimeCurrent()+1)) return false;
   double actual=0;
   for(int n=0;n<HistoryDealsTotal();n++)
   {
      ulong deal=HistoryDealGetTicket(n);
      if((ulong)HistoryDealGetInteger(deal,DEAL_ORDER)!=teacherLimits[i].order ||
         HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN ||
         (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=EA魔法号 ||
         HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
      ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(id==0) return false;
      string k=ExitKey(id);
      if(!Store(k+"ready",0) || !Store(k+"sl",teacherLimits[i].sl) ||
         !Store(k+"first",teacherLimits[i].first) || !Store(k+"be",teacherLimits[i].be) ||
         !Store(k+"tp",teacherLimits[i].finalTP) || !Store(k+"ready",1)) return false;
      actual+=HistoryDealGetDouble(deal,DEAL_VOLUME);
   }
   if(actual+1e-8<expected || actual<=0) return false;
   if(!Store(LimitDoneKey(teacherLimits[i].source),1)) return false;
   GlobalVariablesFlush(); return true;
}
bool ReconcileLimitSlot(const int i)
{
   if(teacherLimits[i].state==0) return true;
   if(teacherLimits[i].state<0) { stateOK=false; return false; }
   if(teacherLimits[i].order==0)
   {
      // 创建结果丢失/重启：按精确tag和发送时刻找回，不盲目补发。
      string tag=LimitTag(teacherLimits[i].source); ulong match=0;
      for(int n=OrdersTotal()-1;n>=0;n--)
      {
         ulong ticket=OrderGetTicket(n);
         if(ticket>0 && (ulong)OrderGetInteger(ORDER_MAGIC)==EA魔法号 && OrderGetString(ORDER_SYMBOL)==_Symbol &&
            OrderGetString(ORDER_COMMENT)==tag && OrderGetInteger(ORDER_TIME_SETUP)>=teacherLimits[i].at)
         { if(match>0 && match!=ticket) return false; match=ticket; }
      }
      if(HistorySelect(teacherLimits[i].at-60,TimeCurrent()+1))
         for(int n=HistoryOrdersTotal()-1;n>=0;n--)
         {
            ulong ticket=HistoryOrderGetTicket(n);
            if((ulong)HistoryOrderGetInteger(ticket,ORDER_MAGIC)==EA魔法号 &&
               HistoryOrderGetString(ticket,ORDER_SYMBOL)==_Symbol && HistoryOrderGetString(ticket,ORDER_COMMENT)==tag &&
               HistoryOrderGetInteger(ticket,ORDER_TIME_SETUP)>=teacherLimits[i].at)
            { if(match>0 && match!=ticket) return false; match=ticket; }
         }
      if(match==0) { reason="老师挂单结果未知，待服务器对账，不补发"; return false; }
      teacherLimits[i].order=match; if(!SaveLimitSlot(i)) return false;
   }
   if(OrderSelect(teacherLimits[i].order))
   {
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=EA魔法号 || OrderGetString(ORDER_SYMBOL)!=_Symbol ||
         OrderGetString(ORDER_COMMENT)!=LimitTag(teacherLimits[i].source) ||
         OrderGetInteger(ORDER_TYPE)!=(teacherLimits[i].sign>0 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT))
      { stateOK=false; reason="老师挂单归属不一致，停止请求"; return false; }
      if(teacherLimits[i].state==1) { teacherLimits[i].state=2; return SaveLimitSlot(i); }
      return true;
   }
   if(!HistoryOrderSelect(teacherLimits[i].order)) return false;
   long status=HistoryOrderGetInteger(teacherLimits[i].order,ORDER_STATE);
   if(status!=ORDER_STATE_FILLED && status!=ORDER_STATE_CANCELED && status!=ORDER_STATE_REJECTED && status!=ORDER_STATE_EXPIRED) return false;
   double filled=HistoryOrderGetDouble(teacherLimits[i].order,ORDER_VOLUME_INITIAL)-HistoryOrderGetDouble(teacherLimits[i].order,ORDER_VOLUME_CURRENT);
   if(status==ORDER_STATE_FILLED && filled<=0) return false;
   if(filled>0 && !BindLimitDeals(i,filled)) return false; // 包含部分成交后撤单
   DecisionLog("LIMIT_RECONCILED","挂单已按服务器终态及真实入场Deal对账",0,teacherLimits[i].order);
   ZeroMemory(teacherLimits[i]); return SaveLimitSlot(i);
}
bool LimitPrices(const int i,double &sl,double &tp)
{
   int sign=aiPlans[i].sign; double level=aiPlans[i].level;
   sl=aiPlans[i].sl>0 ? Align(aiPlans[i].sl,sign) : Align(level-sign*保险价格距离,sign);
   bool ok=true;
   if(aiPlans[i].tp>0) tp=Align(aiPlans[i].tp,-sign);
   else ok=Target(level,sign,tp,false,level);
   double minimum=MathMax((double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                          (double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point+TickSize();
   return ok && sign*(level-sl)>=minimum && sign*(tp-level)>=minimum &&
          (aiPlans[i].first==0 || (sign*(aiPlans[i].first-level)>0 && sign*(tp-aiPlans[i].first)>TickSize())) &&
          (aiPlans[i].breakeven==0 || (sign*(aiPlans[i].breakeven-level)>0 && sign*(tp-aiPlans[i].breakeven)>=0));
}
bool LimitParametersMatch(const int slot,const int plan)
{
   double sl=0,tp=0;
   return LimitPrices(plan,sl,tp) && MathAbs(sl-teacherLimits[slot].sl)<TickSize()*0.5 &&
          MathAbs(tp-teacherLimits[slot].tp)<TickSize()*0.5 &&
          aiPlans[plan].first==teacherLimits[slot].first && aiPlans[plan].breakeven==teacherLimits[slot].be;
}
bool LimitTooFar(const double level,const int sign,const MqlTick &q)
{
   // 使用当前可成交一侧报价；50表示黄金价格差50.00，不是50个_Point。
   return MathAbs(level-(sign>0 ? q.ask : q.bid))>挂单最大离价+1e-8;
}
void SyncTeacherLimits()
{
   bool settled=true;
   for(int i=0;i<4;i++) if(!ReconcileLimitSlot(i)) settled=false;
   if(!CanExecute() || pending.kind!=0) return;
   if(!settled) { reason="老师挂单尚在对账，暂停新增"; return; }
   MqlTick q;
   bool quoteOK=FreshQuote(q);
   // 超距以及来源取消、编辑、改价或通道失效：先撤本模块的未成交单，确认后才补新计划。
   for(int i=0;i<4;i++)
   {
      if(teacherLimits[i].state==0) continue;
      int plan=LimitPlanIndex(teacherLimits[i].source);
      bool tooFar=quoteOK && LimitTooFar(teacherLimits[i].level,teacherLimits[i].sign,q);
      if(teacherLimits[i].state==3 || plan<0 || !LimitParametersMatch(i,plan) || tooFar)
      {
         if(TimeCurrent()<teacherLimits[i].retry) return;
         teacherLimits[i].state=3; teacherLimits[i].retry=TimeCurrent()+5;
         if(!SaveLimitSlot(i)) return;
         reason=tooFar ? "老师挂单距现价超过"+DoubleToString(挂单最大离价,2)+"，撤单等待回近" : "老师挂单撤销待确认";
         if(plan>=0) aiPlans[plan].status=reason;
         DecisionLog("LIMIT_CANCEL",reason,0,teacherLimits[i].order);
         execution.OrderDelete(teacherLimits[i].order);
         PrintFormat("[T哥限价撤单] order=%I64u ret=%u 等待服务器确认",teacherLimits[i].order,execution.ResultRetcode());
         return;
      }
      aiPlans[plan].status="0.02手限价挂单 #"+IntegerToString((long)teacherLimits[i].order);
   }
   if(!AIChannelReady() || aiMode!="SETUP") { reason="等待T哥明确点位与方向："+aiReason; return; }
   reason="T哥限价计划在线，等待券商撮合；不追市价";
   if(!quoteOK || q.ask-q.bid>最大点差价格) { reason="行情/点差异常，不新增挂单"; return; }
   if(!ExactLot(TEACHER_LIMIT_LOTS)) { reason="券商不支持固定0.02手"; return; }
   if((SymbolInfoInteger(_Symbol,SYMBOL_ORDER_MODE)&SYMBOL_ORDER_LIMIT)==0) { reason="品种不支持限价挂单"; return; }
   int active=0,empty=-1;
   for(int j=0;j<4;j++) if(teacherLimits[j].state!=0) active++; else if(empty<0) empty=j;
   if(empty<0 || OwnCount()+active>=最大同时持仓) { reason="持仓加老师挂单已达上限"; return; }
   for(int i=0;i<ArraySize(aiPlans);i++)
   {
      if(aiPlans[i].derived || !LiveTeacherPlan(i)) continue;
      uint source=LimitSource(i); bool exists=false;
      for(int j=0;j<4;j++) if(teacherLimits[j].state!=0 && teacherLimits[j].source==source) exists=true;
      if(exists || Load("tlRetry"+IntegerToString((long)source))>TimeCurrent()) continue;
      if(Load(LimitDoneKey(source))>0) { aiPlans[i].status="本计划已成交，不重复挂单"; continue; }
      if(LimitTooFar(aiPlans[i].level,aiPlans[i].sign,q))
      {
         aiPlans[i].status="距现价超过"+DoubleToString(挂单最大离价,2)+"，暂不挂单";
         reason=aiPlans[i].status; continue;
      }
      double price=Align(aiPlans[i].level,aiPlans[i].sign),sl=0,tp=0;
      if(MathAbs(price-aiPlans[i].level)>TickSize()*0.1) { aiPlans[i].status="点位不符合报价精度，待核对"; continue; }
      double distance=MathMax((double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                              (double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point+TickSize();
      if((aiPlans[i].sign>0 ? q.ask-price : price-q.bid)<distance)
      { aiPlans[i].status="等待合法限价距离；不追市价、不改突破单"; continue; }
      if(!LimitPrices(i,sl,tp)) { aiPlans[i].status="SL/TP顺序或最小距离不合法"; continue; }
      double margin=0;
      if(!OrderCalcMargin(aiPlans[i].sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,TEACHER_LIMIT_LOTS,price,margin) ||
         margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) { aiPlans[i].status="保证金不足"; continue; }
      if(!CanExecute() || !FreshQuote(q) || q.ask-q.bid>最大点差价格 ||
         LimitTooFar(price,aiPlans[i].sign,q) ||
         (aiPlans[i].sign>0 ? q.ask-price : price-q.bid)<distance)
      { aiPlans[i].status="提交前报价/权限变化，等待"; return; }
      ZeroMemory(teacherLimits[empty]); teacherLimits[empty].state=1; teacherLimits[empty].source=source;
      teacherLimits[empty].at=TimeCurrent(); teacherLimits[empty].sign=aiPlans[i].sign; teacherLimits[empty].level=price;
      teacherLimits[empty].sl=sl; teacherLimits[empty].tp=tp; teacherLimits[empty].first=aiPlans[i].first;
      teacherLimits[empty].be=aiPlans[i].breakeven; teacherLimits[empty].finalTP=aiPlans[i].tp;
      if(!SaveLimitSlot(empty)) return;
      string tag=LimitTag(source);
      if(aiPlans[i].sign>0) execution.BuyLimit(TEACHER_LIMIT_LOTS,price,_Symbol,sl,tp,ORDER_TIME_GTC,0,tag);
      else execution.SellLimit(TEACHER_LIMIT_LOTS,price,_Symbol,sl,tp,ORDER_TIME_GTC,0,tag);
      teacherLimits[empty].order=execution.ResultOrder();
      uint code=execution.ResultRetcode();
      PrintFormat("[T哥限价请求] source=%u price=%.2f lots=0.02 order=%I64u ret=%u",source,price,teacherLimits[empty].order,code);
      if(teacherLimits[empty].order==0 && ExplicitReject(code))
      {
         ZeroMemory(teacherLimits[empty]);
         Store("tlRetry"+IntegerToString((long)source),(double)(TimeCurrent()+5));
      }
      SaveLimitSlot(empty); reason="0.02手限价请求已发送，等待服务器对账"; return; // 一次只发一笔，未知结果不重发
   }
}
#endif
