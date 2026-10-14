#ifndef TGE_AI_SIGNALS_MQH
#define TGE_AI_SIGNALS_MQH
// TGA7携带原始时间/明确重申时间；有效性由EA计算，不由AI判断行情。
struct AIPlan
{
   int sign,priority,approach;
   double level,sl,first,tp,breakeven;
   string id,kind,group,source,origin,status,mode,lifeReason;
   datetime created,confirmed;
};
AIPlan aiPlans[];
string aiMode="WAIT",aiReason="等待TGA7执行快照",aiSource="",aiIdentity="";
datetime aiGenerated=0,aiSourceTime=0;
bool aiReady=false;
const double TEACHER_BAND=1.00,REARM_DISTANCE=4.00;
const int REARM_SECONDS=5;
const int DIRECT_MAX_AGE=86400,MARKET_MAX_AGE=180;
bool AIChannelReady()
{
   long now=(long)TimeGMT();
   return aiReady && healthOK && !healthPaused && aiGenerated>0 && healthBeat>0 && healthSync>0 && healthCheckpoint>0 &&
          aiGenerated<=now+5 && now-aiGenerated<=healthMaxAge && healthBeat<=now+5 && healthSync<=now+5 &&
          healthCheckpoint<=now+5 && now-healthBeat<=healthMaxAge && now-healthSync<=healthMaxAge && now-healthCheckpoint<=healthMaxAge;
}
bool InvalidAI(const string why) { aiReady=false; aiReason=why; return false; }
bool ReadAISetups()
{
   int h=FileOpen("FeishuMT5SignalMonitor\\tge_execution_v7.csv",FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(h==INVALID_HANDLE) return InvalidAI("等待监控输出TGA7，请更新并重启监控");
   string lines[]; bool ok=FileSize(h)<=32768;
   while(ok && !FileIsEnding(h))
   {
      int n=ArraySize(lines); if(n>=30) { ok=false; break; }
      ArrayResize(lines,n+1); lines[n]=FileReadString(h);
   }
   FileClose(h); string head[],foot[];
   if(!ok || ArraySize(lines)<2 || StringSplit(lines[0],',',head)!=7 || head[0]!="TGA" || head[1]!="7" ||
      head[4]!=_Symbol || !Number(head[2]) || !Number(head[5]) || (head[3]!="0" && head[3]!="1")) return InvalidAI("TGA7格式/品种不匹配");
   int count=(int)StringToInteger(head[5]); datetime generated=(datetime)StringToInteger(head[2]);
   if(count>28 || ArraySize(lines)!=count+2 || StringSplit(lines[count+1],',',foot)!=2 || foot[0]!="END" || foot[1]!=head[5] ||
      generated<=0 || generated>TimeGMT()+5 || generated<aiGenerated || TimeGMT()-generated>healthMaxAge) return InvalidAI("TGA7不完整或同步心跳失效");
   AIPlan incoming[]; ArrayResize(incoming,count);
   double map[]; datetime mapAt=0; string signature="";
   for(int i=0;i<count;i++)
   {
      string f[];
      if(StringSplit(lines[i+1],',',f)!=16 || f[0]!="PLAN" || f[1]=="" || f[6]=="" || f[7]=="" || f[9]=="" ||
         !Number(f[3]) || !Number(f[5],true) || !Number(f[8]) || !Number(f[14])) return InvalidAI("计划字段/来源无效");
      int priority=(int)StringToInteger(f[3]);
      bool isMap=f[2]=="MAP",direct=f[2]=="DIRECT",range=f[2]=="INNER" || f[2]=="OUTER";
      if((!isMap && !direct && !range) || priority!=(direct ? 8 : range ? 6 : 5) ||
         (isMap ? f[4]!="AUTO" : f[4]!="BUY" && f[4]!="SELL")) return InvalidAI("点位类型/方向/优先级无效");
      incoming[i].id=f[1]; incoming[i].kind=f[2]; incoming[i].priority=priority;
      signature+=lines[i+1]+"|";
      incoming[i].sign=isMap ? 0 : f[4]=="BUY" ? 1 : -1; incoming[i].approach=0;
      incoming[i].level=StringToDouble(f[5]); incoming[i].source=f[6]; incoming[i].group=f[9]; incoming[i].origin=f[1];
      incoming[i].created=(datetime)StringToInteger(f[8]); incoming[i].status="等待触价";
      incoming[i].confirmed=(datetime)StringToInteger(f[14]); incoming[i].mode=f[15]; incoming[i].lifeReason="";
      if(incoming[i].confirmed<incoming[i].created || incoming[i].confirmed>generated+5 ||
         (direct ? f[15]!="REACTION" && f[15]!="MARKET" : f[15]!="REFERENCE")) return InvalidAI("重申时间/参考类型无效");
      if(incoming[i].created<=0 || incoming[i].created>generated+5 || incoming[i].level<=0 || !MathIsValidNumber(incoming[i].level)) return InvalidAI("价格/来源时间无效");
      for(int k=10;k<14;k++)
         if(!Number(f[k],true) || !MathIsValidNumber(StringToDouble(f[k]))) return InvalidAI("退出价字段无效");
      incoming[i].sl=StringToDouble(f[10]); incoming[i].first=StringToDouble(f[11]);
      incoming[i].tp=StringToDouble(f[12]); incoming[i].breakeven=StringToDouble(f[13]);
      int sign=incoming[i].sign; double level=incoming[i].level;
      if((!direct && (incoming[i].sl>0 || incoming[i].first>0 || incoming[i].tp>0 || incoming[i].breakeven>0)) ||
         (incoming[i].sl>0 && sign*(level-incoming[i].sl)<=0) ||
         (incoming[i].first>0 && sign*(incoming[i].first-level)<=0) ||
         (incoming[i].tp>0 && sign*(incoming[i].tp-level)<=0) ||
         (incoming[i].breakeven>0 && sign*(incoming[i].breakeven-level)<=0) ||
         (incoming[i].first>0 && incoming[i].tp>0 && sign*(incoming[i].tp-incoming[i].first)<=0)) return InvalidAI("退出价方向/顺序无效");
      for(int j=0;j<i;j++) if(incoming[j].id==incoming[i].id) return InvalidAI("重复计划编号");
      for(int j=0;j<ArraySize(aiPlans);j++)
         if(aiPlans[j].id==incoming[i].id) { incoming[i].approach=aiPlans[j].approach; incoming[i].status=aiPlans[j].status; break; }
      if(isMap)
      {
         int n=ArraySize(map); ArrayResize(map,n+1); map[n]=level; mapAt=MathMax(mapAt,incoming[i].created);
      }
   }
   // 所有行通过后一次替换；坏文件停新请求，不能发布半组方向。
   ArrayResize(aiPlans,count); aiSourceTime=0;
   for(int i=0;i<count;i++) { aiPlans[i]=incoming[i]; aiSourceTime=MathMax(aiSourceTime,incoming[i].created); }
   aiReady=head[3]=="1"; aiGenerated=generated; aiReason=head[6]; aiMode=count>0 ? "SETUP" : "WAIT";
   identity="TGA7|"+IntegerToString((long)Hash(signature)); aiIdentity=identity;
   aiSource=count>0 ? incoming[0].source : "";
   ArraySort(map); ArrayCopy(levels,map); ArrayResize(levels,ArraySize(map));
   feedActive=aiReady && ArraySize(map)>0; sourceTime=mapAt; feedTime=generated;
   sourceKind="map"; sourceSender="点位来源见执行快照"; feedStatus=aiReason; DrawLevels();
   return true;
}
string PlanLifeKey(const int i)
{
   // 包含完整计划ID，避免目标价变化/心跳让失效记录丢失；新明确重申用时间恢复。
   return "life_"+aiPlans[i].id;
}
string PlanLifeReason(const int i)
{
   string key=PlanLifeKey(i); datetime stopped=(datetime)Load(key+"at");
   if(stopped>0 && aiPlans[i].confirmed<=stopped)
      return Load(key+"why")==2 ? "仅参考：已触及明确止损价" : "仅参考：曾远离，等待新确认";
   if(aiPlans[i].kind=="DIRECT")
   {
      int age=aiPlans[i].mode=="MARKET" ? MARKET_MAX_AGE : DIRECT_MAX_AGE;
      if(TimeGMT()-aiPlans[i].confirmed>=age)
         return aiPlans[i].mode=="MARKET" ? "仅参考：市价提示超过3分钟" : "仅参考：即时计划超过24小时";
   }
   return "";
}
bool PlanExecutable(const int i) { return PlanLifeReason(i)==""; }
void StopPlanReference(const int i,const int why)
{
   string key=PlanLifeKey(i); datetime at=(datetime)Load(key+"at");
   if(at>0 && aiPlans[i].confirmed<=at) return;
   // 状态只表示停止新候选，不表示撤单/平仓已完成；请求仍走原交易对账链。
   if(!Store(key+"why",why) || !Store(key+"at",(double)TimeGMT())) return;
   GlobalVariablesFlush();
   Print("点位停止新入场：",aiPlans[i].kind," ",DoubleToString(aiPlans[i].level,_Digits),
         " 来源=",aiPlans[i].source," 原因=",why==2 ? "触及明确止损价" : "距离超过上限");
}
void RefreshPlanValidity(const MqlTick &q,const bool quoteOK)
{
   bool changed=false;
   bool usable=quoteOK && AIChannelReady() && q.ask>=q.bid && q.bid>0 && q.ask-q.bid<=最大点差价格;
   for(int i=0;i<ArraySize(aiPlans);i++)
   {
      if(usable && PlanExecutable(i))
      {
         bool far=false;
         if(aiPlans[i].kind=="DIRECT")
            far=MathAbs((aiPlans[i].sign>0 ? q.ask : q.bid)-aiPlans[i].level)>挂单最大离价;
         else
         {
            double low=aiPlans[i].level,high=low;
            for(int j=0;j<ArraySize(aiPlans);j++)
               if(aiPlans[j].kind==aiPlans[i].kind && aiPlans[j].group==aiPlans[i].group)
               { low=MathMin(low,aiPlans[j].level); high=MathMax(high,aiPlans[j].level); }
            // 基础表/区间按整体范围判断；表内远端点位不会单独作废。
            far=q.bid-high>挂单最大离价 || low-q.ask>挂单最大离价;
         }
         if(far) StopPlanReference(i,1);
         else if(aiPlans[i].kind=="DIRECT" && aiPlans[i].sl>0 &&
                 (aiPlans[i].sign>0 ? q.bid<=aiPlans[i].sl : q.ask>=aiPlans[i].sl)) StopPlanReference(i,2);
      }
      string life=PlanLifeReason(i);
      if(life!=aiPlans[i].lifeReason) changed=true;
      aiPlans[i].lifeReason=life;
      if(life!="") aiPlans[i].status=life;
   }
   feedActive=false;
   for(int i=0;i<ArraySize(aiPlans);i++)
      if(aiPlans[i].kind=="MAP" && AIChannelReady() && PlanExecutable(i)) feedActive=true;
   if(changed) DrawLevels();
}
string PlanAgeCaption(const int i)
{
   if(aiPlans[i].kind!="DIRECT")
      return TimeGMT()-aiPlans[i].created>=86400 ? "旧参考" : "参考";
   int age=aiPlans[i].mode=="MARKET" ? MARKET_MAX_AGE : DIRECT_MAX_AGE;
   int left=(int)MathMax(0,aiPlans[i].confirmed+age-TimeGMT());
   return left>=3600 ? "余"+IntegerToString(left/3600)+"小时" : "余"+IntegerToString(left/60)+"分钟";
}
string MapLifeCaption()
{
   for(int i=0;i<ArraySize(aiPlans);i++)
      if(aiPlans[i].kind=="MAP")
         return PlanExecutable(i) ? "地图"+PlanAgeCaption(i)+" · "+TimeToString(aiPlans[i].created+8*3600,TIME_DATE|TIME_MINUTES) : PlanLifeReason(i);
   return "暂无完整点位地图";
}
string AIKeyFromHash(const uint originHash,const double level,const int sign)
{ return "av"+IntegerToString((long)originHash)+"_"+DoubleToString(level,_Digits)+"_"+IntegerToString(sign); }
string AIVisitKey(const double level,const int sign)
{ return SharedVisitKey(level,sign); }
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
   if(fastLast>0 && q.time_msc-fastLast>1500)
   {
      fastCount=0; fastCursor=0;
      for(int i=0;i<ArraySize(sharedVisits);i++) sharedVisits[i].left=0;
   }
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
   Store(SharedVisitKey(level,sign),(double)TimeGMT()); RememberSharedVisit(level,sign); GlobalVariablesFlush();
}
bool InTeacherBand(const double entry,const double level)
{ return MathAbs(entry-level)<=TEACHER_BAND+1e-8; }
int PlanSign(const int i) { return aiPlans[i].sign!=0 ? aiPlans[i].sign : aiPlans[i].approach; }
bool PlanNear(const int i,const MqlTick &q)
{
   int sign=PlanSign(i);
   return sign!=0 && InTeacherBand(sign>0 ? q.ask : q.bid,aiPlans[i].level);
}
int ZonePriority(const MqlTick &q)
{
   int priority=0;
   for(int i=0;i<ArraySize(aiPlans);i++)
      if(PlanExecutable(i) && (读取AI即时策略 || aiPlans[i].priority==5) && PlanNear(i,q)) priority=MathMax(priority,aiPlans[i].priority);
   return priority;
}
void UpdateTeacherVisits(const MqlTick &q)
{
   RefreshPlanValidity(q,true);
   UpdateSharedVisit(q);
   for(int i=0;i<ArraySize(aiPlans);i++)
   {
      if(aiPlans[i].kind!="MAP") continue;
      // 在区外确定接近方向，进入±1区域后冻结，避免点位内噪声反复切多空。
      if(q.bid>aiPlans[i].level+TEACHER_BAND) aiPlans[i].approach=1;
      else if(q.ask<aiPlans[i].level-TEACHER_BAND) aiPlans[i].approach=-1;
   }
}
bool TeacherEntryAllowed(const int i,const MqlTick &q)
{
   int sign=PlanSign(i); double entry=sign>0 ? q.ask : q.bid;
   string status=""; double speed=0,oneway=0,pullback=0;
   if(!AIChannelReady() || (!读取AI即时策略 && aiPlans[i].priority>5)) status="来源未就绪";
   else if(!PlanExecutable(i)) status=PlanLifeReason(i);
   else if(sign==0) status="等待从点位上方或下方接近";
   else if(!InTeacherBand(entry,aiPlans[i].level)) status="等待进入±1.00区域";
   else if(aiPlans[i].priority<ZonePriority(q)) status="本区域更高优先级计划优先";
   else if(SameOpportunity(sign,aiPlans[i].level) || SameOpportunity(-sign,aiPlans[i].level)) status="本次触及已消费，离开4点5秒后重入";
   else if(Load(SharedVisitKey(aiPlans[i].level,sign)+"r")>TimeGMT()) status="拒绝后短暂冷却";
   else if(!TickImpact(sign,q.time_msc,speed,oneway,pullback)) status="采样中：至少4个tick覆盖1秒";
   else if(speed>=逆向冲击速度 && oneway>=冲击单向比例 && pullback<恢复回拉价格) status="逆向连续冲穿暂缓";
   else status="触价候选";
   aiPlans[i].status=status;
   return status=="触价候选";
}
bool AIMarketSignal(Candidate &out)
{
   ZeroMemory(out); if(!AIChannelReady()) { reason=aiReason; return false; }
   MqlTick q; if(!FreshQuote(q)) { reason="报价过期/断线"; return false; }
   RememberFastTick(q); UpdateTeacherVisits(q);
   if(q.ask-q.bid>最大点差价格) { reason="点差过大"; return false; }
   int best=-1; double nearest=DBL_MAX; ZeroMemory(entryView);
   for(int i=0;i<ArraySize(aiPlans);i++)
   {
      bool allowed=TeacherEntryAllowed(i,q); int sign=PlanSign(i);
      double gap=MathAbs((sign>0 ? q.ask : q.bid)-aiPlans[i].level);
      if(gap<nearest)
      {
         nearest=gap; reason=aiPlans[i].status; entryView.ready=true; entryView.level=aiPlans[i].level;
         entryView.direction=sign; entryView.distance=gap; entryView.bar=TimeCurrent();
      }
      if(allowed && (best<0 || aiPlans[i].priority>aiPlans[best].priority ||
         (aiPlans[i].priority==aiPlans[best].priority && aiPlans[i].created>aiPlans[best].created))) best=i;
   }
   if(best<0) return false;
   for(int i=0;i<ArraySize(aiPlans);i++)
      if(i!=best && PlanExecutable(i) && aiPlans[i].priority==aiPlans[best].priority && PlanNear(i,q) && PlanSign(i)==-PlanSign(best))
      { reason="同优先级方向冲突，等待更明确点位"; return false; }
   out.valid=true; out.ai=true; out.direction=PlanSign(best); out.level=aiPlans[best].level;
   out.bar=TimeCurrent(); out.originHash=Hash(aiPlans[best].id); out.aiKey=SharedVisitKey(out.level,out.direction);
   out.exitSL=aiPlans[best].sl; out.exitFirst=aiPlans[best].first; out.exitTP=aiPlans[best].tp; out.exitBE=aiPlans[best].breakeven;
   out.method="优先级"+IntegerToString(aiPlans[best].priority)+" "+aiPlans[best].kind+" ["+aiPlans[best].source+"]";
   reason=out.method; entryView.level=out.level; entryView.direction=out.direction; entryView.method=out.method;
   return true;
}
string AIPlanCaption() { return AIChannelReady() ? "触价±1.00 · 每次0.02手 · 优先级8 / 6 / 5" : "暂停新单："+aiReason; }
#endif
