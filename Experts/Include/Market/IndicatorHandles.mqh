#ifndef SMA_MARKET_INDICATOR_HANDLES_MQH
#define SMA_MARKET_INDICATOR_HANDLES_MQH

// Instance-local resource ownership only: never cache prices or CopyBuffer results.
enum ManagedIndicatorKind { MANAGED_EMA, MANAGED_ATR, MANAGED_ADX };
struct ManagedIndicatorHandle
{
   ManagedIndicatorKind kind;
   ENUM_TIMEFRAMES timeframe;
   int period;
   int handle;
};
ManagedIndicatorHandle managedIndicatorHandles[];

int GetManagedIndicatorHandle(ManagedIndicatorKind kind, ENUM_TIMEFRAMES timeframe, int period)
{
   period=MathMax(period,1);
   for(int i=0; i<ArraySize(managedIndicatorHandles); i++)
      if(managedIndicatorHandles[i].kind==kind && managedIndicatorHandles[i].timeframe==timeframe &&
         managedIndicatorHandles[i].period==period)
         return managedIndicatorHandles[i].handle;

   int handle=INVALID_HANDLE;
   if(kind==MANAGED_EMA) handle=iMA(_Symbol,timeframe,period,0,MODE_EMA,PRICE_CLOSE);
   else if(kind==MANAGED_ATR) handle=iATR(_Symbol,timeframe,period);
   else if(kind==MANAGED_ADX) handle=iADX(_Symbol,timeframe,period);
   if(handle==INVALID_HANDLE) return INVALID_HANDLE; // A later call retries creation.
   int count=ArraySize(managedIndicatorHandles);
   if(ArrayResize(managedIndicatorHandles,count+1,16)!=count+1)
   {
      IndicatorRelease(handle);
      return INVALID_HANDLE;
   }
   managedIndicatorHandles[count].kind=kind;
   managedIndicatorHandles[count].timeframe=timeframe;
   managedIndicatorHandles[count].period=period;
   managedIndicatorHandles[count].handle=handle;
   return handle;
}

void ReleaseManagedIndicatorHandles()
{
   for(int i=0; i<ArraySize(managedIndicatorHandles); i++)
      if(managedIndicatorHandles[i].handle!=INVALID_HANDLE)
         IndicatorRelease(managedIndicatorHandles[i].handle);
   ArrayResize(managedIndicatorHandles,0);
}

#endif
