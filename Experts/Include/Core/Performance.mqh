#ifndef SMA_CORE_PERFORMANCE_MQH
#define SMA_CORE_PERFORMANCE_MQH

enum PerformanceMetric
{
   PERF_ON_TICK = 0,
   PERF_ON_TIMER,
   PERF_MANAGE_POSITION,
   PERF_MANAGE_POSITION_SINGLE,
   PERF_BUILD_SHORT_CONTEXT,
   PERF_UPDATE_SUPPORT_RESISTANCE,
   PERF_BOX_UPDATE,
   PERF_PANEL_REFRESH,
   PERF_SHORT_STATE_SAVE,
   PERF_HISTORY_QUERY,
   PERF_TRADE_JOURNAL,
   PERF_ON_TRADE_TRANSACTION,
   PERF_METRIC_COUNT
};

struct PerformanceCounter
{
   ulong count;
   ulong totalUs;
   ulong maxUs;
};

PerformanceCounter performanceCounters[PERF_METRIC_COUNT];
datetime performanceLastFlushTime = 0;

string PerformanceMetricName(int metric)
{
   if(metric == PERF_ON_TICK) return "OnTick";
   if(metric == PERF_ON_TIMER) return "OnTimer";
   if(metric == PERF_MANAGE_POSITION) return "ManagePosition";
   if(metric == PERF_MANAGE_POSITION_SINGLE) return "ManagePositionSingle";
   if(metric == PERF_BUILD_SHORT_CONTEXT) return "BuildShortLineMarketContext";
   if(metric == PERF_UPDATE_SUPPORT_RESISTANCE) return "UpdateSupportResistance";
   if(metric == PERF_BOX_UPDATE) return "ShortBoxUpdate";
   if(metric == PERF_PANEL_REFRESH) return "RefreshPanel";
   if(metric == PERF_SHORT_STATE_SAVE) return "ShortStateSave";
   if(metric == PERF_HISTORY_QUERY) return "HistoryQuery";
   if(metric == PERF_TRADE_JOURNAL) return "TradeJournal";
   if(metric == PERF_ON_TRADE_TRANSACTION) return "OnTradeTransaction";
   return "Unknown";
}

void PerfRecord(int metric, ulong elapsedUs)
{
   if(!启用性能统计 || metric < 0 || metric >= PERF_METRIC_COUNT) return;
   performanceCounters[metric].count++;
   performanceCounters[metric].totalUs += elapsedUs;
   if(elapsedUs > performanceCounters[metric].maxUs) performanceCounters[metric].maxUs = elapsedUs;
}

class PerformanceScope
{
private:
   int   metricId;
   ulong startUs;
public:
   PerformanceScope(int metric)
   {
      metricId = metric;
      startUs = 启用性能统计 ? GetMicrosecondCount() : 0;
   }
   ~PerformanceScope()
   {
      if(startUs > 0) PerfRecord(metricId, GetMicrosecondCount()-startUs);
   }
};

void PerfFlushIfNeeded()
{
   if(!启用性能统计) return;
   datetime now = TimeCurrent();
   if(performanceLastFlushTime == 0)
   {
      performanceLastFlushTime = now;
      return;
   }
   if(now-performanceLastFlushTime < MathMax(性能统计输出秒数, 10)) return;
   for(int i=0; i<PERF_METRIC_COUNT; i++)
   {
      if(performanceCounters[i].count == 0) continue;
      double averageUs = (double)performanceCounters[i].totalUs/(double)performanceCounters[i].count;
      PrintFormat("PERF %s count=%I64u avg_us=%.1f max_us=%I64u total_us=%I64u",
                  PerformanceMetricName(i), performanceCounters[i].count, averageUs,
                  performanceCounters[i].maxUs, performanceCounters[i].totalUs);
      performanceCounters[i].count = 0;
      performanceCounters[i].totalUs = 0;
      performanceCounters[i].maxUs = 0;
   }
   performanceLastFlushTime = now;
}

#endif
