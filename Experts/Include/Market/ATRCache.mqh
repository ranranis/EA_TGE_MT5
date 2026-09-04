#ifndef SMA_MARKET_ATR_CACHE_MQH
#define SMA_MARKET_ATR_CACHE_MQH

int      atrHandle = INVALID_HANDLE;
datetime 缓存ATRBarTime = 0;
double   缓存ATR值 = 0.0;
bool     缓存ATR有效 = false;

// ATR使用已收M1柱，同一根已收柱内直接复用缓存值。
bool GetATRPrice(double &atr)
{
   atr = 0.0;
   if(atrHandle == INVALID_HANDLE) return false;

   datetime lastClosedM1 = iTime(_Symbol, PERIOD_M1, 1);
   if(缓存ATR有效 && lastClosedM1 > 0 && 缓存ATRBarTime == lastClosedM1)
   {
      atr = 缓存ATR值;
      return (atr > 0.0);
   }

   double buf[];
   ArraySetAsSeries(buf, true);
   if(CopyBuffer(atrHandle, 0, 1, 1, buf) != 1) return false;

   缓存ATR值 = buf[0];
   缓存ATRBarTime = lastClosedM1;
   缓存ATR有效 = (缓存ATR值 > 0.0);
   atr = 缓存ATR值;
   return 缓存ATR有效;
}

#endif
