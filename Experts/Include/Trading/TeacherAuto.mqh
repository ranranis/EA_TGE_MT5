#ifndef SMA_TRADING_TEACHER_AUTO_MQH
#define SMA_TRADING_TEACHER_AUTO_MQH

bool TeacherAutoFindLivePosition(ulong &ticket)
{
   ticket = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong candidate = PositionGetTicket(i);
      if(candidate == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != TEACHER_AUTO_SHORT_MAGIC) continue;
      ticket = candidate;
      return true;
   }
   return false;
}

bool TeacherAutoPendingOrderStillActive()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC) != TEACHER_AUTO_SHORT_MAGIC) continue;
      if(老师自动使用积极策略 || teacherAutoEntryState.pendingMode>0) return true;
      if(teacherAutoEntryState.pendingOrder == 0 || ticket == teacherAutoEntryState.pendingOrder ||
         StringFind(OrderGetString(ORDER_COMMENT), TEACHER_AUTO_COMMENT_PREFIX) == 0)
         return true;
   }
   return false;
}

double TeacherAutoNearestLevel(const double price)
{
   if(price <= 0.0 || !缓存老师点位有效) return 0.0;
   double nearest = 0.0;
   double nearestDistance = DBL_MAX;
   for(int i=0; i<ArraySize(缓存老师点位); i++)
   {
      double level = 缓存老师点位[i];
      double distance = MathAbs(level-price);
      if(level > 0.0 && distance < nearestDistance)
      {
         nearest = level;
         nearestDistance = distance;
      }
   }
   return nearest;
}

void TeacherAutoConfirmLivePosition()
{
   ulong ticket = 0;
   if(teacherAutoEntryState.pending)
   {
      ticket=TeacherAutoFindPendingPosition();
      // 部分成交后订单余量还在服务器，不允许放行下一请求。
      if(ticket==0 || TeacherAutoPendingOrderStillActive() || !PositionSelectByTicket(ticket)) return;
   }
   else
   {
      if(老师自动使用积极策略) return; // 多仓时不能拿任意旧仓覆盖最后一次请求身份
      if(!TeacherAutoFindLivePosition(ticket) || !PositionSelectByTicket(ticket)) return;
   }

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   datetime positionTime = (datetime)PositionGetInteger(POSITION_TIME);
   bool changed = false;
   if(teacherAutoEntryState.pending)
   {
      // 真实持仓出现才结束pending；CTrade返回true本身不推进这里的状态。
      TeacherActiveRecordTouch();
      TeacherAutoClearPendingStateFields();
      changed = true;
   }
   if(teacherAutoEntryState.lastDirection != (int)type)
   {
      teacherAutoEntryState.lastDirection = (int)type;
      changed = true;
   }
   if(teacherAutoEntryState.lastLevel <= 0.0)
   {
      double seededLevel = TeacherAutoNearestLevel(openPrice);
      if(seededLevel > 0.0)
      {
         teacherAutoEntryState.lastLevel = seededLevel;
         teacherAutoEntryState.rearmRequired = true;
         changed = true;
      }
   }
   if(teacherAutoEntryState.lastEntryTime <= 0)
   {
      teacherAutoEntryState.lastEntryTime = positionTime > 0 ? positionTime : TimeCurrent();
      changed = true;
   }
   if(changed)
   {
      TeacherAutoStateSave();
      PrintFormat("[老师自动短线] 真实持仓确认 ticket=%I64u direction=%d level=%.5f open=%.5f",
                  ticket, type, teacherAutoEntryState.lastLevel, openPrice);
   }
}

void TeacherAutoReconcilePending()
{
   TeacherAutoConfirmLivePosition();
   if(!teacherAutoEntryState.pending) return;

   datetime now = TimeCurrent();
   if(teacherAutoEntryState.pendingRequestTime <= 0)
   {
      Print("[老师自动短线] pending请求时间无效，已清理");
      TeacherAutoClearPendingStateFields();
      TeacherAutoStateSave();
      return;
   }

   if(TeacherAutoPendingOrderStillActive())
   {
      if(now >= teacherAutoEntryState.pendingRequestTime &&
         now-teacherAutoEntryState.pendingRequestTime >= TEACHER_AUTO_PENDING_TIMEOUT_SECONDS)
         PrintRateLimited("teacher_auto_pending_order_active", 30,
                          "[老师自动短线] pending超时但服务器订单仍存在，继续等待对账，禁止重复开仓");
      return;
   }

   if(now < teacherAutoEntryState.pendingRequestTime ||
      now-teacherAutoEntryState.pendingRequestTime < TEACHER_AUTO_PENDING_TIMEOUT_SECONDS)
      return;

   if(teacherAutoEntryState.pendingMode>0)
   {
      // 超时不代表没有成交。只按匹配历史订单的最终状态释放占位。
      if(!TerminalInfoInteger(TERMINAL_CONNECTED)) return;
      if(now-teacherAutoPendingCheckTime<10) return;
      teacherAutoPendingCheckTime=now;
      if(!TeacherAutoPendingOrderFinal())
      {
         PrintRateLimited("teacher_active_unresolved",60,"[老师积极] 请求结果未能确认，保留占位并暂停新单");
         return;
      }
      teacherActiveHistoryDirty=true;
   }

   PrintFormat("[老师自动短线] pending超时清理 direction=%d level=%.5f order=%I64u deal=%I64u",
               teacherAutoEntryState.pendingDirection, teacherAutoEntryState.pendingLevel,
               teacherAutoEntryState.pendingOrder, teacherAutoEntryState.pendingDeal);
   TeacherAutoClearPendingStateFields();
   // 请求曾被服务器受理但最终没有留下持仓；保持离开区域条件，避免同一根拒绝信号重复尝试。
   teacherAutoEntryState.rearmRequired = true;
   TeacherAutoStateSave();
}

double TeacherAutoReversalDistance(const double atr)
{
   double unit = GetShortLineVolatilityUnit(atr);
   double factor = MathMax(老师点位自动接近ATR倍数, 0.0);
   double distance = unit*factor;
   double tickSize = ShortTeacherTickSize();
   double spread = CurrentSpreadPrice();
   distance = MathMax(distance, MathMax(tickSize*4.0, spread*2.0));
   if(老师点位自动接近最大价格 > 0.0)
      distance = MathMin(distance, MathMax(老师点位自动接近最大价格, tickSize*4.0));
   return MathMax(distance, tickSize*2.0);
}

bool TeacherAutoRearmReady()
{
   if(!teacherAutoEntryState.rearmRequired) return true;
   if(teacherAutoEntryState.lastLevel <= 0.0) return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= bid) return false;
   double mid = (bid+ask)*0.5;
   double distance = MathMax(老师点位自动重新武装距离价格, ShortTeacherTickSize()*4.0);
   if(MathAbs(mid-teacherAutoEntryState.lastLevel) < distance) return false;

   teacherAutoEntryState.rearmRequired = false;
   TeacherAutoStateSave();
   PrintFormat("[老师自动短线] 已重新武装，价格离开上次点位 level=%.5f distance=%.5f",
               teacherAutoEntryState.lastLevel, distance);
   return true;
}

bool TeacherAutoStrictFixedVolume(double &volume)
{
   volume = 0.0;
   double requested = 老师点位自动短线固定手数;
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(requested <= 0.0 || minVolume <= 0.0 || maxVolume < minVolume || step <= 0.0) return false;

   double tolerance = MathMax(step*1e-7, 1e-10);
   if(requested < minVolume-tolerance || requested > maxVolume+tolerance) return false;
   double steps = (requested-minVolume)/step;
   if(MathAbs(steps-MathRound(steps)) > 1e-7) return false;
   // 只去除浮点显示误差，不把不合规输入向上或向下偷偷调整。
   volume = requested;
   return true;
}

double TeacherAutoAlignTradePrice(const double price, const ENUM_POSITION_TYPE type, const bool isSL)
{
   if(price <= 0.0) return 0.0;
   double tickSize = ShortTeacherTickSize();
   double steps = price/tickSize;
   bool roundUp = (type == POSITION_TYPE_BUY) ? !isSL : isSL;
   double aligned = roundUp ? MathCeil(steps-1e-9)*tickSize : MathFloor(steps+1e-9)*tickSize;
   return NormalizeDouble(aligned, _Digits);
}

bool TeacherAutoBuildInitialSLTP(const ENUM_POSITION_TYPE type, const double openPrice, const double atr,
                                  double &sl, double &tp)
{
   sl = 0.0;
   tp = 0.0;
   if(openPrice <= 0.0) return false;

   double initSLDistance = ShortLineDynamicInitialSL(atr, type);
   double boxSL = 0.0, boxSLDistance = 0.0;
   bool hasBoxSL = ShortLineBoxSLPrice(type, openPrice, boxSL, boxSLDistance);
   if(hasBoxSL) initSLDistance = MathMax(initSLDistance, boxSLDistance);

   double visualSL = 0.0, visualTP = 0.0, visualSLDistance = 0.0, visualTPDistance = 0.0;
   bool hasVisualBox = ShortLineVisualBoxInitialTargets(type, openPrice, visualSL, visualTP,
                                                         visualSLDistance, visualTPDistance);
   if(hasVisualBox) initSLDistance = visualSLDistance;
   if(initSLDistance <= 0.0) return false;

   double initTPDistance = ShortLineDynamicMainTP(atr, type);
   double boxTP = 0.0, boxTPDistance = 0.0;
   bool hasBoxTP = ShortLineBoxTPPrice(type, openPrice, boxTP, boxTPDistance);
   bool useVisualBoxTP = false;
   if(hasVisualBox && visualTPDistance > 0.0 && visualTPDistance < initTPDistance)
   {
      initTPDistance = visualTPDistance;
      useVisualBoxTP = true;
   }
   else if(!hasVisualBox && hasBoxTP && boxTPDistance > 0.0 &&
           boxTPDistance < initTPDistance &&
           boxTPDistance >= initTPDistance*MathMax(短线单箱体TP最小主目标比例, 0.10) &&
           boxTPDistance >= 短线单箱体TP最小空间价格)
      initTPDistance = boxTPDistance;
   if(initTPDistance <= 0.0) return false;

   double rawSL = type == POSITION_TYPE_BUY ? openPrice-initSLDistance : openPrice+initSLDistance;
   double rawTP = type == POSITION_TYPE_BUY ? openPrice+initTPDistance : openPrice-initTPDistance;
   sl = hasVisualBox ? TeacherAutoAlignTradePrice(visualSL, type, true) :
                       TeacherAutoAlignTradePrice(rawSL, type, true);
   tp = useVisualBoxTP ? TeacherAutoAlignTradePrice(visualTP, type, false) :
                         TeacherAutoAlignTradePrice(rawTP, type, false);
   if(!SLTPValid(type, sl, tp))
   {
      // 与既有短线初始风险逻辑一致：结构候选不合规时退回灾难保护SL，仍须再次过服务器距离校验。
      sl = TeacherAutoAlignTradePrice(ShortEmergencySLPrice(type, openPrice, atr), type, true);
   }
   if(!SLTPValid(type, sl, tp))
   {
      sl = 0.0;
      tp = 0.0;
      return false;
   }
   return true;
}

bool TeacherAutoGetFiveDayRange(double &rangeHigh, double &rangeLow)
{
   rangeHigh = 0.0;
   rangeLow = 0.0;
   if(!启用老师点位自动5日结构过滤) return true;

   const int lookbackDays = 5;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_D1, 1, lookbackDays, rates) < lookbackDays)
      return false;

   for(int i=0; i<lookbackDays; i++)
   {
      if(rates[i].high <= 0.0 || rates[i].low <= 0.0 || rates[i].high < rates[i].low)
         return false;
      if(rangeHigh <= 0.0 || rates[i].high > rangeHigh) rangeHigh = rates[i].high;
      if(rangeLow <= 0.0 || rates[i].low < rangeLow) rangeLow = rates[i].low;
   }
   return (rangeHigh > rangeLow && rangeLow > 0.0);
}

bool TeacherAutoLevelAtFiveDayEdge(const double level, const bool resistance,
                                   const double rangeHigh, const double rangeLow)
{
   if(!启用老师点位自动5日结构过滤) return true;
   if(level <= 0.0 || rangeHigh <= rangeLow) return false;

   double range = rangeHigh-rangeLow;
   double ratio = ClampDouble(老师点位自动5日结构边缘比例, 0.05, 0.50);
   double tickSize = ShortTeacherTickSize();
   double edgeDistance = MathMax(range*ratio, tickSize*4.0);
   if(老师点位自动5日结构最大边缘距离 > 0.0)
      edgeDistance = MathMin(edgeDistance,
                             MathMax(老师点位自动5日结构最大边缘距离, tickSize*4.0));

   if(resistance) return level >= rangeHigh-edgeDistance;
   return level <= rangeLow+edgeDistance;
}

bool TeacherAutoM5ReversalConfirmed(const double level, const int direction,
                                    const double nearDistance, MqlRates &rates[])
{
   if(!启用老师点位自动M5确认) return true;
   if(level <= 0.0 || nearDistance <= 0.0) return false;
   if(ArraySize(rates) < 2) return false;

   double tickSize = ShortTeacherTickSize();
   double lastRange = rates[0].high-rates[0].low;
   double previousRange = rates[1].high-rates[1].low;
   if(lastRange <= tickSize || previousRange <= tickSize) return false;

   double body = MathAbs(rates[0].close-rates[0].open);
   double m5NearDistance = MathMax(nearDistance, tickSize*8.0);
   double m5MaxPenetration = MathMax(nearDistance*1.50, tickSize*12.0);
   double m5BreakoutBuffer = MathMax(nearDistance*0.75, tickSize*8.0);
   double minWickRatio = MathMax(ClampDouble(老师点位自动反转最小影线比例, 0.0, 0.95)*0.85, 0.25);
   double maxBodyRatio = MathMin(ClampDouble(老师点位自动反转最大实体比例, 0.05, 0.95)+0.10, 0.75);
   bool slowdown = body/lastRange <= maxBodyRatio || lastRange <= previousRange*0.90;

   if(direction == POSITION_TYPE_SELL)
   {
      double upperWick = rates[0].high-MathMax(rates[0].open, rates[0].close);
      bool approachedFromBelow = rates[1].close < level-tickSize*0.5;
      bool touchedPressure = rates[0].high >= level-m5NearDistance;
      bool notDeepBreak = rates[0].high <= level+m5MaxPenetration;
      bool closedBackBelow = rates[0].close < level-tickSize*0.5;
      bool strongBreak = rates[0].close > level+m5BreakoutBuffer;
      bool rejection = upperWick/lastRange >= minWickRatio;
      bool bearishClose = rates[0].close <= rates[0].open || rates[0].close < rates[1].close;
      return approachedFromBelow && touchedPressure && notDeepBreak && closedBackBelow &&
             !strongBreak && rejection && slowdown && bearishClose;
   }

   if(direction == POSITION_TYPE_BUY)
   {
      double lowerWick = MathMin(rates[0].open, rates[0].close)-rates[0].low;
      bool approachedFromAbove = rates[1].close > level+tickSize*0.5;
      bool touchedSupport = rates[0].low <= level+m5NearDistance;
      bool notDeepBreak = rates[0].low >= level-m5MaxPenetration;
      bool closedBackAbove = rates[0].close > level+tickSize*0.5;
      bool strongBreak = rates[0].close < level-m5BreakoutBuffer;
      bool rejection = lowerWick/lastRange >= minWickRatio;
      bool bullishClose = rates[0].close >= rates[0].open || rates[0].close > rates[1].close;
      return approachedFromAbove && touchedSupport && notDeepBreak && closedBackAbove &&
             !strongBreak && rejection && slowdown && bullishClose;
   }
   return false;
}

// 积极策略的日线/ATR只读取已收柱，句柄按需创建，日线偏向每日缓存。
bool TeacherActiveContext(double &atr)
{
   atr = 0.0;
   if(teacherActiveATRHandle == INVALID_HANDLE)
      teacherActiveATRHandle = iATR(_Symbol, PERIOD_M5, 14);
   if(teacherActiveEMAHandle == INVALID_HANDLE)
      teacherActiveEMAHandle = iMA(_Symbol, PERIOD_D1, 20, 0, MODE_EMA, PRICE_CLOSE);
   if(teacherActiveATRHandle == INVALID_HANDLE || teacherActiveEMAHandle == INVALID_HANDLE) return false;
   double values[];
   if(CopyBuffer(teacherActiveATRHandle, 0, 1, 1, values) != 1 ||
      !MathIsValidNumber(values[0]) || values[0] <= 0.0) return false;
   atr = values[0];
   datetime day = iTime(_Symbol, PERIOD_D1, 0);
   if(day <= 0) return false;
   if(day == teacherActiveContextDay) return true;
   MqlRates daily[];
   ArraySetAsSeries(daily, true);
   double ema[];
   ArraySetAsSeries(ema, true);
   if(CopyRates(_Symbol, PERIOD_D1, 1, 5, daily) != 5 ||
      CopyBuffer(teacherActiveEMAHandle, 0, 1, 4, ema) != 4) return false;
   if(!MathIsValidNumber(ema[0]) || !MathIsValidNumber(ema[3]) || ema[0] <= 0 || ema[3] <= 0) return false;
   teacherActiveBias = daily[0].close > ema[0] && ema[0] > ema[3] ? 1 :
                      (daily[0].close < ema[0] && ema[0] < ema[3] ? -1 : 0);
   teacherActiveDayHigh = daily[0].high;
   teacherActiveDayLow = daily[0].low;
   teacherActiveFiveHigh = daily[0].high;
   teacherActiveFiveLow = daily[0].low;
   for(int i=0; i<5; i++)
   {
      if(daily[i].low <= 0.0 || daily[i].high <= daily[i].low) return false;
      teacherActiveFiveHigh = MathMax(teacherActiveFiveHigh, daily[i].high);
      teacherActiveFiveLow = MathMin(teacherActiveFiveLow, daily[i].low);
   }
   teacherActiveContextDay = day;
   return true;
}

datetime TeacherActiveDay()
{
   MqlDateTime parts;
   TimeToStruct(TimeCurrent(), parts);
   parts.hour=0; parts.min=0; parts.sec=0;
   return StructToTime(parts);
}

void TeacherActiveHalt()
{
   if(TeacherAutoStateRead("AH")>0) return;
   GlobalVariableSet(TeacherAutoStateKey("AH"),1.0);
   GlobalVariablesFlush();
}

// 仅Init/Timer查历史，按完整position id统计今日最终平仓，不把分批当连败。
void TeacherActiveRefreshRisk()
{
   if(!老师自动使用积极策略 || !启用老师点位自动反转短线) return;
   datetime now = TimeCurrent(), day = TeacherActiveDay();
   if((datetime)TeacherAutoStateRead("AD") != day)
   {
      GlobalVariableSet(TeacherAutoStateKey("AD"), (double)day);
      GlobalVariableSet(TeacherAutoStateKey("AE"), AccountInfoDouble(ACCOUNT_EQUITY));
      GlobalVariableSet(TeacherAutoStateKey("AH"), 0.0);
      for(int i=0; i<MAX_TEACHER_MARKER_LEVELS*2; i++)
         GlobalVariableDel(TeacherAutoStateKey("AC"+IntegerToString(i)));
      teacherActiveHistoryDirty = true;
      teacherActiveHistoryReady = false;
   }
   double baseline = TeacherAutoStateRead("AE");
   if(baseline > 0 && AccountInfoDouble(ACCOUNT_EQUITY) <= baseline*(1.0-老师自动日内亏损上限百分比/100.0))
      TeacherActiveHalt();
   if(!teacherActiveHistoryDirty && teacherActiveHistoryReady && now-teacherActiveHistoryTime<30) return;
   if(teacherActiveHistoryTime > 0 && now-teacherActiveHistoryTime < 2) return;
   teacherActiveHistoryTime = now;
   teacherActiveHistoryReady = false;
   if(teacherActiveLatestDeal>0 && !HistoryDealSelect(teacherActiveLatestDeal)) return;
   if(!HistorySelect(day-老师自动止损冷却秒, now)) return;
   ulong ids[];
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT) continue;
      ulong id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(id == 0) continue;
      bool found=false;
      for(int j=0; j<ArraySize(ids); j++) if(ids[j] == id) { found=true; break; }
      if(!found) { int n=ArraySize(ids); ArrayResize(ids,n+1); ids[n]=id; }
   }
   datetime times[];
   bool losses[];
   teacherActiveLastStop = 0;
   for(int i=0; i<ArraySize(ids); i++)
   {
      if(FindOpenPositionTicketByIdentifier(ids[i]) != 0) continue;
      if(!HistorySelectByPosition(ids[i])) return;
      bool ours=false, stopped=false, reversed=false;
      double net=0.0, inVolume=0.0, outVolume=0.0;
      datetime closeTime=0;
      for(int j=0; j<HistoryDealsTotal(); j++)
      {
         ulong deal=HistoryDealGetTicket(j);
         long entry=HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN && HistoryDealGetInteger(deal, DEAL_MAGIC) == TEACHER_AUTO_SHORT_MAGIC)
            ours=true;
         if(entry == DEAL_ENTRY_IN) inVolume += HistoryDealGetDouble(deal, DEAL_VOLUME);
         if(entry == DEAL_ENTRY_INOUT) reversed=true;
         if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
         {
            outVolume += HistoryDealGetDouble(deal, DEAL_VOLUME);
            datetime time=(datetime)HistoryDealGetInteger(deal, DEAL_TIME);
            if(time >= closeTime) { closeTime=time; stopped=HistoryDealGetInteger(deal, DEAL_REASON)==DEAL_REASON_SL; }
         }
         net += HistoryDealGetDouble(deal, DEAL_PROFIT)+HistoryDealGetDouble(deal, DEAL_COMMISSION)+
                HistoryDealGetDouble(deal, DEAL_SWAP)+HistoryDealGetDouble(deal, DEAL_FEE);
      }
      if(!ours) continue;
      if(reversed) return; // 本模块仓位被外部净额反转：不猜完整归属
      if(inVolume <= 0 || outVolume+SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)*0.5 < inVolume) return;
      bool loss=stopped && net < 0.0;
      if(loss) teacherActiveLastStop=MathMax(teacherActiveLastStop,closeTime);
      if(closeTime < day) continue;
      int n=ArraySize(times), at=n;
      ArrayResize(times,n+1); ArrayResize(losses,n+1);
      while(at>0 && times[at-1]>closeTime) { times[at]=times[at-1]; losses[at]=losses[at-1]; at--; }
      times[at]=closeTime; losses[at]=loss;
   }
   int streak=0;
   for(int i=0; i<ArraySize(times); i++)
   {
      streak=losses[i] ? streak+1 : 0;
      if(streak >= 老师自动连续止损上限) TeacherActiveHalt();
   }
   teacherActiveHistoryDirty=false;
   teacherActiveHistoryReady=true;
}

bool TeacherActivePlanValid()
{
   if(!缓存老师点位有效 || ArraySize(缓存老师点位)==0) return false;
   datetime now=TimeCurrent();
   if(TeacherAutoStateReadUlong("AS") != 缓存老师点位签名)
   {
      TeacherAutoStateWriteUlong("AS",缓存老师点位签名);
      GlobalVariableSet(TeacherAutoStateKey("AF"),(double)now);
      for(int i=0; i<MAX_TEACHER_MARKER_LEVELS*2; i++)
      {
         GlobalVariableDel(TeacherAutoStateKey("AC"+IntegerToString(i)));
         GlobalVariableDel(TeacherAutoStateKey("AB"+IntegerToString(i)));
         GlobalVariableDel(TeacherAutoStateKey("AT"+IntegerToString(i)));
      }
   }
   datetime start=老师自动点位生效时间 > 0 ? 老师自动点位生效时间 : (datetime)TeacherAutoStateRead("AF");
   datetime end=老师自动点位失效时间 > 0 ? 老师自动点位失效时间 : start+86400;
   return start>0 && end>start && now>=start && now<end;
}

int TeacherActiveLiveCount()
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (long)PositionGetInteger(POSITION_MAGIC)==TEACHER_AUTO_SHORT_MAGIC) count++;
   }
   return count;
}

string TeacherAutoPendingComment()
{
   return "TEACHER_ACTIVE_"+IntegerToString(teacherAutoEntryState.pendingMode)+"_"+
          IntegerToString((long)teacherAutoEntryState.pendingSignalBarTime);
}

ulong TeacherAutoFindPendingPosition()
{
   if(!teacherAutoEntryState.pending) return 0;
   ulong id=0;
   if(teacherAutoEntryState.pendingDeal>0 && HistoryDealSelect(teacherAutoEntryState.pendingDeal))
      id=(ulong)HistoryDealGetInteger(teacherAutoEntryState.pendingDeal,DEAL_POSITION_ID);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         PositionGetInteger(POSITION_MAGIC)!=TEACHER_AUTO_SHORT_MAGIC) continue;
      if(id>0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==id) return ticket;
      if(teacherAutoEntryState.pendingMode>0 &&
         PositionGetString(POSITION_COMMENT)==TeacherAutoPendingComment() &&
         PositionGetInteger(POSITION_TYPE)==teacherAutoEntryState.pendingDirection) return ticket;
      // 升级前请求没有唯一comment，只允许请求后出现且方向一致的仓位。
      if(teacherAutoEntryState.pendingMode==0 &&
         PositionGetInteger(POSITION_TIME)>=teacherAutoEntryState.pendingRequestTime &&
         PositionGetInteger(POSITION_TYPE)==teacherAutoEntryState.pendingDirection) return ticket;
   }
   return 0;
}

bool TeacherAutoPendingOrderFinal()
{
   if(!HistorySelect(teacherAutoEntryState.pendingRequestTime-1,TimeCurrent())) return false;
   for(int i=HistoryOrdersTotal()-1;i>=0;i--)
   {
      ulong order=HistoryOrderGetTicket(i);
      if(order==0 || HistoryOrderGetString(order,ORDER_SYMBOL)!=_Symbol ||
         HistoryOrderGetInteger(order,ORDER_MAGIC)!=TEACHER_AUTO_SHORT_MAGIC) continue;
      if(teacherAutoEntryState.pendingOrder>0 ? order!=teacherAutoEntryState.pendingOrder :
         HistoryOrderGetString(order,ORDER_COMMENT)!=TeacherAutoPendingComment()) continue;
      long state=HistoryOrderGetInteger(order,ORDER_STATE);
      if(state==ORDER_STATE_FILLED || state==ORDER_STATE_CANCELED ||
         state==ORDER_STATE_REJECTED || state==ORDER_STATE_EXPIRED)
         return TeacherAutoFinalOrderReconciled(order,state==ORDER_STATE_FILLED);
   }
   return false;
}

bool TeacherAutoFinalOrderReconciled(ulong order,bool filled)
{
   // 历史订单FILLED仍不能替代真实Position/Deal；快开快平要看到完整退出量。
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if((ulong)HistoryDealGetInteger(deal,DEAL_ORDER)!=order ||
         HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
      ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(id==0) return false;
      teacherAutoEntryState.pendingDeal=deal;
      TeacherAutoStateSave();
      if(FindOpenPositionTicketByIdentifier(id)>0) return false; // 下次按精确id确认
      if(!HistorySelectByPosition(id)) return false;
      double entered=0,exited=0;
      for(int j=0;j<HistoryDealsTotal();j++)
      {
         ulong d=HistoryDealGetTicket(j);
         long entry=HistoryDealGetInteger(d,DEAL_ENTRY);
         if(entry==DEAL_ENTRY_IN) entered+=HistoryDealGetDouble(d,DEAL_VOLUME);
         else if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY) exited+=HistoryDealGetDouble(d,DEAL_VOLUME);
         else if(entry==DEAL_ENTRY_INOUT) return false;
      }
      if(entered<=0 || exited+SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)*0.5<entered) return false;
      TeacherActiveRecordTouch();
      return true;
   }
   return !filled; // 已撤/拒绝且无成交；FILLED无Deal时继续占位
}

void TeacherActiveRecordTouch()
{
   if(teacherAutoEntryState.pendingMode<=0) return;
   for(int i=0;i<ArraySize(缓存老师点位);i++)
      if(MathAbs(缓存老师点位[i]-teacherAutoEntryState.pendingLevel)<ShortTeacherTickSize()*0.5)
         GlobalVariableSet(TeacherAutoStateKey("AT"+IntegerToString(i*2+teacherAutoEntryState.pendingDirection)),
                           (double)teacherAutoEntryState.pendingSignalBarTime);
}

bool TeacherActiveCanOpen()
{
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING ||
      teacherAutoEntryState.pending) return false;
   int slots=TeacherActiveLiveCount();
   if(slots>=MathMin(老师自动同时最大持仓,5)) return false;
   // 不与手动/其他策略持仓或挂单混开；手机提示单仍按原独立规则处理。
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      long magic=PositionGetInteger(POSITION_MAGIC);
      if(magic!=TEACHER_AUTO_SHORT_MAGIC && magic!=手机标记挂单Magic) return false;
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong order=OrderGetTicket(i);
      if(order==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if(OrderGetInteger(ORDER_MAGIC)==手机标记挂单Magic &&
         StringFind(OrderGetString(ORDER_COMMENT),"SMA_MARK_")==0) continue;
      // 包括前一笔尚未终结的老师服务器订单；不并发发送请求。
      return false;
   }
   return true;
}

bool TeacherActiveRange(MqlRates &m5[],double atr,double &low,double &high)
{
   low=0; high=0;
   if(!老师自动允许震荡双向 || ArraySize(m5)<13 || atr<=0) return false;
   low=m5[1].low; high=m5[1].high;
   double path=0;
   for(int i=1;i<=12;i++)
   {
      low=MathMin(low,m5[i].low); high=MathMax(high,m5[i].high);
      if(i<12) path+=MathAbs(m5[i].close-m5[i+1].close);
   }
   double width=high-low;
   return path>0 && MathAbs(m5[1].close-m5[12].close)/path<=0.35 &&
          width>=atr*1.5 && width<=atr*6.0 && m5[0].close>low && m5[0].close<high;
}

// directionSign: BUY=+1, SELL=-1。仅传入已收M1；不再要求顺势M5也长影线。
bool TeacherActiveM1Trigger(MqlRates &bar, MqlRates &previous, double level,
                           int directionSign, double nearDistance, double penetration)
{
   double extreme=directionSign>0 ? bar.low : bar.high;
   return directionSign*(previous.close-level)>0 &&
          directionSign*(bar.close-level)>0 && directionSign*(bar.close-bar.open)>0 &&
          directionSign*(extreme-level)<=nearDistance && directionSign*(extreme-level)>=-penetration;
}

// 返回最近有效突破的收盘时间；随后回踩必须发生在这之后。
datetime TeacherActiveBreakout(MqlRates &m5[], double level, int sign, double buffer)
{
   for(int i=0; i<3 && i+1<ArraySize(m5); i++)
   {
      if(sign*(m5[i].close-level)>buffer && sign*(m5[i+1].close-level)<=buffer)
      {
         for(int j=i-1; j>=0; j--)
            if(sign*(m5[j].close-level)<-buffer) return 0;
         return m5[i].time+PeriodSeconds(PERIOD_M5);
      }
   }
   return 0;
}

bool TeacherActiveFindCandidate(int &direction, double &level, datetime &signalTime,
                               double &atr, int &mode, int &levelIndex, datetime &breakTime)
{
   if(!TeacherActiveContext(atr)) return false;
   MqlRates m1[],m5[];
   ArraySetAsSeries(m1,true); ArraySetAsSeries(m5,true);
   if(CopyRates(_Symbol,PERIOD_M1,1,18,m1)!=18 || CopyRates(_Symbol,PERIOD_M5,1,13,m5)!=13) return false;
   double rangeLow=0,rangeHigh=0;
   bool ranging=TeacherActiveRange(m5,atr,rangeLow,rangeHigh);
   double nearDistance=MathMax(atr*老师自动接近M5ATR,ShortTeacherTickSize()*4);
   double buffer=MathMax(atr*老师自动突破缓冲M5ATR,ShortTeacherTickSize()*2);
   double best=DBL_MAX;
   direction=-1;
   for(int i=0; i<ArraySize(缓存老师点位); i++)
   {
      double price=缓存老师点位[i];
      for(int d=0; d<2; d++)
      {
         int sign=d==POSITION_TYPE_BUY ? 1 : -1;
         if(!TeacherAutoDirectionAllowed(d)) continue;
         double entry=SymbolInfoDouble(_Symbol,d==POSITION_TYPE_BUY ? SYMBOL_ASK : SYMBOL_BID);
         double distance=MathAbs(entry-price);
         if(distance>atr*老师自动追价上限M5ATR || distance>=best) continue;
         datetime lastTouch=(datetime)TeacherAutoStateRead("AT"+IntegerToString(i*2+d));
         if(lastTouch>0)
         {
            bool left=false;
            for(int k=1; k<ArraySize(m1); k++)
               if(m1[k].time>lastTouch && sign*(m1[k].close-price)>nearDistance)
                  { left=true; break; }
            if(!left) continue;
         }
         int candidateMode=0;
         datetime breakout=TeacherActiveBreakout(m5,price,sign,buffer);
         bool aligned=teacherActiveBias==sign;
         bool trigger=TeacherActiveM1Trigger(m1[0],m1[1],price,sign,nearDistance,buffer);
         if(ranging)
         {
            // 震荡上下沿分别交易，不受日线单向偏好限制；区间中段不反转。
            double edge=sign>0 ? rangeLow : rangeHigh;
            if(!trigger || MathAbs(price-edge)>(rangeHigh-rangeLow)*0.25) continue;
            candidateMode=4;
         }
         else if(aligned && trigger)
         {
            if(breakout>0)
            {
               if(m1[0].time<breakout || m1[0].time>=breakout+3*PeriodSeconds(PERIOD_M5)) continue;
               candidateMode=2;
            }
            else
            {
               // 已收M5必须在老师线的持有侧，否则仍处于未确认突破中。
               if(sign*(m5[0].close-price)<=0) continue;
               candidateMode=1;
            }
         }
         else if(!aligned)
         {
            double edge=sign>0 ? teacherActiveDayLow : teacherActiveDayHigh;
            double five=sign>0 ? teacherActiveFiveLow : teacherActiveFiveHigh;
            if(MathMin(MathAbs(price-edge),MathAbs(price-five))>nearDistance) continue;
            // 逆势/中性始终保留M5拒绝，不受旧M5开关放宽影响。
            double range=m5[0].high-m5[0].low;
            double wick=sign>0 ? MathMin(m5[0].open,m5[0].close)-m5[0].low :
                                m5[0].high-MathMax(m5[0].open,m5[0].close);
            if(range<=0 || wick/range<0.30 ||
               !TeacherActiveM1Trigger(m5[0],m5[1],price,sign,nearDistance,buffer)) continue;
            double r=m1[0].high-m1[0].low;
            double w=sign>0 ? MathMin(m1[0].open,m1[0].close)-m1[0].low :
                             m1[0].high-MathMax(m1[0].open,m1[0].close);
            if(!trigger || r<=0 || w/r<0.30) continue;
            candidateMode=3;
         }
         if(candidateMode==0) continue;
         best=distance; direction=d; level=price; signalTime=m1[0].time;
         mode=candidateMode; levelIndex=i; breakTime=breakout;
      }
   }
   return direction>=0;
}

bool TeacherActiveBuildOrder(int direction, double level, double atr, int mode,
                            double &sl, double &tp, double &volume)
{
   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)direction;
   ENUM_ORDER_TYPE orderType=direction==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   int sign=direction==POSITION_TYPE_BUY ? 1 : -1;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID),ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double entry=sign>0 ? ask : bid;
   if(bid<=0 || ask<=bid || MathAbs(entry-level)>atr*老师自动追价上限M5ATR) return false;
   MqlRates bar[];
   if(CopyRates(_Symbol,PERIOD_M1,1,1,bar)!=1) return false;
   double buffer=MathMax(atr*老师自动止损缓冲M5ATR,ShortTeacherTickSize()*2);
   double rawSL=sign>0 ? MathMin(level,bar[0].low)-buffer : MathMax(level,bar[0].high)+buffer;
   double minDistance=(double)MathMax(SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                     SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point+ShortTeacherTickSize();
   rawSL=sign>0 ? MathMin(rawSL,bid-minDistance) : MathMax(rawSL,ask+minDistance);
   sl=TeacherAutoAlignTradePrice(rawSL,type,true);
   double risk=sign*(entry-sl);
   if(risk<=0) return false;
   double target=entry+sign*risk*5.0;
   // 区间单目标不越过另一侧边缘；趋势单仍尊重前方老师/日线障碍。
   if(mode==4)
   {
      MqlRates rangeBars[];
      ArraySetAsSeries(rangeBars,true);
      double rangeLow=0,rangeHigh=0;
      if(CopyRates(_Symbol,PERIOD_M5,1,13,rangeBars)!=13 ||
         !TeacherActiveRange(rangeBars,atr,rangeLow,rangeHigh)) return false;
      double rangeTarget=(sign>0 ? rangeHigh : rangeLow)-sign*buffer;
      if(sign*(rangeTarget-target)<0) target=rangeTarget;
   }
   for(int i=0; i<ArraySize(缓存老师点位)+4; i++)
   {
      double obstacle=0;
      int n=ArraySize(缓存老师点位);
      if(i<n) obstacle=缓存老师点位[i];
      else if(i==n) obstacle=teacherActiveDayHigh;
      else if(i==n+1) obstacle=teacherActiveDayLow;
      else if(i==n+2) obstacle=teacherActiveFiveHigh;
      else obstacle=teacherActiveFiveLow;
      if(sign*(obstacle-entry)>0 && MathAbs(obstacle-level)>ShortTeacherTickSize())
      {
         double candidate=obstacle-sign*buffer;
         if(sign*(candidate-target)<0) target=candidate;
      }
   }
   // 目标朝入场方向对齐，绝不因取整越过障碍。
   tp=TeacherAutoAlignTradePrice(target,type,true);
   if(!SLTPValid(type,sl,tp)) return false;
   double testVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double loss=0,profit=0,margin=0;
   if(testVolume<=0 || !OrderCalcProfit(orderType,_Symbol,testVolume,entry,sl,loss) ||
      !OrderCalcProfit(orderType,_Symbol,testVolume,entry,tp,profit) || loss>=0 || profit<=0) return false;
   double costs=老师自动每手往返费用*testVolume;
   // entry为真实买Ask/卖Bid，已含点差；另加一次当前点差作为滑点预算。
   double slippage=0;
   if(!OrderCalcProfit(orderType,_Symbol,testVolume,entry,entry-sign*(ask-bid),slippage)) return false;
   costs+=MathAbs(slippage);
   if((profit-costs)/(-loss+costs)<老师自动最低净盈亏比) return false;
   if(!TeacherAutoStrictFixedVolume(volume)) return false;
   if(!OrderCalcMargin(orderType,_Symbol,volume,entry,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)) return false;
   return true;
}

void ManageTeacherActivePosition(ulong ticket,int stateIdx,ENUM_POSITION_TYPE type,double openPrice,double profitPrice)
{
   if(!PositionSelectByTicket(ticket) || !states[stateIdx].shortRiskReady ||
      states[stateIdx].partialRequestPending || states[stateIdx].pendingAction!=待确认动作_无) return;
   double risk=states[stateIdx].shortInitialRisk;
   if(risk<=0) return;
   if(profitPrice<=-risk*MathMax(短线单绝对最大风险R,1.0))
   { SubmitManagedFullClose(ticket,stateIdx,退出意图_紧急风控,"teacher_active_risk_guard"); return; }
   double volume=PositionGetDouble(POSITION_VOLUME);
   if(profitPrice>=risk*老师自动贪婪首段R && states[stateIdx].partialTPStage<1)
   {
      double closeVolume=NormalizeVolumeDown(states[stateIdx].initialVolume*0.5-ShortStageFilledVolume(stateIdx,1));
      double minVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      if(closeVolume>=minVolume && volume-closeVolume>=minVolume)
      {
         SubmitManagedPartialClose(ticket,stateIdx,closeVolume,1,退出意图_分批止盈,"teacher_active_greedy_half");
         return;
      }
      // 0.01等无法分批的仓位继续整仓持有，不能到首段阈值就被强制全收。
   }
   if(!currentTickHasNewM1Bar || profitPrice<risk*老师自动贪婪保护R) return;
   MqlRates bars[];
   ArraySetAsSeries(bars,true);
   if(CopyRates(_Symbol,PERIOD_M5,1,3,bars)!=3) return;
   int sign=type==POSITION_TYPE_BUY ? 1 : -1;
   double structural=sign>0 ? MathMin(bars[0].low,bars[1].low) : MathMax(bars[0].high,bars[1].high);
   structural=sign>0 ? MathMin(structural,bars[2].low) : MathMax(structural,bars[2].high);
   double atr=0;
   if(!TeacherActiveContext(atr)) return;
   structural-=sign*atr*MathMax(老师自动止损缓冲M5ATR,0.25);
   double be=openPrice+sign*CurrentSpreadPrice();
   if(sign*(structural-be)<0) return; // 没有已收结构支持，不贴价保本
   double candidate=states[stateIdx].partialTPStage>=1 || profitPrice>=risk*老师自动贪婪首段R ? structural : be;
   candidate=TeacherAutoAlignTradePrice(candidate,type,true);
   double oldSL=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
   if(MoreProtective(type,candidate,oldSL) && SLTPValid(type,candidate,tp))
      SubmitManagedPositionModify(ticket,stateIdx,candidate,tp,SL来源_其他,TP来源_无);
}

bool TeacherAutoFindReversalCandidate(const double atr, int &direction, double &level, datetime &signalBarTime)
{
   direction = -1;
   level = 0.0;
   signalBarTime = 0;
   if(!缓存老师点位有效 || ArraySize(缓存老师点位) <= 0) return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M1, 1, 3, rates) < 3) return false;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= bid) return false;

   double lastRange = rates[0].high-rates[0].low;
   double previousRange = rates[1].high-rates[1].low;
   double tickSize = ShortTeacherTickSize();
   double spread = ask-bid;
   double nearDistance = TeacherAutoReversalDistance(atr);
   double penetration = MathMax(tickSize*2.0, nearDistance*0.50);
   double minWickRatio = ClampDouble(老师点位自动反转最小影线比例, 0.0, 0.95);
   double maxBodyRatio = ClampDouble(老师点位自动反转最大实体比例, 0.05, 0.95);
   double fiveDayHigh = 0.0, fiveDayLow = 0.0;
   if(!TeacherAutoGetFiveDayRange(fiveDayHigh, fiveDayLow))
   {
      PrintRateLimited("teacher_auto_d1_range_unavailable", 30,
                       "[老师自动短线] 跳过：最近5根已收盘D1数据不足或无效");
      return false;
   }
   MqlRates m5Rates[];
   ArraySetAsSeries(m5Rates, true);
   if(启用老师点位自动M5确认 && CopyRates(_Symbol, PERIOD_M5, 1, 2, m5Rates) < 2)
   {
      PrintRateLimited("teacher_auto_m5_unavailable", 30,
                       "[老师自动短线] 跳过：最近已收盘M5数据不足");
      return false;
   }
   if(lastRange <= tickSize || previousRange <= tickSize) return false;

   double bestDistance = DBL_MAX;
   for(int i=0; i<ArraySize(缓存老师点位); i++)
   {
      double teacherLevel = 缓存老师点位[i];
      if(teacherLevel <= 0.0) continue;

      double shortEntryDistance = MathAbs(bid-teacherLevel);
      bool previousBelow = rates[1].close < teacherLevel-tickSize*0.5;
      bool latestNearPressure = rates[0].high >= teacherLevel-nearDistance;
      bool noDeepPressureBreak = rates[0].high <= teacherLevel+penetration;
      bool closedBackBelow = rates[0].close < teacherLevel-tickSize*0.5;
      double upperWick = rates[0].high-MathMax(rates[0].open, rates[0].close);
      double body = MathAbs(rates[0].close-rates[0].open);
      bool pressureRejection = upperWick/lastRange >= minWickRatio;
      bool pressureSlowdown = body/lastRange <= maxBodyRatio || lastRange <= previousRange*0.95;
      bool bearishClose = rates[0].close <= rates[0].open || rates[0].close < rates[1].close;
      bool shortAtFiveDayEdge = TeacherAutoLevelAtFiveDayEdge(teacherLevel, true, fiveDayHigh, fiveDayLow);
      bool shortM5Confirmed = TeacherAutoM5ReversalConfirmed(teacherLevel, POSITION_TYPE_SELL, nearDistance, m5Rates);
      bool shortCandidate = shortAtFiveDayEdge && shortM5Confirmed && previousBelow && latestNearPressure && noDeepPressureBreak &&
                            closedBackBelow && pressureRejection && pressureSlowdown && bearishClose &&
                            shortEntryDistance <= nearDistance+spread;
      if(shortCandidate && shortEntryDistance < bestDistance)
      {
         bestDistance = shortEntryDistance;
         direction = POSITION_TYPE_SELL;
         level = teacherLevel;
         signalBarTime = rates[0].time;
      }

      double longEntryDistance = MathAbs(ask-teacherLevel);
      bool previousAbove = rates[1].close > teacherLevel+tickSize*0.5;
      bool latestNearSupport = rates[0].low <= teacherLevel+nearDistance;
      bool noDeepSupportBreak = rates[0].low >= teacherLevel-penetration;
      bool closedBackAbove = rates[0].close > teacherLevel+tickSize*0.5;
      double lowerWick = MathMin(rates[0].open, rates[0].close)-rates[0].low;
      bool supportRejection = lowerWick/lastRange >= minWickRatio;
      bool supportSlowdown = body/lastRange <= maxBodyRatio || lastRange <= previousRange*0.95;
      bool bullishClose = rates[0].close >= rates[0].open || rates[0].close > rates[1].close;
      bool longAtFiveDayEdge = TeacherAutoLevelAtFiveDayEdge(teacherLevel, false, fiveDayHigh, fiveDayLow);
      bool longM5Confirmed = TeacherAutoM5ReversalConfirmed(teacherLevel, POSITION_TYPE_BUY, nearDistance, m5Rates);
      bool longCandidate = longAtFiveDayEdge && longM5Confirmed && previousAbove && latestNearSupport && noDeepSupportBreak &&
                           closedBackAbove && supportRejection && supportSlowdown && bullishClose &&
                           longEntryDistance <= nearDistance+spread;
      if(longCandidate && longEntryDistance < bestDistance)
      {
         bestDistance = longEntryDistance;
         direction = POSITION_TYPE_BUY;
         level = teacherLevel;
         signalBarTime = rates[0].time;
      }
   }
   return direction == POSITION_TYPE_BUY || direction == POSITION_TYPE_SELL;
}

bool TeacherAutoDirectionAllowed(const int direction)
{
   if(direction == POSITION_TYPE_BUY && !管理多单) return false;
   if(direction == POSITION_TYPE_SELL && !管理空单) return false;
   ENUM_SYMBOL_TRADE_MODE mode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE);
   if(mode == SYMBOL_TRADE_MODE_DISABLED || mode == SYMBOL_TRADE_MODE_CLOSEONLY) return false;
   if(direction == POSITION_TYPE_BUY && mode == SYMBOL_TRADE_MODE_SHORTONLY) return false;
   if(direction == POSITION_TYPE_SELL && mode == SYMBOL_TRADE_MODE_LONGONLY) return false;
   return true;
}

void TeacherAutoConfirmEntryDeal(const ulong dealTicket, const ulong positionIdentifier)
{
   if(dealTicket == 0 || positionIdentifier == 0) return;
   if(teacherAutoEntryState.pendingMode>0)
   {
      if(!teacherAutoEntryState.pending) return;
      ulong order=(ulong)HistoryDealGetInteger(dealTicket,DEAL_ORDER);
      bool matched=teacherAutoEntryState.pendingOrder>0 ? order==teacherAutoEntryState.pendingOrder :
                   HistoryDealGetString(dealTicket,DEAL_COMMENT)==TeacherAutoPendingComment();
      if(!matched) return; // 其他旧仓/其他请求的Deal不能结束本次pending
      teacherAutoEntryState.pendingDeal=dealTicket;
      TeacherAutoStateSave();
      TeacherAutoConfirmLivePosition();
      return;
   }
   ulong ticket = FindOpenPositionTicketByIdentifier(positionIdentifier);
   if(ticket == 0 || !PositionSelectByTicket(ticket) ||
      (long)PositionGetInteger(POSITION_MAGIC) != TEACHER_AUTO_SHORT_MAGIC)
   {
      if(teacherAutoEntryState.pending)
      {
         teacherAutoEntryState.pendingDeal = dealTicket;
         TeacherAutoStateSave();
      }
      return;
   }
   TeacherAutoConfirmLivePosition();
}

bool SubmitTeacherAutoReversal(const int direction, const double level, const datetime signalBarTime,
                               const double atr, double volume, int activeMode=0, int levelIndex=-1,
                               datetime breakTime=0)
{
   if(direction != POSITION_TYPE_BUY && direction != POSITION_TYPE_SELL) return false;
   if(activeMode>0 && !TeacherActiveCanOpen()) return false; // 发送前再次核对容量与账户模式
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= bid) return false;
   double openPrice = direction == POSITION_TYPE_BUY ? ask : bid;
   double sl = 0.0, tp = 0.0;
   bool targetsReady=activeMode>0 ? TeacherActiveBuildOrder(direction,level,atr,activeMode,sl,tp,volume) :
                                  TeacherAutoBuildInitialSLTP((ENUM_POSITION_TYPE)direction,openPrice,atr,sl,tp);
   if(!targetsReady)
   {
      PrintRateLimited("teacher_auto_sltp_invalid", 10,
                      StringFormat("[老师自动短线] 跳过：初始SL/TP候选不合规 direction=%d level=%.5f", direction, level));
      return false;
   }

   if(activeMode>0)
   {
      if(levelIndex<0 || levelIndex>=ArraySize(缓存老师点位)) return false;
      GlobalVariableSet(TeacherAutoStateKey("AX"),(double)signalBarTime);
   }

   teacherAutoEntryState.pending = true;
   teacherAutoEntryState.pendingMode = activeMode;
   teacherAutoEntryState.pendingDirection = direction;
   teacherAutoEntryState.pendingLevel = level;
   teacherAutoEntryState.pendingVolume = volume;
   teacherAutoEntryState.pendingSignalBarTime = signalBarTime;
   teacherAutoEntryState.pendingRequestTime = TimeCurrent();
   teacherAutoEntryState.pendingOrder = 0;
   teacherAutoEntryState.pendingDeal = 0;
   teacherAutoEntryState.rearmRequired = false;
   teacherAutoEntryState.lastDirection = direction;
   teacherAutoEntryState.lastLevel = level;
   teacherAutoEntryState.lastEntryTime = teacherAutoEntryState.pendingRequestTime;
   // 先保存意图，再发送请求；若终端在请求返回前重启，重启对账仍会阻止重复开仓。
   TeacherAutoStateSave();

   teacherAutoTrade.SetExpertMagicNumber(TEACHER_AUTO_SHORT_MAGIC);
   teacherAutoTrade.SetDeviationInPoints(30);
   teacherAutoTrade.SetTypeFillingBySymbol(_Symbol);
   string comment = activeMode>0 ? TeacherAutoPendingComment() :
                                  TEACHER_AUTO_COMMENT_PREFIX + (direction == POSITION_TYPE_BUY ? "_BUY" : "_SELL");
   if(activeMode>0) GlobalVariablesFlush(); // 请求前落盘，重启不重复消耗同一信号
   bool sent = direction == POSITION_TYPE_BUY ? teacherAutoTrade.Buy(volume, _Symbol, 0.0, sl, tp, comment) :
                                                teacherAutoTrade.Sell(volume, _Symbol, 0.0, sl, tp, comment);
   uint retcode = teacherAutoTrade.ResultRetcode();
   if(!sent || !IsTradeRetcodeAccepted(retcode))
   {
      PrintFormat("[老师自动短线] 开仓请求失败 direction=%d level=%.5f volume=%.2f sl=%.5f tp=%.5f retcode=%u comment=%s",
                  direction, level, volume, sl, tp, retcode, teacherAutoTrade.ResultComment());
      if(activeMode>0 && (retcode==TRADE_RETCODE_TIMEOUT || retcode==TRADE_RETCODE_CONNECTION || retcode==TRADE_RETCODE_ERROR))
      {
         teacherAutoEntryState.pendingOrder=teacherAutoTrade.ResultOrder();
         teacherAutoEntryState.pendingDeal=teacherAutoTrade.ResultDeal();
         TeacherAutoStateSave();
         GlobalVariablesFlush();
         return false; // 结果不明仍占位；不能误当拒绝而补发
      }
      TeacherAutoClearPendingStateFields();
      teacherAutoEntryState.rearmRequired = false;
      TeacherAutoStateSave();
      return false;
   }

   teacherAutoEntryState.pendingOrder = teacherAutoTrade.ResultOrder();
   teacherAutoEntryState.pendingDeal = teacherAutoTrade.ResultDeal();
   if(activeMode>0)
      GlobalVariableSet(TeacherAutoStateKey("AT"+IntegerToString(levelIndex*2+direction)),(double)signalBarTime);
   teacherAutoEntryState.rearmRequired = true;
   TeacherAutoStateSave();
   teacherActiveHistoryDirty=true;
   PrintFormat("[老师自动短线] 已发送请求 direction=%d level=%.5f volume=%.2f sl=%.5f tp=%.5f order=%I64u deal=%I64u retcode=%u",
               direction, level, volume, sl, tp, teacherAutoEntryState.pendingOrder,
               teacherAutoEntryState.pendingDeal, retcode);
   return true;
}

void ManageTeacherAutoReversal()
{
   TeacherAutoReconcilePending();
   if(缓存老师点位原文 != 老师点位文本) RefreshTeacherMarkerCache();
   if(!启用老师点位自动反转短线 || !currentTickHasNewM1Bar) return;
   if(teacherAutoEntryState.pending) return;

   ulong liveTicket = 0;
   if(老师自动使用积极策略)
   {
      if(!TeacherActiveCanOpen()) return;
   }
   else
   {
      if(TeacherAutoFindLivePosition(liveTicket)) return;
      if(HasNonMarkerTradeOnCurrentSymbol()) return;
   }
   if(!缓存老师点位有效) return;
   if(!老师自动使用积极策略 && !TeacherAutoRearmReady()) return;

   datetime now = TimeCurrent();
   if(teacherAutoEntryState.lastEntryTime > 0 && now >= teacherAutoEntryState.lastEntryTime &&
      now-teacherAutoEntryState.lastEntryTime < MathMax(老师点位自动冷却秒, 0)) return;

   int direction = -1;
   double level = 0.0;
   datetime signalBarTime = 0;
   double atr = 0.0;
   GetATRPrice(atr);
   if(老师自动使用积极策略)
   {
      if(!TeacherActivePlanValid())
      { PrintRateLimited("teacher_active_expired",60,"[老师积极] 点位未生效或已过期，禁止新单"); return; }
      if((datetime)TeacherAutoStateRead("AD")!=TeacherActiveDay() ||
         !teacherActiveHistoryReady || teacherActiveHistoryDirty) return;
      double baseline=TeacherAutoStateRead("AE");
      if(baseline<=0 || TeacherAutoStateRead("AH")>0 ||
         AccountInfoDouble(ACCOUNT_EQUITY)<=baseline*(1.0-老师自动日内亏损上限百分比/100.0))
      {
         TeacherActiveHalt();
         PrintRateLimited("teacher_active_halt",60,"[老师积极] 日内风险停机，只管理已有仓位");
         return;
      }
      if(teacherActiveLastStop>0 && now-teacherActiveLastStop<老师自动止损冷却秒) return;
      int mode=0,index=-1;
      datetime breakout=0;
      if(!TeacherActiveFindCandidate(direction,level,signalBarTime,atr,mode,index,breakout)) return;
      if(signalBarTime<=(datetime)TeacherAutoStateRead("AX")) return;
      if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;
      PrintFormat("[老师积极] 候选 mode=%d(1顺势/2突破回踩/3逆势/4区间双向) bias=%d level=%.5f ATR_M5=%.5f",
                  mode,teacherActiveBias,level,atr);
      SubmitTeacherAutoReversal(direction,level,signalBarTime,atr,0.0,mode,index,breakout);
      return;
   }
   if(!TeacherAutoFindReversalCandidate(atr, direction, level, signalBarTime)) return;
   if(!TeacherAutoDirectionAllowed(direction)) return;

   double volume = 0.0;
   if(!TeacherAutoStrictFixedVolume(volume))
   {
      PrintRateLimited("teacher_auto_volume_invalid", 30,
                      StringFormat("[老师自动短线] 跳过：固定手数不符合品种规则 requested=%.4f min=%.4f max=%.4f step=%.4f",
                                   老师点位自动短线固定手数,
                                   SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN),
                                   SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX),
                                   SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP)));
      return;
   }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return;
   SubmitTeacherAutoReversal(direction, level, signalBarTime, atr, volume);
}

#endif
