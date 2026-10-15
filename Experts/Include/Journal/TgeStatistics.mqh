// 从交易托管系统迁移完整持仓统计口径；仅使用服务器历史，不依赖旧EA的CSV。
// 统计时间为券商服务器日期，所有页面共享同一批完整平仓记录。
struct TgeStatsTrade
{
   ulong id,lastDeal;
   datetime openTime,closeTime;
   long magic;
   int direction,entryDeals,exitDeals,exitReason;
   bool mixed,reversed;
   double entryVolume,exitVolume,entryValue,exitValue;
   double gross,commission,swap,fee,net;
};
struct TgeStatsSummary
{
   int trades,wins,losses,breakevens,exitDeals,buyTrades,sellTrades;
   int lossStreak,maxLossStreak,winningHolds,losingHolds;
   double net,volume,gains,lossesMoney,avgWin,avgLoss,pf,payoff,best,worst;
   double commission,swap,fee,buyNet,sellNet,holdMinutes,maxHold,winningMinutes,losingMinutes;
   double peak,maxDrawdown;
};
TgeStatsTrade statsTrades[];
TgeStatsSummary statsSummary;
bool statsDirty=true,statsOK=false;
datetime statsRangeStart=0,statsRangeEnd=0;
ulong statsLastAttempt=0;
int statsSkipped=0;
string statsStatus="等待加载成交历史";

datetime StatsMonth(const datetime date,const int offset)
{
   MqlDateTime dt; TimeToStruct(date,dt);
   int months=dt.year*12+dt.mon-1+offset;
   dt.year=months/12; dt.mon=months%12+1; dt.day=1; dt.hour=0; dt.min=0; dt.sec=0;
   return StructToTime(dt);
}
void StatsRange(datetime &start,datetime &end)
{
   MqlDateTime dt; TimeToStruct(TimeTradeServer(),dt);
   dt.hour=0; dt.min=0; dt.sec=0;
   start=StructToTime(dt);
   if(statsPeriod==0) { start+=statsOffsets[0]*86400; end=start+86400; }
   else if(statsPeriod==1)
   {
      start-=((dt.day_of_week+6)%7)*86400;
      start+=statsOffsets[1]*7*86400; end=start+7*86400;
   }
   else { start=StatsMonth(start,statsOffsets[2]); end=StatsMonth(start,1); }
}
bool StatsPositionOpen(const ulong id)
{
   // ticket可能更换，始终按POSITION_IDENTIFIER认领。
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetTicket(i)>0 && PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_IDENTIFIER)==id) return true;
   return false;
}
// 1=完整且范围匹配；0=尚未完整平仓/不属于筛选；-1=无法可靠分段；-2=查询失败。
int StatsReadTrade(const ulong id,const datetime start,const datetime end,TgeStatsTrade &tr)
{
   ZeroMemory(tr); tr.id=id; tr.exitReason=-1;
   if(StatsPositionOpen(id)) return 0;
   if(!HistorySelectByPosition(id)) return -2;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=id ||
         HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
      long type=HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;
      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY),magic=HistoryDealGetInteger(deal,DEAL_MAGIC);
      datetime at=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      double volume=HistoryDealGetDouble(deal,DEAL_VOLUME),price=HistoryDealGetDouble(deal,DEAL_PRICE);
      tr.gross+=HistoryDealGetDouble(deal,DEAL_PROFIT);
      tr.commission+=HistoryDealGetDouble(deal,DEAL_COMMISSION);
      tr.swap+=HistoryDealGetDouble(deal,DEAL_SWAP);
      tr.fee+=HistoryDealGetDouble(deal,DEAL_FEE);
      if(entry==DEAL_ENTRY_IN)
      {
         if(tr.entryDeals>0 && tr.magic!=magic) tr.mixed=true;
         int direction=type==DEAL_TYPE_BUY ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
         if(tr.entryDeals>0 && tr.direction!=direction) tr.reversed=true;
         if(tr.openTime==0 || at<tr.openTime)
         {
            tr.openTime=at; tr.magic=magic; tr.direction=direction;
         }
         tr.entryDeals++; tr.entryVolume+=volume; tr.entryValue+=volume*price;
      }
      else if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
      {
         tr.exitDeals++; tr.exitVolume+=volume; tr.exitValue+=volume*price;
         if(at>tr.closeTime || (at==tr.closeTime && deal>tr.lastDeal)) { tr.closeTime=at; tr.lastDeal=deal; tr.exitReason=(int)HistoryDealGetInteger(deal,DEAL_REASON); }
      }
      else if(entry==DEAL_ENTRY_INOUT) tr.reversed=true;
   }
   // 入场Magic定归属，退出Magic=0的手机/人工平仓仍计入同一生命周期。
   if(statsFilter==0 && (ulong)tr.magic!=EA魔法号) return 0;
   if(statsFilter==1 && tr.magic!=0) return 0;
   if(tr.reversed || (tr.mixed && statsFilter!=2)) return -1;
   if(tr.closeTime<start || tr.closeTime>=end) return 0;
   double tolerance=MathMax(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)*0.001,1e-8);
   if(tr.entryVolume<=0 || tr.exitVolume<=0 || MathAbs(tr.entryVolume-tr.exitVolume)>tolerance) return -1;
   tr.net=tr.gross+tr.commission+tr.swap+tr.fee;
   return 1;
}
void StatsAccumulate(const TgeStatsTrade &tr,TgeStatsSummary &st)
{
   st.trades++; st.net+=tr.net; st.volume+=tr.entryVolume; st.exitDeals+=tr.exitDeals;
   st.commission+=tr.commission; st.swap+=tr.swap; st.fee+=tr.fee;
   double held=MathMax((double)(tr.closeTime-tr.openTime)/60.0,0);
   st.holdMinutes+=held; st.maxHold=MathMax(st.maxHold,held);
   if(tr.direction==POSITION_TYPE_BUY) { st.buyTrades++; st.buyNet+=tr.net; }
   else { st.sellTrades++; st.sellNet+=tr.net; }
   if(st.trades==1 || tr.net>st.best) st.best=tr.net;
   if(st.trades==1 || tr.net<st.worst) st.worst=tr.net;
   if(tr.net>0.005)
   {
      st.wins++; st.gains+=tr.net; st.lossStreak=0;
      st.winningHolds++; st.winningMinutes+=held;
   }
   else if(tr.net< -0.005)
   {
      st.losses++; st.lossesMoney+=tr.net; st.lossStreak++;
      st.maxLossStreak=MathMax(st.maxLossStreak,st.lossStreak);
      st.losingHolds++; st.losingMinutes+=held;
   }
   else { st.breakevens++; st.lossStreak=0; }
   // 初始峰值为0，第一笔亏损也必须产生回撤；不计入未平仓浮盈。
   st.peak=MathMax(st.peak,st.net); st.maxDrawdown=MathMax(st.maxDrawdown,st.peak-st.net);
   st.avgWin=st.wins>0 ? st.gains/st.wins : 0;
   st.avgLoss=st.losses>0 ? st.lossesMoney/st.losses : 0;
   st.pf=st.lossesMoney<0 ? st.gains/MathAbs(st.lossesMoney) : 0;
   st.payoff=st.avgLoss<0 ? st.avgWin/MathAbs(st.avgLoss) : 0;
}
void StatsRefresh()
{
   datetime start,end; StatsRange(start,end);
   ulong now=GetTickCount64();
   bool rangeChanged=start!=statsRangeStart || end!=statsRangeEnd;
   if(!rangeChanged && statsLastAttempt>0 && now-statsLastAttempt<(ulong)(statsDirty ? 1000 : 30000)) return;
   statsLastAttempt=now; statsRangeStart=start; statsRangeEnd=end; statsDirty=false;
   statsOK=false; statsSkipped=0;
   ArrayResize(statsTrades,0); ZeroMemory(statsSummary);
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { statsStatus="终端离线，统计暂不可核对"; return; }
   if(start>TimeTradeServer()) { statsOK=true; statsStatus="所选区间尚未开始"; return; }
   if(!HistorySelect(start,(datetime)MathMin(end,TimeTradeServer())))
   { statsStatus="历史查询失败："+IntegerToString(GetLastError()); return; }
   // 先保存候选ID；HistorySelectByPosition会替换全局历史列表，不能在原列表里嵌套查询。
   ulong ids[]; int count=0,total=HistoryDealsTotal(); ArrayResize(ids,total);
   for(int i=0;i<total;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
      long type=HistoryDealGetInteger(deal,DEAL_TYPE),entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
      datetime at=(datetime)HistoryDealGetInteger(deal,DEAL_TIME);
      if((type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) || at<start || at>=end ||
         (entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY && entry!=DEAL_ENTRY_INOUT)) continue;
      ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(id>0) ids[count++]=id;
   }
   ArrayResize(ids,count); ArraySort(ids);
   ArrayResize(statsTrades,count); int included=0;
   for(int i=0;i<count;i++)
   {
      if(i>0 && ids[i]==ids[i-1]) continue;
      TgeStatsTrade tr; int result=StatsReadTrade(ids[i],start,end,tr);
      if(result== -2) { ArrayResize(statsTrades,0); statsStatus="持仓历史查询失败，未显示不完整统计"; return; }
      if(result== -1) { statsSkipped++; continue; }
      if(result==1) statsTrades[included++]=tr;
   }
   ArrayResize(statsTrades,included);
   // 与原统计页一致按完整平仓时刻累加；同秒成交以Deal号固定顺序。
   for(int i=1;i<included;i++)
   {
      TgeStatsTrade key=statsTrades[i]; int j=i-1;
      while(j>=0 && (statsTrades[j].closeTime>key.closeTime ||
            (statsTrades[j].closeTime==key.closeTime && statsTrades[j].lastDeal>key.lastDeal)))
      { statsTrades[j+1]=statsTrades[j]; j--; }
      statsTrades[j+1]=key;
   }
   for(int i=0;i<included;i++) StatsAccumulate(statsTrades[i],statsSummary);
   statsReview=MathMax(0,MathMin(statsReview,MathMax(included-1,0)));
   statsOK=true; statsDirty=false; statsStatus=included>0 ? "按完整平仓统计 · 含逐笔佣金/隔夜费/费用" : "此区间没有符合筛选的完整平仓记录";
}

string StatsMoney(const double value)
{
   return (value>0.005 ? "+" : "")+DoubleToString(MathAbs(value)<0.005 ? 0 : value,2);
}
color StatsInk(const double value) { return value>0.005 ? UI_GAIN : value< -0.005 ? UI_LOSS : UI_MUTED; }

// 选择只属于视图，以持仓ID跨刷新保持，不能让新增成交把索引指向另一笔。
ulong statsSelectedId=0,statsPressedId=0;
double statsCumulative[],statsDrawdowns[];
int StatsSelectedIndex()
{
   for(int i=0;i<ArraySize(statsTrades);i++) if(statsTrades[i].id==statsSelectedId) return i;
   return -1;
}
void StatsSelect(const int index)
{
   if(index<0 || index>=ArraySize(statsTrades)) return;
   statsSelectedId=statsTrades[index].id;
   statsReview=ArraySize(statsTrades)-1-index;
}
void StatsBuildSeries()
{
   int n=ArraySize(statsTrades);
   ArrayResize(statsCumulative,n); ArrayResize(statsDrawdowns,n);
   double total=0,peak=0;
   for(int i=0;i<n;i++)
   {
      total+=statsTrades[i].net; peak=MathMax(peak,total);
      statsCumulative[i]=total; statsDrawdowns[i]=total-peak;
   }
   int selected=StatsSelectedIndex();
   if(n==0) { statsSelectedId=0; statsReview=0; }
   else StatsSelect(selected<0 ? n-1 : selected);
}
int StatsExtremeIndex(const bool best)
{
   int found=-1;
   for(int i=0;i<ArraySize(statsTrades);i++)
      if(found<0 || (best ? statsTrades[i].net>statsTrades[found].net : statsTrades[i].net<statsTrades[found].net)) found=i;
   return found;
}
int StatsPointX(const int index,const int count)
{
   return 82+(int)MathRound((index+1.0)*442/(count+1.0));
}
int StatsPointAtX(const double x,const int count)
{
   if(count<1) return -1;
   return MathMax(0,MathMin(count-1,(int)MathRound((x-82)*(count+1.0)/442)-1));
}
void StatsHit(const int x,const int y,const int w,const int h,const int action)
{
   int n=ArraySize(uiHits); ArrayResize(uiHits,n+1);
   uiHits[n].x=x; uiHits[n].y=y; uiHits[n].w=w; uiHits[n].h=h; uiHits[n].action=action;
}
void StatsAction(const int action)
{
   if(!statsOK || ArraySize(statsTrades)==0) return;
   if(action>=1000)
   {
      int index=action-1000;
      if(index>=ArraySize(statsTrades) || statsTrades[index].id!=statsPressedId) return;
      StatsSelect(index); statsPressedId=0;
   }
   else if(action==111) { if(StatsSelectedIndex()>=0) statsDetail=3; }
   else if(action==112) statsDetail=2;
   else if(action==113 || action==114)
   {
      StatsSelect(StatsExtremeIndex(action==113)); statsDetail=3;
   }
   else if(action==43 || action==44)
   {
      int index=StatsSelectedIndex();
      StatsSelect(MathMax(0,MathMin(ArraySize(statsTrades)-1,index+(action==43 ? -1 : 1))));
   }
}
string StatsDuration(const double minutes)
{
   if(minutes<1) return IntegerToString((int)MathRound(minutes*60))+"秒";
   if(minutes<60) return DoubleToString(minutes,1)+"分钟";
   return IntegerToString((int)(minutes/60))+"小时"+IntegerToString((int)MathMod(minutes,60))+"分";
}
string StatsExitText(const int value)
{
   if(value==DEAL_REASON_SL) return "止损 SL";
   if(value==DEAL_REASON_TP) return "止盈 TP";
   if(value==DEAL_REASON_SO) return "强制平仓";
   if(value==DEAL_REASON_CLIENT) return "桌面端操作";
   if(value==DEAL_REASON_MOBILE) return "手机端操作";
   if(value==DEAL_REASON_WEB) return "网页端操作";
   if(value==DEAL_REASON_EXPERT) return "EA / 脚本";
   return "其他 / 未知";
}
void StatsMetric(const int x,const int y,const int w,const string label,const string value,const string caption,const color ink)
{
   UIRound(x,y,w,76,UI_CARD);
   UIText(label,x+12,y+9,w-24,9,UI_MUTED);
   UIText(value,x+12,y+28,w-24,17,ink);
   UIText(caption,x+12,y+56,w-24,8,UI_DIM);
}
void StatsKV(const int x,const int y,const int w,const string label,const string value,const color ink)
{
   int labelWidth=(int)MathRound(w*0.44);
   UIText(label,x,y,labelWidth,9,UI_MUTED);
   UIText(value,x+labelWidth,y,w-labelWidth,10,ink,true);
}
void StatsSummaryCards()
{
   int n=statsSummary.trades;
   string currency=AccountInfoString(ACCOUNT_CURRENCY);
   if(statsDetail==2)
   {
      double recent=0; int recentCount=MathMin(n,10);
      for(int i=n-recentCount;i<n;i++) recent+=statsTrades[i].net;
      double dd=n>0 ? statsDrawdowns[n-1] : 0;
      StatsMetric(12,181,128,"累计净收益",statsOK ? StatsMoney(statsSummary.net) : "--",IntegerToString(n)+"笔 · "+currency,StatsInk(statsSummary.net));
      StatsMetric(148,181,128,"当前回撤",statsOK ? StatsMoney(dd) : "--","最大 "+DoubleToString(statsSummary.maxDrawdown,2),dd<0 ? UI_WARN : UI_TEXT);
      StatsMetric(284,181,128,"收益高点",statsOK ? StatsMoney(statsSummary.peak) : "--","从区间起点0累计",UI_TEXT);
      StatsMetric(420,181,128,"最近"+IntegerToString(recentCount)+"笔",statsOK && n>0 ? StatsMoney(recent) : "--","净收益合计",StatsInk(recent));
      return;
   }
   string pf=statsSummary.losses>0 ? DoubleToString(statsSummary.pf,2) : "—";
   StatsMetric(12,181,128,"净收益",statsOK ? StatsMoney(statsSummary.net) : "--",currency+" · 含费用",StatsInk(statsSummary.net));
   StatsMetric(148,181,128,"胜率",statsOK && n>0 ? DoubleToString(100.0*statsSummary.wins/n,1)+"%" : "--",IntegerToString(n)+"笔完整平仓",UI_TEXT);
   StatsMetric(284,181,128,"盈利因子",statsOK ? pf : "--",statsSummary.losses>0 ? "总盈利 / 总亏损" : "暂无亏损样本",UI_TEXT);
   StatsMetric(420,181,128,"最大回撤",statsOK ? DoubleToString(statsSummary.maxDrawdown,2) : "--","已实现 · "+currency,UI_WARN);
}
void StatsOverview()
{
   UIRound(12,267,536,60,UI_ROW);
   UIText("本期结果",26,277,100,9,UI_MUTED);
   string result=MathAbs(statsSummary.net)<0.005 ? "本期净收益接近持平" :
                 statsSummary.net>0 ? "本期净收益为正" : "本期净收益为负";
   UIText(result,26,299,270,11,StatsInk(statsSummary.net));
   UIText("平均每笔 "+StatsMoney(statsSummary.net/statsSummary.trades),310,279,222,11,StatsInk(statsSummary.net),true);
   UIText("当前连亏 "+IntegerToString(statsSummary.lossStreak)+"笔 · 最长 "+IntegerToString(statsSummary.maxLossStreak)+"笔",290,302,242,9,UI_MUTED,true);

   UIRound(12,337,536,116,UI_ROW);
   UIText("盈亏结构",26,349,160,10,UI_TEXT);
   UIText(StringFormat("赢%d / 亏%d / 平%d",statsSummary.wins,statsSummary.losses,statsSummary.breakevens),260,349,272,9,UI_MUTED,true);
   int gain=(int)MathRound(508.0*statsSummary.wins/statsSummary.trades);
   int loss=(int)MathRound(508.0*statsSummary.losses/statsSummary.trades);
   UIRound(26,378,508,6,UI_DIM,0);
   if(gain>0) UIRound(26,378,gain,6,UI_GAIN,0);
   if(loss>0) UIRound(26+gain,378,loss,6,UI_LOSS,0);
   UIText("平均盈利",26,397,150,9,UI_MUTED);
   UIText(StatsMoney(statsSummary.avgWin),26,417,150,14,UI_GAIN);
   UIText("平均亏损",200,397,150,9,UI_MUTED);
   UIText(StatsMoney(statsSummary.avgLoss),200,417,150,14,UI_LOSS);
   UIText("平均盈亏比",374,397,150,9,UI_MUTED);
   UIText(statsSummary.losses>0 ? DoubleToString(statsSummary.payoff,2) : "—",374,417,150,14,UI_TEXT);

   UIRound(12,463,260,70,UI_ROW); UIRound(284,463,264,70,UI_ROW);
   StatsKV(26,475,232,"多单净收益",StatsMoney(statsSummary.buyNet),StatsInk(statsSummary.buyNet));
   UIText(IntegerToString(statsSummary.buyTrades)+"笔 · 平均 "+(statsSummary.buyTrades>0 ? StatsMoney(statsSummary.buyNet/statsSummary.buyTrades) : "—"),26,504,232,9,UI_MUTED);
   StatsKV(298,475,236,"空单净收益",StatsMoney(statsSummary.sellNet),StatsInk(statsSummary.sellNet));
   UIText(IntegerToString(statsSummary.sellTrades)+"笔 · 平均 "+(statsSummary.sellTrades>0 ? StatsMoney(statsSummary.sellNet/statsSummary.sellTrades) : "—"),298,504,236,9,UI_MUTED);

   UIRound(12,543,260,73,UI_ROW); UIRound(284,543,264,73,UI_ROW);
   UIText("最好一笔",26,554,110,9,UI_MUTED);
   UIText(StatsMoney(statsSummary.best),136,550,122,15,StatsInk(statsSummary.best),true);
   UIButton("查看这一笔 ›",26,580,232,113);
   UIText("最差一笔",298,554,110,9,UI_MUTED);
   UIText(StatsMoney(statsSummary.worst),408,550,126,15,StatsInk(statsSummary.worst),true);
   UIButton("查看这一笔 ›",298,580,236,114);
}
void StatsPerformance()
{
   UIRound(12,267,536,152,UI_ROW);
   UIText("收益与费用",26,279,230,11,UI_TEXT);
   UIText(AccountInfoString(ACCOUNT_CURRENCY),350,281,182,9,UI_DIM,true);
   StatsKV(26,313,240,"盈利合计",StatsMoney(statsSummary.gains),UI_GAIN);
   StatsKV(292,313,240,"亏损合计",StatsMoney(statsSummary.lossesMoney),UI_LOSS);
   double costs=statsSummary.commission+statsSummary.swap+statsSummary.fee;
   StatsKV(26,348,240,"成交毛收益",StatsMoney(statsSummary.net-costs),StatsInk(statsSummary.net-costs));
   StatsKV(292,348,240,"费用合计",StatsMoney(costs),StatsInk(costs));
   UIText("佣金 "+StatsMoney(statsSummary.commission)+"   隔夜 "+StatsMoney(statsSummary.swap)+"   其他 "+StatsMoney(statsSummary.fee),26,387,506,9,UI_MUTED);

   UIRound(12,429,536,102,UI_ROW);
   UIText("持仓时间",26,441,200,11,UI_TEXT);
   StatsKV(26,474,240,"盈利单平均",statsSummary.winningHolds>0 ? StatsDuration(statsSummary.winningMinutes/statsSummary.winningHolds) : "—",UI_GAIN);
   StatsKV(292,474,240,"亏损单平均",statsSummary.losingHolds>0 ? StatsDuration(statsSummary.losingMinutes/statsSummary.losingHolds) : "—",UI_LOSS);
   UIText("全部平均 "+StatsDuration(statsSummary.holdMinutes/statsSummary.trades)+" · 最长 "+StatsDuration(statsSummary.maxHold),26,507,506,9,UI_MUTED);

   UIRound(12,541,536,75,UI_ROW);
   UIText("成交规模",26,552,200,11,UI_TEXT);
   StatsKV(26,581,240,"累计入场",DoubleToString(statsSummary.volume,2)+"手",UI_TEXT);
   StatsKV(292,581,240,"入场 / 退出",IntegerToString(statsSummary.trades)+"笔 / "+IntegerToString(statsSummary.exitDeals)+"次",UI_TEXT);
}
// 双图使用相同X坐标和同一持仓ID；0线固定标注，刻度取整避免无意义小数。
void StatsDrawCurve()
{
   int n=ArraySize(statsTrades),selected=StatsSelectedIndex();
   if(n<1 || selected<0) return;
   for(int chart=0;chart<2;chart++)
   {
      int top=chart==0 ? 267 : 413;
      int plotY=top+36,plotH=chart==0 ? 74 : 64;
      UIRound(12,top,536,chart==0 ? 136 : 126,UI_ROW);
      UIText(chart==0 ? "累计净收益" : "每笔盈亏",26,top+10,180,10,UI_TEXT);
      string caption=chart==0 ? "高点 "+StatsMoney(statsSummary.peak) : "正数在上 · 负数在下";
      UIText(caption,280,top+11,252,8.5,chart==0 ? UI_ACCENT : UI_MUTED,true);
      double low=0,high=0;
      for(int i=0;i<n;i++)
      {
         double value=chart==0 ? statsCumulative[i] : statsTrades[i].net;
         low=MathMin(low,value); high=MathMax(high,value);
      }
      double raw=MathMax(high-low,0.02)/3.0;
      double power=MathPow(10,MathFloor(MathLog10(raw))),part=raw/power;
      double step=(part<=1 ? 1 : part<=2 ? 2 : part<=5 ? 5 : 10)*power;
      double bottom=MathFloor(low/step)*step,upper=MathCeil(high/step)*step;
      if(upper==bottom) upper=bottom+step;
      double margin=(upper-bottom)*0.1;
      double minimum=bottom-margin,maximum=upper+margin;
      for(int tick=0;tick<7;tick++)
      {
         double value=bottom+tick*step;
         if(value>upper+step*0.001) break;
         int y=plotY+(int)MathRound((maximum-value)/(maximum-minimum)*plotH);
         panelCanvas.Line(UIPx(82),UIPx(y),UIPx(524),UIPx(y),UIInk(MathAbs(value)<step*0.001 ? UI_DIM : UI_BORDER));
         UIText(DoubleToString(value,step>=1 ? 0 : step>=0.1 ? 1 : 2),20,y-5,52,8,UI_DIM,true);
      }
      int zero=plotY+(int)MathRound(maximum/(maximum-minimum)*plotH);
      int sx=StatsPointX(selected,n);
      panelCanvas.Line(UIPx(sx),UIPx(plotY),UIPx(sx),UIPx(plotY+plotH),UIInk(UI_MUTED));
      int px=82,py=zero;
      for(int i=0;i<n;i++)
      {
         double value=chart==0 ? statsCumulative[i] : statsTrades[i].net;
         int x=StatsPointX(i,n),y=plotY+(int)MathRound((maximum-value)/(maximum-minimum)*plotH);
         if(chart==0)
         {
            panelCanvas.LineAA(UIPx(px),UIPx(py),UIPx(x),UIPx(y),UIInk(UI_ACCENT));
            if(n<45 || i==selected) panelCanvas.FillCircle(UIPx(x),UIPx(y),UIPx(i==selected ? 4 : 2),UIInk(UI_ACCENT));
            if(i==selected) panelCanvas.FillCircle(UIPx(x),UIPx(y),UIPx(2),UIInk(UI_ROW));
            px=x; py=y;
         }
         else
         {
            int half=MathMax(1,(int)MathMin(7,442.0/(n+1)*0.32));
            if(i==selected) panelCanvas.FillRectangle(UIPx(x-half-2),UIPx(MathMin(y,zero)-2),UIPx(x+half+2),UIPx(MathMax(y,zero)+2),UIInk(UI_TEXT));
            panelCanvas.FillRectangle(UIPx(x-half),UIPx(MathMin(y,zero)),UIPx(x+half),UIPx(MathMax(y,zero)),UIInk(StatsInk(value)));
         }
      }
      UIText(chart==0 ? "起点0" : "第1笔",82,plotY+plotH+10,80,8,UI_DIM);
      if(n>2) UIText("第"+IntegerToString((n+1)/2)+"笔",270,plotY+plotH+10,80,8,UI_DIM);
      UIText("第"+IntegerToString(n)+"笔",444,plotY+plotH+10,80,8,UI_DIM,true);
      StatsHit(82,plotY,443,plotH+1,110);
   }
   TgeStatsTrade tr=statsTrades[selected];
   UICard(12,549,536,67,UI_CARD);
   UIText("第"+IntegerToString(selected+1)+"/"+IntegerToString(n)+"笔 · "+TimeToString(tr.closeTime,TIME_MINUTES)+" · "+(tr.direction==POSITION_TYPE_BUY ? "多单" : "空单"),26,559,358,10,UI_TEXT);
   UIText("单笔 "+StatsMoney(tr.net)+"   累计 "+StatsMoney(statsCumulative[selected])+"   回撤 "+StatsMoney(statsDrawdowns[selected]),26,587,358,9,UI_MUTED);
   UIButton("查看复盘 ›",416,567,118,111,true);
}
void StatsReviewPanel()
{
   int index=StatsSelectedIndex(),n=ArraySize(statsTrades);
   if(index<0) return;
   TgeStatsTrade tr=statsTrades[index];
   if(index>0) UIButton("‹ 更早",12,181,84,43);
   if(index<n-1) UIButton("更新 ›",104,181,84,44);
   UIText("第"+IntegerToString(index+1)+"/"+IntegerToString(n)+"笔 · #"+IntegerToString((long)tr.id),200,189,210,9,UI_MUTED);
   UIButton("返回走势",430,181,118,112);

   UIRound(12,220,536,92,UI_CARD);
   UIText(tr.direction==POSITION_TYPE_BUY ? "多单 BUY" : "空单 SELL",26,231,190,13,tr.direction==POSITION_TYPE_BUY ? UI_ACCENT : UI_SELL);
   UIText("净收益 · "+AccountInfoString(ACCOUNT_CURRENCY),330,231,202,9,UI_MUTED,true);
   UIText(DoubleToString(tr.entryVolume,2)+"手 · 持有"+StatsDuration((double)(tr.closeTime-tr.openTime)/60),26,262,286,10,UI_TEXT);
   UIText(StatsMoney(tr.net),330,252,202,23,StatsInk(tr.net),true);
   string origin=tr.mixed ? "混合来源" : (ulong)tr.magic==EA魔法号 ? "本EA" : tr.magic==0 ? "手动入场" : "其他EA";
   UIText(origin+" · 已完整平仓",26,290,280,8.5,UI_DIM);

   double entry=tr.entryValue/tr.entryVolume,exit=tr.exitValue/tr.exitVolume;
   UIRound(12,322,260,110,UI_ROW); UIRound(284,322,264,110,UI_ROW);
   UIText("入场 · 加权成交价",26,334,230,9,UI_MUTED);
   UIText(DoubleToString(entry,_Digits),26,358,230,17,UI_TEXT);
   UIText(TimeToString(tr.openTime,TIME_DATE|TIME_SECONDS),26,400,230,9,UI_MUTED);
   UIText("退出 · 加权成交价",298,334,236,9,UI_MUTED);
   UIText(DoubleToString(exit,_Digits),298,358,236,17,UI_TEXT);
   UIText(TimeToString(tr.closeTime,TIME_DATE|TIME_SECONDS),298,400,236,9,UI_MUTED);

   UIRound(12,442,536,98,UI_ROW);
   double move=(tr.direction==POSITION_TYPE_BUY ? 1 : -1)*(exit-entry);
   StatsKV(26,454,240,"顺方向价差",StatsMoney(move),StatsInk(move));
   StatsKV(292,454,240,"最后退出来源",StatsExitText(tr.exitReason),UI_TEXT);
   StatsKV(26,487,240,"入场成交",IntegerToString(tr.entryDeals)+"次",UI_TEXT);
   StatsKV(292,487,240,"退出成交",IntegerToString(tr.exitDeals)+"次",UI_TEXT);
   UIText("退出来源按最后一笔成交记录；分批成交可能有不同来源",26,519,506,8,UI_DIM);

   UIRound(12,550,536,66,UI_ROW);
   StatsKV(26,561,240,"毛收益",StatsMoney(tr.gross),StatsInk(tr.gross));
   StatsKV(292,561,240,"费用合计",StatsMoney(tr.commission+tr.swap+tr.fee),StatsInk(tr.commission+tr.swap+tr.fee));
   UIText("佣金 "+StatsMoney(tr.commission)+"   隔夜 "+StatsMoney(tr.swap)+"   其他 "+StatsMoney(tr.fee),26,592,506,8.5,UI_MUTED);
}
void StatsPanel()
{
   StatsRefresh(); StatsBuildSeries();
   string periods[3]={"日统计","周统计","月统计"};
   string current=statsPeriod==0 ? "今日" : statsPeriod==1 ? "本周" : "本月";
   for(int i=0;i<3;i++) UIButton(periods[i],12+i*76,88,68,30+i,statsPeriod==i);
   UIButton("上一期",258,88,82,33);
   UIButton(current,348,88,82,34,statsOffsets[statsPeriod]==0);
   UIButton("下一期",438,88,110,35);
   string details[4]={"总览","表现","走势","复盘"},filters[3]={"本EA","手动","全部"};
   for(int i=0;i<4;i++) UIButton(details[i],12+i*76,122,68,36+i,statsDetail==i);
   for(int i=0;i<3;i++) UIButton(filters[i],338+i*72,122,66,40+i,statsFilter==i);
   string first=TimeToString(statsRangeStart,TIME_DATE),last=TimeToString(statsRangeEnd-1,TIME_DATE);
   UIText((first==last ? first : first+" → "+last)+" · 券商时间 · "+AccountInfoString(ACCOUNT_CURRENCY),14,160,530,9,UI_MUTED);

   if(statsDetail!=3 || !statsOK || statsSummary.trades==0) StatsSummaryCards();
   if(!statsOK || statsSummary.trades==0)
   {
      UIRound(12,267,536,349,UI_ROW);
      UIText(statsStatus,28,380,504,11,UI_WARN);
      UIText(statsOK ? "切换日期或筛选，查看完整平仓记录" : "连接恢复后自动重试",28,416,504,10,UI_MUTED);
   }
   else if(statsDetail==0) StatsOverview();
   else if(statsDetail==1) StatsPerformance();
   else if(statsDetail==2) StatsDrawCurve();
   else StatsReviewPanel();

   string note=statsDetail==3 ? "浮盈/浮亏及SL调整轨迹未记录 · 此页仅展示成交历史" :
               statsDetail==2 ? "点击双图选择交易 · 完整平仓累计 · 不含浮动权益" :
               "完整平仓 · 净收益含费用 · 回撤不含浮动权益";
   if(statsSkipped>0) note=IntegerToString(statsSkipped)+"笔缺失/反转未计入 · "+note;
   UIText(note,14,631,532,8,statsSkipped>0 ? UI_WARN : UI_DIM);
   panelCanvas.Update();
}
