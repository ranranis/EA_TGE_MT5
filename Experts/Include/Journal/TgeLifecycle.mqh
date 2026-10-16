// 复盘旁路：只记录，不参与pending、入场、保护或成交确认。
struct TgeLifeEvent
{
   ulong id,order,deal;
   datetime at;
   string key,kind,detail;
   double price,volume,sl,tp,mfe,mae;
};
struct TgeLifeWatch
{
   ulong id;
   int sign;
   double open,sl,tp,volume,mfe,mae;
   datetime saved;
   bool seen;
};
TgeLifeEvent lifeQueue[];
TgeLifeWatch lifeWatch[];
ulong lifeRevision=0,lifeRetryAt=0;
string lifeStatus="";
string lifeEntryContext="";
string LifePath(const ulong id)
{
   return "FeishuMT5SignalMonitor\\lifecycles\\"+prefix+IntegerToString((long)id)+".tsv";
}
string LifeClean(string text)
{
   StringReplace(text,"\t"," "); StringReplace(text,"\r"," "); StringReplace(text,"\n"," ");
   return text;
}
bool LifeParse(const string line,const ulong id,TgeLifeEvent &e)
{
   string f[];
   if(StringSplit(line,'\t',f)!=14 || f[0]!="L1" || f[13]!="END" || f[1]=="") return false;
   for(int i=2;i<=11;i++)
   {
      if(i==3) continue;
      if(!Number(f[i],i>=6)) return false;
   }
   ZeroMemory(e); e.id=id; e.key=f[1]; e.at=(datetime)StringToInteger(f[2]); e.kind=f[3];
   e.order=(ulong)StringToInteger(f[4]); e.deal=(ulong)StringToInteger(f[5]);
   e.price=StringToDouble(f[6]); e.volume=StringToDouble(f[7]);
   e.sl=StringToDouble(f[8]); e.tp=StringToDouble(f[9]);
   e.mfe=StringToDouble(f[10]); e.mae=StringToDouble(f[11]); e.detail=f[12];
   return e.at>0 && MathIsValidNumber(e.mfe) && MathIsValidNumber(e.mae);
}
bool LifeRead(const ulong id,TgeLifeEvent &rows[])
{
   ArrayResize(rows,0);
   if(!FileIsExist(LifePath(id),FILE_COMMON)) return true;
   int h=FileOpen(LifePath(id),FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(h==INVALID_HANDLE) return false;
   while(!FileIsEnding(h))
   {
      TgeLifeEvent e;
      if(!LifeParse(FileReadString(h),id,e)) continue; // 残缺尾行不当作完整记录
      int n=ArraySize(rows); ArrayResize(rows,n+1); rows[n]=e;
   }
   FileClose(h); return true;
}
bool LifeAppend(const TgeLifeEvent &e)
{
   FolderCreate("FeishuMT5SignalMonitor\\lifecycles",FILE_COMMON);
   int h=FileOpen(LifePath(e.id),FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(h==INVALID_HANDLE) return false;
   // 完整行的稳定key去重，覆盖写入成功但flush/确认中断后的重试。
   while(!FileIsEnding(h))
   {
      TgeLifeEvent old;
      if(LifeParse(FileReadString(h),e.id,old) && old.key==e.key) { FileClose(h); return true; }
   }
   string line="L1\t"+LifeClean(e.key)+"\t"+IntegerToString((long)e.at)+"\t"+LifeClean(e.kind)+"\t"+
      IntegerToString((long)e.order)+"\t"+IntegerToString((long)e.deal)+"\t"+
      DoubleToString(e.price,8)+"\t"+DoubleToString(e.volume,8)+"\t"+
      DoubleToString(e.sl,8)+"\t"+DoubleToString(e.tp,8)+"\t"+
      DoubleToString(e.mfe,8)+"\t"+DoubleToString(e.mae,8)+"\t"+LifeClean(e.detail)+"\tEND\r\n";
   FileSeek(h,0,SEEK_END); ResetLastError();
   uint written=FileWriteString(h,"\r\n"+line); FileFlush(h);
   bool ok=written>0 && GetLastError()==0; FileClose(h); return ok;
}
void LifeEnqueue(TgeLifeEvent &e)
{
   if(e.id==0) return;
   if(e.at==0) e.at=TimeCurrent();
   if(e.key=="") e.key=e.kind+"."+IntegerToString((long)e.at)+"."+IntegerToString((long)GetMicrosecondCount());
   for(int i=0;i<ArraySize(lifeQueue);i++) if(lifeQueue[i].id==e.id && lifeQueue[i].key==e.key) return;
   if(ArraySize(lifeQueue)>=512) { lifeStatus="复盘队列已满：部分新记录缺失"; return; }
   int n=ArraySize(lifeQueue); ArrayResize(lifeQueue,n+1); lifeQueue[n]=e; lifeRevision++;
}
void LifeDecision(const string event,const string detail,const uint retcode,const ulong deal)
{
   if(pending.kind==1 && event=="REQUEST_INTENT") lifeEntryContext=detail;
   if(pending.position==0 || (event!="REQUEST_INTENT" && event!="REQUEST_RESULT" &&
      event!="POSITION_CONFIRMED" && event!="ORDER_RECONCILED" && event!="POSITION_CLOSED")) return;
   TgeLifeEvent e; ZeroMemory(e);
   e.id=pending.position; e.order=pending.order; e.deal=deal;
   e.kind=event; e.volume=pending.volume; e.sl=pending.sl; e.tp=pending.tp;
   e.detail=detail+(retcode>0 ? " · ret="+IntegerToString(retcode) : "");
   LifeEnqueue(e);
}
void LifeEntry(const ulong id)
{
   TgeLifeEvent e; ZeroMemory(e); e.id=id; e.key="PLAN"; e.at=pending.at; e.order=pending.order;
   e.kind="PLAN"; e.price=pending.level; e.sl=pending.sl; e.tp=pending.tp; e.volume=pending.volume;
   e.detail=(pending.fixedExit ? "固定TP5/SL10" : pending.adaptive ? "结构持单" : "旧版分批")+
      " · 点位 "+DoubleToString(pending.level,_Digits)+" · 来源标识 "+IntegerToString(pending.originHash)+
      " · 首批 "+DoubleToString(pending.exitFirst,_Digits)+" · ATR "+DoubleToString(pending.entryAtr,2)+
      " · "+(lifeEntryContext=="" ? "重启后按已保存请求恢复；原判断文本缺失" : lifeEntryContext);
   LifeEnqueue(e);
}
void LifeFlush()
{
   ulong now=GetTickCount64();
   if(lifeRetryAt>now) return;
   int done=0,n=ArraySize(lifeQueue);
   for(;done<MathMin(n,8);done++)
   {
      if(!LifeAppend(lifeQueue[done])) { lifeStatus="复盘日志写入失败，等待重试"; lifeRetryAt=now+5000; break; }
   }
   if(done>0)
   {
      for(int i=done;i<n;i++) lifeQueue[i-done]=lifeQueue[i];
      ArrayResize(lifeQueue,n-done);
      if(n==done && lifeStatus!="复盘队列已满：部分新记录缺失") lifeStatus="";
   }
}
void LifePoll()
{
   if(lockHandle==INVALID_HANDLE || prefix=="" || AccountInfoInteger(ACCOUNT_LOGIN)!=accountLogin ||
      AccountInfoString(ACCOUNT_SERVER)!=accountServer) return;
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) { LifeFlush(); return; }
   for(int i=0;i<ArraySize(lifeWatch);i++) lifeWatch[i].seen=false;
   MqlTick q; bool fresh=FreshQuote(q);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0 || !OwnSelected()) continue;
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      double open=PositionGetDouble(POSITION_PRICE_OPEN),sl=PositionGetDouble(POSITION_SL),
             tp=PositionGetDouble(POSITION_TP),volume=PositionGetDouble(POSITION_VOLUME);
      int sign=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1;
      int at=-1;
      for(int j=0;j<ArraySize(lifeWatch);j++) if(lifeWatch[j].id==id) { at=j; break; }
      bool initial=at<0;
      if(initial)
      {
         at=ArraySize(lifeWatch); ArrayResize(lifeWatch,at+1); ZeroMemory(lifeWatch[at]);
         lifeWatch[at].id=id;
         TgeLifeEvent saved[];
         if(LifeRead(id,saved))
            for(int k=0;k<ArraySize(saved);k++)
            {
               lifeWatch[at].mfe=MathMax(lifeWatch[at].mfe,saved[k].mfe);
               lifeWatch[at].mae=MathMax(lifeWatch[at].mae,saved[k].mae);
            }
      }
      lifeWatch[at].seen=true; lifeWatch[at].open=open; lifeWatch[at].sign=sign;
      if(fresh)
      {
         double move=sign*((sign>0 ? q.bid : q.ask)-open);
         lifeWatch[at].mfe=MathMax(lifeWatch[at].mfe,move);
         lifeWatch[at].mae=MathMax(lifeWatch[at].mae,-move);
      }
      bool changed=initial || MathAbs(sl-lifeWatch[at].sl)>TickSize()*0.5 ||
                   MathAbs(tp-lifeWatch[at].tp)>TickSize()*0.5 || MathAbs(volume-lifeWatch[at].volume)>1e-8;
      if(changed || TimeCurrent()-lifeWatch[at].saved>=60)
      {
         TgeLifeEvent e; ZeroMemory(e); e.id=id; e.sl=sl; e.tp=tp; e.volume=volume;
         e.price=fresh ? (sign>0 ? q.bid : q.ask) : 0;
         e.mfe=lifeWatch[at].mfe; e.mae=lifeWatch[at].mae;
         e.kind=initial ? "OBSERVE" : changed ? "POSITION" : "SAMPLE";
         e.detail=initial ? "开始/恢复在线采样；离线及采样间隔内路径未知" :
                  changed ? "实际持仓量/SL/TP变化；仅凭快照不推断修改来源" : "在线1秒采样累计极值，非逐tick完整轨迹";
         LifeEnqueue(e); lifeWatch[at].saved=TimeCurrent();
      }
      lifeWatch[at].sl=sl; lifeWatch[at].tp=tp; lifeWatch[at].volume=volume;
   }
   for(int i=ArraySize(lifeWatch)-1;i>=0;i--)
   {
      if(lifeWatch[i].seen) continue;
      // 离开观测列表只表示当前仓位不可见，完整平仓仍由真实Deal复盘核对。
      TgeLifeEvent e; ZeroMemory(e); e.id=lifeWatch[i].id; e.kind="OBSERVE_END";
      e.mfe=lifeWatch[i].mfe; e.mae=lifeWatch[i].mae;
      e.detail="仓位离开在线观测；退出结果以成交历史为准"; LifeEnqueue(e);
      int last=ArraySize(lifeWatch)-1; if(i!=last) lifeWatch[i]=lifeWatch[last];
      ArrayResize(lifeWatch,last);
   }
   LifeFlush();
}
