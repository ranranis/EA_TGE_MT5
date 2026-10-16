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
#define PAPER_ARMS 5
int paperDetailArm=0;
string PaperName(const int arm)
{
   if(arm==0) return "A 碰价基准";
   if(arm==1) return "B 区间反弹";
   if(arm==2) return "C 单点收回";
   if(arm==3) return "D 顺势回踩";
   return "E 突破回踩";
}
// C/D/E的纯收盘判定，所有bars均为已完成K线，trend为当时已缓存的M5趋势。
int PaperReaction(const int arm,const double level,const int messageSide,const MqlRates &bars[],
                  const double volatility,const int trendValue)
{
   if(ArraySize(bars)<3 || volatility<=0 || level<=0) return 0;
   MqlRates b=bars[0];
   double buffer=MathMax(TickSize()*2,volatility*观察收回ATR倍数);
   if(b.high-b.low>volatility*3) return 0;
   int sign=messageSide!=0 ? messageSide : (b.close>level ? 1 : -1);
   if(arm==4)
   {
      // 突破K必须先完成；下一根回踩K也必须完成。不用同根高低猜先后。
      bool up=bars[2].close<=level && bars[1].close>level+buffer;
      bool down=bars[2].close>=level && bars[1].close<level-buffer;
      sign=up ? 1 : down ? -1 : 0;
      if(sign==0 || messageSide*sign<0) return 0;
   }
   if(arm==3 && trendValue!=sign) return 0;
   if(sign*(b.close-b.open)<volatility*0.10 || sign*(b.close-level)<buffer ||
      MathAbs(b.close-level)>TEACHER_BAND+buffer) return 0;
   if(sign>0 && (b.low<level-TEACHER_BAND || b.low>level+TEACHER_BAND)) return 0;
   if(sign<0 && (b.high>level+TEACHER_BAND || b.high<level-TEACHER_BAND)) return 0;
   return sign;
}
int PaperDirection(const int arm,const int i)
{
   if(arm==0) return PlanSign(i);
   if(arm==1) return ObserverDirection(i);
   return PaperReaction(arm,aiPlans[i].level,aiPlans[i].sign,adaptiveBars,adaptiveATR,adaptiveTrend);
}
string PaperReactionStatus(const int i,const MqlTick &q,const int arm,datetime after)
{
   if(!AdaptiveMarketFresh() || ArraySize(adaptiveBars)<3) return "等待完整收盘行情";
   MqlRates b=adaptiveBars[0];
   long offset=(long)MathRound((double)(TimeCurrent()-TimeGMT())/3600.0)*3600;
   datetime evidenceBar=arm==4 ? adaptiveBars[2].time : b.time;
   if(aiPlans[i].confirmed+offset>evidenceBar || aiPlans[i].available+offset>evidenceBar)
      return "当时尚未收到该点位版本，等待新的反应";
   if(q.time<b.time+60 || q.time>=b.time+120) return "等待新的一分钟行情";
   if(TimeCurrent()<adaptiveRecoverUntil) after=(datetime)MathMax(after,adaptiveShockUntil);
   if(after>0 && evidenceBar<after) return "等待消息或冲击结束后的新反应";
   int sign=PaperDirection(arm,i);
   if(sign==0) return arm==4 ? "等待突破完成后再回踩" : arm==3 ? "等待顺势回踩并收回" : "等待点位收回，暂不入场";
   double entry=sign>0 ? q.ask : q.bid;
   if(sign*(entry-aiPlans[i].level)<=0 ||
      MathAbs(entry-aiPlans[i].level)>TEACHER_BAND+MathMax(TickSize()*2,adaptiveATR*观察收回ATR倍数))
      return "价格已离开反应区域，不追价";
   return "区间反应候选";
}
PaperTrade paperTrades[];
PaperVisit paperVisits[];
PaperScore paperScores[PAPER_ARMS];
long paperSeq=0,paperLastTick=0;
int paperFile=INVALID_HANDLE;
bool paperReady=false,paperPending=false,paperRestored=false;
datetime paperRetry=0;
PaperEvent paperFrozen;
string paperPolicy="",paperFilePath="",paperLastLine="",paperHealth="自动模拟尚未初始化";
string paperStatus[PAPER_ARMS],paperLastResult="尚无模拟平仓";
long paperDecisionMinute[PAPER_ARMS];

string PaperClean(string text)
{
   StringReplace(text,"\t"," "); StringReplace(text,"\r"," "); StringReplace(text,"\n"," "); return text;
}
string PaperPolicy()
{
   // 改变比较规则或费用会自动分开账本，不能把不同假设的成绩相加。
   return "P2/five-arms-v1.72/tp5/sl10/hold60/lot"+DoubleToString(每次开仓手数,8)+"/cap"+IntegerToString(最大同时持仓)+
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
   return e.seq>0 && e.msc>0 && e.arm>=0 && e.arm<PAPER_ARMS &&
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

// 只读明细缓存：由已提交事件重建，保持原P1账本和策略身份兼容。
struct PaperDetail { PaperEvent entryEvent, endEvent; };
PaperDetail paperDetails[];
bool paperShowDetails=false;
long paperSelectedId=0;
bool paperChartDirty=true;
int PaperDetailFind(const long id)
{
   for(int i=0;i<ArraySize(paperDetails);i++)
      if(paperDetails[i].entryEvent.id==id) return i;
   return -1;
}
void PaperRemember(const PaperEvent &e)
{
   paperChartDirty=true;
   if(e.kind=="OPEN")
   {
      int count=0,oldest=-1;
      for(int i=0;i<ArraySize(paperDetails);i++)
         if(paperDetails[i].entryEvent.arm==e.arm)
         {
            count++;
            if(oldest<0 && paperDetails[i].endEvent.kind!="") oldest=i;
         }
      // 每组最多保留200笔；绝不丢弃尚未结束的模拟仓。
      if(count>=200 && oldest>=0)
      {
         for(int j=oldest+1;j<ArraySize(paperDetails);j++) paperDetails[j-1]=paperDetails[j];
         ArrayResize(paperDetails,ArraySize(paperDetails)-1);
      }
      int n=ArraySize(paperDetails); ArrayResize(paperDetails,n+1);
      paperDetails[n].entryEvent=e; ZeroMemory(paperDetails[n].endEvent);
   }
   else if(e.kind=="CLOSE" || e.kind=="GAP")
   {
      int i=PaperDetailFind(e.id);
      if(i>=0) paperDetails[i].endEvent=e;
   }
}
int PaperSelected()
{
   int selected=PaperDetailFind(paperSelectedId);
   if(selected>=0 && paperDetails[selected].entryEvent.arm==paperDetailArm) return selected;
   for(int i=ArraySize(paperDetails)-1;i>=0;i--)
      if(paperDetails[i].entryEvent.arm==paperDetailArm) return i;
   return -1;
}
void PaperDetailAction(const int action)
{
   if(action==215)
   {
      paperShowDetails=!paperShowDetails;
      if(!paperShowDetails) PaperClearReviewChart(); else paperChartDirty=true;
      return;
   }
   if(action==219) { PaperClearReviewChart(); ReviewReturnLive(); return; }
   int at=PaperSelected(); if(at<0) return;
   if(action==218)
   {
      reviewNavTime=(datetime)(paperDetails[at].entryEvent.msc/1000);
      reviewNavAttempts=0; ReviewNavigate(); return;
   }
   int step=action==216 ? -1 : 1;
   for(int i=at+step;i>=0 && i<ArraySize(paperDetails);i+=step)
      if(paperDetails[i].entryEvent.arm==paperDetailArm)
      { paperSelectedId=paperDetails[i].entryEvent.id; paperChartDirty=true; break; }
}
string PaperMoment(const long msc)
{
   return TimeToString((datetime)(msc/1000),TIME_DATE|TIME_SECONDS);
}
string PaperReviewPrefix()
{
   return VIEW+"PAPER_REVIEW_";
}
void PaperClearReviewChart()
{
   string objectPrefix=PaperReviewPrefix();
   for(int i=ObjectsTotal(0,0)-1;i>=0;i--)
   {
      string name=ObjectName(0,i,0);
      if(StringFind(name,objectPrefix)==0) ObjectDelete(0,name);
   }
   paperChartDirty=true;
   ChartRedraw(0);
}
void PaperReviewArrow(const string name,const datetime at,const double price,
                      const int code,const color ink,const int width,const string tip)
{
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_ARROW,0,at,price)) return;
   ObjectMove(0,name,0,at,price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,code);
   ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,0);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
}
void PaperReviewLine(const string name,const datetime t1,const double p1,
                     const datetime t2,const double p2,const color ink,const int width,
                     const ENUM_LINE_STYLE style,const string tip)
{
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2)) return;
   ObjectMove(0,name,0,t1,p1); ObjectMove(0,name,1,t2,p2);
   ObjectSetInteger(0,name,OBJPROP_COLOR,ink);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false);
   ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,0);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,tip);
}
void PaperDrawReviewChart()
{
   if(!paperShowDetails || !paperChartDirty) return;
   PaperClearReviewChart();
   paperChartDirty=false;
   string objectPrefix=PaperReviewPrefix();
   for(int i=0;i<ArraySize(paperDetails);i++)
   {
      PaperEvent e=paperDetails[i].entryEvent, end=paperDetails[i].endEvent;
      if(e.arm!=paperDetailArm || e.msc<=0 || e.entry<=0) continue;
      bool selected=e.id==paperSelectedId || (paperSelectedId==0 && i==PaperSelected());
      int width=selected ? 3 : 1;
      color entryInk=e.sign>0 ? C'0,108,180' : C'190,88,35';
      color exitInk=e.sign>0 ? C'0,145,110' : C'175,55,115';
      string base=objectPrefix+IntegerToString(e.id)+"_";
      string direction=e.sign>0 ? "模拟多单" : "模拟空单";
      PaperReviewArrow(base+"IN",(datetime)(e.msc/1000),e.entry,e.sign>0 ? 233 : 234,
                       entryInk,width,direction+" 入场 #"+IntegerToString(e.id)+" · "+PaperMoment(e.msc));
      if(end.kind=="CLOSE" && end.msc>e.msc && end.exit>0)
      {
         PaperReviewLine(base+"PATH",(datetime)(e.msc/1000),e.entry,(datetime)(end.msc/1000),end.exit,
                         end.gross-end.fee>=0 ? C'0,145,110' : C'190,88,35',width,
                         end.gross-end.fee>=0 ? STYLE_SOLID : STYLE_DASH,
                         direction+" 入场→出场 #"+IntegerToString(e.id));
         PaperReviewArrow(base+"OUT",(datetime)(end.msc/1000),end.exit,e.sign>0 ? 234 : 233,
                          exitInk,width,direction+" 出场 #"+IntegerToString(e.id)+" · "+PaperMoment(end.msc)+
                          " · "+DoubleToString(end.gross-end.fee,2));
      }
   }
   ChartRedraw(0);
}
void PaperDetailPanel()
{
   PaperDrawReviewChart();
   UIText("模拟单明细 · "+PaperName(paperDetailArm),16,94,340,16,UI_TEXT);
   UIButton("返回成绩单",420,94,124,215);
   for(int arm=0;arm<PAPER_ARMS;arm++)
      UIButton(PaperName(arm),12+arm*108,132,104,210+arm,paperDetailArm==arm);
   int at=PaperSelected(),count=0,ordinal=0;
   for(int i=0;i<ArraySize(paperDetails);i++)
      if(paperDetails[i].entryEvent.arm==paperDetailArm)
      { count++; if(i==at) ordinal=count; }
   UIText("本组 "+IntegerToString(ordinal)+"/"+IntegerToString(count)+" · 按开仓时间，最新在后 · 券商时间",16,172,528,9,UI_MUTED);
   if(at<0)
   {
      UIText("本组尚无模拟开单记录",26,226,508,14,UI_TEXT);
      UIText(paperStatus[paperDetailArm],26,265,508,10,UI_MUTED);
      UIText("五组继续自动运行；有模拟开单后这里会显示。",26,308,508,9,UI_DIM);
      panelCanvas.Update(); return;
   }
   PaperEvent e=paperDetails[at].entryEvent, end=paperDetails[at].endEvent;
   bool closed=end.kind=="CLOSE",gap=end.kind=="GAP";
   int live=PaperFind(e.id);
   double mfe=live>=0 ? paperTrades[live].mfe : end.mfe;
   double mae=live>=0 ? paperTrades[live].mae : end.mae;
   UICard(12,202,536,346,UI_ROW);
   UIText((e.sign>0 ? "做多 BUY" : "做空 SELL")+" · #"+IntegerToString(e.id),26,214,300,13,UI_TEXT);
   UIText(closed ? "已平仓" : gap ? "过程缺失" : "模拟持仓中",350,216,180,11,gap ? UI_WARN : UI_ACCENT,true);
   UIText("点位 "+DoubleToString(e.level,_Digits)+" · "+DoubleToString(e.volume,2)+"手",26,246,508,11,UI_TEXT);
   UIText("开仓 "+PaperMoment(e.msc)+"   @ "+DoubleToString(e.entry,_Digits),26,278,508,10,UI_TEXT);
   UIText("结束 "+(end.kind!="" ? PaperMoment(end.msc) : "尚未结束")+
      (closed ? "   @ "+DoubleToString(end.exit,_Digits) : ""),26,307,508,10,UI_MUTED);
   UIText("SL "+DoubleToString(e.entry-e.sign*10,_Digits)+"   TP "+DoubleToString(e.entry+e.sign*5,_Digits)+
      "   最长60分钟",26,336,508,10,UI_MUTED);
   UIText(closed ? "结果 "+DoubleToString(end.gross-end.fee,2)+" "+AccountInfoString(ACCOUNT_CURRENCY)+
      " · 费用 "+DoubleToString(end.fee,2) : gap ? "结果不计入盈亏，不推测缺失过程" : "结果待平仓结算",26,365,508,12,UI_TEXT);
   UIText("最大顺行 "+DoubleToString(mfe,2)+" / 最大逆行 "+DoubleToString(mae,2)+"（采样价格差）",26,398,508,9,UI_MUTED);
   UIText("入场原因："+e.why,26,428,508,9,UI_TEXT);
   UIText("结束原因："+(end.kind!="" ? end.why : "等待止盈、止损或时间退出"),26,458,508,9,UI_MUTED);
   UIText("判断K线："+(e.bar>0 ? TimeToString(e.bar,TIME_DATE|TIME_MINUTES) : "碰价入场，无收线条件"),26,487,508,9,UI_DIM);
   UIText("来源："+e.source,26,516,508,8,UI_DIM);
   UIButton("上一笔",12,562,92,216); UIButton("下一笔",112,562,92,217);
   UIButton("定位入场K线",212,562,148,218); UIButton("返回实时",368,562,176,219);
   UIText("仅模拟 · 每组显示最近200笔；完整记录保留在原账本",16,601,528,9,UI_MUTED);
   UIText(reviewNotice!="" ? reviewNotice : "费用0表示未配置佣金；模拟金额不含隔夜费。",16,628,528,8,UI_DIM);
   panelCanvas.Update();
}

void PaperApply(const PaperEvent &e)
{
   paperSeq=e.seq;
   PaperRemember(e);
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
   paperLastResult=PaperName(e.arm)+ " · "+e.why+" · "+
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
   for(int arm=0;arm<PAPER_ARMS;arm++)
   {
      if(PaperCount(arm)>=最大同时持仓) { paperStatus[arm]="模拟持仓已达上限"; continue; }
      int best=-1,side=0,closest=-1; double nearest=DBL_MAX;
      paperStatus[arm]=AIChannelReady() ? "等待有效点位" : "消息未同步，暂停新模拟";
      for(int i=0;i<ArraySize(aiPlans);i++)
      {
         int sign=PaperDirection(arm,i);
         string status=UnifiedEntryStatus(i,q,arm==0 ? 0 : arm+1,false);
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
         int sign=PaperDirection(arm,i);
         if(i==best || sign!=-side || aiPlans[i].priority!=aiPlans[best].priority) continue;
         string status=UnifiedEntryStatus(i,q,arm==0 ? 0 : arm+1,false);
         if(status=="触价候选" || status=="区间反应候选") conflict=true;
      }
      if(conflict) { paperStatus[arm]="同优先级意见冲突，等待新消息或新行情"; continue; }
      PaperEvent e; ZeroMemory(e); e.kind="OPEN"; e.arm=arm; e.sign=side; e.msc=q.time_msc;
      e.bar=arm==0 ? 0 : arm==1 ? entryObservations[ArraySize(entryObservations)-1].bar : adaptiveBars[0].time;
      e.level=aiPlans[best].level; e.volume=每次开仓手数;
      e.entry=Align((side>0 ? q.ask : q.bid)+side*模拟单边滑点价格,side);
      e.source=aiPlans[best].id+"/"+aiPlans[best].source+"/"+IntegerToString((long)aiPlans[best].confirmed);
      e.why=PaperName(arm)+"：按本组规则自动模拟入场";
      if(arm==0) e.why+="；B当时："+UnifiedEntryStatus(best,q,2,false);
      if(!PaperEmit(e)) return;
      paperStatus[arm]="已模拟"+(side>0 ? "买入 " : "卖出 ")+DoubleToString(e.entry,_Digits);
   }
   paperHealth="自动比较运行中 · 无需人工处理";
}
void PaperPanel()
{
   if(paperShowDetails) { PaperDetailPanel(); return; }
   UIText("自动试做 · 五组比较",16,94,310,17,UI_TEXT);
   UIButton("查看判断明细",420,94,124,205);
   UIText(tradeMode ? "模拟不发单；原EA仍处于交易模式" : "原EA处于观察模式；五组模拟自动运行",
      16,126,528,10,tradeMode ? UI_WARN : UI_ACCENT);
   UIText(paperHealth,16,155,528,9,UI_TEXT);
   UIText(replayHealth,16,179,528,9,UI_MUTED);
   UIText("各组相同0.02手 / TP5 SL10 / 最长60分钟",16,203,528,9,UI_DIM);
   UIText("点选策略查看原因",16,233,176,9,UI_MUTED);
   UIText("结果 / "+AccountInfoString(ACCOUNT_CURRENCY),198,233,88,9,UI_MUTED);
   UIText("完成/持有",290,233,80,9,UI_MUTED);
   UIText("赢/亏",374,233,65,9,UI_MUTED);
   UIText("回撤 / 缺失",444,233,100,9,UI_MUTED);
   for(int arm=0;arm<PAPER_ARMS;arm++)
   {
      int y=255+arm*41;
      UICard(12,y,536,36,UI_ROW);
      UIButton(PaperName(arm),16,y+4,172,210+arm,paperDetailArm==arm);
      UIText(DoubleToString(paperScores[arm].net,2),198,y+8,88,11,UI_ACCENT);
      UIText(IntegerToString(paperScores[arm].closed)+"/"+IntegerToString(PaperCount(arm)),290,y+9,80,9,UI_TEXT);
      UIText(IntegerToString(paperScores[arm].wins)+"/"+IntegerToString(paperScores[arm].losses),374,y+9,65,9,UI_TEXT);
      UIText(DoubleToString(paperScores[arm].drawdown,1)+" / "+IntegerToString(paperScores[arm].invalid),444,y+9,100,9,UI_MUTED);
   }
   UIText(PaperName(paperDetailArm)+"："+paperStatus[paperDetailArm],16,472,528,9,UI_TEXT);
   UIButton("查看本组模拟单",16,501,190,215);
   UIText("可翻页 / 定位入场K线",220,506,324,9,UI_MUTED);
   UIText(模拟每手往返费用>0 ? "已扣设置费用，不含隔夜费；仍为模拟估算" :
      "费用尚未配置：金额未扣佣金，不可当作净收益",16,533,528,9,UI_WARN);
   UIText("每秒采样试做；历史归档另存收到的报价，不保证完整逐笔。",16,560,528,8.5,UI_DIM);
   UIText("缺失过程不计盈亏；旧两组成绩保留在原账本。",16,585,528,8.5,UI_DIM);
   UIText("所有组均为待验证假设，暂不接管实盘。",16,614,528,9,UI_MUTED);
   panelCanvas.Update();
}
void StopPaper()
{
   if(paperPending && paperFile!=INVALID_HANDLE && PaperWrite(paperFrozen))
   { PaperApply(paperFrozen); paperPending=false; }
   if(paperFile!=INVALID_HANDLE) { FileClose(paperFile); paperFile=INVALID_HANDLE; }
}
