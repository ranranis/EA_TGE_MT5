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
// 只绘制缓存的完整平仓结果；图表不查询历史，也不参与交易决策。
void StatsLine(const int row,const string left,const string right)
{
   int y=345+row*24;
   string cells[2]={left,right};
   for(int i=0;i<2;i++)
   {
      int x=24+i*270,split=StringFind(cells[i],"：");
      string label=split>=0 ? StringSubstr(cells[i],0,split) : cells[i];
      string value=split>=0 ? StringSubstr(cells[i],split+1) : "";
      UIText(label,x,y,124,8.5,UI_MUTED);
      UIText(value,x+120,y,118,9,UI_TEXT,true);
      if(row<6) panelCanvas.Line(UIPx(x),UIPx(y+20),UIPx(x+238),UIPx(y+20),UIInk(UI_BORDER));
   }
}
void StatsDrawCurve()
{
   int n=ArraySize(statsTrades);
   if(n==0) return;
   double cumulative[];
   ArrayResize(cumulative,n+1); cumulative[0]=0;
   double peak=0;
   for(int i=0;i<n;i++) { cumulative[i+1]=cumulative[i]+statsTrades[i].net; peak=MathMax(peak,cumulative[i+1]); }
   for(int chart=0;chart<2;chart++)
   {
      int top=chart==0 ? 261 : 439;
      UIRound(12,top,536,166,UI_ROW);
      UIText(chart==0 ? "累计净收益" : "每笔盈亏",26,top+12,200,10,UI_TEXT);
      string caption=chart==0 ? "高点 "+StatsMoney(peak) : "盈利 / 亏损 · "+IntegerToString(n)+"笔";
      UIText(caption,256,top+13,274,8.5,chart==0 ? UI_ACCENT : UI_MUTED,true);
      double low=0,high=0;
      for(int i=0;i<n;i++)
      {
         double value=chart==0 ? cumulative[i+1] : statsTrades[i].net;
         low=MathMin(low,value); high=MathMax(high,value);
      }
      // 留出端点和极值的绘制空间；全零和单笔记录也有稳定坐标轴。
      double padding=MathMax((high-low)*0.12,0.01);
      low-=padding; high+=padding;
      int x=108,y=top+43,w=414,h=90;
      for(int tick=0;tick<3;tick++)
      {
         double value=high-(high-low)*tick/2.0;
         int gy=y+(int)MathRound(h*tick/2.0);
         panelCanvas.Line(UIPx(x),UIPx(gy),UIPx(x+w),UIPx(gy),UIInk(UI_BORDER));
         UIText(DoubleToString(value,2),24,gy-5,74,8,UI_DIM,true);
      }
      int zero=y+(int)MathRound(high/(high-low)*h);
      panelCanvas.Line(UIPx(x),UIPx(zero),UIPx(x+w),UIPx(zero),UIInk(UI_DIM));
      int px=x,py=zero;
      for(int i=0;i<n;i++)
      {
         double value=chart==0 ? cumulative[i+1] : statsTrades[i].net;
         int nx=x+(int)MathRound((chart==0 ? i+1.0 : i+0.5)*w/n);
         int ny=y+(int)MathRound((high-value)/(high-low)*h);
         if(chart==0)
         {
            panelCanvas.LineAA(UIPx(px),UIPx(py),UIPx(nx),UIPx(ny),UIInk(UI_ACCENT));
            if(i==n-1) panelCanvas.FillCircle(UIPx(nx),UIPx(ny),UIPx(3),UIInk(UI_ACCENT));
            px=nx; py=ny;
         }
         else
         {
            int half=MathMax(1,(int)MathMin(9.0,w/(double)n*0.30));
            panelCanvas.FillRectangle(UIPx(MathMax(x,nx-half)),UIPx(MathMin(zero,ny)),
                                      UIPx(MathMin(x+w,nx+half)),UIPx(MathMax(zero,ny)),UIInk(StatsInk(value)));
         }
      }
      UIText(chart==0 ? "起点 0" : "第1笔",108,top+144,95,8,UI_DIM);
      if(n>2) UIText("第"+IntegerToString((n+1)/2)+"笔",276,top+144,90,8,UI_DIM);
      if(n>1 || chart==0) UIText("第"+IntegerToString(n)+"笔",424,top+144,100,8,UI_DIM,true);
   }
   UIText("按完整平仓顺序 · "+AccountInfoString(ACCOUNT_CURRENCY),24,612,280,8,UI_DIM);
   UIText("最新 "+StatsMoney(cumulative[n]),318,612,214,9,StatsInk(cumulative[n]),true);
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
   UIRound(12,181,536,70,UI_CARD);
   string titles[4]={"净收益","胜率","盈利因子","最大回撤"};
   double winRate=statsSummary.trades>0 ? 100.0*statsSummary.wins/statsSummary.trades : 0;
   string profitFactor=statsSummary.losses>0 ? DoubleToString(statsSummary.pf,2) :
                       statsSummary.wins>0 ? "无亏损" : "--";
   string values[4]={statsOK ? StatsMoney(statsSummary.net) : "--",
                    statsOK && statsSummary.trades>0 ? DoubleToString(winRate,1)+"%" : "--",
                    statsOK ? profitFactor : "--",
                    statsOK ? "-"+DoubleToString(statsSummary.maxDrawdown,2) : "--"};
   for(int i=0;i<4;i++)
   {
      int x=24+i*134;
      if(i>0) panelCanvas.Line(UIPx(x-12),UIPx(195),UIPx(x-12),UIPx(235),UIInk(UI_BORDER));
      UIText(titles[i],x,191,114,8.5,UI_MUTED);
      UIText(values[i],x,213,114,14,i==0 ? StatsInk(statsSummary.net) : i==3 ? UI_LOSS : UI_TEXT);
   }
   if(!statsOK || statsSummary.trades==0)
   {
      UIRound(12,261,536,260,UI_ROW);
      UIText(statsStatus,24,282,508,10,UI_WARN);
      UIText(statsOK ? "切换日期或范围，查看已平仓交易" : "恢复连接后自动重试，也可切换日期重新查询",24,315,508,9.5,UI_MUTED);
   }
   else if(statsDetail==0)
   {
      UIRound(12,261,536,260,UI_ROW);
      UIText("结果结构",26,274,200,10,UI_TEXT);
      UIText(StringFormat("%d笔完成 · 当前连亏%d笔",statsSummary.trades,statsSummary.lossStreak),256,275,274,9,UI_MUTED,true);
      int gainWidth=(int)MathRound(508.0*statsSummary.wins/statsSummary.trades);
      int lossWidth=(int)MathRound(508.0*statsSummary.losses/statsSummary.trades);
      panelCanvas.FillRectangle(UIPx(26),UIPx(305),UIPx(533),UIPx(312),UIInk(UI_DIM));
      if(gainWidth>0) panelCanvas.FillRectangle(UIPx(26),UIPx(305),UIPx(25+gainWidth),UIPx(312),UIInk(UI_GAIN));
      if(lossWidth>0) panelCanvas.FillRectangle(UIPx(26+gainWidth),UIPx(305),UIPx(25+gainWidth+lossWidth),UIPx(312),UIInk(UI_LOSS));
      string pf=statsSummary.losses>0 ? DoubleToString(statsSummary.pf,2) : statsSummary.wins>0 ? "无亏损样本" : "--";
      StatsLine(0,StringFormat("赢 / 亏 / 平：%d / %d / %d",statsSummary.wins,statsSummary.losses,statsSummary.breakevens),
                "平均每笔："+StatsMoney(statsSummary.net/statsSummary.trades));
      StatsLine(1,"平均赚："+StatsMoney(statsSummary.avgWin),"平均亏："+StatsMoney(statsSummary.avgLoss));
      StatsLine(2,"盈亏比："+(statsSummary.losses>0 ? DoubleToString(statsSummary.payoff,2) : "--"),
                "最长连亏："+IntegerToString(statsSummary.maxLossStreak)+"笔");
      StatsLine(3,StringFormat("多单：%d笔  %s",statsSummary.buyTrades,StatsMoney(statsSummary.buyNet)),
                StringFormat("空单：%d笔  %s",statsSummary.sellTrades,StatsMoney(statsSummary.sellNet)));
      StatsLine(4,"平均持仓："+DoubleToString(statsSummary.holdMinutes/statsSummary.trades,1)+"分钟",
                "最长持仓："+DoubleToString(statsSummary.maxHold,1)+"分钟");
      StatsLine(5,"最好："+StatsMoney(statsSummary.best),"最差："+StatsMoney(statsSummary.worst));
      StatsLine(6,"累计入场："+DoubleToString(statsSummary.volume,2)+"手","退出成交："+IntegerToString(statsSummary.exitDeals)+"次");
   }
   else if(statsDetail==1)
   {
      UIRound(12,261,536,260,UI_ROW);
      UIText("收益与成本",26,274,220,10,UI_TEXT);
      UIText("每笔净收益",26,304,200,9,UI_MUTED);
      UIText(StatsMoney(statsSummary.net/statsSummary.trades)+" "+AccountInfoString(ACCOUNT_CURRENCY),240,301,292,15,StatsInk(statsSummary.net),true);
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
      UIText("第"+IntegerToString(statsReview+1)+" / "+IntegerToString(n)+"笔 · 按最近平仓排序",202,269,330,9,UI_MUTED,true);
      UIRound(12,298,536,223,UI_ROW);
      color sideInk=tr.direction==POSITION_TYPE_BUY ? UI_ACCENT : UI_SELL;
      UIText(tr.direction==POSITION_TYPE_BUY ? "多单 BUY" : "空单 SELL",24,310,160,11,sideInk);
      UIText("净结果",268,310,80,8.5,UI_MUTED);
      UIText(StatsMoney(tr.net)+" "+AccountInfoString(ACCOUNT_CURRENCY),354,307,178,12,StatsInk(tr.net),true);
      UIText("交易编号  #"+IntegerToString((long)tr.id),24,340,230,8.5,UI_DIM);
      UIText("持仓时长  "+DoubleToString((double)(tr.closeTime-tr.openTime)/60,1)+" 分钟",268,340,240,8.5,UI_DIM);
      UIText("时间",24,371,80,8.5,UI_MUTED);
      UIText(TimeToString(tr.openTime,TIME_DATE|TIME_MINUTES)+"  →  "+TimeToString(tr.closeTime,TIME_DATE|TIME_MINUTES),112,371,408,9,UI_TEXT);
      UIText("价格路径",24,402,80,8.5,UI_MUTED);
      UIText(DoubleToString(tr.entryValue/tr.entryVolume,_Digits)+"  →  "+DoubleToString(tr.exitValue/tr.exitVolume,_Digits),112,402,408,10,UI_TEXT);
      UIText("成交结构",24,433,80,8.5,UI_MUTED);
      UIText(StringFormat("入场 %.2f手 · %d次退出成交",tr.entryVolume,tr.exitDeals),112,433,408,9,UI_TEXT);
      UIText("结果拆分",24,464,80,8.5,UI_MUTED);
      UIText("毛收益 "+StatsMoney(tr.gross)+" · 佣金 "+StatsMoney(tr.commission)+" · 隔夜费 "+StatsMoney(tr.swap)+" · 费用 "+StatsMoney(tr.fee),112,464,408,8.5,UI_MUTED);
   }
   string note=statsOK ? "完整平仓 · 净收益含逐笔费用 · "+AccountInfoString(ACCOUNT_CURRENCY) :
                          "请确认MT5已连接并可读取成交历史";
   if(statsSkipped>0) note+=" · "+IntegerToString(statsSkipped)+"笔缺失/反转未计入";
   else if(statsOK) note+=" · 回撤不含浮动权益";
   UIText(note,14,statsDetail==2 ? 633 : 540,530,8,statsSkipped>0 ? UI_WARN : UI_MUTED);
   panelCanvas.Update();
}
