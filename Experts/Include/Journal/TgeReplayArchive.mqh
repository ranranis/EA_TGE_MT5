// R1 append-only replay evidence. OnTick only copies received quotes to bounded RAM.
struct ReplayQuote { MqlTick q; datetime utc; ulong mono; };
ReplayQuote replayQuotes[4096];
int replayQuoteCount=0,replayFile=INVALID_HANDLE;
long replaySequence=0,replayDropped=0,replayPreviousMSC=0;
datetime replayBar=0,replayRetry=0;
string replayBuffer="",replayDay="",replaySession="",replayFeed="",replayState="";
string replayHealth="历史归档未初始化";
bool replayStarted=false;
string ReplayEscape(string text)
{
   StringReplace(text,"\\","\\\\"); StringReplace(text,"\t","\\t");
   StringReplace(text,"\r","\\r"); StringReplace(text,"\n","\\n"); return text;
}
bool ReplayRecord(const string kind,const string payload,const long marketMSC,const datetime utc,const ulong mono)
{
   if(!启用历史归档 || !replayStarted) return false;
   if(StringLen(replayBuffer)>2000000) { replayDropped++; return false; }
   string line="R1\t"+IntegerToString(++replaySequence)+"\t"+kind+"\t"+IntegerToString((long)utc)+
      "\t"+IntegerToString((long)mono)+"\t"+IntegerToString(marketMSC)+"\t"+ReplayEscape(payload);
   replayBuffer+=line+"\t"+IntegerToString((long)Hash(line))+"\tEND\r\n";
   return true;
}
void ReplayCapture(const MqlTick &q)
{
   if(!启用历史归档 || !replayStarted) return;
   if(replayQuoteCount>=4096) { replayDropped++; return; }
   replayQuotes[replayQuoteCount].q=q; replayQuotes[replayQuoteCount].utc=TimeGMT();
   replayQuotes[replayQuoteCount].mono=GetTickCount64(); replayQuoteCount++;
}
void ReplayAccepted(const string &lines[])
{
   if(!启用历史归档 || !replayStarted || ArraySize(lines)<2) return;
   string header[]; if(StringSplit(lines[0],',',header)!=7) return;
   string semantic=header[3]+"|"+header[4]+"|"+header[5],payload=lines[0];
   for(int i=1;i<ArraySize(lines);i++) { semantic+="\n"+lines[i]; payload+="\n"+lines[i]; }
   if(semantic==replayFeed) return; // Heartbeats cannot renew historical availability.
   if(ReplayRecord("ACCEPTED_TGA9",payload,(long)TimeCurrent()*1000,TimeGMT(),GetTickCount64()))
      replayFeed=semantic;
}
bool ReplayFlush()
{
   if(!启用历史归档 || !replayStarted) return false;
   if(TimeGMT()<replayRetry) return false;
   string day=TimeToString(TimeGMT(),TIME_DATE); StringReplace(day,".","");
   // Finish the old file first. A failed write retains the same sequence IDs for retry.
   if(replayFile==INVALID_HANDLE)
   {
      string folder="FeishuMT5SignalMonitor\\replay\\"+day;
      FolderCreate("FeishuMT5SignalMonitor\\replay",FILE_COMMON); FolderCreate(folder,FILE_COMMON);
      replayFile=FileOpen(folder+"\\"+prefix+replaySession+".tsv",
         FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
      if(replayFile==INVALID_HANDLE) { replayRetry=TimeGMT()+10; replayHealth="历史归档无法打开，10秒后重试"; return false; }
      replayDay=day;
   }
   if(replayBuffer!="")
   {
      FileSeek(replayFile,0,SEEK_END); ResetLastError();
      uint size=FileWriteString(replayFile,"\r\n"+replayBuffer); FileFlush(replayFile);
      if(size==0 || GetLastError()!=0)
      { replayRetry=TimeGMT()+10; replayHealth="历史保存失败，缓冲保留并重试"; return false; }
      replayBuffer="";
   }
   if(day!=replayDay) { FileClose(replayFile); replayFile=INVALID_HANDLE; }
   replayHealth="历史归档在线 · 点位版本 / 收盘K线 / 收到的报价";
   return true;
}
void InitReplay()
{
   if(!启用历史归档) { replayHealth="历史归档已关闭"; return; }
   replaySession=IntegerToString((long)TimeGMT())+"_"+IntegerToString((long)GetTickCount64());
   replayStarted=true;
   string meta="session="+replaySession+";symbol="+_Symbol+";server="+accountServer+
      ";digits="+IntegerToString(_Digits)+";point="+DoubleToString(_Point,10)+
      ";tick_size="+DoubleToString(TickSize(),10)+";contract="+DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),8)+
      ";volume_min="+DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),8)+
      ";volume_step="+DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),8)+
      ";currency="+AccountInfoString(ACCOUNT_CURRENCY)+";coverage=delivered_OnTick_not_all_broker_ticks;version=1.72";
   ReplayRecord("SESSION",meta,(long)TimeCurrent()*1000,TimeGMT(),GetTickCount64());
   ReplayRecord("GAP","session_start_no_claim_for_offline_period",(long)TimeCurrent()*1000,TimeGMT(),GetTickCount64());
   ReplayFlush();
}
void ReplayPoll()
{
   if(!启用历史归档 || !replayStarted) return;
   for(int i=0;i<replayQuoteCount;i++)
   {
      MqlTick q=replayQuotes[i].q;
      if(replayPreviousMSC>0 && q.time_msc-replayPreviousMSC>5000)
         ReplayRecord("GAP","quote_time_gap_over_5s",q.time_msc,replayQuotes[i].utc,replayQuotes[i].mono);
      replayPreviousMSC=q.time_msc;
      string text=DoubleToString(q.bid,8)+","+DoubleToString(q.ask,8)+","+DoubleToString(q.last,8)+","+
         IntegerToString((long)q.volume)+","+IntegerToString((long)q.flags)+","+DoubleToString(q.volume_real,8);
      ReplayRecord("QUOTE",text,q.time_msc,replayQuotes[i].utc,replayQuotes[i].mono);
   }
   replayQuoteCount=0;
   if(AdaptiveMarketFresh() && ArraySize(adaptiveBars)>0 && adaptiveBars[0].time!=replayBar)
   {
      MqlRates b=adaptiveBars[0];
      if(replayBar>0 && b.time-replayBar>60)
         ReplayRecord("GAP","closed_m1_gap",(long)b.time*1000,TimeGMT(),GetTickCount64());
      string text=IntegerToString((long)b.time)+","+DoubleToString(b.open,8)+","+DoubleToString(b.high,8)+","+
         DoubleToString(b.low,8)+","+DoubleToString(b.close,8)+","+IntegerToString((long)b.tick_volume)+","+
         IntegerToString(b.spread)+","+IntegerToString((long)b.real_volume);
      if(ReplayRecord("CLOSED_M1",text,(long)b.time*1000,TimeGMT(),GetTickCount64())) replayBar=b.time;
   }
   datetime after=0; string news=AdaptiveNewsState(TimeCurrent(),after);
   string state="ready="+IntegerToString((int)AIChannelReady())+";reason="+aiReason+
      ";news="+news+";after="+IntegerToString((long)after)+";shock="+IntegerToString((long)adaptiveShockUntil)+
      ";recover="+IntegerToString((long)adaptiveRecoverUntil)+";trend="+IntegerToString(adaptiveTrend)+
      ";atr="+DoubleToString(adaptiveATR,8)+";policy="+PaperPolicy();
   for(int i=0;i<ArraySize(aiPlans);i++)
      state+="\n"+aiPlans[i].id+","+IntegerToString((long)aiPlans[i].available)+","+IntegerToString(aiPlans[i].approach)+","+PlanLifeReason(i);
   if(state!=replayState && ReplayRecord("EA_STATE",state,(long)TimeCurrent()*1000,TimeGMT(),GetTickCount64()))
      replayState=state;
   if(ReplayFlush() && replayDropped>0)
   {
      long dropped=replayDropped; replayDropped=0;
      ReplayRecord("GAP","buffer_overflow_dropped="+IntegerToString(dropped),(long)TimeCurrent()*1000,TimeGMT(),GetTickCount64());
      ReplayFlush();
   }
}
void StopReplay()
{
   if(!replayStarted) return;
   ReplayPoll();
   ReplayRecord("SESSION_END","unload",(long)TimeCurrent()*1000,TimeGMT(),GetTickCount64());
   replayRetry=0; ReplayFlush();
   if(replayFile!=INVALID_HANDLE) { FileClose(replayFile); replayFile=INVALID_HANDLE; }
   if(replayBuffer!="") Print("历史归档存在未落盘尾部，后续回放必须排除该会话未完整结束部分");
   replayStarted=false;
}
