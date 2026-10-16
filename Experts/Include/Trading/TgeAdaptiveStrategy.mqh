// v1.60：点位仍决定机会，行情决定确认方式和退出；只接管带adaptive标记的真实成交。
MqlRates adaptiveBars[]; // series：0是最近一根已收盘M1，绝不用当前K线确认方向。
double adaptiveATR=0,adaptiveBaseline=0;
int adaptiveTrend=0;
bool adaptiveMarketReady=false,adaptiveHistoryReady=false,adaptiveHistoryDirty=true;
datetime adaptiveMarketAt=0,adaptiveHistoryAt=0,adaptiveCalendarAt=0,adaptiveCalendarTry=0;
datetime adaptiveShockUntil=0,adaptiveRecoverUntil=0,adaptiveShockSave=0;
long adaptiveMinute=0,adaptiveRangeTriggered=0;
double adaptiveMinuteHigh=0,adaptiveMinuteLow=0;
struct AdaptiveEvent { datetime at; bool core; string name; };
AdaptiveEvent adaptiveEvents[];
struct AdaptiveResult { ulong id; double level,net; int sign; datetime closed; };
AdaptiveResult adaptiveResults[];

bool AdaptiveInputsValid()
{
   double values[]={结构缓冲ATR倍数,最小结构风险距离,合计风险标准单倍数,减风险触发R,保本触发R,保本缓冲价格};
   for(int i=0;i<ArraySize(values);i++) if(!MathIsValidNumber(values[i])) return false;
   return MathIsValidNumber(点位破位缓冲ATR倍数) && 点位破位缓冲ATR倍数>=0 && 点位破位缓冲ATR倍数<=3 &&
           点位破位确认根数>=1 && 点位破位确认根数<=5 && 点位刺穿冷却秒数>=1 && 点位刺穿冷却秒数<=3600 &&
           点位破位冷却秒数>=1 && 点位破位冷却秒数<=3600 && 结构缓冲ATR倍数>=0 && 结构缓冲ATR倍数<=2 && 最小结构风险距离>0 &&
          最小结构风险距离<=保险价格距离 && 合计风险标准单倍数>=1 && 合计风险标准单倍数<=10 &&
          减风险触发R>0 && 保本触发R>减风险触发R && 保本缓冲价格>=0 &&
          无进展退出分钟>=1 && 连亏区域冷却分钟>=1 && 冲击冷却秒数>=30 && 恢复确认秒数>=60 &&
          重点事件前后分钟>=1 && 重点事件前后分钟<=60 && 一般高重要性前后分钟>=1 &&
          一般高重要性前后分钟<=60 && 重点事件提前退出分钟>=0 &&
          重点事件提前退出分钟<=重点事件前后分钟;
}
void InitAdaptive()
{
   ArraySetAsSeries(adaptiveBars,true);
   adaptiveShockUntil=(datetime)Load("ad.shockUntil");
   adaptiveRecoverUntil=(datetime)Load("ad.recoverUntil");
   adaptiveBaseline=Load("ad.baseline");
}
void RefreshAdaptiveMarket()
{
   datetime now=TimeCurrent();
   adaptiveMarketReady=false;
   if(CopyRates(_Symbol,PERIOD_M1,1,16,adaptiveBars)!=16) return;
   if(now-adaptiveBars[0].time<60 || now-adaptiveBars[0].time>120) return;
   double ranges[14],total=0;
   for(int i=0;i<14;i++)
   {
      if(adaptiveBars[i].time-adaptiveBars[i+1].time!=60 || adaptiveBars[i].low<=0) return;
      ranges[i]=MathMax(adaptiveBars[i].high-adaptiveBars[i].low,
                       MathMax(MathAbs(adaptiveBars[i].high-adaptiveBars[i+1].close),
                               MathAbs(adaptiveBars[i].low-adaptiveBars[i+1].close)));
      if(!MathIsValidNumber(ranges[i])) return;
      total+=ranges[i];
   }
   adaptiveATR=total/14.0;
   if(adaptiveATR<=TickSize()) return;
   ArraySort(ranges);
   if(adaptiveBaseline<=0 || now>=adaptiveRecoverUntil) adaptiveBaseline=(ranges[6]+ranges[7])/2;
   double fast[2],slow[2]; adaptiveTrend=0;
   if(CopyBuffer(trendFastHandle,0,1,2,fast)!=2 || CopyBuffer(trendSlowHandle,0,1,2,slow)!=2) return;
   if(fast[1]>slow[1] && fast[1]>fast[0]) adaptiveTrend=1;
   if(fast[1]<slow[1] && fast[1]<fast[0]) adaptiveTrend=-1;
   adaptiveMarketAt=now; adaptiveMarketReady=true;
}
bool AdaptiveMarketFresh()
{
   return adaptiveMarketReady && TimeCurrent()-adaptiveMarketAt<=5 && ArraySize(adaptiveBars)>=16 &&
          TimeCurrent()-adaptiveBars[0].time<=120;
}
void RefreshAdaptiveCalendar()
{
   if(!启用消息日历) return;
   datetime now=TimeCurrent();
   if(adaptiveCalendarTry>0 && now-adaptiveCalendarTry<60) return;
   adaptiveCalendarTry=now;
   MqlCalendarValue values[];
   int lookback=MathMax(重点事件前后分钟,一般高重要性前后分钟)*60+恢复确认秒数;
   int count=CalendarValueHistory(values,now-lookback,now+3600,NULL,"USD");
   if(count<0) return; // 失败不把上次日历擦成“无消息”。
   AdaptiveEvent next[];
   for(int i=0;i<count;i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id,event)) return;
      if(event.importance!=CALENDAR_IMPORTANCE_HIGH) continue;
      if(event.time_mode!=CALENDAR_TIMEMODE_DATETIME) return; // 无准确时间，不假装安全。
      int n=ArraySize(next); ArrayResize(next,n+1);
      next[n].at=values[i].time; next[n].name=event.name;
      next[n].core=event.sector==CALENDAR_SECTOR_JOBS || event.sector==CALENDAR_SECTOR_PRICES ||
                   event.sector==CALENDAR_SECTOR_MONEY;
   }
   ArrayResize(adaptiveEvents,ArraySize(next));
   for(int i=0;i<ArraySize(next);i++) adaptiveEvents[i]=next[i];
   adaptiveCalendarAt=now;
}
// 返回当前消息窗口，恢复期要求一根窗口结束后形成的M1。
string AdaptiveNewsState(const datetime now,datetime &confirmAfter)
{
   confirmAfter=0;
   if(!启用消息日历) return "";
   if(adaptiveCalendarAt==0 || now-adaptiveCalendarAt>180) return "消息日历未就绪，暂停新单";
   string blocked="";
   for(int i=0;i<ArraySize(adaptiveEvents);i++)
   {
      int seconds=(adaptiveEvents[i].core ? 重点事件前后分钟 : 一般高重要性前后分钟)*60;
      datetime end=adaptiveEvents[i].at+seconds;
      if(now>=adaptiveEvents[i].at-seconds && now<=end) blocked="消息窗口，暂停新单";
      if(now>end && now<end+恢复确认秒数 && end>confirmAfter) confirmAfter=end;
   }
   return blocked;
}
bool AdaptiveNewsExit(const datetime now)
{
   if(!启用消息日历 || 重点事件提前退出分钟==0) return false;
   // 即使刷新失败，仍按已知事件保护；过期记录的窗口自然失效。
   for(int i=0;i<ArraySize(adaptiveEvents);i++)
      if(adaptiveEvents[i].core && now>=adaptiveEvents[i].at-重点事件提前退出分钟*60 &&
         now<=adaptiveEvents[i].at+重点事件前后分钟*60) return true;
   return false;
}
void UpdateAdaptiveShock(const MqlTick &q)
{
   datetime now=TimeCurrent(); long minute=q.time/60;
   if(minute!=adaptiveMinute)
   { adaptiveMinute=minute; adaptiveMinuteHigh=q.bid; adaptiveMinuteLow=q.bid; }
   adaptiveMinuteHigh=MathMax(adaptiveMinuteHigh,q.bid); adaptiveMinuteLow=MathMin(adaptiveMinuteLow,q.bid);
   double speed=0,oneway=0,pullback=0;
   bool impact=TickImpact(1,q.time_msc,speed,oneway,pullback) &&
               MathAbs(speed)>=MathMax(1.5,adaptiveBaseline*0.5) && oneway>=0.85;
   // TickImpact的单向比例对当前方向计算，两边均检查。
   double opposite=0,ratio=0,back=0;
   if(TickImpact(-1,q.time_msc,opposite,ratio,back) && opposite>=MathMax(1.5,adaptiveBaseline*0.5) && ratio>=0.85) impact=true;
   bool range=adaptiveRangeTriggered!=minute &&
              adaptiveMinuteHigh-adaptiveMinuteLow>=MathMax(4.0,adaptiveBaseline*3.0);
   bool spread=q.ask-q.bid>MathMax(1.0,最大点差价格*2);
   if(!impact && !range && !spread) return;
   if(range) adaptiveRangeTriggered=minute;
   if(now-adaptiveShockSave<5 && adaptiveShockUntil>now) return;
   adaptiveShockUntil=now+冲击冷却秒数; adaptiveRecoverUntil=adaptiveShockUntil+恢复确认秒数;
   adaptiveShockSave=now;
   Store("ad.shockUntil",(double)adaptiveShockUntil); Store("ad.recoverUntil",(double)adaptiveRecoverUntil);
   Store("ad.baseline",adaptiveBaseline);
   GlobalVariablesFlush();
}
void RefreshAdaptiveHistory()
{
   datetime now=TimeCurrent();
   if(!adaptiveHistoryDirty && now-adaptiveHistoryAt<30) return;
   adaptiveHistoryReady=false;
   if(!HistorySelect(now-7*86400,now+1)) return;
   ulong ids[];
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i),id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol || Load(ExitKey(id)+"level")<=0) continue;
      bool seen=false; for(int j=0;j<ArraySize(ids);j++) if(ids[j]==id) { seen=true; break; }
      if(!seen) { int n=ArraySize(ids); ArrayResize(ids,n+1); ids[n]=id; }
   }
   AdaptiveResult results[];
   for(int i=0;i<ArraySize(ids);i++)
   {
      if(PositionById(ids[i])>0) continue;
      if(!HistorySelectByPosition(ids[i])) return;
      double entered=0,exited=0,net=0; int sign=0; datetime ended=0; bool own=false,valid=true;
      for(int j=0;j<HistoryDealsTotal();j++)
      {
         ulong d=HistoryDealGetTicket(j); long e=HistoryDealGetInteger(d,DEAL_ENTRY);
         if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol) continue;
         net+=HistoryDealGetDouble(d,DEAL_PROFIT)+HistoryDealGetDouble(d,DEAL_COMMISSION)+
              HistoryDealGetDouble(d,DEAL_SWAP)+HistoryDealGetDouble(d,DEAL_FEE);
         if(e==DEAL_ENTRY_IN)
         {
            entered+=HistoryDealGetDouble(d,DEAL_VOLUME);
            if((ulong)HistoryDealGetInteger(d,DEAL_MAGIC)==EA魔法号) own=true;
            sign=HistoryDealGetInteger(d,DEAL_TYPE)==DEAL_TYPE_BUY ? 1 : -1;
         }
         if(e==DEAL_ENTRY_OUT || e==DEAL_ENTRY_OUT_BY)
         { exited+=HistoryDealGetDouble(d,DEAL_VOLUME); ended=(datetime)MathMax(ended,HistoryDealGetInteger(d,DEAL_TIME)); }
         if(e==DEAL_ENTRY_INOUT) valid=false;
      }
      if(!own || !valid || entered<=0 || MathAbs(entered-exited)>1e-8 || ended<now-7*86400) continue;
      int n=ArraySize(results); ArrayResize(results,n+1);
      results[n].id=ids[i]; results[n].sign=sign; results[n].closed=ended; results[n].net=net;
      results[n].level=Load(ExitKey(ids[i])+"level");
   }
   // 最近完整平仓在前，部分退出不能增加重试次数；手机退出Magic=0仍计入净结果。
   for(int i=1;i<ArraySize(results);i++)
   {
      AdaptiveResult item=results[i]; int j=i-1;
      while(j>=0 && results[j].closed<item.closed) { results[j+1]=results[j]; j--; }
      results[j+1]=item;
   }
   ArrayResize(adaptiveResults,ArraySize(results));
   for(int i=0;i<ArraySize(results);i++) adaptiveResults[i]=results[i];
   adaptiveHistoryAt=now; adaptiveHistoryDirty=false; adaptiveHistoryReady=true;
}
bool AdaptiveConfirmed(const int sign,const double level,const datetime after)
{
   if(!AdaptiveMarketFresh()) return false;
   MqlRates bar=adaptiveBars[0];
   return bar.time>=after && sign*(bar.close-bar.open)>=adaptiveATR*0.10 &&
          sign*(bar.close-level)>TickSize()*0.5 && bar.low<=level+TEACHER_BAND && bar.high>=level-TEACHER_BAND;
}
string AdaptiveEntryStatus(const int i,const MqlTick &q)
{
   datetime now=TimeCurrent(),after=0;
   string news=AdaptiveNewsState(now,after); if(news!="") return news;
   if(now<adaptiveShockUntil) return "冲击冷却，已有仓继续管理";
   if(!AdaptiveMarketFresh()) return "M1/M5行情未就绪";
   if(!adaptiveHistoryReady || adaptiveHistoryDirty || now-adaptiveHistoryAt>60) return "成交历史核对中";
   int sign=PlanSign(i); double level=aiPlans[i].level;
   for(int j=PositionsTotal()-1;j>=0;j--)
   {
      if(PositionGetTicket(j)==0 || !OwnSelected()) continue;
      string key=ExitKey((ulong)PositionGetInteger(POSITION_IDENTIFIER));
      double used=Load(key+"level"); if(used<=0) used=PositionGetDouble(POSITION_PRICE_OPEN);
      if(MathAbs(used-level)<=TEACHER_BAND*2) return "本区域已有持仓";
   }
   int losses=0; datetime lastLoss=0;
   for(int j=0;j<ArraySize(adaptiveResults);j++)
   {
      if(adaptiveResults[j].sign!=sign || MathAbs(adaptiveResults[j].level-level)>TEACHER_BAND*2) continue;
      if(adaptiveResults[j].net>=0) break;
      losses++; if(lastLoss==0) lastLoss=adaptiveResults[j].closed;
   }
   if(losses>=2 && now<lastLoss+连亏区域冷却分钟*60) return "本区域连续亏损冷却";
   if(lastLoss>after) after=lastLoss;
   if(now<adaptiveRecoverUntil && adaptiveShockUntil>after) after=adaptiveShockUntil;
   bool confirm=after>0 || adaptiveTrend==-sign;
   if(confirm && !AdaptiveConfirmed(sign,level,after)) return "等待M1回收确认";
   return confirm ? "M1确认候选" : "触价候选";
}
bool AdaptiveEntryPrices(const Candidate &signal,const MqlTick &q,double &sl,double &first,double &tp,double &structure)
{
   if(!AdaptiveMarketFresh()) { reason="结构行情未就绪"; return false; }
   int sign=signal.direction; double entry=sign>0 ? q.ask : q.bid;
   double buffer=MathMax(MathMax(adaptiveATR*结构缓冲ATR倍数,q.ask-q.bid),TickSize()*2);
   structure=signal.level-sign*TEACHER_BAND;
   for(int i=0;i<3;i++)
      structure=sign>0 ? MathMin(structure,adaptiveBars[i].low) : MathMax(structure,adaptiveBars[i].high);
   sl=signal.exitSL>0 ? Align(signal.exitSL,sign) :
      Align(entry-sign*MathMax(最小结构风险距离,sign*(entry-structure)+buffer),-sign);
   double risk=sign*(entry-sl);
   if(risk<=0 || risk>保险价格距离+TickSize()*0.5)
   { reason="结构止损超过单笔风险上限，等待新结构"; return false; }
   // 老师有明确止损时不另造一个更远的结构失效位。
   if(sign*(structure-sl)<buffer) structure=sl+sign*buffer;
   double obstacle=DBL_MAX;
   for(int i=0;i<ArraySize(levels);i++)
   {
      double space=sign*(levels[i]-entry)-buffer;
      if(space>TickSize()*2 && MathAbs(levels[i]-signal.level)>TEACHER_BAND*2) obstacle=MathMin(obstacle,space);
   }
   double firstDistance=MathMin(首批止盈价格距离,MathMax(最小结构风险距离,risk*0.8));
   firstDistance=MathMin(firstDistance,obstacle);
   if(signal.exitFirst<=0 && firstDistance<risk*0.5)
   { reason="下一障碍过近，等待更好的入场价格"; return false; }
   first=signal.exitFirst>0 ? Align(signal.exitFirst,-sign) : Align(entry+sign*firstDistance,-sign);
   double targetDistance=MathMax(尾仓目标价格距离,risk*2.0);
   if(adaptiveTrend!=sign && obstacle<DBL_MAX) targetDistance=MathMin(targetDistance,obstacle);
   tp=signal.exitTP>0 ? Align(signal.exitTP,-sign) : Align(entry+sign*targetDistance,-sign);
   // 震荡的近障碍是全量目标时，首批放在目标前，不能把尾仓TP推过阻力。
   if(signal.exitFirst<=0 && sign*(tp-first)<=TickSize()) first=Align(entry+sign*(sign*(tp-entry)*0.7),-sign);
   return true;
}
bool AdaptiveRiskAllowed(const int sign,const double entry,const double sl,const double volume)
{
   double standard=0,loss=0;
   ENUM_ORDER_TYPE type=sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type,_Symbol,每次开仓手数,entry,entry-sign*保险价格距离,standard) ||
      !OrderCalcProfit(type,_Symbol,volume,entry,sl,loss) || !MathIsValidNumber(standard) || standard>=0 || !MathIsValidNumber(loss))
   { reason="风险金额计算失败"; return false; }
   double budget=-standard,total=MathMax(0,-loss);
   if(total>budget+0.01) { reason="单笔风险超过标准单"; return false; }
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0 || !OwnSelected()) continue;
      double stop=PositionGetDouble(POSITION_SL),pnl=0;
      ENUM_ORDER_TYPE side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(stop<=0 || !OrderCalcProfit(side,_Symbol,PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_PRICE_OPEN),stop,pnl) || !MathIsValidNumber(pnl))
      { reason="已有持仓风险不可计量，暂停叠加"; return false; }
      total+=MathMax(0,-pnl); // 不用另一单浮盈抵消风险。
   }
   if(total>budget*合计风险标准单倍数+0.01) { reason="合计止损风险达到上限"; return false; }
   return true;
}
// 纯价格保护目标，与请求成功/失败无关；只在实际SL确认后显示已保护。
double AdaptiveProtection(const int sign,const double open,const double risk,const double peak,const bool reduced)
{
   double stop=open-sign*risk;
   if(peak>=risk*减风险触发R) stop=open-sign*risk*0.5;
   if(peak>=risk*保本触发R || reduced) stop=open+sign*保本缓冲价格;
   return stop;
}
void ManageAdaptive(const ulong ticket,const ulong id,const int sign,const double open,const double volume,
                    const double sl,const double tp,const double initial,const double closed,const datetime opened,const MqlTick &q)
{
   string key=ExitKey(id); double price=sign>0 ? q.bid : q.ask;
   double risk=Load(key+"risk");
   if(risk<=0)
   {
      risk=sign*(open-Load(key+"initialSL"));
      if(risk<=TickSize()) { reason="成交风险基准异常，保留服务器保护"; return; }
      Store(key+"risk",risk); GlobalVariablesFlush();
   }
   double gain=sign*(price-open),peak=MathMax(Load(key+"mfe"),gain),adverse=MathMax(Load(key+"mae"),-gain);
   bool changed=false;
   if(peak>Load(key+"mfe")+TickSize()*0.5) { Store(key+"mfe",peak); changed=true; }
   if(adverse>Load(key+"mae")+TickSize()*0.5) { Store(key+"mae",adverse); changed=true; }
   if(changed) GlobalVariablesFlush();
   double half=LotDown(initial*0.5),minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   bool split=half>=minimum && initial-half>=minimum,reduced=split && closed+1e-8>=half;
   double goal=Load(key+"tp"),customSL=Load(key+"sl");
   if(AdaptiveNewsExit(TimeCurrent()))
   { RequestExit(ticket,id,volume,true,"重点消息窗口，主动退出新策略持仓"); return; }
   if((goal>0 && sign*(price-goal)>=0) || (customSL>0 && sign*(price-customSL)<=0))
   { RequestExit(ticket,id,volume,true,"已触及计划退出价"); return; }
   bool fresh=AdaptiveMarketFresh(); double structure=Load(key+"structure");
   if(fresh && adaptiveBars[0].time>=opened && structure>0 && sign*(adaptiveBars[0].close-structure)<-TickSize())
   { RequestExit(ticket,id,volume,true,"M1收盘越过入场结构，申请退出"); return; }
   if(fresh && TimeCurrent()-opened>=无进展退出分钟*60 && adaptiveBars[0].time>=opened && peak<risk*0.35 && gain<=0)
   { RequestExit(ticket,id,volume,true,"持仓无进展且未盈利，申请时间退出"); return; }
   double required=AdaptiveProtection(sign,open,risk,peak,reduced);
   if(customSL>0 && sign*(customSL-required)>0) required=customSL;
   if(Load(key+"beHit")==0 && Load(key+"be")>0 && sign*(price-Load(key+"be"))>=0)
   { Store(key+"beHit",1); GlobalVariablesFlush(); }
   if(Load(key+"beHit")==1 && sign*(open+sign*保本缓冲价格-required)>0) required=open+sign*保本缓冲价格;
   if(reduced && fresh && adaptiveBars[2].time>=opened)
   {
      double trail=sign>0 ? adaptiveBars[0].low : adaptiveBars[0].high;
      for(int i=1;i<3;i++) trail=sign>0 ? MathMin(trail,adaptiveBars[i].low) : MathMax(trail,adaptiveBars[i].high);
      trail-=sign*MathMax(adaptiveATR*结构缓冲ATR倍数,q.ask-q.bid);
      if(sign*(trail-required)>0) required=trail;
   }
   required=Align(required,-sign);
   if(sl>0 && sign*(sl-required)>0) required=sl;
   double target=goal>0 ? Align(goal,-sign) : tp;
   double first=FirstExit(id,sign,open,target);
   if(!reduced && sign*(price-first)>=0 && Load(key+"firstHit")==0)
   { Store(key+"firstHit",1); GlobalVariablesFlush(); }
   if(sign*(price-required)<=0)
   { RequestExit(ticket,id,volume,true,"价格回撤越过已获得的保护位，申请退出"); return; }
   // 保护优先；距离不足时不退回旧止损，等待价格可放置或实际越过保护位再退出。
   bool needsModify=sl<=0 || sign*(required-sl)>TickSize()*0.5 || MathAbs(target-tp)>TickSize()*0.5;
   if(needsModify && Stops(sign,required,target,q))
   { Modify(ticket,id,sign,required,target); if(pending.kind!=0) return; }
   if(reduced) return;
   if(Load(key+"firstHit")!=1) return;
   double take=PartialRemaining(initial,closed,volume);
   if(!split) { RequestExit(ticket,id,volume,true,"首批目标到达，手数无法拆分，全量退出"); return; }
   if(take>0) RequestExit(ticket,id,take,false,"首批目标到达，申请减至初始一半，成交后保护余仓");
}
string AdaptivePositionProgress(const ulong id,const int sign,const double open,const double sl)
{
   string key=ExitKey(id); double risk=Load(key+"risk");
   if(risk<=0) risk=sign*(open-Load(key+"initialSL"));
   string state=sl>0 && sign*(sl-open)>=0 ? "价格保本/跟踪已确认" :
                sl>0 && risk>0 && sign*(sl-(open-sign*risk*0.5))>=-TickSize() ? "减风险已确认" : "初始保护";
   if(pending.position==id && pending.kind!=0) state=pending.kind==2 ? "退出请求待确认" : "保护请求待确认";
   return "结构持单 · R="+DoubleToString(risk,2)+" · 最大浮盈 "+DoubleToString(risk>0 ? Load(key+"mfe")/risk : 0,2)+"R · "+state;
}
string AdaptiveCaption()
{
   datetime after=0; string news=AdaptiveNewsState(TimeCurrent(),after);
   if(news!="") return news+" · 持仓继续管理";
   if(TimeCurrent()<adaptiveShockUntil) return "异常冲击冷却 · 持仓继续管理";
   if(TimeCurrent()<adaptiveRecoverUntil || after>0) return "冲击/消息恢复期 · M1确认入场";
   return "积极触价 / 逆势M1确认 · 分级保护 / 结构退出"+(启用消息日历 ? "" : " · 消息日历关闭");
}
