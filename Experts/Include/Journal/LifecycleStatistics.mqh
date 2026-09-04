#ifndef SMA_JOURNAL_LIFECYCLE_STATISTICS_MQH
#define SMA_JOURNAL_LIFECYCLE_STATISTICS_MQH

// 统计页以完整position生命周期为口径；退出Deal数量仅作为执行质量信息，绝不再冒充交易笔数。
struct LifecycleSummaryMeta
{
   ulong  positionId;
   int    templateId;
   int    archetype;
   double initialRMoney;
   double mfeR;
   double maeR;
   double realizedR;
   double captureRatio;
   int    partialStages;
   int    partialFills;
   bool   fastProtection;
   int    runnerMode;
   bool   fixedTPRemoved;
   int    slModifyCount;
   int    tpModifyCount;
   double gross;
   double commission;
   double swap;
   double fee;
   double net;
};

struct LifecycleTradeAggregate
{
   ulong    positionId;
   datetime openTime;
   datetime closeTime;
   int      direction;
   long     entryMagic;
   bool     entryScope;
   double   entryVolume;
   double   exitVolume;
   double   entryValue;
   double   exitValue;
   int      exitDeals;
   double   gross;
   double   commission;
   double   swap;
   double   fee;
   double   net;
   int      templateId;
   int      archetype;
   double   initialRMoney;
   double   mfeR;
   double   maeR;
   double   realizedR;
   double   captureRatio;
   int      partialStages;
   int      partialFills;
   bool     fastProtection;
   int      runnerMode;
   bool     fixedTPRemoved;
   int      slModifyCount;
   int      tpModifyCount;
};

// 单笔复盘只读已写入的完整Summary；绝不根据未确认请求猜测分批、保护或最终离场。
struct LifecycleReviewItem
{
   ulong    positionId;
   datetime openTime;
   datetime closeTime;
   int      direction;
   int      templateId;
   int      archetype;
   double   initialVolume;
   double   entryVolume;
   double   exitVolume;
   double   entryPrice;
   double   exitPrice;
   double   initialSL;
   double   initialRPrice;
   double   initialRMoney;
   double   maxProfitMoney;
   double   maxLossMoney;
   double   mfeR;
   double   maeR;
   int      partialStages;
   int      partialFills;
   bool     fastProtection;
   int      runnerMode;
   bool     fixedTPRemoved;
   int      slModifyCount;
   int      tpModifyCount;
   int      exitIntent;
   long     actualExitReason;
   ulong    lastExitDeal;
   double   lastExitPrice;
   double   gross;
   double   commission;
   double   swap;
   double   fee;
   double   net;
   double   realizedR;
   double   captureRatio;
   double   floatingProfitSeconds;
   double   floatingLossSeconds;
   double   floatingFlatSeconds;
   double   longestFloatingLossSeconds;
   datetime firstFloatingProfitTime;
   datetime floatingTimingObservationStartTime;
   double   floatingTimingObservedSeconds;
   double   floatingTimingCoverageRatio;
   bool     floatingTimingHasData;
   double   maxLifecycleProfitMoney;
   double   maxLifecycleLossMoney;
};

// 新档案优先使用完整生命周期峰谷；旧档案至少以最终净结果修复明显矛盾。
double LifecycleReviewHighestFloatingProfit(const LifecycleReviewItem &item)
{
   double finalProfit = item.net > 0.0 ? item.net : 0.0;
   return MathMax(item.maxLifecycleProfitMoney,MathMax(item.maxProfitMoney,finalProfit));
}

double LifecycleReviewMaximumFloatingLoss(const LifecycleReviewItem &item)
{
   double finalLoss = item.net < 0.0 ? -item.net : 0.0;
   return MathMax(item.maxLifecycleLossMoney,MathMax(item.maxLossMoney,finalLoss));
}

// 复盘数组会在日/周/月与筛选之间反复复用。复制前必须精确缩短目标数组，
// 避免较短结果覆盖较长结果时保留旧尾部记录。
void CopyLifecycleReviewItemsExact(LifecycleReviewItem &target[], const LifecycleReviewItem &source[])
{
   int count=ArraySize(source);
   ArrayResize(target,count);
   if(count>0)
      ArrayCopy(target,source,0,0,count);
}

// 走势页只读逐笔投影。数据直接来自统计口径已经筛选完成的交易集合，
// 不从复盘档案反推，也不在 Canvas 绘制阶段重新扫描历史。
struct LifecycleTrendItem
{
   ulong    positionId;
   datetime closeTime;
   double   netProfit;
};

enum StatsTemplateBucket
{
   STATS_TEMPLATE_SHORT = 0,
   STATS_TEMPLATE_LONG,
   STATS_TEMPLATE_NEWS,
   STATS_TEMPLATE_MANUAL,
   STATS_TEMPLATE_COUNT
};

struct StatsPerformanceBucket
{
   int    trades;
   int    wins;
   int    losses;
   int    breakevens;
   int    riskKnownTrades;
   int    holdKnownTrades;
   double netProfit;
   double realizedR;
   double totalHoldMinutes;
};

struct LifecycleStats
{
   datetime bjDate;
   datetime serverStart;
   datetime serverEnd;
   int      trades;
   int      wins;
   int      losses;
   int      breakevens;
   int      exitDeals;
   double   entryVolume;
   double   exitVolume;
   double   netProfit;
   double   priceDiff;
   double   grossProfit;
   double   grossLoss;
   double   commission;
   double   swap;
   double   fee;
   double   totalTradingCost;
   double   avgWin;
   double   avgLoss;
   double   profitFactor;
   double   payoffRatio;
   double   bestProfit;
   bool     bestTradeValid;
   ulong    bestTradePositionId;
   int      bestTradeDirection;
   double   bestTradeVolume;
   double   bestTradePriceDiff;
   double   worstProfit;
   bool     worstTradeValid;
   ulong    worstTradePositionId;
   int      worstTradeDirection;
   double   worstTradeVolume;
   double   worstTradePriceDiff;
   int      currentLossStreak;
   int      maxLossStreak;
   int      buyTrades;
   int      sellTrades;
   double   buyProfit;
   double   sellProfit;
   double   totalHoldMinutes;
   int      holdKnownTrades;
   double   winningHoldMinutes;
   int      winningHoldKnownTrades;
   double   losingHoldMinutes;
   int      losingHoldKnownTrades;
   double   maxHoldMinutes;
   double   maxRealizedDrawdown;
   double   equityPeak;
   int      metadataTrades;
   int      riskKnownTrades;
   double   totalRealizedR;
   double   avgInitialRMoney;
   double   avgMfeR;
   double   avgMaeR;
   double   avgCaptureRatio;
   int      captureKnownTrades;
   double   maxRDrawdown;
   double   rPeak;
   int      partialTrades;
   int      partialStagesTotal;
   int      partialFillTotal;
   int      fastProtectionTrades;
   int      runnerStructureTrades;
   int      runnerFixedTrades;
   int      runnerBoxTrades;
   int      runnerFastExitTrades;
   int      fixedTPRemovedTrades;
   int      slModifyTotal;
   int      tpModifyTotal;
   int      archetypeTrades[6];
   double   archetypeProfit[6];
   double   archetypeR[6];
   int      sessionTrades[4];
   double   sessionProfit[4];
   double   sessionR[4];
   // “表现”页在同一次完整生命周期扫描中生成。配置表始终比较全部配置，
   // 时段矩阵则供顶部筛选直接选择，渲染阶段不再查询历史。
   StatsPerformanceBucket templatePerformance[STATS_TEMPLATE_COUNT];
   StatsPerformanceBucket sessionPerformanceAll[4];
   StatsPerformanceBucket sessionPerformanceByTemplate[STATS_TEMPLATE_COUNT][4];
   int      sltpRequested;
   int      sltpConfirmed;
   int      sltpFailed;
   int      partialRequested;
   int      partialFillEvents;
   int      fullCloseRequested;
   int      fullCloseFilled;
   int      fullCloseFailed;
   int      fastProtectionRequested;
   int      fastProtectionConfirmed;
   int      fastProtectionFailed;
};

LifecycleStats 生命周期统计缓存;
bool           生命周期统计缓存有效 = false;
datetime       生命周期统计缓存时间 = 0;
int            生命周期缓存周期 = -1;
int            生命周期缓存筛选 = -1;
int            生命周期缓存日偏移 = 0;
int            生命周期缓存周偏移 = 0;
int            生命周期缓存月偏移 = 0;
// 当前日期范围内已完成且已补齐Summary元数据的生命周期不依赖顶部配置筛选。
// 筛选切换时复用该数组，只做内存聚合，不重复HistorySelect和Deal全量遍历。
LifecycleTradeAggregate 生命周期完整交易缓存[];
bool                    生命周期完整交易缓存有效 = false;
bool                    生命周期完整交易缓存筛选复用 = false;
datetime                生命周期完整交易缓存时间 = 0;
datetime                生命周期完整交易缓存服务器开始 = 0;
datetime                生命周期完整交易缓存服务器结束 = 0;
LifecycleReviewItem 生命周期复盘缓存[];
bool                生命周期复盘缓存有效 = false;
datetime            生命周期复盘缓存时间 = 0;
int                 生命周期复盘缓存周期 = -1;
int                 生命周期复盘缓存筛选 = -1;
int                 生命周期复盘缓存日偏移 = 0;
int                 生命周期复盘缓存周偏移 = 0;
int                 生命周期复盘缓存月偏移 = 0;
datetime            生命周期复盘缓存服务器开始 = 0;
datetime            生命周期复盘缓存服务器结束 = 0;
LifecycleTrendItem  生命周期走势缓存[];
bool                生命周期走势缓存有效 = false;
int                 生命周期走势缓存周期 = -1;
int                 生命周期走势缓存筛选 = -1;
int                 生命周期走势缓存日偏移 = 0;
int                 生命周期走势缓存周偏移 = 0;
int                 生命周期走势缓存月偏移 = 0;
datetime            生命周期走势缓存服务器开始 = 0;
datetime            生命周期走势缓存服务器结束 = 0;

void CopyLifecycleTradesExact(LifecycleTradeAggregate &target[],
                              const LifecycleTradeAggregate &source[])
{
   int count=ArraySize(source);
   ArrayResize(target,count);
   if(count>0) ArrayCopy(target,source,0,0,count);
}

bool ReadLifecycleCsvRow(int handle, string &row[])
{
   ArrayResize(row, 0);
   if(handle == INVALID_HANDLE || FileIsEnding(handle)) return false;
   while(!FileIsEnding(handle))
   {
      int n = ArraySize(row);
      ArrayResize(row, n+1);
      row[n] = FileReadString(handle);
      if(FileIsLineEnding(handle)) break;
   }
   return ArraySize(row) > 0;
}

int FindSummaryMeta(LifecycleSummaryMeta &items[], ulong positionId)
{
   for(int i=0; i<ArraySize(items); i++)
      if(items[i].positionId == positionId) return i;
   return -1;
}

void LoadLifecycleSummaryMetadata(LifecycleSummaryMeta &items[])
{
   ArrayResize(items, 0);
   int handle = FileOpen(TradeJournalFileName("TradeSummary"),
                         FILE_CSV|FILE_READ|FILE_SHARE_READ|FILE_COMMON|FILE_ANSI, ',');
   if(handle == INVALID_HANDLE) return;

   string row[];
   bool firstRow = true;
   while(ReadLifecycleCsvRow(handle, row))
   {
      if(firstRow)
      {
         firstRow = false;
         continue;
      }
      if(ArraySize(row) < 42) continue;
      if(row[3] != _Symbol) continue;
      ulong positionId = (ulong)StringToInteger(row[2]);
      if(positionId == 0) continue;
      int idx = FindSummaryMeta(items, positionId);
      if(idx < 0)
      {
         idx = ArraySize(items);
         ArrayResize(items, idx+1);
      }
      items[idx].positionId = positionId;
      items[idx].templateId = (int)StringToInteger(row[5]);
      items[idx].archetype = (int)StringToInteger(row[6]);
      items[idx].initialRMoney = StringToDouble(row[17]);
      items[idx].mfeR = StringToDouble(row[22]);
      items[idx].maeR = StringToDouble(row[23]);
      items[idx].partialStages = (int)StringToInteger(row[24]);
      items[idx].partialFills = (int)StringToInteger(row[25]);
      items[idx].fastProtection = (StringToInteger(row[26]) != 0);
      items[idx].runnerMode = (int)StringToInteger(row[27]);
      items[idx].fixedTPRemoved = (StringToInteger(row[28]) != 0);
      items[idx].slModifyCount = (int)StringToInteger(row[29]);
      items[idx].tpModifyCount = (int)StringToInteger(row[30]);
      items[idx].gross = StringToDouble(row[35]);
      items[idx].commission = StringToDouble(row[36]);
      items[idx].swap = StringToDouble(row[37]);
      items[idx].fee = StringToDouble(row[38]);
      items[idx].net = StringToDouble(row[39]);
      items[idx].realizedR = StringToDouble(row[40]);
      items[idx].captureRatio = StringToDouble(row[41]);
   }
   FileClose(handle);
}

bool LifecycleTemplateMatches(int templateId)
{
   if(当前统计筛选 == 统计筛选_全部) return true;
   if(当前统计筛选 == 统计筛选_短线) return templateId == (int)配置_黄金超短快保;
   if(当前统计筛选 == 统计筛选_趋势) return templateId == (int)配置_黄金稳健托管;
   if(当前统计筛选 == 统计筛选_消息) return templateId == (int)配置_黄金消息对冲;
   return templateId == (int)配置_自定义 || templateId == (int)配置_黄金支压止盈;
}

int LifecycleTemplatePerformanceBucket(int templateId)
{
   if(templateId == (int)配置_黄金超短快保) return STATS_TEMPLATE_SHORT;
   if(templateId == (int)配置_黄金稳健托管) return STATS_TEMPLATE_LONG;
   if(templateId == (int)配置_黄金消息对冲) return STATS_TEMPLATE_NEWS;
   // 明确手动、自定义、旧记录缺失值和未来未映射模板统一进入手动桶。
   return STATS_TEMPLATE_MANUAL;
}

int LifecycleSelectedPerformanceTemplateBucket()
{
   if(当前统计筛选 == 统计筛选_短线) return STATS_TEMPLATE_SHORT;
   if(当前统计筛选 == 统计筛选_趋势) return STATS_TEMPLATE_LONG;
   if(当前统计筛选 == 统计筛选_消息) return STATS_TEMPLATE_NEWS;
   if(当前统计筛选 == 统计筛选_普通) return STATS_TEMPLATE_MANUAL;
   return -1;
}

void SortLifecycleReviewItemsByCloseTimeDesc(LifecycleReviewItem &items[])
{
   for(int i=1; i<ArraySize(items); i++)
   {
      LifecycleReviewItem key = items[i];
      int j = i-1;
      while(j >= 0 && items[j].closeTime < key.closeTime)
      {
         items[j+1] = items[j];
         j--;
      }
      items[j+1] = key;
   }
}

// 复盘页面必须与统计页使用同一套“完整平仓且落在当前服务器范围”口径。
// CSV 只保存管理过程细节，不能单独决定某笔交易属于哪一天；否则在切换
// 日/周/月时，会出现统计为 0 笔、复盘仍显示其他日期档案的矛盾回显。
bool LifecycleReviewPositionClosedInServerRange(ulong positionId,
                                                datetime serverStart,
                                                datetime serverEnd,
                                                datetime &actualCloseTime)
{
   actualCloseTime = 0;
   if(positionId == 0 || LifecyclePositionStillOpen(positionId)) return false;

   double entryVolume = 0.0;
   double exitVolume = 0.0;
   bool entryScope = false;
   int dealsTotal = HistoryDealsTotal();
   for(int i=0; i<dealsTotal; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != positionId) continue;

      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;

      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      double volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
      datetime dealTime = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      if(entry == DEAL_ENTRY_IN)
      {
         entryVolume += volume;
         if(MagicInScope((long)HistoryDealGetInteger(deal, DEAL_MAGIC))) entryScope = true;
      }
      else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
      {
         exitVolume += volume;
         if(dealTime >= actualCloseTime) actualCloseTime = dealTime;
      }
   }

   double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(volumeStep <= 0.0) volumeStep = 0.01;
   if(entryVolume <= 0.0 || exitVolume + volumeStep*0.5 < entryVolume) return false;
   if(actualCloseTime < serverStart || actualCloseTime >= serverEnd) return false;
   if(统计页仅统计受管Magic && !entryScope) return false;
   return true;
}

void LoadLifecycleReviewItemsByServerRange(datetime serverStart, datetime serverEnd, LifecycleReviewItem &items[])
{
   ArrayResize(items, 0);
   // 与统计聚合保持一致：额外回看用于识别跨日仓位的完整入场/离场手数。
   if(!HistorySelect(serverStart - 90*86400, serverEnd)) return;
   int handle = FileOpen(TradeJournalFileName("TradeSummary"),
                         FILE_CSV|FILE_READ|FILE_SHARE_READ|FILE_COMMON|FILE_ANSI, ',');
   if(handle == INVALID_HANDLE) return;

   string row[];
   bool firstRow = true;
   while(ReadLifecycleCsvRow(handle, row))
   {
      if(firstRow) { firstRow=false; continue; }
      if(ArraySize(row) < 42 || row[3] != _Symbol) continue;
      if((long)StringToInteger(row[1]) != AccountInfoInteger(ACCOUNT_LOGIN)) continue;

      LifecycleReviewItem item;
      ZeroMemory(item);
      item.positionId = (ulong)StringToInteger(row[2]);
      item.templateId = (int)StringToInteger(row[5]);
      // 平仓归属只信真实 Deal；row[8] 仅保留为历史档案字段，不能独立做日期筛选。
      if(!LifecycleReviewPositionClosedInServerRange(item.positionId, serverStart, serverEnd, item.closeTime)) continue;
      if(!LifecycleTemplateMatches(item.templateId)) continue;

      item.direction = (int)StringToInteger(row[4]);
      item.archetype = (int)StringToInteger(row[6]);
      item.openTime = StringToTime(row[7]);
      item.initialVolume = StringToDouble(row[10]);
      item.entryVolume = StringToDouble(row[11]);
      item.exitVolume = StringToDouble(row[12]);
      item.entryPrice = StringToDouble(row[13]);
      item.exitPrice = StringToDouble(row[14]);
      item.initialSL = StringToDouble(row[15]);
      item.initialRPrice = StringToDouble(row[16]);
      item.initialRMoney = StringToDouble(row[17]);
      item.maxProfitMoney = StringToDouble(row[20]);
      item.maxLossMoney = StringToDouble(row[21]);
      item.mfeR = StringToDouble(row[22]);
      item.maeR = StringToDouble(row[23]);
      item.partialStages = (int)StringToInteger(row[24]);
      item.partialFills = (int)StringToInteger(row[25]);
      item.fastProtection = (StringToInteger(row[26]) != 0);
      item.runnerMode = (int)StringToInteger(row[27]);
      item.fixedTPRemoved = (StringToInteger(row[28]) != 0);
      item.slModifyCount = (int)StringToInteger(row[29]);
      item.tpModifyCount = (int)StringToInteger(row[30]);
      item.exitIntent = (int)StringToInteger(row[31]);
      item.actualExitReason = StringToInteger(row[32]);
      item.lastExitDeal = (ulong)StringToInteger(row[33]);
      item.lastExitPrice = StringToDouble(row[34]);
      item.gross = StringToDouble(row[35]);
      item.commission = StringToDouble(row[36]);
      item.swap = StringToDouble(row[37]);
      item.fee = StringToDouble(row[38]);
      item.net = StringToDouble(row[39]);
      item.realizedR = StringToDouble(row[40]);
      item.captureRatio = StringToDouble(row[41]);
      // v1.56时长扩展字段全部追加在旧42列之后；旧档案保持ZeroMemory默认值并显示“未记录”。
      if(ArraySize(row) >= 51)
      {
         item.floatingProfitSeconds = MathMax(StringToDouble(row[42]),0.0);
         item.floatingLossSeconds = MathMax(StringToDouble(row[43]),0.0);
         item.floatingFlatSeconds = MathMax(StringToDouble(row[44]),0.0);
         item.longestFloatingLossSeconds = MathMax(StringToDouble(row[45]),0.0);
         item.firstFloatingProfitTime = (datetime)StringToInteger(row[46]);
         item.floatingTimingObservationStartTime = (datetime)StringToInteger(row[47]);
         item.floatingTimingObservedSeconds = MathMax(StringToDouble(row[48]),0.0);
         item.floatingTimingCoverageRatio = MathMax(0.0,MathMin(StringToDouble(row[49]),1.0));
         item.floatingTimingHasData = (StringToInteger(row[50]) != 0 && item.floatingTimingObservedSeconds > 0.0);
      }
      // v1.56生命周期峰谷字段继续追加在时长字段之后；旧档案保持0并由显示兼容函数兜底。
      if(ArraySize(row) >= 53)
      {
         item.maxLifecycleProfitMoney = MathMax(StringToDouble(row[51]),0.0);
         item.maxLifecycleLossMoney = MathMax(StringToDouble(row[52]),0.0);
      }

      int n = ArraySize(items);
      ArrayResize(items, n+1);
      items[n] = item;
   }
   FileClose(handle);
   SortLifecycleReviewItemsByCloseTimeDesc(items);
}

int FindLifecycleAggregate(LifecycleTradeAggregate &items[], ulong positionId)
{
   for(int i=0; i<ArraySize(items); i++)
      if(items[i].positionId == positionId) return i;
   int n = ArraySize(items);
   ArrayResize(items, n+1);
   ZeroMemory(items[n]);
   items[n].positionId = positionId;
   items[n].direction = -1;
   items[n].templateId = -1;
   items[n].archetype = 短线类型_未知;
   return n;
}

bool LifecyclePositionStillOpen(ulong positionId)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == positionId) return true;
   }
   return false;
}

datetime LifecycleSundayBoundaryBeijing(int year, int month, int occurrence, int hour)
{
   MqlDateTime boundary;
   ZeroMemory(boundary);
   boundary.year=year;
   boundary.mon=month;
   boundary.day=1;

   int sundayDay=0;
   if(occurrence>0)
   {
      datetime firstDayTime=StructToTime(boundary);
      MqlDateTime firstDay;
      if(firstDayTime<=0 || !TimeToStruct(firstDayTime,firstDay)) return 0;
      sundayDay=1+((7-firstDay.day_of_week)%7)+(occurrence-1)*7;
   }
   else
   {
      MqlDateTime nextMonth=boundary;
      nextMonth.mon++;
      if(nextMonth.mon>12)
      {
         nextMonth.mon=1;
         nextMonth.year++;
      }
      datetime lastDayTime=StructToTime(nextMonth)-24*60*60;
      MqlDateTime lastDay;
      if(lastDayTime<=0 || !TimeToStruct(lastDayTime,lastDay)) return 0;
      sundayDay=lastDay.day-lastDay.day_of_week;
   }

   boundary.day=sundayDay;
   boundary.hour=hour;
   return StructToTime(boundary);
}

bool LifecycleLondonSummerTime(datetime beijingTime)
{
   MqlDateTime value;
   if(beijingTime<=0 || !TimeToStruct(beijingTime,value)) return false;
   // 英国夏令时：3月最后一个周日01:00 UTC至10月最后一个周日01:00 UTC。
   datetime starts=LifecycleSundayBoundaryBeijing(value.year,3,-1,9);
   datetime ends=LifecycleSundayBoundaryBeijing(value.year,10,-1,9);
   return (starts>0 && ends>starts && beijingTime>=starts && beijingTime<ends);
}

bool LifecycleNewYorkSummerTime(datetime beijingTime)
{
   MqlDateTime value;
   if(beijingTime<=0 || !TimeToStruct(beijingTime,value)) return false;
   // 美国夏令时：3月第二个周日02:00 EST至11月第一个周日02:00 EDT。
   datetime starts=LifecycleSundayBoundaryBeijing(value.year,3,2,15);
   datetime ends=LifecycleSundayBoundaryBeijing(value.year,11,1,14);
   return (starts>0 && ends>starts && beijingTime>=starts && beijingTime<ends);
}

bool LifecycleSessionContainsSeconds(int currentSeconds, int startsAt, int endsAt)
{
   if(startsAt<endsAt) return (currentSeconds>=startsAt && currentSeconds<endsAt);
   return (currentSeconds>=startsAt || currentSeconds<endsAt);
}

int LifecycleBeijingSession(datetime serverTime)
{
   datetime tradeServerNow = TimeTradeServer();
   if(tradeServerNow <= 0) tradeServerNow = TimeCurrent();
   datetime gmtNow = TimeGMT();
   int serverOffset = (int)(tradeServerNow-gmtNow);
   datetime bjTime = serverTime-serverOffset+北京UTC偏移小时*3600;
   MqlDateTime dt;
   TimeToStruct(bjTime, dt);
   int currentSeconds=dt.hour*3600+dt.min*60+dt.sec;
   bool londonSummer=LifecycleLondonSummerTime(bjTime);
   bool newYorkSummer=LifecycleNewYorkSummerTime(bjTime);

   int asiaStarts=7*3600;
   int asiaEnds=16*3600;
   int londonStarts=(londonSummer?15:16)*3600;
   int londonEnds=(londonSummer?0:1)*3600;
   int newYorkStarts=(newYorkSummer?20:21)*3600;
   int newYorkEnds=(newYorkSummer?5:6)*3600;

   // 主要交易时段存在重叠；单一标签和统计桶按最新开盘市场优先归类。
   if(LifecycleSessionContainsSeconds(currentSeconds,newYorkStarts,newYorkEnds)) return 2;
   if(LifecycleSessionContainsSeconds(currentSeconds,londonStarts,londonEnds)) return 1;
   if(LifecycleSessionContainsSeconds(currentSeconds,asiaStarts,asiaEnds)) return 0;
   return 3;
}

void AccumulatePerformanceBucket(StatsPerformanceBucket &bucket,
                                 const LifecycleTradeAggregate &trade)
{
   bucket.trades++;
   bucket.netProfit += trade.net;
   // 与统计总览完全复用同一胜负阈值，平局继续计入完整交易分母。
   if(trade.net > 0.005) bucket.wins++;
   else if(trade.net < -0.005) bucket.losses++;
   else bucket.breakevens++;
   if(trade.initialRMoney > 0.0)
   {
      bucket.riskKnownTrades++;
      bucket.realizedR += trade.realizedR;
   }
   if(trade.closeTime > trade.openTime)
   {
      bucket.totalHoldMinutes += (double)(trade.closeTime-trade.openTime)/60.0;
      bucket.holdKnownTrades++;
   }
}

void SortLifecycleTradesByCloseTime(LifecycleTradeAggregate &items[])
{
   for(int i=1; i<ArraySize(items); i++)
   {
      LifecycleTradeAggregate key = items[i];
      int j = i-1;
      while(j >= 0 && items[j].closeTime > key.closeTime)
      {
         items[j+1] = items[j];
         j--;
      }
      items[j+1] = key;
   }
}

void SortLifecycleTrendItemsByCloseTime(LifecycleTrendItem &items[])
{
   for(int i=1; i<ArraySize(items); i++)
   {
      LifecycleTrendItem key = items[i];
      int j = i-1;
      while(j >= 0 && (items[j].closeTime > key.closeTime ||
                       (items[j].closeTime == key.closeTime && items[j].positionId > key.positionId)))
      {
         items[j+1] = items[j];
         j--;
      }
      items[j+1] = key;
   }
}

void CollectLifecycleExecutionEvents(datetime serverStart, datetime serverEnd, LifecycleStats &st)
{
   int handle = FileOpen(TradeJournalFileName("TradeLifecycle"),
                         FILE_CSV|FILE_READ|FILE_SHARE_READ|FILE_COMMON|FILE_ANSI, ',');
   if(handle == INVALID_HANDLE) return;
   string row[];
   bool firstRow = true;
   while(ReadLifecycleCsvRow(handle, row))
   {
      if(firstRow) { firstRow=false; continue; }
      if(ArraySize(row) < 9 || row[4] != _Symbol) continue;
      datetime eventTime = StringToTime(row[0]);
      if(eventTime < serverStart || eventTime >= serverEnd) continue;
      int templateId = (int)StringToInteger(row[5]);
      if(!LifecycleTemplateMatches(templateId)) continue;
      string eventName = row[1];
      if(eventName == "SLTP_MODIFY_REQUESTED") st.sltpRequested++;
      else if(eventName == "SLTP_MODIFY_CONFIRMED") st.sltpConfirmed++;
      else if(eventName == "SLTP_MODIFY_FAILED") st.sltpFailed++;
      else if(eventName == "PARTIAL_CLOSE_REQUESTED") st.partialRequested++;
      else if(eventName == "PARTIAL_CLOSE_FILL") st.partialFillEvents++;
      else if(eventName == "FULL_CLOSE_REQUESTED") st.fullCloseRequested++;
      else if(eventName == "FULL_CLOSE_FILL" || eventName == "FULL_CLOSE_FILLED") st.fullCloseFilled++;
      else if(eventName == "FULL_CLOSE_FAILED") st.fullCloseFailed++;
      else if(eventName == "FAST_PROTECTION_REQUESTED") st.fastProtectionRequested++;
      else if(eventName == "FAST_PROTECTION_CONFIRMED") st.fastProtectionConfirmed++;
      else if(eventName == "FAST_PROTECTION_FAILED") st.fastProtectionFailed++;
   }
   FileClose(handle);
}

void CalculateLifecycleStatsByBJRange(datetime bjStart, datetime bjEnd, LifecycleStats &st)
{
   ZeroMemory(st);
   生命周期走势缓存有效 = false;
   ArrayResize(生命周期走势缓存, 0);
   st.bjDate = bjStart;
   GetBeijingRangeServerRange(bjStart, bjEnd, st.serverStart, st.serverEnd);

   LifecycleTradeAggregate all[];
   ArrayResize(all, 0);
   datetime now=TimeCurrent();
   bool completedCacheMatch=生命周期完整交易缓存有效 &&
                            生命周期完整交易缓存服务器开始==st.serverStart &&
                            生命周期完整交易缓存服务器结束==st.serverEnd &&
                            (生命周期完整交易缓存筛选复用 || now-生命周期完整交易缓存时间<=30);
   if(completedCacheMatch)
   {
      CopyLifecycleTradesExact(all,生命周期完整交易缓存);
      生命周期完整交易缓存筛选复用=false;
   }
   else
   {
      // 短线生命周期通常远短于90天；额外回看用于把跨日仓位的入场费用一并纳入。
      datetime searchStart = st.serverStart - 90*86400;
      if(!HistorySelect(searchStart, st.serverEnd)) return;

      LifecycleSummaryMeta meta[];
      LoadLifecycleSummaryMetadata(meta);
      LifecycleTradeAggregate raw[];
      ArrayResize(raw,0);
      int dealsTotal = HistoryDealsTotal();
      for(int i=0; i<dealsTotal; i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
         ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
         if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
         ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
         if(positionId == 0) continue;
         long magic = (long)HistoryDealGetInteger(deal, DEAL_MAGIC);
         string comment = HistoryDealGetString(deal, DEAL_COMMENT);
         if(magic == 手机标记挂单Magic && StringFind(comment, "SMA_MARK_") == 0) continue;

         int idx = FindLifecycleAggregate(raw, positionId);
         ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
         datetime dealTime = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
         double volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
         double price = HistoryDealGetDouble(deal, DEAL_PRICE);
         raw[idx].gross += HistoryDealGetDouble(deal, DEAL_PROFIT);
         raw[idx].commission += HistoryDealGetDouble(deal, DEAL_COMMISSION);
         raw[idx].swap += HistoryDealGetDouble(deal, DEAL_SWAP);
         raw[idx].fee += HistoryDealGetDouble(deal, DEAL_FEE);

         if(entry == DEAL_ENTRY_IN)
         {
            raw[idx].entryVolume += volume;
            raw[idx].entryValue += volume*price;
            if(raw[idx].openTime == 0 || dealTime < raw[idx].openTime) raw[idx].openTime = dealTime;
            raw[idx].direction = (dealType == DEAL_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
            raw[idx].entryMagic = magic;
            if(MagicInScope(magic)) raw[idx].entryScope = true;
         }
         else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
         {
            raw[idx].exitVolume += volume;
            raw[idx].exitValue += volume*price;
            raw[idx].exitDeals++;
            if(dealTime >= raw[idx].closeTime) raw[idx].closeTime = dealTime;
         }
      }

      double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(volumeStep <= 0.0) volumeStep = 0.01;
      for(int i=0; i<ArraySize(raw); i++)
      {
         if(raw[i].entryVolume <= 0.0 || raw[i].exitVolume <= 0.0 || raw[i].closeTime < st.serverStart ||
            raw[i].closeTime >= st.serverEnd || LifecyclePositionStillOpen(raw[i].positionId)) continue;
         if(raw[i].exitVolume + volumeStep*0.5 < raw[i].entryVolume) continue;
         if(统计页仅统计受管Magic && !raw[i].entryScope) continue;
         int mi = FindSummaryMeta(meta, raw[i].positionId);
         if(mi >= 0)
         {
            raw[i].templateId = meta[mi].templateId;
            raw[i].archetype = meta[mi].archetype;
            raw[i].initialRMoney = meta[mi].initialRMoney;
            raw[i].mfeR = meta[mi].mfeR;
            raw[i].maeR = meta[mi].maeR;
            raw[i].realizedR = meta[mi].realizedR;
            raw[i].captureRatio = meta[mi].captureRatio;
            raw[i].partialStages = meta[mi].partialStages;
            raw[i].partialFills = meta[mi].partialFills;
            raw[i].fastProtection = meta[mi].fastProtection;
            raw[i].runnerMode = meta[mi].runnerMode;
            raw[i].fixedTPRemoved = meta[mi].fixedTPRemoved;
            raw[i].slModifyCount = meta[mi].slModifyCount;
            raw[i].tpModifyCount = meta[mi].tpModifyCount;
            // Summary由完整生命周期结算产生，优先于窗口内重新拼接Deal，尤其适用于Netting反转分段。
            raw[i].gross = meta[mi].gross;
            raw[i].commission = meta[mi].commission;
            raw[i].swap = meta[mi].swap;
            raw[i].fee = meta[mi].fee;
            raw[i].net = meta[mi].net;
         }
         if(mi < 0) raw[i].net = raw[i].gross+raw[i].commission+raw[i].swap+raw[i].fee;
         int n=ArraySize(all);
         ArrayResize(all,n+1);
         all[n]=raw[i];
      }
      CopyLifecycleTradesExact(生命周期完整交易缓存,all);
      生命周期完整交易缓存有效=true;
      生命周期完整交易缓存时间=now;
      生命周期完整交易缓存服务器开始=st.serverStart;
      生命周期完整交易缓存服务器结束=st.serverEnd;
   }

   LifecycleTradeAggregate included[];
   ArrayResize(included, 0);
   for(int i=0; i<ArraySize(all); i++)
   {
      // 配置对比和配置×时段矩阵必须在当前页面筛选之前聚合，确保上表始终
      // 比较四种冻结配置；未识别模板按业务规则进入手动桶。
      int templateBucket = LifecycleTemplatePerformanceBucket(all[i].templateId);
      int sessionBucket = LifecycleBeijingSession(all[i].openTime);
      AccumulatePerformanceBucket(st.templatePerformance[templateBucket], all[i]);
      AccumulatePerformanceBucket(st.sessionPerformanceAll[sessionBucket], all[i]);
      AccumulatePerformanceBucket(st.sessionPerformanceByTemplate[templateBucket][sessionBucket], all[i]);

      if(!LifecycleTemplateMatches(all[i].templateId)) continue;
      int n = ArraySize(included);
      ArrayResize(included, n+1);
      included[n] = all[i];
   }
   SortLifecycleTradesByCloseTime(included);

   int trendCount=ArraySize(included);
   ArrayResize(生命周期走势缓存,trendCount);
   for(int trendIndex=0; trendIndex<trendCount; trendIndex++)
   {
      生命周期走势缓存[trendIndex].positionId=included[trendIndex].positionId;
      生命周期走势缓存[trendIndex].closeTime=included[trendIndex].closeTime;
      生命周期走势缓存[trendIndex].netProfit=included[trendIndex].net;
   }
   SortLifecycleTrendItemsByCloseTime(生命周期走势缓存);
   生命周期走势缓存有效=true;
   生命周期走势缓存周期=(int)当前统计周期;
   生命周期走势缓存筛选=(int)当前统计筛选;
   生命周期走势缓存日偏移=统计日期偏移天数;
   生命周期走势缓存周偏移=统计周偏移周数;
   生命周期走势缓存月偏移=统计月偏移月数;
   生命周期走势缓存服务器开始=st.serverStart;
   生命周期走势缓存服务器结束=st.serverEnd;

   double winSum=0.0, lossSum=0.0, cumMoney=0.0, cumR=0.0;
   int currentStreak=0, rCount=0, mfeCount=0, maeCount=0;
   for(int i=0; i<ArraySize(included); i++)
   {
      LifecycleTradeAggregate tr = included[i];
      st.trades++;
      st.exitDeals += tr.exitDeals;
      st.entryVolume += tr.entryVolume;
      st.exitVolume += tr.exitVolume;
      st.netProfit += tr.net;
      st.commission += tr.commission;
      st.swap += tr.swap;
      st.fee += tr.fee;
      st.totalTradingCost += MathMax(0.0,-tr.commission)+MathMax(0.0,-tr.swap)+MathMax(0.0,-tr.fee);
      bool priceDiffKnown=(tr.entryVolume>0.0 && tr.exitVolume>0.0 &&
                           (tr.direction==POSITION_TYPE_BUY || tr.direction==POSITION_TYPE_SELL));
      double tradePriceDiff=0.0;
      if(priceDiffKnown)
      {
         double weightedEntryPrice=tr.entryValue/tr.entryVolume;
         double weightedExitPrice=tr.exitValue/tr.exitVolume;
         tradePriceDiff=tr.direction==POSITION_TYPE_BUY?
                        weightedExitPrice-weightedEntryPrice:
                        weightedEntryPrice-weightedExitPrice;
         st.priceDiff += tradePriceDiff;
      }
      bool holdTimeKnown = (tr.openTime > 0 && tr.closeTime > tr.openTime);
      double holdMinutes = holdTimeKnown ? (double)(tr.closeTime-tr.openTime)/60.0 : 0.0;
      st.totalHoldMinutes += holdMinutes;
      if(holdTimeKnown) st.holdKnownTrades++;
      st.maxHoldMinutes = MathMax(st.maxHoldMinutes, holdMinutes);
      if(tr.direction == POSITION_TYPE_BUY) { st.buyTrades++; st.buyProfit += tr.net; }
      else if(tr.direction == POSITION_TYPE_SELL) { st.sellTrades++; st.sellProfit += tr.net; }
      if(!st.bestTradeValid || tr.net>st.bestProfit)
      {
         st.bestTradeValid=true;
         st.bestProfit=tr.net;
         st.bestTradePositionId=tr.positionId;
         st.bestTradeDirection=tr.direction;
         st.bestTradeVolume=tr.entryVolume;
         st.bestTradePriceDiff=tradePriceDiff;
      }
      if(!st.worstTradeValid || tr.net<st.worstProfit)
      {
         st.worstTradeValid=true;
         st.worstProfit=tr.net;
         st.worstTradePositionId=tr.positionId;
         st.worstTradeDirection=tr.direction;
         st.worstTradeVolume=tr.entryVolume;
         st.worstTradePriceDiff=tradePriceDiff;
      }
      if(tr.net > 0.005)
      {
         st.wins++; st.grossProfit += tr.net; winSum += tr.net; currentStreak=0;
         if(holdTimeKnown)
         {
            st.winningHoldMinutes += holdMinutes;
            st.winningHoldKnownTrades++;
         }
      }
      else if(tr.net < -0.005)
      {
         st.losses++; st.grossLoss += tr.net; lossSum += tr.net; currentStreak++;
         st.maxLossStreak = MathMax(st.maxLossStreak, currentStreak);
         if(holdTimeKnown)
         {
            st.losingHoldMinutes += holdMinutes;
            st.losingHoldKnownTrades++;
         }
      }
      else { st.breakevens++; currentStreak=0; }

      cumMoney += tr.net;
      st.equityPeak = MathMax(st.equityPeak, cumMoney);
      st.maxRealizedDrawdown = MathMax(st.maxRealizedDrawdown, st.equityPeak-cumMoney);

      if(tr.templateId >= 0) st.metadataTrades++;
      if(tr.initialRMoney > 0.0)
      {
         st.riskKnownTrades++;
         st.avgInitialRMoney += tr.initialRMoney;
         st.totalRealizedR += tr.realizedR;
         cumR += tr.realizedR;
         st.rPeak = MathMax(st.rPeak, cumR);
         st.maxRDrawdown = MathMax(st.maxRDrawdown, st.rPeak-cumR);
         rCount++;
      }
      if(tr.mfeR > 0.0) { st.avgMfeR += tr.mfeR; mfeCount++; }
      if(tr.maeR > 0.0) { st.avgMaeR += tr.maeR; maeCount++; }
      if(tr.captureRatio != 0.0) { st.avgCaptureRatio += tr.captureRatio; st.captureKnownTrades++; }
      if(tr.partialStages > 0) st.partialTrades++;
      st.partialStagesTotal += tr.partialStages;
      st.partialFillTotal += tr.partialFills;
      if(tr.fastProtection) st.fastProtectionTrades++;
      if(tr.partialStages > 0)
      {
         if(tr.runnerMode == 短线尾仓_结构追踪) st.runnerStructureTrades++;
         else if(tr.runnerMode == 短线尾仓_箱体目标) st.runnerBoxTrades++;
         else if(tr.runnerMode == 短线尾仓_快速退出) st.runnerFastExitTrades++;
         else st.runnerFixedTrades++;
      }
      if(tr.fixedTPRemoved) st.fixedTPRemovedTrades++;
      st.slModifyTotal += tr.slModifyCount;
      st.tpModifyTotal += tr.tpModifyCount;
      if(tr.archetype >= 0 && tr.archetype < 6)
      {
         st.archetypeTrades[tr.archetype]++;
         st.archetypeProfit[tr.archetype] += tr.net;
         if(tr.initialRMoney > 0.0) st.archetypeR[tr.archetype] += tr.realizedR;
      }
      int session = LifecycleBeijingSession(tr.openTime);
      st.sessionTrades[session]++;
      st.sessionProfit[session] += tr.net;
      if(tr.initialRMoney > 0.0) st.sessionR[session] += tr.realizedR;
   }
   st.currentLossStreak = currentStreak;
   st.avgWin = st.wins > 0 ? winSum/st.wins : 0.0;
   st.avgLoss = st.losses > 0 ? lossSum/st.losses : 0.0;
   st.profitFactor = MathAbs(st.grossLoss) > 0.0 ? st.grossProfit/MathAbs(st.grossLoss) : 0.0;
   st.payoffRatio = MathAbs(st.avgLoss) > 0.0 ? st.avgWin/MathAbs(st.avgLoss) : 0.0;
   if(st.riskKnownTrades > 0) st.avgInitialRMoney /= st.riskKnownTrades;
   if(mfeCount > 0) st.avgMfeR /= mfeCount;
   if(maeCount > 0) st.avgMaeR /= maeCount;
   if(st.captureKnownTrades > 0) st.avgCaptureRatio /= st.captureKnownTrades;
   CollectLifecycleExecutionEvents(st.serverStart, st.serverEnd, st);
}

void InvalidateLifecycleStatsCache(bool preserveCompletedTrades=false)
{
   生命周期统计缓存有效 = false;
   生命周期复盘缓存有效 = false;
   生命周期走势缓存有效 = false;
   if(!preserveCompletedTrades)
   {
      生命周期完整交易缓存有效=false;
      生命周期完整交易缓存筛选复用=false;
      ArrayResize(生命周期完整交易缓存,0);
   }
   else if(生命周期完整交易缓存有效)
      生命周期完整交易缓存筛选复用=true;
   // ArrayCopy 在源数组为空时不会替目标动态数组缩容；不清空会让上一日期的
   // 复盘条目在下一次定时刷新中重新回显。
   ArrayResize(生命周期复盘缓存, 0);
   ArrayResize(生命周期走势缓存, 0);
}

void GetCurrentLifecycleStatsRange(datetime &bjStart, datetime &bjEnd)
{
   bjStart = 0;
   bjEnd = 0;
   if(当前统计周期 == 统计_日)
   {
      bjStart = GetBJTodayZero()+统计日期偏移天数*86400;
      bjEnd = bjStart+86400;
   }
   else if(当前统计周期 == 统计_周)
   {
      bjStart = GetBJMonday(GetBJTodayZero())+统计周偏移周数*7*86400;
      bjEnd = bjStart+5*86400;
   }
   else
   {
      bjStart = AddBJMonths(GetBJMonthStart(GetBJTodayZero()), 统计月偏移月数);
      bjEnd = AddBJMonths(bjStart, 1);
   }
}

void GetCurrentLifecycleTrendItems(const LifecycleStats &stats, LifecycleTrendItem &items[])
{
   bool cacheMatch=生命周期走势缓存有效 &&
                   生命周期走势缓存服务器开始==stats.serverStart &&
                   生命周期走势缓存服务器结束==stats.serverEnd &&
                   生命周期走势缓存周期==(int)当前统计周期 &&
                   生命周期走势缓存筛选==(int)当前统计筛选 &&
                   生命周期走势缓存日偏移==统计日期偏移天数 &&
                   生命周期走势缓存周偏移==统计周偏移周数 &&
                   生命周期走势缓存月偏移==统计月偏移月数;
   ArrayResize(items,0);
   if(cacheMatch) ArrayCopy(items,生命周期走势缓存);
}

void GetCurrentLifecycleReviewItems(const LifecycleStats &stats, LifecycleReviewItem &items[])
{
   datetime now = TimeCurrent();
   bool cacheMatch = 生命周期复盘缓存有效 &&
                     生命周期复盘缓存服务器开始 == stats.serverStart &&
                     生命周期复盘缓存服务器结束 == stats.serverEnd &&
                     生命周期复盘缓存周期 == (int)当前统计周期 &&
                     生命周期复盘缓存筛选 == (int)当前统计筛选 &&
                     生命周期复盘缓存日偏移 == 统计日期偏移天数 &&
                     生命周期复盘缓存周偏移 == 统计周偏移周数 &&
                     生命周期复盘缓存月偏移 == 统计月偏移月数 &&
                     now-生命周期复盘缓存时间 <= 30;
   if(cacheMatch)
   {
      CopyLifecycleReviewItemsExact(items,生命周期复盘缓存);
      return;
   }

   // 直接复用统计页实际使用的服务器范围，避免复盘与日/周/月统计跨到不同日期。
   LoadLifecycleReviewItemsByServerRange(stats.serverStart, stats.serverEnd, items);
   CopyLifecycleReviewItemsExact(生命周期复盘缓存,items);
   生命周期复盘缓存有效 = true;
   生命周期复盘缓存时间 = now;
   生命周期复盘缓存周期 = (int)当前统计周期;
   生命周期复盘缓存筛选 = (int)当前统计筛选;
   生命周期复盘缓存日偏移 = 统计日期偏移天数;
   生命周期复盘缓存周偏移 = 统计周偏移周数;
   生命周期复盘缓存月偏移 = 统计月偏移月数;
   生命周期复盘缓存服务器开始 = stats.serverStart;
   生命周期复盘缓存服务器结束 = stats.serverEnd;
}

void GetCurrentLifecycleStats(LifecycleStats &st)
{
   datetime now = TimeCurrent();
   if(生命周期统计缓存有效 && 生命周期缓存周期 == (int)当前统计周期 &&
      生命周期缓存筛选 == (int)当前统计筛选 && 生命周期缓存日偏移 == 统计日期偏移天数 &&
      生命周期缓存周偏移 == 统计周偏移周数 && 生命周期缓存月偏移 == 统计月偏移月数 &&
      now-生命周期统计缓存时间 <= 30)
   {
      st = 生命周期统计缓存;
      return;
   }

   datetime bjStart=0, bjEnd=0;
   GetCurrentLifecycleStatsRange(bjStart, bjEnd);
   CalculateLifecycleStatsByBJRange(bjStart, bjEnd, st);
   生命周期统计缓存 = st;
   生命周期统计缓存有效 = true;
   生命周期统计缓存时间 = now;
   生命周期缓存周期 = (int)当前统计周期;
   生命周期缓存筛选 = (int)当前统计筛选;
   生命周期缓存日偏移 = 统计日期偏移天数;
   生命周期缓存周偏移 = 统计周偏移周数;
   生命周期缓存月偏移 = 统计月偏移月数;
}

#endif
