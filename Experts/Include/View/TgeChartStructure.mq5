// 看盘结构：独立对象与句柄；只使用已收盘来源K线，不发送交易请求。
#property strict
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots 1
#property indicator_type1 DRAW_NONE
input int ViewKind=0; // 0滚动框，1确认震荡框，2BBW收缩，3数值卡
input string ViewName="TGE.Structure";
input ENUM_TIMEFRAMES SourcePeriod=PERIOD_M5;
input int BoxBars=5;
input int RangeBars=12;
input double RangeATR=1.5;
input int ATRBars=14;
input int BandBars=20;
input double BandDeviation=2.0;
input int CompareBars=100;
input double LowPercent=20.0;
double unused[];
int atrHandle=INVALID_HANDLE;
string objectPrefix="";
datetime drawnBar=0;
datetime rangeStart=0,rangeConfirmed=0,rangeEnd=0,rangeProcessed=0,rangeBreak=0;
double rangeHigh=0,rangeLow=0;
bool rangeActive=false;
string rangeState="";
const color BLUE=C'0,83,138',ORANGE=C'153,76,0',PURPLE=C'105,52,139',INK=C'40,45,52';
int OnInit()
{
   if(ViewKind<0 || ViewKind>3 || BoxBars<2 || BoxBars>200 || RangeBars<3 || RangeBars>200 ||
      ATRBars<2 || ATRBars>200 || BandBars<2 || BandBars>200 || CompareBars<20 || CompareBars>500 ||
      !MathIsValidNumber(RangeATR) || RangeATR<=0 || RangeATR>10 ||
      !MathIsValidNumber(BandDeviation) || BandDeviation<=0 ||
      !MathIsValidNumber(LowPercent) || LowPercent<=0 || LowPercent>=100) return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,unused,INDICATOR_DATA);
   PlotIndexSetInteger(0,PLOT_SHOW_DATA,false);
   IndicatorSetString(INDICATOR_SHORTNAME,ViewName);
   objectPrefix=ViewName+".S.";
   atrHandle=iATR(_Symbol,SourcePeriod,ATRBars);
   return atrHandle==INVALID_HANDLE ? INIT_FAILED : INIT_SUCCEEDED;
}
void StyleObject(const string name,const color ink,const int width=2,const ENUM_LINE_STYLE style=STYLE_SOLID)
{
   ObjectSetInteger(0,name,OBJPROP_COLOR,ink); ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true); ObjectSetInteger(0,name,OBJPROP_BACK,false);
}
void PriceText(const string key,const datetime at,const double price,const string text,const color ink,const bool below=false)
{
   string name=objectPrefix+key;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TEXT,0,at,price);
   ObjectMove(0,name,0,at,price); StyleObject(name,ink);
   ObjectSetString(0,name,OBJPROP_FONT,"Microsoft YaHei UI");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,below ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
   ObjectSetString(0,name,OBJPROP_TEXT,text);
}
void Readout(const int row,const string text,const color ink)
{
   int top=ViewKind==2 ? 106 : ViewKind==1 ? 166 : 30;
   if(row==0)
   {
      string card=objectPrefix+"readout";
      if(ObjectFind(0,card)<0) ObjectCreate(0,card,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(0,card,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
      ObjectSetInteger(0,card,OBJPROP_XDISTANCE,370); ObjectSetInteger(0,card,OBJPROP_YDISTANCE,top-6);
      ObjectSetInteger(0,card,OBJPROP_XSIZE,360); ObjectSetInteger(0,card,OBJPROP_YSIZE,ViewKind==3 ? 70 : ViewKind==2 ? 50 : 30);
      ObjectSetInteger(0,card,OBJPROP_BGCOLOR,clrWhite); ObjectSetInteger(0,card,OBJPROP_COLOR,C'165,170,177');
      ObjectSetInteger(0,card,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,card,OBJPROP_SELECTABLE,false); ObjectSetInteger(0,card,OBJPROP_HIDDEN,true);
   }
   string name=objectPrefix+"note"+IntegerToString(row);
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   StyleObject(name,ink);
   ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,20);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,top+row*20);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,10);
   ObjectSetString(0,name,OBJPROP_FONT,"Microsoft YaHei UI");
   ObjectSetString(0,name,OBJPROP_TEXT,text);
}
void DrawBox(const datetime start,const datetime end,const double hi,const double lo,
             const string title,const color ink,const ENUM_LINE_STYLE style=STYLE_SOLID)
{
   string name=objectPrefix+"box";
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_RECTANGLE,0,start,hi,end,lo);
   ObjectMove(0,name,0,start,hi); ObjectMove(0,name,1,end,lo);
   StyleObject(name,ink,style==STYLE_SOLID ? 2 : 1,style);
   ObjectSetInteger(0,name,OBJPROP_FILL,false);
   name=objectPrefix+"mid";
   double middle=(hi+lo)*0.5;
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TREND,0,start,middle,end,middle);
   ObjectMove(0,name,0,start,middle); ObjectMove(0,name,1,end,middle);
   StyleObject(name,ink,1,STYLE_DOT);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false); ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   PriceText("high",start,hi,title+" | H "+DoubleToString(hi,_Digits),ink);
   PriceText("low",start,lo,"L "+DoubleToString(lo,_Digits)+" | 宽 "+DoubleToString(hi-lo,2),ink,true);
}
double BandWidth(const MqlRates &bars[],const int at)
{
   double sum=0,variance=0;
   for(int j=at-BandBars+1;j<=at;j++) sum+=bars[j].close;
   double mean=sum/BandBars;
   if(mean<=0) return 0;
   for(int j=at-BandBars+1;j<=at;j++) variance+=MathPow(bars[j].close-mean,2);
   return 2*BandDeviation*MathSqrt(variance/BandBars)/mean*100;
}
bool Contracted(const double &widths[],const int at)
{
   double past[]; ArrayResize(past,CompareBars);
   for(int j=0;j<CompareBars;j++) past[j]=widths[at-CompareBars+j];
   ArraySort(past);
   int rank=(int)MathFloor((CompareBars-1)*LowPercent/100.0);
   return widths[at]<=past[rank];
}
// 从旧到新回放已收盘数据；边界在确认时冻结，越界后等待全新的窗口。
void RangeBox(const MqlRates &bars[],const double &atr[],const int n,const int seconds)
{
   // 正常增量只处理新收盘柱，避免滚动历史窗口改变已确认边界。
   if(rangeProcessed>0 && (rangeProcessed<bars[0].time || rangeProcessed>bars[n-1].time))
   {
      rangeStart=0; rangeConfirmed=0; rangeEnd=0; rangeProcessed=0; rangeBreak=0;
      rangeHigh=0; rangeLow=0; rangeActive=false; rangeState="";
   }
   for(int i=MathMax(RangeBars-1,ATRBars);i<n;i++)
   {
      if(bars[i].time<=rangeProcessed) continue;
      rangeProcessed=bars[i].time;
      if(rangeActive)
      {
         rangeEnd=bars[i].time+seconds;
         if(bars[i].close>rangeHigh || bars[i].close<rangeLow)
         {
            rangeState=bars[i].close>rangeHigh ? "收盘上破" : "收盘下破";
            rangeActive=false; rangeBreak=bars[i].time;
         }
         continue;
      }
      if(bars[i-RangeBars+1].time<=rangeBreak || atr[i]<=0 || atr[i]==EMPTY_VALUE || !MathIsValidNumber(atr[i])) continue;
      double mean=0;
      for(int j=i-RangeBars+1;j<=i;j++) mean+=bars[j].close;
      mean/=RangeBars;
      double band=RangeATR*atr[i];
      bool fits=true;
      for(int j=i-RangeBars+1;j<=i;j++)
         if(MathAbs(bars[j].close-mean)>band) { fits=false; break; }
      if(!fits) continue;
      rangeStart=bars[i-RangeBars+1].time; rangeConfirmed=bars[i].time+seconds;
      rangeEnd=rangeConfirmed; rangeHigh=mean+band; rangeLow=mean-band;
      rangeActive=true; rangeState="框内";
   }
   if(rangeStart==0)
   {
      ObjectsDeleteAll(0,objectPrefix);
      Readout(0,"震荡箱体：最近窗口尚未确认",ORANGE); return;
   }
   ObjectDelete(0,objectPrefix+"note0"); ObjectDelete(0,objectPrefix+"readout");
   DrawBox(rangeStart,rangeEnd,rangeHigh,rangeLow,
           "震荡 "+rangeState+" | 确认 "+TimeToString(rangeConfirmed,TIME_DATE|TIME_MINUTES)+" 服务器",
           ORANGE,rangeActive ? STYLE_SOLID : STYLE_DASH);
   string name=objectPrefix+"confirmed";
   if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_TREND,0,rangeConfirmed,rangeHigh,rangeConfirmed,rangeLow);
   ObjectMove(0,name,0,rangeConfirmed,rangeHigh); ObjectMove(0,name,1,rangeConfirmed,rangeLow);
   StyleObject(name,ORANGE,1,STYLE_DASHDOT);
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false); ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
}
int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   datetime latest=iTime(_Symbol,SourcePeriod,0);
   if(latest<=0) return prev_calculated;
   if(latest==drawnBar && prev_calculated>0) return rates_total;
   int needed=MathMax(300,MathMax(BoxBars,MathMax(RangeBars+ATRBars,BandBars+CompareBars+1)));
   int n=MathMin(needed,Bars(_Symbol,SourcePeriod)-1);
   int minimum=ViewKind==1 ? RangeBars+ATRBars : ViewKind==2 ? BandBars+CompareBars : MathMax(BoxBars,ATRBars+1);
   if(n<minimum || BarsCalculated(atrHandle)<n+1) return prev_calculated;
   MqlRates bars[]; double atr[];
   ArraySetAsSeries(bars,false); ArraySetAsSeries(atr,false);
   // 起始shift=1：包含的最新来源K线也已经收盘。
   if(CopyRates(_Symbol,SourcePeriod,1,n,bars)!=n || CopyBuffer(atrHandle,0,1,n,atr)!=n) return prev_calculated;
   int last=n-1,seconds=PeriodSeconds(SourcePeriod);
   if(seconds<=0 || bars[last].time+seconds>latest) return prev_calculated;
   string frame=EnumToString(SourcePeriod); StringReplace(frame,"PERIOD_","");
   double hi=bars[last].high,lo=bars[last].low;
   for(int i=MathMax(n-BoxBars,0);i<n;i++) { hi=MathMax(hi,bars[i].high); lo=MathMin(lo,bars[i].low); }
   if(ViewKind==0)
      DrawBox(bars[n-BoxBars].time,latest,hi,lo,frame+"×"+IntegerToString(BoxBars)+" 已收盘",BLUE);
   else if(ViewKind==1) RangeBox(bars,atr,n,seconds);
   else if(ViewKind==2)
   {
      double widths[]; ArrayResize(widths,n); ArrayInitialize(widths,0);
      for(int i=BandBars-1;i<n;i++) widths[i]=BandWidth(bars,i);
      bool squeezed=Contracted(widths,last);
      if(squeezed)
      {
         int start=last;
         while(start>BandBars+CompareBars-1 && Contracted(widths,start-1)) start--;
         double top=bars[last].high,bottom=bars[last].low;
         for(int i=start;i<n;i++) { top=MathMax(top,bars[i].high); bottom=MathMin(bottom,bars[i].low); }
         DrawBox(bars[start].time,latest,top,bottom,frame+" 波动收缩",PURPLE,STYLE_DASHDOT);
      }
      else
      {
         ObjectDelete(0,objectPrefix+"box"); ObjectDelete(0,objectPrefix+"mid");
         ObjectDelete(0,objectPrefix+"high"); ObjectDelete(0,objectPrefix+"low");
      }
      Readout(0,frame+" BBW "+DoubleToString(widths[last],3)+"% | "+(squeezed ? "收缩" : "未收缩"),PURPLE);
      Readout(1,"对比此前"+IntegerToString(CompareBars)+"根的低"+DoubleToString(LowPercent,0)+"%分位",INK);
   }
   else
   {
      Readout(0,frame+"×"+IntegerToString(BoxBars)+" 框宽 "+DoubleToString(hi-lo,2)+
                " | ATR"+IntegerToString(ATRBars)+" "+DoubleToString(atr[last],2),INK);
      Readout(1,"收盘距上沿 "+DoubleToString(hi-bars[last].close,2)+
                " | 距下沿 "+DoubleToString(bars[last].close-lo,2),INK);
      Readout(2,"截至 "+TimeToString(latest,TIME_MINUTES)+" 服务器时间 · 已收盘",INK);
   }
   drawnBar=latest; ChartRedraw(0);
   return rates_total;
}
void OnDeinit(const int reason)
{
   if(objectPrefix!="") ObjectsDeleteAll(0,objectPrefix);
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
   ChartRedraw(0);
}
