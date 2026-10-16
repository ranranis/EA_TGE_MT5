// 独立观察旁路：不读写交易消费/pending，不调用交易请求。
struct TgeObservation
{
   datetime bar,utc,server;
   double lower,upper,atr,bid,ask,op,hi,lo,cl;
   int sign,lowerHits,upperHits;
   string state,why,lowerEvidence,upperEvidence,policy,bars;
   datetime lowerConfirmed,upperConfirmed,lowerExpires,upperExpires;
};
TgeObservation entryObservations[];
int observerOffset=0;
datetime observerLastBar=0,observerRetry=0;
string observerHealth="等待首次收盘行情";
bool observerHasPending=false;
TgeObservation observerPending;
bool uiObserver=false;

// 全部参数均来自当时快照；bars[0]明确是刚收盘K，绝不用未收盘K或未来行情。
void ObserverClassify(const MqlRates &bars[],const double lower,const double upper,
                      const double atrValue,const double spread,TgeObservation &out)
{
   out.sign=0; out.lowerHits=0; out.upperHits=0; out.state="WAIT"; out.why="等待边界反应";
   if(ArraySize(bars)<10 || lower<=0 || upper<=lower || atrValue<=0)
   { out.state="NO_RANGE"; out.why="有效点位不足，尚不能构成待验证区间"; return; }
   double band=TEACHER_BAND,buffer=MathMax(TickSize()*2,atrValue*观察收回ATR倍数);
   // 最后两根收盘突破优先于区间触碰统计，旧反弹不能抵消新破位。
   if((bars[0].close<lower-buffer && bars[1].close<lower-buffer) ||
      (bars[0].close>upper+buffer && bars[1].close>upper+buffer))
   { out.state="BROKEN"; out.why="连续两根M1收盘越界，暂停原区间反向观察"; return; }
   if(spread<0 || spread>最大点差价格)
   { out.state="SPREAD"; out.why="当前点差异常，放弃本次观察候选"; return; }
   if(upper-lower<MathMax(atrValue*观察最小区间ATR倍数,2*band+4*spread))
   { out.state="SPACE"; out.why="区间空间不足以容纳当前波动和点差"; return; }
   int lastLower=-100,lastUpper=-100;
   for(int j=ArraySize(bars)-1;j>=1;j--)
   {
      int step=ArraySize(bars)-j;
      bool lowTouch=bars[j].low>=lower-band && bars[j].low<=lower+band &&
                    bars[j].close>lower+buffer && bars[j].close<upper-buffer;
      bool highTouch=bars[j].high>=upper-band && bars[j].high<=upper+band &&
                     bars[j].close<upper-buffer && bars[j].close>lower+buffer;
      if(lowTouch && step-lastLower>=3) { out.lowerHits++; lastLower=step; }
      if(highTouch && step-lastUpper>=3) { out.upperHits++; lastUpper=step; }
   }
   if(out.lowerHits<观察边界最少反应次数 || out.upperHits<观察边界最少反应次数)
   { out.state="UNPROVEN"; out.why="上下沿历史反应不足，相邻点位不直接视为震荡区间"; return; }
   bool low=bars[0].low<=lower+band,high=bars[0].high>=upper-band;
   if(low && high)
   { out.state="CROSS"; out.why="同一根K扫到两端，区间方向不清"; return; }
   if(bars[0].high-bars[0].low>atrValue*3)
   { out.state="IMPULSE"; out.why="刚收盘K波幅超过3ATR，放弃冲击中的反向候选"; return; }
   if(low && bars[1].close<bars[2].close && bars[2].close<bars[3].close &&
      bars[3].close-bars[1].close>atrValue*1.5)
   { out.state="IMPULSE"; out.why="到达下沿前持续下推，等待新的边界反应"; return; }
   if(high && bars[1].close>bars[2].close && bars[2].close>bars[3].close &&
      bars[1].close-bars[3].close>atrValue*1.5)
   { out.state="IMPULSE"; out.why="到达上沿前持续上推，等待新的边界反应"; return; }
   if(bars[0].low<lower-band || bars[0].high>upper+band)
   { out.state="PIERCE"; out.why="本根越过边界缓冲，等待后续新的反应"; return; }
   if(low && bars[0].close>bars[0].open && bars[0].close>lower+buffer &&
      bars[0].close<lower+band+buffer && upper-bars[0].close>MathMax(atrValue,3*spread))
   { out.sign=1; out.state="BUY_WATCH"; out.why="下沿触及后收回，出现反弹观察候选"; return; }
   if(high && bars[0].close<bars[0].open && bars[0].close<upper-buffer &&
      bars[0].close>upper-band-buffer && bars[0].close-lower>MathMax(atrValue,3*spread))
   { out.sign=-1; out.state="SELL_WATCH"; out.why="上沿触及后回落，出现回落观察候选"; return; }
   out.why=low || high ? "碰到边界但收回不足，或反应已离边界太远" : "处于区间中部，等待到达边界";
}
string ObserverClean(string text)
{
   StringReplace(text,"\t"," "); StringReplace(text,"\r"," "); StringReplace(text,"\n"," "); return text;
}
string ObserverPolicy()
{
   return "O1:M1/"+IntegerToString(观察回看分钟)+"/hits"+IntegerToString(观察边界最少反应次数)+
          "/recover"+DoubleToString(观察收回ATR倍数,3)+"/width"+DoubleToString(观察最小区间ATR倍数,3)+
          "/band"+DoubleToString(TEACHER_BAND,2)+"/spread"+DoubleToString(最大点差价格,3);
}
string ObserverPath()
{
   string day=TimeToString(TimeGMT(),TIME_DATE); StringReplace(day,".","");
   return "FeishuMT5SignalMonitor\\observations\\"+prefix+day+".tsv";
}
bool ObserverParse(const string line,TgeObservation &r)
{
   string f[]; if(StringSplit(line,'\t',f)!=28 || f[0]!="O1" || f[27]!="END" || f[26]!=_Symbol) return false;
   int numeric[]={1,2,3,4,5,11,12,13,14,15,16,17,18,19,21,22,23,24};
   for(int i=0;i<ArraySize(numeric);i++)
      if(!Number(f[numeric[i]],true) || !MathIsValidNumber(StringToDouble(f[numeric[i]]))) return false;
   if(f[6]!="0" && f[6]!="1" && f[6]!="-1") return false;
   r.bar=(datetime)StringToInteger(f[1]); r.utc=(datetime)StringToInteger(f[2]); r.server=(datetime)StringToInteger(f[3]);
   r.lower=StringToDouble(f[4]); r.upper=StringToDouble(f[5]); r.sign=(int)StringToInteger(f[6]);
   r.state=f[7]; r.why=f[8]; r.lowerEvidence=f[9]; r.upperEvidence=f[10];
   r.atr=StringToDouble(f[11]); r.bid=StringToDouble(f[12]); r.ask=StringToDouble(f[13]);
   r.op=StringToDouble(f[14]); r.hi=StringToDouble(f[15]); r.lo=StringToDouble(f[16]); r.cl=StringToDouble(f[17]);
   r.lowerHits=(int)StringToInteger(f[18]); r.upperHits=(int)StringToInteger(f[19]); r.policy=f[20];
   r.lowerConfirmed=(datetime)StringToInteger(f[21]); r.upperConfirmed=(datetime)StringToInteger(f[22]);
   r.lowerExpires=(datetime)StringToInteger(f[23]); r.upperExpires=(datetime)StringToInteger(f[24]); r.bars=f[25];
   return r.bar>0 && r.server>=r.bar+60 && r.utc>0;
}
bool ObserverAppend(const TgeObservation &r)
{
   FolderCreate("FeishuMT5SignalMonitor\\observations",FILE_COMMON);
   int h=FileOpen(ObserverPath(),FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(h==INVALID_HANDLE) return false;
   // 正常每分钟只追加；只有失败重试才核对是否已落盘。启动恢复负责重启去重。
   if(observerRetry>0)
      while(!FileIsEnding(h))
      {
         TgeObservation old;
         if(ObserverParse(FileReadString(h),old) && old.bar==r.bar) { FileClose(h); return true; }
      }
   string line="O1\t"+IntegerToString((long)r.bar)+"\t"+IntegerToString((long)r.utc)+"\t"+IntegerToString((long)r.server)+
      "\t"+DoubleToString(r.lower,8)+"\t"+DoubleToString(r.upper,8)+"\t"+IntegerToString(r.sign)+
      "\t"+r.state+"\t"+ObserverClean(r.why)+"\t"+ObserverClean(r.lowerEvidence)+"\t"+ObserverClean(r.upperEvidence)+
      "\t"+DoubleToString(r.atr,8)+"\t"+DoubleToString(r.bid,8)+"\t"+DoubleToString(r.ask,8)+
      "\t"+DoubleToString(r.op,8)+"\t"+DoubleToString(r.hi,8)+"\t"+DoubleToString(r.lo,8)+"\t"+DoubleToString(r.cl,8)+
      "\t"+IntegerToString(r.lowerHits)+"\t"+IntegerToString(r.upperHits)+"\t"+r.policy+
      "\t"+IntegerToString((long)r.lowerConfirmed)+"\t"+IntegerToString((long)r.upperConfirmed)+
      "\t"+IntegerToString((long)r.lowerExpires)+"\t"+IntegerToString((long)r.upperExpires)+
      "\t"+r.bars+"\t"+_Symbol+"\tEND\r\n";
   FileSeek(h,0,SEEK_END); ResetLastError(); uint written=FileWriteString(h,"\r\n"+line); FileFlush(h);
   bool ok=written>0 && GetLastError()==0; FileClose(h); return ok;
}
void ObserverRemember(const TgeObservation &r)
{
   int n=ArraySize(entryObservations);
   if(n>=120)
   {
      string old=VIEW+"OBS_"+IntegerToString((long)entryObservations[0].bar); ObjectDelete(0,old);
      for(int i=1;i<n;i++) entryObservations[i-1]=entryObservations[i];
      n--; ArrayResize(entryObservations,n);
   }
   ArrayResize(entryObservations,n+1); entryObservations[n]=r;
}
void ObserverMark(const TgeObservation &r)
{
   if(r.sign==0) return;
   string name=VIEW+"OBS_"+IntegerToString((long)r.bar);
   double price=r.sign>0 ? r.lo : r.hi;
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_ARROW,0,r.bar,price)) return;
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,r.sign>0 ? 233 : 234);
   ObjectSetInteger(0,name,OBJPROP_COLOR,r.sign>0 ? C'0,83,138' : C'105,52,139');
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2); ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,(r.sign>0 ? "观察多，非成交" : "观察空，非成交")+
      " · "+TimeToString(r.bar,TIME_DATE|TIME_MINUTES)+" · "+r.why);
}
void InitObserver()
{
   if(!启用入场观察实验) { observerHealth="入场观察实验已关闭"; return; }
   int h=FileOpen(ObserverPath(),FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(h==INVALID_HANDLE) return;
   while(!FileIsEnding(h))
   {
      TgeObservation r; if(!ObserverParse(FileReadString(h),r)) continue;
      if(r.bar<=observerLastBar) continue;
      ObserverRemember(r); observerLastBar=r.bar;
   }
   FileClose(h);
   for(int i=0;i<ArraySize(entryObservations);i++) ObserverMark(entryObservations[i]);
   observerHealth="已恢复当日记录；仅记录在线观察，不补造离线信号";
}
void ObserverDeduplicate(const MqlRates &bars[],TgeObservation &r)
{
   if(r.sign==0) return;
   double edge=r.sign>0 ? r.lower : r.upper;
   for(int i=ArraySize(entryObservations)-1;i>=0;i--)
   {
      if(entryObservations[i].sign!=r.sign ||
         MathAbs((r.sign>0 ? entryObservations[i].lower : entryObservations[i].upper)-edge)>=TickSize()) continue;
      // 必须在前次候选之后、此次候选之前，实际有一根收盘离开边界；不以经过时间代替价格证据。
      double away=TEACHER_BAND+MathMax(TickSize()*2,r.atr*观察收回ATR倍数);
      for(int j=1;j<ArraySize(bars);j++)
         if(bars[j].time>entryObservations[i].bar && r.sign*(bars[j].close-edge)>away) return;
      r.sign=0; r.state="SEEN"; r.why="同次边界反应已记录，尚无离开边界的新收盘证据"; return;
   }
}
bool ObserverFlush()
{
   if(!observerHasPending) return true;
   if(!ObserverAppend(observerPending))
   { observerHealth="观察记录写入失败，本次不发布箭头；10秒后重试"; observerRetry=TimeGMT()+10; return false; }
   if(observerOffset>0) observerOffset++;
   ObserverRemember(observerPending); ObserverMark(observerPending); observerLastBar=observerPending.bar;
   observerOffset=MathMin(observerOffset,ArraySize(entryObservations)-1);
   observerHasPending=false; observerRetry=0; observerHealth="观察在线 · 本分钟判断已保存";
   return true;
}
void RefreshObserver()
{
   if(!启用入场观察实验 || TimeGMT()<observerRetry) return;
   if(observerHasPending && !ObserverFlush()) return;
   // 即使原EA处于观察模式也运行；任何故障只影响本观察旁路。
   if(!AIChannelReady()) { observerHealth="来源未就绪，旧记录仅供复盘"; return; }
   if(!AdaptiveMarketFresh()) { observerHealth="收盘行情未就绪，旧记录仅供复盘"; return; }
   MqlTick q; if(!FreshQuote(q)) { observerHealth="报价过期，旧记录仅供复盘"; return; }
   datetime bar=adaptiveBars[0].time;
   if(bar<=observerLastBar) { observerHealth="观察在线 · 等待下一根M1收盘"; return; }
   MqlRates bars[]; ArraySetAsSeries(bars,true);
   if(CopyRates(_Symbol,PERIOD_M1,1,观察回看分钟,bars)!=观察回看分钟 || bars[0].time!=bar)
   { observerHealth="回看K线不足，等待行情加载"; return; }
   for(int j=0;j<ArraySize(bars)-1;j++)
      if(bars[j].time-bars[j+1].time!=60 || bars[j].low<=0)
      { observerHealth="回看存在断档，等待连续K线"; return; }
   TgeObservation r; ZeroMemory(r);
   r.bar=bar; r.utc=TimeGMT(); r.server=TimeCurrent(); r.atr=adaptiveATR; r.bid=q.bid; r.ask=q.ask;
   r.op=bars[0].open; r.hi=bars[0].high; r.lo=bars[0].low; r.cl=bars[0].close; r.policy=ObserverPolicy();
   // 群消息UTC与券商K线服务器时间分开保存。只采用本根K开盘前已确认且目前仍有效的来源。
   long offset=(long)MathRound((double)(r.server-r.utc)/3600.0)*3600;
   int indices[];
   for(int i=0;i<ArraySize(aiPlans);i++)
   {
      if(aiPlans[i].kind=="WATCH" || aiPlans[i].feedState!="READY" ||
         aiPlans[i].expires<=r.utc || aiPlans[i].confirmed+offset>bar) continue;
      int n=ArraySize(indices); ArrayResize(indices,n+1); indices[n]=i;
   }
   for(int i=1;i<ArraySize(indices);i++)
   {
      int at=indices[i],j=i-1;
      while(j>=0 && aiPlans[indices[j]].level>aiPlans[at].level) { indices[j+1]=indices[j]; j--; }
      indices[j+1]=at;
   }
   int lower=-1,upper=-1; double best=DBL_MAX;
   for(int i=1;i<ArraySize(indices);i++)
   {
      double low=aiPlans[indices[i-1]].level,high=aiPlans[indices[i]].level;
      if(high-low<=TickSize()) continue;
      double distance=MathMax(0,MathMax(low-r.cl,r.cl-high));
      if(distance<best) { best=distance; lower=indices[i-1]; upper=indices[i]; }
   }
   if(lower>=0)
   {
      r.lower=aiPlans[lower].level; r.upper=aiPlans[upper].level;
      r.lowerEvidence=aiPlans[lower].kind+"/"+IntegerToString(aiPlans[lower].sign)+"/"+aiPlans[lower].id+"/"+aiPlans[lower].source;
      r.upperEvidence=aiPlans[upper].kind+"/"+IntegerToString(aiPlans[upper].sign)+"/"+aiPlans[upper].id+"/"+aiPlans[upper].source;
      r.lowerConfirmed=aiPlans[lower].confirmed; r.upperConfirmed=aiPlans[upper].confirmed;
      r.lowerExpires=aiPlans[lower].expires; r.upperExpires=aiPlans[upper].expires;
   }
   ObserverClassify(bars,r.lower,r.upper,r.atr,q.ask-q.bid,r);
   ObserverDeduplicate(bars,r);
   for(int j=0;j<ArraySize(bars);j++)
      r.bars+=(j==0 ? "" : ";")+IntegerToString((long)bars[j].time)+":"+
         DoubleToString(bars[j].open,8)+":"+DoubleToString(bars[j].high,8)+":"+
         DoubleToString(bars[j].low,8)+":"+DoubleToString(bars[j].close,8);
   // 写入失败时冻结本次快照；重试不能用后续行情替换原判断。
   observerPending=r; observerHasPending=true;
   ObserverFlush();

}
string ObserverLabel(const TgeObservation &r)
{
   if(r.state=="BUY_WATCH") return "↑ 多头观察候选 · 非订单";
   if(r.state=="SELL_WATCH") return "↓ 空头观察候选 · 非订单";
   if(r.state=="BROKEN") return "× 区间破位 · 暂停反向观察";
   if(r.state=="UNPROVEN" || r.state=="NO_RANGE") return "？区间尚未成立";
   if(r.state=="SEEN") return "— 同次触及已记录";
   return "— 等待 / 放弃本次候选";
}
string ObserverEvidenceLabel(const string evidence)
{
   string f[]; if(StringSplit(evidence,'/',f)!=4) return "无有效来源";
   string side=f[1]=="1" ? "多" : f[1]=="-1" ? "空" : "中性";
   string kind=f[0]=="DIRECT" ? "明确方向" : f[0]=="ROLE" ? "支撑/压力" :
               f[0]=="MAP" ? "普通点位" : "区间边界";
   return kind+" · "+side+" · "+(f[3]=="MANUAL" ? "手动来源" : "群消息来源")+"（仅作观察位置）";
}
void ObserverPage()
{
   UIText("入场研判 · 只观察",16,94,300,17,UI_TEXT);
   UIText(tradeMode ? "原EA处于交易模式；本页研判不会替它下单或拦单" :
          "原EA处于观察模式；本页只计算和记录",16,125,528,9,tradeMode ? UI_WARN : UI_ACCENT);
   UICard(12,157,536,60,UI_ROW);
   UIText(observerHealth,26,166,508,10,UI_TEXT);
   UIText("箭头只是观察候选；缺失行情不回填。时间均为券商服务器时间。",26,192,508,8.5,UI_MUTED);
   int n=ArraySize(entryObservations);
   if(n==0)
   {
      UIText("等待一根完整M1及足够回看数据",26,244,500,12,UI_MUTED);
      UIText("消息提供观察位置，收盘行情验证边界；不会自动反手。",26,278,500,9,UI_DIM);
      panelCanvas.Update(); return;
   }
   observerOffset=MathMax(0,MathMin(observerOffset,n-1));
   TgeObservation r=entryObservations[n-1-observerOffset];
   UICard(12,231,536,283,UI_ROW);
   UIText(ObserverLabel(r),26,243,508,13,r.sign==0 ? UI_MUTED : r.sign>0 ? UI_ACCENT : UI_SELL);
   UIText("待验证区间  "+DoubleToString(r.lower,_Digits)+" — "+DoubleToString(r.upper,_Digits),26,276,508,15,UI_TEXT);
   UIText("判断K线 "+TimeToString(r.bar,TIME_DATE|TIME_MINUTES)+" · "+(observerOffset==0 ? "最近记录" : "历史记录"),26,309,508,9,UI_MUTED);
   UIText(r.why,26,336,508,10,UI_TEXT);
   UIText("下沿反应 "+IntegerToString(r.lowerHits)+"次 / 上沿反应 "+IntegerToString(r.upperHits)+
      "次 · ATR "+DoubleToString(r.atr,2)+" · 点差 "+DoubleToString(r.ask-r.bid,2),26,364,508,9,UI_MUTED);
   UIText("O "+DoubleToString(r.op,2)+"   H "+DoubleToString(r.hi,2)+"   L "+DoubleToString(r.lo,2)+"   C "+DoubleToString(r.cl,2),26,389,508,9,UI_MUTED);
   UIText("下沿原文性质："+ObserverEvidenceLabel(r.lowerEvidence),26,418,508,8,UI_DIM);
   UIText("上沿原文性质："+ObserverEvidenceLabel(r.upperEvidence),26,441,508,8,UI_DIM);
   UIText("恢复条件：有效区间 + 新的边界收回；突破不转为追单。",26,478,508,8.5,UI_MUTED);
   UIButton("上一条",12,530,82,200); UIButton("下一条",102,530,82,201);
   UIButton("定位K线",192,530,94,202); UIButton("最新记录",294,530,94,203); UIButton("返回实时",396,530,148,204);
   UIText(IntegerToString(n-observerOffset)+"/"+IntegerToString(n)+" · 内存保留120条；当日文件保留全部在线记录",16,574,526,9,UI_MUTED);
   UIText("实验规则尚未验证盈利能力；点击定位只移动图表。",16,600,526,9,UI_DIM);
   if(reviewNotice!="") UIText(reviewNotice,16,628,526,8,UI_MUTED);
   panelCanvas.Update();
}
void ObserverAction(const int action)
{
   int n=ArraySize(entryObservations);
   if(action==200) observerOffset=MathMin(MathMax(0,n-1),observerOffset+1);
   if(action==201) observerOffset=MathMax(0,observerOffset-1);
   if(action==203) observerOffset=0;
   if(action==204) ReviewReturnLive();
   if(action==202 && n>0)
   {
      reviewNavTime=entryObservations[n-1-observerOffset].bar; reviewNavAttempts=0;
      ReviewNavigate();
   }
}
