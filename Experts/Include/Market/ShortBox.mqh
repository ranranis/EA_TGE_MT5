#ifndef SMA_MARKET_SHORT_BOX_MQH
#define SMA_MARKET_SHORT_BOX_MQH

bool ShortLineBoxLevelQualified(const SRLevel &level)
{
   if(!level.boxBoundary || level.brokenConfirmed || level.observeOnly) return false;
   if(level.tradeScore < MathMax(短线单箱体最低交易评分, 0.0)) return false;

   bool higherTF = ((level.tfMask & SR_TF_M5) != 0 || (level.tfMask & SR_TF_M15) != 0);
   bool confirmedReaction = (level.effectiveReaction || level.retestConfirmed || level.sweepFailed);
   if(level.touches < MathMax(短线单箱体最低触碰次数, 1) && !higherTF && !confirmedReaction)
      return false;
   return true;
}

bool ShortLineM1MomentumWithPosition(ENUM_POSITION_TYPE type)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, 3, rates);
   if(copied < 3) return false;

   double bodySum = 0.0;
   for(int i=0; i<copied; i++)
      bodySum += rates[i].close - rates[i].open;

   double progress = rates[0].close - rates[copied - 1].open;
   if(type == POSITION_TYPE_BUY)
      return (bodySum > 0.0 && progress > 0.0 && rates[0].close >= rates[1].close);
   return (bodySum < 0.0 && progress < 0.0 && rates[0].close <= rates[1].close);
}

bool GetShortLineBoxEdge(bool resistance, double refPrice, SRLevel &level)
{
   SRLevel bestBox;
   SRLevel bestAny;
   bool foundBox = false;
   bool foundAny = false;
   double bestBoxDist = 0.0;
   double bestAnyDist = 0.0;

   if(resistance)
   {
      for(int i=0; i<ArraySize(缓存压力位); i++)
      {
         if(缓存压力位[i].price <= refPrice) continue;
         if(!ShortLineBoxLevelQualified(缓存压力位[i])) continue;
         double d = 缓存压力位[i].price - refPrice;
         if(!foundAny || d < bestAnyDist)
         {
            bestAny = 缓存压力位[i];
            bestAnyDist = d;
            foundAny = true;
         }
         if(缓存压力位[i].boxBoundary && (!foundBox || d < bestBoxDist))
         {
            bestBox = 缓存压力位[i];
            bestBoxDist = d;
            foundBox = true;
         }
      }
   }
   else
   {
      for(int i=0; i<ArraySize(缓存支撑位); i++)
      {
         if(缓存支撑位[i].price >= refPrice) continue;
         if(!ShortLineBoxLevelQualified(缓存支撑位[i])) continue;
         double d = refPrice - 缓存支撑位[i].price;
         if(!foundAny || d < bestAnyDist)
         {
            bestAny = 缓存支撑位[i];
            bestAnyDist = d;
            foundAny = true;
         }
         if(缓存支撑位[i].boxBoundary && (!foundBox || d < bestBoxDist))
         {
            bestBox = 缓存支撑位[i];
            bestBoxDist = d;
            foundBox = true;
         }
      }
   }

   if(foundBox)
   {
      level = bestBox;
      return true;
   }
   if(foundAny && bestAny.boxBoundary)
   {
      level = bestAny;
      return true;
   }
   return false;
}

bool ShortLineBoxTPPrice(ENUM_POSITION_TYPE type, double openPrice, double &tpPrice, double &tpDistance)
{
   tpPrice = 0.0;
   tpDistance = 0.0;
   if(!短线单启用箱体边缘TP_SL) return false;

   SRLevel edge;
   if(type == POSITION_TYPE_BUY)
   {
      if(!GetShortLineBoxEdge(true, openPrice, edge)) return false;
      tpPrice = NormalizePrice(edge.price - MathMax(短线单箱体TP贴边缓冲价格, 0.0));
      tpDistance = tpPrice - openPrice;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      if(!GetShortLineBoxEdge(false, openPrice, edge)) return false;
      tpPrice = NormalizePrice(edge.price + MathMax(短线单箱体TP贴边缓冲价格, 0.0));
      tpDistance = openPrice - tpPrice;
   }
   else
   {
      return false;
   }

   if(tpPrice <= 0.0) return false;
   if(tpDistance < MathMax(短线单箱体TP最小空间价格, 0.0)) return false;
   if(短线单箱体TP最大空间价格 > 0.0 && tpDistance > 短线单箱体TP最大空间价格) return false;
   return true;
}

bool ShortLineBoxSLPrice(ENUM_POSITION_TYPE type, double openPrice, double &slPrice, double &slDistance)
{
   slPrice = 0.0;
   slDistance = 0.0;
   if(!短线单启用箱体边缘TP_SL) return false;

   SRLevel edge;
   if(type == POSITION_TYPE_BUY)
   {
      if(!GetShortLineBoxEdge(false, openPrice, edge)) return false;
      slPrice = NormalizePrice(edge.price - MathMax(短线单箱体SL外侧缓冲价格, 0.0));
      slDistance = openPrice - slPrice;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      if(!GetShortLineBoxEdge(true, openPrice, edge)) return false;
      slPrice = NormalizePrice(edge.price + MathMax(短线单箱体SL外侧缓冲价格, 0.0));
      slDistance = slPrice - openPrice;
   }
   else
   {
      return false;
   }

   if(slPrice <= 0.0) return false;
   if(slDistance < MathMax(短线单箱体SL最小距离价格, 0.0)) return false;
   if(短线单箱体SL最大距离价格 > 0.0 && slDistance > 短线单箱体SL最大距离价格) return false;
   return true;
}

// 最近有效结构箱体的初始风控候选。箱体本身仅由已收 M1 建立、连续已收 M1 突破后失效；
// 这里把同一箱体的反侧 SL 与同侧 TP 成对返回，避免窄幅行情只缩小风险却仍保留过远目标。
bool ShortLineVisualBoxInitialTargets(ENUM_POSITION_TYPE type, double openPrice,
                                      double &slPrice, double &tpPrice,
                                      double &slDistance, double &tpDistance)
{
   slPrice = 0.0;
   tpPrice = 0.0;
   slDistance = 0.0;
   tpDistance = 0.0;
   if(!短线单启用箱体边缘TP_SL || openPrice <= 0.0) return false;
   if(!RefreshShortVisualBoxState() || !shortVisualBox.hasBox || !shortVisualBox.validBox ||
      !shortVisualBox.frozen || shortVisualBox.boxHigh <= shortVisualBox.boxLow)
      return false;
   if(ShortVisualBoxConfirmedBreakoutDirection() != 0) return false;

   double slBuffer = MathMax(短线单箱体SL外侧缓冲价格, _Point*5.0);
   double tpBuffer = MathMax(短线单箱体TP贴边缓冲价格, _Point*2.0);
   if(type == POSITION_TYPE_BUY)
   {
      slPrice = NormalizePrice(shortVisualBox.boxLow-slBuffer);
      tpPrice = NormalizePrice(shortVisualBox.boxHigh-tpBuffer);
      slDistance = openPrice-slPrice;
      tpDistance = tpPrice-openPrice;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      slPrice = NormalizePrice(shortVisualBox.boxHigh+slBuffer);
      tpPrice = NormalizePrice(shortVisualBox.boxLow+tpBuffer);
      slDistance = slPrice-openPrice;
      tpDistance = openPrice-tpPrice;
   }
   else
   {
      return false;
   }

   double brokerDistance = (double)MathMax((int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                                            (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   brokerDistance = MathMax(brokerDistance, CurrentSpreadPrice()*2.0);
   if(slDistance <= brokerDistance || tpDistance <= brokerDistance) return false;
   if(tpDistance + _Point*0.5 < slDistance*MathMax(短线单主TP最小风险回报比, 0.10)) return false;
   return (slPrice > 0.0 && tpPrice > 0.0);
}

// 仅用于升级后的首次清理：删除旧版遗留的箱体图表对象，不读取或改变箱体计算状态。
void DeleteLegacyShortLineBoxChartObjects()
{
   string exactNames[] =
   {
      "SMA_SHORT_BOX", "SMA_SHORT_BOX_TEXT", "SMA_SHORT_BOX_HIGH",
      "SMA_SHORT_BOX_UPPER_ZONE", "SMA_SHORT_BOX_MIDDLE", "SMA_SHORT_BOX_LOWER_ZONE",
      "SMA_SHORT_BOX_LOW", "SMA_SHORT_MICRO_BOX", "SMA_SHORT_MICRO_BOX_TEXT",
      "SMA_SHORT_MICRO_BOX_MIDDLE"
   };
   for(int i=0; i<ArraySize(exactNames); i++)
      ObjectDelete(0, exactNames[i]);

   const string historyPrefix = "SMA_SHORT_BOX_HIST_";
   for(int i=ObjectsTotal(0, 0, -1)-1; i>=0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, historyPrefix) == 0)
         ObjectDelete(0, name);
   }
}

// 微型箱体是最近5-10根M1的短节奏范围：只用来在已有利润后抬高保护位，
// 不和60-120根的结构箱体混用，更不会参与首次SL和主TP。
bool GetShortLineMicroBoxRange(bool includeCurrentBar, double atr, double &low, double &high,
                               datetime &newestBarTime)
{
   low = 0.0;
   high = 0.0;
   newestBarTime = 0;
   if(当前参数配置模板 != 配置_黄金超短快保 || !短线单启用微型箱体保护) return false;

   int lookback = MathMin(MathMax(短线单微型箱体回看M1, 5), 10);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, includeCurrentBar ? 0 : 1, lookback, rates);
   if(copied < lookback) return false;

   low = rates[0].low;
   high = rates[0].high;
   for(int i=1; i<copied; i++)
   {
      low = MathMin(low, rates[i].low);
      high = MathMax(high, rates[i].high);
   }
   newestBarTime = rates[0].time;
   if(high <= low) return false;

   double unit = atr > 0.0 ? atr : AverageClosedRange(PERIOD_M1, 14);
   if(unit <= 0.0) unit = MathMax(_Point * 100.0, 0.10);
   // 一根极端波动把范围拉得过宽时，它不是可用于追踪的微整理结构。
   if(high-low > unit * MathMax(短线单微型箱体最大高度ATR倍数, 0.50)) return false;
   return true;
}

bool ShortLineMicroBoxStructureSL(ENUM_POSITION_TYPE type, double atr, bool includeCurrentBar,
                                   double &candidateSL, double &minDistance, datetime &newestBarTime)
{
   candidateSL = 0.0;
   minDistance = 0.0;
   double low = 0.0, high = 0.0;
   if(!GetShortLineMicroBoxRange(includeCurrentBar, atr, low, high, newestBarTime)) return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= bid) return false;
   minDistance = MathMax(M1结构最小SL距离, (ask-bid)*3.0);
   if(atr > 0.0) minDistance = MathMax(minDistance, atr*M1结构最小SL距离ATR倍数);
   double buffer = MathMax(短线单微型箱体SL缓冲价格, _Point*5.0);

   if(type == POSITION_TYPE_BUY)
   {
      candidateSL = NormalizePrice(low-buffer);
      return (candidateSL > 0.0 && candidateSL < bid && bid-candidateSL >= minDistance);
   }
   if(type == POSITION_TYPE_SELL)
   {
      candidateSL = NormalizePrice(high+buffer);
      return (candidateSL > ask && candidateSL-ask >= minDistance);
   }
   return false;
}

bool GetShortLineVisualEdge(bool resistance, double refPrice, SRLevel &level, bool &tradeQualified)
{
   tradeQualified = GetShortLineBoxEdge(resistance, refPrice, level);
   // 保留原默认配置下的候选边界回退，避免移除绘图开关后改变动态箱体边缘计算。
   if(tradeQualified) return true;
   bool found = false;
   double bestDistance = 0.0;
   SRLevel fallback;
   if(resistance)
   {
      for(int i=0; i<ArraySize(缓存压力位); i++)
      {
         if(缓存压力位[i].price <= refPrice || 缓存压力位[i].brokenConfirmed) continue;
         double distance = 缓存压力位[i].price-refPrice;
         if(!found || distance < bestDistance)
         {
            fallback = 缓存压力位[i];
            bestDistance = distance;
            found = true;
         }
      }
   }
   else
   {
      for(int i=0; i<ArraySize(缓存支撑位); i++)
      {
         if(缓存支撑位[i].price >= refPrice || 缓存支撑位[i].brokenConfirmed) continue;
         double distance = refPrice-缓存支撑位[i].price;
         if(!found || distance < bestDistance)
         {
            fallback = 缓存支撑位[i];
            bestDistance = distance;
            found = true;
         }
      }
   }
   if(found) level = fallback;
   return found;
}

void ResetShortVisualBoxState()
{
   shortVisualBox.hasBox = false;
   shortVisualBox.validBox = false;
   shortVisualBox.frozen = false;
   shortVisualBox.scannedClosedBarTime = 0;
   shortVisualBox.boxStartTime = 0;
   shortVisualBox.boxHigh = 0.0;
   shortVisualBox.boxLow = 0.0;
   shortVisualBox.upperTouches = 0;
   shortVisualBox.lowerTouches = 0;
   shortVisualBox.insideCloseRatio = 0.0;
   shortVisualBox.atrWidth = 0.0;
}

double ShortVisualMedian(double &values[], int count)
{
   if(count <= 0) return 0.0;
   double sorted[];
   ArrayResize(sorted, count);
   for(int i=0; i<count; i++) sorted[i] = values[i];
   for(int i=1; i<count; i++)
   {
      double value = sorted[i];
      int j = i-1;
      while(j >= 0 && sorted[j] > value)
      {
         sorted[j+1] = sorted[j];
         j--;
      }
      sorted[j+1] = value;
   }
   return (count % 2 == 0) ? (sorted[count/2-1]+sorted[count/2])*0.5 : sorted[count/2];
}

int BuildShortVisualEdgeCandidates(double &pivotPrices[], datetime &pivotTimes[], int pivotCount,
                                   double tolerance, ShortVisualBoxEdge &edges[])
{
   ArrayResize(edges, 0);
   if(pivotCount <= 0 || tolerance <= 0.0) return 0;
   for(int i=0; i<pivotCount; i++)
   {
      double clusteredPrices[];
      int clusteredCount = 0;
      datetime latestTouch = 0;
      for(int j=0; j<pivotCount; j++)
      {
         if(MathAbs(pivotPrices[j]-pivotPrices[i]) > tolerance) continue;
         ArrayResize(clusteredPrices, clusteredCount+1);
         clusteredPrices[clusteredCount++] = pivotPrices[j];
         if(pivotTimes[j] > latestTouch) latestTouch = pivotTimes[j];
      }
      if(clusteredCount <= 0) continue;
      double edgePrice = ShortVisualMedian(clusteredPrices, clusteredCount);
      bool duplicate = false;
      for(int k=0; k<ArraySize(edges); k++)
      {
         if(MathAbs(edges[k].price-edgePrice) <= tolerance*0.5)
         {
            duplicate = true;
            break;
         }
      }
      if(duplicate) continue;
      int n = ArraySize(edges);
      ArrayResize(edges, n+1);
      edges[n].price = edgePrice;
      edges[n].touches = clusteredCount;
      edges[n].lastTouchTime = latestTouch;
   }
   return ArraySize(edges);
}

double SnapShortVisualEdgeToSR(bool resistance, double price, int localTouches, double tolerance)
{
   // 支撑压力只在本地M1结构已确认至少两次测试后，作为同一价格带内的吸附参考。
   if(localTouches < 2 || tolerance <= 0.0) return price;
   SRLevel sr;
   bool qualified = false;
   double refPrice = resistance ? price-tolerance : price+tolerance;
   if(GetShortLineVisualEdge(resistance, refPrice, sr, qualified) && MathAbs(sr.price-price) <= tolerance)
      return sr.price;
   return price;
}

int ShortVisualBoxConfirmedBreakoutDirection()
{
   if(!shortVisualBox.validBox || shortVisualBox.boxHigh <= shortVisualBox.boxLow) return 0;
   int requiredBars = MathMax(短线单箱体突破失效确认M1, 2);
   double atr = 0.0;
   GetATRPrice(atr);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (bid > 0.0 && ask > bid) ? ask-bid : _Point*5.0;
   double breakoutBuffer = MathMax(atr*0.15, spread*2.0);
   int upCount = 0, downCount = 0;
   for(int i=1; i<=requiredBars; i++)
   {
      double close = iClose(_Symbol, PERIOD_M1, i);
      if(close > shortVisualBox.boxHigh+breakoutBuffer) upCount++;
      if(close < shortVisualBox.boxLow-breakoutBuffer) downCount++;
   }
   if(upCount == requiredBars) return 1;
   if(downCount == requiredBars) return -1;
   return 0;
}

bool RefreshShortVisualBoxState()
{
   if(当前参数配置模板 != 配置_黄金超短快保)
   {
      ResetShortVisualBoxState();
      return false;
   }
   if(shortVisualBox.frozen && shortVisualBox.validBox)
   {
      int breakoutDirection = ShortVisualBoxConfirmedBreakoutDirection();
      if(breakoutDirection == 0) return true;
      PrintFormat("[短线箱体] 连续%d根M1%s突破，淘汰旧箱体 %.5f-%.5f，等待新整理区",
                  MathMax(短线单箱体突破失效确认M1, 2), breakoutDirection > 0 ? "向上" : "向下",
                  shortVisualBox.boxLow, shortVisualBox.boxHigh);
      // 冻结只防止影线扩张箱体；连续收盘突破说明原整理已经结束，旧箱体必须退休。
      ResetShortVisualBoxState();
   }

   datetime newestClosedBar = iTime(_Symbol, PERIOD_M1, 1);
   if(newestClosedBar <= 0) return false;
   if(shortVisualBox.scannedClosedBarTime == newestClosedBar) return shortVisualBox.hasBox;

   int lookback = MathMin(MathMax(短线单箱体识别回看M1, 20), 30);
   int strength = MathMin(MathMax(短线单箱体摆点强度M1, 1), 2);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, lookback, rates);
   if(copied < strength*2+5)
   {
      ResetShortVisualBoxState();
      shortVisualBox.scannedClosedBarTime = newestClosedBar;
      return false;
   }

   double atr = 0.0;
   GetATRPrice(atr);
   if(atr <= 0.0) atr = AverageClosedRange(PERIOD_M1, 14);
   if(atr <= 0.0) atr = MathMax(_Point*100.0, 0.10);
   double tolerance = MathMax(atr*MathMax(短线单箱体边界聚类ATR倍数, 0.01),
                              MathMax(短线单箱体边界最小容差价格, _Point*5.0));

   double pivotHighs[];
   datetime pivotHighTimes[];
   double pivotLows[];
   datetime pivotLowTimes[];
   for(int i=strength; i<copied-strength; i++)
   {
      bool localHigh = true;
      bool localLow = true;
      for(int j=1; j<=strength; j++)
      {
         if(rates[i].high <= rates[i-j].high || rates[i].high <= rates[i+j].high) localHigh = false;
         if(rates[i].low >= rates[i-j].low || rates[i].low >= rates[i+j].low) localLow = false;
      }
      if(localHigh)
      {
         int n = ArraySize(pivotHighs);
         ArrayResize(pivotHighs, n+1);
         ArrayResize(pivotHighTimes, n+1);
         pivotHighs[n] = rates[i].high;
         pivotHighTimes[n] = rates[i].time;
      }
      if(localLow)
      {
         int n = ArraySize(pivotLows);
         ArrayResize(pivotLows, n+1);
         ArrayResize(pivotLowTimes, n+1);
         pivotLows[n] = rates[i].low;
         pivotLowTimes[n] = rates[i].time;
      }
   }

   ShortVisualBoxEdge upperEdges[];
   ShortVisualBoxEdge lowerEdges[];
   BuildShortVisualEdgeCandidates(pivotHighs, pivotHighTimes, ArraySize(pivotHighs), tolerance, upperEdges);
   BuildShortVisualEdgeCandidates(pivotLows, pivotLowTimes, ArraySize(pivotLows), tolerance, lowerEdges);

   bool found = false;
   double bestScore = -DBL_MAX;
   double bestHigh = 0.0, bestLow = 0.0, bestInside = 0.0, bestAtrWidth = 0.0;
   int bestUpperTouches = 0, bestLowerTouches = 0;
   bool bestValid = false;
   double candidateMinWidth = atr*1.00;
   double candidateMaxWidth = atr*5.00;
   double validMinWidth = atr*MathMax(短线单箱体有效最小宽度ATR倍数, 0.10);
   double validMaxWidth = atr*MathMax(短线单箱体有效最大宽度ATR倍数,
                                      短线单箱体有效最小宽度ATR倍数);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (bid > 0.0 && ask > bid) ? ask-bid : _Point*5.0;
   double breakoutBuffer = MathMax(atr*0.15, spread*2.0);
   for(int u=0; u<ArraySize(upperEdges); u++)
   {
      double high = SnapShortVisualEdgeToSR(true, upperEdges[u].price, upperEdges[u].touches, tolerance);
      for(int l=0; l<ArraySize(lowerEdges); l++)
      {
         double low = SnapShortVisualEdgeToSR(false, lowerEdges[l].price, lowerEdges[l].touches, tolerance);
         double width = high-low;
         if(width < candidateMinWidth || width > candidateMaxWidth) continue;
         // 当前最新已收M1已有效离开该范围时，不能把旧整理区重新识别为新箱体。
         if(rates[0].close > high+breakoutBuffer || rates[0].close < low-breakoutBuffer) continue;
         bool hasTwoSidedCandidate =
            (upperEdges[u].touches >= 2 && lowerEdges[l].touches >= 1) ||
            (lowerEdges[l].touches >= 2 && upperEdges[u].touches >= 1);
         if(!hasTwoSidedCandidate) continue;

         int insideCloses = 0;
         for(int i=0; i<copied; i++)
            if(rates[i].close >= low && rates[i].close <= high) insideCloses++;
         double insideRatio = (double)insideCloses/(double)copied;
         if(insideRatio < ClampDouble(短线单箱体候选最小箱内收盘比例, 0.10, 1.00)) continue;

         double atrWidth = width/MathMax(atr, _Point);
         bool valid = upperEdges[u].touches >= 2 && lowerEdges[l].touches >= 2 &&
                      insideRatio >= ClampDouble(短线单箱体有效最小箱内收盘比例, 0.10, 1.00) &&
                      width >= validMinWidth && width <= validMaxWidth;
         double recentTouchScore = 0.0;
         datetime latestTouch = MathMax(upperEdges[u].lastTouchTime, lowerEdges[l].lastTouchTime);
         int touchAgeBars = (int)((newestClosedBar-latestTouch)/60);
         recentTouchScore = ClampDouble(2.0-(double)touchAgeBars/(double)lookback*2.0, 0.0, 2.0);
         double widthScore = (width >= validMinWidth && width <= validMaxWidth) ? 2.0 : 0.5;
         double isolatedWickPenalty = (upperEdges[u].touches == 1 ? 5.0 : 0.0) +
                                      (lowerEdges[l].touches == 1 ? 5.0 : 0.0);
         double unbalancedTouchPenalty = MathAbs(upperEdges[u].touches-lowerEdges[l].touches)*0.75;
         double score = upperEdges[u].touches*2.0 + lowerEdges[l].touches*2.0 + insideRatio*5.0 +
                        recentTouchScore + widthScore - isolatedWickPenalty - unbalancedTouchPenalty;
         if(!found || score > bestScore)
         {
            found = true;
            bestScore = score;
            bestHigh = high;
            bestLow = low;
            bestInside = insideRatio;
            bestAtrWidth = atrWidth;
            bestUpperTouches = upperEdges[u].touches;
            bestLowerTouches = lowerEdges[l].touches;
            bestValid = valid;
         }
      }
   }

   ResetShortVisualBoxState();
   shortVisualBox.scannedClosedBarTime = newestClosedBar;
   if(!found) return false;
   shortVisualBox.hasBox = true;
   shortVisualBox.validBox = bestValid;
   shortVisualBox.frozen = bestValid;
   shortVisualBox.boxStartTime = rates[copied-1].time;
   shortVisualBox.boxHigh = bestHigh;
   shortVisualBox.boxLow = bestLow;
   shortVisualBox.upperTouches = bestUpperTouches;
   shortVisualBox.lowerTouches = bestLowerTouches;
   shortVisualBox.insideCloseRatio = bestInside;
   shortVisualBox.atrWidth = bestAtrWidth;
   return true;
}

#endif
