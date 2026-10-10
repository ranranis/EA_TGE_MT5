// 从交易托管系统迁移完整持仓统计口径；仅使用服务器历史，不依赖旧EA的CSV。
// 统计时间为券商服务器日期，所有页面共享同一批完整平仓记录。
struct TgeStatsTrade
{
   ulong id,lastDeal;
   datetime openTime,closeTime;
   long magic;
   int direction,entryDeals,exitDeals;
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
   ZeroMemory(tr); tr.id=id;
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
         if(at>tr.closeTime || (at==tr.closeTime && deal>tr.lastDeal)) { tr.closeTime=at; tr.lastDeal=deal; }
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
   return (value>0 ? "+" : "")+DoubleToString(value,2);
}
color StatsInk(const double value) { return value>0.005 ? UI_GAIN : value< -0.005 ? UI_LOSS : UI_MUTED; }
void StatsLine(const int row,const string left,const string right)
{
   int y=276+row*26;
   UIText(left,24,y,246,9.5,UI_TEXT); UIText(right,290,y,242,9.5,UI_TEXT);
}
void StatsDrawCurve()
{
   UICard(12,261,536,200,UI_ROW);
   UIText("累计已完成交易净收益",24,272,300,10,UI_TEXT);
   double value=0,low=0,high=0;
   for(int i=0;i<ArraySize(statsTrades);i++) { value+=statsTrades[i].net; low=MathMin(low,value); high=MathMax(high,value); }
   if(high-low<1e-8) { high+=1; low-=1; }
   int x=28,y=308,w=498,h=113,n=ArraySize(statsTrades);
   int baseline=y+(int)MathRound(high/(high-low)*h);
   panelCanvas.Line(UIPx(x),UIPx(baseline),UIPx(x+w),UIPx(baseline),UIInk(UI_BORDER));
   value=0; int px=x,py=baseline;
   for(int i=0;i<n;i++)
   {
      value+=statsTrades[i].net;
      int nx=x+(int)MathRound((i+1)*(double)w/MathMax(n,1));
      int ny=y+(int)MathRound((high-value)/(high-low)*h);
      panelCanvas.Line(UIPx(px),UIPx(py),UIPx(nx),UIPx(ny),UIInk(UI_ACCENT)); px=nx; py=ny;
   }
   UIText(StatsMoney(high),24,292,130,8.5,UI_DIM);
   UIText(StatsMoney(low),24,425,130,8.5,UI_DIM);
   UIText("区间起点",156,439,150,8.5,UI_DIM);
   UIText("最新 "+StatsMoney(value),344,439,188,8.5,StatsInk(value),true);
}
void StatsPanel()
{
   StatsRefresh();
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
   string range=first==last ? first : first+" → "+last;
   UIText(range+" · 券商服务器日期",14,160,530,9.5,UI_MUTED);
   UICard(12,181,536,70,UI_CARD);
   string titles[4]={"净收益","胜率","完成持仓","已实现回撤"};
   double winRate=statsSummary.trades>0 ? 100.0*statsSummary.wins/statsSummary.trades : 0;
   string values[4]={statsOK ? StatsMoney(statsSummary.net) : "--",
                    statsOK && statsSummary.trades>0 ? DoubleToString(winRate,1)+"%" : "--",
                    statsOK ? IntegerToString(statsSummary.trades)+"笔" : "--",
                    statsOK ? DoubleToString(statsSummary.maxDrawdown,2) : "--"};
   for(int i=0;i<4;i++)
   {
      int x=24+i*134;
      UIText(titles[i],x,191,114,9,UI_MUTED);
      UIText(values[i],x,213,114,14,i==0 ? StatsInk(statsSummary.net) : UI_TEXT);
   }
   if(!statsOK || statsSummary.trades==0)
   {
      UICard(12,261,536,200,UI_ROW);
      UIText(statsStatus,24,282,508,10,UI_WARN);
      UIText(statsOK ? "切换日期或范围，查看已平仓交易" : "恢复连接后自动重试，也可切换日期重新查询",24,315,508,9.5,UI_MUTED);
   }
   else if(statsDetail==0)
   {
      UICard(12,261,536,200,UI_ROW);
      string pf=statsSummary.losses>0 ? DoubleToString(statsSummary.pf,2) : statsSummary.wins>0 ? "无亏损样本" : "--";
      StatsLine(0,StringFormat("赢 / 亏 / 平：%d / %d / %d",statsSummary.wins,statsSummary.losses,statsSummary.breakevens),
                "盈利因子："+pf);
      StatsLine(1,"平均赚："+StatsMoney(statsSummary.avgWin),"平均亏："+StatsMoney(statsSummary.avgLoss));
      StatsLine(2,"最好："+StatsMoney(statsSummary.best),"最差："+StatsMoney(statsSummary.worst));
      StatsLine(3,StringFormat("多单：%d笔  %s",statsSummary.buyTrades,StatsMoney(statsSummary.buyNet)),
                StringFormat("空单：%d笔  %s",statsSummary.sellTrades,StatsMoney(statsSummary.sellNet)));
      StatsLine(4,"累计入场："+DoubleToString(statsSummary.volume,2)+"手","退出成交："+IntegerToString(statsSummary.exitDeals)+"次");
      StatsLine(5,"当前连亏："+IntegerToString(statsSummary.lossStreak)+"笔","最长连亏："+IntegerToString(statsSummary.maxLossStreak)+"笔");
      StatsLine(6,"平均持仓："+DoubleToString(statsSummary.holdMinutes/statsSummary.trades,1)+"分钟",
                "盈亏比："+(statsSummary.losses>0 ? DoubleToString(statsSummary.payoff,2) : "--"));
   }
   else if(statsDetail==1)
   {
      UICard(12,261,536,200,UI_ROW);
      StatsLine(0,"盈利交易合计："+StatsMoney(statsSummary.gains),"亏损交易合计："+StatsMoney(statsSummary.lossesMoney));
      StatsLine(1,"佣金："+StatsMoney(statsSummary.commission),"隔夜费："+StatsMoney(statsSummary.swap));
      StatsLine(2,"成交费用："+StatsMoney(statsSummary.fee),"平均每笔："+StatsMoney(statsSummary.net/statsSummary.trades));
      StatsLine(3,"盈利平均持仓："+(statsSummary.winningHolds>0 ? DoubleToString(statsSummary.winningMinutes/statsSummary.winningHolds,1)+"分钟" : "--"),
                "亏损平均持仓："+(statsSummary.losingHolds>0 ? DoubleToString(statsSummary.losingMinutes/statsSummary.losingHolds,1)+"分钟" : "--"));
      StatsLine(4,"最长持仓："+DoubleToString(statsSummary.maxHold,1)+"分钟",
                "额外退出成交："+IntegerToString(statsSummary.exitDeals-statsSummary.trades)+"次");
      StatsLine(5,"多单净收益："+StatsMoney(statsSummary.buyNet),"空单净收益："+StatsMoney(statsSummary.sellNet));
      StatsLine(6,"统计范围：完整平仓","金额单位："+AccountInfoString(ACCOUNT_CURRENCY));
   }
   else if(statsDetail==2) StatsDrawCurve();
   else
   {
      int n=ArraySize(statsTrades); TgeStatsTrade tr=statsTrades[n-1-statsReview];
      UIButton("上一笔",12,261,82,43); UIButton("下一笔",102,261,82,44);
      UIText(IntegerToString(statsReview+1)+" / "+IntegerToString(n)+" · 从最近平仓开始",202,269,330,9,UI_MUTED,true);
      UICard(12,298,536,163,UI_ROW);
      UIText((tr.direction==POSITION_TYPE_BUY ? "BUY" : "SELL")+"  #"+IntegerToString((long)tr.id),24,310,320,10.5,UI_ACCENT);
      UIText(StatsMoney(tr.net)+" "+AccountInfoString(ACCOUNT_CURRENCY),354,310,178,11,StatsInk(tr.net),true);
      UIText("开仓 "+TimeToString(tr.openTime,TIME_DATE|TIME_MINUTES)+"  →  平仓 "+TimeToString(tr.closeTime,TIME_DATE|TIME_MINUTES),24,341,508,9,UI_MUTED);
      UIText("入场 "+DoubleToString(tr.entryValue/tr.entryVolume,_Digits)+"  →  退出 "+DoubleToString(tr.exitValue/tr.exitVolume,_Digits)+
             " · 加权成交价",24,368,508,9.5,UI_TEXT);
      UIText(StringFormat("入场 %.2f手 · %d次退出成交 · 持仓 %.1f分钟",tr.entryVolume,tr.exitDeals,(double)(tr.closeTime-tr.openTime)/60),24,395,508,9.5,UI_TEXT);
      UIText("毛收益 "+StatsMoney(tr.gross)+" · 佣金 "+StatsMoney(tr.commission)+" · 隔夜费 "+StatsMoney(tr.swap)+" · 费用 "+StatsMoney(tr.fee),24,427,508,9,UI_MUTED);
   }
   string note=statsOK ? "完整平仓 · 净收益含逐笔费用 · "+AccountInfoString(ACCOUNT_CURRENCY) :
                          "请确认MT5已连接并可读取成交历史";
   if(statsSkipped>0) note+=" · "+IntegerToString(statsSkipped)+"笔缺失/反转未计入";
   else if(statsOK) note+=" · 回撤不含浮动权益";
   UIText(note,14,473,530,8.5,statsSkipped>0 ? UI_WARN : UI_MUTED);
   panelCanvas.Update();
}
