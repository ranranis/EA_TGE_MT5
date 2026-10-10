#property strict
#property version "1.19"
#property description "T哥点位地图 / M5 MA5 / M1收线 / 0.02手分批。独立Magic，仅管理本EA持仓。"
#include <Trade/Trade.mqh>
#include <Canvas/Canvas.mqh>
// 看盘指标嵌入主EX5，用户仍只需挂载这一份EA。
#resource "Include\\View\\TgeChartOverlay.ex5"
#resource "Include\\View\\TgeChartOscillator.ex5"

input group "执行与仓位"
input bool   启用真实交易=true;        // 默认执行交易；手动关闭时仅观察，不发送交易请求
input double 每次开仓手数=0.02;
input int    最大同时持仓=3;
input double 每日权益回撤上限百分比=1.0; // 本实例启动/每日首次观察权益为基准，含账户其他交易
input double 最大点差价格=0.50;         // 黄金报价价格差，不是_Point倍数
input ulong  EA魔法号=560056;
input group "T哥点位节奏与退出"
input bool   允许震荡点位反应=true;
input double 保险价格距离=10.0;
input double 首批止盈价格距离=5.0;
input double 尾仓目标价格距离=10.0;

// 以下参数只配置图表显示，不改变M5/M1交易规则。
input group "看盘指标 · 均线"
input int    看盘均线1周期=5;
input int    看盘均线2周期=10;
input int    看盘均线3周期=20;
input int    看盘均线4周期=50;
input int    看盘均线5周期=100;
input int    看盘均线6周期=200;
input ENUM_MA_METHOD 看盘主均线算法=MODE_SMA;
input ENUM_MA_METHOD 看盘辅助均线算法=MODE_EMA;
input ENUM_APPLIED_PRICE 看盘指标计算价格=PRICE_CLOSE;
input group "看盘指标 · 波动与动量"
input int    看盘布林周期=20;
input double 看盘布林标准差=2.0;
input int    看盘RSI周期=14;
input int    看盘MACD快线=12;
input int    看盘MACD慢线=26;
input int    看盘MACD信号线=9;
input int    看盘ATR周期=14;
input group "看盘指标 · 趋势与点位辅助"
input int    看盘ADX周期=14;
input double 看盘ADX参考线=25.0;       // 仅副图参考，不参与交易过滤
input int    看盘KD周期=9;
input int    看盘KD平滑=3;
input int    看盘KD信号=3;


const string FEED="FeishuMT5SignalMonitor\\tge_levels.csv";
const string VIEW="TGE_";
// 图表工具仅控制显示；独立于交易状态与输入参数。
int uiX=8,uiY=24;
bool uiCollapsed=false,uiPointLines=true;

CTrade execution;
double levels[];
string identity="",sourceKind="",sourceSender="",feedStatus="等待首次点位",reason="等待收线";
datetime sourceTime=0,feedTime=0,readyFrom=0,lastMinute=0;
bool feedActive=false,busy=false,stateOK=true;
int maHandle=INVALID_HANDLE,atrHandle=INVALID_HANDLE,lockHandle=INVALID_HANDLE,trend=0;
double atr=0,dayBase=0;
string prefix="";
long accountLogin=0;
string accountServer="";
long dayKey=0;
bool dayStopped=false;

// 一个实例只允许一个未确认请求。持久化的是意图，不是“已成交”。
struct Pending
{
   int kind;                 // 1开仓，2分批，3保护修改
   ulong order,position;
   datetime at,bar;
   double volume,sl,tp,level;
   int direction;
};
Pending pending;
struct Candidate
{
   bool valid;
   int direction;
   double level;
   datetime bar;
   string method;
};

uint Hash(const string text)
{
   uint h=2166136261;
   for(int i=0;i<StringLen(text);i++) h=(h^StringGetCharacter(text,i))*16777619;
   return h;
}
double TickSize() { return SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE); }
double Align(const double price,const int sign)
{
   double step=TickSize();
   return NormalizeDouble((sign>0 ? MathCeil(price/step-1e-8) : MathFloor(price/step+1e-8))*step,_Digits);
}
double LotDown(const double volume)
{
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   return step>0 ? NormalizeDouble(MathFloor(volume/step+1e-8)*step,8) : 0;
}
bool ExactLot(const double volume)
{
   return volume>=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)-1e-8 &&
          volume<=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX)+1e-8 &&
          MathAbs(volume-LotDown(volume))<1e-8;
}
bool Store(const string name,const double value)
{
   if(GlobalVariableSet(prefix+name,value)==0) { stateOK=false; reason="状态保存失败，停止发请求"; return false; }
   return true;
}
double Load(const string name) { return GlobalVariableGet(prefix+name); }
void SavePending()
{
   // 中断发生在字段保存途中时留下-1，重启必须人工核对而非猜测没有请求。
   Store("kind",-1); GlobalVariablesFlush();
   Store("order",(double)pending.order); Store("position",(double)pending.position);
   Store("at",(double)pending.at); Store("bar",(double)pending.bar);
   Store("volume",pending.volume); Store("sl",pending.sl); Store("tp",pending.tp);
   Store("level",pending.level); Store("direction",pending.direction);
   Store("kind",pending.kind); GlobalVariablesFlush();
}
void ClearPending()
{
   ZeroMemory(pending); SavePending();
}
void RestorePending()
{
   pending.kind=(int)Load("kind"); pending.order=(ulong)Load("order");
   pending.position=(ulong)Load("position"); pending.at=(datetime)Load("at"); pending.bar=(datetime)Load("bar");
   pending.volume=Load("volume"); pending.sl=Load("sl"); pending.tp=Load("tp");
   pending.level=Load("level"); pending.direction=(int)Load("direction");
}
bool CanExecute()
{
   return 启用真实交易 && stateOK && lockHandle!=INVALID_HANDLE &&
          AccountInfoInteger(ACCOUNT_LOGIN)==accountLogin && AccountInfoString(ACCOUNT_SERVER)==accountServer &&
          AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING &&
          TerminalInfoInteger(TERMINAL_CONNECTED) && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
          MQLInfoInteger(MQL_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) &&
          AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
}
bool FreshQuote(MqlTick &q)
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !SymbolInfoTick(_Symbol,q) ||
      q.bid<=0 || q.ask<q.bid || TickSize()<=0) return false;
   // TimeTradeServer估算当前服务器时刻；不能用可能随最后Tick一起停住的TimeCurrent判鲜。
   long age=(long)TimeTradeServer()*1000-q.time_msc;
   return age>=-2000 && age<=5000;
}
bool OwnSelected()
{
   return PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==EA魔法号;
}
ulong PositionById(const ulong id)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && OwnSelected() && (ulong)PositionGetInteger(POSITION_IDENTIFIER)==id) return ticket;
   }
   return 0;
}
int OwnCount()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--) if(PositionGetTicket(i)>0 && OwnSelected()) n++;
   return n;
}
bool Number(const string text,const bool decimal=false)
{
   int dots=0,n=StringLen(text);
   if(n<1 || n>24) return false;
   for(int i=0;i<n;i++)
   {
      ushort c=StringGetCharacter(text,i);
      if(decimal && c=='.' && i>0 && i<n-1 && ++dots==1) continue;
      if(c<'0' || c>'9') return false;
   }
   return true;
}
void DrawLevels()
{
   for(int i=0;i<20;i++)
   {
      string name=VIEW+"L"+IntegerToString(i);
      if(i>=ArraySize(levels)) { ObjectDelete(0,name); continue; }
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,levels[i]);
      ObjectMove(0,name,0,0,levels[i]);
      ObjectSetInteger(0,name,OBJPROP_COLOR,feedActive ? clrGold : clrGray);
      ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,uiPointLines ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
      ObjectSetString(0,name,OBJPROP_TEXT,"T点位 "+DoubleToString(levels[i],_Digits));
   }
}
bool ReadFeed()
{
   int h=FileOpen(FEED,FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(h==INVALID_HANDLE) { feedStatus="文件暂不可读，保留上次地图"; return false; }
   string lines[];
   bool ok=FileSize(h)<=16384;
   while(ok && !FileIsEnding(h))
   {
      int n=ArraySize(lines);
      if(n>=22) { ok=false; break; }
      ArrayResize(lines,n+1); lines[n]=FileReadString(h);
   }
   FileClose(h);
   string head[],foot[];
   if(!ok || ArraySize(lines)<2 || StringSplit(lines[0],',',head)!=11 ||
      head[0]!="TGE" || head[1]!="1" || head[4]!=_Symbol ||
      !Number(head[2]) || !Number(head[7]) || !Number(head[8]) || (head[3]!="0" && head[3]!="1"))
   { feedStatus="快照格式或品种错误，保留上次地图"; return false; }
   int n=(int)StringToInteger(head[7]);
   if(n>20 || ArraySize(lines)!=n+2 || StringSplit(lines[n+1],',',foot)!=2 ||
      foot[0]!="END" || foot[1]!=head[7] || (datetime)StringToInteger(head[2])>TimeGMT()+5)
      return false;
   double incoming[]; ArrayResize(incoming,n);
   for(int i=0;i<n;i++)
   {
      string fields[];
      if(StringSplit(lines[i+1],',',fields)!=2 || fields[0]!="LEVEL" || !Number(fields[1],true)) return false;
      incoming[i]=StringToDouble(fields[1]);
      if(!MathIsValidNumber(incoming[i]) || incoming[i]<=0 || (i>0 && incoming[i]<=incoming[i-1])) return false;
   }
   bool active=head[3]=="1";
   if(active && (n<3 || head[5]=="" || head[6]=="" || head[10]=="")) return false;
   string next=head[5]+"|"+head[6];
   if(next!=identity || active!=feedActive)
   {
      readyFrom=TimeCurrent(); // 新版本/恢复后必须等随后完整形成的M1，不能追认历史K线。
      Print("[T哥点位] 来源=",head[9]," 消息=",head[5]," 有效=",active);
   }
   identity=next; sourceKind=head[9]; sourceSender=head[10]; feedActive=active;
   sourceTime=(datetime)StringToInteger(head[8]); feedTime=(datetime)StringToInteger(head[2]);
   if(active) ArrayCopy(levels,incoming); // 暂停仍展示上一组灰色参考线
   if(active) ArrayResize(levels,n);
   feedStatus=active ? "沿用当前点位，收到更新才替换" : "来源撤回/编辑/暂停，停止新单";
   DrawLevels();
   return true;
}

// 下列纯计算只读已收盘K线；ATR容差、SMA选择属于工程定义，不是逐字原话。
bool Reaction(const MqlRates &bar,const MqlRates &previous,const double level,
              const int sign,const double tolerance,const double escape)
{
   if(sign>0)
      return MathMin(bar.low,previous.low)<=level+tolerance &&
             MathMin(bar.low,previous.low)>=level-tolerance &&
             bar.low>=previous.low-TickSize()*0.5 &&
             bar.close>level+escape && bar.close>bar.open && bar.close>=previous.close;
   return MathMax(bar.high,previous.high)>=level-tolerance &&
          MathMax(bar.high,previous.high)<=level+tolerance &&
          bar.high<=previous.high+TickSize()*0.5 &&
          bar.close<level-escape && bar.close<bar.open && bar.close<=previous.close;
}
int Trend(const MqlRates &last,const MqlRates &previous,const double ma0,const double ma1)
{
   // “完整脱离一根”：前一根整根K在MA同侧，最新收线仍守住且均线有斜率。
   if(previous.low>ma1 && last.close>ma0 && ma0>ma1) return 1;
   if(previous.high<ma1 && last.close<ma0 && ma0<ma1) return -1;
   return 0;
}
bool BreakRetest(const MqlRates &last,const MqlRates &breakbar,const MqlRates &before,
                 const double level,const int sign,const double tolerance,const double escape)
{
   if(sign>0)
      return before.close<=level && breakbar.close>level+escape &&
             last.low>=level-tolerance && last.low<=level+tolerance && last.close>level+escape;
   return before.close>=level && breakbar.close<level-escape &&
          last.high<=level+tolerance && last.high>=level-tolerance && last.close<level-escape;
}
bool Target(const double entry,const int sign,double &tp)
{
   double distance=尾仓目标价格距离;
   for(int i=0;i<ArraySize(levels);i++)
   {
      double gap=sign*(levels[i]-entry);
      if(gap>TickSize()) distance=MathMin(distance,gap-MathMax(0.20,TickSize()*2));
   }
   if(distance<=首批止盈价格距离+TickSize()) return false;
   tp=Align(entry+sign*distance,-sign); // 不把目标舍入到阻力之外
   return true;
}
string VisitKey(const double level) { return "visit"+DoubleToString(level,_Digits); }
bool Signal(Candidate &out)
{
   out.valid=false;
   MqlTick quote;
   if(!feedActive || !FreshQuote(quote)) { reason="等待有效点位及新鲜报价"; return false; }
   if(quote.ask-quote.bid>最大点差价格) { reason="点差过大"; return false; }
   MqlRates m1[],m5[]; double ma[],vol[];
   ArraySetAsSeries(m1,true); ArraySetAsSeries(m5,true); ArraySetAsSeries(ma,true);
   if(CopyRates(_Symbol,PERIOD_M1,1,2,m1)!=2 || CopyRates(_Symbol,PERIOD_M5,1,7,m5)!=7 ||
      CopyBuffer(maHandle,0,1,7,ma)!=7 || CopyBuffer(atrHandle,0,1,1,vol)!=1)
   { reason="等待M1/M5数据"; return false; }
   if(m1[0].time<readyFrom || TimeCurrent()-m1[0].time>90 || m1[0].time-m1[1].time!=60 ||
      TimeCurrent()-m5[0].time>360) { reason="等待启动/更新后的完整收线"; return false; }
   for(int i=0;i<6;i++) if(m5[i].time-m5[i+1].time!=300) { reason="M5数据缺口"; return false; }
   atr=vol[0]; if(!MathIsValidNumber(atr) || atr<=TickSize()) return false;
   trend=Trend(m5[0],m5[1],ma[0],ma[1]);
   int maCrossings=0;
   for(int i=0;i<6;i++)
      if((m5[i].close-ma[i])*(m5[i+1].close-ma[i+1])<0) maCrossings++;
   if(maCrossings>=3) trend=0;
   double tolerance=MathMax(0.20*atr,2*TickSize()),escape=MathMax(0.05*atr,TickSize());
   double nearest=DBL_MAX;
   reason="等待点位附近的完整M1止跌/受阻";
   for(int i=0;i<ArraySize(levels);i++)
   {
      double level=levels[i];
      datetime consumed=(datetime)Load(VisitKey(level));
      if(consumed>0 && m1[0].time>consumed && MathAbs(m1[0].close-level)>MathMax(atr,2.0))
         Store(VisitKey(level),0); // 离开后才可重新回踩；消息重发不会重置
      if(Load(VisitKey(level))>0) continue;
      int flips=0;
      for(int j=0;j<6;j++) if((m5[j].close-level)*(m5[j+1].close-level)<0) flips++;
      for(int sign=-1;sign<=1;sign+=2)
      {
         double entry=sign>0 ? quote.ask : quote.bid,gap=sign*(entry-level);
         if(gap<0 || gap>MathMin(0.75*atr,首批止盈价格距离*0.8)) continue;
         if(!Reaction(m1[0],m1[1],level,sign,tolerance,escape)) continue;
         if(trend!=0 && sign!=trend) continue; // 强趋势不盲摸顶抄底
         bool retest=BreakRetest(m5[0],m5[1],m5[2],level,sign,tolerance,escape);
         bool maTouch=sign>0 ? MathMin(m1[0].low,m1[1].low)<=ma[0]+tolerance :
                              MathMax(m1[0].high,m1[1].high)>=ma[0]-tolerance;
         bool pullback=trend==sign && maTouch && MathAbs(m1[0].close-ma[0])<=0.75*atr;
         bool reaction=允许震荡点位反应 && trend==0 && sign*(m5[0].close-level)>escape &&
                       m5[0].high-m5[0].low<=2*atr;
         if(flips>=3 && !retest) continue; // 反复穿越只禁用反应单，明确突破回测可恢复角色
         if(!retest && !pullback && !reaction) continue;
         double tp;
         if(!Target(entry,sign,tp)) { reason="下一点位之前不足5点收米空间"; continue; }
         if(gap>=nearest) continue;
         nearest=gap; out.valid=true; out.direction=sign; out.level=level; out.bar=m1[0].time;
         out.method=retest ? "M5突破回测" : pullback ? "M5 MA5顺势回踩" : "震荡点位反应";
      }
   }
   if(out.valid) reason=out.method+(out.direction>0 ? " 多" : " 空")+" @"+DoubleToString(out.level,_Digits);
   return out.valid;
}

void UpdateDay()
{
   MqlDateTime d; TimeToStruct(TimeCurrent(),d);
   long key=d.year*1000+d.day_of_year;
   if(key!=dayKey)
   {
      dayKey=key; dayBase=AccountInfoDouble(ACCOUNT_EQUITY); dayStopped=false;
      Store("day",dayKey); Store("base",dayBase); Store("stopped",0); GlobalVariablesFlush();
   }
   if(dayBase>0 && AccountInfoDouble(ACCOUNT_EQUITY)<=dayBase*(1-每日权益回撤上限百分比/100.0))
   {
      if(!dayStopped) { dayStopped=true; Store("stopped",1); GlobalVariablesFlush(); }
   }
}
bool Stops(const int sign,const double sl,const double tp,const MqlTick &q)
{
   double distance=MathMax((double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                           (double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point+TickSize();
   if(sign>0) return q.bid-sl>=distance && tp-q.bid>=distance;
   return sl-q.ask>=distance && q.ask-tp>=distance;
}
bool ExplicitReject(const uint code)
{
   return code==TRADE_RETCODE_REQUOTE || code==TRADE_RETCODE_REJECT || code==TRADE_RETCODE_INVALID ||
          code==TRADE_RETCODE_INVALID_VOLUME || code==TRADE_RETCODE_INVALID_PRICE ||
          code==TRADE_RETCODE_INVALID_STOPS || code==TRADE_RETCODE_TRADE_DISABLED ||
          code==TRADE_RETCODE_MARKET_CLOSED || code==TRADE_RETCODE_NO_MONEY ||
          code==TRADE_RETCODE_PRICE_CHANGED || code==TRADE_RETCODE_PRICE_OFF ||
          code==TRADE_RETCODE_INVALID_FILL || code==TRADE_RETCODE_LIMIT_VOLUME;
}
void RecordResult()
{
   uint code=execution.ResultRetcode();
   pending.order=execution.ResultOrder();
   if(pending.order==0 && execution.ResultDeal()>0 && HistoryDealSelect(execution.ResultDeal()))
      pending.order=(ulong)HistoryDealGetInteger(execution.ResultDeal(),DEAL_ORDER);
   PrintFormat("[T哥请求] 动作=%d retcode=%u order=%I64u deal=%I64u %s",
               pending.kind,code,pending.order,execution.ResultDeal(),execution.ResultComment());
   if(ExplicitReject(code)) { ClearPending(); reason="请求被明确拒绝，见日志"; }
   else SavePending(); // TIMEOUT/CONNECTION/未知结果不猜失败，不补发
}
string EntryTag() { return "TG"+IntegerToString((long)pending.bar)+"_"+IntegerToString((long)Hash(DoubleToString(pending.level,_Digits))); }
bool FinalOrderConfirmed(const ulong order)
{
   if(OrderSelect(order)) return false;
   if(!HistoryOrderSelect(order)) return false;
   ENUM_ORDER_STATE state=(ENUM_ORDER_STATE)HistoryOrderGetInteger(order,ORDER_STATE);
   if(state!=ORDER_STATE_FILLED && state!=ORDER_STATE_CANCELED && state!=ORDER_STATE_REJECTED && state!=ORDER_STATE_EXPIRED) return false;
   double filled=HistoryOrderGetDouble(order,ORDER_VOLUME_INITIAL)-HistoryOrderGetDouble(order,ORDER_VOLUME_CURRENT);
   if(!HistorySelect(pending.at-60,TimeCurrent()+1)) return false;
   double actual=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if((ulong)HistoryDealGetInteger(deal,DEAL_ORDER)==order) actual+=HistoryDealGetDouble(deal,DEAL_VOLUME);
   }
   // FILLED但Deal迟到不能先解锁。
   return (state!=ORDER_STATE_FILLED || actual>0) && actual+1e-8>=filled;
}
void Reconcile()
{
   if(pending.kind==0 || !TerminalInfoInteger(TERMINAL_CONNECTED)) return;
   if(pending.kind<0) { reason="上次状态写入中断，待人工核对请求"; return; }
   if(pending.kind==3)
   {
      ulong ticket=PositionById(pending.position);
      if(ticket>0)
      {
         double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
         if(sl>0 && pending.direction*(sl-pending.sl)>=-TickSize()*0.5 && MathAbs(tp-pending.tp)<TickSize()*0.5)
         { ClearPending(); return; }
      }
      // 仓位消失时必须有历史出量对账，不能凭“找不到”当完成。
      else if(HistorySelectByPosition(pending.position))
      {
         double inVol=0,outVol=0;
         for(int i=0;i<HistoryDealsTotal();i++)
         {
            ulong deal=HistoryDealGetTicket(i);
            long e=HistoryDealGetInteger(deal,DEAL_ENTRY);
            if(e==DEAL_ENTRY_IN) inVol+=HistoryDealGetDouble(deal,DEAL_VOLUME);
            if(e==DEAL_ENTRY_OUT || e==DEAL_ENTRY_OUT_BY) outVol+=HistoryDealGetDouble(deal,DEAL_VOLUME);
         }
         if(inVol>0 && outVol+1e-8>=inVol) ClearPending();
      }
      return;
   }
   if(pending.order==0 && pending.kind==1 && HistorySelect(pending.at-60,TimeCurrent()+1))
   {
      string tag=EntryTag();
      for(int i=HistoryOrdersTotal()-1;i>=0;i--)
      {
         ulong order=HistoryOrderGetTicket(i);
         if((ulong)HistoryOrderGetInteger(order,ORDER_MAGIC)==EA魔法号 &&
            HistoryOrderGetString(order,ORDER_SYMBOL)==_Symbol && HistoryOrderGetString(order,ORDER_COMMENT)==tag)
         { pending.order=order; SavePending(); break; }
      }
   }
   if(pending.order==0 && pending.kind==2 && HistorySelectByPosition(pending.position))
   {
      // 发送后、写回order之前重启：按真实退出Deal找唯一对应请求；多候选不猜。
      ulong match=0; bool ambiguous=false;
      for(int i=0;i<HistoryDealsTotal();i++)
      {
         ulong deal=HistoryDealGetTicket(i);
         long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;
         if(HistoryDealGetInteger(deal,DEAL_TIME)<pending.at ||
            (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=EA魔法号) continue;
         ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
         if(match>0 && match!=order) ambiguous=true;
         match=order;
      }
      if(match>0 && !ambiguous) { pending.order=match; SavePending(); }
   }
   if(pending.order>0 && FinalOrderConfirmed(pending.order)) ClearPending();
   if(pending.kind!=0 && TimeCurrent()-pending.at>30)
      reason="请求尚未完成服务器对账，暂停新请求（查看日志）";
}
void Open(const Candidate &signal)
{
   if(!CanExecute() || pending.kind!=0 || dayStopped || OwnCount()>=最大同时持仓) return;
   if((datetime)Load("attemptBar")>=signal.bar || Load(VisitKey(signal.level))>0) return;
   MqlTick q;
   if(!FreshQuote(q) || q.ask-q.bid>最大点差价格 || !ExactLot(每次开仓手数)) return;
   int sign=signal.direction;
   double entry=sign>0 ? q.ask : q.bid,sl=Align(entry-sign*保险价格距离,sign),tp;
   if(!Target(entry,sign,tp) || !Stops(sign,sl,tp,q)) { reason="价格保护不符合券商规格"; return; }
   ENUM_ORDER_TYPE type=sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double margin=0;
   if(!OrderCalcMargin(type,_Symbol,每次开仓手数,entry,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   { reason="可用保证金不足"; return; }
   Store("attemptBar",(double)signal.bar); Store(VisitKey(signal.level),(double)signal.bar);
   ZeroMemory(pending); pending.kind=1; pending.at=TimeCurrent(); pending.bar=signal.bar;
   pending.volume=每次开仓手数; pending.sl=sl; pending.tp=tp; pending.level=signal.level; pending.direction=sign;
   SavePending(); if(!CanExecute()) return;
   execution.PositionOpen(_Symbol,type,每次开仓手数,entry,sl,tp,EntryTag());
   RecordResult();
}
// 从真实入/出Deal累计恢复初始量与已减仓量，退出Magic可为0。
bool PositionVolumes(const ulong id,double &initial,double &closed)
{
   initial=0; closed=0;
   if(!HistorySelectByPosition(id)) return false;
   bool own=false;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_IN)
      {
         initial+=HistoryDealGetDouble(deal,DEAL_VOLUME);
         if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)==EA魔法号) own=true;
      }
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY) closed+=HistoryDealGetDouble(deal,DEAL_VOLUME);
      if(entry==DEAL_ENTRY_INOUT) return false;
   }
   return own && initial>0;
}
double PartialRemaining(const double initial,const double closed,const double remaining)
{
   double minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double half=LotDown(initial*0.5);
   if(half<minimum || initial-half<minimum) return 0; // 无法拆分，使用5点全量服务器TP
   double need=LotDown(half-closed);
   return need>=minimum && remaining-need>=minimum-1e-8 ? need : 0;
}
void Modify(const ulong ticket,const ulong id,const int sign,const double sl,const double tp)
{
   if(!CanExecute() || pending.kind!=0) return;
   MqlTick q; if(!FreshQuote(q) || !Stops(sign,sl,tp,q)) return;
   if(!PositionSelectByTicket(ticket) || !OwnSelected()) return;
   double current=PositionGetDouble(POSITION_SL);
   if(current>0 && sign*(sl-current)<-TickSize()*0.5) return; // 绝不放宽已有保险
   ZeroMemory(pending); pending.kind=3; pending.position=id; pending.direction=sign;
   pending.sl=sl; pending.tp=tp; pending.at=TimeCurrent(); SavePending();
   if(!CanExecute()) return;
   execution.PositionModify(ticket,sl,tp); RecordResult();
}
void Manage()
{
   if(!CanExecute() || pending.kind!=0) return;
   MqlTick q; if(!FreshQuote(q)) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !OwnSelected()) continue;
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      int sign=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1;
      double open=PositionGetDouble(POSITION_PRICE_OPEN),volume=PositionGetDouble(POSITION_VOLUME);
      double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP),initial,closed;
      if(!PositionVolumes(id,initial,closed) || MathAbs(initial-closed-volume)>1e-8) continue;
      double half=LotDown(initial*0.5),minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      bool split=half>=minimum && initial-half>=minimum;
      bool partialDone=split && closed+1e-8>=half; // 真实Deal确认，重启不重复分批
      double required=Align(open-sign*保险价格距离,sign);
      if(partialDone) required=Align(open,sign); // 价格保本；不声称已覆盖佣金/隔夜费
      if(sl>0 && sign*(sl-required)>0) required=sl;
      double target=tp;
      if(target<=0) target=Align(open+sign*(split ? 尾仓目标价格距离 : 首批止盈价格距离),-sign);
      if(!split) target=Align(open+sign*首批止盈价格距离,-sign);
      if(sl<=0 || sign*(required-sl)>TickSize()*0.5 || MathAbs(target-tp)>TickSize()*0.5)
      {
         Modify(ticket,id,sign,required,target);
         if(pending.kind!=0) return;
      }
      double gain=sign*((sign>0 ? q.bid : q.ask)-open);
      double closeVolume=PartialRemaining(initial,closed,volume);
      if(gain<首批止盈价格距离 || closeVolume<=0) continue;
      if(!PositionSelectByTicket(ticket) || !OwnSelected() ||
         MathAbs(PositionGetDouble(POSITION_VOLUME)-volume)>1e-8) continue;
      ZeroMemory(pending); pending.kind=2; pending.position=id; pending.at=TimeCurrent(); pending.volume=closeVolume;
      SavePending(); if(!CanExecute()) return;
      execution.PositionClosePartial(ticket,closeVolume,30);
      RecordResult(); return;
   }
}
// 视图层沿用交易托管系统的Canvas、深蓝底色与四格概览，只读取状态。
CCanvas panelCanvas;
bool panelReady=false;
int panelWidth=0,panelHeight=0;
double panelScale=1.0;
struct UIHit { int x,y,w,h,action; };
UIHit uiHits[];
string uiPrefix="";
bool uiInitialized=false,uiOldMouseMove=false,uiDragging=false,uiOldScroll=false,uiLeftWasDown=false;
int uiDragDX=0,uiDragDY=0,uiPressedAction=0;
// 统计页状态属于显示偏好，不参与交易管理。
bool uiStatistics=false;
int statsPeriod=0,statsOffsets[3]={0,0,0},statsFilter=0,statsDetail=0,statsReview=0;
// 1收起；27点位线；50..59旧指标；60/61均线组合；70..75策略辅助指标。

// 这些句柄和偏好仅供看盘，与策略maHandle/atrHandle分开。
// 前六项保留旧显示ID，新增均线使用6..9，避免覆盖已有显示偏好。
string uiIndicatorLabels[16]={"MA5","EMA20","布林","RSI","MACD","ATR","MA10","MA50","MA100","MA200","M5·MA5","M15·MA5","确认拐点","昨高低","ADX","随机KD"};
int uiIndicatorHandles[16]={INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE};
string uiIndicatorNotice="指标随当前图表周期；RSI/MACD/ATR/ADX/KD切换副图；固定MA5只显示已收盘值";

const color UI_ROOT=C'12,20,31',UI_HEADER=C'16,27,42',UI_CARD=C'25,41,60';
const color UI_ROW=C'25,40,58',UI_BORDER=C'52,73,96',UI_TEXT=C'225,232,241';
const color UI_MUTED=C'150,165,184',UI_DIM=C'94,108,128',UI_ACCENT=C'45,190,177';
const color UI_GAIN=C'255,122,89',UI_LOSS=C'77,163,255',UI_WARN=C'232,169,70';
const color UI_SELL=C'167,139,250';
#include "Include/Journal/TgeStatistics.mqh"

int UIPx(const double value) { return (int)MathRound(value*panelScale); }
uint UIInk(const color value) { return ColorToARGB(value,255); }
void UIRound(const int x,const int y,const int w,const int h,const color fill)
{
   int left=UIPx(x),top=UIPx(y),width=UIPx(w),height=UIPx(h),r=UIPx(5);
   panelCanvas.FillRectangle(left+r,top,left+width-r-1,top+height-1,UIInk(fill));
   panelCanvas.FillRectangle(left,top+r,left+width-1,top+height-r-1,UIInk(fill));
   panelCanvas.FillCircle(left+r,top+r,r,UIInk(fill));
   panelCanvas.FillCircle(left+width-r-1,top+r,r,UIInk(fill));
   panelCanvas.FillCircle(left+r,top+height-r-1,r,UIInk(fill));
   panelCanvas.FillCircle(left+width-r-1,top+height-r-1,r,UIInk(fill));
}
void UICard(const int x,const int y,const int w,const int h,const color fill)
{
   UIRound(x,y,w,h,UI_BORDER);
   UIRound(x+1,y+1,w-2,h-2,fill);
}
void UIText(string text,const int x,const int y,const int width,const double size,
            const color ink,const bool right=false)
{
   panelCanvas.FontSet("Microsoft YaHei UI",-MathMax((int)MathRound(size*10*panelScale),10));
   int available=UIPx(width);
   if(panelCanvas.TextWidth(text)>available)
   {
      while(StringLen(text)>0 && panelCanvas.TextWidth(text+"…")>available)
         text=StringSubstr(text,0,StringLen(text)-1);
      text+="…";
   }
   int at=UIPx(x)+(right ? available-panelCanvas.TextWidth(text) : 0);
   panelCanvas.TextOut(at,UIPx(y),text,UIInk(ink));
}
void UIBadge(const string text,const int x,const int y,const int w,const color ink,const bool active=false)
{
   UICard(x,y,w,27,active ? C'27,72,78' : UI_HEADER);
   UIText(text,x+8,y+5,w-16,9.5,ink);
}

int UIIndicatorPeriod(const int index)
{
   if(index==0) return 看盘均线1周期;
   if(index==6) return 看盘均线2周期;
   if(index==1) return 看盘均线3周期;
   if(index==7) return 看盘均线4周期;
   if(index==8) return 看盘均线5周期;
   if(index==9) return 看盘均线6周期;
   if(index==10 || index==11) return 5;
   if(index==14) return 看盘ADX周期;
   if(index==15) return 看盘KD周期;
   return index==2 ? 看盘布林周期 : index==3 ? 看盘RSI周期 : 看盘ATR周期;
}
bool UIIsMovingAverage(const int index) { return index==0 || index==1 || (index>=6 && index<=9); }
bool UIIsOscillator(const int index) { return (index>=3 && index<=5) || index==14 || index==15; }
string UIIndicatorLabel(const int index)
{
   if(!UIIsMovingAverage(index)) return uiIndicatorLabels[index];
   ENUM_MA_METHOD method=index==0 ? 看盘主均线算法 : 看盘辅助均线算法;
   string label=method==MODE_SMA ? "MA" : method==MODE_EMA ? "EMA" : method==MODE_SMMA ? "SMMA" : "LWMA";
   return label+IntegerToString(UIIndicatorPeriod(index));
}

string UIIndicatorName(const int index)
{
   return uiPrefix+"V"+IntegerToString(index)+" "+uiIndicatorLabels[index];
}
int UIIndicatorWindow(const int index)
{
   if(index<0 || index>=ArraySize(uiIndicatorLabels) || uiPrefix=="") return -1;
   string name=UIIndicatorName(index);
   int windows=(int)ChartGetInteger(0,CHART_WINDOWS_TOTAL);
   for(int w=0;w<windows;w++)
      for(int i=0;i<ChartIndicatorsTotal(0,w);i++)
         if(ChartIndicatorName(0,w,i)==name) return w;
   return -1;
}
bool UIIndicatorSet(const int index,const bool enabled)
{
   if(index<0 || index>=ArraySize(uiIndicatorLabels)) return false;
   int window=UIIndicatorWindow(index);
   if(enabled && window>=0) return true;
   if(!enabled && window>=0)
   {
      if(!ChartIndicatorDelete(0,window,UIIndicatorName(index)))
      { uiIndicatorNotice=UIIndicatorLabel(index)+"关闭失败："+IntegerToString(GetLastError()); Print(uiIndicatorNotice); return false; }
      ChartRedraw(0);
      if(UIIndicatorWindow(index)>=0) return false;
   }
   if(uiIndicatorHandles[index]!=INVALID_HANDLE) IndicatorRelease(uiIndicatorHandles[index]);
   uiIndicatorHandles[index]=INVALID_HANDLE;
   if(!enabled) return true;
   bool overlay=!UIIsOscillator(index);
   int kind=overlay ? (index>=10 ? index-7 : index==2 ? 2 : index==0 ? 0 : 1) : index>=14 ? index-11 : index-3;
   ENUM_MA_METHOD method=index==0 ? 看盘主均线算法 : 看盘辅助均线算法;
   color lineInk=index==0 ? clrGold : index==6 ? clrOrange : index==1 ? clrMediumTurquoise :
                 index==10 ? clrWhite : index==11 ? clrOrangeRed : index==7 ? clrDeepSkyBlue : index==8 ? clrMediumPurple : clrHotPink;
   int handle=overlay ?
      iCustom(_Symbol,ChartPeriod(0),"::Include\\View\\TgeChartOverlay.ex5",kind,UIIndicatorName(index),
              UIIndicatorPeriod(index),method,看盘指标计算价格,看盘布林标准差,lineInk) :
      iCustom(_Symbol,ChartPeriod(0),"::Include\\View\\TgeChartOscillator.ex5",kind,UIIndicatorName(index),
              UIIndicatorPeriod(index),看盘MACD快线,看盘MACD慢线,看盘MACD信号线,看盘指标计算价格,
              看盘KD信号,看盘KD平滑,看盘ADX参考线);
   if(handle==INVALID_HANDLE)
   { uiIndicatorNotice=UIIndicatorLabel(index)+"创建失败："+IntegerToString(GetLastError()); Print(uiIndicatorNotice); return false; }
   window=overlay ? 0 : (int)ChartGetInteger(0,CHART_WINDOWS_TOTAL);
   if(!ChartIndicatorAdd(0,window,handle))
   {
      uiIndicatorNotice=UIIndicatorLabel(index)+"显示失败："+IntegerToString(GetLastError()); Print(uiIndicatorNotice);
      IndicatorRelease(handle); return false;
   }
   uiIndicatorHandles[index]=handle;
   ChartRedraw(0);
   // 副图一次展示一种量纲；先成功加载新的，再移除旧的，失败时保留原显示。
   if(!overlay)
   {
      for(int i=0;i<ArraySize(uiIndicatorLabels);i++) if(UIIsOscillator(i) && i!=index) UIIndicatorSet(i,false);
      window=UIIndicatorWindow(index);
      if(window>0) ChartSetInteger(0,CHART_HEIGHT_IN_PIXELS,window,120);
   }
   uiIndicatorNotice=UIIndicatorLabel(index)+(index==10 || index==11 ? "：固定周期收盘值，投影到当前图表" :
                     index==12 ? "：两根右侧K线收完才确认，箭头延后出现" :
                     index==13 ? "：前一交易日高低，按券商D1日期" : "已显示；指标周期跟随当前图表");
   return true;
}
void CloseViewIndicators()
{
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
   {
      UIIndicatorSet(i,false);
      if(uiIndicatorHandles[i]!=INVALID_HANDLE) IndicatorRelease(uiIndicatorHandles[i]);
      uiIndicatorHandles[i]=INVALID_HANDLE;
   }
}

void SaveView()
{
   // 显示偏好不写入交易Store，保存失败也不改变交易状态。
   GlobalVariableSet(uiPrefix+"x",uiX); GlobalVariableSet(uiPrefix+"y",uiY);
   GlobalVariableSet(uiPrefix+"fold",uiCollapsed ? 1 : 0);
   GlobalVariableSet(uiPrefix+"lines",uiPointLines ? 1 : 0);
   GlobalVariableSet(uiPrefix+"stats",uiStatistics ? 1 : 0);
   GlobalVariableSet(uiPrefix+"period",statsPeriod); GlobalVariableSet(uiPrefix+"filter",statsFilter);
   GlobalVariableSet(uiPrefix+"detail",statsDetail);
   for(int i=0;i<3;i++) GlobalVariableSet(uiPrefix+"offset"+IntegerToString(i),statsOffsets[i]);
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++) GlobalVariableSet(uiPrefix+"indicator"+IntegerToString(i),UIIndicatorWindow(i)>=0 ? 1 : 0);
}
void InitView()
{
   uiPrefix="TGUI."+IntegerToString(ChartID())+".";
   if(GlobalVariableCheck(uiPrefix+"x")) uiX=(int)GlobalVariableGet(uiPrefix+"x");
   if(GlobalVariableCheck(uiPrefix+"y")) uiY=(int)GlobalVariableGet(uiPrefix+"y");
   if(GlobalVariableCheck(uiPrefix+"fold")) uiCollapsed=GlobalVariableGet(uiPrefix+"fold")>0;
   if(GlobalVariableCheck(uiPrefix+"lines")) uiPointLines=GlobalVariableGet(uiPrefix+"lines")>0;
   uiStatistics=GlobalVariableGet(uiPrefix+"stats")>0;
   statsPeriod=(int)MathMax(0,MathMin(GlobalVariableGet(uiPrefix+"period"),2));
   statsFilter=(int)MathMax(0,MathMin(GlobalVariableGet(uiPrefix+"filter"),2));
   statsDetail=(int)MathMax(0,MathMin(GlobalVariableGet(uiPrefix+"detail"),3));
   for(int i=0;i<3;i++) statsOffsets[i]=(int)GlobalVariableGet(uiPrefix+"offset"+IntegerToString(i));
   // 默认关闭新增看盘指标，按图表ID恢复用户已选的显示组合。
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if(GlobalVariableGet(uiPrefix+"indicator"+IntegerToString(i))>0) UIIndicatorSet(i,true);
   uiOldMouseMove=ChartGetInteger(0,CHART_EVENT_MOUSE_MOVE)!=0;
   ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,true);
   ChartRedraw(0);
   uiInitialized=true;
}
void MovePanel()
{
   int cw=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),ch=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   uiX=MathMax(0,MathMin(uiX,MathMax(cw-panelWidth-4,0)));
   uiY=MathMax(0,MathMin(uiY,MathMax(ch-panelHeight-4,0)));
   if((int)ObjectGetInteger(0,VIEW+"CANVAS",OBJPROP_XDISTANCE)!=uiX)
      ObjectSetInteger(0,VIEW+"CANVAS",OBJPROP_XDISTANCE,uiX);
   if((int)ObjectGetInteger(0,VIEW+"CANVAS",OBJPROP_YDISTANCE)!=uiY)
      ObjectSetInteger(0,VIEW+"CANVAS",OBJPROP_YDISTANCE,uiY);
}
void UIButton(const string text,const int x,const int y,const int w,const int action,const bool active=false)
{
   UICard(x,y,w,27,active ? C'27,72,78' : UI_HEADER);
   UIText(text,x+5,y+5,w-10,9,active ? UI_ACCENT : UI_MUTED);
   int n=ArraySize(uiHits); ArrayResize(uiHits,n+1);
   uiHits[n].x=x; uiHits[n].y=y; uiHits[n].w=w; uiHits[n].h=27; uiHits[n].action=action;
}
void ChartTools(const int y)
{
   int averages[6]={0,6,1,7,8,9};
   for(int i=0;i<6;i++)
   {
      int index=averages[i]; bool visible=UIIndicatorWindow(index)>=0;
      UIButton(UIIndicatorLabel(index)+(visible ? "开" : "关"),12+i*90,y,82,50+index,visible);
   }
   for(int i=0;i<4;i++)
   {
      int index=2+i; bool visible=UIIndicatorWindow(index)>=0;
      UIButton(UIIndicatorLabel(index)+(visible ? "开" : "关"),12+i*90,y+34,82,50+index,visible);
   }
   bool shortSet=UIIndicatorWindow(0)>=0 && UIIndicatorWindow(6)>=0 && UIIndicatorWindow(1)>=0;
   bool trendSet=UIIndicatorWindow(1)>=0 && UIIndicatorWindow(7)>=0 && UIIndicatorWindow(9)>=0;
   UIButton("短线组",372,y+34,82,60,shortSet);
   UIButton("趋势组",462,y+34,82,61,trendSet);
   for(int i=0;i<6;i++)
   {
      int index=10+i; bool visible=UIIndicatorWindow(index)>=0;
      UIButton(UIIndicatorLabel(index)+(visible ? "开" : "关"),12+i*90,y+68,82,70+i,visible);
   }
}
int HitAction(const int mouseX,const int mouseY)
{
   double x=(mouseX-uiX)/panelScale,y=(mouseY-uiY)/panelScale;
   for(int i=0;i<ArraySize(uiHits);i++)
      if(x>=uiHits[i].x && x<uiHits[i].x+uiHits[i].w && y>=uiHits[i].y && y<uiHits[i].y+uiHits[i].h)
         return uiHits[i].action;
   return 0;
}
bool UIMovingAverageGroup(const bool trendGroup)
{
   int selected[3];
   selected[0]=trendGroup ? 1 : 0; selected[1]=trendGroup ? 7 : 6; selected[2]=trendGroup ? 9 : 1;
   // 先显示所选均线；任一加载失败时保留原有线，不清空图表。
   for(int i=0;i<3;i++) if(!UIIndicatorSet(selected[i],true)) return false;
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if(UIIsMovingAverage(i) && i!=selected[0] && i!=selected[1] && i!=selected[2]) UIIndicatorSet(i,false);
   return true;
}

void ViewAction(const int action)
{
   if(action==1) uiCollapsed=!uiCollapsed;
   else if(action==2 || action==3) uiStatistics=action==3;
   else if(action>=30 && action<=44)
   {
      if(action<=32) { statsPeriod=action-30; statsReview=0; statsDirty=true; statsLastAttempt=0; }
      else if(action<=35)
      {
         if(action==33) statsOffsets[statsPeriod]--;
         else if(action==34) statsOffsets[statsPeriod]=0;
         else statsOffsets[statsPeriod]++;
         statsReview=0; statsDirty=true; statsLastAttempt=0;
      }
      else if(action<=39) statsDetail=action-36;
      else if(action<=42) { statsFilter=action-40; statsReview=0; statsDirty=true; statsLastAttempt=0; }
      else if(action==43) statsReview=MathMin(statsReview+1,MathMax(ArraySize(statsTrades)-1,0));
      else statsReview=MathMax(statsReview-1,0);
   }
   else if(action>=50 && action<=59) UIIndicatorSet(action-50,UIIndicatorWindow(action-50)<0);
   else if(action>=70 && action<=75) UIIndicatorSet(action-60,UIIndicatorWindow(action-60)<0);
   else if(action==60 || action==61) UIMovingAverageGroup(action==61);
   else if(action==27) { uiPointLines=!uiPointLines; DrawLevels(); }
   else return;
   // 先完成图表命令，再按实际状态画工具栏。
   ChartRedraw(0); Panel(); SaveView();
}
bool EnsurePanel(const int logicalHeight)
{
   double dpi=(double)TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0;
   int chartWidth=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),chartHeight=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   panelScale=MathMax(0.70,MathMin(MathMax(0.85,dpi),1.5));
   if(chartWidth>40) panelScale=MathMin(panelScale,(chartWidth-20)/560.0);
   if(chartHeight>60) panelScale=MathMin(panelScale,(chartHeight-40)/(double)logicalHeight);
   panelScale=MathMax(panelScale,0.45);
   int width=UIPx(560),height=UIPx(logicalHeight);
   if(!panelReady || ObjectFind(0,VIEW+"CANVAS")<0 || width!=panelWidth || height!=panelHeight)
   {
      if(panelReady) panelCanvas.Destroy();
      if(!panelCanvas.CreateBitmapLabel(ChartID(),0,VIEW+"CANVAS",uiX,uiY,width,height,COLOR_FORMAT_ARGB_NORMALIZE))
         return false;
      panelReady=true; panelWidth=width; panelHeight=height;
      ObjectSetInteger(0,VIEW+"CANVAS",OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,VIEW+"CANVAS",OBJPROP_BACK,false);
      ObjectSetInteger(0,VIEW+"CANVAS",OBJPROP_ZORDER,1);
   }
   MovePanel();
   return true;
}
void Panel()
{
   ulong tickets[]; double volume=0,pnl=0; int protectedCount=0,tpCount=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !OwnSelected()) continue;
      int n=ArraySize(tickets); ArrayResize(tickets,n+1); tickets[n]=ticket;
      volume+=PositionGetDouble(POSITION_VOLUME);
      pnl+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      if(PositionGetDouble(POSITION_SL)>0) protectedCount++;
      if(PositionGetDouble(POSITION_TP)>0) tpCount++;
   }
   int count=ArraySize(tickets),visible=MathMin(count,3),positionHeight=MathMax(visible,1)*72;
   int levelRows=MathMax((ArraySize(levels)+5)/6,1),pointY=294+positionHeight+10;
   int pointHeight=52+levelRows*30,signalY=pointY+pointHeight+10;
   int height=uiCollapsed ? (uiStatistics ? 87 : 187) : uiStatistics ? 499 : signalY+101;
   if(!EnsurePanel(height)) return;
   ArrayResize(uiHits,0);
   panelCanvas.Erase(UIInk(UI_ROOT));
   UIRound(0,0,560,height,UI_ROOT);
   panelCanvas.FillRectangle(0,0,UIPx(559),UIPx(39),UIInk(UI_HEADER));
   panelCanvas.FillRectangle(0,0,UIPx(3),UIPx(39),UIInk(UI_ACCENT));
   UIText(_Symbol+(uiStatistics ? " · 交易统计" : " · T哥点位"),14,10,275,12,UI_TEXT);
   // 点位时钟来自UTC，标题按北京时间显示；不使用券商时区推算。
   UIText(TimeToString(TimeGMT()+8*3600,TIME_SECONDS),288,12,100,10,UI_MUTED,true);
   UIButton(uiCollapsed ? "+" : "−",396,7,30,1);
   UIText(启用真实交易 ? "模式 · 交易" : "模式 · 观察",434,13,112,9.5,启用真实交易 ? UI_ACCENT : UI_WARN);

   // 统计页面只显示统计导航；指标开关属于持仓/看盘页面。
   if(!uiStatistics) ChartTools(uiCollapsed ? 49 : 88);
   ObjectSetString(0,VIEW+"CANVAS",OBJPROP_TOOLTIP,"拖动标题移动面板；−收起 / +展开；指标配置只影响显示 · "+feedStatus+" · 来源 "+sourceSender+" · 消息 "+identity+" · "+uiIndicatorNotice);
   if(uiCollapsed)
   {
      if(uiStatistics)
      {
         UIButton("持仓",12,49,68,2,false); UIButton("统计",88,49,68,3,true);
         UIText("点击 + 展开交易统计",170,56,374,9.5,UI_MUTED);
      }
      else
      {
         UIText("M5/M1策略 · "+IntegerToString(count)+"单 · "+reason,14,154,436,9,UI_MUTED);
         UIButton(uiPointLines ? "点位线开" : "点位线关",462,151,82,27,uiPointLines);
      }
      panelCanvas.Update(); return;
   }
   UIButton("持仓",12,49,68,2,!uiStatistics);
   UIButton("统计",88,49,68,3,uiStatistics);
   if(uiStatistics) UIText("已平仓交易 · 当前品种",170,56,374,9.5,UI_MUTED);
   else
   {
      UIText("M5 · MA5 + M1收线",170,56,186,9.5,UI_MUTED);
      UIText(StringFormat("%.2f手/单",每次开仓手数),366,55,88,9,UI_MUTED,true);
      UIButton(uiPointLines ? "点位线开" : "点位线关",462,49,82,27,uiPointLines);
   }

   if(uiStatistics) { StatsPanel(); return; }
   UICard(12,198,536,76,UI_CARD);
   string titles[4]={"浮盈","风险","持仓","保护"};
   string values[4]={DoubleToString(pnl,2),dayStopped ? "已限仓" : count==0 ? "空仓" : "持仓中",
                     IntegerToString(count)+"单","SL "+IntegerToString(protectedCount)+"/"+IntegerToString(count)};
   string captions[4]={AccountInfoString(ACCOUNT_CURRENCY),StringFormat("日回撤上限 %.1f%%",每日权益回撤上限百分比),
                       DoubleToString(volume,2)+"手","TP "+IntegerToString(tpCount)+"/"+IntegerToString(count)};
   for(int i=0;i<4;i++)
   {
      int x=24+i*134;
      if(i>0) panelCanvas.FillRectangle(UIPx(x-12),UIPx(210),UIPx(x-12),UIPx(261),UIInk(UI_BORDER));
      UIText(titles[i],x,208,108,9.5,UI_MUTED);
      color valueInk=i==0 ? (pnl>0 ? UI_GAIN : pnl<0 ? UI_LOSS : UI_MUTED) :
                     i==2 ? UI_ACCENT : dayStopped && i==1 ? UI_WARN : UI_TEXT;
      UIText(values[i],x,226,110,i==0 || i==2 ? 16 : 13,valueInk);
      UIText(captions[i],x,255,112,8.5,UI_MUTED);
   }
   UIText("持仓明细 · "+IntegerToString(count)+"笔",14,281,300,10,UI_TEXT);
   UIText(count>3 ? "显示最近3笔" : "仅本EA持仓",350,281,194,9,UI_DIM,true);

   for(int row=0;row<MathMax(visible,1);row++)
   {
      int y=300+row*72;
      UICard(12,y,536,64,UI_ROW);
      if(count==0)
      {
         panelCanvas.FillRectangle(UIPx(13),UIPx(y+12),UIPx(15),UIPx(y+51),UIInk(UI_ACCENT));
         UIText("当前没有本EA持仓",28,y+12,480,11,UI_TEXT);
         UIText("机会出现后，成交价、止损与止盈将在这里显示",28,y+37,480,9.5,UI_MUTED);
         break;
      }
      if(!PositionSelectByTicket(tickets[row])) continue;
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      color sideInk=buy ? UI_ACCENT : UI_SELL;
      double profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      UIText(buy ? "BUY" : "SELL",24,y+9,54,11,sideInk);
      UIText("#"+IntegerToString((long)tickets[row])+" · "+DoubleToString(PositionGetDouble(POSITION_VOLUME),2)+"手",84,y+11,280,9.5,UI_MUTED);
      UIText((profit>0 ? "+" : "")+DoubleToString(profit,2),382,y+8,150,13,profit>0 ? UI_GAIN : profit<0 ? UI_LOSS : UI_MUTED,true);
      string priceTexts[3]={"入场 "+DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN),_Digits),
                          "SL "+(PositionGetDouble(POSITION_SL)>0 ? DoubleToString(PositionGetDouble(POSITION_SL),_Digits) : "未设置"),
                          "TP "+(PositionGetDouble(POSITION_TP)>0 ? DoubleToString(PositionGetDouble(POSITION_TP),_Digits) : "未设置")};
      for(int j=0;j<3;j++) UIText(priceTexts[j],24+j*172,y+38,158,9.5,UI_TEXT);
   }

   UICard(12,pointY,536,pointHeight,UI_ROW);
   UIText("老师点位",24,pointY+10,150,10.5,UI_TEXT);
   string source=sourceKind=="teacher" ? "T哥原文" : sourceKind=="" ? "等待来源" : "群友转述";
   UIText(source+(feedActive ? " · 当前参考" : " · 暂停"),330,pointY+10,204,9.5,feedActive ? UI_ACCENT : UI_WARN,true);
   for(int i=0;i<ArraySize(levels);i++)
   {
      int x=24+(i%6)*85,y=pointY+34+(i/6)*30;
      UICard(x,y,77,24,feedActive ? C'19,59,67' : UI_HEADER);
      UIText(DoubleToString(levels[i],_Digits),x+5,y+4,67,9.5,feedActive ? C'105,221,210' : UI_DIM);
   }
   if(ArraySize(levels)==0) UIText("等待飞书同步完整点位",24,pointY+37,490,10,UI_MUTED);
   string sourceAt=sourceTime>0 ? TimeToString(sourceTime+8*3600,TIME_DATE|TIME_MINUTES) : "尚未同步";
   UIText("来源时间 "+sourceAt+" · 北京时间",24,pointY+pointHeight-18,494,8.5,UI_DIM);

   UICard(12,signalY,536,56,UI_CARD);
   string trendText=trend>0 ? "M5偏多" : trend<0 ? "M5偏空" : "M5方向未明";
   UIText(trendText,24,signalY+9,140,10,trend>0 ? UI_ACCENT : trend<0 ? UI_SELL : UI_MUTED);
   UIText(StringFormat("保险%.1f / 首批%.1f / 尾仓≤%.1f",保险价格距离,首批止盈价格距离,尾仓目标价格距离),
          190,signalY+10,344,9,UI_MUTED,true);
   UIText(reason,24,signalY+33,508,9.5,UI_TEXT);

   string gate=!启用真实交易 ? "观察模式 · 仅显示信号" : !CanExecute() ? "交易权限、账户或连接未就绪" :
               dayStopped ? "当日权益回撤限制已触发" : pending.kind!=0 ? "请求待服务器确认" : "等待下一次有效机会";
   UICard(12,signalY+64,536,28,UI_HEADER);
   UIText("状态："+gate,24,signalY+70,508,9.5,pending.kind!=0 || dayStopped ? UI_WARN : UI_MUTED);
   panelCanvas.Update();
}
int OnInit()
{
   if(每次开仓手数<=0 || 最大同时持仓<1 || 最大同时持仓>10 ||
      每日权益回撤上限百分比<=0 || 每日权益回撤上限百分比>100 || 最大点差价格<=0 ||
      保险价格距离<=0 || 首批止盈价格距离<=0 || 尾仓目标价格距离<=首批止盈价格距离 ||
      TickSize()<=0 || !ExactLot(每次开仓手数))
      return INIT_PARAMETERS_INCORRECT;
   if(MQLInfoInteger(MQL_TESTER))
   {
      Print("当前版不读取实时Common点位做历史回测，避免未来信息。请使用离线规则回归。");
      return INIT_FAILED;
   }
   if(启用真实交易 && AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   { Print("本版分批只支持Hedging账户"); return INIT_FAILED; }
   accountLogin=AccountInfoInteger(ACCOUNT_LOGIN); accountServer=AccountInfoString(ACCOUNT_SERVER);
   prefix="TG."+IntegerToString((long)Hash(accountServer+"|"+IntegerToString(accountLogin)+"|"+_Symbol+"|"+IntegerToString((long)EA魔法号)))+".";
   // 独占文件句柄跨图表/跨同机终端防重复；观察实例使用独立状态命名空间。
   if(!启用真实交易) prefix+="obs"+IntegerToString(ChartID())+".";
   FolderCreate("FeishuMT5SignalMonitor",FILE_COMMON);
   lockHandle=FileOpen("FeishuMT5SignalMonitor\\"+prefix+"lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(lockHandle==INVALID_HANDLE) { Print("同账户/品种/Magic已有实例"); return INIT_FAILED; }
   execution.SetExpertMagicNumber(EA魔法号); execution.SetDeviationInPoints(30);
   execution.SetTypeFillingBySymbol(_Symbol); execution.SetAsyncMode(false);
   maHandle=iMA(_Symbol,PERIOD_M5,5,0,MODE_SMA,PRICE_CLOSE); atrHandle=iATR(_Symbol,PERIOD_M5,14);
   if(maHandle==INVALID_HANDLE || atrHandle==INVALID_HANDLE) return INIT_FAILED;
   RestorePending(); dayKey=(long)Load("day"); dayBase=Load("base"); dayStopped=Load("stopped")>0;
   InitView();
   readyFrom=TimeCurrent(); ReadFeed(); EventSetTimer(1); Panel();
   return INIT_SUCCEEDED;
}
void OnTimer()
{
   if(busy) return; busy=true;
   ReadFeed(); UpdateDay(); Reconcile(); Manage();
   datetime minute=iTime(_Symbol,PERIOD_M1,1);
   if(minute>0 && minute!=lastMinute)
   {
      lastMinute=minute; Candidate candidate; ZeroMemory(candidate);
      if(Signal(candidate)) Open(candidate);
   }
   Panel(); busy=false;
}
void OnTick() { }
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   // 统计只标脏，不在交易事件里扫描历史或改变pending。
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD || trans.type==TRADE_TRANSACTION_DEAL_UPDATE ||
      trans.type==TRADE_TRANSACTION_DEAL_DELETE) statsDirty=true;
   // 定时器统一读取真实历史，事件回调不提前标记分批/成交完成。
   // 不按Magic粗略认领事件：延迟到达的上一笔REQUEST不能绑定到下一笔pending。
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(!panelReady) return;
   if(id==CHARTEVENT_MOUSE_MOVE)
   {
      int mx=(int)lparam,my=(int)dparam;
      bool leftDown=(StringToInteger(sparam)&1)!=0;
      bool pressed=leftDown && !uiLeftWasDown,released=!leftDown && uiLeftWasDown;
      uiLeftWasDown=leftDown;
      if(pressed)
      {
         uiPressedAction=HitAction(mx,my);
         if(uiPressedAction==0 && mx>=uiX && mx<uiX+UIPx(275) && my>=uiY && my<uiY+UIPx(40))
         {
            uiDragging=true; uiDragDX=mx-uiX; uiDragDY=my-uiY;
            uiOldScroll=ChartGetInteger(0,CHART_MOUSE_SCROLL)!=0;
            ChartSetInteger(0,CHART_MOUSE_SCROLL,false);
         }
      }
      if(uiDragging)
      {
         if(released)
         {
            uiDragging=false; uiPressedAction=0;
            ChartSetInteger(0,CHART_MOUSE_SCROLL,uiOldScroll); SaveView();
         }
         else if(leftDown)
         {
            uiX=mx-uiDragDX; uiY=my-uiDragDY; MovePanel(); ChartRedraw(0);
         }
      }
      else if(released)
      {
         // MOUSE_MOVE也包含鼠标键变化：每次按下/松开只执行一次。
         // CLICK/OBJECT_CLICK是同一手势的其他通知，不再重复切换。
         int action=uiPressedAction; uiPressedAction=0;
         if(action>0 && action==HitAction(mx,my)) ViewAction(action);
      }
   }
   else if(id==CHARTEVENT_CHART_CHANGE) Panel();
}
void OnDeinit(const int why)
{
   EventKillTimer();
   if(uiInitialized)
   {
      if(uiDragging) ChartSetInteger(0,CHART_MOUSE_SCROLL,uiOldScroll);
      SaveView(); ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,uiOldMouseMove);
   }
   CloseViewIndicators();
   if(maHandle!=INVALID_HANDLE) IndicatorRelease(maHandle);
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(lockHandle!=INVALID_HANDLE) FileClose(lockHandle);
   if(panelReady) panelCanvas.Destroy();
   ObjectsDeleteAll(0,VIEW);
}
