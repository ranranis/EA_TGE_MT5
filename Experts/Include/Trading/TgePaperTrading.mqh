// P1：独立虚拟账本；仅OnTimer采样，无交易请求，不触碰真实pending/消费/持仓状态。
struct PaperTrade
{
   long id,opened,checked;
   bool recovering;
   datetime retry;
   datetime bar;
   int arm,sign;
   double level,entry,volume,mfe,mae;
   string source;
};
struct PaperVisit { int arm; double level; datetime away; };
struct PaperScore { int opened,closed,wins,losses,invalid,repaired; double net,peak,drawdown; };
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
struct PaperSettlement { long id,msc; int arm; double net; };
PaperSettlement paperSettlements[];
PaperTrade paperRepair;
long paperRepairId=0;
int paperRepairCursor=0;
datetime paperRepairRetry=0;
int paperHistoryHandle=INVALID_HANDLE;
long paperHistoryId=0,paperHistoryFrom=0,paperHistoryUntil=0;
datetime paperHistoryStarted=0;
void PaperReleaseHistory()
{
   if(paperHistoryHandle!=INVALID_HANDLE) IndicatorRelease(paperHistoryHandle);
   paperHistoryHandle=INVALID_HANDLE; paperHistoryId=0;
}
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
      (e.kind=="OPEN" || e.kind=="CLOSE" || e.kind=="GAP" || e.kind=="REPAIR" || e.kind=="REARM" || e.kind=="WAIT");
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
   if(e.kind=="REPAIR")
   {
      int d=PaperDetailFind(e.id);
      return d>=0 && paperDetails[d].endEvent.kind=="GAP" &&
         paperDetails[d].entryEvent.arm==e.arm && paperDetails[d].entryEvent.sign==e.sign &&
         paperDetails[d].entryEvent.entry==e.entry && paperDetails[d].entryEvent.volume==e.volume &&
         e.msc>=paperDetails[d].entryEvent.msc && e.exit>0 && e.fee>=0;
   }
   int i=PaperFind(e.id);
   if(i<0 || paperTrades[i].arm!=e.arm || paperTrades[i].sign!=e.sign ||
      paperTrades[i].entry!=e.entry || paperTrades[i].volume!=e.volume || e.msc<paperTrades[i].opened) return false;
   return e.kind=="GAP" || (e.kind=="CLOSE" && e.exit>0 && e.fee>=0);
}

// 只读明细缓存：由已提交事件重建，保持原P1账本和策略身份兼容。
struct PaperDetail { PaperEvent entryEvent, endEvent; };
PaperDetail paperDetails[];
bool paperShowDetails=false;
int paperListPage=0;
const int PAPER_PAGE_SIZE=5;
long paperRowIds[5],paperReviewId=0,paperPressedId=0;
string paperReviewStamp="";
int PaperDetailFind(const long id)
{
   for(int i=0;i<ArraySize(paperDetails);i++)
      if(paperDetails[i].entryEvent.id==id) return i;
   return -1;
}
void PaperRemember(const PaperEvent &e)
{
   if(e.kind=="OPEN")
   {
      int count=0,oldest=-1;
      for(int i=0;i<ArraySize(paperDetails);i++)
         if(paperDetails[i].entryEvent.arm==e.arm)
         {
            count++;
            if(oldest<0 && paperDetails[i].endEvent.kind!="" && paperDetails[i].entryEvent.id!=paperRepairId) oldest=i;
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
   else if(e.kind=="CLOSE" || e.kind=="GAP" || e.kind=="REPAIR")
   {
      int i=PaperDetailFind(e.id);
      if(i>=0) paperDetails[i].endEvent=e;
   }
}
int PaperDetailCount()
{
   int count=0;
   for(int i=0;i<ArraySize(paperDetails);i++) if(paperDetails[i].entryEvent.arm==paperDetailArm && paperDetails[i].endEvent.kind!="GAP") count++;
   return count;
}
void PaperClearReview()
{
   if(paperReviewId>0)
   {
      ObjectsDeleteAll(0,VIEW+"PAPER_REVIEW_");
      ReviewReturnLive();
   }
   paperReviewId=0; paperPressedId=0; paperReviewStamp="";
}
void PaperSyncReview()
{
   if(paperReviewId<=0) return;
   int i=PaperDetailFind(paperReviewId);
   if(i<0 || paperDetails[i].endEvent.kind=="GAP") { PaperClearReview(); return; }
   PaperEvent e=paperDetails[i].entryEvent,end=paperDetails[i].endEvent;
   string stamp=IntegerToString(e.id)+"|"+end.kind+"|"+IntegerToString(end.msc);
   if(stamp==paperReviewStamp) return;
   ObjectsDeleteAll(0,VIEW+"PAPER_REVIEW_");
   string entry=VIEW+"PAPER_REVIEW_IN",exit=VIEW+"PAPER_REVIEW_OUT";
   ReviewMark(entry,(datetime)(e.msc/1000),e.entry,"入",C'46,99,142');
   ObjectSetString(0,entry,OBJPROP_FONT,"Microsoft YaHei");
   ObjectSetInteger(0,entry,OBJPROP_FONTSIZE,9);
   if(end.kind=="CLOSE" || end.kind=="REPAIR")
   {
      ReviewMark(exit,(datetime)(end.msc/1000),end.exit,"出",C'151,103,45');
      ObjectSetString(0,exit,OBJPROP_FONT,"Microsoft YaHei");
      ObjectSetInteger(0,exit,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,exit,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
      string path=VIEW+"PAPER_REVIEW_PATH";
      ObjectCreate(0,path,OBJ_TREND,0,(datetime)(e.msc/1000),e.entry,(datetime)(end.msc/1000),end.exit);
      ObjectSetInteger(0,path,OBJPROP_RAY_RIGHT,false); ObjectSetInteger(0,path,OBJPROP_RAY_LEFT,false);
      ObjectSetInteger(0,path,OBJPROP_COLOR,C'107,116,125'); ObjectSetInteger(0,path,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,path,OBJPROP_WIDTH,1); ObjectSetInteger(0,path,OBJPROP_BACK,true);
      ObjectSetInteger(0,path,OBJPROP_SELECTABLE,false);
   }
   paperReviewStamp=stamp; ChartRedraw(0);
}
void PaperDetailAction(const int action)
{
   if(action==218) { PaperClearReview(); return; }
   if(action>=220 && action<220+PAPER_PAGE_SIZE)
   {
      long id=paperRowIds[action-220];
      // 刷新导致行号换单时，不把按下的旧行误当成另一单。
      if(id<=0 || (paperPressedId>0 && id!=paperPressedId)) { paperPressedId=0; return; }
      if(id==paperReviewId) { PaperClearReview(); return; }
      PaperClearReview(); ReviewReturnLive(false);
      int i=PaperDetailFind(id); if(i<0 || paperDetails[i].endEvent.kind=="GAP") return;
      paperReviewId=id; PaperSyncReview();
      reviewNavTime=(datetime)(paperDetails[i].entryEvent.msc/1000); reviewNavAttempts=0; ReviewNavigate();
      return;
   }
   PaperClearReview();
   if(action==215) { paperShowDetails=!paperShowDetails; paperListPage=0; return; }
   int last=MathMax(0,(PaperDetailCount()-1)/PAPER_PAGE_SIZE);
   if(action==216) paperListPage=MathMax(0,paperListPage-1);
   if(action==217) paperListPage=MathMin(last,paperListPage+1);
}
string PaperMoment(const long msc)
{
   return TimeToString((datetime)(msc/1000),TIME_DATE|TIME_SECONDS);
}
void PaperDetailPanel()
{
   UIText("模拟单列表 · "+PaperName(paperDetailArm),16,94,340,16,UI_TEXT);
   UIButton("返回成绩单",420,94,124,215);
   for(int arm=0;arm<PAPER_ARMS;arm++)
      UIButton(PaperName(arm),12+arm*108,132,104,210+arm,paperDetailArm==arm);
   int count=PaperDetailCount(),pages=MathMax(1,(count+PAPER_PAGE_SIZE-1)/PAPER_PAGE_SIZE);
   paperListPage=MathMax(0,MathMin(paperListPage,pages-1));
   UIText("有效 "+IntegerToString(count)+" 笔 · 点击行看入/出 · "+IntegerToString(paperListPage+1)+"/"+IntegerToString(pages)+" 页 · 券商时间",16,172,528,9,UI_MUTED);
   int seen=0,shown=0; ArrayInitialize(paperRowIds,0);
   for(int i=ArraySize(paperDetails)-1;i>=0 && shown<PAPER_PAGE_SIZE;i--)
   {
      PaperEvent e=paperDetails[i].entryEvent,end=paperDetails[i].endEvent;
      if(e.arm!=paperDetailArm || end.kind=="GAP") continue;
      if(seen++<paperListPage*PAPER_PAGE_SIZE) continue;
      bool closed=end.kind=="CLOSE" || end.kind=="REPAIR",gap=end.kind=="GAP";
      int live=PaperFind(e.id),y=198+shown*72;
      string status=closed ? (end.kind=="REPAIR" ? "已补算" : "已平仓") : gap ? "旧缺失·待补齐" :
         live>=0 && paperTrades[live].recovering ? "核对历史中" : "模拟持仓";
      double net=end.gross-end.fee;
      string result=closed ? (net>0 ? "+" : "")+DoubleToString(net,2)+" "+AccountInfoString(ACCOUNT_CURRENCY) : "—";
      if(!closed && !gap && live>=0 && !paperTrades[live].recovering)
      {
         MqlTick q; double floating=0;
         if(FreshQuote(q) && OrderCalcProfit(e.sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,e.volume,e.entry,e.sign>0 ? q.bid : q.ask,floating))
            result="浮动 "+(floating>0 ? "+" : "")+DoubleToString(floating,2);
      }
      UICard(12,y,536,66,paperReviewId==e.id ? UI_HEADER : UI_ROW);
       paperRowIds[shown]=e.id;
       int hit=ArraySize(uiHits); ArrayResize(uiHits,hit+1);
       uiHits[hit].x=12; uiHits[hit].y=y; uiHits[hit].w=536; uiHits[hit].h=66; uiHits[hit].action=220+shown;
      UIText((e.sign>0 ? "BUY" : "SELL")+" #"+IntegerToString(e.id)+" · "+DoubleToString(e.volume,2)+"手",24,y+6,230,10,UI_TEXT);
      UIText(status,256,y+7,128,9,gap ? UI_WARN : UI_MUTED);
      UIText(result,382,y+5,150,11,closed ? (net>0 ? UI_GAIN : net<0 ? UI_LOSS : UI_MUTED) : UI_TEXT,true);
      UIText("入 "+DoubleToString(e.entry,_Digits)+" · "+PaperMoment(e.msc),24,y+27,306,9,UI_TEXT);
      UIText("点位 "+DoubleToString(e.level,_Digits),356,y+27,176,9,UI_MUTED,true);
      string tail=closed ? "出 "+DoubleToString(end.exit,_Digits)+" · "+PaperMoment(end.msc)+" · "+end.why :
         gap ? "旧版已作废；后台尝试按历史报价补算，不猜测出场" :
         "SL "+DoubleToString(e.entry-e.sign*10,_Digits)+" · TP "+DoubleToString(e.entry+e.sign*5,_Digits)+" · 最长60分钟";
      UIText(tail,24,y+48,508,8,UI_MUTED);
      shown++;
   }
   if(shown==0)
   {
      UICard(12,202,536,70,UI_ROW);
      UIText("本组尚无模拟开单记录",26,220,500,12,UI_TEXT);
      UIText(paperStatus[paperDetailArm],26,245,500,9,UI_MUTED);
   }
   UIButton("上一页",12,568,108,216); UIButton("下一页",130,568,108,217);
   UIButton(paperReviewId>0 ? "清除标记 / 回到实时" : "图上标记：未选择",250,568,294,218,paperReviewId>0);
   UIText(paperHealth,16,612,528,9,UI_MUTED);
   UIText("仅模拟 · 作废记录已隐藏；点击只显示这一单，再点取消",16,636,528,8,UI_DIM);
   panelCanvas.Update();
}
void PaperSettle(const PaperEvent &e)
{
   int n=ArraySize(paperSettlements),at=n;
   ArrayResize(paperSettlements,n+1);
   while(at>0 && (paperSettlements[at-1].msc>e.msc ||
      (paperSettlements[at-1].msc==e.msc && paperSettlements[at-1].id>e.id)))
   { paperSettlements[at]=paperSettlements[at-1]; at--; }
   paperSettlements[at].id=e.id; paperSettlements[at].msc=e.msc;
   paperSettlements[at].arm=e.arm; paperSettlements[at].net=e.gross-e.fee;
   if(at==n)
   {
      paperScores[e.arm].net+=e.gross-e.fee;
      paperScores[e.arm].peak=MathMax(paperScores[e.arm].peak,paperScores[e.arm].net);
      paperScores[e.arm].drawdown=MathMax(paperScores[e.arm].drawdown,paperScores[e.arm].peak-paperScores[e.arm].net);
      return;
   }
   // 补算可能是更早的结束时间，按实际结束顺序重新计算该组回撤。
   paperScores[e.arm].net=0; paperScores[e.arm].peak=0; paperScores[e.arm].drawdown=0;
   for(int i=0;i<ArraySize(paperSettlements);i++) if(paperSettlements[i].arm==e.arm)
   {
      paperScores[e.arm].net+=paperSettlements[i].net;
      paperScores[e.arm].peak=MathMax(paperScores[e.arm].peak,paperScores[e.arm].net);
      paperScores[e.arm].drawdown=MathMax(paperScores[e.arm].drawdown,paperScores[e.arm].peak-paperScores[e.arm].net);
   }
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
      paperTrades[n].id=e.id; paperTrades[n].opened=e.msc;
      paperTrades[n].checked=e.msc; paperTrades[n].recovering=false; paperTrades[n].retry=0; paperTrades[n].bar=e.bar;
      paperTrades[n].arm=e.arm; paperTrades[n].sign=e.sign; paperTrades[n].level=e.level;
      paperTrades[n].entry=e.entry; paperTrades[n].volume=e.volume;
      paperTrades[n].mfe=0; paperTrades[n].mae=0; paperTrades[n].source=e.source;
      n=ArraySize(paperVisits); ArrayResize(paperVisits,n+1);
      paperVisits[n].arm=e.arm; paperVisits[n].level=e.level; paperVisits[n].away=0;
      paperScores[e.arm].opened++; return;
   }
   if(e.kind=="REPAIR") { paperScores[e.arm].invalid--; paperScores[e.arm].repaired++; }
   else
   {
      int at=PaperFind(e.id),n=ArraySize(paperTrades);
      for(int j=at+1;j<n;j++) paperTrades[j-1]=paperTrades[j];
      ArrayResize(paperTrades,n-1);
      if(e.kind=="GAP") { paperScores[e.arm].invalid++; return; }
   }
   double net=e.gross-e.fee;
   paperScores[e.arm].closed++;
   if(net>0) paperScores[e.arm].wins++;
   if(net<0) paperScores[e.arm].losses++;
   PaperSettle(e);
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
   for(int i=0;i<ArraySize(paperTrades);i++)
   { paperTrades[i].recovering=true; paperTrades[i].checked=paperTrades[i].opened; }
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
// 返回 -1=等待数据/收益换算，0=下一段，1=已追上当前，2=已找到实际报价触发的退出。
// 每段最多5分钟；失败不推进游标，未取得完整窗口不使用部分返回值。
int PaperHistoryStep(PaperTrade &t,const MqlTick &latest,PaperEvent &ending)
{
   if(TimeGMT()<t.retry) return -1;
   if(t.checked>latest.time_msc) return 1;
   if(paperHistoryHandle!=INVALID_HANDLE && paperHistoryId!=t.id) return 0;
   if(paperHistoryHandle==INVALID_HANDLE)
   {
      paperHistoryFrom=t.checked;
      paperHistoryUntil=(long)MathMin(t.checked+300000,latest.time_msc);
      paperHistoryHandle=iCustom(_Symbol,PERIOD_M1,"::Include\\View\\TgePaperHistory.ex5",
         paperHistoryFrom,paperHistoryUntil,t.opened,t.entry,t.sign,paperHistoryUntil==latest.time_msc);
      if(paperHistoryHandle==INVALID_HANDLE) { t.retry=TimeGMT()+10; return -1; }
      paperHistoryId=t.id; paperHistoryStarted=TimeGMT();
   }
   double values[6],one[1]; bool ready=BarsCalculated(paperHistoryHandle)>0;
   if(ready) for(int b=0;b<6;b++)
   {
      if(CopyBuffer(paperHistoryHandle,b,0,1,one)!=1 || !MathIsValidNumber(one[0]) || one[0]==EMPTY_VALUE)
      { ready=false; break; }
      values[b]=one[0];
   }
   if(!ready || values[0]==0)
   {
      if(TimeGMT()-paperHistoryStarted<15) return 0;
      PaperReleaseHistory(); t.retry=TimeGMT()+10; return -1;
   }
   long until=paperHistoryUntil;
   PaperReleaseHistory();
   t.mfe=MathMax(t.mfe,values[3]); t.mae=MathMin(t.mae,values[4]);
   MqlTick q=latest; double exit=0; string why="";
   if(values[0]==2)
   {
      q.time_msc=(long)values[1]; q.time=(datetime)(q.time_msc/1000);
      exit=Align(values[2]-t.sign*模拟单边滑点价格,-t.sign);
      why=values[5]==1 ? "止损" : values[5]==2 ? "止盈" : "满60分钟退出";
   }
   else if(latest.time_msc-until<=5000)
   {
      // 已补到最近5秒内，按原采样口径处理最新报价，不无限追赶移动中的末端。
      double delta=t.sign*((t.sign>0 ? latest.bid : latest.ask)-t.entry);
      t.mfe=MathMax(t.mfe,delta); t.mae=MathMin(t.mae,delta);
      why=PaperExit(t,q,exit); until=latest.time_msc;
   }
   if(why!="")
   {
      PaperFromTrade(t,q,ending); ending.kind="CLOSE"; ending.exit=exit;
      ending.why="历史报价补齐 · "+why;
      if(!OrderCalcProfit(t.sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,t.volume,t.entry,exit,ending.gross))
      { t.retry=TimeGMT()+10; return -1; }
      ending.fee=模拟每手往返费用*t.volume;
      return 2;
   }
   t.checked=until+1; t.retry=0;
   return until==latest.time_msc ? 1 : 0;
}

void PaperRepairLegacy(const MqlTick &q)
{
   if(paperPending || TimeGMT()<paperRepairRetry) return;
   if(paperRepairId>0)
   {
      int d=PaperDetailFind(paperRepairId);
      if(d<0 || paperDetails[d].endEvent.kind!="GAP")
      { if(paperHistoryId==paperRepairId) PaperReleaseHistory(); paperRepairId=0; }
   }
   if(paperRepairId==0)
   {
      int n=ArraySize(paperDetails);
      for(int k=0;k<n;k++)
      {
         int i=(paperRepairCursor+k)%n;
         if(paperDetails[i].endEvent.kind!="GAP") continue;
         PaperEvent e=paperDetails[i].entryEvent; ZeroMemory(paperRepair);
         paperRepair.id=e.id; paperRepair.arm=e.arm; paperRepair.sign=e.sign; paperRepair.opened=e.msc;
         paperRepair.checked=e.msc; paperRepair.level=e.level; paperRepair.entry=e.entry;
         paperRepair.volume=e.volume; paperRepair.bar=e.bar; paperRepair.source=e.source;
         paperRepairId=e.id; paperRepairCursor=(i+1)%n; break;
      }
      if(paperRepairId==0) { paperRepairRetry=TimeGMT()+30; return; }
   }
   PaperEvent ending;
   int state=PaperHistoryStep(paperRepair,q,ending);
   if(state==2)
   {
      ending.kind="REPAIR"; ending.why="旧缺失补算 · "+ending.why;
      if(PaperEmit(ending)) paperRepairId=0;
   }
   else if(state<0 || state==1)
   { paperRepairId=0; paperRepairRetry=TimeGMT()+10; }
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
      PaperApply(paperFrozen); paperPending=false;
   }
   MqlTick q;
   if(!FreshQuote(q)) { paperHealth="等待新报价 · 模拟持仓保留，恢复后核对历史"; return; }
   if(paperLastTick>0 && q.time_msc<paperLastTick) return;
   bool gap=paperRestored || (paperLastTick>0 && q.time_msc-paperLastTick>5000);
   if(gap) for(int i=0;i<ArraySize(paperTrades);i++) paperTrades[i].recovering=true;
   paperRestored=false;
   bool newTick=q.time_msc>paperLastTick;
   paperLastTick=q.time_msc;
   int recoveryBudget=2; bool waiting=false;
   // 已有模拟单的退出不受消息中断、入场暂停影响；缺口不再直接作废。
   for(int i=ArraySize(paperTrades)-1;i>=0;i--)
   {
      if(paperTrades[i].recovering)
      {
         waiting=true;
         if(recoveryBudget<=0 || TimeGMT()<paperTrades[i].retry) continue;
         if(paperHistoryHandle!=INVALID_HANDLE && paperHistoryId!=paperTrades[i].id) continue;
         recoveryBudget--;
         PaperEvent e; int state=PaperHistoryStep(paperTrades[i],q,e);
         if(state==2) { if(!PaperEmit(e)) return; }
         else if(state==1) paperTrades[i].recovering=false;
         continue;
      }
      if(!newTick) continue;
      double delta=paperTrades[i].sign*((paperTrades[i].sign>0 ? q.bid : q.ask)-paperTrades[i].entry);
      paperTrades[i].mfe=MathMax(paperTrades[i].mfe,delta);
      paperTrades[i].mae=MathMin(paperTrades[i].mae,delta);
      double exit=0; string why=PaperExit(paperTrades[i],q,exit);
      if(why=="") { paperTrades[i].checked=q.time_msc+1; continue; }
      PaperEvent e; PaperFromTrade(paperTrades[i],q,e); e.kind="CLOSE"; e.exit=exit; e.why=why;
      if(!OrderCalcProfit(e.sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,e.volume,e.entry,e.exit,e.gross))
      {
         paperTrades[i].recovering=true; paperTrades[i].retry=TimeGMT()+10;
         waiting=true; continue;
      }
      e.fee=模拟每手往返费用*e.volume;
      if(!PaperEmit(e)) return;
   }
   if(!waiting || (paperRepairId>0 && paperHistoryId==paperRepairId)) PaperRepairLegacy(q);
   if(paperPending) return;
   if(!newTick) return;
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
      bool recovering=false;
      for(int i=0;i<ArraySize(paperTrades);i++)
         if(paperTrades[i].arm==arm && paperTrades[i].recovering) recovering=true;
      if(recovering) { paperStatus[arm]="正在补齐已有模拟单；本组暂缓新开"; continue; }
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
   paperHealth=waiting ? "历史报价核对中 · 未结束单保留，失败10秒后重试" : "自动比较运行中 · 旧缺失记录后台补算";
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
   UIText("已平/持有",290,233,80,9,UI_MUTED);
   UIText("赢/亏",374,233,65,9,UI_MUTED);
   UIText("最大回撤",444,233,100,9,UI_MUTED);
   for(int arm=0;arm<PAPER_ARMS;arm++)
   {
      int y=255+arm*41;
      UICard(12,y,536,36,UI_ROW);
      UIButton(PaperName(arm),16,y+4,172,210+arm,paperDetailArm==arm);
      UIText(DoubleToString(paperScores[arm].net,2),198,y+8,88,11,UI_ACCENT);
      UIText(IntegerToString(paperScores[arm].closed)+"/"+IntegerToString(PaperCount(arm)),290,y+9,80,9,UI_TEXT);
      UIText(IntegerToString(paperScores[arm].wins)+"/"+IntegerToString(paperScores[arm].losses),374,y+9,65,9,UI_TEXT);
      UIText(DoubleToString(paperScores[arm].drawdown,2),444,y+9,100,9,UI_MUTED);
   }
   UIText(PaperName(paperDetailArm)+"："+paperStatus[paperDetailArm],16,472,528,9,UI_TEXT);
   UIButton("查看本组模拟单",16,501,190,215);
   UIText("有效单列表 · 点选查看入/出",220,506,324,9,UI_MUTED);
   UIText(模拟每手往返费用>0 ? "已扣设置费用，不含隔夜费；仍为模拟估算" :
      "费用尚未配置：金额未扣佣金，不可当作净收益",16,533,528,9,UI_WARN);
   UIText("每秒采样试做；历史归档另存收到的报价，不保证完整逐笔。",16,560,528,8.5,UI_DIM);
   UIText("已补算 "+IntegerToString(paperScores[paperDetailArm].repaired)+" 笔；未取得完整报价的记录不猜测盈亏。",16,585,528,8.5,UI_DIM);
   UIText("所有组均为待验证假设，暂不接管实盘。",16,614,528,9,UI_MUTED);
   panelCanvas.Update();
}
void StopPaper()
{
   PaperClearReview();
   PaperReleaseHistory();
   if(paperPending && paperFile!=INVALID_HANDLE && PaperWrite(paperFrozen))
   { PaperApply(paperFrozen); paperPending=false; }
   if(paperFile!=INVALID_HANDLE) { FileClose(paperFile); paperFile=INVALID_HANDLE; }
}
