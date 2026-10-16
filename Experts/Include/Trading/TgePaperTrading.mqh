// P1：独立虚拟账本；仅OnTimer采样，无交易请求，不触碰真实pending/消费/持仓状态。
struct PaperTrade
{
   long id,opened;
   datetime bar;
   int arm,sign;
   double level,entry,volume,mfe,mae;
   string source;
};
struct PaperVisit { int arm; double level; datetime away; };
struct PaperScore { int opened,closed,wins,losses,invalid; double net,peak,drawdown; };
struct PaperEvent
{
   long seq,id,msc;
   datetime bar;
   int arm,sign;
   double level,entry,exit,volume,gross,fee,mfe,mae;
   string kind,source,why;
};
PaperTrade paperTrades[];
PaperVisit paperVisits[];
PaperScore paperScores[2];
long paperSeq=0,paperLastTick=0;
int paperFile=INVALID_HANDLE;
bool paperReady=false,paperPending=false,paperRestored=false;
datetime paperRetry=0;
PaperEvent paperFrozen;
string paperPolicy="",paperFilePath="",paperLastLine="",paperHealth="自动模拟尚未初始化";
string paperStatus[2]={"等待报价","等待报价"},paperLastResult="尚无模拟平仓";
long paperDecisionMinute[2]={0,0};

string PaperClean(string text)
{
   StringReplace(text,"\t"," "); StringReplace(text,"\r"," "); StringReplace(text,"\n"," "); return text;
}
string PaperPolicy()
{
   // 改变比较规则或费用会自动分开账本，不能把不同假设的成绩相加。
   return "P1/tp5/sl10/hold60/lot"+DoubleToString(每次开仓手数,8)+"/cap"+IntegerToString(最大同时持仓)+
      "/fee"+DoubleToString(模拟每手往返费用,8)+"/slip"+DoubleToString(模拟单边滑点价格,8)+
      "/news"+IntegerToString((int)启用消息日历)+"/windows"+IntegerToString(重点事件前后分钟)+","+
      IntegerToString(一般高重要性前后分钟)+"/shock"+IntegerToString(冲击冷却秒数)+
      "/recover"+IntegerToString(恢复确认秒数)+"/observer"+IntegerToString((int)启用入场观察实验)+
      "/distance"+DoubleToString(挂单最大离价,8)+"/ai"+IntegerToString((int)读取AI即时策略)+"/"+ObserverPolicy();
}
string PaperEncode(const PaperEvent &e)
{
   string line="P1\t"+IntegerToString(e.seq)+"\t"+e.kind+"\t"+IntegerToString(e.arm)+"\t"+
      IntegerToString(e.id)+"\t"+IntegerToString(e.msc)+"\t"+IntegerToString((long)e.bar)+"\t"+IntegerToString(e.sign)+
      "\t"+DoubleToString(e.level,8)+"\t"+DoubleToString(e.entry,8)+"\t"+DoubleToString(e.exit,8)+
      "\t"+DoubleToString(e.volume,8)+"\t"+DoubleToString(e.gross,8)+"\t"+DoubleToString(e.fee,8)+
      "\t"+DoubleToString(e.mfe,8)+"\t"+DoubleToString(e.mae,8)+"\t"+PaperClean(e.source)+"\t"+PaperClean(e.why)+
      "\t"+paperPolicy+"\t"+AccountInfoString(ACCOUNT_CURRENCY)+"\t"+_Symbol;
   return line+"\t"+IntegerToString((long)Hash(line))+"\tEND";
}
bool PaperParse(const string line,PaperEvent &e)
{
   string f[]; if(StringSplit(line,'\t',f)!=23 || f[0]!="P1" || f[22]!="END" ||
      f[18]!=paperPolicy || f[19]!=AccountInfoString(ACCOUNT_CURRENCY) || f[20]!=_Symbol) return false;
   string payload="";
   for(int i=0;i<=20;i++) payload+=(i==0 ? "" : "\t")+f[i];
   if(IntegerToString((long)Hash(payload))!=f[21]) return false;
   for(int i=1;i<=15;i++)
   {
      if(i==2) continue;
      string value=f[i]; if(StringLen(value)>0 && StringGetCharacter(value,0)=='-') value=StringSubstr(value,1);
      if(!Number(value,true) || !MathIsValidNumber(StringToDouble(f[i]))) return false;
   }
   ZeroMemory(e);
   e.seq=StringToInteger(f[1]); e.kind=f[2]; e.arm=(int)StringToInteger(f[3]);
   e.id=StringToInteger(f[4]); e.msc=StringToInteger(f[5]); e.bar=(datetime)StringToInteger(f[6]);
   e.sign=(int)StringToInteger(f[7]); e.level=StringToDouble(f[8]); e.entry=StringToDouble(f[9]);
   e.exit=StringToDouble(f[10]); e.volume=StringToDouble(f[11]); e.gross=StringToDouble(f[12]);
   e.fee=StringToDouble(f[13]); e.mfe=StringToDouble(f[14]); e.mae=StringToDouble(f[15]);
   e.source=f[16]; e.why=f[17];
   return e.seq>0 && e.msc>0 && e.arm>=0 && e.arm<=1 &&
      (e.kind=="OPEN" || e.kind=="CLOSE" || e.kind=="GAP" || e.kind=="REARM" || e.kind=="WAIT");
}
int PaperFind(const long id)
{
   for(int i=0;i<ArraySize(paperTrades);i++) if(paperTrades[i].id==id) return i;
   return -1;
}
int PaperVisitIndex(const int arm,const double level)
{
   for(int i=0;i<ArraySize(paperVisits);i++)
      if(paperVisits[i].arm==arm && MathAbs(paperVisits[i].level-level)<TickSize()*0.5) return i;
   return -1;
}
bool PaperEventValid(const PaperEvent &e)
{
   if(e.seq!=paperSeq+1) return false;
   if(e.kind=="WAIT") return e.level>0;
   if(e.kind=="REARM") return PaperVisitIndex(e.arm,e.level)>=0;
   if(e.kind=="OPEN") return e.id==e.seq && PaperFind(e.id)<0 && (e.sign==1 || e.sign==-1) &&
      e.level>0 && e.entry>0 && e.volume>0 && PaperVisitIndex(e.arm,e.level)<0;
   int i=PaperFind(e.id);
   if(i<0 || paperTrades[i].arm!=e.arm || paperTrades[i].sign!=e.sign ||
      paperTrades[i].entry!=e.entry || paperTrades[i].volume!=e.volume || e.msc<paperTrades[i].opened) return false;
   return e.kind=="GAP" || (e.kind=="CLOSE" && e.exit>0 && e.fee>=0);
}
void PaperApply(const PaperEvent &e)
{
   paperSeq=e.seq;
   if(e.kind=="WAIT")
   { paperDecisionMinute[e.arm]=e.msc/60000; return; }
   if(e.kind=="REARM")
   {
      int at=PaperVisitIndex(e.arm,e.level),n=ArraySize(paperVisits);
      for(int j=at+1;j<n;j++) paperVisits[j-1]=paperVisits[j];
      ArrayResize(paperVisits,n-1); return;
   }
   if(e.kind=="OPEN")
   {
      int n=ArraySize(paperTrades); ArrayResize(paperTrades,n+1);
      paperTrades[n].id=e.id; paperTrades[n].opened=e.msc; paperTrades[n].bar=e.bar;
      paperTrades[n].arm=e.arm; paperTrades[n].sign=e.sign; paperTrades[n].level=e.level;
      paperTrades[n].entry=e.entry; paperTrades[n].volume=e.volume;
      paperTrades[n].mfe=0; paperTrades[n].mae=0; paperTrades[n].source=e.source;
      n=ArraySize(paperVisits); ArrayResize(paperVisits,n+1);
      paperVisits[n].arm=e.arm; paperVisits[n].level=e.level; paperVisits[n].away=0;
      paperScores[e.arm].opened++; return;
   }
   int at=PaperFind(e.id),n=ArraySize(paperTrades);
   for(int j=at+1;j<n;j++) paperTrades[j-1]=paperTrades[j];
   ArrayResize(paperTrades,n-1);
   if(e.kind=="GAP") { paperScores[e.arm].invalid++; return; }
   double net=e.gross-e.fee;
   paperScores[e.arm].closed++; paperScores[e.arm].net+=net;
   if(net>0) paperScores[e.arm].wins++;
   if(net<0) paperScores[e.arm].losses++;
   paperScores[e.arm].peak=MathMax(paperScores[e.arm].peak,paperScores[e.arm].net);
   paperScores[e.arm].drawdown=MathMax(paperScores[e.arm].drawdown,paperScores[e.arm].peak-paperScores[e.arm].net);
   paperLastResult=(e.arm==0 ? "碰价基准" : "新判断")+ " · "+e.why+" · "+
      DoubleToString(net,2)+" "+AccountInfoString(ACCOUNT_CURRENCY);
}
bool PaperWrite(const PaperEvent &e)
{
   if(paperFile==INVALID_HANDLE) return false;
   string line=PaperEncode(e);
   FileSeek(paperFile,0,SEEK_END); ResetLastError();
   uint written=FileWriteString(paperFile,"\r\n"+line+"\r\n"); FileFlush(paperFile);
   bool ok=written>0 && GetLastError()==0;
   if(ok) paperLastLine=line;
   return ok;
}
bool PaperEmit(PaperEvent &e)
{
   e.seq=paperSeq+1;
   if(e.kind=="OPEN") e.id=e.seq;
   if(!PaperEventValid(e)) { paperReady=false; paperHealth="模拟账本状态不一致，已停止模拟"; return false; }
   // 写入成功才推进模拟状态，失败冻结同一事件重试；不触碰真实订单。
   if(!PaperWrite(e))
   {
      paperFrozen=e; paperPending=true; paperRetry=TimeGMT()+10;
      paperHealth="模拟记录保存失败，暂停新模拟并重试"; return false;
   }
   PaperApply(e); return true;
}
void InitPaper()
{
   if(!启用自动模拟对比) { paperHealth="自动模拟已关闭"; return; }
   paperPolicy=PaperPolicy();
   FolderCreate("FeishuMT5SignalMonitor\\paper",FILE_COMMON);
   paperFilePath="FeishuMT5SignalMonitor\\paper\\"+prefix+IntegerToString((long)Hash(paperPolicy))+".tsv";
   paperFile=FileOpen(paperFilePath,FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(paperFile==INVALID_HANDLE) { paperHealth="模拟账本无法打开，请检查Common文件目录"; return; }
   while(!FileIsEnding(paperFile))
   {
      string line=FileReadString(paperFile); if(line=="") continue;
      // 崩溃时未写完的末行不算事件；后续重试通过序号与完整校验去重。
      if(StringLen(line)<4 || StringSubstr(line,StringLen(line)-4)!="\tEND") continue;
      PaperEvent e;
      if(!PaperParse(line,e)) { paperHealth="模拟账本校验失败，保留文件并停止模拟"; return; }
      if(e.seq==paperSeq && line==paperLastLine) continue;
      if(!PaperEventValid(e)) { paperHealth="模拟账本顺序异常，保留文件并停止模拟"; return; }
      PaperApply(e); paperLastLine=line;
   }
   paperRestored=ArraySize(paperTrades)>0;
   paperReady=true; paperHealth="自动模拟已就绪，等待新报价";
}
void PaperFromTrade(const PaperTrade &t,const MqlTick &q,PaperEvent &e)
{
   ZeroMemory(e);
   e.id=t.id; e.arm=t.arm; e.sign=t.sign; e.msc=q.time_msc; e.bar=t.bar;
   e.level=t.level; e.entry=t.entry; e.volume=t.volume; e.source=t.source;
   e.mfe=t.mfe; e.mae=t.mae;
}
// 仅用实际观察到的Bid/Ask。TP不给跳空额外收益，SL承担更差的采样价。
string PaperExit(const PaperTrade &t,const MqlTick &q,double &price)
{
   double mark=t.sign>0 ? q.bid : q.ask;
   double delta=t.sign*(mark-t.entry);
   string why="";
   if(delta<=-10) { price=mark; why="止损"; }
   else if(delta>=5) { price=t.entry+t.sign*5; why="止盈"; }
   else if(q.time_msc-t.opened>=3600000) { price=mark; why="满60分钟退出"; }
   if(why!="") price=Align(price-t.sign*模拟单边滑点价格,-t.sign);
   return why;
}
bool PaperInvalidate(const MqlTick &q)
{
   for(int i=ArraySize(paperTrades)-1;i>=0;i--)
   {
      PaperEvent e; PaperFromTrade(paperTrades[i],q,e);
      e.kind="GAP"; e.why="断流、重启或保存中断，过程缺失；不计盈亏";
      if(!PaperEmit(e)) return false;
   }
   for(int i=0;i<ArraySize(paperVisits);i++) paperVisits[i].away=0;
   paperRestored=false; return true;
}
int PaperCount(const int arm)
{
   int n=0; for(int i=0;i<ArraySize(paperTrades);i++) if(paperTrades[i].arm==arm) n++;
   return n;
}
bool PaperAreaBusy(const int arm,const double level)
{
   for(int i=0;i<ArraySize(paperTrades);i++)
      if(paperTrades[i].arm==arm && MathAbs(paperTrades[i].level-level)<=TEACHER_BAND*2) return true;
   return false;
}
void PaperPoll()
{
   if(!启用自动模拟对比 || !paperReady) return;
   if(paperPending)
   {
      if(TimeGMT()<paperRetry) return;
      if(!PaperWrite(paperFrozen)) { paperRetry=TimeGMT()+10; return; }
      PaperApply(paperFrozen); paperPending=false; paperRestored=true;
   }
   MqlTick q;
   if(!FreshQuote(q)) { paperHealth="报价断流，等待恢复；缺失过程不补算收益"; return; }
   if(paperLastTick>0 && q.time_msc<=paperLastTick) return;
   if(paperRestored || (paperLastTick>0 && q.time_msc-paperLastTick>5000))
   {
      if(!PaperInvalidate(q)) return;
      paperLastTick=q.time_msc; paperHealth="缺失过程已排除，等待下一次完整机会"; return;
   }
   paperLastTick=q.time_msc;
   // 已有模拟单的退出不受消息中断、入场暂停影响。
   for(int i=ArraySize(paperTrades)-1;i>=0;i--)
   {
      double delta=paperTrades[i].sign*((paperTrades[i].sign>0 ? q.bid : q.ask)-paperTrades[i].entry);
      paperTrades[i].mfe=MathMax(paperTrades[i].mfe,delta);
      paperTrades[i].mae=MathMin(paperTrades[i].mae,delta);
      double exit=0; string why=PaperExit(paperTrades[i],q,exit); if(why=="") continue;
      PaperEvent e; PaperFromTrade(paperTrades[i],q,e); e.kind="CLOSE"; e.exit=exit; e.why=why;
      if(!OrderCalcProfit(e.sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,e.volume,e.entry,e.exit,e.gross))
      { paperRestored=true; paperHealth="收益换算失败，下次将排除不完整样本"; return; }
      e.fee=模拟每手往返费用*e.volume;
      if(!PaperEmit(e)) return;
   }
   for(int i=ArraySize(paperVisits)-1;i>=0;i--)
   {
      if(PaperAreaBusy(paperVisits[i].arm,paperVisits[i].level)) { paperVisits[i].away=0; continue; }
      if(MathAbs((q.bid+q.ask)/2-paperVisits[i].level)<REARM_DISTANCE) { paperVisits[i].away=0; continue; }
      if(paperVisits[i].away==0) paperVisits[i].away=q.time;
      if(q.time-paperVisits[i].away<REARM_SECONDS) continue;
      PaperEvent e; ZeroMemory(e); e.kind="REARM"; e.arm=paperVisits[i].arm;
      e.level=paperVisits[i].level; e.msc=q.time_msc; e.why="离开4点至少5秒，允许新机会";
      if(!PaperEmit(e)) return;
   }
   for(int arm=0;arm<2;arm++)
   {
      if(PaperCount(arm)>=最大同时持仓) { paperStatus[arm]="模拟持仓已达上限"; continue; }
      int best=-1,side=0,closest=-1; double nearest=DBL_MAX;
      paperStatus[arm]=AIChannelReady() ? "等待有效点位" : "消息未同步，暂停新模拟";
      for(int i=0;i<ArraySize(aiPlans);i++)
      {
         int sign=arm==0 ? PlanSign(i) : ObserverDirection(i);
         string status=UnifiedEntryStatus(i,q,arm==0 ? 0 : 2,false);
         double distance=MathAbs(aiPlans[i].level-(q.bid+q.ask)/2);
         if(distance<nearest) { nearest=distance; closest=i; paperStatus[arm]=status; }
         if(status!="触价候选" && status!="区间反应候选") continue;
         if(sign==0 || PaperAreaBusy(arm,aiPlans[i].level) || PaperVisitIndex(arm,aiPlans[i].level)>=0)
         { if(distance<=nearest) paperStatus[arm]="同次机会已尝试，等离开后再来"; continue; }
         if(best<0 || aiPlans[i].priority>aiPlans[best].priority ||
            (aiPlans[i].priority==aiPlans[best].priority && aiPlans[i].confirmed>aiPlans[best].confirmed))
         { best=i; side=sign; }
      }
      if(best<0)
      {
         // 只记录临近点位的等待原因，每组每分钟最多一条，避免每秒刷盘。
         if(closest>=0 && nearest<=3 && paperDecisionMinute[arm]!=q.time_msc/60000)
         {
            PaperEvent e; ZeroMemory(e); e.kind="WAIT"; e.arm=arm; e.msc=q.time_msc;
            e.level=aiPlans[closest].level; e.source=aiPlans[closest].id; e.why=paperStatus[arm];
            if(!PaperEmit(e)) return;
         }
         continue;
      }
      bool conflict=false;
      for(int i=0;i<ArraySize(aiPlans);i++)
      {
         int sign=arm==0 ? PlanSign(i) : ObserverDirection(i);
         if(i==best || sign!=-side || aiPlans[i].priority!=aiPlans[best].priority) continue;
         string status=UnifiedEntryStatus(i,q,arm==0 ? 0 : 2,false);
         if(status=="触价候选" || status=="区间反应候选") conflict=true;
      }
      if(conflict) { paperStatus[arm]="同优先级意见冲突，等待新消息或新行情"; continue; }
      PaperEvent e; ZeroMemory(e); e.kind="OPEN"; e.arm=arm; e.sign=side; e.msc=q.time_msc;
      e.bar=arm==1 ? entryObservations[ArraySize(entryObservations)-1].bar : 0;
      e.level=aiPlans[best].level; e.volume=每次开仓手数;
      e.entry=Align((side>0 ? q.ask : q.bid)+side*模拟单边滑点价格,side);
      e.source=aiPlans[best].id+"/"+aiPlans[best].source+"/"+IntegerToString((long)aiPlans[best].confirmed);
      e.why=arm==0 ? "碰价基准：有效点位接近后模拟入场" : "新判断：消息位置与已收盘K线反应一致";
      if(arm==0) e.why+="；B当时："+UnifiedEntryStatus(best,q,2,false);
      if(!PaperEmit(e)) return;
      paperStatus[arm]="已模拟"+(side>0 ? "买入 " : "卖出 ")+DoubleToString(e.entry,_Digits);
   }
   paperHealth="自动比较运行中 · 无需人工处理";
}
void PaperPanel()
{
   UIText("自动试做 · 成绩单",16,94,310,17,UI_TEXT);
   UIButton("查看判断明细",420,94,124,205);
   UIText(tradeMode ? "模拟不发单；原EA仍处于交易模式" : "原EA处于观察模式；两组模拟仍自动运行",
      16,126,528,10,tradeMode ? UI_WARN : UI_ACCENT);
   UICard(12,155,536,55,UI_ROW);
   UIText(paperHealth,26,163,508,10,UI_TEXT);
   UIText("相同0.02手 · TP5/SL10 · 最长60分钟 · 各自独立计算",26,188,508,9,UI_MUTED);
   for(int arm=0;arm<2;arm++)
   {
      int x=12+arm*272;
      UICard(x,222,264,220,UI_ROW);
      UIText(arm==0 ? "A · 碰价就尝试" : "B · 等价格给出反应",x+14,235,236,12,UI_TEXT);
      UIText(DoubleToString(paperScores[arm].net,2)+" "+AccountInfoString(ACCOUNT_CURRENCY),x+14,268,236,22,UI_ACCENT);
      UIText("已结束 "+IntegerToString(paperScores[arm].closed)+" 单 / 进行中 "+IntegerToString(PaperCount(arm))+" 单",x+14,308,236,10,UI_MUTED);
      UIText("盈利 "+IntegerToString(paperScores[arm].wins)+" / 亏损 "+IntegerToString(paperScores[arm].losses),x+14,335,236,10,UI_MUTED);
      UIText("已实现最大回撤 "+DoubleToString(paperScores[arm].drawdown,2),x+14,362,236,9,UI_MUTED);
      UIText("过程缺失、不计结果 "+IntegerToString(paperScores[arm].invalid)+" 单",x+14,389,236,9,UI_WARN);
      UIText("共尝试 "+IntegerToString(paperScores[arm].opened)+" 单",x+14,415,236,9,UI_DIM);
   }
   UIText("A："+paperStatus[0],16,455,528,9,UI_MUTED);
   UIText("B："+paperStatus[1],16,479,528,9,UI_MUTED);
   UIText("最近结果："+paperLastResult,16,510,528,9,UI_TEXT);
   UIText(模拟每手往返费用>0 ? "金额已扣设置费用；不含隔夜费，仍是模拟估算" :
      "费用尚未配置：金额未扣佣金，不可当作净收益",16,541,528,9,UI_WARN);
   UIText("每秒采样Bid/Ask；可能漏掉秒内触价，不等同真实成交。",16,566,528,8.5,UI_DIM);
   UIText("账本按规则/费用分开；重启恢复累计成绩，不猜缺失过程。",16,590,528,8.5,UI_DIM);
   UIText("新判断仍在验证，暂不接管实盘。",16,618,528,9,UI_MUTED);
   panelCanvas.Update();
}
void StopPaper()
{
   if(paperPending && paperFile!=INVALID_HANDLE && PaperWrite(paperFrozen))
   { PaperApply(paperFrozen); paperPending=false; }
   if(paperFile!=INVALID_HANDLE) { FileClose(paperFile); paperFile=INVALID_HANDLE; }
}
