#ifndef TGE_AI_SIGNALS_MQH
#define TGE_AI_SIGNALS_MQH
// 这里只读经Python校验的参考快照；模型无权决定账号、手数或调用交易接口。
struct AIPlan { int sign; double level,sl,first,tp,breakeven; bool market,near; string origin,status; datetime created,left; };
AIPlan aiPlans[];
string aiMode="WAIT",aiReason="等待AI策略桥接",aiSource="",aiIdentity="";
datetime aiGenerated=0,aiSourceTime=0;
bool aiReady=false;
bool aiPlanCached=false;

bool AIChannelReady()
{
   long now=(long)TimeGMT();
   return aiReady && healthOK && !healthPaused && aiGenerated>0 && healthBeat>0 && healthSync>0 && healthCheckpoint>0 && aiGenerated<=now+5 &&
          now-aiGenerated<=healthMaxAge && healthBeat<=now+5 && healthSync<=now+5 &&
          healthCheckpoint<=now+5 && now-healthBeat<=healthMaxAge &&
          now-healthSync<=healthMaxAge && now-healthCheckpoint<=healthMaxAge;
}
bool KeepCachedAI(const string why)
{
   aiReady=aiPlanCached;
   if(AIChannelReady())
   {
      aiReason=why+"；同步健康，短暂沿用已验证计划";
      return true;
   }
   aiReady=false; aiReason=why; return false;
}
bool InvalidAI(const string why)
{
   aiReady=false; aiPlanCached=false; aiReason=why; return false;
}

bool ReadAISetups()
{
   aiReady=false;
   int h=FileOpen("FeishuMT5SignalMonitor\\tge_ai_setups.csv",FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(h==INVALID_HANDLE) return KeepCachedAI("AI快照暂时不可读");
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
      head[0]!="TGA" || (head[1]!="1" && head[1]!="2" && head[1]!="3") || head[4]!=_Symbol ||
      !Number(head[2]) || !Number(head[7]) || !Number(head[8]) || (head[3]!="0" && head[3]!="1"))
   { return InvalidAI("AI快照格式错误"); }
   int count=(int)StringToInteger(head[8]);
   datetime generated=(datetime)StringToInteger(head[2]),at=(datetime)StringToInteger(head[7]);
   if(count>4 || ArraySize(lines)!=count+2 || StringSplit(lines[count+1],',',foot)!=2 ||
      foot[0]!="END" || foot[1]!=head[8] || generated>TimeGMT()+5 || TimeGMT()-generated>healthMaxAge || at>TimeGMT()+5 ||
      (head[9]!="MAP" && head[9]!="SETUP" && head[9]!="WAIT"))
   { return InvalidAI("AI快照心跳中断"); }
   AIPlan incoming[]; ArrayResize(incoming,count);
   for(int i=0;i<count;i++)
   {
      string fields[];
      if(StringSplit(lines[i+1],',',fields)!=(head[1]=="3" ? 12 : head[1]=="2" ? 8 : 5) || fields[0]!="SETUP" ||
         (fields[1]!="BUY" && fields[1]!="SELL") || !Number(fields[2],true) ||
         (fields[3]!="REACTION" && fields[3]!="MARKET") || (fields[4]!="POINT" && fields[4]!="NEAR"))
      { return InvalidAI("AI方向/价格字段无效"); }
      incoming[i].left=0; incoming[i].status="等待靠近";
      incoming[i].sl=0; incoming[i].first=0; incoming[i].tp=0; incoming[i].breakeven=0;
      incoming[i].sign=fields[1]=="BUY" ? 1 : -1;
      incoming[i].level=StringToDouble(fields[2]); incoming[i].market=fields[3]=="MARKET"; incoming[i].near=fields[4]=="NEAR";
      incoming[i].origin=head[5]+"|"+head[6]+"|"+head[9]; incoming[i].created=at;
      if(head[1]!="1")
      {
         if(fields[5]=="" || fields[6]=="" || !Number(fields[7]) ||
            StringToInteger(fields[7])<=0 || StringToInteger(fields[7])>TimeGMT()+5)
        { return InvalidAI("AI计划来源无效"); }
         incoming[i].origin=fields[5]+"|"+fields[6]+"|SETUP";
         incoming[i].created=(datetime)StringToInteger(fields[7]);
      }
      if(head[1]=="3")
      {
         for(int k=8;k<12;k++)
            if(!Number(fields[k],true) || !MathIsValidNumber(StringToDouble(fields[k]))) return InvalidAI("退出价格无效");
         incoming[i].sl=StringToDouble(fields[8]); incoming[i].first=StringToDouble(fields[9]);
         incoming[i].tp=StringToDouble(fields[10]); incoming[i].breakeven=StringToDouble(fields[11]);
         int sign=incoming[i].sign; double level=incoming[i].level;
         if((incoming[i].sl>0 && sign*(level-incoming[i].sl)<=0) ||
            (incoming[i].first>0 && sign*(incoming[i].first-level)<=0) ||
            (incoming[i].tp>0 && sign*(incoming[i].tp-level)<=0) ||
            (incoming[i].breakeven>0 && sign*(incoming[i].breakeven-level)<=0) ||
            (incoming[i].first>0 && incoming[i].tp>0 && sign*(incoming[i].tp-incoming[i].first)<=0))
            return InvalidAI("退出价格方向/先后顺序无效");
      }
      if(incoming[i].level<=0 || !MathIsValidNumber(incoming[i].level)) return InvalidAI("AI计划价格无效");
   }
   bool active=head[3]=="1";
   if(active && (at<=0 || head[5]=="" || head[6]=="" ||
      (head[9]=="WAIT") || (head[9]=="SETUP" && count<1) || (head[9]=="MAP" && count!=0))) return InvalidAI("AI快照激活状态无效");
   string next=head[5]+"|"+head[6]+"|"+head[9];
   if(active && (!aiReady || next!=aiIdentity))
   {
      // 仅在来源/模式变化时建立新收线围栏，绝不按历史消息补历史单。
      if(next!=aiIdentity) { readyFrom=TimeCurrent(); lastMinute=0; }
   }
   aiIdentity=next; aiSource=head[5]; aiMode=head[9]; aiSourceTime=at; aiGenerated=generated;
   aiReason=head[10]; aiReady=active;
   aiPlanCached=active && head[9]=="SETUP" && count>0;
   for(int i=0;i<count;i++)
      for(int j=0;j<ArraySize(aiPlans);j++)
         if(aiPlans[j].origin==incoming[i].origin && aiPlans[j].sign==incoming[i].sign && aiPlans[j].level==incoming[i].level)
         { incoming[i].left=aiPlans[j].left; incoming[i].status=aiPlans[j].status; break; }
   ArrayResize(aiPlans,count);
   for(int i=0;i<count;i++)
   {
      aiPlans[i]=incoming[i]; // 来源字符串不使用ArrayCopy。
   }
   return true;
}
// 消费状态沿用旧键，形式编辑和同价重述的origin由Python稳定化。
string AIKeyFromHash(const uint originHash,const double level,const int sign)
{
   return "av"+IntegerToString((long)originHash)+"_"+DoubleToString(level,_Digits)+"_"+IntegerToString(sign);
}
string AIVisitKey(const double level,const int sign)
{
   string origin=aiIdentity;
   for(int i=0;i<ArraySize(aiPlans);i++)
      if(aiPlans[i].sign==sign && MathAbs(aiPlans[i].level-level)<=TickSize() && aiPlans[i].origin!="")
         { origin=aiPlans[i].origin; break; }
   return AIKeyFromHash(Hash(origin),level,sign);
}
const double TEACHER_BAND=2.00,REARM_DISTANCE=4.00;
const int REARM_SECONDS=5;
struct TickSample { long at; double bid,ask; };
TickSample fastTicks[256];
int fastCount=0,fastCursor=0;
long fastLast=0;
datetime fastStarted=0;

void RememberFastTick(const MqlTick &q)
{
   if(q.time_msc<=fastLast) return;
   // 最多每50ms一份样本，避免密集报价把3秒窗挤成不足1秒。
   if(fastLast>0 && q.time_msc-fastLast<50) return;
   if(fastLast>0 && q.time_msc-fastLast>1500) { fastCount=0; fastCursor=0; }
   fastTicks[fastCursor].at=q.time_msc; fastTicks[fastCursor].bid=q.bid; fastTicks[fastCursor].ask=q.ask;
   fastCursor=(fastCursor+1)%256; fastCount=MathMin(fastCount+1,256); fastLast=q.time_msc;
}
// 纯tick计算：正值speed表示逆向净速度。缺样本返回false，不假装没有冲击。
bool TickImpact(const int sign,const long now,double &speed,double &oneway,double &pullback)
{
   int count=0; long first=0,last=0,maxGap=0;
   double start=0,end=0,previous=0,total=0,adverse=0,extreme=0;
   speed=0; oneway=0; pullback=0;
   for(int i=0;i<fastCount;i++)
   {
      int index=(fastCursor-fastCount+i+256)%256;
      long at=fastTicks[index].at;
      if(at<now-冲击短窗毫秒 || at>now) continue;
      double price=sign>0 ? fastTicks[index].ask : fastTicks[index].bid;
      if(count==0) { first=at; start=price; extreme=price; }
      else
      {
         double move=-sign*(price-previous);
         adverse+=MathMax(move,0); total+=MathAbs(move); maxGap=MathMax(maxGap,at-last);
         extreme=sign>0 ? MathMin(extreme,price) : MathMax(extreme,price);
      }
      end=price; previous=price; last=at; count++;
   }
   if(count<4 || last-first<1000 || maxGap>1500 || now-last>1500) return false;
   speed=-sign*(end-start)/((last-first)/1000.0);
   oneway=total>0 ? adverse/total : 0;
   pullback=sign*(end-extreme);
   return true;
}
bool InTeacherBand(const double entry,const double level)
{
   // 含两端：黄金报价差2.00，非_Point；浮点误差只容许1e-8。
   return MathAbs(entry-level)<=TEACHER_BAND+1e-8;
}
bool LiveTeacherPlan(const int i)
{
   return 读取AI即时策略 && AIChannelReady() && aiMode=="SETUP" &&
          (!aiPlans[i].market || (aiPlans[i].created>fastStarted && TimeGMT()>=aiPlans[i].created && TimeGMT()-aiPlans[i].created<180));
}
bool TeacherOwnsZone(const MqlTick &q)
{
   for(int i=0;i<ArraySize(aiPlans);i++)
      if(LiveTeacherPlan(i) && InTeacherBand(aiPlans[i].sign>0 ? q.ask : q.bid,aiPlans[i].level)) return true;
   return false;
}
bool TeacherEntryAllowed(const int i,const MqlTick &q)
{
   double entry=aiPlans[i].sign>0 ? q.ask : q.bid;
   string status="",key=AIVisitKey(aiPlans[i].level,aiPlans[i].sign);
   double speed=0,oneway=0,pullback=0;
   if(!LiveTeacherPlan(i)) status="来源未就绪/市价已过时";
   else if(!InTeacherBand(entry,aiPlans[i].level)) status="离开允许区域，不追价";
   else if(SameOpportunity(aiPlans[i].sign,aiPlans[i].level) && Load(key)==0) status="同向同机会已合并，等待重新离区";
   else if(Load(key)>0) status="本次触及已消费，需离开4.00至少5秒后再回区";
   else if(Load(key+"r")>TimeGMT()) status="明确拒绝后的短暂重试冷却";
   else if(!TickImpact(aiPlans[i].sign,q.time_msc,speed,oneway,pullback)) status="短暂采样：需4个tick覆盖1秒";
   else if(speed>=逆向冲击速度 && oneway>=冲击单向比例 && pullback<恢复回拉价格)
      status="逆向连续冲穿暂缓";
   else status=aiPlans[i].status=="逆向连续冲穿暂缓" ? "冲击已恢复，区域内候选" : "近价候选：无需等收线";
   aiPlans[i].status=status;
   return status=="近价候选：无需等收线" || status=="冲击已恢复，区域内候选";
}
void UpdateTeacherVisits(const MqlTick &q)
{
   // Tick和定时器观察离区；重启清掉left计时但保留消费，不把停机时间算离区。
   for(int i=0;i<ArraySize(aiPlans);i++)
   {
      string key=AIVisitKey(aiPlans[i].level,aiPlans[i].sign);
      double entry=aiPlans[i].sign>0 ? q.ask : q.bid;
      if(Load(key)>0 && !aiPlans[i].market && 允许同机会重入 &&
         MathAbs(entry-aiPlans[i].level)>=REARM_DISTANCE && pending.kind==0)
      {
         if(aiPlans[i].left==0) aiPlans[i].left=TimeGMT();
         if(TimeGMT()-aiPlans[i].left>=REARM_SECONDS)
         { Store(key,0); GlobalVariablesFlush(); aiPlans[i].left=0; aiPlans[i].status="已离区重新允许，等待回到区域"; }
      }
      else aiPlans[i].left=0;
   }
}
bool AISignal(const MqlRates &bar,const MqlTick &q,Candidate &out)
{
   // 保留旧入口签名，条件计划已完全独立于bar/ATR/M5趋势。
   double nearest=DBL_MAX;
   for(int i=0;i<ArraySize(aiPlans);i++)
   {
      bool allowed=TeacherEntryAllowed(i,q);
      double gap=MathAbs((aiPlans[i].sign>0 ? q.ask : q.bid)-aiPlans[i].level);
      if(gap<nearest)
      {
         nearest=gap; reason=aiPlans[i].status; entryView.ready=true;
         entryView.level=aiPlans[i].level; entryView.direction=aiPlans[i].sign;
         entryView.distance=gap; entryView.bar=TimeCurrent(); entryView.reaction=allowed; entryView.method="T哥实时近价";
      }
      if(!allowed) continue;
      out.valid=true; out.ai=true; out.follow=false; out.direction=aiPlans[i].sign; out.level=aiPlans[i].level;
      out.bar=TimeCurrent(); out.originHash=Hash(aiPlans[i].origin); out.aiKey=AIVisitKey(out.level,out.direction);
      out.exitSL=aiPlans[i].sl; out.exitFirst=aiPlans[i].first;
      out.exitTP=aiPlans[i].tp; out.exitBE=aiPlans[i].breakeven;
      out.method=(aiPlans[i].market ? "T哥市价候选[" : "T哥近价候选[")+aiSource+"]";
      reason=out.method; return true;
   }
   return false;
}
bool AIMarketSignal(Candidate &out)
{
   // 兼容旧调用名：MARKET与持续条件计划都走实时通道，不调用CopyRates/CopyBuffer。
   if(!读取AI即时策略 || !AIChannelReady() || aiMode!="SETUP") return false;
   MqlTick q;
   if(!FreshQuote(q)) { reason="报价过期/断线"; return false; }
   RememberFastTick(q);
   if(q.ask-q.bid>最大点差价格) { reason="点差过大"; return false; }
   MqlRates unused; ZeroMemory(unused);
   return AISignal(unused,q,out);
}
string AIPlanCaption()
{
   if(!AIChannelReady()) return "老师通道WAIT："+aiReason;
   if(aiMode=="MAP") return "中性地图已就绪 · 普通策略仍用M5/M1确认";
   return "老师计划优先 · 实时±2.00 · 请求后等待券商Deal确认";
}

struct FollowMember
{
   string sender,name,source,revision,reason;
   bool ready;
   int sign,ttl;
   double price,adverse;
   datetime created,expiry;
};
FollowMember followMembers[];
int followIndex=-1;
bool followReady=false;
datetime followGenerated=0;
string followReason="等待学生本人入场参考";
string FollowVisitKey(const int index=-1)
{
   int i=index<0 ? followIndex : index;
   return i>=0 && i<ArraySize(followMembers) ? "fv"+IntegerToString((long)Hash(followMembers[i].source)) : "";
}
string FollowMissKey(const int index=-1)
{
   int i=index<0 ? followIndex : index;
   return i>=0 && i<ArraySize(followMembers) ? "fm"+IntegerToString((long)Hash(followMembers[i].source)) : "";
}
bool ReadLegacyFollow()
{
   int h=FileOpen("FeishuMT5SignalMonitor\\tge_member_follow.csv",FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(h==INVALID_HANDLE) return false;
   string lines[]; bool ok=FileSize(h)<=4096;
   while(ok && !FileIsEnding(h))
   {
      int n=ArraySize(lines); if(n>=3) { ok=false; break; }
      ArrayResize(lines,n+1); lines[n]=FileReadString(h);
   }
   FileClose(h); string head[],foot[],fields[];
   if(!ok || ArraySize(lines)<2 || StringSplit(lines[0],',',head)!=12 || head[0]!="TGF" || head[1]!="1" ||
      head[4]!=_Symbol || !Number(head[2]) || !Number(head[7]) || !Number(head[8]) || !Number(head[10]) ||
      (head[3]!="0" && head[3]!="1")) return false;
   int n=(int)StringToInteger(head[10]);
   datetime generated=(datetime)StringToInteger(head[2]),at=(datetime)StringToInteger(head[7]),expiry=(datetime)StringToInteger(head[8]);
   if(n>1 || ArraySize(lines)!=n+2 || StringSplit(lines[n+1],',',foot)!=2 || foot[0]!="END" || foot[1]!=head[10] ||
      generated>TimeGMT()+5 || TimeGMT()-generated>10 || at>TimeGMT()+5 || expiry-at!=300) return false;
   followGenerated=generated;
   if(head[3]=="0") { ArrayResize(followMembers,0); followReason=head[11]; return n==0; }
   if(n!=1 || at<=0 || head[5]=="" || head[6]=="" || head[9]=="" ||
      StringSplit(lines[1],',',fields)!=3 || fields[0]!="FOLLOW" || (fields[1]!="BUY" && fields[1]!="SELL") || !Number(fields[2],true)) return false;
   ArrayResize(followMembers,1);
   followMembers[0].sender=head[9]; followMembers[0].name="起飞"; followMembers[0].source=head[5]; followMembers[0].revision=head[6];
   followMembers[0].created=at; followMembers[0].expiry=expiry; followMembers[0].ttl=300;
   followMembers[0].price=StringToDouble(fields[2]); followMembers[0].sign=fields[1]=="BUY" ? 1 : -1;
   followMembers[0].adverse=起飞最大追价价格差; followMembers[0].reason=head[11];
   followMembers[0].ready=MathIsValidNumber(followMembers[0].price) && followMembers[0].price>0 && TimeGMT()<expiry;
   followReady=followMembers[0].ready; return true;
}
bool ReadMemberFollow()
{
   followReady=false; followIndex=-1;
   int h=FileOpen("FeishuMT5SignalMonitor\\tge_member_follows.csv",FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(h==INVALID_HANDLE) return ReadLegacyFollow();
   string lines[]; bool ok=FileSize(h)<=16384;
   while(ok && !FileIsEnding(h))
   {
      int n=ArraySize(lines); if(n>=10) { ok=false; break; }
      ArrayResize(lines,n+1); lines[n]=FileReadString(h);
   }
   FileClose(h); string head[],foot[];
   if(!ok || ArraySize(lines)<2 || StringSplit(lines[0],',',head)!=5 || head[0]!="TGF" || head[1]!="2" ||
      head[3]!=_Symbol || !Number(head[2]) || !Number(head[4])) { followReason="学生快照格式无效"; return false; }
   int count=(int)StringToInteger(head[4]); datetime generated=(datetime)StringToInteger(head[2]);
   if(count>8 || ArraySize(lines)!=count+2 || StringSplit(lines[count+1],',',foot)!=2 || foot[0]!="END" || foot[1]!=head[4] ||
      generated>TimeGMT()+5 || TimeGMT()-generated>10) { followReason="学生快照过期/不完整"; return false; }
   FollowMember incoming[]; ArrayResize(incoming,count);
   for(int i=0;i<count;i++)
   {
      string f[];
      if(StringSplit(lines[i+1],',',f)!=13 || f[0]!="MEMBER" || f[1]=="" || f[2]=="" || (f[3]!="0" && f[3]!="1") ||
         !Number(f[6]) || !Number(f[7]) || !Number(f[8]) || !Number(f[9],true) || !Number(f[11],true)) return false;
      incoming[i].sender=f[1]; incoming[i].name=f[2]; incoming[i].source=f[4]; incoming[i].revision=f[5];
      incoming[i].created=(datetime)StringToInteger(f[6]); incoming[i].expiry=(datetime)StringToInteger(f[7]);
      incoming[i].ttl=(int)StringToInteger(f[8]); incoming[i].adverse=StringToDouble(f[9]);
      if(incoming[i].sender=="ou_cb14bfbe46d981efccc5473ff3a68aee") incoming[i].adverse=起飞最大追价价格差;
      incoming[i].price=StringToDouble(f[11]); incoming[i].sign=f[10]=="BUY" ? 1 : -1;
      incoming[i].reason=f[12]; incoming[i].ready=f[3]=="1" && TimeGMT()<incoming[i].expiry;
      for(int j=0;j<i;j++) if(incoming[j].sender==incoming[i].sender) return false;
      if(incoming[i].ttl<1 || incoming[i].ttl>3600 || incoming[i].adverse<=0 || !MathIsValidNumber(incoming[i].adverse) ||
         incoming[i].created>TimeGMT()+5 || (f[3]=="1" && (incoming[i].created<=0 || incoming[i].source=="" || incoming[i].revision=="" ||
         incoming[i].expiry-incoming[i].created!=incoming[i].ttl || (f[10]!="BUY" && f[10]!="SELL") || incoming[i].price<=0 || !MathIsValidNumber(incoming[i].price)))) return false;
   }
   ArrayResize(followMembers,count);
   for(int i=0;i<count;i++) { followMembers[i]=incoming[i]; if(incoming[i].ready) followReady=true; }
   followGenerated=generated; followReason="学生账号独立就绪"; return true;
}
bool FollowEnabled(const int i)
{
   return followMembers[i].sender=="ou_cb14bfbe46d981efccc5473ff3a68aee" ? 启用起飞跟随 : 启用其他学生跟随;
}
bool FollowPriceAllowed(const MqlTick &q,const int index=-1)
{
   int i=index<0 ? followIndex : index;
   if(i<0 || i>=ArraySize(followMembers)) return false;
   string key=FollowMissKey(i);
   if(Load(key)>0) { followMembers[i].reason="不利价差曾达上限，永久错过本条"; return false; }
   double entry=followMembers[i].sign>0 ? q.ask : q.bid;
   if(followMembers[i].sign*(entry-followMembers[i].price)>=followMembers[i].adverse-1e-8)
   {
      Store(key,1); GlobalVariablesFlush(); followMembers[i].reason="不利价差达上限，永久错过本条"; return false;
   }
   return true;
}
struct SharedVisit { double level; int sign; datetime left; };
SharedVisit sharedVisits[];
string SharedVisitKey(const double level,const int sign)
{
   return "opv_"+DoubleToString(level,_Digits)+"_"+IntegerToString(sign);
}
bool SameOpportunity(const int sign,const double level)
{
   return Load(SharedVisitKey(level,sign))>0;
}
void RememberSharedVisit(const double level,const int sign)
{
   for(int i=0;i<ArraySize(sharedVisits);i++)
      if(sharedVisits[i].sign==sign && MathAbs(sharedVisits[i].level-level)<TickSize()*0.5) return;
   int n=ArraySize(sharedVisits); ArrayResize(sharedVisits,n+1);
   sharedVisits[n].level=level; sharedVisits[n].sign=sign; sharedVisits[n].left=0;
}
void RestoreSharedVisits()
{
   // 仅初始化枚举本EA的有效合并记录；不在tick里扫全局状态或历史。
   string start=prefix+"opv_";
   for(int i=0;i<GlobalVariablesTotal();i++)
   {
      string name=GlobalVariableName(i);
      if(StringFind(name,start)!=0 || GlobalVariableGet(name)<=0) continue;
      string fields[];
      if(StringSplit(StringSubstr(name,StringLen(prefix)),'_',fields)!=3 || !Number(fields[1],true) ||
         (fields[2]!="1" && fields[2]!="-1")) continue;
      double level=StringToDouble(fields[1]);
      if(level>0) RememberSharedVisit(level,(int)StringToInteger(fields[2]));
   }
}
void UpdateSharedVisit(const MqlTick &q)
{
   for(int i=ArraySize(sharedVisits)-1;i>=0;i--)
   {
      int sign=sharedVisits[i].sign;
      string key=SharedVisitKey(sharedVisits[i].level,sign);
      if(Load(key)>0 && 允许同机会重入 &&
         MathAbs((sign>0 ? q.ask : q.bid)-sharedVisits[i].level)>=REARM_DISTANCE && pending.kind==0)
      {
         if(sharedVisits[i].left==0) sharedVisits[i].left=TimeGMT();
         if(TimeGMT()-sharedVisits[i].left>=REARM_SECONDS) { Store(key,0); GlobalVariablesFlush(); }
      }
      else sharedVisits[i].left=0;
      if(Load(key)==0)
      {
         int n=ArraySize(sharedVisits);
         for(int j=i;j<n-1;j++) sharedVisits[j]=sharedVisits[j+1];
         ArrayResize(sharedVisits,n-1);
      }
   }
}
void MergeOpportunity(const int sign,const double level)
{
   // 未知结果也锁住同机会；只有券商明确拒绝才让老师重试。
   Store(SharedVisitKey(level,sign),(double)TimeGMT()); RememberSharedVisit(level,sign);
   for(int i=0;i<ArraySize(followMembers);i++)
      if(followMembers[i].ready && TimeGMT()<followMembers[i].expiry && followMembers[i].sign==sign && MathAbs(followMembers[i].price-level)<=TickSize()*0.5)
         Store(FollowVisitKey(i),2); // 2=同机会来源合并；1=本人通道已尝试
   for(int i=0;i<ArraySize(aiPlans);i++)
      if(LiveTeacherPlan(i) && aiPlans[i].sign==sign && MathAbs(aiPlans[i].level-level)<=TickSize()*0.5)
         Store(AIVisitKey(aiPlans[i].level,sign),(double)TimeCurrent());
   GlobalVariablesFlush();
}
bool MemberFollowSignal(Candidate &out)
{
   if(!followReady || TimeGMT()-followGenerated>10) return false;
   if(!healthOK || healthPaused || healthBeat<=0 || TimeGMT()-healthBeat>10 ||
      healthSync<=0 || healthCheckpoint<=0 || TimeGMT()-healthSync>healthMaxAge || TimeGMT()-healthCheckpoint>healthMaxAge)
   { followReason="飞书同步未就绪，暂停学生跟随"; return false; }
   MqlTick q;
   if(!FreshQuote(q)) { followReason="行情失效，等待新报价"; return false; }
   for(int i=0;i<ArraySize(followMembers);i++)
   {
      if(!FollowEnabled(i) || !followMembers[i].ready || TimeGMT()>=followMembers[i].expiry) continue;
      if(Load(FollowVisitKey(i))>0) { followMembers[i].reason="本条已尝试或同机会已合并"; continue; }
      if(!FollowPriceAllowed(q,i)) continue;
      if(TeacherOwnsZone(q)) { followMembers[i].reason="老师明确计划区域优先，学生等待"; continue; }
      if(SameOpportunity(followMembers[i].sign,followMembers[i].price))
      { Store(FollowVisitKey(i),2); GlobalVariablesFlush(); followMembers[i].reason="同向同机会已合并来源"; continue; }
      if(q.ask-q.bid>最大点差价格) { followMembers[i].reason="点差过大，暂不跟随"; continue; }
      followIndex=i;
      out.valid=true; out.ai=false; out.follow=true; out.direction=followMembers[i].sign; out.level=followMembers[i].price;
      out.bar=TimeCurrent(); out.followExpiry=followMembers[i].expiry; out.followKey=FollowVisitKey(i);
      out.method=followMembers[i].name+"本人入场跟随["+followMembers[i].source+"]"; reason=out.method; return true;
   }
   return false;
}
string FollowMemberCaption(const int i)
{
   if(!FollowEnabled(i)) return followMembers[i].name+" · 已关闭";
   if(TimeGMT()-followGenerated>10) return followMembers[i].name+" · 快照心跳失效";
   if(Load(FollowVisitKey(i))>0) return followMembers[i].name+(Load(FollowVisitKey(i))==2 ? " · 同机会已合并" : " · 此条已尝试");
   if(Load(FollowMissKey(i))>0) return followMembers[i].name+" · 价格永久错过";
   if(followMembers[i].created>0 && TimeGMT()>=followMembers[i].expiry) return followMembers[i].name+" · 超过有效期";
   if(followMembers[i].ready && followReady)
      return followMembers[i].name+" "+(followMembers[i].sign>0 ? "BUY " : "SELL ")+DoubleToString(followMembers[i].price,_Digits)+
             " · 剩余"+IntegerToString((int)(followMembers[i].expiry-TimeGMT()))+"秒 · "+followMembers[i].reason;
   return followMembers[i].name+" · "+followMembers[i].reason;
}
string FollowCaption()
{
   return ArraySize(followMembers)>0 ? FollowMemberCaption(0) : "学生跟随 · "+followReason;
}
#endif
