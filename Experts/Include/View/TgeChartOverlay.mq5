// 持仓页指标：仅绘图；跨周期MA和日高低只使用图表K线开始时已完成的数据。
#property strict
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots 3
#property indicator_type1 DRAW_LINE
#property indicator_type2 DRAW_LINE
#property indicator_type3 DRAW_LINE
#property indicator_color1 clrGold
#property indicator_color2 clrDeepSkyBlue
#property indicator_color3 clrDeepSkyBlue
#property indicator_width1 2
input int ViewKind=0; // 0/1均线，2布林，3 M5 MA5，4 M15 MA5，5确认分形，6前日高低
input string ViewName="TGE.View";
input int ViewPeriod=20;
input ENUM_MA_METHOD ViewMethod=MODE_EMA;
input ENUM_APPLIED_PRICE ViewPrice=PRICE_CLOSE;
input double ViewDeviation=2.0;
input color ViewColor=clrGold;
double line0[],line1[],line2[];
int viewHandle=INVALID_HANDLE;
int OnInit()
{
   if(ViewKind<0 || ViewKind>6 || ViewPeriod<1 || ViewPeriod>10000 ||
      (ViewKind==2 && (!MathIsValidNumber(ViewDeviation) || ViewDeviation<=0))) return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,line0,INDICATOR_DATA); SetIndexBuffer(1,line1,INDICATOR_DATA); SetIndexBuffer(2,line2,INDICATOR_DATA);
   ArraySetAsSeries(line0,false); ArraySetAsSeries(line1,false); ArraySetAsSeries(line2,false);
   IndicatorSetString(INDICATOR_SHORTNAME,ViewName); IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   for(int i=0;i<3;i++)
   {
      PlotIndexSetDouble(i,PLOT_EMPTY_VALUE,EMPTY_VALUE);
      PlotIndexSetInteger(i,PLOT_DRAW_BEGIN,ViewKind<3 ? ViewPeriod-1 : 0);
      if(i>0 && !(ViewKind==2 || (i==1 && (ViewKind==5 || ViewKind==6))))
      { PlotIndexSetInteger(i,PLOT_DRAW_TYPE,DRAW_NONE); PlotIndexSetInteger(i,PLOT_SHOW_DATA,false); }
   }
   PlotIndexSetString(0,PLOT_LABEL,ViewKind==2 ? "BOLL中轨" : ViewName);
   PlotIndexSetString(1,PLOT_LABEL,"BOLL上轨"); PlotIndexSetString(2,PLOT_LABEL,"BOLL下轨");
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,ViewKind==2 ? clrLightSkyBlue : ViewColor);
   if(ViewKind==3 || ViewKind==4)
   {
      PlotIndexSetString(0,PLOT_LABEL,ViewKind==3 ? "M5 收盘MA5" : "M15 收盘MA5");
      PlotIndexSetInteger(0,PLOT_LINE_STYLE,STYLE_DASH); PlotIndexSetInteger(0,PLOT_LINE_WIDTH,1);
      viewHandle=iMA(_Symbol,ViewKind==3 ? PERIOD_M5 : PERIOD_M15,5,0,MODE_SMA,PRICE_CLOSE);
   }
   else if(ViewKind==5)
   {
      PlotIndexSetInteger(0,PLOT_DRAW_TYPE,DRAW_ARROW); PlotIndexSetInteger(1,PLOT_DRAW_TYPE,DRAW_ARROW);
      PlotIndexSetInteger(0,PLOT_ARROW,217); PlotIndexSetInteger(1,PLOT_ARROW,218);
      PlotIndexSetInteger(0,PLOT_ARROW_SHIFT,-8); PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,8);
      PlotIndexSetInteger(0,PLOT_LINE_COLOR,clrHotPink); PlotIndexSetInteger(1,PLOT_LINE_COLOR,clrMediumTurquoise);
      PlotIndexSetString(0,PLOT_LABEL,"确认上拐点"); PlotIndexSetString(1,PLOT_LABEL,"确认下拐点");
      viewHandle=iFractals(_Symbol,_Period);
   }
   else if(ViewKind==6)
   {
      PlotIndexSetString(0,PLOT_LABEL,"前一交易日高"); PlotIndexSetString(1,PLOT_LABEL,"前一交易日低");
      PlotIndexSetInteger(0,PLOT_LINE_COLOR,clrOrange); PlotIndexSetInteger(1,PLOT_LINE_COLOR,clrDeepSkyBlue);
      for(int i=0;i<2;i++)
      { PlotIndexSetInteger(i,PLOT_LINE_STYLE,STYLE_DASH); PlotIndexSetInteger(i,PLOT_LINE_WIDTH,1); }
      return INIT_SUCCEEDED; // 日高低直接使用CopyRates，不需要指标句柄。
   }
   else viewHandle=ViewKind==2 ? iBands(_Symbol,_Period,ViewPeriod,0,ViewDeviation,ViewPrice) :
                                iMA(_Symbol,_Period,ViewPeriod,0,ViewMethod,ViewPrice);
   return viewHandle==INVALID_HANDLE ? INIT_FAILED : INIT_SUCCEEDED;
}
// 先批量读取来源，再逐根映射；+1排除当时尚未结束的来源K线。
int MapClosedView(const int rates_total,const int from,const datetime &time[])
{
   ENUM_TIMEFRAMES source=ViewKind==6 ? PERIOD_D1 : ViewKind==3 ? PERIOD_M5 : PERIOD_M15;
   int available=Bars(_Symbol,source);
   if(available<2) return 0;
   int oldest=iBarShift(_Symbol,source,time[from],false);
   int needed=oldest<0 ? available : MathMin(available,oldest+2);
   MqlRates bars[]; double values[];
   ArraySetAsSeries(bars,true); ArraySetAsSeries(values,true);
   if(CopyRates(_Symbol,source,0,needed,bars)!=needed) return 0;
   if(ViewKind!=6 && (BarsCalculated(viewHandle)<needed ||
      CopyBuffer(viewHandle,0,0,needed,values)!=needed)) return 0;
   for(int i=from;i<rates_total;i++)
   {
      int current=iBarShift(_Symbol,source,time[i],false),shift=current+1;
      line0[i]=EMPTY_VALUE; line1[i]=EMPTY_VALUE; line2[i]=EMPTY_VALUE;
      if(current<0 || shift>=needed || bars[current].time>time[i]) continue;
      if(ViewKind==6) { line0[i]=bars[shift].high; line1[i]=bars[shift].low; }
      else if(MathIsValidNumber(values[shift])) line0[i]=values[shift];
   }
   return rates_total;
}
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<1) return 0;
   if(ViewKind==3 || ViewKind==4 || ViewKind==6)
   {
      ArraySetAsSeries(time,false);
      int from=prev_calculated<=0 || prev_calculated>rates_total ? 0 : MathMax(prev_calculated-1,0);
      return MapClosedView(rates_total,from,time);
   }
   if(viewHandle==INVALID_HANDLE || BarsCalculated(viewHandle)<rates_total) return prev_calculated;
   int count=prev_calculated<=0 || prev_calculated>rates_total ? rates_total : rates_total-prev_calculated+1;
   // 右侧两根收线后才确认；额外复制最近三根，刷新此前隐藏的分形。
   if(ViewKind==5) count=MathMin(rates_total,count+3);
   if(CopyBuffer(viewHandle,0,0,count,line0)!=count) return 0;
   if((ViewKind==2 || ViewKind==5) && CopyBuffer(viewHandle,1,0,count,line1)!=count) return 0;
   if(ViewKind==2 && CopyBuffer(viewHandle,2,0,count,line2)!=count) return 0;
   if(ViewKind==5)
      for(int i=MathMax(rates_total-count,0);i<rates_total;i++)
      {
         if(i>=rates_total-3 || line0[i]==0 || !MathIsValidNumber(line0[i])) line0[i]=EMPTY_VALUE;
         if(i>=rates_total-3 || line1[i]==0 || !MathIsValidNumber(line1[i])) line1[i]=EMPTY_VALUE;
      }
   return rates_total;
}
void OnDeinit(const int reason)
{
   if(viewHandle!=INVALID_HANDLE) IndicatorRelease(viewHandle);
}
