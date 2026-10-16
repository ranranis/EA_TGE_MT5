#property strict
#property version "1.71"
#property description "T哥点位：积极入场、分级保护、结构化退出；固定0.02手，独立Magic。"
#include <Trade/Trade.mqh>
#include <Canvas/Canvas.mqh>
// 看盘指标嵌入主EX5，用户仍只需挂载这一份EA。
#resource "Include\\View\\TgeChartOverlay.ex5"
#resource "Include\\View\\TgeChartOscillator.ex5"
#resource "Include\\View\\TgeChartStructure.ex5"

input group "执行与仓位"
input bool   启用真实交易=true;        // 初始模式；关闭时每次加载先观察，面板可手动切换
const double 每次开仓手数=0.02; // 固定0.02手，不从旧set继承其他手数
input int    最大同时持仓=3;
input double 挂单最大离价=50.0;        // 离价超过该值进入休眠，回近后按有效期和结构重新核验
input double 最大点差价格=0.50;         // 黄金报价价格差，不是_Point倍数
input ulong  EA魔法号=560056;
input bool   读取AI即时策略=true;     // 读取本地DeepSeek语义桥；未就绪时等待，不猜方向
const int    冲击短窗毫秒=3000;
const double 逆向冲击速度=0.60;       // 黄金报价价格差/秒，只检查对当前方向不利的净速度
const double 冲击单向比例=0.85;
const double 恢复回拉价格=0.35;
input group "点位触价与持仓退出"
const bool   允许同机会重入=true; // 离开4点至少5秒，再回区允许新机会
input double 保险价格距离=10.0;
input double 首批止盈价格距离=5.0;
input double 尾仓目标价格距离=10.0;

enum TgeHoldingMode
{
   TGE_HOLD_LEGACY=0,   // 旧版分批：到5点判断分批，尾仓默认10点
   TGE_HOLD_STRUCTURE=1,// 新版结构：积极入场、分级保护、结构退出
   TGE_HOLD_FIXED=2     // 固定TP5 / SL10：全量止盈，不分批
};
enum TgeEntryMode
{
   TGE_ENTRY_COMPAT=0,   // 兼容原设置：原来随持单策略变化的入场检查
   TGE_ENTRY_TOUCH=1,    // 原触价检查；独立于持单策略
   TGE_ENTRY_ADAPTIVE=2  // 原行情/消息保护检查；独立于持单策略
};
input group "实盘入场 · 新研判暂不接管实盘"
input TgeEntryMode 入场策略=TGE_ENTRY_COMPAT;
input group "持单策略 · 切换只影响新开仓"
input TgeHoldingMode 持单策略=TGE_HOLD_STRUCTURE;
bool 启用积极持单=false; // 由下拉选项派生，兼容既有新策略调用链。
input group "积极持单 · 开关仅影响新开仓"
input double 结构缓冲ATR倍数=0.25;
input double 最小结构风险距离=2.0;
input double 合计风险标准单倍数=2.0; // 标准单=0.02手、保险价格距离；按账户货币计算
input double 减风险触发R=0.5;
input double 保本触发R=1.0;
input double 保本缓冲价格=0.20;       // 估算价格缓冲，不保证覆盖滑点及全部费用
input int    无进展退出分钟=8;
input int    连亏区域冷却分钟=30;
input int    冲击冷却秒数=120;
input int    恢复确认秒数=180;
input group "点位生命周期 · 只影响新入场"
input bool   启用点位结构失效=true;
input double 点位破位缓冲ATR倍数=0.25;
input int    点位破位确认根数=2;       // 已收盘M1，1至5根
input int    点位刺穿冷却秒数=60;
input int    点位破位冷却秒数=180;
input group "消息保护 · 券商服务器时间"
input bool   启用消息日历=true;
input int    重点事件前后分钟=10;     // 美元高重要性：就业、通胀、货币政策
input int    一般高重要性前后分钟=3;
input int    重点事件提前退出分钟=2; // 仅新策略持仓；0关闭主动消息退出

input group "入场研判实验 · 仅观察，不接管交易"
input bool   启用入场观察实验=true;
input int    观察回看分钟=60;           // 连续已收盘M1，20至240
input int    观察边界最少反应次数=2;    // 上下沿分别满足；反应至少间隔3根K
input double 观察收回ATR倍数=0.25;      // 实验阈值，尚未验证盈利能力
input double 观察最小区间ATR倍数=2.0;

input group "自动模拟对比 · 不发送订单"
input bool   启用自动模拟对比=true;
input double 模拟每手往返费用=0.0;     // 账户货币/手；0表示费用未配置，不代表免费
input double 模拟单边滑点价格=0.0;     // 每次进出均作不利滑点，价格差
// 两组固定使用同一0.02手、TP5/SL10，最长持有60分钟；不继承实盘持单设置。

input group "手机点位 TP 标记"
input bool   启用手机标记挂单=false;      // 首次默认状态；之后由面板记忆开关，开启会创建真实0.01手标记挂单
input double 手机标记挂单固定价格=100.0; // 仅黄金；接近挂单价20点时请求撤销

// 以下参数只配置图表显示，不改变M5/M1交易规则。
input group "看盘面板"
input bool   历史成交置于面板后方=true; // 仅调整MT5历史箭头/连线的背景层；卸载时恢复
input int    看盘面板宽度=760;        // 逻辑宽度560~1000；随窗口缩放，字体不横向拉伸
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


input group "看盘结构 · 仅显示"
input ENUM_TIMEFRAMES 看盘框体周期=PERIOD_M5;
input int    看盘近期框根数=5;
input int    看盘震荡最少根数=12;
input double 看盘震荡ATR倍数=1.5;
input int    看盘收缩比较根数=100;
input double 看盘收缩低位百分比=20.0;

const string FEED="FeishuMT5SignalMonitor\\tge_levels.csv";
const string VIEW="TGE_";
// 图表显示和手机TP开关独立于短线候选、仓位及pending状态。
int uiX=8,uiY=24;
bool uiCollapsed=false,uiPointLines=true,uiMobileMarkers=true;

CTrade execution;
double levels[];
string identity="",sourceKind="",sourceSender="",feedStatus="等待首次点位",reason="等待收线";
datetime sourceTime=0,feedTime=0,readyFrom=0,lastMinute=0;
bool feedActive=false,busy=false,stateOK=true;
bool tradeMode=false;
const int TREND_UNKNOWN=2;
int maHandle=INVALID_HANDLE,atrHandle=INVALID_HANDLE,trendFastHandle=INVALID_HANDLE,trendSlowHandle=INVALID_HANDLE;
int lockHandle=INVALID_HANDLE,trend=TREND_UNKNOWN;
double atr=0;
string prefix="";
long accountLogin=0;
string accountServer="";
// 仅记录最近一次收线评估，不作为第二套交易状态。
bool signalRetry=false;
datetime checkingMinute=0,healthBeat=0,healthSync=0,healthCheckpoint=0;
bool healthOK=false,healthPaused=false;
int healthMaxAge=120;
struct EntryView
{
   bool ready,reaction;
   datetime bar;
   int direction,crossings;
   double level,distance,space,ma,m1close;
   string method;
};
EntryView entryView;
string lastDecisionKey="";

// 一个实例只允许一个未确认请求。持久化的是意图，不是“已成交”。
struct Pending
{
   int kind;                 // 1开仓，2分批，3保护修改
   ulong order,position;
   datetime at,bar;
   double volume,sl,tp,level,exitSL,exitFirst,exitTP,exitBE;
   int direction;
   bool fast,adaptive,fixedExit;
   double structure,entryAtr;
   uint originHash;
};
Pending pending;
struct Candidate
{
   bool valid,ai,follow,probe;
   int direction;
   double level,exitSL,exitFirst,exitTP,exitBE;
   datetime bar,followExpiry;
   string method,followKey,aiKey;
   uint originHash;
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
bool SavePending()
{
   // 字段全部保存成功才提交kind；失败保留中断标记，禁止发送请求。
   if(!Store("kind",-1)) return false;
   GlobalVariablesFlush();
   if(!Store("order",(double)pending.order)) return false;
   if(!Store("position",(double)pending.position)) return false;
   if(!Store("at",(double)pending.at)) return false;
   if(!Store("bar",(double)pending.bar)) return false;
   if(!Store("volume",pending.volume)) return false;
   if(!Store("sl",pending.sl)) return false;
   if(!Store("tp",pending.tp)) return false;
   if(!Store("level",pending.level)) return false;
   if(!Store("direction",pending.direction)) return false;
   if(!Store("fast",pending.fast ? 1 : 0)) return false;
   if(!Store("originHash",(double)pending.originHash)) return false;
   if(!Store("exitSL",pending.exitSL)) return false;
   if(!Store("exitFirst",pending.exitFirst)) return false;
   if(!Store("exitBE",pending.exitBE)) return false;
   if(!Store("exitTP",pending.exitTP)) return false;
   if(!Store("adaptive",pending.adaptive ? 1 : 0)) return false;
   if(!Store("structure",pending.structure)) return false;
   if(!Store("entryAtr",pending.entryAtr)) return false;
   if(!Store("fixedExit",pending.fixedExit ? 1 : 0)) return false;
   if(!Store("kind",pending.kind)) return false;
   GlobalVariablesFlush(); return true;
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
   pending.exitSL=Load("exitSL"); pending.exitFirst=Load("exitFirst"); pending.exitBE=Load("exitBE"); pending.exitTP=Load("exitTP");
   pending.fast=Load("fast")==1; pending.originHash=(uint)Load("originHash");
   pending.adaptive=Load("adaptive")==1; pending.structure=Load("structure"); pending.entryAtr=Load("entryAtr");
   pending.fixedExit=Load("fixedExit")==1;
}
bool CanExecute()
{
   return tradeMode && stateOK && lockHandle!=INVALID_HANDLE &&
          AccountInfoInteger(ACCOUNT_LOGIN)==accountLogin && AccountInfoString(ACCOUNT_SERVER)==accountServer &&
          AccountInfoInteger(ACCOUNT_MARGIN_MODE)==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING &&
          TerminalInfoInteger(TERMINAL_CONNECTED) && TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
          MQLInfoInteger(MQL_TRADE_ALLOWED) && AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) &&
          AccountInfoInteger(ACCOUNT_TRADE_EXPERT);
}
// 解释既有执行门槛；不会自动改变权限或解除pending。
string ExecutionBlock()
{
   if(!tradeMode) return "观察模式：暂停交易及自动管理，已有服务器订单仍有效";
   if(!stateOK) return "状态保存失败，停止请求";
   if(lockHandle==INVALID_HANDLE) return "实例锁未就绪";
   if(AccountInfoInteger(ACCOUNT_LOGIN)!=accountLogin || AccountInfoString(ACCOUNT_SERVER)!=accountServer)
      return "账户已切换，请重新加载EA";
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) return "需要Hedging账户";
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) return "MT5连接已断开";
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return "MT5算法交易未开启";
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return "当前EA交易权限未开启";
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_EXPERT)) return "账户不允许EA交易";
   if(pending.kind!=0) return pending.kind<0 ? "状态写入中断，待人工核对" : "上一请求待服务器确认";
   if(OwnCount()>=最大同时持仓) return "本EA持仓已达上限";
   return "";
}
#include "Include/Journal/TgeLifecycle.mqh"

void DecisionLog(const string event,const string detail,const uint retcode=0,const ulong deal=0)
{
   // 日文件只在评估结果变化、请求返回和真实对账时追加；不包含聊天正文。
   string key=event+"|"+identity+"|"+IntegerToString((long)checkingMinute)+"|"+detail;
   if(event=="EVALUATE" && key==lastDecisionKey) return;
   LifeDecision(event,detail,retcode,deal);
   string folder="FeishuMT5SignalMonitor\\decisions";
   FolderCreate(folder,FILE_COMMON);
   string date=TimeToString(TimeGMT(),TIME_DATE); StringReplace(date,".","");
   int h=FileOpen(folder+"\\"+prefix+date+".csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,',',CP_UTF8);
   if(h==INVALID_HANDLE)
   {
      static datetime warned=0;
      if(TimeGMT()-warned>=60) { Print("[T哥决策] 日志暂不可写：",GetLastError()); warned=TimeGMT(); }
      return;
   }
   if(FileSize(h)==0)
      FileWrite(h,"utc","server_time","symbol","event","context_identity","source_kind","source_sender","source_utc",
                "m1_bar","snapshot_ready","level","direction","distance","next_level_space","ma5","m1_close","atr","trend","ma_crossings","m1_reaction","method","detail",
                "request_kind","request_at","request_bar","request_level","order","position_id","volume","sl","tp","retcode","deal");
   FileSeek(h,0,SEEK_END);
   uint written=FileWrite(h,(long)TimeGMT(),(long)TimeCurrent(),_Symbol,event,identity,sourceKind,sourceSender,(long)sourceTime,
             (long)entryView.bar,entryView.ready,entryView.level,entryView.direction,entryView.distance,entryView.space,entryView.ma,entryView.m1close,
             entryView.ready ? atr : 0,entryView.ready ? trend : 0,entryView.crossings,entryView.reaction,entryView.method,detail,
             pending.kind,(long)pending.at,(long)pending.bar,pending.level,pending.order,pending.position,pending.volume,pending.sl,pending.tp,retcode,deal);
   FileFlush(h); FileClose(h);
   if(event=="EVALUATE" && written>0) lastDecisionKey=key;
}
bool FreshQuote(MqlTick &q)
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !SymbolInfoTick(_Symbol,q) ||
      q.bid<=0 || q.ask<q.bid || TickSize()<=0) return false;
   // TimeTradeServer依赖本机时钟，可能落后券商数秒；TimeCurrent是已观测的券商时间。
   // 取较晚者：跟随真实新Tick，同时让估算时钟在断流后继续使旧报价过期。
   long serverNow=(long)MathMax((long)TimeTradeServer(),(long)TimeCurrent());
   long age=serverNow*1000-q.time_msc;
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
   for(int i=0;i<64;i++)
   {
      string name=VIEW+"L"+IntegerToString(i);
      string label=VIEW+"PRICE"+IntegerToString(i);
      if(i>=ArraySize(levels)) { ObjectDelete(0,name); ObjectDelete(0,label); continue; }
      if(ObjectFind(0,name)<0) ObjectCreate(0,name,OBJ_HLINE,0,0,levels[i]);
      ObjectMove(0,name,0,0,levels[i]);
      ObjectSetInteger(0,name,OBJPROP_COLOR,feedActive ? C'38,83,145' : C'145,151,160');
      ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_SOLID);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
      // 点位属于行情背景层，已有对象也更新，避免重新开启后盖住前景Canvas面板。
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,uiPointLines ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
      ObjectSetString(0,name,OBJPROP_TEXT,"T点位 "+DoubleToString(levels[i],_Digits));
      int px=0,py=0;
      bool shown=uiPointLines && ChartTimePriceToXY(0,0,iTime(_Symbol,_Period,0),levels[i],px,py) &&
                 py>=10 && py<ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0)-10;
      if(!shown) { ObjectDelete(0,label); continue; }
      if(ObjectFind(0,label)<0) ObjectCreate(0,label,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,label,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
      ObjectSetInteger(0,label,OBJPROP_ANCHOR,ANCHOR_RIGHT_LOWER);
      ObjectSetInteger(0,label,OBJPROP_XDISTANCE,8);
      ObjectSetInteger(0,label,OBJPROP_YDISTANCE,py-2);
      ObjectSetInteger(0,label,OBJPROP_COLOR,feedActive ? C'38,83,145' : C'95,101,110');
      ObjectSetInteger(0,label,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,label,OBJPROP_BACK,true);
      ObjectSetInteger(0,label,OBJPROP_SELECTABLE,false);
      ObjectSetString(0,label,OBJPROP_FONT,"Arial");
      ObjectSetString(0,label,OBJPROP_TEXT,DoubleToString(levels[i],_Digits));
      ObjectSetString(0,label,OBJPROP_TOOLTIP,"点位价格（仅显示）");
   }
}
void ReadHealth()
{
   int h=FileOpen("FeishuMT5SignalMonitor\\tge_health.csv",FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ,0,CP_UTF8);
   if(h==INVALID_HANDLE) return;
   string line=FileSize(h)<=1024 ? FileReadString(h) : ""; FileClose(h);
   string fields[];
   if(StringSplit(line,',',fields)!=9 || fields[0]!="HEALTH" || fields[1]!="1" || fields[8]!="END") return;
   for(int i=2;i<=7;i++) if(!Number(fields[i])) return;
   datetime beat=(datetime)StringToInteger(fields[2]),sync=(datetime)StringToInteger(fields[3]),checkpoint=(datetime)StringToInteger(fields[4]);
   int age=(int)StringToInteger(fields[7]);
   if(beat<=0 || beat>TimeGMT()+5 || sync>beat+5 || checkpoint>beat+5 || age<1 || age>86400 ||
      (fields[5]!="0" && fields[5]!="1") || (fields[6]!="0" && fields[6]!="1")) return;
   healthBeat=beat; healthSync=sync; healthCheckpoint=checkpoint;
   healthOK=fields[5]=="1"; healthPaused=fields[6]=="1"; healthMaxAge=age;
}
string SyncStatus()
{
   if(healthBeat<=0) return "同步状态未知（等待监控新版）";
   if(TimeGMT()-healthBeat>10) return "监控心跳中断";
   if(healthPaused) return "监控已暂停";
   if(!healthOK) return "飞书同步失败";
   if(healthSync<=0 || healthCheckpoint<=0 || TimeGMT()-healthSync>healthMaxAge || TimeGMT()-healthCheckpoint>healthMaxAge)
      return "飞书同步延迟";
   return "监控在线 · 飞书同步正常";
}

#include "Include/Trading/TgeAISignals.mqh"

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
          code==TRADE_RETCODE_INVALID_FILL || code==TRADE_RETCODE_LIMIT_VOLUME ||
           code==TRADE_RETCODE_INVALID_EXPIRATION || code==TRADE_RETCODE_TOO_MANY_REQUESTS ||
           code==TRADE_RETCODE_SERVER_DISABLES_AT || code==TRADE_RETCODE_CLIENT_DISABLES_AT ||
           code==TRADE_RETCODE_FROZEN || code==TRADE_RETCODE_ONLY_REAL ||
           code==TRADE_RETCODE_LIMIT_ORDERS || code==TRADE_RETCODE_INVALID_ORDER ||
           code==TRADE_RETCODE_INVALID_CLOSE_VOLUME || code==TRADE_RETCODE_LIMIT_POSITIONS ||
           code==TRADE_RETCODE_LONG_ONLY || code==TRADE_RETCODE_SHORT_ONLY ||
           code==TRADE_RETCODE_CLOSE_ONLY || code==TRADE_RETCODE_FIFO_CLOSE ||
           code==TRADE_RETCODE_HEDGE_PROHIBITED;
}
void RecordResult(CTrade &requestTrade)
{
   uint code=requestTrade.ResultRetcode();
   pending.order=requestTrade.ResultOrder();
   if(pending.order==0 && requestTrade.ResultDeal()>0 && HistoryDealSelect(requestTrade.ResultDeal()))
      pending.order=(ulong)HistoryDealGetInteger(requestTrade.ResultDeal(),DEAL_ORDER);
   PrintFormat("[T哥请求] 动作=%d retcode=%u order=%I64u deal=%I64u %s",
                pending.kind,code,pending.order,requestTrade.ResultDeal(),requestTrade.ResultComment());
   DecisionLog("REQUEST_RESULT",requestTrade.ResultComment(),code,requestTrade.ResultDeal());
   if(ExplicitReject(code) || (pending.kind==3 && code==TRADE_RETCODE_NO_CHANGES))
   {
      if(pending.kind==1 && pending.fast)
      {
         string key=AIKeyFromHash(pending.originHash,pending.level,pending.direction);
         Store(key,0); Store(SharedVisitKey(pending.level,pending.direction),0); Store(SharedVisitKey(pending.level,pending.direction)+"r",(double)(TimeGMT()+5)); GlobalVariablesFlush();
      }
      ClearPending(); reason=code==TRADE_RETCODE_NO_CHANGES ? "服务器确认无需修改，重新核对实际保护价" :
                             "请求被明确拒绝；老师5秒后可复查，学生本条不再尝试";
   }
   else { if(pending.kind==1) MergeOpportunity(pending.direction,pending.level); SavePending(); reason="请求已发送，等待真实成交/持仓确认"; } // 未知结果不补发
}
// 只用于尚未调用交易接口的本地中止，未知服务器结果不得走此路径。
void AbortUnsent(const bool releaseVisit=false)
{
   if(!stateOK) return;
   DecisionLog("REQUEST_ABORTED","发送前执行条件变化；未调用交易接口，撤销本地意图");
   if(releaseVisit && pending.kind==1 && pending.fast)
   {
      Store(AIKeyFromHash(pending.originHash,pending.level,pending.direction),0);
      Store(SharedVisitKey(pending.level,pending.direction),0);
      GlobalVariablesFlush();
      if(!stateOK) return;
   }
   ClearPending(); reason="发送前条件变化，本次未发送，等待重新评估";
}
bool EntryOrderMatches(const ulong order)
{
   return HistoryOrderGetString(order,ORDER_SYMBOL)==_Symbol &&
          (ulong)HistoryOrderGetInteger(order,ORDER_MAGIC)==EA魔法号 &&
          HistoryOrderGetInteger(order,ORDER_TIME_SETUP)>=pending.at &&
          HistoryOrderGetInteger(order,ORDER_TYPE)==(pending.direction>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
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
// 将请求的明确退出价绑定真实POSITION_IDENTIFIER；请求不等于成交，重启靠pending补写。
string ExitKey(const ulong id) { return "exit"+IntegerToString((long)id)+"."; }
bool SaveEntryExits()
{
   bool found=false;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if((ulong)HistoryDealGetInteger(deal,DEAL_ORDER)!=pending.order ||
         HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_IN ||
         (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=EA魔法号 ||
         HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
      ulong id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(id==0) return false;
      string key=ExitKey(id);
      if(!Store(key+"ready",0) || !Store(key+"origin",(double)pending.originHash) || !Store(key+"sl",pending.exitSL) ||
         !Store(key+"first",pending.exitFirst) || !Store(key+"be",pending.exitBE) || !Store(key+"tp",pending.exitTP) ||
         !Store(key+"adaptive",pending.adaptive ? 1 : 0) || !Store(key+"initialSL",pending.sl) ||
         !Store(key+"level",pending.level) || !Store(key+"structure",pending.structure) ||
          !Store(key+"fixedExit",pending.fixedExit ? 1 : 0) ||
         !Store(key+"entryAtr",pending.entryAtr) || !Store(key+"ready",1)) return false;
      LifeEntry(id);
      found=true;
   }
   GlobalVariablesFlush(); return found;
}
double FirstExit(const ulong id,const int sign,const double open,const double tp)
{
   string key=ExitKey(id);
   double first=Load(key+"ready")==1 ? Load(key+"first") : 0;
   if(first<=0) first=open+sign*首批止盈价格距离;
   // 近目标小于首批距离时由服务器TP全量退出，不把TP改到障碍之后。
   return tp>0 && sign*(first-tp)>=-TickSize() ? tp : Align(first,-sign);
}
// 平仓以POSITION_IDENTIFIER关联完整生命周期；服务器SL/TP的退出Magic不必等于EA。
// 返回true只代表真实历史和剩余仓位已确认，绝不靠超时或CTrade返回值解锁。
bool ReconcileExit()
{
   if(pending.position==0 || !HistorySelectByPosition(pending.position)) return false;
   double entered=0,exited=0;
   int direction=0; ulong match=0; bool ambiguous=false,owned=false;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0 || (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID)!=pending.position ||
         HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) return false;
      long entry=HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry==DEAL_ENTRY_INOUT) return false;
      if(entry==DEAL_ENTRY_IN)
      {
         if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=EA魔法号) return false;
         int sign=HistoryDealGetInteger(deal,DEAL_TYPE)==DEAL_TYPE_BUY ? 1 : -1;
         if(direction!=0 && direction!=sign) return false;
         direction=sign; owned=true; entered+=HistoryDealGetDouble(deal,DEAL_VOLUME);
      }
      if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_OUT_BY) continue;
      exited+=HistoryDealGetDouble(deal,DEAL_VOLUME);
      if(HistoryDealGetInteger(deal,DEAL_TIME)<pending.at ||
         (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=EA魔法号) continue;
      ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
      if(order==0) continue;
      if(match>0 && match!=order) ambiguous=true;
      match=order;
   }
   if(!owned || entered<=0 || exited>entered+1e-8) return false;
   // 已知仍在服务器上的请求不能提前解锁；仓位暂不可见也不等于已平仓。
   if(pending.order>0 && OrderSelect(pending.order)) return false;
   ulong ticket=PositionById(pending.position);
   if(ticket==0)
   {
      if(MathAbs(entered-exited)>1e-8) return false;
      DecisionLog("POSITION_CLOSED","真实持仓历史进出量一致，确认完整平仓并恢复请求队列");
      ClearPending(); reason="历史成交已确认完整平仓"; return true;
   }
   // 部分平仓必须同时对上真实剩余量，不能用一次部分成交当作全量完成。
   if(MathAbs(entered-exited-PositionGetDouble(POSITION_VOLUME))>1e-8) return false;
   bool known=false;
   if(pending.order>0 && HistoryOrderSelect(pending.order))
      known=HistoryOrderGetString(pending.order,ORDER_SYMBOL)==_Symbol &&
            (ulong)HistoryOrderGetInteger(pending.order,ORDER_POSITION_ID)==pending.position &&
            (ulong)HistoryOrderGetInteger(pending.order,ORDER_MAGIC)==EA魔法号 &&
            HistoryOrderGetInteger(pending.order,ORDER_TIME_SETUP)>=pending.at &&
            HistoryOrderGetInteger(pending.order,ORDER_TYPE)==(direction>0 ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
   // 旧版可能写入开仓订单号。仅有唯一、同仓位、请求之后的真实退出订单才补绑。
   if(!known)
   {
      if(match==0 || ambiguous) return false;
      pending.order=match; SavePending();
   }
   if(!stateOK || !FinalOrderConfirmed(pending.order)) return false;
   DecisionLog("ORDER_RECONCILED","平仓订单终态、真实退出成交及剩余持仓量已对账");
   ClearPending(); reason="平仓成交已对账，继续管理剩余持仓"; return true;
}

void Reconcile()
{
   if(pending.kind==0 || !TerminalInfoInteger(TERMINAL_CONNECTED)) return;
   if(pending.kind<0) { reason="上次状态写入中断，待人工核对请求"; return; }
   if(pending.kind==2)
   {
      if(!ReconcileExit() && TimeCurrent()-pending.at>30)
         reason="平仓请求尚未完成真实成交对账，暂停新请求（查看日志）";
      return;
   }
   if(pending.kind==3)
   {
      ulong ticket=PositionById(pending.position);
      if(ticket>0)
      {
         double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP);
         if(sl>0 && pending.direction*(sl-pending.sl)>=-TickSize()*0.5 && MathAbs(tp-pending.tp)<TickSize()*0.5)
         { DecisionLog("POSITION_CONFIRMED","持仓SL/TP已与请求对齐"); ClearPending(); reason="服务器已确认保护价"; return; }
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
         if(inVol>0 && outVol+1e-8>=inVol)
         { DecisionLog("POSITION_CLOSED","历史退出量确认完整平仓"); ClearPending(); reason="历史成交已确认完整平仓"; }
      }
      return;
   }
   bool entryKnown=pending.kind==1 && pending.order>0 &&
                   HistoryOrderSelect(pending.order) && EntryOrderMatches(pending.order);
   if(pending.kind==1 && !entryKnown && HistorySelect(pending.at-60,TimeCurrent()+1))
   {
      string tag=EntryTag(); ulong match=0; bool ambiguous=false;
      for(int i=HistoryOrdersTotal()-1;i>=0;i--)
      {
         ulong order=HistoryOrderGetTicket(i);
         if(EntryOrderMatches(order) && HistoryOrderGetString(order,ORDER_COMMENT)==tag)
         {
            if(match>0 && match!=order) ambiguous=true;
            match=order;
         }
      }
      if(match>0 && !ambiguous)
      {
         pending.order=match;
         if(!SavePending()) return;
         entryKnown=true;
      }
   }
   if(entryKnown && stateOK && FinalOrderConfirmed(pending.order))
   {
      if(pending.kind==1)
      {
         // 返回结果写回前重启，也由真实订单/Deal对账补齐同机会合并状态。
         double filled=HistoryOrderGetDouble(pending.order,ORDER_VOLUME_INITIAL)-HistoryOrderGetDouble(pending.order,ORDER_VOLUME_CURRENT);
         if(filled>1e-8)
         {
            if(!SaveEntryExits()) { reason="成交退出计划尚未保存，保留请求等待重试"; return; }
            MergeOpportunity(pending.direction,pending.level);
         }
         else if(pending.fast)
         {
            string key=AIKeyFromHash(pending.originHash,pending.level,pending.direction);
            Store(key,0); Store(SharedVisitKey(pending.level,pending.direction)+"r",(double)(TimeGMT()+5));
            Store(SharedVisitKey(pending.level,pending.direction),0); GlobalVariablesFlush();
         }
      }
      DecisionLog("ORDER_RECONCILED","终态订单与实际Deal量已对账（不代表全量成交）"); ClearPending(); reason="请求已对账，等待下一机会";
   }
   if(pending.kind!=0 && TimeCurrent()-pending.at>30)
      reason="请求尚未完成服务器对账，暂停新请求（查看日志）";
}
#include "Include/Trading/TgeAdaptiveStrategy.mqh"

void Open(const Candidate &signal)
{
   string blocked=ExecutionBlock();
   if(!CanExecute() || blocked!="") { reason=blocked; return; }
   MqlTick q; if(!FreshQuote(q) || q.ask-q.bid>最大点差价格) return;
   RefreshPlanValidity(q,true);
   bool allowed=false;
   for(int i=0;i<ArraySize(aiPlans);i++)
      if(Hash(aiPlans[i].id)==signal.originHash && PlanSign(i)==signal.direction && aiPlans[i].level==signal.level)
         allowed=TeacherEntryAllowed(i,q);
   if(!allowed) { reason="提交前来源/区域/优先级检查未通过"; return; }
   int sign=signal.direction;
   double volume=每次开仓手数,entry=sign>0 ? q.ask : q.bid;
   double sl=Align(signal.exitSL>0 ? signal.exitSL : entry-sign*保险价格距离,sign);
   double tp=Align(signal.exitTP>0 ? signal.exitTP : entry+sign*尾仓目标价格距离,-sign);
   double first=signal.exitFirst,structure=0;
   bool fixedExit=持单策略==TGE_HOLD_FIXED;
   if(fixedExit) { sl=Align(entry-sign*10.0,sign); tp=Align(entry+sign*5.0,-sign); first=0; }
   if(启用积极持单 && !AdaptiveEntryPrices(signal,q,sl,first,tp,structure)) return;
   if(启用积极持单 && !AdaptiveRiskAllowed(sign,entry,sl,volume)) return;
   if(!ExactLot(volume) || sign*(entry-sl)<=0 || sign*(tp-entry)<=TickSize() ||
      (first>0 && (sign*(first-entry)<=0 || sign*(tp-first)<=TickSize())) ||
      !Stops(sign,sl,tp,q)) { reason="退出价已错过/顺序无效或券商规格不支持"; return; }
   ENUM_ORDER_TYPE type=sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double margin=0;
   if(!OrderCalcMargin(type,_Symbol,volume,entry,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   { reason="可用保证金不足"; return; }
   MqlTick finalQuote;
   if(!FreshQuote(finalQuote) || finalQuote.ask-finalQuote.bid>最大点差价格 ||
      !InTeacherBand(sign>0 ? finalQuote.ask : finalQuote.bid,signal.level) ||
      MathAbs((sign>0 ? finalQuote.ask : finalQuote.bid)-entry)>TickSize()*0.5) return;
   ZeroMemory(pending); pending.kind=1; pending.at=TimeCurrent(); pending.bar=signal.bar;
   pending.volume=volume; pending.sl=sl; pending.tp=tp; pending.level=signal.level; pending.direction=sign;
   pending.fast=true; pending.originHash=signal.originHash;
   pending.adaptive=启用积极持单; pending.structure=structure; pending.entryAtr=adaptiveATR;
   pending.fixedExit=fixedExit;
   pending.exitSL=pending.adaptive || fixedExit ? sl : signal.exitSL; pending.exitFirst=first;
   pending.exitTP=pending.adaptive || fixedExit ? tp : signal.exitTP; pending.exitBE=fixedExit ? 0 : signal.exitBE;
   if(!SavePending()) return;
   if(!CanExecute()) { AbortUnsent(); return; }
   // 请求前写消费意图；成功状态仍只由真实Deal确认。重启不得重复提交。
   MergeOpportunity(sign,signal.level); if(!CanExecute()) { AbortUnsent(true); return; }
   DecisionLog("REQUEST_INTENT",signal.method+(pending.adaptive ?
               " · 结构风险="+DoubleToString(sign*(entry-sl),2)+" · M1ATR="+DoubleToString(adaptiveATR,2)+
               " · 首批="+DoubleToString(first,_Digits) : ""));
   CTrade openExecution;
   openExecution.SetExpertMagicNumber(EA魔法号); openExecution.SetDeviationInPoints(30);
   openExecution.SetTypeFillingBySymbol(_Symbol); openExecution.SetAsyncMode(false);
   openExecution.PositionOpen(_Symbol,type,volume,entry,sl,tp,EntryTag()); RecordResult(openExecution);
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
string PositionProgress(const ulong id,const int sign,const double open,const double remaining,const double sl)
{
   if(Load(ExitKey(id)+"ready")==1 && Load(ExitKey(id)+"fixedExit")==1)
      return "固定TP5 / SL10 · 全量退出，不分批";
   if(Load(ExitKey(id)+"ready")==1 && Load(ExitKey(id)+"adaptive")==1)
      return AdaptivePositionProgress(id,sign,open,sl);
   // 只读真实Deal和当前SL；pending只显示为“待确认”。
   double initial,closed;
   if(!PositionVolumes(id,initial,closed) || MathAbs(initial-closed-remaining)>1e-8) return "成交历史待核对 · 不推断分批状态";
   double half=LotDown(initial*0.5),minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(half<minimum || initial-half<minimum) return "手数无法分批 · 按全量TP退出";
   string reduced="已减 "+DoubleToString(closed,2)+"手 · ";
   if(closed+1e-8>=half)
   {
      bool protectedPrice=sl>0 && sign*(sl-open)>=-TickSize()*0.5;
      return reduced+(protectedPrice ? "价格保本已确认 · 余仓看TP" :
                      pending.kind==3 && pending.position==id ? "保本请求待确认" : "等待移至价格保本");
   }
   if(pending.kind==2 && pending.position==id) return reduced+"分批请求待确认";
   MqlTick q;
   if(!FreshQuote(q)) return reduced+"报价失效，首批距离不可用";
   double tp=0;
   ulong ticket=PositionById(id); if(ticket>0) tp=PositionGetDouble(POSITION_TP);
   double distance=MathMax(0,sign*(FirstExit(id,sign,open,tp)-(sign>0 ? q.bid : q.ask)));
   return reduced+(distance>0 ? "首批还差 "+DoubleToString(distance,2)+"价差" : "已到首批价，等待执行");
}
void Modify(const ulong ticket,const ulong id,const int sign,const double sl,const double tp)
{
   if(!CanExecute() || pending.kind!=0) return;
   MqlTick q; if(!FreshQuote(q) || !Stops(sign,sl,tp,q)) return;
   if(!PositionSelectByTicket(ticket) || !OwnSelected()) return;
   double current=PositionGetDouble(POSITION_SL);
   if(current>0 && sign*(sl-current)<-TickSize()*0.5) return; // 绝不放宽已有保险
   ZeroMemory(pending); pending.kind=3; pending.position=id; pending.direction=sign;
   pending.sl=sl; pending.tp=tp; pending.at=TimeCurrent();
   if(!SavePending()) return;
   if(!CanExecute()) { AbortUnsent(); return; }
   DecisionLog("REQUEST_INTENT","申请修改SL/TP，尚未确认");
   CTrade modifyExecution;
   modifyExecution.SetExpertMagicNumber(EA魔法号); modifyExecution.SetDeviationInPoints(30);
   modifyExecution.SetTypeFillingBySymbol(_Symbol); modifyExecution.SetAsyncMode(false);
   modifyExecution.PositionModify(ticket,sl,tp); RecordResult(modifyExecution);
}
#include "Include/Trading/TgeTeacherLimits.mqh"

// 1=完整M5连续顺向，可减半；2=尚无完整M5，M1连续顺向继续拿；0=犹豫全平；-1=数据不足。
int ExitCandles(const MqlRates &bars[],const int sign,const datetime opened,const int period,const datetime now)
{
   int used=0; bool clean=true; datetime last=0;
   for(int i=0;i<ArraySize(bars);i++)
   {
      if(bars[i].time<opened || bars[i].time+period>now) continue;
      if(last>0 && MathAbs((double)(bars[i].time-last))!=period) return -1;
      last=bars[i].time;
      used++;
      if(sign*(bars[i].close-bars[i].open)<=TickSize()*0.5) clean=false; // 反向/十字K均视为犹豫
   }
   return used>0 ? (clean ? 1 : 0) : -1;
}
int ExitRhythm(const int sign,const datetime opened)
{
   MqlRates bars[]; datetime now=TimeCurrent();
   int shift=iBarShift(_Symbol,PERIOD_M5,opened,false);
   if(shift<0) return -1;
   int count=MathMin(shift,512);
   if(count>0)
   {
      if(CopyRates(_Symbol,PERIOD_M5,1,count,bars)!=count) return -1;
      // 只检查开仓后完整形成的K线；第0根价格永远不参与。
      int mode=ExitCandles(bars,sign,opened,300,now);
      if(mode>=0) return mode;
   }
   shift=iBarShift(_Symbol,PERIOD_M1,opened,false); count=MathMin(shift,10);
   if(count<1 || CopyRates(_Symbol,PERIOD_M1,1,count,bars)!=count) return -1;
   int mode=ExitCandles(bars,sign,opened,60,now);
   return mode==1 ? 2 : mode;
}
void RefreshEntryExits(const string key,const int sign)
{
   // 仅更新已由入场Deal绑定的同一计划；取消计划不等于授权平掉已有持仓。
   if(!AIChannelReady() || Load(key+"origin")==0) return;
   for(int i=0;i<ArraySize(aiPlans);i++)
   {
      if(aiPlans[i].kind!="DIRECT" || aiPlans[i].sign!=sign || Hash(aiPlans[i].id)!=(uint)Load(key+"origin")) continue;
      bool changed=false;
      if(aiPlans[i].sl>0 && aiPlans[i].sl!=Load(key+"sl")) { Store(key+"sl",aiPlans[i].sl); changed=true; }
      if(aiPlans[i].tp>0 && aiPlans[i].tp!=Load(key+"tp")) { Store(key+"tp",aiPlans[i].tp); changed=true; }
      if(aiPlans[i].first>0 && aiPlans[i].first!=Load(key+"first"))
      { Store(key+"first",aiPlans[i].first); Store(key+"hit5",0); Store(key+"firstHit",0); changed=true; }
      if(changed) GlobalVariablesFlush();
      return;
   }
}
void RequestExit(const ulong ticket,const ulong id,const double volume,const bool full,const string why)
{
   if(!CanExecute() || pending.kind!=0 || !PositionSelectByTicket(ticket) || !OwnSelected()) return;
   double current=PositionGetDouble(POSITION_VOLUME);
   if(volume<=0 || volume>current+1e-8 || (!full && !ExactLot(volume))) return;
   ZeroMemory(pending); pending.kind=2; pending.position=id; pending.at=TimeCurrent(); pending.volume=full ? current : volume;
   if(!SavePending()) return;
   if(!CanExecute()) { AbortUnsent(); return; }
   DecisionLog("REQUEST_INTENT",why);
   // CTrade在仓位消失时可能先返回false，尚未清空其旧result。
   // 每次退出使用全新对象，不能把上一笔开仓/改保护的结果写入此次pending。
   CTrade closeExecution;
   closeExecution.SetExpertMagicNumber(EA魔法号); closeExecution.SetDeviationInPoints(30);
   closeExecution.SetTypeFillingBySymbol(_Symbol); closeExecution.SetAsyncMode(false);
   bool sent=full ? closeExecution.PositionClose(ticket,30) :
                   closeExecution.PositionClosePartial(ticket,volume,30);
   uint code=closeExecution.ResultRetcode();
   pending.order=closeExecution.ResultOrder();
   if(closeExecution.ResultDeal()>0 && HistoryDealSelect(closeExecution.ResultDeal()) &&
      (ulong)HistoryDealGetInteger(closeExecution.ResultDeal(),DEAL_POSITION_ID)==id)
      pending.order=(ulong)HistoryDealGetInteger(closeExecution.ResultDeal(),DEAL_ORDER);
   PrintFormat("[T哥请求] 动作=2 retcode=%u order=%I64u deal=%I64u %s",
               code,pending.order,closeExecution.ResultDeal(),closeExecution.ResultComment());
   DecisionLog("REQUEST_RESULT",sent ? closeExecution.ResultComment() :
               "平仓调用未确认："+closeExecution.ResultComment(),code,closeExecution.ResultDeal());
   if(ExplicitReject(code))
   {
      ClearPending(); reason="平仓请求已明确拒绝，后续按实际持仓重新评估";
   }
   else
   {
      SavePending(); reason="平仓结果待真实成交/剩余持仓确认";
   }
}
void ManageFixedExit(const ulong ticket,const ulong id,const int sign,const double open,const double volume,
                     const double sl,const double tp,const MqlTick &q)
{
   // 实际成交均价为基准；已有更紧SL保留，不因模式切换/重新加载放宽。
   double stop=Align(open-sign*10.0,sign),target=Align(open+sign*5.0,-sign);
   if(sl>0 && sign*(sl-stop)>0) stop=sl;
   double price=sign>0 ? q.bid : q.ask;
   if(sign*(price-target)>=0 || sign*(price-stop)<=0)
   { RequestExit(ticket,id,volume,true,"固定TP5 / SL10已触及，全量退出"); return; }
   if(sl<=0 || sign*(stop-sl)>TickSize()*0.5 || MathAbs(target-tp)>TickSize()*0.5)
      Modify(ticket,id,sign,stop,target);
}
void Manage()
{
   if(!CanExecute() || pending.kind!=0) return;
   MqlTick q; if(!FreshQuote(q)) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !OwnSelected() || LimitEntryPending(PositionGetString(POSITION_COMMENT))) continue;
      ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      int sign=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1;
      double open=PositionGetDouble(POSITION_PRICE_OPEN),volume=PositionGetDouble(POSITION_VOLUME);
      double sl=PositionGetDouble(POSITION_SL),tp=PositionGetDouble(POSITION_TP),initial,closed;
      if(!PositionVolumes(id,initial,closed) || MathAbs(initial-closed-volume)>1e-8) continue;
      double half=LotDown(initial*0.5),minimum=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      bool split=half>=minimum && initial-half>=minimum;
      bool partialDone=split && closed+1e-8>=half;
      string key=ExitKey(id);
      if(Load(key+"ready")==1 && Load(key+"fixedExit")==1)
      {
         ManageFixedExit(ticket,id,sign,open,volume,sl,tp,q);
         if(pending.kind!=0) return;
         continue;
      }
      RefreshEntryExits(key,sign);
      if(Load(key+"ready")==1 && Load(key+"adaptive")==1)
      {
         ManageAdaptive(ticket,id,sign,open,volume,sl,tp,initial,closed,opened,q);
         if(pending.kind!=0) return;
         continue;
      }
      bool custom=Load(key+"ready")==1;
      double customSL=custom ? Load(key+"sl") : 0;
      double price=sign>0 ? q.bid : q.ask,goal=custom ? Load(key+"tp") : 0;
      if((goal>0 && sign*(price-goal)>=0) || (customSL>0 && sign*(price-customSL)<=0))
      { RequestExit(ticket,id,volume,true,"同一老师计划更新的SL/TP已触及，申请退出"); return; }
      double required=Align(customSL>0 ? customSL : open-sign*保险价格距离,sign);
      // 保本只在实际减半后启动，不能因请求发送成功提前显示已保护。
      if(partialDone) required=Align(open,sign);
      if(sl>0 && sign*(sl-required)>0) required=sl;
      double target=goal>0 ? Align(goal,-sign) : tp;
      if(target<=0) target=Align(open+sign*尾仓目标价格距离,-sign);
      if(partialDone && (sl<=0 || sign*(sl-open)<-TickSize()*0.5) && !Stops(sign,required,target,q))
      {
         // 已减半但价格回撤至保本附近，券商不允许再放BE：退出余仓，不退回原10点风险。
         RequestExit(ticket,id,volume,true,"减半已确认，保本距离不足，申请退出余仓"); return;
      }
      if(sl<=0 || sign*(required-sl)>TickSize()*0.5 || MathAbs(target-tp)>TickSize()*0.5)
      {
         Modify(ticket,id,sign,required,target); if(pending.kind!=0) return;
      }
      if(partialDone) continue;
      double first=FirstExit(id,sign,open,target);
      if(sign*(price-first)>=0 && Load(key+"hit5")==0) { Store(key+"hit5",1); GlobalVariablesFlush(); }
      if(Load(key+"hit5")==0) continue;
      int mode=ExitRhythm(sign,opened);
      if(mode<0) { reason="已到首批目标，等待完整M1/M5判断"; continue; }
      if(mode==2) { reason="快速获利，M1连续顺向，继续持有"; continue; }
      if(mode==0 || !split)
      { RequestExit(ticket,id,volume,true,"已到首批目标，K线犹豫或手数不可拆，申请全平"); return; }
      double closeVolume=PartialRemaining(initial,closed,volume);
      if(closeVolume>0)
      { RequestExit(ticket,id,closeVolume,false,"已到首批目标，完整M5无反向K，申请减半后保本"); return; }
   }
}
#include "Include/Trading/TgeMobileMarkers.mqh"

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
bool uiStatistics=false,uiIndicators=false,uiPositions=false;
int uiPositionPage=0;
int uiWatchTab=0,uiUndoMask=-1; // 看盘子页与一次撤销，仅影响显示
int statsPeriod=0,statsOffsets[3]={0,0,0},statsFilter=0,statsDetail=0,statsReview=0;
// 1收起；27点位线；50..59旧指标；60/61均线组合；70..75策略辅助指标。

// 这些句柄和偏好仅供看盘，与策略maHandle/atrHandle分开。
// 前六项保留旧显示ID，新增均线使用6..9，避免覆盖已有显示偏好。
string uiIndicatorLabels[20]={"MA5","EMA20","布林","RSI","MACD","ATR","MA10","MA50","MA100","MA200","M5·MA5","M15·MA5","确认拐点","昨高低","ADX","随机KD","近期K线框","震荡箱体","波动收缩","框宽/ATR"};
int uiIndicatorHandles[20]={INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE};
string uiIndicatorNotice="指标随当前图表周期；RSI/MACD/ATR/ADX/KD切换副图；固定MA5只显示已收盘值";

const color UI_ROOT=C'14,19,27',UI_HEADER=C'18,25,35',UI_CARD=C'23,31,43';
const color UI_ROW=C'20,28,39',UI_BORDER=C'37,48,63',UI_TEXT=C'232,238,245';
const color UI_MUTED=C'190,202,216',UI_DIM=C'158,176,197',UI_ACCENT=C'130,199,255';
const color UI_GAIN=C'255,151,117',UI_LOSS=C'107,174,239',UI_WARN=C'235,193,120';
const color UI_SELL=C'240,191,112';
#include "Include/Journal/TgeStatistics.mqh"

int UIPx(const double value) { return (int)MathRound(value*panelScale); }
double UIWidthFactor() { return MathMax(560,MathMin(看盘面板宽度,1000))/560.0; }
int UIXPx(const double value) { return UIPx(value*UIWidthFactor()); }
uint UIInk(const color value) { return ColorToARGB(value,255); }
void UIRound(const int x,const int y,const int w,const int h,const color fill,const int radius=8)
{
   int left=UIXPx(x),top=UIPx(y),width=UIXPx(w),height=UIPx(h);
   int r=MathMax(0,MathMin(UIPx(radius),MathMin((width-1)/2,(height-1)/2)));
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
   // 小字号不再随长页面缩成难辨认的细字；价格继续保持层次。
   int minimumFont=MathMin(80,(int)MathRound(95*panelScale));
   panelCanvas.FontSet("Microsoft YaHei UI",-MathMax((int)MathRound(size*10*panelScale),minimumFont));
   int available=UIXPx(width);
   if(panelCanvas.TextWidth(text)>available)
   {
      while(StringLen(text)>0 && panelCanvas.TextWidth(text+"…")>available)
         text=StringSubstr(text,0,StringLen(text)-1);
      text+="…";
   }
   int at=UIXPx(x)+(right ? available-panelCanvas.TextWidth(text) : 0);
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
      if(UIIndicatorWindow(index)>=0) return false;
   }
   if(uiIndicatorHandles[index]!=INVALID_HANDLE) IndicatorRelease(uiIndicatorHandles[index]);
   uiIndicatorHandles[index]=INVALID_HANDLE;
   if(!enabled)
   {
      // 结构框与文字是独立图表对象，关闭时立即清理，不等待指标的OnDeinit。
      // 指标已被手动移除时也清理残留；删除失败则在上方返回，保留原显示。
      if(index>=16) ObjectsDeleteAll(0,UIIndicatorName(index)+".S.");
      ChartRedraw(0);
      return true;
   }
   bool overlay=!UIIsOscillator(index);
   int kind=overlay ? (index>=10 ? index-7 : index==2 ? 2 : index==0 ? 0 : 1) : index>=14 ? index-11 : index-3;
   ENUM_MA_METHOD method=index==0 ? 看盘主均线算法 : 看盘辅助均线算法;
   color lineInk=index==0 ? C'0,83,138' : index==6 ? C'153,76,0' : index==1 ? C'105,52,139' :
                  index==10 ? C'20,55,85' : index==11 ? C'112,62,0' : index==7 ? C'45,45,45' :
                  index==8 ? C'70,63,116' : C'70,83,96';
   ENUM_LINE_STYLE lineStyle=index==7 || index==10 ? STYLE_DASH :
                              index==8 || index==11 ? STYLE_DOT : STYLE_SOLID;
   int lineWidth=lineStyle==STYLE_SOLID ? (index==0 || index==9 ? 3 : 2) : 1;
   int handle=index>=16 ?
       iCustom(_Symbol,ChartPeriod(0),"::Include\\View\\TgeChartStructure.ex5",index-16,UIIndicatorName(index),
               看盘框体周期,看盘近期框根数,看盘震荡最少根数,看盘震荡ATR倍数,看盘ATR周期,
               看盘布林周期,看盘布林标准差,看盘收缩比较根数,看盘收缩低位百分比) : overlay ?
      iCustom(_Symbol,ChartPeriod(0),"::Include\\View\\TgeChartOverlay.ex5",kind,UIIndicatorName(index),
              UIIndicatorPeriod(index),method,看盘指标计算价格,看盘布林标准差,lineInk,lineStyle,lineWidth) :
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
   if(index>=16)
   {
      string tf=EnumToString(看盘框体周期); StringReplace(tf,"PERIOD_","");
      uiIndicatorNotice=UIIndicatorLabel(index)+" · "+tf+"已收盘 · "+
         (index==16 ? "滚动范围，不代表震荡" : index==17 ? "均价±ATR框；竖线标确认时间" :
          index==18 ? "BBW历史低分位，不预判方向" : "框宽与距离均为报价价格差");
      return true;
   }
   uiIndicatorNotice=UIIndicatorLabel(index)+(index==10 || index==11 ? "：固定周期收盘值，投影到当前图表" :
                     index==12 ? "：两根右侧K线收完才确认，箭头延后出现" :
                     index==13 ? "：前一交易日高低，按券商D1日期" : "已显示；指标周期跟随当前图表");
   return true;
}
// 保留旧组合：位0..15为旧指标，位16仍为点位线，新指标使用位17..20。
int UIIndicatorBit(const int index) { return 1<<(index<16 ? index : index+1); }
int UIViewMask()
{
   int mask=uiPointLines ? (1<<16) : 0;
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if(UIIndicatorWindow(i)>=0) mask|=(UIIndicatorBit(i));
   return mask;
}
int UIPresetMask(const int preset)
{
   // 默认简洁看盘：点位、MA5、EMA20和前一交易日高低，避免辅助线互相覆盖。
   if(preset==0) return (1<<0)|(1<<1)|(1<<13)|(1<<16);
   if(preset==1) return (1<<0)|(1<<6)|(1<<1)|(1<<3)|(1<<16);
   if(preset==2) return (1<<1)|(1<<7)|(1<<9)|(1<<14)|(1<<16);
   if(preset==3) return (1<<2)|(1<<13)|(1<<3)|(1<<16);
   if(preset==4) return (1<<0)|(1<<1)|(1<<4)|(1<<16);
   return (1<<10)|(1<<12)|(1<<13)|(1<<15)|(1<<16);
}
string UIPresetLabel(const int preset)
{
   string names[6]={"简洁看盘","短线节奏","趋势延续","区间震荡","动量确认","结构拐点"};
   return names[preset];
}
string UICombinationText(const int mask)
{
   string text="";
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if((mask & (UIIndicatorBit(i)))!=0) text+=(text=="" ? "" : " / ")+UIIndicatorLabel(i);
   return text=="" ? "纯K线" : text;
}
bool UISetMask(const int mask)
{
   int oscillators=0;
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if((mask & (UIIndicatorBit(i)))!=0 && UIIsOscillator(i)) oscillators++;
   if(mask<0 || mask>2097151 || oscillators>1) return false;
   // 先加载目标主图，再加载副图；失败时不主动清空原有显示。
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if((mask & (UIIndicatorBit(i)))!=0 && !UIIsOscillator(i) && !UIIndicatorSet(i,true)) return false;
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if((mask & (UIIndicatorBit(i)))!=0 && UIIsOscillator(i) && !UIIndicatorSet(i,true)) return false;
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if((mask & (UIIndicatorBit(i)))==0 && !UIIndicatorSet(i,false)) return false;
   uiPointLines=(mask & (1<<16))!=0;
   DrawLevels();
   return UIViewMask()==mask;
}
bool UIApplyMask(const int mask)
{
   int previous=UIViewMask();
   if(UISetMask(mask))
   {
      uiIndicatorNotice="当前组合："+UICombinationText(mask);
      return true;
   }
   string detail=uiIndicatorNotice;
   bool restored=UISetMask(previous);
   uiIndicatorNotice=restored ? "切换失败，已恢复原组合："+detail : "切换未完成，请检查实际亮起的指标按钮";
   Print(uiIndicatorNotice);
   return false;
}
void UIFavorite(const int slot,const bool save)
{
   string key=uiPrefix+"favorite"+IntegerToString(slot);
   if(save)
   {
      if(GlobalVariableSet(key,UIViewMask())==0) { uiIndicatorNotice="组合保存失败"; return; }
      GlobalVariablesFlush();
      uiIndicatorNotice="当前指标与点位线已保存到组合"+IntegerToString(slot+1);
   }
   else if(!GlobalVariableCheck(key)) uiIndicatorNotice="组合尚未保存：先选择指标，再点下方保存按钮";
   else UIApplyMask((int)GlobalVariableGet(key));
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

#include "Include/View/TgeEntryObserver.mqh"
#include "Include/Trading/TgePaperTrading.mqh"

void SaveView()
{
   // 显示偏好不写入交易Store，保存失败也不改变交易状态。
   GlobalVariableSet(uiPrefix+"x",uiX); GlobalVariableSet(uiPrefix+"y",uiY);
   GlobalVariableSet(uiPrefix+"fold",uiCollapsed ? 1 : 0);
   GlobalVariableSet(uiPrefix+"lines",uiPointLines ? 1 : 0);
   GlobalVariableSet(uiPrefix+"stats",uiStatistics ? 1 : 0);
   GlobalVariableSet(uiPrefix+"page",uiObserver ? 4 : uiPositions ? 3 : uiIndicators ? 2 : uiStatistics ? 1 : 0);
   GlobalVariableSet(uiPrefix+"watchTab",uiWatchTab);
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
   int page=GlobalVariableCheck(uiPrefix+"page") ? (int)GlobalVariableGet(uiPrefix+"page") :
            GlobalVariableGet(uiPrefix+"stats")>0 ? 1 : 0;
   page=MathMax(0,MathMin(page,4)); uiStatistics=page==1; uiIndicators=page==2; uiPositions=page==3; uiObserver=page==4;
   uiWatchTab=(int)MathMax(0,MathMin(GlobalVariableGet(uiPrefix+"watchTab"),2));
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
void PageTabs(const int y)
{
   UIButton("点位",12,y,58,2,!uiStatistics && !uiIndicators && !uiPositions && !uiObserver);
   UIButton("持仓",78,y,58,5,uiPositions);
   UIButton("统计",144,y,58,3,uiStatistics);
   UIButton("看盘",210,y,58,4,uiIndicators);
   UIButton("研判",276,y,58,9,uiObserver);
   UIButton(uiMobileMarkers ? "手机TP开" : "手机TP关",342,y,110,28,uiMobileMarkers);
   UIButton(uiPointLines ? "点位线开" : "点位线关",462,y,82,27,uiPointLines);
}
void IndicatorPage()
{
   UIText("看盘工作台",16,94,240,17,UI_TEXT);
   UIText("组合沿用输入参数中的周期 · 手工添加的指标保留",16,122,520,9,UI_MUTED);
   UIButton("组合模板",16,146,100,80,uiWatchTab==0);
   UIButton("单项指标",124,146,100,81,uiWatchTab==1);
   UIButton("结构辅助",232,146,92,98,uiWatchTab==2);
   UIButton("撤销切换",332,146,100,92,uiUndoMask>=0);
   UIButton("清空指标",444,146,100,93);
   if(uiWatchTab==0)
   {
      int mask=UIViewMask();
      for(int i=0;i<6;i++)
      {
         int x=16+(i%2)*270,y=188+(i/2)*64;
         UIRound(x,y,258,58,UI_CARD);
         UIButton(UIPresetLabel(i),x+8,y+5,242,82+i,mask==UIPresetMask(i));
         UIText(UICombinationText(UIPresetMask(i)),x+10,y+36,238,8,UI_DIM);
      }
      UIText("我的组合 · 保存当前显示，点击组合可恢复",16,390,528,9,UI_MUTED);
      for(int i=0;i<3;i++)
      {
         string key=uiPrefix+"favorite"+IntegerToString(i);
         bool saved=GlobalVariableCheck(key);
         UIButton("组合"+IntegerToString(i+1)+(saved ? "" : " · 未保存"),16+i*180,416,168,88+i,
                  saved && mask==(int)GlobalVariableGet(key));
         UIButton("保存到 "+IntegerToString(i+1),16+i*180,452,168,94+i);
      }
   }
   else if(uiWatchTab==1)
   {
      UIText("均线",16,192,160,10,UI_MUTED);
      UIText("点位与结构",16,300,200,10,UI_MUTED);
      UIText("波动与动量",16,364,200,10,UI_MUTED);
      ChartTools(222);
   }
   else
   {
      string tf=EnumToString(看盘框体周期); StringReplace(tf,"PERIOD_","");
      UIText("框体与波动 · "+tf+" 已收盘",16,190,528,11,UI_TEXT);
      string notes[4]={"近期高低范围，不等同震荡","边界确认后固定；标实际确认时间",
                       "BBW相对历史收窄，不提示多空","显示框宽、ATR及收盘到上下沿距离"};
      for(int i=0;i<4;i++)
      {
         int y=222+i*58,index=16+i;
         bool visible=UIIndicatorWindow(index)>=0;
         UIButton(UIIndicatorLabel(index)+(visible ? "开" : "关"),16,y,168,100+i,visible);
         UIText(notes[i],200,y+6,340,9,UI_MUTED);
      }
      UIText("白底辨识：名称 + H/L标签 + 实线/虚线",16,466,528,9,UI_MUTED);
   }
   UIRound(12,502,536,74,UI_HEADER);
   UIText(uiIndicatorNotice,26,513,508,9,UI_MUTED);
   UIText("白底高对比配色 · 开/关文字标识 · 仅用于看盘",26,541,508,9,UI_MUTED);
   panelCanvas.Update();
}
void UIButton(const string text,const int x,const int y,const int w,const int action,const bool active=false)
{
   // 导航用底部指示线；开关用状态灯；普通操作保留中性描边。
   bool navigation=action==9 || (action>=2 && action<=5) || (action>=30 && action<=32) ||
                   (action>=36 && action<=42) || action==80 || action==81 || action==98;
   bool toggle=action==27 || action==28 || action==29 || (action>=50 && action<=59) ||
               (action>=70 && action<=75) || (action>=100 && action<=103);
   color edge=active ? C'95,151,200' : C'78,94,114';
   color fill=active ? C'25,49,76' : C'22,30,41';
   UIRound(x,y,w,27,edge,4);
   UIRound(x+1,y+1,w-2,25,fill,3);
   if(navigation && active) UIRound(x+8,y+24,w-16,2,UI_ACCENT,0);
   int inset=w<40 ? 10 : 8;
   UIText(text,x+inset,y+5,w-inset-(toggle ? 22 : inset),9,active ? UI_ACCENT : UI_MUTED);
   if(toggle)
      UIRound(x+w-14,y+10,6,6,active ? UI_ACCENT : UI_DIM,3);
   int n=ArraySize(uiHits); ArrayResize(uiHits,n+1);
   uiHits[n].x=x; uiHits[n].y=y; uiHits[n].w=w; uiHits[n].h=27; uiHits[n].action=action;
}
void ChartTools(const int y)
{
   int averages[6]={0,6,1,7,8,9};
   for(int i=0;i<6;i++)
   {
      int index=averages[i]; bool visible=UIIndicatorWindow(index)>=0;
      UIButton(UIIndicatorLabel(index)+(visible ? "开" : "关"),16+(i%3)*180,y+(i/3)*36,168,50+index,visible);
   }
   bool shortSet=UIIndicatorWindow(0)>=0 && UIIndicatorWindow(6)>=0 && UIIndicatorWindow(1)>=0;
   bool trendSet=UIIndicatorWindow(1)>=0 && UIIndicatorWindow(7)>=0 && UIIndicatorWindow(9)>=0;
   UIButton("短线组",332,y-34,100,60,shortSet);
   UIButton("趋势组",444,y-34,100,61,trendSet);
   for(int i=0;i<4;i++)
   {
      int index=10+i; bool visible=UIIndicatorWindow(index)>=0;
      UIButton(UIIndicatorLabel(index)+(visible ? "开" : "关"),16+i*134,y+102,126,70+i,visible);
   }
   int momentum[6]={2,3,4,5,14,15};
   for(int i=0;i<6;i++)
   {
      int index=momentum[i]; bool visible=UIIndicatorWindow(index)>=0;
      UIButton(UIIndicatorLabel(index)+(visible ? "开" : "关"),16+(i%3)*180,y+166+(i/3)*36,168,
               index>=14 ? index+60 : index+50,visible);
   }
}
int HitAction(const int mouseX,const int mouseY)
{
   double x=(mouseX-uiX)/(panelScale*UIWidthFactor()),y=(mouseY-uiY)/panelScale;
   for(int i=0;i<ArraySize(uiHits);i++)
      if(x>=uiHits[i].x && x<uiHits[i].x+uiHits[i].w && y>=uiHits[i].y && y<uiHits[i].y+uiHits[i].h)
      {
         if(uiHits[i].action==110)
         {
            int index=StatsPointAtX(x,ArraySize(statsTrades));
            return index>=0 ? 1000+index : 0;
         }
         return uiHits[i].action;
      }
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

void ToggleTradeMode()
{
   bool enabled=!tradeMode;
   if(enabled && AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   { reason="无法切换交易模式：需要Hedging账户"; return; }
   if(!Store("tradeMode",enabled ? 1 : 0)) return;
   GlobalVariablesFlush();
   tradeMode=enabled;
   markerDirty=true;
   reason=enabled ? "已切换交易模式，等待执行条件" : "已切换观察模式，暂停交易及自动管理";
   DecisionLog("MODE",reason);
}
void ViewAction(const int action)
{
   int before=UIViewMask();
   bool recordUndo=action==27 || (action>=50 && action<=75) || (action>=82 && action<=90) || action==93 || (action>=100 && action<=103);
   if(action>=2 && action<=5) uiObserver=false;
   if(action==1) uiCollapsed=!uiCollapsed;
    else if(action==2) { uiStatistics=false; uiIndicators=false; uiPositions=false; }
    else if(action==3) { uiStatistics=true; uiIndicators=false; uiPositions=false; }
    else if(action==4) { uiStatistics=false; uiIndicators=true; uiPositions=false; }
    else if(action==5) { uiStatistics=false; uiIndicators=false; uiPositions=true; }
    else if(action==6) uiPositionPage=MathMax(0,uiPositionPage-1);
    else if(action==7) uiPositionPage++;
   else if(action==8)
   {
      int file=FileOpen("FeishuMT5SignalMonitor\\open_point_editor.txt",FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON,0,CP_UTF8);
      if(file!=INVALID_HANDLE)
      {
         FileWriteString(file,IntegerToString((long)TimeGMT())); FileFlush(file); FileClose(file);
         reason="已请求打开点位编辑器；需要新版监控运行";
      }
      else reason="无法打开编辑入口，请从监控看板进入点位编辑器";
   }
   else if(action==9) { uiObserver=true; uiStatistics=false; uiIndicators=false; uiPositions=false; }
   else if(action==205) uiPaperSummary=!uiPaperSummary;
   else if(action>=200 && action<=204) ObserverAction(action);
   else if(action==29) ToggleTradeMode();
   else if(action>=30 && action<=42)
   {
      bool scope=action<=35 || action>=40;
      if(action<=32) statsPeriod=action-30;
      else if(action<=35)
      {
         if(action==33) statsOffsets[statsPeriod]--;
         else if(action==34) statsOffsets[statsPeriod]=0;
         else statsOffsets[statsPeriod]++;
      }
      else if(action<=39) statsDetail=action-36;
      else statsFilter=action-40;
      if(scope)
      {
         statsSelectedId=0; statsPressedId=0; statsReview=0;
         statsDirty=true; statsLastAttempt=0;
      }
   }
   else if(action==43 || action==44 || (action>=111 && action<=133) || action>=1000)
      StatsAction(action);
   else if(action>=50 && action<=59) UIIndicatorSet(action-50,UIIndicatorWindow(action-50)<0);
   else if(action>=70 && action<=75) UIIndicatorSet(action-60,UIIndicatorWindow(action-60)<0);
   else if(action==60 || action==61) UIMovingAverageGroup(action==61);
   else if(action==80 || action==81 || action==98) uiWatchTab=action==98 ? 2 : action-80;
   else if(action>=100 && action<=103) UIIndicatorSet(action-84,UIIndicatorWindow(action-84)<0);
    else if(action>=82 && action<=87) UIApplyMask(UIPresetMask(action-82));
   else if(action>=88 && action<=90) UIFavorite(action-88,false);
   else if(action>=94 && action<=96) UIFavorite(action-94,true);
   else if(action==92)
   {
      if(uiUndoMask<0) uiIndicatorNotice="尚无可撤销的显示切换";
      else if(UIApplyMask(uiUndoMask)) uiUndoMask=-1;
   }
   else if(action==93) UIApplyMask(before & (1<<16));
   else if(action==27) { uiPointLines=!uiPointLines; DrawLevels(); }
   else if(action==28)
   {
      ToggleTgeMobileMarkers();
   }
   else return;
   if(recordUndo && UIViewMask()!=before) uiUndoMask=before;
   // 先完成图表命令，再按实际状态画工具栏。
   Panel(); uiHistoryNextScan=0; SyncHistoryLayer(); SaveView();
}
// MT5原生交易历史对象使用autotrade前缀。面板外以裁切副本保持前景可见，不改原始坐标/颜色/历史开关。
// 保留本次实际修改过的对象，卸载时恢复；不触碰其他指标或用户手动画线。
struct UIHistoryLayer { string name,copy; datetime created; };
uint uiHistoryCopySerial=0;
UIHistoryLayer uiHistoryLayers[];
bool IsNativeTradeHistory(const string name)
{
   if(StringFind(name,"autotrade")!=0 || StringLen(name)<=9) return false;
   string separator=StringSubstr(name,9,1);
   if(separator!=" " && separator!="#") return false;
   if(!ObjectGetInteger(0,name,OBJPROP_HIDDEN)) return false;
   ENUM_OBJECT type=(ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE);
   return type==OBJ_ARROW || type==OBJ_ARROW_BUY || type==OBJ_ARROW_SELL || type==OBJ_TREND;
}
ulong uiHistoryNextScan=0,uiHistoryLastScan=0;
int uiHistoryObjectCount=-1;
string uiHistoryGeometry="";
// Liang-Barsky: 返回线段进入/离开面板的参数；只用于显示，不涉及交易价格。
bool HistoryClipEdge(const double p,const double q,double &enter,double &leave)
{
   if(MathAbs(p)<1e-10) return q>=0;
   double t=q/p;
   if(p<0) { if(t>leave) return false; enter=MathMax(enter,t); }
   else { if(t<enter) return false; leave=MathMin(leave,t); }
   return true;
}
bool HistoryPanelSpan(const double x1,const double y1,const double x2,const double y2,
                      const double left,const double top,const double right,const double bottom,
                      double &enter,double &leave)
{
   enter=0; leave=1;
   double dx=x2-x1,dy=y2-y1;
   return HistoryClipEdge(-dx,x1-left,enter,leave) && HistoryClipEdge(dx,right-x1,enter,leave) &&
          HistoryClipEdge(-dy,y1-top,enter,leave) && HistoryClipEdge(dy,bottom-y1,enter,leave);
}
void HistoryDeleteCopies(const string base)
{
   if(base=="") return;
   if(ObjectFind(0,base+"a")>=0) ObjectDelete(0,base+"a");
   if(ObjectFind(0,base+"b")>=0) ObjectDelete(0,base+"b");
}
bool HistoryCopySegment(const string source,const string name,
                        const datetime t1,const double p1,const datetime t2,const double p2,
                        const double x1,const double y1,const double x2,const double y2,
                        const double from,const double to)
{
   if(to-from<1e-7)
   { if(ObjectFind(0,name)>=0) ObjectDelete(0,name); return true; }
   datetime start=t1,end=t2; double low=p1,high=p2; int window=0;
   if(from>0 && (!ChartXYToTimePrice(0,(int)MathRound(x1+(x2-x1)*from),(int)MathRound(y1+(y2-y1)*from),window,start,low) || window!=0))
      return false;
   if(to<1 && (!ChartXYToTimePrice(0,(int)MathRound(x1+(x2-x1)*to),(int)MathRound(y1+(y2-y1)*to),window,end,high) || window!=0))
      return false;
   if(ObjectFind(0,name)<0 && !ObjectCreate(0,name,OBJ_TREND,0,start,low,end,high)) return false;
   ObjectMove(0,name,0,start,low); ObjectMove(0,name,1,end,high);
   ObjectSetInteger(0,name,OBJPROP_COLOR,ObjectGetInteger(0,source,OBJPROP_COLOR));
   ObjectSetInteger(0,name,OBJPROP_STYLE,ObjectGetInteger(0,source,OBJPROP_STYLE));
   ObjectSetInteger(0,name,OBJPROP_WIDTH,ObjectGetInteger(0,source,OBJPROP_WIDTH));
   ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,ObjectGetInteger(0,source,OBJPROP_TIMEFRAMES));
   ObjectSetInteger(0,name,OBJPROP_RAY_LEFT,false); ObjectSetInteger(0,name,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false); ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true); ObjectSetInteger(0,name,OBJPROP_ZORDER,0);
   ObjectSetString(0,name,OBJPROP_TOOLTIP,"历史成交 · "+source);
   return true;
}
void SyncHistoryLayer()
{
   if(!历史成交置于面板后方 || !panelReady) return;
   int objectCount=ObjectsTotal(0,0); ulong now=GetTickCount64();
   string geometry=IntegerToString(uiX)+"|"+IntegerToString(uiY)+"|"+IntegerToString(panelWidth)+"|"+
      IntegerToString(panelHeight)+"|"+IntegerToString(ChartGetInteger(0,CHART_FIRST_VISIBLE_BAR))+"|"+
      IntegerToString(ChartGetInteger(0,CHART_WIDTH_IN_PIXELS))+"|"+IntegerToString(ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS))+"|"+
      IntegerToString(ChartGetInteger(0,CHART_SCALE))+"|"+
      DoubleToString(ChartGetDouble(0,CHART_PRICE_MIN),_Digits+2)+"|"+DoubleToString(ChartGetDouble(0,CHART_PRICE_MAX),_Digits+2);
   if(objectCount==uiHistoryObjectCount && geometry==uiHistoryGeometry && now<uiHistoryNextScan) return;
   // 拖动中最多10次/秒，松开和按钮切换直接按最终边界处理。
   if(uiDragging && uiHistoryLastScan>0 && now-uiHistoryLastScan<100) return;
   uiHistoryLastScan=now; uiHistoryGeometry=geometry; uiHistoryNextScan=now+5000;
   for(int i=ArraySize(uiHistoryLayers)-1;i>=0;i--)
      if(ObjectFind(0,uiHistoryLayers[i].name)<0 ||
         (datetime)ObjectGetInteger(0,uiHistoryLayers[i].name,OBJPROP_CREATETIME)!=uiHistoryLayers[i].created)
      {
         HistoryDeleteCopies(uiHistoryLayers[i].copy);
         int last=ArraySize(uiHistoryLayers)-1;
         if(i!=last) uiHistoryLayers[i]=uiHistoryLayers[last];
         ArrayResize(uiHistoryLayers,last);
      }
   // 时间轴换算会取到K线时间，留一根K线宽的边距，防止副本端点伸进面板。
   double barWidth=(double)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)/MathMax(1,(int)ChartGetInteger(0,CHART_VISIBLE_BARS));
   double margin=MathMax(8,barWidth+2);
   double left=uiX-margin,top=uiY-margin,right=uiX+panelWidth+margin,bottom=uiY+panelHeight+margin;
   int total=ObjectsTotal(0,0);
   // 先保存名称，创建/删除显示副本不会扰动原生对象的枚举索引。
   string names[]; int count=0;
   for(int i=0;i<total;i++)
   {
      string name=ObjectName(0,i,0);
      if(!IsNativeTradeHistory(name)) continue;
      ArrayResize(names,count+1,256); names[count++]=name;
   }
   for(int i=0;i<count;i++)
   {
      string name=names[i]; int at=-1;
      for(int j=0;j<ArraySize(uiHistoryLayers);j++) if(uiHistoryLayers[j].name==name) { at=j; break; }
      // 用户/终端原本就放在背景的对象，不改其原始设置。
      if(at<0 && ObjectGetInteger(0,name,OBJPROP_BACK)) continue;
      datetime t1=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,0);
      double p1=ObjectGetDouble(0,name,OBJPROP_PRICE,0);
      int x1=0,y1=0,x2=0,y2=0;
      bool mapped=ChartTimePriceToXY(0,0,t1,p1,x1,y1);
      ENUM_OBJECT type=(ENUM_OBJECT)ObjectGetInteger(0,name,OBJPROP_TYPE);
      bool line=type==OBJ_TREND,overlap=false;
      datetime t2=t1; double p2=p1,enter=0,leave=1;
      if(line)
      {
         t2=(datetime)ObjectGetInteger(0,name,OBJPROP_TIME,1); p2=ObjectGetDouble(0,name,OBJPROP_PRICE,1);
         mapped=mapped && ChartTimePriceToXY(0,0,t2,p2,x2,y2);
         if(mapped) overlap=HistoryPanelSpan(x1,y1,x2,y2,left,top,right,bottom,enter,leave);
      }
      else if(mapped) overlap=x1>=left && x1<=right && y1>=top && y1<=bottom;
      if(!overlap)
      {
         if(at>=0)
         {
            if(ObjectGetInteger(0,name,OBJPROP_BACK)) ObjectSetInteger(0,name,OBJPROP_BACK,false);
            HistoryDeleteCopies(uiHistoryLayers[at].copy);
         }
         continue;
      }
      if(at<0)
      {
         at=ArraySize(uiHistoryLayers);
         if(ArrayResize(uiHistoryLayers,at+1)!=at+1) continue;
         uiHistoryLayers[at].name=name;
         uiHistoryLayers[at].created=(datetime)ObjectGetInteger(0,name,OBJPROP_CREATETIME);
         uiHistoryLayers[at].copy=VIEW+"HC"+IntegerToString(++uiHistoryCopySerial);
      }
      if(!ObjectGetInteger(0,name,OBJPROP_BACK)) ObjectSetInteger(0,name,OBJPROP_BACK,true);
      if(line)
      {
         bool first=HistoryCopySegment(name,uiHistoryLayers[at].copy+"a",t1,p1,t2,p2,x1,y1,x2,y2,0,enter);
         bool second=HistoryCopySegment(name,uiHistoryLayers[at].copy+"b",t1,p1,t2,p2,x1,y1,x2,y2,leave,1);
         if(!first || !second)
         {
            // 无法可靠换算时保留原生可见线，不以静默消失代替失败。
            ObjectSetInteger(0,name,OBJPROP_BACK,false); HistoryDeleteCopies(uiHistoryLayers[at].copy);
         }
      }
      else HistoryDeleteCopies(uiHistoryLayers[at].copy);
   }
   uiHistoryObjectCount=ObjectsTotal(0,0);
   ChartRedraw(0);
}
void RestoreHistoryLayer()
{
   for(int i=ArraySize(uiHistoryLayers)-1;i>=0;i--)
   {
      string name=uiHistoryLayers[i].name;
      HistoryDeleteCopies(uiHistoryLayers[i].copy);
      if(ObjectFind(0,name)>=0 && IsNativeTradeHistory(name) &&
         (datetime)ObjectGetInteger(0,name,OBJPROP_CREATETIME)==uiHistoryLayers[i].created &&
         ObjectGetInteger(0,name,OBJPROP_BACK))
         ObjectSetInteger(0,name,OBJPROP_BACK,false);
   }
   ArrayResize(uiHistoryLayers,0);
}

bool EnsurePanel(const int logicalHeight,const int scaleHeight)
{
   double dpi=(double)TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0;
   int chartWidth=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS),chartHeight=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS);
   panelScale=MathMax(0.70,MathMin(MathMax(0.85,dpi),1.5));
   if(chartWidth>40) panelScale=MathMin(panelScale,(chartWidth-20)/(560.0*UIWidthFactor()));
   if(chartHeight>60) panelScale=MathMin(panelScale,(chartHeight-40)/(double)scaleHeight);
   panelScale=MathMax(panelScale,0.45);
   int width=UIXPx(560),height=UIPx(logicalHeight);
   bool alive=panelReady && ObjectFind(0,VIEW+"CANVAS")>=0;
   if(!alive)
   {
      if(panelReady) panelCanvas.Destroy();
      panelReady=false;
      if(!panelCanvas.CreateBitmapLabel(ChartID(),0,VIEW+"CANVAS",uiX,uiY,width,height,COLOR_FORMAT_ARGB_NORMALIZE))
         return false;
      panelReady=true;
      ObjectSetInteger(0,VIEW+"CANVAS",OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,VIEW+"CANVAS",OBJPROP_BACK,false);
      ObjectSetInteger(0,VIEW+"CANVAS",OBJPROP_ZORDER,1);
   }
   else if(width!=panelWidth || height!=panelHeight)
   {
      // 窗口缩放或主动收起才调整像素缓冲，保留同一个图表对象。
      if(!panelCanvas.Resize(width,height)) return false;
   }
   panelWidth=width; panelHeight=height;
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
   ArraySort(tickets);
   ArrayReverse(tickets);
   int count=ArraySize(tickets),positionPages=MathMax(1,(count+3)/4),rowHeight=96;
   uiPositionPage=MathMax(0,MathMin(uiPositionPage,positionPages-1));
   int firstPosition=uiPositionPage*4,visible=MathMin(MathMax(0,count-firstPosition),4);
   int directRows=0,rangeRows=0;
   for(int i=0;i<ArraySize(aiPlans);i++)
       if(aiPlans[i].kind=="DIRECT" || aiPlans[i].kind=="ROLE") directRows++;
       else if(aiPlans[i].kind=="INNER" || aiPlans[i].kind=="OUTER") rangeRows++;
    int planRows=(directRows+2)/3;
    int pointRows=MathMax((ArraySize(levels)+4)/5,1);
   int directHeight=directRows>0 ? 24+planRows*100 : 28;
   int rangeHeight=rangeRows>0 ? 26+rangeRows*48+8 : 0;
   int heroY=88,heroHeight=44+directHeight+rangeHeight+28+pointRows*44+26+32;
   int decisionY=heroY+heroHeight+12,positionY=184;
   // 持仓固定四笔一页；持仓数量和当前页不参与缩放计算。
   int expandedHeight=MathMax(654,decisionY+126);
   int height=uiCollapsed ? 122 : uiStatistics || uiPositions || uiObserver ? 654 : uiIndicators ? 592 : expandedHeight;
   if(!EnsurePanel(height,expandedHeight)) return;
   ArrayResize(uiHits,0);
   panelCanvas.Erase(UIInk(UI_ROOT));
   UIRound(0,0,560,height,UI_ROOT);
   panelCanvas.FillRectangle(0,0,UIXPx(559),UIPx(39),UIInk(UI_HEADER));
   string pageTitle=uiObserver ? "入场研判" : uiPositions ? "持仓明细" : uiStatistics ? "交易统计" : uiIndicators ? "看盘设置" : "T哥点位计划";
   UIText(_Symbol+" · "+pageTitle,16,10,222,11,UI_TEXT);
   UIText("v1.71",242,13,40,8,UI_DIM);
   UIText(TimeToString(TimeGMT()+8*3600,TIME_SECONDS),286,12,100,10,UI_MUTED,true);
   UIButton(uiCollapsed ? "+" : "−",396,7,30,1);
   UIButton(tradeMode ? "交易模式" : "观察模式",434,7,110,29,tradeMode);
   PageTabs(49);
   // 禁用整块Canvas的原生长提示，避免遮挡统计导航和图形。
   ObjectSetString(0,VIEW+"CANVAS",OBJPROP_TOOLTIP,"\n");
   if(uiCollapsed)
   {
      string compact=uiObserver ? "研判页 · 只观察，不接管交易" : uiStatistics ? "统计页 · 点击 + 展开" :
                     uiIndicators ? "看盘页 · 指标显示设置" :
                     "监控 · "+IntegerToString(count)+"单 · "+reason;
      UIText(compact,16,94,526,9,UI_MUTED);
      panelCanvas.Update(); return;
   }
   if(uiObserver) { ObserverPage(); return; }
   if(uiStatistics) { StatsPanel(); return; }
   if(uiIndicators) { IndicatorPage(); return; }

   if(uiPositions)
   {
   // 持仓概览和明细只在持仓页绘制。
   UIRound(12,88,536,80,UI_CARD);
   UIText("浮动盈亏 / "+AccountInfoString(ACCOUNT_CURRENCY),28,99,222,9,UI_MUTED);
   UIText((pnl>0 ? "+" : "")+DoubleToString(pnl,2),28,122,224,24,
          pnl>0 ? UI_GAIN : pnl<0 ? UI_LOSS : UI_TEXT);
   panelCanvas.FillRectangle(UIXPx(266),UIPx(106),UIXPx(266),UIPx(150),UIInk(UI_BORDER));
   UIText("持仓",284,100,112,9,UI_MUTED);
   UIText(IntegerToString(count)+" 单",284,123,112,17,UI_TEXT);
   UIText(DoubleToString(volume,2)+" 手",284,148,112,8,UI_DIM);
   UIText("仓位保护",418,100,114,9,UI_MUTED);
   UIText("SL "+IntegerToString(protectedCount)+"/"+IntegerToString(count),418,125,114,12,UI_TEXT);
   UIText("TP "+IntegerToString(tpCount)+"/"+IntegerToString(count),418,148,114,8,UI_DIM);
   }

   if(!uiPositions)
   {
   // 价格独占一行或一列，分区按实际内容排布，不为空方向计划预留卡片。
   UICard(12,heroY,536,heroHeight,UI_ROW);
   bool hasManual=false;
   for(int i=0;i<ArraySize(aiPlans);i++) if(aiPlans[i].source=="MANUAL") { hasManual=true; break; }
   UIText(hasManual ? "点位计划 · 含手动修正" : "点位计划",28,heroY+12,280,12,UI_TEXT);
   UIButton("编辑点位",332,heroY+10,94,8);
   bool fallback=AIChannelReady() && StringFind(aiReason,"沿用已确认点位")>=0;
   color syncInk=AIChannelReady() && !fallback ? UI_ACCENT : UI_WARN;
   UIRound(434,heroY+10,98,26,UI_HEADER,5);
   UIText(AIChannelReady() ? (fallback ? "沿用已确认" : "同步正常") : "已暂停",
          444,heroY+15,78,9,syncInk,true);
   int y=heroY+44;
   if(directRows>0)
   {
       UIText("方向与支撑压力",28,y,260,9,UI_MUTED);
       UIText("按证据排序",420,y,112,8,UI_DIM,true);
      int card=0;
      for(int i=0;i<ArraySize(aiPlans);i++)
      {
          if(aiPlans[i].kind!="DIRECT" && aiPlans[i].kind!="ROLE") continue;
         int x=28+(card%3)*172,cy=y+24+(card/3)*100; card++;
         bool buy=aiPlans[i].sign>0,usable=PlanExecutable(i);
         color ink=buy ? UI_ACCENT : UI_SELL;
         UIRound(x,cy,160,92,!usable ? UI_CARD : buy ? C'20,47,44' : C'36,32,53',6);
          UIText((aiPlans[i].kind=="ROLE" ? (buy ? "支撑" : "压力") : (buy ? "做多" : "做空"))+" · "+IntegerToString(aiPlans[i].priority),x+10,cy+8,90,9,ink);
         UIText(TimeToString(aiPlans[i].confirmed+8*3600,TIME_MINUTES),x+104,cy+9,46,8,UI_DIM,true);
         UIText(DoubleToString(aiPlans[i].level,_Digits),x+10,cy+27,140,20,UI_TEXT);
         UIText(usable ? "触价 ±1.00 · "+PlanAgeCaption(i) : "仅供参考",x+10,cy+60,140,8,ink);
         UIText(aiPlans[i].status,x+10,cy+76,140,8,UI_MUTED);
      }
   }
   else
   {
      UIText("暂无明确方向计划",28,y+3,220,9,UI_MUTED);
      UIText("区间 / 地图仍可独立触发",260,y+4,272,8,UI_DIM,true);
   }
   y+=directHeight;
   if(rangeRows>0)
   {
      UIText("区间边界",28,y,260,9,UI_MUTED);
       UIText("大75 / 小70",420,y,112,8,UI_DIM,true);
      y+=26;
      for(int i=0;i<ArraySize(aiPlans);i++)
      {
          if(aiPlans[i].kind!="INNER" && aiPlans[i].kind!="OUTER") continue;
         bool buy=aiPlans[i].sign>0,usable=PlanExecutable(i);
         color ink=buy ? UI_ACCENT : UI_SELL;
         string label=(aiPlans[i].kind=="INNER" ? "小区间" : "大区间")+(buy ? "下沿" : "上沿");
         UIRound(28,y,504,40,UI_CARD,5);
         UIText(label,40,y+5,94,9,UI_MUTED);
         UIText(buy ? "做多 BUY" : "做空 SELL",40,y+23,94,8,ink);
         UIText(DoubleToString(aiPlans[i].level,_Digits),140,y+8,130,16,usable ? UI_TEXT : UI_DIM,true);
         UIText(usable ? PlanAgeCaption(i) : "仅供参考",288,y+5,232,8,ink,true);
         UIText(aiPlans[i].status,288,y+23,232,8,UI_MUTED,true);
         y+=48;
      }
      y+=8;
   }
    UIText("全部参考点位",28,y,220,9,UI_MUTED);
    UIText("中性40 · "+IntegerToString(ArraySize(levels))+" 个价格",280,y,252,8,UI_DIM,true);
   y+=28;
   for(int row=0;row<pointRows;row++)
   {
      for(int col=0;col<5;col++)
      {
         int i=row*5+col; if(i>=ArraySize(levels)) break;
         int x=28+col*103;
         UIRound(x,y,92,36,UI_CARD,5);
          UIText(DoubleToString(levels[i],_Digits),x+8,y+3,76,13,feedActive ? UI_TEXT : UI_DIM,true);
          UIText(PointRoleCaption(levels[i]),x+8,y+23,76,8,UI_MUTED,true);
      }
      if(ArraySize(levels)==0)
      {
         UIRound(28,y,504,36,UI_CARD,5);
         UIText("暂无地图点位，等待同步",40,y+10,480,9,UI_DIM);
      }
      y+=44;
   }
   UIText(MapLifeCaption(),28,y+2,504,8,feedActive ? UI_MUTED : UI_WARN);
   y+=26;
   panelCanvas.FillRectangle(UIXPx(28),UIPx(y),UIXPx(532),UIPx(y),UIInk(UI_BORDER));
   UIText(AIPlanCaption(),28,y+10,504,8,AIChannelReady() ? UI_MUTED : UI_WARN);
   UIText("当前执行",16,decisionY+3,106,9,UI_DIM);
   UIText("实时触价 · 0.02手",132,decisionY+3,198,9,UI_MUTED);
   UIText("离开4点5秒可重入",336,decisionY+3,204,9,UI_MUTED,true);
   UIText(reason,16,decisionY+25,526,12,UI_TEXT);
   string detail=entryView.ready ? StringFormat("参考 %.2f · 距点位 %.2f",entryView.level,entryView.distance) : "等待新鲜报价；参考保留，有效性由EA检查";
   UIText(detail,16,decisionY+52,510,9,UI_MUTED);
   }

   if(uiPositions)
   {
   UIText("持仓明细",16,positionY,220,10,UI_TEXT);
   UIText("仅本EA · 共"+IntegerToString(count)+"笔 · "+IntegerToString(uiPositionPage+1)+"/"+IntegerToString(positionPages)+"页",160,positionY+5,188,8.5,UI_DIM,true);
   UIButton("上一页",360,positionY-2,86,6);
   UIButton("下一页",454,positionY-2,90,7);
   for(int row=0;row<MathMax(visible,1);row++)
   {
      int y=positionY+38+row*rowHeight;
      UICard(12,y,536,rowHeight-6,UI_ROW);
      if(count==0)
      {
         panelCanvas.FillRectangle(UIXPx(13),UIPx(y+12),UIXPx(15),UIPx(y+45),UIInk(UI_ACCENT));
         UIText("当前没有本EA持仓",28,y+12,480,11,UI_TEXT);
         UIText("等待符合条件的机会 · 成交后显示分批与保护进度",28,y+35,480,9.5,UI_MUTED);
         break;
      }
      int ticketIndex=firstPosition+row;
      if(!PositionSelectByTicket(tickets[ticketIndex])) continue;
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      color sideInk=buy ? UI_ACCENT : UI_SELL;
      double profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      UIText(buy ? "BUY" : "SELL",24,y+8,54,11,sideInk);
      UIText("#"+IntegerToString((long)tickets[ticketIndex])+" · "+DoubleToString(PositionGetDouble(POSITION_VOLUME),2)+"手",
             84,y+10,280,9.5,UI_MUTED);
      UIText((profit>0 ? "+" : "")+DoubleToString(profit,2),382,y+7,150,13,
             profit>0 ? UI_GAIN : profit<0 ? UI_LOSS : UI_MUTED,true);
      string priceTexts[3]={"入场 "+DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN),_Digits),
                            "SL "+(PositionGetDouble(POSITION_SL)>0 ? DoubleToString(PositionGetDouble(POSITION_SL),_Digits) : "未设置"),
                            "TP "+(PositionGetDouble(POSITION_TP)>0 ? DoubleToString(PositionGetDouble(POSITION_TP),_Digits) : "未设置")};
      for(int j=0;j<3;j++) UIText(priceTexts[j],24+j*172,y+34,158,9.5,UI_TEXT);
      string progress=PositionProgress((ulong)PositionGetInteger(POSITION_IDENTIFIER),buy ? 1 : -1,
                         PositionGetDouble(POSITION_PRICE_OPEN),PositionGetDouble(POSITION_VOLUME),PositionGetDouble(POSITION_SL));
      UIText(progress,24,y+58,508,8.5,UI_MUTED);
   }
   }

   string gate=ExecutionBlock();
   if(gate=="") gate=AIChannelReady() ? "按优先级等待触价" : aiReason;
   if(!LegacyLimitsClear()) gate="旧限价单迁移对账中";
   UIText("实盘入场："+(EffectiveEntryMethod()==1 ? "原行情保护" : "原触价检查")+
          (入场策略==TGE_ENTRY_COMPAT ? "（兼容）" : "（独立）")+" · 持单："+
          (启用积极持单 ? "结构退出" : 持单策略==TGE_HOLD_FIXED ? "TP5/SL10" : "旧版分批"),16,height-43,526,8,UI_DIM);
   UIText("执行 · "+gate,16,height-25,526,9,pending.kind!=0 ? UI_WARN : UI_MUTED);
   panelCanvas.Update();
}
int OnInit()
{
   if(入场策略!=TGE_ENTRY_COMPAT && 入场策略!=TGE_ENTRY_TOUCH && 入场策略!=TGE_ENTRY_ADAPTIVE)
      return INIT_PARAMETERS_INCORRECT;
   if(!MathIsValidNumber(模拟每手往返费用) || 模拟每手往返费用<0 ||
      !MathIsValidNumber(模拟单边滑点价格) || 模拟单边滑点价格<0) return INIT_PARAMETERS_INCORRECT;
   if(持单策略!=TGE_HOLD_LEGACY && 持单策略!=TGE_HOLD_STRUCTURE && 持单策略!=TGE_HOLD_FIXED)
      return INIT_PARAMETERS_INCORRECT;
   启用积极持单=持单策略==TGE_HOLD_STRUCTURE;
   if(!AdaptiveInputsValid()) return INIT_PARAMETERS_INCORRECT;
   if(观察回看分钟<20 || 观察回看分钟>240 || 观察边界最少反应次数<1 || 观察边界最少反应次数>10 ||
      !MathIsValidNumber(观察收回ATR倍数) || 观察收回ATR倍数<=0 || 观察收回ATR倍数>2 ||
      !MathIsValidNumber(观察最小区间ATR倍数) || 观察最小区间ATR倍数<1 || 观察最小区间ATR倍数>10)
      return INIT_PARAMETERS_INCORRECT;
   if(每次开仓手数<=0 || 最大同时持仓<1 || 最大同时持仓>10 ||
      冲击短窗毫秒<1000 || 冲击短窗毫秒>10000 || !MathIsValidNumber(逆向冲击速度) || 逆向冲击速度<=0 ||
       !MathIsValidNumber(冲击单向比例) || 冲击单向比例<=0.5 || 冲击单向比例>1 ||
       !MathIsValidNumber(恢复回拉价格) || 恢复回拉价格<=0 ||
       !MathIsValidNumber(挂单最大离价) || 挂单最大离价<=0 ||
       最大点差价格<=0 || !MathIsValidNumber(最大点差价格) ||
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
   // 两种模式共用持仓状态和独占锁，切换不能绕过实例互斥或pending对账。
   FolderCreate("FeishuMT5SignalMonitor",FILE_COMMON);
   lockHandle=FileOpen("FeishuMT5SignalMonitor\\"+prefix+"lock",FILE_READ|FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(lockHandle==INVALID_HANDLE) { Print("同账户/品种/Magic已有实例"); return INIT_FAILED; }
   tradeMode=启用真实交易 && (!GlobalVariableCheck(prefix+"tradeMode") || Load("tradeMode")>0);
   execution.SetExpertMagicNumber(EA魔法号); execution.SetDeviationInPoints(30);
   execution.SetTypeFillingBySymbol(_Symbol); execution.SetAsyncMode(false);
   maHandle=iMA(_Symbol,PERIOD_M5,5,0,MODE_SMA,PRICE_CLOSE); atrHandle=iATR(_Symbol,PERIOD_M5,14);
   trendFastHandle=iMA(_Symbol,PERIOD_M5,20,0,MODE_EMA,PRICE_CLOSE);
   trendSlowHandle=iMA(_Symbol,PERIOD_M5,50,0,MODE_EMA,PRICE_CLOSE);
   if(maHandle==INVALID_HANDLE || atrHandle==INVALID_HANDLE ||
      trendFastHandle==INVALID_HANDLE || trendSlowHandle==INVALID_HANDLE) return INIT_FAILED;
   RestorePending(); RestoreSharedVisits(); RestoreTeacherLimits();
   InitView(); InitTgeMobileMarkers();
   fastStarted=TimeGMT(); readyFrom=TimeCurrent(); ReadHealth(); ReadAISetups();
   InitAdaptive(); RefreshAdaptiveMarket(); RefreshAdaptiveHistory(); RefreshPointStructure(); RefreshAdaptiveCalendar();
   LifePoll();
   MqlTick q; bool fresh=FreshQuote(q); RefreshPlanValidity(q,fresh,true);
   InitObserver(); RefreshObserver(); InitPaper();
   EventSetTimer(1); Panel(); SyncHistoryLayer();
   return INIT_SUCCEEDED;
}
void OnTimer()
{
   if(busy) return; busy=true;
   ReadHealth(); ReadAISetups();
   RefreshAdaptiveMarket(); RefreshAdaptiveHistory(); RefreshPointStructure();
   MqlTick q; bool fresh=FreshQuote(q); RefreshPlanValidity(q,fresh,true);
   if(fresh) UpdateAdaptiveShock(q);
   if(fresh) for(int i=0;i<ArraySize(aiPlans);i++) TeacherEntryAllowed(i,q);
   Reconcile();
   SyncTeacherLimits(); Manage();
   LifePoll(); ReviewNavigate(); RefreshObserver(); PaperPoll();
   checkingMinute=iTime(_Symbol,PERIOD_M1,1);
   DecisionLog("EVALUATE",reason);
   SyncTgeMobileMarkers(); SyncHistoryLayer(); Panel(); busy=false;
   RefreshAdaptiveCalendar();
}
void OnTick()
{
   if(busy) return; busy=true;
   MqlTick q;
   if(FreshQuote(q)) { RememberFastTick(q); UpdateTeacherVisits(q); UpdateAdaptiveShock(q); }
   Candidate candidate;
   if(LegacyLimitsClear() && pending.kind==0 && AIMarketSignal(candidate)) Open(candidate);
   busy=false;
}
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   uiHistoryNextScan=0;
   // 统计只标脏，不在交易事件里扫描历史或改变pending。
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD || trans.type==TRADE_TRANSACTION_DEAL_UPDATE ||
      trans.type==TRADE_TRANSACTION_DEAL_DELETE) statsDirty=true;
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD || trans.type==TRADE_TRANSACTION_DEAL_UPDATE ||
      trans.type==TRADE_TRANSACTION_DEAL_DELETE) adaptiveHistoryDirty=true;
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
         statsPressedId=uiPressedAction>=1000 && uiPressedAction-1000<ArraySize(statsTrades) ?
                        statsTrades[uiPressedAction-1000].id : 0;
         if(uiPressedAction==0 && mx>=uiX && mx<uiX+UIXPx(275) && my>=uiY && my<uiY+UIPx(40))
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
            ChartSetInteger(0,CHART_MOUSE_SCROLL,uiOldScroll); uiHistoryNextScan=0; SyncHistoryLayer(); SaveView();
         }
         else if(leftDown)
         {
            uiX=mx-uiDragDX; uiY=my-uiDragDY; MovePanel(); SyncHistoryLayer(); ChartRedraw(0);
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
    else if(id==CHARTEVENT_CHART_CHANGE) { uiHistoryNextScan=0; DrawLevels(); Panel(); SyncHistoryLayer(); }
}
void OnDeinit(const int why)
{
   EventKillTimer();
   StopPaper();
   LifePoll(); LifeFlush(); ReviewReturnLive(false);
   RestoreHistoryLayer(); StopTgeMobileMarkers();
   if(uiInitialized)
   {
      if(uiDragging) ChartSetInteger(0,CHART_MOUSE_SCROLL,uiOldScroll);
      SaveView(); ChartSetInteger(0,CHART_EVENT_MOUSE_MOVE,uiOldMouseMove);
   }
   CloseViewIndicators();
   if(maHandle!=INVALID_HANDLE) IndicatorRelease(maHandle);
   if(atrHandle!=INVALID_HANDLE) IndicatorRelease(atrHandle);
   if(trendFastHandle!=INVALID_HANDLE) IndicatorRelease(trendFastHandle);
   if(trendSlowHandle!=INVALID_HANDLE) IndicatorRelease(trendSlowHandle);
   if(lockHandle!=INVALID_HANDLE) FileClose(lockHandle);
   if(panelReady) panelCanvas.Destroy();
   ObjectsDeleteAll(0,VIEW);
}
