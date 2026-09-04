#ifndef SMA_CORE_SYMBOL_UTILS_MQH
#define SMA_CORE_SYMBOL_UTILS_MQH

datetime lastM1BarTime = 0;
datetime lastM5BarTime = 0;
bool currentTickHasNewM1Bar = false;
bool currentTickHasNewM5Bar = false;

bool IsNewBar(ENUM_TIMEFRAMES timeframe, datetime &lastBarTime)
{
   datetime currentBarTime = iTime(_Symbol, timeframe, 0);
   if(currentBarTime <= 0) return false;
   if(lastBarTime == 0)
   {
      lastBarTime = currentBarTime;
      return false;
   }
   if(currentBarTime == lastBarTime) return false;
   lastBarTime = currentBarTime;
   return true;
}

#endif
