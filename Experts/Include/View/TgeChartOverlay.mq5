// 持仓页指标：仅绘图；跨周期MA和日高低只使用图表K线开始时已完成的数据。
#property strict
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots 3
#property indicator_type1 DRAW_LINE
#property indicator_type2 DRAW_LINE
#property indicator_type3 DRAW_LINE
#property indicator_color1 C'0,83,138'
#property indicator_color2 C'0,83,138'
#property indicator_color3 C'153,76,0'
#property indicator_width1 2
input int ViewKind=0; // 0/1均线，2布林，3 M5 MA5，4 M15 MA5，5确认分形，6前日高低
input string ViewName="TGE.View";
input int ViewPeriod=20;
input ENUM_MA_METHOD ViewMethod=MODE_EMA;
input ENUM_APPLIED_PRICE ViewPrice=PRICE_CLOSE;
input double ViewDeviation=2.0;
input color ViewColor=C'0,83,138';
input ENUM_LINE_STYLE ViewStyle=STYLE_SOLID;
input int ViewWidth=2;
double line0[],line1[],line2[];
int viewHandle=INVALID_HANDLE;
int OnInit()
{
   if(ViewWidth<1 || ViewWidth>5 || ViewKind<0 || ViewKind>6 || ViewPeriod<1 || ViewPeriod>10000 ||
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
   PlotIndexSetInteger(0,PLOT_LINE_COLOR,ViewKind==2 ? C'65,65,65' : ViewColor);
   PlotIndexSetInteger(0,PLOT_LINE_STYLE,ViewStyle); PlotIndexSetInteger(0,PLOT_LINE_WIDTH,ViewWidth);
   if(ViewKind==2)
   {
      PlotIndexSetInteger(0,PLOT_LINE_STYLE,STYLE_DASH); PlotIndexSetInteger(0,PLOT_LINE_WIDTH,1);
      PlotIndexSetInteger(1,PLOT_LINE_WIDTH,2); PlotIndexSetInteger(2,PLOT_LINE_WIDTH,2);
   }
   if(ViewKind==3 || ViewKind==4)
   {
      PlotIndexSetString(0,PLOT_LABEL,ViewKind==3 ? "M5 收盘MA5" : "M15 收盘MA5");
      PlotIndexSetInteger(0,PLOT_LINE_STYLE,ViewKind==4 ? STYLE_DOT : STYLE_DASH); PlotIndexSetInteger(0,PLOT_LINE_WIDTH,1);
      viewHandle=iMA(_Symbol,ViewKind==3 ? PERIOD_M5 : PERIOD_M15,5,0,MODE_SMA,PRICE_CLOSE);
   }
   else if(ViewKind==5)
   {
      PlotIndexSetInteger(0,PLOT_DRAW_TYPE,DRAW_ARROW); PlotIndexSetInteger(1,PLOT_DRAW_TYPE,DRAW_ARROW);
      PlotIndexSetInteger(0,PLOT_ARROW,217); PlotIndexSetInteger(1,PLOT_ARROW,218);
      PlotIndexSetInteger(0,PLOT_ARROW_SHIFT,-8); PlotIndexSetInteger(1,PLOT_ARROW_SHIFT,8);
      PlotIndexSetInteger(0,PLOT_LINE_COLOR,C'105,52,139'); PlotIndexSetInteger(1,PLOT_LINE_COLOR,C'0,83,138');
      PlotIndexSetInteger(0,PLOT_LINE_WIDTH,2); PlotIndexSetInteger(1,PLOT_LINE_WIDTH,2);
      PlotIndexSetString(0,PLOT_LABEL,"确认上拐点"); PlotIndexSetString(1,PLOT_LABEL,"确认下拐点");
      viewHandle=iFractals(_Symbol,_Period);
   }
   else if(ViewKind==6)
   {
      PlotIndexSetString(0,PLOT_LABEL,"前一交易日高"); PlotIndexSetString(1,PLOT_LABEL,"前一交易日低");
      PlotIndexSetInteger(0,PLOT_LINE_COLOR,C'105,52,139'); PlotIndexSetInteger(1,PLOT_LINE_COLOR,C'45,45,45');
      for(int i=0;i<2;i++)
      { PlotIndexSetInteger(i,PLOT_LINE_STYLE,i==0 ? STYLE_SOLID : STYLE_DOT); PlotIndexSetInteger(i,PLOT_LINE_WIDTH,i==0 ? 2 : 1); }
      return INIT_SUCCEEDED; // 日高低直接使用CopyRates，不需要指标句柄。
   }
   else viewHandle=ViewKind==2 ? iBands(_Symbol,_Period,ViewPeriod,0,ViewDeviation,ViewPrice) :
                                iMA(_Symbol,_Period,ViewPeriod,0,ViewMethod,ViewPrice);
   return viewHandle==INVALID_HANDLE ? INIT_FAILED : INIT_SUCCEEDED;
}
// 名称直接贴在线边；色弱用户不必只凭颜色识别多条线。
void PaintNames(const datetime at,const int last)
{
   if(ViewKind==5 || last<0) return;
   string ma=ViewMethod==MODE_SMA ? "MA" : ViewMethod==MODE_EMA ? "EMA" : ViewMethod==MODE_SMMA ? "SMMA" : "LWMA";
   string titles[3]={ViewKind==2 ? "BOLL中" : ViewKind==3 ? "M5 MA5" : ViewKind==4 ? "M15 MA5" :
                      ViewKind==6 ? "昨高" : ma+IntegerToString(ViewPeriod),
                      ViewKind==6 ? "昨低" : "BOLL上","BOLL下"};
   int count=ViewKind==2 ? 3 : ViewKind==6 ? 2 : 1;
   for(int i=0;i<count;i++)
   {
      double price=i==0 ? line0[last] : i==1 ? line1[last] : line2[last];
      string name=ViewName+".L."+IntegerToString(i);
      if(price==EMPTY_VALUE || !MathIsValidNumber(price)) { ObjectDelete(0,name); continue; }
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TEXT,0,at,price);
      ObjectMove(0,name,0,at,price);
      ObjectSetString(0,name,OBJPROP_TEXT,titles[i]);
      ObjectSetString(0,name,OBJPROP_FONT,"Microsoft YaHei UI");
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_RIGHT_LOWER);
      ObjectSetInteger(0,name,OBJPROP_COLOR,PlotIndexGetInteger(i,PLOT_LINE_COLOR));
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
   }
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
   PaintNames(time[rates_total-1],rates_total-1);
   return rates_total;
}
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<1) return 0;
   ArraySetAsSeries(time,false);
   if(ViewKind==3 || ViewKind==4 || ViewKind==6)
   {
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
   PaintNames(time[rates_total-1],rates_total-1);
   return rates_total;
}
void OnDeinit(const int reason)
{
   for(int i=0;i<3;i++) ObjectDelete(0,ViewName+".L."+IntegerToString(i));
   if(viewHandle!=INVALID_HANDLE) IndicatorRelease(viewHandle);
}
