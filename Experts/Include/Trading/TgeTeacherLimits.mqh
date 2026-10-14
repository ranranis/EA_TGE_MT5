#ifndef TGE_TEACHER_LIMITS_MQH
#define TGE_TEACHER_LIMITS_MQH
// v1.42只迁移旧TGL挂单：撤单、成交绑定、终态对账，不新增挂单。
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
   MergeOpportunity(teacherLimits[i].sign,teacherLimits[i].level);
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
bool LegacyLimitsClear()
{
   for(int i=0;i<4;i++) if(teacherLimits[i].state!=0) return false;
   // 防止状态文件缺失时忽略服务器旧挂单；只阻塞，绝不认领其他EA/手机标记。
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderGetTicket(i)>0 && (ulong)OrderGetInteger(ORDER_MAGIC)==EA魔法号 && OrderGetString(ORDER_SYMBOL)==_Symbol &&
         StringFind(OrderGetString(ORDER_COMMENT),"TGL")==0) return false;
   return true;
}
void SyncTeacherLimits()
{
   bool settled=true;
   for(int i=0;i<4;i++) if(!ReconcileLimitSlot(i)) settled=false;
   if(!CanExecute() || pending.kind!=0 || !settled) return;
   for(int i=0;i<4;i++)
   {
      if(teacherLimits[i].state==0 || TimeCurrent()<teacherLimits[i].retry) continue;
      teacherLimits[i].state=3; teacherLimits[i].retry=TimeCurrent()+5;
      if(!SaveLimitSlot(i)) return;
      reason="升级触价模式：旧策略挂单撤销待服务器确认";
      DecisionLog("LIMIT_CANCEL",reason,0,teacherLimits[i].order);
      execution.OrderDelete(teacherLimits[i].order); return;
   }
   if(!LegacyLimitsClear()) reason="发现未认领的旧TGL挂单，核对后才允许新入场";
}
#endif
