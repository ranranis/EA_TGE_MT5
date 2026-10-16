// 非显示辅助指标：指标线程请求历史报价立即返回，不在EA线程等待下载。
#property strict
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots 0
input long FromMSC=0;
input long UntilMSC=0;
input long OpenedMSC=0;
input double EntryPrice=0;
input int Side=1;
input bool RequireEnd=false;
double StateBuffer[],TimeBuffer[],ExitBuffer[],MfeBuffer[],MaeBuffer[],ReasonBuffer[];
double historyState=0,historyTime=0,historyExit=0,historyMfe=0,historyMae=0,historyReason=0;
datetime historyRetry=0;
int OnInit()
{
   if(FromMSC<=0 || UntilMSC<FromMSC || OpenedMSC<=0 || EntryPrice<=0 || (Side!=1 && Side!=-1))
      return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,StateBuffer,INDICATOR_DATA); ArraySetAsSeries(StateBuffer,true);
   SetIndexBuffer(1,TimeBuffer,INDICATOR_DATA); ArraySetAsSeries(TimeBuffer,true);
   SetIndexBuffer(2,ExitBuffer,INDICATOR_DATA); ArraySetAsSeries(ExitBuffer,true);
   SetIndexBuffer(3,MfeBuffer,INDICATOR_DATA); ArraySetAsSeries(MfeBuffer,true);
   SetIndexBuffer(4,MaeBuffer,INDICATOR_DATA); ArraySetAsSeries(MaeBuffer,true);
   SetIndexBuffer(5,ReasonBuffer,INDICATOR_DATA); ArraySetAsSeries(ReasonBuffer,true);
   IndicatorSetString(INDICATOR_SHORTNAME,"TGE simulation history worker");
   return INIT_SUCCEEDED;
}
void HistoryScan()
{
   if(historyState!=0 || TimeGMT()<historyRetry) return;
   historyRetry=TimeGMT()+1;
   MqlTick ticks[]; ResetLastError();
   int count=CopyTicksRange(_Symbol,ticks,COPY_TICKS_ALL,(ulong)FromMSC,(ulong)UntilMSC);
   if(count<0 || GetLastError()!=0 ||
      (FromMSC==OpenedMSC && (count==0 || ticks[0].time_msc!=OpenedMSC)) ||
      (RequireEnd && (count==0 || ticks[count-1].time_msc!=UntilMSC))) return;
   for(int j=0;j<count;j++)
   {
      MqlTick q=ticks[j];
      if(q.time_msc<FromMSC || q.time_msc>UntilMSC || q.bid<=0 || q.ask<q.bid ||
         (j>0 && q.time_msc<ticks[j-1].time_msc)) return;
   }
   for(int j=0;j<count;j++)
   {
      MqlTick q=ticks[j];
      if(q.time_msc<=OpenedMSC) continue;
      double mark=Side>0 ? q.bid : q.ask,delta=Side*(mark-EntryPrice);
      historyMfe=MathMax(historyMfe,delta); historyMae=MathMin(historyMae,delta);
      int why=delta<=-10 ? 1 : delta>=5 ? 2 : q.time_msc-OpenedMSC>=3600000 ? 3 : 0;
      if(why==0) continue;
      historyTime=(double)q.time_msc;
      historyExit=why==2 ? EntryPrice+Side*5 : mark;
      historyReason=why; historyState=2; return;
   }
   historyState=1;
}
int OnCalculate(const int rates_total,const int prev_calculated,const int begin,const double &price[])
{
   if(rates_total<=0) return 0;
   HistoryScan();
   StateBuffer[0]=historyState; TimeBuffer[0]=historyTime; ExitBuffer[0]=historyExit;
   MfeBuffer[0]=historyMfe; MaeBuffer[0]=historyMae; ReasonBuffer[0]=historyReason;
   return rates_total;
}
