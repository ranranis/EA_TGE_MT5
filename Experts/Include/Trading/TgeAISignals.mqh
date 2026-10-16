#ifndef TGE_AI_SIGNALS_MQH
#define TGE_AI_SIGNALS_MQH
// TGA7携带原始时间/明确重申时间；有效性由EA计算，不由AI判断行情。
struct AIPlan
{
   int sign,priority,approach;
   double level,sl,first,tp,breakeven;
   string id,kind,group,source,origin,status,mode,lifeReason;
   datetime created,confirmed,expires;
   int evidenceCount;
   string feedState,feedNote,loggedLife;
   bool sleeping,hardStopped;
   datetime brokenAt,pierceUntil,structureUntil;
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
   int h=FileOpen("FeishuMT5SignalMonitor\\tge_execution_v9.csv",FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(h==INVALID_HANDLE) return InvalidAI("等待监控输出TGA9，请更新并重启监控");
   string lines[]; bool ok=FileSize(h)<=65536;
   while(ok && !FileIsEnding(h))
   {
      int n=ArraySize(lines); if(n>=66) { ok=false; break; }
      ArrayResize(lines,n+1); lines[n]=FileReadString(h);
   }
   FileClose(h); string head[],foot[];
   if(!ok || ArraySize(lines)<2 || StringSplit(lines[0],',',head)!=7 || head[0]!="TGA" || head[1]!="9" ||
       head[4]!=_Symbol || !Number(head[2]) || !Number(head[5]) || (head[3]!="0" && head[3]!="1")) return InvalidAI("TGA9格式/品种不匹配");
   int count=(int)StringToInteger(head[5]); datetime generated=(datetime)StringToInteger(head[2]);
   if(count>64 || ArraySize(lines)!=count+2 || StringSplit(lines[count+1],',',foot)!=2 || foot[0]!="END" || foot[1]!=head[5] ||
       generated<=0 || generated>TimeGMT()+5 || generated<aiGenerated || TimeGMT()-generated>healthMaxAge) return InvalidAI("TGA9不完整或同步心跳失效");
   AIPlan incoming[]; ArrayResize(incoming,count);
   double map[]; datetime mapAt=0; string signature="";
   for(int i=0;i<count;i++)
   {
      string f[];
      if(StringSplit(lines[i+1],',',f)!=20 || f[0]!="PLAN" || f[1]=="" || f[6]=="" || f[7]=="" || f[9]=="" ||
         !Number(f[3]) || !Number(f[5],true) || !Number(f[8]) || !Number(f[14])) return InvalidAI("计划字段/来源无效");
      int priority=(int)StringToInteger(f[3]);
      bool isMap=f[2]=="MAP",direct=f[2]=="DIRECT",range=f[2]=="INNER" || f[2]=="OUTER";
      bool role=f[2]=="ROLE",watch=f[2]=="WATCH";
      bool ranked=direct ? (priority==100 || priority==95 || priority==90) :
                  range ? priority==(f[2]=="INNER" ? 70 : 75) : role ? (priority==55 || priority==60) :
                  isMap ? priority==40 : watch && priority==0;
      if((!isMap && !direct && !range && !role && !watch) || !ranked ||
          (isMap || watch ? f[4]!="AUTO" : f[4]!="BUY" && f[4]!="SELL")) return InvalidAI("点位类型/方向/优先级无效");
      incoming[i].id=f[1]; incoming[i].kind=f[2]; incoming[i].priority=priority;
      signature+=lines[i+1]+"|";
      incoming[i].sign=isMap || watch ? 0 : f[4]=="BUY" ? 1 : -1; incoming[i].approach=0;
      incoming[i].level=StringToDouble(f[5]); incoming[i].source=f[6]; incoming[i].group=f[9]; incoming[i].origin=f[1];
      incoming[i].created=(datetime)StringToInteger(f[8]); incoming[i].status="等待触价";
      incoming[i].confirmed=(datetime)StringToInteger(f[14]); incoming[i].mode=f[15]; incoming[i].lifeReason="";
      if(!Number(f[16]) || !Number(f[17]) || StringToInteger(f[17])>64 ||
         (f[18]!="READY" && f[18]!="WATCH" && f[18]!="EXPIRED" && f[18]!="CANCELLED" &&
          f[18]!="REPLACED" && f[18]!="CONFLICT" && f[18]!="DISABLED")) return InvalidAI("点位生命周期字段无效");
      incoming[i].expires=(datetime)StringToInteger(f[16]); incoming[i].evidenceCount=(int)StringToInteger(f[17]);
      incoming[i].feedState=f[18]; incoming[i].feedNote=f[19]; incoming[i].loggedLife="";
      if((!watch && (incoming[i].feedState!="READY" || incoming[i].expires<=incoming[i].confirmed)) ||
         (watch && incoming[i].feedState=="READY")) return InvalidAI("点位状态/期限不一致");
      incoming[i].sleeping=false; incoming[i].hardStopped=false;
      string pk="ps_"+DoubleToString(incoming[i].level,_Digits)+"_"+IntegerToString(incoming[i].sign);
      incoming[i].brokenAt=(datetime)Load(pk+"b"); incoming[i].pierceUntil=(datetime)Load(pk+"p");
      incoming[i].structureUntil=(datetime)Load(pk+"u");
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
          if(aiPlans[j].id==incoming[i].id)
          {
            bool reconfirmed=incoming[i].confirmed>aiPlans[j].confirmed;
            incoming[i].approach=aiPlans[j].approach; incoming[i].status=aiPlans[j].status;
            // 明确重申是一次新的确认：旧点位的离价休眠、止损停用和状态文案不能把新消息锁死。
            // 结构破位的价格/方向状态仍从 ps_* 恢复，并由定时器重新核验。
            if(reconfirmed)
            {
               incoming[i].sleeping=false; incoming[i].hardStopped=false;
               incoming[i].loggedLife=""; incoming[i].lifeReason=""; incoming[i].status="";
            }
            else
            {
               incoming[i].sleeping=aiPlans[j].sleeping; incoming[i].hardStopped=aiPlans[j].hardStopped;
               incoming[i].loggedLife=aiPlans[j].loggedLife; incoming[i].lifeReason=aiPlans[j].lifeReason;
            }
            break;
         }
      bool mapped=false;
      for(int j=0;j<ArraySize(map);j++) if(MathAbs(map[j]-level)<TickSize()*0.5) mapped=true;
      if(!mapped)
      {
         int n=ArraySize(map); ArrayResize(map,n+1); map[n]=level; mapAt=MathMax(mapAt,incoming[i].created);
      }
   }
   // 所有行通过后一次替换；坏文件停新请求，不能发布半组方向。
   ArrayResize(aiPlans,count); aiSourceTime=0;
   for(int i=0;i<count;i++) { aiPlans[i]=incoming[i]; aiSourceTime=MathMax(aiSourceTime,incoming[i].created); }
   aiReady=head[3]=="1"; aiGenerated=generated; aiReason=head[6]; aiMode=count>0 ? "SETUP" : "WAIT";
   string nextIdentity="TGA9|"+IntegerToString((long)Hash(signature));
   static double lastPriceMin=0,lastPriceMax=0;
   double priceMin=ChartGetDouble(0,CHART_PRICE_MIN),priceMax=ChartGetDouble(0,CHART_PRICE_MAX);
   bool displayChanged=identity!=nextIdentity || feedActive!=(aiReady && ArraySize(map)>0) ||
                       priceMin!=lastPriceMin || priceMax!=lastPriceMax;
   lastPriceMin=priceMin; lastPriceMax=priceMax;
   identity=nextIdentity; aiIdentity=identity;
   aiSource=count>0 ? incoming[0].source : "";
   ArraySort(map); ArrayCopy(levels,map); ArrayResize(levels,ArraySize(map));
   feedActive=aiReady && ArraySize(map)>0; sourceTime=mapAt; feedTime=generated;
   sourceKind="map"; sourceSender="点位来源见执行快照"; feedStatus=aiReason; if(displayChanged) DrawLevels();
   return true;
}
string PlanLifeKey(const int i)
{
   // 包含完整计划ID，避免目标价变化/心跳让失效记录丢失；新明确重申用时间恢复。
   return "life_"+aiPlans[i].id;
}
string PlanLifeReason(const int i)
{
   if(aiPlans[i].feedState!="READY") return aiPlans[i].feedNote;
   if(aiPlans[i].expires>0 && TimeGMT()>=aiPlans[i].expires) return "确认期限已到：仅观察";
   string key=PlanLifeKey(i); datetime stopped=(datetime)Load(key+"at");
   if(aiPlans[i].hardStopped || (stopped>0 && aiPlans[i].confirmed<=stopped && Load(key+"why")==2))
      return "仅参考：已触及明确止损价";
   if(aiPlans[i].sleeping) return "休眠：离价较远，回近后复核";
   if(启用点位结构失效 && aiPlans[i].sign!=0)
   {
      if(aiPlans[i].brokenAt>0) return TimeGMT()<aiPlans[i].structureUntil ?
         "破位冷却：暂停此点原方向" : "破位后等待M1收回";
      if(TimeGMT()<aiPlans[i].pierceUntil) return "刺穿冷却：等待收回";
      if(!AdaptiveMarketFresh()) return "点位结构待同步";
   }
   if(!adaptiveHistoryReady || adaptiveHistoryDirty) return "成交历史核对中";
   int losses=0; datetime last=0;
   for(int j=0;j<ArraySize(adaptiveResults);j++)
   {
      if(MathAbs(adaptiveResults[j].level-aiPlans[i].level)>TickSize()*0.5) continue;
      if(adaptiveResults[j].net>=0) break;
      losses++; if(last==0) last=adaptiveResults[j].closed;
   }
   if(losses>=2 && TimeCurrent()<last+连亏区域冷却分钟*60) return "此点连续亏损冷却";
   return "";
}
bool PlanExecutable(const int i) { return PlanLifeReason(i)==""; }
void StopPlanReference(const int i,const int why)
{
   string key=PlanLifeKey(i); datetime at=(datetime)Load(key+"at");
   if(at>0 && aiPlans[i].confirmed<=at && Load(key+"why")==why) return;
   if(!Store(key+"why",why) || !Store(key+"at",(double)TimeGMT())) return;
   GlobalVariablesFlush();
}
void RefreshPlanValidity(const MqlTick &q,const bool quoteOK,const bool persist=false)
{
   bool changed=false;
   bool usable=quoteOK && AIChannelReady() && q.ask>=q.bid && q.bid>0 && q.ask-q.bid<=最大点差价格;
   for(int i=0;i<ArraySize(aiPlans);i++)
   {
      if(usable)
      {
         double low=aiPlans[i].level,high=low;
         if(aiPlans[i].kind=="INNER" || aiPlans[i].kind=="OUTER" || aiPlans[i].kind=="MAP")
            for(int j=0;j<ArraySize(aiPlans);j++)
               if(aiPlans[j].kind==aiPlans[i].kind && aiPlans[j].group==aiPlans[i].group)
               { low=MathMin(low,aiPlans[j].level); high=MathMax(high,aiPlans[j].level); }
         aiPlans[i].sleeping=q.bid-high>挂单最大离价 || low-q.ask>挂单最大离价;
         if(aiPlans[i].kind=="DIRECT" && aiPlans[i].sl>0 &&
            (aiPlans[i].sign>0 ? q.bid<=aiPlans[i].sl : q.ask>=aiPlans[i].sl)) aiPlans[i].hardStopped=true;
         if(persist && aiPlans[i].hardStopped) StopPlanReference(i,2);
      }
      string life=PlanLifeReason(i);
      if(life!=aiPlans[i].lifeReason) changed=true;
      aiPlans[i].lifeReason=life;
      if(life!="") aiPlans[i].status=life;
      if(persist && life!=aiPlans[i].loggedLife)
      {
         DecisionLog("POINT_STATE",DoubleToString(aiPlans[i].level,_Digits)+" "+aiPlans[i].id+" "+
            (life=="" ? "恢复候选，等待既有触价条件" : life));
         aiPlans[i].loggedLife=life;
      }
   }
   feedActive=false;
   for(int i=0;i<ArraySize(aiPlans);i++) if(AIChannelReady() && PlanExecutable(i)) feedActive=true;
   if(changed) DrawLevels();
}
void RefreshPointStructure()
{
   // 只由定时器调用；已收盘M1和原有ATR缓存，不在Tick扫描历史或写文件。
   if(!启用点位结构失效 || !AdaptiveMarketFresh() || !AIChannelReady()) return;
   MqlTick q; if(!FreshQuote(q) || q.ask-q.bid>最大点差价格) return;
   double buffer=MathMax(TEACHER_BAND,adaptiveATR*点位破位缓冲ATR倍数);
   datetime now=TimeGMT();
   for(int i=0;i<ArraySize(aiPlans);i++)
   {
      if(aiPlans[i].sign==0 || aiPlans[i].feedState!="READY" || aiPlans[i].expires<=now) continue;
      int sign=aiPlans[i].sign; double level=aiPlans[i].level;
      string key="ps_"+DoubleToString(level,_Digits)+"_"+IntegerToString(sign);
      datetime oldB=aiPlans[i].brokenAt,oldP=aiPlans[i].pierceUntil,oldU=aiPlans[i].structureUntil;
      // 新计划也必须确认当前结构，不能凭消息更新跳过已确认破位。
      bool broken=true;
      for(int k=0;k<点位破位确认根数;k++)
         if(sign*(adaptiveBars[k].close-level)>=-buffer) { broken=false; break; }
      if(broken && aiPlans[i].brokenAt==0)
      {
         aiPlans[i].brokenAt=adaptiveBars[0].time;
         aiPlans[i].structureUntil=now+点位破位冷却秒数;
      }
      else if(aiPlans[i].brokenAt>0 && now>=aiPlans[i].structureUntil &&
              adaptiveBars[0].time>aiPlans[i].brokenAt && sign*(adaptiveBars[0].close-level)>buffer)
      { aiPlans[i].brokenAt=0; aiPlans[i].structureUntil=0; }
      double price=sign>0 ? q.bid : q.ask;
      if(aiPlans[i].brokenAt==0 && sign*(price-level)<-buffer && now>=aiPlans[i].pierceUntil)
         aiPlans[i].pierceUntil=now+点位刺穿冷却秒数;
      bool dirty=false;
      if(oldB!=aiPlans[i].brokenAt) { Store(key+"b",(double)aiPlans[i].brokenAt); dirty=true; }
      if(oldP!=aiPlans[i].pierceUntil) { Store(key+"p",(double)aiPlans[i].pierceUntil); dirty=true; }
      if(oldU!=aiPlans[i].structureUntil) { Store(key+"u",(double)aiPlans[i].structureUntil); dirty=true; }
      if(dirty) GlobalVariablesFlush();
   }
}
string PlanAgeCaption(const int i)
{
   if(aiPlans[i].expires<=0) return aiPlans[i].feedNote;
   int left=(int)MathMax(0,aiPlans[i].expires-TimeGMT());
   string time=left>=86400 ? "余"+IntegerToString(left/86400)+"天" :
      left>=3600 ? "余"+IntegerToString(left/3600)+"小时" : "余"+IntegerToString(left/60)+"分钟";
   return IntegerToString(aiPlans[i].evidenceCount)+"条依据 · "+time;
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
      if(PlanExecutable(i) && (读取AI即时策略 || aiPlans[i].kind=="MAP") && PlanNear(i,q)) priority=MathMax(priority,aiPlans[i].priority);
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
// method: 0原触价，1原行情保护，2区间反应（只供模拟）。
int EffectiveEntryMethod()
{
   if(入场策略==TGE_ENTRY_TOUCH) return 0;
   if(入场策略==TGE_ENTRY_ADAPTIVE) return 1;
   return 启用积极持单 ? 1 : 0;
}
string EntrySourceReason(const int i)
{
   if(!AIChannelReady()) return "消息同步中";
   if(aiPlans[i].kind=="WATCH") return "仅供参考，不作为入场";
   if(!读取AI即时策略 && aiPlans[i].kind!="MAP") return "即时点位读取关闭";
   if(aiPlans[i].feedState!="READY") return "点位已撤销、过期或存在冲突";
   if(aiPlans[i].expires<=TimeGMT()) return "点位已到期";
   if(aiPlans[i].sleeping || aiPlans[i].hardStopped) return "点位休眠或已触及明确止损";
   return "";
}
string UnifiedEntryStatus(const int i,const MqlTick &q,const int method,const bool live)
{
   // 模拟不读取真实单的消费、持仓数量或连亏结果，避免两组被实盘交易污染。
   if(!live)
   {
      string source=EntrySourceReason(i); if(source!="") return source;
      if(q.ask-q.bid>最大点差价格) return "点差过大";
      datetime after=0; string news=AdaptiveNewsState(TimeCurrent(),after);
      if(news!="") return news;
      if(TimeCurrent()<adaptiveShockUntil) return "急涨急跌，暂等稳定";
      if(method==2) return ObserverEntryStatus(i,q,after);
      int side=PlanSign(i);
      if(side==0) return "等待接近点位";
      if(!InTeacherBand(side>0 ? q.ask : q.bid,aiPlans[i].level)) return "等待接近点位";
      // 两组使用相同消息/冲击恢复门槛；不沿用真实仓位的连亏冷却。
      if(TimeCurrent()<adaptiveRecoverUntil) after=(datetime)MathMax(after,adaptiveShockUntil);
      if(after>0 && !AdaptiveConfirmed(side,aiPlans[i].level,after)) return "等待消息或冲击后的新反应";
      return "触价候选";
   }

   int sign=PlanSign(i); double entry=sign>0 ? q.ask : q.bid;
   string status=""; double speed=0,oneway=0,pullback=0;
   if(!AIChannelReady() || (!读取AI即时策略 && aiPlans[i].kind!="MAP")) status="来源未就绪";
   else if(live && !PlanExecutable(i)) status=PlanLifeReason(i);
   else if(sign==0) status="等待从点位上方或下方接近";
   else if(!InTeacherBand(entry,aiPlans[i].level)) status="等待进入±1.00区域";
   else if(启用点位结构失效 && aiPlans[i].sign!=0 && AdaptiveMarketFresh() &&
           aiPlans[i].sign*((aiPlans[i].sign>0 ? q.bid : q.ask)-aiPlans[i].level)<-MathMax(TEACHER_BAND,adaptiveATR*点位破位缓冲ATR倍数))
      status="刺穿暂缓：等待收回";
   else if(live && aiPlans[i].priority<ZonePriority(q)) status="本区域更高优先级计划优先";
   else if(live && (SameOpportunity(sign,aiPlans[i].level) || SameOpportunity(-sign,aiPlans[i].level))) status="本次触及已消费，离开4点5秒后重入";
   else if(live && Load(SharedVisitKey(aiPlans[i].level,sign)+"r")>TimeGMT()) status="拒绝后短暂冷却";
   else if(!TickImpact(sign,q.time_msc,speed,oneway,pullback)) status="采样中：至少4个tick覆盖1秒";
   else if(speed>=逆向冲击速度 && oneway>=冲击单向比例 && pullback<恢复回拉价格) status="逆向连续冲穿暂缓";
   else status=method==1 ? AdaptiveEntryStatus(i,q) : "触价候选";
   return status;
}
bool TeacherEntryAllowed(const int i,const MqlTick &q)
{
   string status=UnifiedEntryStatus(i,q,EffectiveEntryMethod(),true);
   aiPlans[i].status=status;
   return status=="触价候选" || status=="M1确认候选";
}
bool AIMarketSignal(Candidate &out)
{
   ZeroMemory(out); if(!AIChannelReady()) { reason=aiReason; return false; }
   MqlTick q; if(!FreshQuote(q)) { reason="报价过期/断线"; return false; }
   RefreshPlanValidity(q,true);
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
   if(EffectiveEntryMethod()==1) out.method+=" · "+aiPlans[best].status;
   reason=out.method; entryView.level=out.level; entryView.direction=out.direction; entryView.method=out.method;
   return true;
}
string AIPlanCaption()
{
   if(!AIChannelReady()) return "暂停新单："+aiReason;
   if(StringFind(aiReason,"AI")==0) return aiReason;
   if(StringFind(aiReason,"手动替换")>=0) return "手动替换 · 自动点位不覆盖 · "+SyncStatus();
   return "触价±1.00 · 每次0.02手 · 分数仅排序，不代表胜率";
}
string PointRoleCaption(const double price)
{
   int best=-1;
   for(int i=0;i<ArraySize(aiPlans);i++)
      if(MathAbs(aiPlans[i].level-price)<TickSize()*0.5 && (best<0 || aiPlans[i].priority>aiPlans[best].priority)) best=i;
   if(best<0) return "参考";
   if(aiPlans[best].feedState=="CANCELLED") return "已撤销";
   if(aiPlans[best].feedState=="REPLACED") return "已替换";
   if(aiPlans[best].feedState=="EXPIRED") return "已过期";
   if(aiPlans[best].feedState=="CONFLICT") return "冲突待确认";
   if(aiPlans[best].feedState=="DISABLED") return "手动停用";
   string kind=aiPlans[best].kind;
   if(kind=="WATCH") return "仅展示";
   string role=kind=="MAP" ? "中性" : kind=="ROLE" ? (aiPlans[best].sign>0 ? "支撑" : "压力") :
               kind=="DIRECT" ? (aiPlans[best].sign>0 ? "做多" : "做空") : "区间";
   return role+" · "+IntegerToString(aiPlans[best].priority);
}
#endif
