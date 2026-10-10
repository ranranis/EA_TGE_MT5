// 独立副图：RSI、MACD、ATR、ADX/DMI或随机KD，全部仅用于看盘。
#property strict
#property indicator_separate_window
#property indicator_buffers 3
#property indicator_plots 3
#property indicator_type1 DRAW_LINE
#property indicator_type2 DRAW_LINE
#property indicator_type3 DRAW_LINE
#property indicator_color1 clrDeepSkyBlue
#property indicator_color2 clrOrange
#property indicator_color3 clrHotPink
#property indicator_width1 2
input int ViewKind=0; // 0 RSI，1 MACD，2 ATR，3 ADX/DMI，4随机KD（不包含J线）
input string ViewName="TGE.View";
input int ViewPeriod=14;
input int ViewFast=12;
input int ViewSlow=26;
input int ViewSignal=9;
input ENUM_APPLIED_PRICE ViewPrice=PRICE_CLOSE;
input int ViewD=3;
input int ViewSlowing=3;
input double ViewStrength=25.0;
double line0[],line1[],line2[];
int viewHandle=INVALID_HANDLE;
int OnInit()
{
   if(ViewKind<0 || ViewKind>4 || ViewPeriod<1 || ViewPeriod>10000 ||
      (ViewKind==1 && (ViewFast<1 || ViewSlow<=ViewFast || ViewSlow>10000 || ViewSignal<1 || ViewSignal>10000)) ||
      (ViewKind==3 && (!MathIsValidNumber(ViewStrength) || ViewStrength<=0 || ViewStrength>=100)) ||
      (ViewKind==4 && (ViewD<1 || ViewD>10000 || ViewSlowing<1 || ViewSlowing>10000))) return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,line0,INDICATOR_DATA); SetIndexBuffer(1,line1,INDICATOR_DATA); SetIndexBuffer(2,line2,INDICATOR_DATA);
   IndicatorSetString(INDICATOR_SHORTNAME,ViewName);
   IndicatorSetInteger(INDICATOR_DIGITS,ViewKind==0 || ViewKind>=3 ? 2 : _Digits);
   for(int i=0;i<3;i++) PlotIndexSetDouble(i,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,ViewKind==1 ? ViewSlow+ViewSignal-2 :
                       ViewKind==3 ? 2*ViewPeriod : ViewKind==4 ? ViewPeriod+ViewD+ViewSlowing-3 : ViewPeriod);
   PlotIndexSetString(0,PLOT_LABEL,ViewKind==0 ? "RSI"+IntegerToString(ViewPeriod) :
                      ViewKind==1 ? "MACD主线" : ViewKind==2 ? "ATR"+IntegerToString(ViewPeriod) : ViewKind==3 ? "ADX" : "%K");
   PlotIndexSetString(1,PLOT_LABEL,ViewKind==3 ? "+DI" : ViewKind==4 ? "%D" : "MACD信号");
   PlotIndexSetString(2,PLOT_LABEL,"-DI");
   if(ViewKind==0 || ViewKind==2)
   { PlotIndexSetInteger(1,PLOT_DRAW_TYPE,DRAW_NONE); PlotIndexSetInteger(1,PLOT_SHOW_DATA,false); }
   if(ViewKind!=3)
   { PlotIndexSetInteger(2,PLOT_DRAW_TYPE,DRAW_NONE); PlotIndexSetInteger(2,PLOT_SHOW_DATA,false); }
   if(ViewKind==0 || ViewKind>=3)
   { IndicatorSetDouble(INDICATOR_MINIMUM,0); IndicatorSetDouble(INDICATOR_MAXIMUM,100); }
   if(ViewKind==0)
   {
      IndicatorSetInteger(INDICATOR_LEVELS,2);
      IndicatorSetDouble(INDICATOR_LEVELVALUE,0,30); IndicatorSetDouble(INDICATOR_LEVELVALUE,1,70);
      viewHandle=iRSI(_Symbol,_Period,ViewPeriod,ViewPrice);
   }
   else if(ViewKind==1)
   {
      PlotIndexSetInteger(0,PLOT_DRAW_TYPE,DRAW_HISTOGRAM);
      PlotIndexSetInteger(0,PLOT_LINE_COLOR,clrMediumTurquoise);
      PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,ViewSlow+ViewSignal-2);
      IndicatorSetInteger(INDICATOR_LEVELS,1); IndicatorSetDouble(INDICATOR_LEVELVALUE,0,0);
      viewHandle=iMACD(_Symbol,_Period,ViewFast,ViewSlow,ViewSignal,ViewPrice);
   }
   else if(ViewKind==2)
   {
      PlotIndexSetInteger(0,PLOT_LINE_COLOR,clrGold); IndicatorSetDouble(INDICATOR_MINIMUM,0);
      viewHandle=iATR(_Symbol,_Period,ViewPeriod);
   }
   else if(ViewKind==3)
   {
      PlotIndexSetInteger(0,PLOT_LINE_COLOR,clrGold); PlotIndexSetInteger(1,PLOT_LINE_COLOR,clrMediumTurquoise);
      PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,ViewPeriod); PlotIndexSetInteger(2,PLOT_DRAW_BEGIN,ViewPeriod);
      IndicatorSetInteger(INDICATOR_LEVELS,1); IndicatorSetDouble(INDICATOR_LEVELVALUE,0,ViewStrength);
      viewHandle=iADX(_Symbol,_Period,ViewPeriod);
   }
   else
   {
      PlotIndexSetInteger(1,PLOT_LINE_STYLE,STYLE_DOT);
      PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,ViewPeriod+ViewD+ViewSlowing-3);
      IndicatorSetInteger(INDICATOR_LEVELS,2);
      IndicatorSetDouble(INDICATOR_LEVELVALUE,0,20); IndicatorSetDouble(INDICATOR_LEVELVALUE,1,80);
      viewHandle=iStochastic(_Symbol,_Period,ViewPeriod,ViewD,ViewSlowing,MODE_SMA,STO_LOWHIGH);
   }
   return viewHandle==INVALID_HANDLE ? INIT_FAILED : INIT_SUCCEEDED;
}
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(viewHandle==INVALID_HANDLE || BarsCalculated(viewHandle)<rates_total) return prev_calculated;
   int count=prev_calculated<=0 || prev_calculated>rates_total ? rates_total : rates_total-prev_calculated+1;
   if(CopyBuffer(viewHandle,0,0,count,line0)!=count) return 0;
   if((ViewKind==1 || ViewKind==3 || ViewKind==4) && CopyBuffer(viewHandle,1,0,count,line1)!=count) return 0;
   if(ViewKind==3 && CopyBuffer(viewHandle,2,0,count,line2)!=count) return 0;
   return rates_total;
}
void OnDeinit(const int reason)
{
   if(viewHandle!=INVALID_HANDLE) IndicatorRelease(viewHandle);
}
