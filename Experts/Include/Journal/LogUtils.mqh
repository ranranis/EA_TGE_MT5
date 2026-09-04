#ifndef SMA_JOURNAL_LOG_UTILS_MQH
#define SMA_JOURNAL_LOG_UTILS_MQH

struct RateLimitedLogState
{
   string key;
   datetime lastTime;
   int suppressedCount;
};

RateLimitedLogState rateLimitedLogs[];

bool AllowRateLimitedLog(string key, int intervalSeconds, int &suppressedCount)
{
   suppressedCount = 0;
   datetime now = TimeCurrent();
   if(now <= 0) now = TimeLocal();
   int found = -1;
   for(int i=0; i<ArraySize(rateLimitedLogs); i++)
   {
      if(rateLimitedLogs[i].key == key) { found = i; break; }
   }
   if(found < 0)
   {
      int size = ArraySize(rateLimitedLogs);
      if(size < 64)
      {
         ArrayResize(rateLimitedLogs, size+1);
         found = size;
      }
      else
      {
         found = 0;
         for(int i=1; i<size; i++)
            if(rateLimitedLogs[i].lastTime < rateLimitedLogs[found].lastTime) found = i;
      }
      rateLimitedLogs[found].key = key;
      rateLimitedLogs[found].lastTime = now;
      rateLimitedLogs[found].suppressedCount = 0;
      return true;
   }

   int interval = MathMax(intervalSeconds, 1);
   if(now < rateLimitedLogs[found].lastTime || now-rateLimitedLogs[found].lastTime >= interval)
   {
      suppressedCount = rateLimitedLogs[found].suppressedCount;
      rateLimitedLogs[found].lastTime = now;
      rateLimitedLogs[found].suppressedCount = 0;
      return true;
   }
   rateLimitedLogs[found].suppressedCount++;
   return false;
}

void PrintRateLimited(string key, int intervalSeconds, string message)
{
   int suppressed = 0;
   if(!AllowRateLimitedLog(key, intervalSeconds, suppressed)) return;
   if(suppressed > 0) message += StringFormat(" suppressed=%d", suppressed);
   Print(message);
}

#endif
