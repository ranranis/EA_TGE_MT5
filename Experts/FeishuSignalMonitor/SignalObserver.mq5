// 只显示本地模拟信号：没有交易对象或真实委托接口。
#property strict
#property version "1.00"
#property description "LOCAL PAPER SIMULATION ONLY - Feishu signal observer"
input string SignalFile="FeishuMT5SignalMonitor\\signals.csv";
input int RefreshSeconds=2;
input int StaleSeconds=120;
string prefix="FSM_PAPER_";
struct PaperRow
{
   string id,symbol,side,status,tps,source;
   double entry,sl,remaining;
   datetime opened;
   bool invalid;
};

void Label(const string text,const color c)
{
   string name=prefix+"STATUS";
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,12);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,32);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
}

void Line(const string name,const double price,const string text,const color c)
{
   if(price<=0) return;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,c);
   ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,text+" "+DoubleToString(price,_Digits));
}

bool ReadSnapshot(PaperRow &rows[],datetime &generated,bool &paused,string &currency)
{
   int h=FileOpen(SignalFile,FILE_READ|FILE_CSV|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE,',',CP_UTF8);
   if(h==INVALID_HANDLE) return false;
   string tag=FileReadString(h);
   if(tag!="META") {FileClose(h);return false;}
   string version=FileReadString(h);
   generated=(datetime)StringToInteger(FileReadString(h));
   int count=(int)StringToInteger(FileReadString(h));
   paused=(StringToInteger(FileReadString(h))!=0);
   currency=FileReadString(h);
   if(version!="1" || count<0 || count>100) {FileClose(h);return false;}
   ArrayResize(rows,count);
   for(int i=0;i<count;i++)
   {
      if(FileIsEnding(h) || FileReadString(h)!="ORDER") {FileClose(h);return false;}
      rows[i].id=FileReadString(h);
      rows[i].symbol=FileReadString(h);
      rows[i].side=FileReadString(h);
      rows[i].status=FileReadString(h);
      rows[i].entry=StringToDouble(FileReadString(h));
      rows[i].sl=StringToDouble(FileReadString(h));
      rows[i].tps=FileReadString(h);
      rows[i].remaining=StringToDouble(FileReadString(h));
      rows[i].opened=(datetime)StringToInteger(FileReadString(h));
      rows[i].invalid=(StringToInteger(FileReadString(h))!=0);
      rows[i].source=FileReadString(h);
      if(rows[i].side!="BUY" && rows[i].side!="SELL") {FileClose(h);return false;}
   }
   bool valid=(FileReadString(h)=="END" && (int)StringToInteger(FileReadString(h))==count);
   FileClose(h);
   return valid;
}

bool HasName(const string &names[],const string name)
{
   for(int i=0;i<ArraySize(names);i++) if(names[i]==name) return true;
   return false;
}
void Keep(string &names[],const string name)
{
   int n=ArraySize(names);ArrayResize(names,n+1);names[n]=name;
}

void OnTimer()
{
   PaperRow rows[];datetime generated=0;bool paused=false;string currency="";
   if(!ReadSnapshot(rows,generated,paused,currency))
   {
      Label("SIM ONLY | 等待完整模拟信号文件（旧标记仅供参考）",clrOrange);
      return;
   }
   bool stale=((long)TimeGMT()-(long)generated>StaleSeconds || generated>TimeGMT()+5);
   string keep[];Keep(keep,prefix+"STATUS");
   int positions=0,pending=0;
   for(int i=0;i<ArraySize(rows);i++)
   {
      PaperRow r=rows[i];
      if(r.symbol!=_Symbol) continue;
      if(r.status!="OPEN" && r.status!="PENDING") continue;
      if(r.status=="OPEN") positions++;else pending++;
      color c=r.side=="BUY"?clrLimeGreen:clrTomato;
      if(r.invalid) c=clrOrange;
      string base=prefix+r.id+"_";
      string title="SIM "+r.side+" #"+r.id+" "+r.status+(r.invalid?" 待核对":"");
      Keep(keep,base+"ENTRY");Line(base+"ENTRY",r.entry,title,c);
      Keep(keep,base+"SL");Line(base+"SL",r.sl,title+" SL",clrOrangeRed);
      string targets[];int n=StringSplit(r.tps,'|',targets);
      for(int j=0;j<n && j<8;j++)
      {
         string name=base+"TP"+IntegerToString(j+1);Keep(keep,name);
         Line(name,StringToDouble(targets[j]),title+" TP"+IntegerToString(j+1),clrDeepSkyBlue);
      }
      if(r.status=="OPEN")
      {
         string name=base+"ARROW";Keep(keep,name);
         datetime chart_time=r.opened+(TimeTradeServer()-TimeGMT());
         if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_ARROW,0,chart_time,r.entry);
         else ObjectMove(0,name,0,chart_time,r.entry);
         ObjectSetInteger(0,name,OBJPROP_ARROWCODE,r.side=="BUY"?233:234);
         ObjectSetInteger(0,name,OBJPROP_COLOR,c);
         ObjectSetString(0,name,OBJPROP_TOOLTIP,title+" 模拟剩余手数 "+DoubleToString(r.remaining,4));
      }
   }
   for(int i=ObjectsTotal(0)-1;i>=0;i--)
   {
      string name=ObjectName(0,i);
      if(StringFind(name,prefix)==0 && !HasName(keep,name)) ObjectDelete(0,name);
   }
   string status=stale?"数据过期":paused?"暂停新增成交":"运行中";
   Label("SIM ONLY | "+status+" | "+_Symbol+" 模拟持仓 "+IntegerToString(positions)+" 挂单 "+IntegerToString(pending)+" | "+currency,stale||paused?clrOrange:clrAqua);
   ChartRedraw();
}

int OnInit()
{
   if(RefreshSeconds<1 || StaleSeconds<5) return INIT_PARAMETERS_INCORRECT;
   EventSetTimer(RefreshSeconds);OnTimer();return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   EventKillTimer();ObjectsDeleteAll(0,prefix);ChartRedraw();
}
