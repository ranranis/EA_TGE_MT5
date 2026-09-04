#ifndef SMA_MARKET_SUPPORT_RESISTANCE_MQH
#define SMA_MARKET_SUPPORT_RESISTANCE_MQH

double SRZoneHalfWidth(double mergeDistance)
{
   double half = MathMax(mergeDistance * 0.5, 0.0);
   double atr = 0.0;
   if(GetATRPrice(atr) && atr > 0.0)
      half = MathMax(half, atr * 0.25);
   if(half <= 0.0)
      half = MathMax(_Point * 100, 0.10);
   return half;
}

int SRWeightToInt(double weight)
{
   if(!MathIsValidNumber(weight)) return 1;
   return MathMax(1, (int)MathRound(weight));
}

void AddOrMergeSRLevelEx(SRLevel &arr[],
                         double price,
                         datetime t,
                         double mergeDistance,
                         double weight,
                         bool isResistance,
                         bool isSupport,
                         int tfMask,
                         bool sessionLevel=false,
                         bool densityLevel=false,
                         bool liquiditySweep=false,
                         bool retestConfirmed=false,
                         double tradeScoreBonus=0.0,
                         bool boxBoundary=false,
                         bool integerConfluence=false,
                         bool effectiveReaction=false,
                         double maxReaction=0.0)
{
   if(price <= 0.0) return;
   if(mergeDistance <= 0.0) mergeDistance = _Point * 100;
   int w = SRWeightToInt(weight);
   double half = SRZoneHalfWidth(mergeDistance);
   double zoneLow = price - half;
   double zoneHigh = price + half;

   for(int i=0; i<ArraySize(arr); i++)
   {
      if(MathAbs(arr[i].price - price) <= mergeDistance)
      {
         // 同一区域内多次出现摆点/触碰，认为强度增加；价格用强度加权平均，减少线条抖动。
         int oldStrength = MathMax(arr[i].strength, 1);
         arr[i].price = (arr[i].price * oldStrength + price * w) / (oldStrength + w);
         arr[i].strength += w;
         arr[i].tradeScore += tradeScoreBonus;
         arr[i].touches++;
         arr[i].zoneLow = (arr[i].zoneLow > 0.0) ? MathMin(arr[i].zoneLow, zoneLow) : zoneLow;
         arr[i].zoneHigh = (arr[i].zoneHigh > 0.0) ? MathMax(arr[i].zoneHigh, zoneHigh) : zoneHigh;
         arr[i].tfMask |= tfMask;
         arr[i].isResistance = (arr[i].isResistance || isResistance);
         arr[i].isSupport = (arr[i].isSupport || isSupport);
         arr[i].sessionLevel = (arr[i].sessionLevel || sessionLevel);
         arr[i].densityLevel = (arr[i].densityLevel || densityLevel);
         arr[i].liquiditySweep = (arr[i].liquiditySweep || liquiditySweep);
         arr[i].sweepFailed = (arr[i].sweepFailed || liquiditySweep);
         arr[i].retestConfirmed = (arr[i].retestConfirmed || retestConfirmed);
         arr[i].boxBoundary = (arr[i].boxBoundary || boxBoundary);
         arr[i].integerConfluence = (arr[i].integerConfluence || integerConfluence);
         arr[i].effectiveReaction = (arr[i].effectiveReaction || effectiveReaction);
         arr[i].maxReaction = MathMax(arr[i].maxReaction, maxReaction);
         if(t > arr[i].lastTime) arr[i].lastTime = t;
         return;
      }
   }

   int n = ArraySize(arr);
   ArrayResize(arr, n + 1);
   arr[n].price = price;
   arr[n].zoneLow = zoneLow;
   arr[n].zoneHigh = zoneHigh;
   arr[n].strength = w;
   arr[n].tradeScore = tradeScoreBonus;
   arr[n].qualityGrade = 0;
   arr[n].touches = 1;
   arr[n].tfMask = tfMask;
   arr[n].isResistance = isResistance;
   arr[n].isSupport = isSupport;
   arr[n].tradable = false;
   arr[n].observeOnly = true;
   arr[n].boxBoundary = boxBoundary;
   arr[n].brokenConfirmed = false;
   arr[n].retestConfirmed = retestConfirmed;
   arr[n].liquiditySweep = liquiditySweep;
   arr[n].sweepFailed = liquiditySweep;
   arr[n].effectiveReaction = effectiveReaction;
   arr[n].maxReaction = MathMax(0.0, maxReaction);
   arr[n].sessionLevel = sessionLevel;
   arr[n].densityLevel = densityLevel;
   arr[n].integerConfluence = integerConfluence;
   arr[n].statusText = "观察";
   arr[n].lastTime = t;
}

void AddOrMergeSRLevelWeighted(SRLevel &arr[], double price, datetime t, double mergeDistance, int weight)
{
   AddOrMergeSRLevelEx(arr, price, t, mergeDistance, weight, false, false, 0);
}

void AddOrMergeSRLevel(SRLevel &arr[], double price, datetime t, double mergeDistance)
{
   AddOrMergeSRLevelWeighted(arr, price, t, mergeDistance, 1);
}

void StrengthenNearbySRLevel(SRLevel &arr[], double price, datetime t, double mergeDistance, int weight)
{
   if(price <= 0.0 || ArraySize(arr) <= 0) return;
   int w = MathMax(weight, 1);
   for(int i=0; i<ArraySize(arr); i++)
   {
      if(MathAbs(arr[i].price - price) <= mergeDistance)
      {
         // 只强化已有结构区，不把每一根普通K线都新增成支撑压力。
         int oldStrength = MathMax(arr[i].strength, 1);
         arr[i].price = (arr[i].price * oldStrength + price * w) / (oldStrength + w);
         arr[i].strength += w;
         arr[i].touches++;
         double half = SRZoneHalfWidth(mergeDistance);
         arr[i].zoneLow = (arr[i].zoneLow > 0.0) ? MathMin(arr[i].zoneLow, price - half) : price - half;
         arr[i].zoneHigh = (arr[i].zoneHigh > 0.0) ? MathMax(arr[i].zoneHigh, price + half) : price + half;
         if(t > arr[i].lastTime) arr[i].lastTime = t;
         return;
      }
   }
}

int RecentSRWeight(int barIndex, int baseWeight)
{
   int base = MathMax(baseWeight, 1);
   int recentBars = MathMax(支撑压力近端加权K线数, 0);
   if(recentBars <= 0 || barIndex <= 0)
      return base;

   double maxMult = MathMax(支撑压力近端最大权重倍数, 1.0);
   double alpha = 2.0 / ((double)recentBars + 1.0);
   double decay = MathPow(1.0 - alpha, barIndex - 1);
   double mult = 1.0 + (maxMult - 1.0) * decay;
   return MathMax(base, (int)MathRound(base * mult));
}

double DistanceToRoundStep(double price, double step)
{
   if(price <= 0.0 || step <= 0.0) return DBL_MAX;
   double nearest = MathRound(price / step) * step;
   return MathAbs(price - nearest);
}

int SRRoundLevelBonus(double price)
{
   if(!支撑压力启用整数位加权 || price <= 0.0) return 0;
   double tol = MathMax(支撑压力整数位容差价格, 0.0);
   if(tol <= 0.0) return 0;

   if(支撑压力启用大整数分层权重)
   {
      if(DistanceToRoundStep(price, 100.0) <= tol) return 8;
      if(DistanceToRoundStep(price, 50.0) <= tol) return 6;
      if(DistanceToRoundStep(price, 10.0) <= tol) return 4;
      if(DistanceToRoundStep(price, 5.0) <= tol) return 2;
      if(DistanceToRoundStep(price, 1.0) <= tol) return 1;
      return 0;
   }

   double d1 = DistanceToRoundStep(price, 1.0);
   double d5 = DistanceToRoundStep(price, 5.0);
   double d10 = DistanceToRoundStep(price, 10.0);
   if(d1 <= tol || d5 <= tol || d10 <= tol)
      return 2;
   return 0;
}

int SRReactionLookAhead(ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_M5) return MathMax(支撑压力反应观察K线数_M5, 1);
   if(tf == PERIOD_M15) return MathMax(支撑压力反应观察K线数_M15, 1);
   return MathMax(支撑压力反应观察K线数_M1, 1);
}

int SRTFMask(ENUM_TIMEFRAMES tf)
{
   if(tf == PERIOD_M5) return SR_TF_M5;
   if(tf == PERIOD_M15) return SR_TF_M15;
   return SR_TF_M1;
}

double CalcReactionForResistance(MqlRates &rates[], int index, int lookAhead)
{
   if(index <= 0 || lookAhead <= 0) return 0.0;
   int end = MathMax(index - lookAhead, 0);
   double low = DBL_MAX;
   for(int i=index - 1; i>=end; i--)
      low = MathMin(low, rates[i].low);
   if(low == DBL_MAX) return 0.0;
   return MathMax(0.0, rates[index].high - low);
}

double CalcReactionForSupport(MqlRates &rates[], int index, int lookAhead)
{
   if(index <= 0 || lookAhead <= 0) return 0.0;
   int end = MathMax(index - lookAhead, 0);
   double high = -DBL_MAX;
   for(int i=index - 1; i>=end; i--)
      high = MathMax(high, rates[i].high);
   if(high == -DBL_MAX) return 0.0;
   return MathMax(0.0, high - rates[index].low);
}

int SRReactionBonus(double reaction)
{
   if(!支撑压力启用有效反应过滤) return 0;
   if(reaction >= 支撑压力关键反应价格) return 9;
   if(reaction >= 支撑压力强反应价格) return 6;
   if(reaction >= 支撑压力最小有效反应价格) return 3;
   return 0;
}

int SRRecentReactionBonus(datetime barTime)
{
   if(!支撑压力启用近60分钟反应加权 || barTime <= 0) return 0;
   int minutes = MathMax(支撑压力近反应分钟, 0);
   if(minutes <= 0) return 0;
   datetime now = TimeCurrent();
   if(now >= barTime && now - barTime <= minutes * 60)
      return 2;
   return 0;
}

int SRCandidateWeight(int barIndex, int baseWeight, bool swingPoint, double price, datetime barTime)
{
   int w = RecentSRWeight(barIndex, MathMax(baseWeight, 1));
   if(swingPoint)
      w *= 2;
   w += SRRoundLevelBonus(price);
   w += SRRecentReactionBonus(barTime);
   return MathMax(w, 1);
}

bool IsSwingHigh(MqlRates &rates[], int index, int strength)
{
   for(int j=1; j<=strength; j++)
   {
      if(rates[index].high <= rates[index-j].high || rates[index].high <= rates[index+j].high)
         return false;
   }
   return true;
}

bool IsSwingLow(MqlRates &rates[], int index, int strength)
{
   for(int j=1; j<=strength; j++)
   {
      if(rates[index].low >= rates[index-j].low || rates[index].low >= rates[index+j].low)
         return false;
   }
   return true;
}

void ApplyBreakRetestBonus(SRLevel &arr[], bool resistance, MqlRates &rates[], int copied, double mergeDistance)
{
   if(!支撑压力启用突破回踩确认) return;
   if(ArraySize(arr) <= 0 || copied <= 2 || mergeDistance <= 0.0) return;

   int recentBars = MathMin(copied - 1, MathMax(突破回踩观察K线数, 1));
   for(int lv=0; lv<ArraySize(arr); lv++)
   {
      if(arr[lv].retestConfirmed) continue;
      double lowEdge = (arr[lv].zoneLow > 0.0) ? arr[lv].zoneLow : arr[lv].price - mergeDistance * 0.5;
      double highEdge = (arr[lv].zoneHigh > 0.0) ? arr[lv].zoneHigh : arr[lv].price + mergeDistance * 0.5;

      for(int i=1; i<=recentBars; i++)
      {
         bool retest = false;
         if(resistance)
         {
            // 旧支撑跌破后反抽不过，强化为压力的预留判断。
            retest = (rates[i].high >= lowEdge && rates[i].low <= highEdge &&
                      rates[i].close < highEdge);
         }
         else
         {
            // 旧压力突破后回踩不破，强化为支撑的预留判断。
            retest = (rates[i].high >= lowEdge && rates[i].low <= highEdge &&
                      rates[i].close > lowEdge);
         }

         if(retest)
         {
            arr[lv].strength += SRWeightToInt(突破回踩加分);
            arr[lv].touches++;
            arr[lv].retestConfirmed = true;
            if(rates[i].time > arr[lv].lastTime) arr[lv].lastTime = rates[i].time;
            break;
         }
      }
   }
}

void ScanSRTimeframe(ENUM_TIMEFRAMES tf,
                     int lookback,
                     int swingStrength,
                     int weight,
                     double mergeDistance,
                     SRLevel &allRes[],
                     SRLevel &allSup[])
{
   int strength = MathMax(swingStrength, 1);
   int barsNeed = MathMax(lookback, strength * 2 + 30);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 1, barsNeed, rates);
   if(copied <= strength * 2 + 5) return;

   int w = MathMax(weight, 1);
   int tfMask = SRTFMask(tf);
   int reactionBars = SRReactionLookAhead(tf);

   // 1）摆点建区：候选点来自M1/M5/M15的swing high/low，不再让每根普通K线单独制造R/S。
   int createdBeforeRes = ArraySize(allRes);
   int createdBeforeSup = ArraySize(allSup);
   for(int i=strength; i<copied - strength; i++)
   {
      bool swingHigh = IsSwingHigh(rates, i, strength);
      bool swingLow = IsSwingLow(rates, i, strength);
      if(swingHigh)
      {
         double reaction = CalcReactionForResistance(rates, i, reactionBars);
         int reactionBonus = SRReactionBonus(reaction);
         int swingWeight = SRCandidateWeight(i + 1, w, true, rates[i].high, rates[i].time) + reactionBonus;
         if(支撑压力启用有效反应过滤 && tf == PERIOD_M1 && reaction < 支撑压力最小有效反应价格)
            swingWeight = MathMax(1, swingWeight / 2);
         double tradeBonus = reactionBonus;
         if(tf == PERIOD_M5) tradeBonus += 4;
         if(tf == PERIOD_M15) tradeBonus += 6;
         if(SRRoundLevelBonus(rates[i].high) > 0) tradeBonus += SRRoundLevelBonus(rates[i].high);
         bool effective = (reaction >= 支撑压力最小有效反应价格);
         AddOrMergeSRLevelEx(allRes, rates[i].high, rates[i].time, mergeDistance, swingWeight, true, false, tfMask, false, false, false, false, tradeBonus, false, SRRoundLevelBonus(rates[i].high) > 0, effective, reaction);
      }
      if(swingLow)
      {
         double reaction = CalcReactionForSupport(rates, i, reactionBars);
         int reactionBonus = SRReactionBonus(reaction);
         int swingWeight = SRCandidateWeight(i + 1, w, true, rates[i].low, rates[i].time) + reactionBonus;
         if(支撑压力启用有效反应过滤 && tf == PERIOD_M1 && reaction < 支撑压力最小有效反应价格)
            swingWeight = MathMax(1, swingWeight / 2);
         double tradeBonus = reactionBonus;
         if(tf == PERIOD_M5) tradeBonus += 4;
         if(tf == PERIOD_M15) tradeBonus += 6;
         if(SRRoundLevelBonus(rates[i].low) > 0) tradeBonus += SRRoundLevelBonus(rates[i].low);
         bool effective = (reaction >= 支撑压力最小有效反应价格);
         AddOrMergeSRLevelEx(allSup, rates[i].low, rates[i].time, mergeDistance, swingWeight, false, true, tfMask, false, false, false, false, tradeBonus, false, SRRoundLevelBonus(rates[i].low) > 0, effective, reaction);
      }
   }

   // 极端单边行情可能没有标准摆点，保留最近区间高低点作为弱 fallback，避免面板完全断档。
   if(ArraySize(allRes) == createdBeforeRes || ArraySize(allSup) == createdBeforeSup)
   {
      int highIndex = -1;
      int lowIndex = -1;
      double highPrice = -DBL_MAX;
      double lowPrice = DBL_MAX;
      for(int i=0; i<copied; i++)
      {
         if(rates[i].high > highPrice)
         {
            highPrice = rates[i].high;
            highIndex = i;
         }
         if(rates[i].low < lowPrice)
         {
            lowPrice = rates[i].low;
            lowIndex = i;
         }
      }
      if(ArraySize(allRes) == createdBeforeRes && highIndex >= 0)
         AddOrMergeSRLevelEx(allRes, highPrice, rates[highIndex].time, mergeDistance, SRCandidateWeight(highIndex + 1, w, false, highPrice, rates[highIndex].time), true, false, tfMask);
      if(ArraySize(allSup) == createdBeforeSup && lowIndex >= 0)
         AddOrMergeSRLevelEx(allSup, lowPrice, rates[lowIndex].time, mergeDistance, SRCandidateWeight(lowIndex + 1, w, false, lowPrice, rates[lowIndex].time), false, true, tfMask);
   }

   // 2）触碰强化：高低点密集区只给已有区域加分，不再单独造噪声线。
   if(支撑压力启用触碰强化)
   {
      int touchWeight = MathMax(1, w);
      for(int i=0; i<copied; i++)
      {
         int barTouchWeight = RecentSRWeight(i + 1, touchWeight);
         StrengthenNearbySRLevel(allRes, rates[i].high, rates[i].time, mergeDistance, barTouchWeight);
         StrengthenNearbySRLevel(allSup, rates[i].low,  rates[i].time, mergeDistance, barTouchWeight);
      }
   }

   // 3）突破后回踩/反抽不过的预留强化，先做轻量确认，不改变任何交易动作。
   ApplyBreakRetestBonus(allRes, true, rates, copied, mergeDistance);
   ApplyBreakRetestBonus(allSup, false, rates, copied, mergeDistance);
}

datetime SRServerDayStart(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

bool SRRangeHighLow(datetime startTime, datetime endTime, double &hi, double &lo)
{
   hi = -DBL_MAX;
   lo = DBL_MAX;
   if(endTime <= startTime) return false;

   MqlRates rates[];
   int copied = CopyRates(_Symbol, PERIOD_M1, startTime, endTime, rates);
   if(copied <= 0) return false;

   for(int i=0; i<copied; i++)
   {
      hi = MathMax(hi, rates[i].high);
      lo = MathMin(lo, rates[i].low);
   }
   return (hi > 0.0 && lo < DBL_MAX);
}

void AddSessionLevel(SRLevel &allRes[], SRLevel &allSup[], double price, datetime t, double mergeDistance, double weight, bool asResistance, bool asSupport)
{
   int roundBonus = SRRoundLevelBonus(price);
   int w = SRWeightToInt(weight + roundBonus);
   double tradeBonus = weight * 0.8 + roundBonus;
   if(asResistance)
      AddOrMergeSRLevelEx(allRes, price, t, mergeDistance, w, true, false, SR_SRC_SESSION, true, false, false, false, tradeBonus, false, roundBonus > 0);
   if(asSupport)
      AddOrMergeSRLevelEx(allSup, price, t, mergeDistance, w, false, true, SR_SRC_SESSION, true, false, false, false, tradeBonus, false, roundBonus > 0);
}

void AddDailyAndSessionLevels(SRLevel &allRes[], SRLevel &allSup[], double mergeDistance)
{
   if(!支撑压力启用时段关键位) return;

   datetime now = TimeCurrent();
   datetime today0 = SRServerDayStart(now);
   datetime yesterday0 = today0 - 86400;

   double hi, lo;
   if(SRRangeHighLow(yesterday0, today0, hi, lo))
   {
      AddSessionLevel(allRes, allSup, hi, yesterday0, mergeDistance, 8, true, false);
      AddSessionLevel(allRes, allSup, lo, yesterday0, mergeDistance, 8, false, true);
   }

   if(SRRangeHighLow(today0, now, hi, lo))
   {
      AddSessionLevel(allRes, allSup, hi, today0, mergeDistance, 6, true, false);
      AddSessionLevel(allRes, allSup, lo, today0, mergeDistance, 6, false, true);
   }

   double todayOpen = iOpen(_Symbol, PERIOD_D1, 0);
   if(todayOpen > 0.0)
      AddSessionLevel(allRes, allSup, todayOpen, today0, mergeDistance, 4, true, true);

   datetime asiaStart = today0 + MathMax(0, MathMin(23, 亚洲盘开始小时)) * 3600;
   datetime asiaEnd = today0 + MathMax(0, MathMin(24, 亚洲盘结束小时)) * 3600;
   if(asiaEnd > asiaStart && SRRangeHighLow(asiaStart, MathMin(asiaEnd, now), hi, lo))
   {
      AddSessionLevel(allRes, allSup, hi, asiaStart, mergeDistance, 5, true, false);
      AddSessionLevel(allRes, allSup, lo, asiaStart, mergeDistance, 5, false, true);
   }

   datetime londonStart = today0 + MathMax(0, MathMin(23, 伦敦盘开始小时)) * 3600;
   datetime londonEnd = londonStart + MathMax(1, 伦敦盘开盘区间分钟) * 60;
   if(now >= londonStart && SRRangeHighLow(londonStart, MathMin(londonEnd, now), hi, lo))
   {
      AddSessionLevel(allRes, allSup, hi, londonStart, mergeDistance, 5, true, false);
      AddSessionLevel(allRes, allSup, lo, londonStart, mergeDistance, 5, false, true);
   }

   datetime nyStart = today0 + MathMax(0, MathMin(23, 纽约盘开始小时)) * 3600;
   datetime nyEnd = nyStart + MathMax(1, 纽约盘开盘区间分钟) * 60;
   if(now >= nyStart && SRRangeHighLow(nyStart, MathMin(nyEnd, now), hi, lo))
   {
      AddSessionLevel(allRes, allSup, hi, nyStart, mergeDistance, 5, true, false);
      AddSessionLevel(allRes, allSup, lo, nyStart, mergeDistance, 5, false, true);
   }
}

void AddDensityLevelsByM1PriceBuckets(SRLevel &allRes[], SRLevel &allSup[], double mergeDistance)
{
   if(!支撑压力启用价格密集区) return;

   int lookback = MathMin(MathMax(价格密集区回看M1根数, 30), 240);
   double bucketSize = MathMax(价格密集区分桶大小, 0.10);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, lookback, rates);
   if(copied <= 0) return;

   double buckets[];
   int counts[];
   for(int i=0; i<copied; i++)
   {
      int fromBucket = (int)MathFloor(rates[i].low / bucketSize);
      int toBucket = (int)MathFloor(rates[i].high / bucketSize);
      if(toBucket < fromBucket) continue;

      for(int b=fromBucket; b<=toBucket; b++)
      {
         double center = (b + 0.5) * bucketSize;
         int idx = -1;
         for(int k=0; k<ArraySize(buckets); k++)
         {
            if(MathAbs(buckets[k] - center) < bucketSize * 0.1)
            {
               idx = k;
               break;
            }
         }
         if(idx < 0)
         {
            int n = ArraySize(buckets);
            ArrayResize(buckets, n + 1);
            ArrayResize(counts, n + 1);
            buckets[n] = center;
            counts[n] = 1;
         }
         else
         {
            counts[idx]++;
         }
      }
   }

   int maxCandidates = MathMin(MathMax(价格密集区最多候选数, 1), 10);
   for(int pick=0; pick<maxCandidates; pick++)
   {
      int best = -1;
      int bestCount = MathMax(价格密集区最小覆盖次数, 1) - 1;
      for(int i=0; i<ArraySize(buckets); i++)
      {
         if(counts[i] > bestCount)
         {
            best = i;
            bestCount = counts[i];
         }
      }
      if(best < 0) break;

      double w = 价格密集区基础加分 + MathMin(bestCount / 10.0, 5.0) + SRRoundLevelBonus(buckets[best]);
      AddOrMergeSRLevelEx(allRes, buckets[best], rates[0].time, mergeDistance, w, true, false, SR_SRC_DENSITY, false, true, false, false, w * 0.4, false, SRRoundLevelBonus(buckets[best]) > 0);
      AddOrMergeSRLevelEx(allSup, buckets[best], rates[0].time, mergeDistance, w, false, true, SR_SRC_DENSITY, false, true, false, false, w * 0.4, false, SRRoundLevelBonus(buckets[best]) > 0);
      counts[best] = -1;
   }
}

void AddRangeBoxBoundaries(SRLevel &allRes[], SRLevel &allSup[], double mergeDistance)
{
   int lookback = MathMin(MathMax(支撑压力回看K线数, 60), 120);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, lookback, rates);
   if(copied < 40) return;

   double hi = -DBL_MAX;
   double lo = DBL_MAX;
   for(int i=0; i<copied; i++)
   {
      hi = MathMax(hi, rates[i].high);
      lo = MathMin(lo, rates[i].low);
   }
   if(hi <= lo) return;

   double atr = 0.0;
   if(!GetATRPrice(atr) || atr <= 0.0) atr = MathMax(支撑压力合并距离价格, 1.0);
   double boxHeight = hi - lo;
   if(boxHeight < atr * 2.0 || boxHeight > atr * 10.0) return;

   int trend = DetectTrendRegimeM5();
   if(trend != 0) return;

   double topZone = MathMax(mergeDistance, atr * 0.35);
   double bottomZone = topZone;
   int topTouches = 0;
   int bottomTouches = 0;
   int middleCrosses = 0;
   double mid = (hi + lo) / 2.0;
   bool lastAboveMid = (rates[copied-1].close > mid);

   for(int i=copied-2; i>=0; i--)
   {
      if(hi - rates[i].high <= topZone)
         topTouches++;
      if(rates[i].low - lo <= bottomZone)
         bottomTouches++;
      bool aboveMid = (rates[i].close > mid);
      if(aboveMid != lastAboveMid)
      {
         middleCrosses++;
         lastAboveMid = aboveMid;
      }
   }

   if(topTouches < 2 || bottomTouches < 2 || middleCrosses < 2) return;

   double topScore = 18.0 + (topTouches >= 3 ? 7.0 : 4.0);
   double bottomScore = 18.0 + (bottomTouches >= 3 ? 7.0 : 4.0);
   AddOrMergeSRLevelEx(allRes, hi, rates[0].time, mergeDistance, SRWeightToInt(topScore), true, false, SR_TF_M1,
                       false, false, false, false, topScore, true, SRRoundLevelBonus(hi) > 0, true, boxHeight);
   AddOrMergeSRLevelEx(allSup, lo, rates[0].time, mergeDistance, SRWeightToInt(bottomScore), false, true, SR_TF_M1,
                       false, false, false, false, bottomScore, true, SRRoundLevelBonus(lo) > 0, true, boxHeight);
}

bool IsSRHighVolatilityMode()
{
   if(!支撑压力启用高波动保护) return false;

   double atr = 0.0;
   if(!GetATRPrice(atr) || atr <= 0.0) return false;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, 3, rates);
   if(copied < 3) return false;

   double body = MathAbs(rates[0].close - rates[0].open);
   double totalRange = 0.0;
   for(int i=0; i<3; i++)
      totalRange += MathMax(0.0, rates[i].high - rates[i].low);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   bool spreadWide = false;
   if(bid > 0.0 && ask > 0.0 && !忽略点差过滤)
      spreadWide = ((ask - bid) / _Point > 最大点差点数);

   return (body > atr * MathMax(高波动M1实体ATR倍数, 0.1) ||
           totalRange > atr * MathMax(高波动3根M1总波动ATR倍数, 0.1) ||
           spreadWide);
}

bool HasM1ReactionAtLevel(const SRLevel &lv, bool resistance)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, 4, rates);
   if(copied < 2) return false;

   double lowEdge = (lv.zoneLow > 0.0) ? lv.zoneLow : lv.price;
   double highEdge = (lv.zoneHigh > 0.0) ? lv.zoneHigh : lv.price;
   for(int i=0; i<MathMin(copied, 3); i++)
   {
      double body = MathAbs(rates[i].close - rates[i].open);
      double upperWick = rates[i].high - MathMax(rates[i].open, rates[i].close);
      double lowerWick = MathMin(rates[i].open, rates[i].close) - rates[i].low;
      bool touched = (rates[i].high >= lowEdge && rates[i].low <= highEdge);

      if(resistance)
      {
         bool bearishReject = touched && rates[i].close < highEdge && (upperWick >= body * 1.2 || rates[i].close < rates[i].open);
         bool bearishEngulf = (i + 1 < copied && rates[i].close < rates[i].open && rates[i].open >= rates[i+1].close && rates[i].close <= rates[i+1].open);
         if(bearishReject || bearishEngulf) return true;
      }
      else
      {
         bool bullishReject = touched && rates[i].close > lowEdge && (lowerWick >= body * 1.2 || rates[i].close > rates[i].open);
         bool bullishEngulf = (i + 1 < copied && rates[i].close > rates[i].open && rates[i].open <= rates[i+1].close && rates[i].close >= rates[i+1].open);
         if(bullishReject || bullishEngulf) return true;
      }
   }
   return false;
}

string SRGradeText(int grade)
{
   if(grade >= 3) return "A";
   if(grade == 2) return "B";
   if(grade == 1) return "C";
   return "D";
}

string SRActionText(const SRLevel &lv, bool resistance, bool compact=false)
{
   if(!支撑压力启用最终增强版)
      return "结构参考";

   if(lv.statusText == "高波动观察")
      return compact ? "仅观察" : "高波动，仅观察";
   if(lv.statusText == "等空确认")
      return compact ? "等空" : "到位，等空确认";
   if(lv.statusText == "等多确认")
      return compact ? "等多" : "到位，等多确认";
   if(lv.statusText == "空头反应")
      return compact ? "空反" : "已有空头反应";
   if(lv.statusText == "多头反应")
      return compact ? "多反" : "已有多头反应";

   if(lv.tradable)
      return compact ? (resistance ? "可空" : "可多") : (resistance ? "建议等空" : "建议等多");

   if(lv.qualityGrade >= 1 || lv.sessionLevel || lv.densityLevel || lv.integerConfluence)
      return compact ? "观察" : "仅观察，不建议直接下单";

   return compact ? "不做" : "暂不建议下单";
}

void ClassifySRTradingIntent(SRLevel &arr[], bool resistance, double refPrice, int trendRegime, bool highVol)
{
   double atr = 0.0;
   if(!GetATRPrice(atr) || atr <= 0.0) atr = MathMax(支撑压力合并距离价格, 1.0);

   for(int i=0; i<ArraySize(arr); i++)
   {
      double score = arr[i].tradeScore;
      score += arr[i].strength * 0.20;
      if(arr[i].boxBoundary) score += 10.0;
      if(arr[i].sweepFailed || arr[i].liquiditySweep) score += 10.0;
      if(arr[i].retestConfirmed) score += 4.0;
      if((arr[i].tfMask & SR_TF_M5) != 0) score += 4.0;
      if((arr[i].tfMask & SR_TF_M15) != 0) score += 6.0;
      if(arr[i].sessionLevel) score += 4.0;
      if(arr[i].integerConfluence) score += MathMin((double)SRRoundLevelBonus(arr[i].price), 6.0);

      double distance = MathAbs(arr[i].price - refPrice);
      if(distance > atr * 8.0)
         score -= 5.0;
      if(distance > 支撑压力最大交易显示距离价格)
         score -= 8.0;

      bool trendAgainst = (resistance && trendRegime > 0) || (!resistance && trendRegime < 0);
      if(trendAgainst && !arr[i].sweepFailed && !arr[i].boxBoundary)
         score -= 8.0;

      if(highVol)
         score -= 10.0;

      arr[i].tradeScore = score;
      arr[i].qualityGrade = (score >= 支撑压力A级线最低分) ? 3 : (score >= 支撑压力B级线最低分 ? 2 : (score >= 支撑压力可交易线最低分 ? 1 : 0));
      bool multiTF = ((arr[i].tfMask & SR_TF_M5) != 0 || (arr[i].tfMask & SR_TF_M15) != 0);
      bool hardQualified =
         arr[i].boxBoundary ||
         arr[i].sweepFailed ||
         arr[i].liquiditySweep ||
         (arr[i].effectiveReaction && arr[i].maxReaction >= 支撑压力最小有效反应价格) ||
         (multiTF && arr[i].effectiveReaction && arr[i].maxReaction >= 3.0) ||
         (arr[i].sessionLevel && arr[i].effectiveReaction) ||
         (arr[i].integerConfluence && (arr[i].boxBoundary || arr[i].sweepFailed || arr[i].effectiveReaction || arr[i].sessionLevel || multiTF)) ||
         (score >= 支撑压力A级线最低分 + 6.0 && arr[i].touches >= 3);

      if(distance > 支撑压力最大交易显示距离价格 || distance > atr * 8.0)
         hardQualified = false;

      arr[i].tradable = (arr[i].qualityGrade >= 1 && hardQualified && !highVol);
      arr[i].observeOnly = !arr[i].tradable;

      if(highVol)
      {
         arr[i].statusText = "高波动观察";
         continue;
      }

      if(!arr[i].tradable)
      {
         arr[i].statusText = "仅观察";
         continue;
      }

      if(支撑压力启用到位提示 && distance <= 支撑压力接近距离价格)
      {
         if(HasM1ReactionAtLevel(arr[i], resistance))
            arr[i].statusText = resistance ? "空头反应" : "多头反应";
         else
            arr[i].statusText = resistance ? "等空确认" : "等多确认";
      }
      else
      {
         arr[i].statusText = resistance ? "建议等空" : "建议等多";
      }
   }
}

void DetectLiquiditySweeps(SRLevel &arr[], bool resistance)
{
   if(!支撑压力启用扫单失败识别 || ArraySize(arr) <= 0) return;

   int confirmBars = MathMax(扫单确认K线数, 1);
   int barsNeed = MathMax(confirmBars + 8, 20);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, barsNeed, rates);
   if(copied <= confirmBars + 1) return;

   for(int lv=0; lv<ArraySize(arr); lv++)
   {
      if(arr[lv].liquiditySweep) continue;
      double lowEdge = (arr[lv].zoneLow > 0.0) ? arr[lv].zoneLow : arr[lv].price;
      double highEdge = (arr[lv].zoneHigh > 0.0) ? arr[lv].zoneHigh : arr[lv].price;

      for(int i=confirmBars; i<copied; i++)
      {
         double pierce = 0.0;
         bool swept = false;
         if(resistance)
         {
            pierce = rates[i].high - highEdge;
            if(pierce >= 扫单最小刺破价格 && pierce <= 扫单最大刺破价格)
            {
               for(int j=i-1; j>=MathMax(0, i-confirmBars); j--)
               {
                  if(rates[j].close < highEdge)
                  {
                     swept = true;
                     break;
                  }
               }
            }
         }
         else
         {
            pierce = lowEdge - rates[i].low;
            if(pierce >= 扫单最小刺破价格 && pierce <= 扫单最大刺破价格)
            {
               for(int j=i-1; j>=MathMax(0, i-confirmBars); j--)
               {
                  if(rates[j].close > lowEdge)
                  {
                     swept = true;
                     break;
                  }
               }
            }
         }

         if(swept)
         {
            arr[lv].strength += SRWeightToInt(扫单失败加分);
            arr[lv].tradeScore += 扫单失败加分;
            arr[lv].liquiditySweep = true;
            arr[lv].sweepFailed = true;
            arr[lv].effectiveReaction = true;
            arr[lv].maxReaction = MathMax(arr[lv].maxReaction, pierce);
            arr[lv].touches++;
            if(rates[0].time > arr[lv].lastTime) arr[lv].lastTime = rates[0].time;
            break;
         }
      }
   }
}

int DetectTrendRegimeM5()
{
   if(!支撑压力启用趋势环境过滤) return 0;

   int fastHandle = iMA(_Symbol, PERIOD_M5, MathMax(趋势EMA快线周期, 1), 0, MODE_EMA, PRICE_CLOSE);
   int slowHandle = iMA(_Symbol, PERIOD_M5, MathMax(趋势EMA慢线周期, 1), 0, MODE_EMA, PRICE_CLOSE);
   int adxHandleLocal = iADX(_Symbol, PERIOD_M5, MathMax(趋势ADX周期, 1));
   if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE || adxHandleLocal == INVALID_HANDLE)
   {
      if(fastHandle != INVALID_HANDLE) IndicatorRelease(fastHandle);
      if(slowHandle != INVALID_HANDLE) IndicatorRelease(slowHandle);
      if(adxHandleLocal != INVALID_HANDLE) IndicatorRelease(adxHandleLocal);
      return 0;
   }

   double fast[], slow[], adx[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(adx, true);
   bool ok = (CopyBuffer(fastHandle, 0, 1, 1, fast) == 1 &&
              CopyBuffer(slowHandle, 0, 1, 1, slow) == 1 &&
              CopyBuffer(adxHandleLocal, 0, 1, 1, adx) == 1);
   IndicatorRelease(fastHandle);
   IndicatorRelease(slowHandle);
   IndicatorRelease(adxHandleLocal);
   if(!ok) return 0;
   if(adx[0] <= 趋势ADX阈值) return 0;
   if(fast[0] > slow[0]) return 1;
   if(fast[0] < slow[0]) return -1;
   return 0;
}

void ApplyTrendWeightToSRLevels(SRLevel &allRes[], SRLevel &allSup[], int trendRegime, double refPrice)
{
   if(trendRegime == 0) return;
   double trendMult = MathMax(顺势点位加权倍数, 0.10);
   double contraMult = MathMax(逆势点位降权倍数, 0.10);

   for(int i=0; i<ArraySize(allRes); i++)
   {
      double mult = (trendRegime < 0 && allRes[i].price > refPrice) ? trendMult : contraMult;
      allRes[i].strength = MathMax(1, (int)MathRound(allRes[i].strength * mult));
   }
   for(int i=0; i<ArraySize(allSup); i++)
   {
      double mult = (trendRegime > 0 && allSup[i].price < refPrice) ? trendMult : contraMult;
      allSup[i].strength = MathMax(1, (int)MathRound(allSup[i].strength * mult));
   }
}

void ApplyExpiryPenalty(SRLevel &arr[])
{
   if(!支撑压力启用过期惩罚) return;
   int expireSec = MathMax(支撑压力过期分钟, 1) * 60;
   double mult = MathMax(MathMin(支撑压力过期降权倍数, 1.0), 0.10);
   datetime now = TimeCurrent();

   for(int i=0; i<ArraySize(arr); i++)
   {
      bool protectedLevel = arr[i].sessionLevel || arr[i].densityLevel || ((arr[i].tfMask & SR_TF_M15) != 0);
      if(protectedLevel || arr[i].lastTime <= 0) continue;
      if(now - arr[i].lastTime > expireSec)
         arr[i].strength = MathMax(1, (int)MathRound(arr[i].strength * mult));
   }
}

void DetectBreakoutRetests(SRLevel &allRes[], SRLevel &allSup[], double mergeDistance)
{
   if(!支撑压力启用突破回踩确认) return;

   int lookback = MathMax(突破回踩观察K线数, 3);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, lookback + 5, rates);
   if(copied <= 3) return;

   double buffer = GetConfirmedBreakoutBuffer();
   for(int lv=0; lv<ArraySize(allRes); lv++)
   {
      double lowEdge = (allRes[lv].zoneLow > 0.0) ? allRes[lv].zoneLow : allRes[lv].price - mergeDistance * 0.5;
      double highEdge = (allRes[lv].zoneHigh > 0.0) ? allRes[lv].zoneHigh : allRes[lv].price + mergeDistance * 0.5;
      for(int i=2; i<copied; i++)
      {
         if(rates[i].close <= highEdge + buffer) continue;
         for(int j=i-1; j>=0; j--)
         {
            if(rates[j].low <= highEdge && rates[j].high >= lowEdge && rates[j].close > lowEdge)
            {
               AddOrMergeSRLevelEx(allSup, allRes[lv].price, rates[j].time, mergeDistance,
                                   allRes[lv].strength * 0.35 + 突破回踩加分,
                                   false, true, allRes[lv].tfMask, allRes[lv].sessionLevel,
                                   allRes[lv].densityLevel, false, true, 突破回踩加分, false, allRes[lv].integerConfluence, true, allRes[lv].maxReaction);
               break;
            }
         }
         break;
      }
   }

   for(int lv=0; lv<ArraySize(allSup); lv++)
   {
      double lowEdge = (allSup[lv].zoneLow > 0.0) ? allSup[lv].zoneLow : allSup[lv].price - mergeDistance * 0.5;
      double highEdge = (allSup[lv].zoneHigh > 0.0) ? allSup[lv].zoneHigh : allSup[lv].price + mergeDistance * 0.5;
      for(int i=2; i<copied; i++)
      {
         if(rates[i].close >= lowEdge - buffer) continue;
         for(int j=i-1; j>=0; j--)
         {
            if(rates[j].high >= lowEdge && rates[j].low <= highEdge && rates[j].close < highEdge)
            {
               AddOrMergeSRLevelEx(allRes, allSup[lv].price, rates[j].time, mergeDistance,
                                   allSup[lv].strength * 0.35 + 突破回踩加分,
                                   true, false, allSup[lv].tfMask, allSup[lv].sessionLevel,
                                   allSup[lv].densityLevel, false, true, 突破回踩加分, false, allSup[lv].integerConfluence, true, allSup[lv].maxReaction);
               break;
            }
         }
         break;
      }
   }
}

bool SRZoneConfirmedBroken(const SRLevel &lv, bool resistance)
{
   double edge = lv.price;
   if(resistance)
      edge = (lv.zoneHigh > 0.0) ? lv.zoneHigh : lv.price;
   else
      edge = (lv.zoneLow > 0.0) ? lv.zoneLow : lv.price;

   double buffer = GetConfirmedBreakoutBuffer();
   if(!手机标记突破需M1收线确认)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(bid <= 0.0 || ask <= 0.0) return false;
      double mid = (bid + ask) / 2.0;
      return resistance ? (mid >= edge + buffer) : (mid <= edge - buffer);
   }

   datetime t; double c;
   if(!GetLastClosedM1(t, c)) return false;
   return resistance ? (c >= edge + buffer) : (c <= edge - buffer);
}

double SRSortScore(const SRLevel &lv, double refPrice)
{
   double dist = MathAbs(lv.price - refPrice);
   double atr = 0.0;
   GetATRPrice(atr);
   double distUnit = MathMax(atr, 支撑压力合并距离价格);
   if(distUnit <= 0.0) distUnit = MathMax(_Point * 100, 1.0);

   // 强结构优先，同时惩罚过远点位；这里只用于候选筛选，最终显示仍按纯距离排序。
   double penalty = 支撑压力启用距离惩罚 ? MathMax(支撑压力距离惩罚强度, 0.0) : 0.0;
   double baseScore = 支撑压力启用最终增强版 ? (lv.tradeScore * 120.0 + lv.strength * 20.0) : (lv.strength * 100.0);
   if(支撑压力启用最终增强版 && lv.tradable) baseScore += 10000.0;
   return baseScore - dist / distUnit * penalty;
}

void SortSRByDistance(SRLevel &arr[], double refPrice)
{
   int n = ArraySize(arr);
   for(int i=1; i<n; i++)
   {
      SRLevel key = arr[i];
      double keyDist = MathAbs(key.price - refPrice);
      double keyScore = SRSortScore(key, refPrice);
      int j = i - 1;
      while(j >= 0)
      {
         double d = MathAbs(arr[j].price - refPrice);
         double score = SRSortScore(arr[j], refPrice);

         if(支撑压力强度优先排序)
         {
            // 分数高的排前；分数接近时，离现价近的排前。
            if(score > keyScore) break;
            if(MathAbs(score - keyScore) < 1.0 && d <= keyDist) break;
         }
         else
         {
            if(d < keyDist) break;
            if(MathAbs(d - keyDist) < MathMax(_Point * 10, 支撑压力合并距离价格 * 0.10) && arr[j].strength >= key.strength) break;
         }

         arr[j + 1] = arr[j];
         j--;
      }
      arr[j + 1] = key;
   }
}

void SortSRByPureDistance(SRLevel &arr[], double refPrice)
{
   int n = ArraySize(arr);
   for(int i=1; i<n; i++)
   {
      SRLevel key = arr[i];
      double keyDist = MathAbs(key.price - refPrice);
      int j = i - 1;
      while(j >= 0)
      {
         double d = MathAbs(arr[j].price - refPrice);
         if(d < keyDist) break;
         if(MathAbs(d - keyDist) < 0.50 && arr[j].strength >= key.strength) break;
         arr[j + 1] = arr[j];
         j--;
      }
      arr[j + 1] = key;
   }
}

void SortSRByTradePurpose(SRLevel &arr[], double refPrice)
{
   int n = ArraySize(arr);
   for(int i=1; i<n; i++)
   {
      SRLevel key = arr[i];
      double keyDist = MathAbs(key.price - refPrice);
      int j = i - 1;
      while(j >= 0)
      {
         double d = MathAbs(arr[j].price - refPrice);
         bool keepBefore = false;
         if(arr[j].tradable != key.tradable)
            keepBefore = arr[j].tradable;
         else if(MathAbs(d - keyDist) < 0.50)
            keepBefore = (arr[j].tradeScore >= key.tradeScore);
         else
            keepBefore = (d < keyDist);

         if(keepBefore) break;
         arr[j + 1] = arr[j];
         j--;
      }
      arr[j + 1] = key;
   }
}

void CopyTopSRLevels(SRLevel &source[], SRLevel &target[], double refPrice, int maxCount)
{
   ArrayResize(target, 0);
   if(maxCount <= 0) return;

   // 先按“强度 + 距离”筛出有价值的点位，避免最近的小噪声直接占用R1/S1。
   SortSRByDistance(source, refPrice);
   int total = ArraySize(source);
   if(total <= 0) return;

   int minStrength = MathMax(支撑压力最低有效强度, 1);

   // 增强版：先拿可交易线，再拿观察线；不拿明显弱噪声来冒充R1/S1。
   int passes = 支撑压力启用最终增强版 ? 3 : 2;
   for(int pass=0; pass<passes; pass++)
   {
      for(int i=0; i<total; i++)
      {
         if(支撑压力启用最终增强版)
         {
            if(pass == 0 && !source[i].tradable) continue;
            if(pass == 1 && (!支撑压力无交易线时允许显示弱观察线 || source[i].tradable || source[i].qualityGrade < 1)) continue;
            if(pass == 2 && !支撑压力无交易线时允许显示弱观察线) continue;
            if(pass == 2 && source[i].strength < MathMax(2, minStrength / 2)) continue;
            if(pass > 0 && source[i].statusText == "")
               source[i].statusText = (pass == 1 ? "仅观察" : "暂不建议");
         }
         else
         {
            if(pass == 0 && source[i].strength < minStrength) continue;
         }

         bool exists = false;
         for(int j=0; j<ArraySize(target); j++)
         {
            if(MathAbs(target[j].price - source[i].price) <= MathMax(_Point * 5, 支撑压力合并距离价格 * 0.25))
            {
               exists = true;
               break;
            }
         }
         if(exists) continue;

         int n = ArraySize(target);
         ArrayResize(target, n + 1);
         target[n] = source[i];
         if(ArraySize(target) >= maxCount)
         {
            // 面板显示、R1/R2与S1/S2触发顺序，统一按离当前价格近到远排列。
            if(支撑压力启用最终增强版)
               SortSRByTradePurpose(target, refPrice);
            else
               SortSRByPureDistance(target, refPrice);
            return;
         }
      }
   }

   if(支撑压力启用最终增强版)
      SortSRByTradePurpose(target, refPrice);
   else
      SortSRByPureDistance(target, refPrice);
}

void SetSRHLine(string name, double price, color clr, ENUM_LINE_STYLE style, int width, string text)
{
   if(price <= 0.0)
   {
      ObjectDelete(0, name);
      return;
   }

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}

void DeleteSRObjects()
{
   for(int i=1; i<=5; i++)
   {
      ObjectDelete(0, "SMA_SR_RES_" + IntegerToString(i));
      ObjectDelete(0, "SMA_SR_SUP_" + IntegerToString(i));
   }
}

void DrawSupportResistanceLines()
{
   int maxShow = MathMin(MathMax(每侧最多显示点位数, 0), 5);
   for(int i=1; i<=5; i++)
   {
      if(i <= maxShow && i <= ArraySize(缓存压力位))
      {
         string status = 支撑压力启用最终增强版 ? SRActionText(缓存压力位[i-1], true, false) : "";
         string txt = 支撑压力启用最终增强版 ?
            StringFormat("R%d %.2f %s", i, 缓存压力位[i-1].price, status) :
            StringFormat("R%d %.2f x%d", i, 缓存压力位[i-1].price, 缓存压力位[i-1].strength);
         SetSRHLine("SMA_SR_RES_" + IntegerToString(i), NormalizePrice(缓存压力位[i-1].price), clrTomato, STYLE_DASH, i == 1 ? 2 : 1, txt);
      }
      else ObjectDelete(0, "SMA_SR_RES_" + IntegerToString(i));

      if(i <= maxShow && i <= ArraySize(缓存支撑位))
      {
         string status = 支撑压力启用最终增强版 ? SRActionText(缓存支撑位[i-1], false, false) : "";
         string txt = 支撑压力启用最终增强版 ?
            StringFormat("S%d %.2f %s", i, 缓存支撑位[i-1].price, status) :
            StringFormat("S%d %.2f x%d", i, 缓存支撑位[i-1].price, 缓存支撑位[i-1].strength);
         SetSRHLine("SMA_SR_SUP_" + IntegerToString(i), NormalizePrice(缓存支撑位[i-1].price), clrLime, STYLE_DASH, i == 1 ? 2 : 1, txt);
      }
      else ObjectDelete(0, "SMA_SR_SUP_" + IntegerToString(i));
   }
}


double GetConfirmedBreakoutBuffer()
{
   double buffer = MathMax(手机标记突破确认缓冲, 0.0);
   buffer = MathMax(buffer, MathMax(手机标记大突破最小缓冲, 0.0));
   double atr = 0.0;
   if(GetATRPrice(atr) && atr > 0.0)
      buffer = MathMax(buffer, atr * MathMax(手机标记大突破ATR倍数, 0.0));
   return buffer;
}

bool GetLastClosedM1(datetime &barTime, double &closePrice)
{
   barTime = iTime(_Symbol, PERIOD_M1, 1);
   closePrice = iClose(_Symbol, PERIOD_M1, 1);
   return (barTime > 0 && closePrice > 0.0);
}

bool SRLevelConfirmedBroken(double levelPrice, bool resistance)
{
   if(levelPrice <= 0.0) return false;

   double buffer = GetConfirmedBreakoutBuffer();
   if(!手机标记突破需M1收线确认)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(bid <= 0.0 || ask <= 0.0) return false;
      double mid = (bid + ask) / 2.0;
      return resistance ? (mid >= levelPrice + buffer) : (mid <= levelPrice - buffer);
   }

   datetime t; double c;
   if(!GetLastClosedM1(t, c)) return false;
   return resistance ? (c >= levelPrice + buffer) : (c <= levelPrice - buffer);
}

bool UpdateSupportResistance(bool force=false, bool updateVisuals=true)
{
   PerformanceScope perfScope(PERF_UPDATE_SUPPORT_RESISTANCE);
   // 箱体计算仍为短线动态 SL/TP 服务，不能随着图表显示移除而停掉结构缓存。
   bool needShortBoxCalculation = (当前参数配置模板 == 配置_黄金超短快保 && 短线单启用箱体边缘TP_SL);
   if(!显示支撑压力线 && !面板显示支撑压力 && !needShortBoxCalculation)
   {
      ArrayResize(缓存压力位, 0);
      ArrayResize(缓存支撑位, 0);
      if(updateVisuals)
         DeleteSRObjects();
      return false;
   }

   datetime now = TimeCurrent();
   if(!force && 上次支撑压力刷新时间 > 0 && now - 上次支撑压力刷新时间 < 支撑压力刷新秒数)
   {
      if(updateVisuals)
      {
         if(显示支撑压力线) DrawSupportResistanceLines();
         else DeleteSRObjects();
      }
      return (ArraySize(缓存压力位) > 0 || ArraySize(缓存支撑位) > 0);
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return false;
   double mid = (bid + ask) / 2.0;

   SRLevel allRes[];
   SRLevel allSup[];
   double mergeDistance = MathMax(支撑压力合并距离价格, _Point * 20);
   if(支撑压力合并使用ATR)
   {
      double srAtr = 0.0;
      if(GetATRPrice(srAtr) && srAtr > 0.0)
         mergeDistance = MathMax(mergeDistance, srAtr * MathMax(支撑压力合并ATR倍数, 0.0));
   }

   if(支撑压力使用多周期结构)
   {
      // 多周期结构识别：M1负责近场细节，M5/M15负责更稳定的M/W结构和多次触碰区域。
      if(支撑压力启用M1)
         ScanSRTimeframe(PERIOD_M1, 支撑压力回看K线数, 支撑压力摆点强度, 支撑压力M1权重, mergeDistance, allRes, allSup);
      if(支撑压力启用M5)
         ScanSRTimeframe(PERIOD_M5, 支撑压力M5回看K线数, 支撑压力M5摆点强度, 支撑压力M5权重, mergeDistance, allRes, allSup);
      if(支撑压力启用M15)
         ScanSRTimeframe(PERIOD_M15, 支撑压力M15回看K线数, 支撑压力M15摆点强度, 支撑压力M15权重, mergeDistance, allRes, allSup);
   }
   else
   {
      ScanSRTimeframe(支撑压力周期,
                      支撑压力回看K线数,
                      支撑压力摆点强度,
                      1,
                      mergeDistance,
                      allRes,
                      allSup);
   }

   if(支撑压力启用最终增强版)
   {
      AddRangeBoxBoundaries(allRes, allSup, mergeDistance);
      AddDailyAndSessionLevels(allRes, allSup, mergeDistance);
      AddDensityLevelsByM1PriceBuckets(allRes, allSup, mergeDistance);
      DetectLiquiditySweeps(allRes, true);
      DetectLiquiditySweeps(allSup, false);
      DetectBreakoutRetests(allRes, allSup, mergeDistance);
      ApplyExpiryPenalty(allRes);
      ApplyExpiryPenalty(allSup);
      int trendRegime = DetectTrendRegimeM5();
      bool highVolatility = IsSRHighVolatilityMode();
      ApplyTrendWeightToSRLevels(allRes, allSup, trendRegime, mid);
      ClassifySRTradingIntent(allRes, true, mid, trendRegime, highVolatility);
      ClassifySRTradingIntent(allSup, false, mid, trendRegime, highVolatility);
   }

   SRLevel nearRes[];
   SRLevel nearSup[];

   for(int i=0; i<ArraySize(allRes); i++)
   {
      // 缓存压力位必须严格位于当前价上方；已被价格穿越但未确认的旧压力只做内部观察，不进入R缓存。
      if(allRes[i].price > mid)
      {
         int n = ArraySize(nearRes);
         ArrayResize(nearRes, n + 1);
         nearRes[n] = allRes[i];
      }
   }

   for(int i=0; i<ArraySize(allSup); i++)
   {
      // 缓存支撑位必须严格位于当前价下方；已被价格穿越但未确认的旧支撑不进入S缓存。
      if(allSup[i].price < mid)
      {
         int n = ArraySize(nearSup);
         ArrayResize(nearSup, n + 1);
         nearSup[n] = allSup[i];
      }
   }

   int displayShow = 支撑压力启用最终增强版 ? MathMax(支撑压力最多显示数量, 0) : MathMax(每侧最多显示点位数, 0);
   int markerNeed = 启用手机标记挂单 ? MathMax(手机标记每侧点位数, 0) : 0;
   int maxShow = MathMin(MathMax(displayShow, markerNeed), 5);
   CopyTopSRLevels(nearRes, 缓存压力位, mid, maxShow);
   CopyTopSRLevels(nearSup, 缓存支撑位, mid, maxShow);

   上次支撑压力刷新时间 = now;
   if(updateVisuals)
   {
      if(显示支撑压力线)
         DrawSupportResistanceLines();
      else
         DeleteSRObjects();
   }

   return true;
}

#endif
