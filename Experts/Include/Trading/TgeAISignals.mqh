#ifndef TGE_AI_SIGNALS_MQH
#define TGE_AI_SIGNALS_MQH
// 这里只读经Python校验的参考快照；模型无权决定账号、手数或调用交易接口。
struct AIPlan { int sign; double level; bool market,near; };
AIPlan aiPlans[];
string aiMode="WAIT",aiReason="等待AI策略桥接",aiSource="",aiIdentity="";
datetime aiGenerated=0,aiSourceTime=0;
bool aiReady=false;

bool ReadAISetups()
{
   aiReady=false;
   int h=FileOpen("FeishuMT5SignalMonitor\\tge_ai_setups.csv",FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(h==INVALID_HANDLE) { aiReason="AI快照尚未生成"; return false; }
   string lines[];
   bool ok=FileSize(h)<=8192;
   while(ok && !FileIsEnding(h))
   {
      int n=ArraySize(lines); if(n>=6) { ok=false; break; }
      ArrayResize(lines,n+1); lines[n]=FileReadString(h);
   }
   FileClose(h);
   string head[],foot[];
   if(!ok || ArraySize(lines)<2 || StringSplit(lines[0],',',head)!=11 ||
      head[0]!="TGA" || head[1]!="1" || head[4]!=_Symbol ||
      !Number(head[2]) || !Number(head[7]) || !Number(head[8]) || (head[3]!="0" && head[3]!="1"))
   { aiReason="AI快照格式错误"; return false; }
   int count=(int)StringToInteger(head[8]);
   datetime generated=(datetime)StringToInteger(head[2]),at=(datetime)StringToInteger(head[7]);
   if(count>4 || ArraySize(lines)!=count+2 || StringSplit(lines[count+1],',',foot)!=2 ||
      foot[0]!="END" || foot[1]!=head[8] || generated>TimeGMT()+5 || TimeGMT()-generated>10 || at>TimeGMT()+5 ||
      (head[9]!="MAP" && head[9]!="SETUP" && head[9]!="WAIT"))
   { aiReason="AI快照不完整/心跳中断"; return false; }
   AIPlan incoming[]; ArrayResize(incoming,count);
   for(int i=0;i<count;i++)
   {
      string fields[];
      if(StringSplit(lines[i+1],',',fields)!=5 || fields[0]!="SETUP" ||
         (fields[1]!="BUY" && fields[1]!="SELL") || !Number(fields[2],true) ||
         (fields[3]!="REACTION" && fields[3]!="MARKET") || (fields[4]!="POINT" && fields[4]!="NEAR"))
      { aiReason="AI方向/价格字段无效"; return false; }
      incoming[i].sign=fields[1]=="BUY" ? 1 : -1;
      incoming[i].level=StringToDouble(fields[2]); incoming[i].market=fields[3]=="MARKET"; incoming[i].near=fields[4]=="NEAR";
      if(incoming[i].level<=0 || !MathIsValidNumber(incoming[i].level)) return false;
   }
   bool active=head[3]=="1";
   if(active && (at<=0 || head[5]=="" || head[6]=="" ||
      (head[9]=="SETUP" && count<1) || (head[9]=="MAP" && count!=0))) return false;
   string next=head[5]+"|"+head[6]+"|"+head[9];
   if(active && (!aiReady || next!=aiIdentity))
   {
      // 仅在来源/模式变化时建立新收线围栏，绝不按历史消息补历史单。
      if(next!=aiIdentity) { readyFrom=TimeCurrent(); lastMinute=0; }
   }
   aiIdentity=next; aiSource=head[5]; aiMode=head[9]; aiSourceTime=at; aiGenerated=generated;
   aiReason=head[10]; aiReady=active;
   ArrayResize(aiPlans,count); ArrayCopy(aiPlans,incoming);
   return true;
}
string AIVisitKey(const double level,const int sign)
{
   return "av"+IntegerToString((long)Hash(aiIdentity))+"_"+DoubleToString(level,_Digits)+"_"+IntegerToString(sign);
}
string AIPlanCaption()
{
   if(!aiReady) return "AI："+aiReason;
   if(aiMode=="MAP") return "AI已理解完整点位地图";
   string text="AI "+TimeToString(aiSourceTime+8*3600,TIME_MINUTES)+"：";
   for(int i=0;i<ArraySize(aiPlans);i++)
      text+=(i>0 ? " / " : "")+(aiPlans[i].sign>0 ? "BUY " : "SELL ")+DoubleToString(aiPlans[i].level,_Digits);
   return text;
}
bool AISignal(const MqlRates &bar,const MqlTick &q,Candidate &out)
{
   double nearest=DBL_MAX,tolerance=MathMax(atr*0.20,TickSize()*2),escape=MathMax(atr*0.05,TickSize());
   reason="等待T哥即时点位附近的收线反应";
   for(int i=0;i<ArraySize(aiPlans);i++)
   {
      int sign=aiPlans[i].sign; double level=aiPlans[i].level;
      double entry=sign>0 ? q.ask : q.bid,gap=sign*(entry-level);
      string key=AIVisitKey(level,sign);
      datetime consumed=(datetime)Load(key);
      if(!aiPlans[i].market && consumed>0 && bar.time>consumed && MathAbs(bar.close-level)>MathMax(atr,2.0)) Store(key,0);
      // “接近/附近/60开”允许同一价格档的参考区域；宽度来自既有10点保险预算，不由AI编造。
      double allowed=aiPlans[i].near && !aiPlans[i].market ? 保险价格距离 : MathMin(atr*0.75,首批止盈价格距离*0.8);
      double touch=aiPlans[i].near ? allowed : tolerance;
      bool reaction=sign>0 ? bar.low<=level+touch && bar.high>=level-tolerance &&
                            bar.close>level+escape && bar.close>bar.open :
                            bar.high>=level-touch && bar.low<=level+tolerance &&
                            bar.close<level-escape && bar.close<bar.open;
      double tp;
      string blocked=aiPlans[i].market && TimeGMT()-aiSourceTime>180 ? "市价喊单已过时，不补历史单" :
                     Load(key)>0 ? "本次AI点位机会已消费，等待重新离开" :
                     gap<0 || gap>=allowed ? "等待靠近AI即时点位，不追价" :
                     !aiPlans[i].market && !reaction ? "等待M1在AI点位止跌/受阻" :
                     !Target(entry,sign,tp) ? "AI区间不足首批止盈空间" : "";
      if(MathAbs(gap)<nearest)
      {
         nearest=MathAbs(gap); entryView.ready=true; entryView.level=level; entryView.direction=sign;
         entryView.distance=MathAbs(gap); entryView.reaction=reaction;
         entryView.method="T哥AI即时点位"; reason=blocked; entryView.space=0;
      }
      if(blocked!="") continue;
      out.valid=true; out.ai=true; out.direction=sign; out.level=level; out.bar=bar.time;
      out.method=(aiPlans[i].market ? "T哥AI市价指令[" : "T哥AI即时点位[")+aiSource+"]"; reason=out.method; return true;
   }
   return false;
}
bool AIMarketSignal(Candidate &out)
{
   if(!feedActive || !读取AI即时策略 || !aiReady || aiMode!="SETUP" || TimeGMT()-aiGenerated>10) return false;
   bool market=false;
   for(int i=0;i<ArraySize(aiPlans);i++) if(aiPlans[i].market) market=true;
   if(!market) return false;
   MqlTick q; double values[];
   if(!FreshQuote(q) || q.ask-q.bid>最大点差价格 ||
      CopyBuffer(atrHandle,0,1,1,values)!=1 || !MathIsValidNumber(values[0]) || values[0]<=TickSize()) return false;
   atr=values[0]; MqlRates bar; ZeroMemory(bar); bar.time=TimeCurrent();
   return AISignal(bar,q,out);
}
#endif
