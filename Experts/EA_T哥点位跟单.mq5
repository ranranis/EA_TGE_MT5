#property strict
#property version "1.37"
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
input double 最大点差价格=0.50;         // 黄金报价价格差，不是_Point倍数
input ulong  EA魔法号=560056;
input bool   读取AI即时策略=true;     // 读取本地DeepSeek语义桥；未就绪时等待，不猜方向
input group "学员跟随 · 最新点位价格区间"
input bool   启用起飞跟随=true;
input double 学员最大追价价格差=1.00; // 做多最多高1；做空最多低1，含边界
input double 学员最大回落价格差=5.00; // 做多最多低5；做空最多高5，含边界
input bool   启用其他学生跟随=true; // 按监控端真实账号名单分别启用
input group "T哥近价 · 实时冲击检查"
input int    冲击短窗毫秒=3000;
input double 逆向冲击速度=0.60;       // 黄金报价价格差/秒，只检查对当前方向不利的净速度
input double 冲击单向比例=0.85;
input double 恢复回拉价格=0.35;
input group "T哥点位节奏与退出"
input bool   允许震荡点位反应=true;
input bool   启用点位试仓=true;           // M1初步收回但M5/趋势未确认时，近价先试0.01手
input bool   允许地图趋势过滤=true;       // 趋势明确时只做顺趋势方向；震荡时保留双向反应
input bool   允许同机会重入=true;         // 离开同一机会后，允许在仍有其他仓位时再次进入
input double 保险价格距离=10.0;
input double 首批止盈价格距离=5.0;
input double 尾仓目标价格距离=10.0;

input group "手机点位 TP 标记"
input bool   启用手机标记挂单=false;      // 默认关闭；启用后会向服务器发送真实0.01手Buy Limit
input double 手机标记挂单固定价格=100.0; // 仅黄金；接近挂单价20点时请求撤销

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
// 图表显示和手机TP开关独立于短线候选、仓位及pending状态。
int uiX=8,uiY=24;
bool uiCollapsed=false,uiPointLines=true,uiMobileMarkers=true;

CTrade execution;
double levels[];
string identity="",sourceKind="",sourceSender="",feedStatus="等待首次点位",reason="等待收线";
datetime sourceTime=0,feedTime=0,readyFrom=0,lastMinute=0;
bool feedActive=false,busy=false,stateOK=true;
int maHandle=INVALID_HANDLE,atrHandle=INVALID_HANDLE,lockHandle=INVALID_HANDLE,trend=0;
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
   bool fast;
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
void SavePending()
{
   // 中断发生在字段保存途中时留下-1，重启必须人工核对而非猜测没有请求。
   Store("kind",-1); GlobalVariablesFlush();
   Store("order",(double)pending.order); Store("position",(double)pending.position);
   Store("at",(double)pending.at); Store("bar",(double)pending.bar);
   Store("volume",pending.volume); Store("sl",pending.sl); Store("tp",pending.tp);
   Store("level",pending.level); Store("direction",pending.direction);
   Store("fast",pending.fast ? 1 : 0); Store("originHash",(double)pending.originHash);
   Store("exitSL",pending.exitSL); Store("exitFirst",pending.exitFirst); Store("exitBE",pending.exitBE); Store("exitTP",pending.exitTP);
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
   pending.exitSL=Load("exitSL"); pending.exitFirst=Load("exitFirst"); pending.exitBE=Load("exitBE"); pending.exitTP=Load("exitTP");
   pending.fast=Load("fast")==1; pending.originHash=(uint)Load("originHash");
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
// 解释既有执行门槛；不会自动改变权限或解除pending。
string ExecutionBlock()
{
   if(!启用真实交易) return "观察模式：交易输入已关闭";
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
void DecisionLog(const string event,const string detail,const uint retcode=0,const ulong deal=0)
{
   // 日文件只在评估结果变化、请求返回和真实对账时追加；不包含聊天正文。
   string key=event+"|"+identity+"|"+IntegerToString((long)checkingMinute)+"|"+detail;
   if(event=="EVALUATE" && key==lastDecisionKey) return;
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
   bool sameLevels=n==ArraySize(levels);
   for(int i=0;i<n && sameLevels;i++) if(incoming[i]!=levels[i]) sameLevels=false;
   if(!sameLevels || active!=feedActive)
   {
      readyFrom=TimeCurrent(); // 新版本/恢复后必须等随后完整形成的M1，不能追认历史K线。
      ZeroMemory(entryView); reason="点位状态变更，等待随后完整M1";
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
bool Target(const double entry,const int sign,double &tp,const bool mapOnly=false,const double reference=0)
{
   double distance=尾仓目标价格距离;
   if(!mapOnly && 读取AI即时策略 && aiReady && aiMode=="SETUP")
   {
      for(int i=0;i<ArraySize(aiPlans);i++)
      {
         if(reference>0 && MathAbs(aiPlans[i].level-reference)<=TickSize()) continue;
         double gap=sign*(aiPlans[i].level-entry);
         if(gap>TickSize()) distance=MathMin(distance,gap-MathMax(0.20,TickSize()*2));
      }
      if(distance<=TickSize()*2) return false;
      tp=Align(entry+sign*distance,-sign); return true;
   }
   for(int i=0;i<ArraySize(levels);i++)
   {
      double gap=sign*(levels[i]-entry);
      if(gap>TickSize()) distance=MathMin(distance,gap-MathMax(0.20,TickSize()*2));
   }
   if(distance<=TickSize()*2) return false;
   tp=Align(entry+sign*distance,-sign); // 不把目标舍入到阻力之外
   return true;
}
string VisitKey(const double level) { return "visit"+DoubleToString(level,_Digits); }
// 地图是中性关键位：角色由已收M5受阻/止跌与M1反应确定，不冒充老师喊单。
bool MapReaction(const MqlRates &bar,const MqlRates &previous,const MqlRates &m5,
                 const MqlTick &quote,Candidate &out,const bool probeOnly=false)
{
   reason="等待地图支撑/压力的收线反应";
   if(!允许震荡点位反应) { reason="地图反应开关已关闭"; return false; }
   if(bar.time<readyFrom) { reason="等待更新后的完整M1"; return false; }
   // 明确市价指令不扩展为另一套反向机会；无方向/取消仍由Signal入口拦截。
   if(读取AI即时策略 && aiMode=="SETUP")
      for(int i=0;i<ArraySize(aiPlans);i++)
         if(aiPlans[i].market) { reason="市价指令不扩展地图反应"; return false; }
   double tolerance=MathMax(atr*0.20,TickSize()*2),escape=MathMax(atr*0.05,TickSize());
   double nearest=DBL_MAX,probeDistance=DBL_MAX;
   Candidate trial; ZeroMemory(trial);
   for(int i=0;i<ArraySize(levels);i++)
   {
      double level=levels[i]; bool explicitLevel=false;
      if(读取AI即时策略 && aiMode=="SETUP")
         for(int j=0;j<ArraySize(aiPlans);j++)
            if(MathAbs(aiPlans[j].level-level)<=TickSize()) explicitLevel=true;
      if(explicitLevel) continue; // 该价位保留老师指定方向，不偷偷反做。
      datetime consumed=(datetime)Load(VisitKey(level));
      if(允许同机会重入 && consumed>0 && bar.time>consumed && MathAbs(bar.close-level)>MathMax(atr,2.0))
         Store(VisitKey(level),0);
      for(int sign=-1;sign<=1;sign+=2)
      {
         double entry=sign>0 ? quote.ask : quote.bid,gap=sign*(entry-level);
         if(gap<0) continue;
         // 先有M5触及关键位并收回，再有最新M1止跌/受阻；不只看现价触线。
         bool rejection=sign>0 ? m5.low>=level-tolerance && m5.low<=level+tolerance &&
                                  m5.close>level+escape :
                                  m5.high<=level+tolerance && m5.high>=level-tolerance &&
                                  m5.close<level-escape;
         bool reaction=Reaction(bar,previous,level,sign,tolerance,escape);
         double tp;
         string blocked=Load(VisitKey(level))>0 ? "本点位机会已消费，等待离开后再回踩" :
                        (允许地图趋势过滤 && trend!=0 && sign!=trend) ? "M5趋势相反，地图反应等待顺势" :
                        gap>MathMin(atr*0.75,首批止盈价格距离*0.8) ? "距地图点位过远，不追单" :
                        !rejection ? "等待M5在地图点位收回确认" :
                        !reaction ? "等待M1在地图点位止跌/受阻" :
                        !Target(entry,sign,tp,true) ? "下一地图点位前无有效止盈空间" : "";
         if(gap<nearest || blocked=="")
         {
            nearest=gap; reason=blocked;
            entryView.ready=true; entryView.level=level; entryView.direction=sign;
            entryView.distance=gap; entryView.reaction=reaction; entryView.space=0;
            entryView.method=sign>0 ? "地图支撑止跌" : "地图压力受阻";
            for(int k=0;k<ArraySize(levels);k++)
            {
               double space=sign*(levels[k]-entry);
               if(space>TickSize() && (entryView.space==0 || space<entryView.space)) entryView.space=space;
            }
         }
         if(blocked!="" || probeOnly)
         {
            // 只降低形态确认门槛：已收M1有回收动作、现价在点位2.00以内。
            // 不要求上一根M5同时满足；直线下跌/上涨的反向K线不试。
            double edge=sign>0 ? MathMin(bar.low,previous.low) : MathMax(bar.high,previous.high);
            bool initial=sign*(bar.close-bar.open)>0 && sign*(bar.close-level)>0 &&
                         MathAbs(edge-level)<=2.00;
            if(启用点位试仓 && gap<=2.00 && initial && Load(VisitKey(level))==0 &&
               !SameOpportunity(sign,level) && Target(entry,sign,tp,true) && gap<probeDistance)
            {
               probeDistance=gap; trial.valid=true; trial.probe=true;
               trial.direction=sign; trial.level=level; trial.bar=bar.time;
               trial.method=(sign>0 ? "地图支撑" : "地图压力")+"试仓0.01（M1初步收回）";
            }
            continue;
         }
         out.probe=false; out.valid=true; out.ai=false; out.direction=sign; out.level=level; out.bar=bar.time;
         out.method=entryView.method+"（EA收线确认）"; reason=out.method; return true;
      }
   }
   if(trial.valid) { out=trial; reason=trial.method; return true; }
   return false;
}
bool Signal(Candidate &out)
{
   out.valid=false; out.ai=false; out.follow=false; out.probe=false; signalRetry=false; ZeroMemory(entryView); entryView.bar=checkingMinute;
   // 同一收线的数据等待只发生在原有90秒窗口内，不补做已经过时的信号。
   if(checkingMinute>0 && TimeTradeServer()-checkingMinute>90) { reason="本根M1评估窗口已结束"; return false; }
   MqlTick quote;
   if(!feedActive) { reason="点位地图未启用，等待有效来源"; return false; }
   if(读取AI即时策略 && !AIChannelReady())
   { reason="AI等待："+aiReason; return false; }
   if(!FreshQuote(quote)) { signalRetry=true; reason="报价过期/断线，等待新鲜报价"; return false; }
   if(quote.ask-quote.bid>最大点差价格) { reason="点差过大"; return false; }
   MqlRates m1[],m5[]; double ma[],vol[];
   ArraySetAsSeries(m1,true); ArraySetAsSeries(m5,true); ArraySetAsSeries(ma,true);
   if(CopyRates(_Symbol,PERIOD_M1,1,2,m1)!=2 || CopyRates(_Symbol,PERIOD_M5,1,7,m5)!=7 ||
      CopyBuffer(maHandle,0,1,7,ma)!=7 || CopyBuffer(atrHandle,0,1,1,vol)!=1)
   { signalRetry=true; reason="等待M1/M5数据，窗口内重试"; return false; }
   if(checkingMinute>0 && m1[0].time!=checkingMinute) { signalRetry=true; reason="M1序列尚未对齐"; return false; }
   if((m1[0].time<readyFrom && !(读取AI即时策略 && aiMode=="SETUP" && m1[0].time+60>readyFrom)) ||
      TimeCurrent()-m1[0].time>90)
   { reason="等待启动/更新后的完整收线"; return false; }
   // K线time是开盘时刻；上一根M5在整个当前M5周期内都是有效的已收盘数据。
   // 索引0只取时间校验连续性，价格、均线和ATR判断仍使用索引1及以前。
   datetime currentM5=iTime(_Symbol,PERIOD_M5,0);
   if(m1[0].time-m1[1].time!=60 || currentM5<=0 || m5[0].time+300!=currentM5)
   { signalRetry=true; reason="收线序列尚未完整，窗口内重试"; return false; }
   for(int i=0;i<6;i++) if(m5[i].time-m5[i+1].time!=300) { signalRetry=true; reason="M5数据缺口，窗口内重试"; return false; }
   atr=vol[0]; if(!MathIsValidNumber(atr) || atr<=TickSize()) { signalRetry=true; reason="ATR数据未就绪"; return false; }
   for(int i=0;i<7;i++) if(!MathIsValidNumber(ma[i]) || ma[i]==EMPTY_VALUE || ma[i]<=0)
   { signalRetry=true; reason="MA5数据未就绪"; return false; }
   trend=Trend(m5[0],m5[1],ma[0],ma[1]);
   int maCrossings=0;
   for(int i=0;i<6;i++)
      if((m5[i].close-ma[i])*(m5[i+1].close-ma[i+1])<0) maCrossings++;
   if(maCrossings>=3) trend=0;
   double tolerance=MathMax(0.20*atr,2*TickSize()),escape=MathMax(0.05*atr,TickSize());
   double nearest=DBL_MAX,probe=DBL_MAX;
   entryView.bar=m1[0].time; entryView.ma=ma[0]; entryView.m1close=m1[0].close; entryView.crossings=maCrossings;
   bool continuation=读取AI即时策略 && aiMode=="SETUP";
   int continuationSign=0;
   double continuationAnchor=0;
   string directReason="";
   // 优先级：老师明确点位 -> 独立地图支撑/压力反应 -> 同向突破延续。
   if(continuation)
   {
      if(TeacherOwnsZone(quote)) { reason="老师近价区域优先："+reason; return false; }
      directReason="老师明确计划使用独立实时通道";
   }
   if(continuation && MapReaction(m1[0],m1[1],m5[0],quote,out)) return true;
   string reactionReason=reason;
   if(continuation)
   {
      for(int i=0;i<ArraySize(aiPlans);i++)
      {
         if(aiPlans[i].market)
         { reason="延续：市价指令不扩展为地图机会；回踩："+directReason; return false; }
         int sign=aiPlans[i].sign;
         if(continuationSign!=0 && continuationSign!=sign)
         { reason="地图反应："+reactionReason+"；延续等待明确方向；回踩："+directReason; return false; }
         if(continuationSign==0 || sign*(aiPlans[i].level-continuationAnchor)>0)
            continuationAnchor=aiPlans[i].level;
         continuationSign=sign;
      }
      if(continuationSign==0 || trend!=continuationSign)
      { reason="地图反应："+reactionReason+"；延续等待同向M5；回踩："+directReason; return false; }
      // 延续只允许启用/更新后完整形成的M1，不沿用即时计划的半根收线例外。
      if(m1[0].time<readyFrom)
      { reason="延续：等待更新后的完整M1；回踩："+directReason; return false; }
   }
   reason=continuation ? "等待方向前方地图点位的M5突破回测" : "等待点位附近的完整M1止跌/受阻";
   for(int i=0;i<ArraySize(levels);i++)
   {
      double level=levels[i];
      // 当前明确回踩价仍由AI分支处理；只拓展其方向前方的其他地图点位。
      if(continuation && continuationSign*(level-continuationAnchor)<=TickSize()) continue;
      datetime consumed=(datetime)Load(VisitKey(level));
      if(允许同机会重入 && consumed>0 && m1[0].time>consumed && MathAbs(m1[0].close-level)>MathMax(atr,2.0))
         Store(VisitKey(level),0); // 离开后才可重新回踩；消息重发不会重置
      bool consumedVisit=Load(VisitKey(level))>0;
      int flips=0;
      for(int j=0;j<6;j++) if((m5[j].close-level)*(m5[j+1].close-level)<0) flips++;
      for(int sign=-1;sign<=1;sign+=2)
      {
         if(continuation && sign!=continuationSign) continue;
         double entry=sign>0 ? quote.ask : quote.bid,gap=sign*(entry-level);
         if(gap<0) continue;
         bool m1Reaction=Reaction(m1[0],m1[1],level,sign,tolerance,escape);
         bool retest=BreakRetest(m5[0],m5[1],m5[2],level,sign,tolerance,escape);
         bool maTouch=sign>0 ? MathMin(m1[0].low,m1[1].low)<=ma[0]+tolerance :
                              MathMax(m1[0].high,m1[1].high)>=ma[0]-tolerance;
         bool pullback=trend==sign && maTouch && MathAbs(m1[0].close-ma[0])<=0.75*atr;
         bool reaction=允许震荡点位反应 && trend==0 && sign*(m5[0].close-level)>escape &&
                       m5[0].high-m5[0].low<=2*atr;
         double tp;
         bool targetOK=Target(entry,sign,tp,continuation);
         string method=continuation ? "老师方向·地图突破回测" : retest ? "M5突破回测" : pullback ? "M5 MA5顺势回踩" : reaction ? "震荡点位反应" : "等待入场结构";
         string blocked=consumedVisit ? "本点位机会已消费，等待离开后再回踩" :
                        gap>MathMin(0.75*atr,首批止盈价格距离*0.8) ? "距点位过远，避免追价" :
                        !m1Reaction ? "M1尚未止跌/受阻并收回点位" :
                        trend!=0 && sign!=trend ? "M1反应与M5趋势相反" :
                        flips>=3 && !retest ? "M5反复穿越点位，等待明确突破回测" :
                        continuation && !retest ? "延续需M5完成突破回测" :
                        !retest && !pullback && !reaction ? "M5入场结构尚未成立" :
                        !targetOK ? "下一点位之前不足首批收米空间" : "";
         // 同一遍计算生成解释；优先展示实际候选，否则展示最近点位的阻塞项。
         if((!out.valid && gap<probe) || (blocked=="" && gap<nearest))
         {
            probe=gap; entryView.ready=true; entryView.level=level; entryView.direction=sign;
            entryView.distance=gap; entryView.reaction=m1Reaction; entryView.method=method; entryView.space=0;
            for(int k=0;k<ArraySize(levels);k++)
            {
               double space=sign*(levels[k]-entry);
               if(space>TickSize() && (entryView.space==0 || space<entryView.space)) entryView.space=space;
            }
            reason=blocked;
         }
         if(blocked!="") continue;
         if(gap>=nearest) continue;
         nearest=gap; out.valid=true; out.direction=sign; out.level=level; out.bar=m1[0].time;
         out.method=method+(continuation ? "["+aiSource+"]" : "");
      }
   }
   if(!continuation && !out.valid && 启用点位试仓) MapReaction(m1[0],m1[1],m5[0],quote,out,true);
   if(continuation && !out.valid) reason="地图反应："+reactionReason+"；延续："+reason+"；回踩："+directReason;
   if(out.valid) reason=out.method+(out.direction>0 ? " 多" : " 空")+" @"+DoubleToString(out.level,_Digits);
   return out.valid;
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
   DecisionLog("REQUEST_RESULT",execution.ResultComment(),code,execution.ResultDeal());
   if(ExplicitReject(code))
   {
      if(pending.kind==1 && pending.fast)
      {
         string key=AIKeyFromHash(pending.originHash,pending.level,pending.direction);
         Store(key,0); Store(key+"r",(double)(TimeGMT()+5)); GlobalVariablesFlush();
      }
      ClearPending(); reason="请求被明确拒绝；老师5秒后可复查，学生本条不再尝试";
   }
   else { if(pending.kind==1) MergeOpportunity(pending.direction,pending.level); SavePending(); reason="请求已发送，等待真实成交/持仓确认"; } // 未知结果不补发
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
   if(pending.exitSL==0 && pending.exitFirst==0 && pending.exitBE==0 && pending.exitTP==0) return true;
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
      if(!Store(key+"ready",0) || !Store(key+"sl",pending.exitSL) ||
         !Store(key+"first",pending.exitFirst) || !Store(key+"be",pending.exitBE) || !Store(key+"tp",pending.exitTP) ||
         !Store(key+"ready",1)) return false;
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
   if(pending.order>0 && FinalOrderConfirmed(pending.order))
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
            Store(key,0); Store(key+"r",(double)(TimeGMT()+5));
            Store(SharedVisitKey(pending.level,pending.direction),0); GlobalVariablesFlush();
         }
      }
      DecisionLog("ORDER_RECONCILED","终态订单与实际Deal量已对账（不代表全量成交）"); ClearPending(); reason="请求已对账，等待下一机会";
   }
   if(pending.kind!=0 && TimeCurrent()-pending.at>30)
      reason="请求尚未完成服务器对账，暂停新请求（查看日志）";
}
void Open(const Candidate &signal)
{
   string blocked=ExecutionBlock();
   if(!CanExecute() || blocked!="") { reason=blocked=="" ? "执行条件未就绪" : blocked; return; }
   if(!signal.ai && !signal.follow && (datetime)Load("attemptBar")>=signal.bar) { reason="本根M1已发送过请求"; return; }
   string visit=signal.follow ? signal.followKey : signal.ai ? signal.aiKey : VisitKey(signal.level);
   if(Load(visit)>0) { reason="本点位机会已消费"; return; }
   MqlTick q;
   if(!FreshQuote(q)) { signalRetry=true; reason="发送前报价失效，窗口内重试"; return; }
   if(signal.follow && (!followReady || signal.followKey!=FollowVisitKey() ||
      TimeGMT()-followGenerated>10 || !FollowPriceAllowed(q) || TeacherOwnsZone(q) || SameOpportunity(signal.direction,signal.level)))
   { reason="学生来源已变更/离区，或老师优先/同机会合并"; return; }
   if(signal.ai)
   {
      bool allowed=false;
      for(int i=0;i<ArraySize(aiPlans);i++)
         if(aiPlans[i].sign==signal.direction && aiPlans[i].level==signal.level && AIVisitKey(signal.level,signal.direction)==signal.aiKey)
            allowed=TeacherEntryAllowed(i,q);
      if(!allowed) { reason="发送前老师来源/区域/冲击检查未通过"; return; }
   }
   else if(!signal.follow && TeacherOwnsZone(q)) { reason="发送前老师明确区域优先"; return; }
   if(signal.probe && (MathAbs((signal.direction>0 ? q.ask : q.bid)-signal.level)>2.00 || SameOpportunity(signal.direction,signal.level)))
   { reason="试仓发送前已离开点位或同机会已占用"; return; }
   if(q.ask-q.bid>最大点差价格) { reason="发送前点差超过上限"; return; }
   double volume=signal.probe ? 0.01 : 每次开仓手数;
   if(!ExactLot(volume)) { reason="开仓手数不符合券商规格"; return; }
   int sign=signal.direction;
   double entry=sign>0 ? q.ask : q.bid,sl=Align(entry-sign*保险价格距离,sign),tp;
   // 成员跟随沿用现有10点尾仓/5点分批退出，不把老师地图障碍当成他的入场价。
   bool targetOK=true;
   if(signal.follow) tp=Align(entry+sign*尾仓目标价格距离,-sign);
   else if(signal.ai && signal.exitTP>0) tp=Align(signal.exitTP,-sign);
   else targetOK=Target(entry,sign,tp,!signal.ai,signal.ai ? signal.level : 0);
   if(signal.ai && signal.exitSL>0) sl=Align(signal.exitSL,sign);
   if(!targetOK || sign*(entry-sl)<=0 || sign*(tp-entry)<=TickSize() ||
      (signal.ai && signal.exitFirst>0 && (sign*(signal.exitFirst-entry)<=0 || sign*(tp-signal.exitFirst)<=TickSize())) ||
      (signal.ai && signal.exitBE>0 && (sign*(signal.exitBE-entry)<=0 || sign*(tp-signal.exitBE)<0)) ||
      !Stops(sign,sl,tp,q)) { reason="退出价已错过/顺序无效或不符合券商规格"; return; }
   ENUM_ORDER_TYPE type=sign>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double margin=0;
   if(!OrderCalcMargin(type,_Symbol,volume,entry,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   { reason="可用保证金不足"; return; }
   // 保证金/规格计算后再次取得实时报价；变化时交回下一tick重新生成候选，不沿用旧价格。
   MqlTick finalQuote;
   if(!FreshQuote(finalQuote) || finalQuote.ask-finalQuote.bid>最大点差价格)
   { reason="提交前报价过期或点差超限"; return; }
   if(signal.follow && (!FollowPriceAllowed(finalQuote) || TeacherOwnsZone(finalQuote)))
   { reason="提交前学生参考离区或老师区域优先"; return; }
   if(signal.ai)
   {
      RememberFastTick(finalQuote); bool stillAllowed=false;
      for(int i=0;i<ArraySize(aiPlans);i++)
         if(aiPlans[i].sign==signal.direction && aiPlans[i].level==signal.level && AIVisitKey(signal.level,signal.direction)==signal.aiKey)
            stillAllowed=TeacherEntryAllowed(i,finalQuote);
      if(!stillAllowed) { reason="提交前老师允许区域/冲击已变化"; return; }
   }
   if(MathAbs((sign>0 ? finalQuote.ask : finalQuote.bid)-entry)>TickSize()*0.5)
   { reason="提交前执行价格变化，下一报价重新评估"; return; }
   if(!signal.ai && !signal.follow) Store("attemptBar",(double)signal.bar);
   Store(visit,(double)(signal.follow ? 1 : signal.bar));
   ZeroMemory(pending); pending.kind=1; pending.at=TimeCurrent(); pending.bar=signal.bar;
   pending.volume=volume; pending.sl=sl; pending.tp=tp; pending.level=signal.level; pending.direction=sign;
   pending.fast=signal.ai; pending.originHash=signal.originHash;
   pending.exitSL=signal.ai ? signal.exitSL : 0;
   pending.exitFirst=signal.ai ? signal.exitFirst : 0; pending.exitBE=signal.ai ? signal.exitBE : 0;
   pending.exitTP=signal.ai ? signal.exitTP : 0;
   SavePending(); if(!CanExecute()) { reason="请求意图已保存，但执行条件失效，待核对"; return; }
   DecisionLog("REQUEST_INTENT",signal.method);
   execution.PositionOpen(_Symbol,type,volume,entry,sl,tp,EntryTag());
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
string PositionProgress(const ulong id,const int sign,const double open,const double remaining,const double sl)
{
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
   pending.sl=sl; pending.tp=tp; pending.at=TimeCurrent(); SavePending();
   if(!CanExecute()) return;
   DecisionLog("REQUEST_INTENT","申请修改SL/TP，尚未确认");
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
      string exitKey=ExitKey(id); bool custom=Load(exitKey+"ready")==1;
      double customSL=custom ? Load(exitKey+"sl") : 0,be=custom ? Load(exitKey+"be") : 0;
      double required=Align(customSL>0 ? customSL : open-sign*保险价格距离,sign);
      if(be>0 && sign*((sign>0 ? q.bid : q.ask)-be)>=0) required=Align(open,sign);
      if(partialDone) required=Align(open,sign); // 价格保本；不声称已覆盖佣金/隔夜费
      if(sl>0 && sign*(sl-required)>0) required=sl;
      double target=tp;
      if(target<=0 && custom && Load(exitKey+"tp")>0) target=Align(Load(exitKey+"tp"),-sign);
      if(target<=0) target=Align(open+sign*(split ? 尾仓目标价格距离 : 首批止盈价格距离),-sign);
      if(!split && !(custom && Load(exitKey+"tp")>0 && Load(exitKey+"first")==0))
         target=FirstExit(id,sign,open,target);
      if(sl<=0 || sign*(required-sl)>TickSize()*0.5 || MathAbs(target-tp)>TickSize()*0.5)
      {
         Modify(ticket,id,sign,required,target);
         if(pending.kind!=0) return;
      }
      double first=FirstExit(id,sign,open,target);
      double closeVolume=PartialRemaining(initial,closed,volume);
      if((target>0 && sign*(target-first)<=TickSize()) ||
         sign*((sign>0 ? q.bid : q.ask)-first)<0 || closeVolume<=0) continue;
      if(!PositionSelectByTicket(ticket) || !OwnSelected() ||
         MathAbs(PositionGetDouble(POSITION_VOLUME)-volume)>1e-8) continue;
      ZeroMemory(pending); pending.kind=2; pending.position=id; pending.at=TimeCurrent(); pending.volume=closeVolume;
      SavePending(); if(!CanExecute()) return;
      DecisionLog("REQUEST_INTENT","申请分批退出，尚未确认");
      execution.PositionClosePartial(ticket,closeVolume,30);
      RecordResult(); return;
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
bool uiStatistics=false,uiIndicators=false;
int uiWatchTab=0,uiUndoMask=-1; // 看盘子页与一次撤销，仅影响显示
int statsPeriod=0,statsOffsets[3]={0,0,0},statsFilter=0,statsDetail=0,statsReview=0;
// 1收起；27点位线；50..59旧指标；60/61均线组合；70..75策略辅助指标。

// 这些句柄和偏好仅供看盘，与策略maHandle/atrHandle分开。
// 前六项保留旧显示ID，新增均线使用6..9，避免覆盖已有显示偏好。
string uiIndicatorLabels[16]={"MA5","EMA20","布林","RSI","MACD","ATR","MA10","MA50","MA100","MA200","M5·MA5","M15·MA5","确认拐点","昨高低","ADX","随机KD"};
int uiIndicatorHandles[16]={INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE};
string uiIndicatorNotice="指标随当前图表周期；RSI/MACD/ATR/ADX/KD切换副图；固定MA5只显示已收盘值";

const color UI_ROOT=C'14,19,27',UI_HEADER=C'18,25,35',UI_CARD=C'23,31,43';
const color UI_ROW=C'20,28,39',UI_BORDER=C'37,48,63',UI_TEXT=C'232,238,245';
const color UI_MUTED=C'151,166,184',UI_DIM=C'112,130,151',UI_ACCENT=C'89,214,184';
const color UI_GAIN=C'255,151,117',UI_LOSS=C'107,174,239',UI_WARN=C'235,193,120';
const color UI_SELL=C'167,139,250';
#include "Include/Journal/TgeStatistics.mqh"

int UIPx(const double value) { return (int)MathRound(value*panelScale); }
uint UIInk(const color value) { return ColorToARGB(value,255); }
void UIRound(const int x,const int y,const int w,const int h,const color fill,const int radius=8)
{
   int left=UIPx(x),top=UIPx(y),width=UIPx(w),height=UIPx(h);
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
// 位0..15表示本EA的显示指标，位16表示老师点位线；不涉及手工指标。
int UIViewMask()
{
   int mask=uiPointLines ? (1<<16) : 0;
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if(UIIndicatorWindow(i)>=0) mask|=(1<<i);
   return mask;
}
int UIPresetMask(const int preset)
{
   if(preset==0) return (1<<10)|(1<<11)|(1<<12)|(1<<5)|(1<<16);
   if(preset==1) return (1<<0)|(1<<6)|(1<<1)|(1<<3)|(1<<16);
   if(preset==2) return (1<<1)|(1<<7)|(1<<9)|(1<<14)|(1<<16);
   if(preset==3) return (1<<2)|(1<<13)|(1<<3)|(1<<16);
   if(preset==4) return (1<<0)|(1<<1)|(1<<4)|(1<<16);
   return (1<<10)|(1<<12)|(1<<13)|(1<<15)|(1<<16);
}
string UIPresetLabel(const int preset)
{
   string names[6]={"T哥点位","短线节奏","趋势延续","区间震荡","动量确认","结构拐点"};
   return names[preset];
}
string UICombinationText(const int mask)
{
   string text="";
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if((mask & (1<<i))!=0) text+=(text=="" ? "" : " / ")+UIIndicatorLabel(i);
   return text=="" ? "纯K线" : text;
}
bool UISetMask(const int mask)
{
   int oscillators=0;
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if((mask & (1<<i))!=0 && UIIsOscillator(i)) oscillators++;
   if(mask<0 || mask>131071 || oscillators>1) return false;
   // 先加载目标主图，再加载副图；失败时不主动清空原有显示。
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if((mask & (1<<i))!=0 && !UIIsOscillator(i) && !UIIndicatorSet(i,true)) return false;
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if((mask & (1<<i))!=0 && UIIsOscillator(i) && !UIIndicatorSet(i,true)) return false;
   for(int i=0;i<ArraySize(uiIndicatorLabels);i++)
      if((mask & (1<<i))==0 && !UIIndicatorSet(i,false)) return false;
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

void SaveView()
{
   // 显示偏好不写入交易Store，保存失败也不改变交易状态。
   GlobalVariableSet(uiPrefix+"x",uiX); GlobalVariableSet(uiPrefix+"y",uiY);
   GlobalVariableSet(uiPrefix+"fold",uiCollapsed ? 1 : 0);
   GlobalVariableSet(uiPrefix+"lines",uiPointLines ? 1 : 0);
   GlobalVariableSet(uiPrefix+"stats",uiStatistics ? 1 : 0);
   GlobalVariableSet(uiPrefix+"page",uiIndicators ? 2 : uiStatistics ? 1 : 0);
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
   page=MathMax(0,MathMin(page,2)); uiStatistics=page==1; uiIndicators=page==2;
   uiWatchTab=(int)MathMax(0,MathMin(GlobalVariableGet(uiPrefix+"watchTab"),1));
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
   UIButton("监控",12,y,68,2,!uiStatistics && !uiIndicators);
   UIButton("统计",88,y,68,3,uiStatistics);
   UIButton("看盘",164,y,68,4,uiIndicators);
   UIButton(uiMobileMarkers && 启用手机标记挂单 ? "手机TP开" : "手机TP关",240,y,100,28,uiMobileMarkers && 启用手机标记挂单);
   UIText(markerStatus,350,y+7,104,8,UI_DIM);
   UIButton(uiPointLines ? "点位线开" : "点位线关",462,y,82,27,uiPointLines);
}
void IndicatorPage()
{
   UIText("看盘工作台",16,94,240,17,UI_TEXT);
   UIText("组合沿用输入参数中的周期 · 手工添加的指标保留",16,122,520,9,UI_MUTED);
   UIButton("组合模板",16,146,100,80,uiWatchTab==0);
   UIButton("单项指标",124,146,100,81,uiWatchTab==1);
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
   else
   {
      UIText("均线",16,192,160,10,UI_MUTED);
      UIText("点位与结构",16,300,200,10,UI_MUTED);
      UIText("波动与动量",16,364,200,10,UI_MUTED);
      ChartTools(222);
   }
   UIRound(12,502,536,74,UI_HEADER);
   UIText(uiIndicatorNotice,26,513,508,9,UI_MUTED);
   UIText("仅调整看盘显示 · 不切换周期，不改变EA交易条件",26,541,508,9,UI_DIM);
   panelCanvas.Update();
}
void UIButton(const string text,const int x,const int y,const int w,const int action,const bool active=false)
{
   // 导航用底部指示线；开关用状态灯；普通操作保留中性描边。
   bool navigation=(action>=2 && action<=4) || (action>=30 && action<=32) ||
                   (action>=36 && action<=42) || action==80 || action==81;
   bool toggle=action==27 || action==28 || (action>=50 && action<=59) ||
               (action>=70 && action<=75);
   color edge=active ? C'57,121,111' : C'49,63,80';
   color fill=active ? C'24,48,47' : C'22,30,41';
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
   int before=UIViewMask();
   bool recordUndo=action==27 || (action>=50 && action<=75) || (action>=82 && action<=90) || action==93;
   if(action==1) uiCollapsed=!uiCollapsed;
    else if(action==2) { uiStatistics=false; uiIndicators=false; }
    else if(action==3) { uiStatistics=true; uiIndicators=false; }
    else if(action==4) { uiStatistics=false; uiIndicators=true; }
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
   else if(action==80 || action==81) uiWatchTab=action-80;
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
      if(markerPrefix=="" || !启用手机标记挂单) return;
      bool enabled=!uiMobileMarkers;
      if(GlobalVariableSet(markerPrefix+"enabled",enabled ? 1 : 0)==0) return;
      uiMobileMarkers=enabled; markerDirty=true; GlobalVariablesFlush();
   }
   else return;
   if(recordUndo && UIViewMask()!=before) uiUndoMask=before;
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
   int count=ArraySize(tickets),visible=MathMin(count,3),rowHeight=count>0 ? 82 : 66;
   int planCount=读取AI即时策略 && aiReady && aiMode=="SETUP" ? ArraySize(aiPlans) : 0;
   int planRows=MathMax((planCount+1)/2,1);
   int pointRows=MathMax((ArraySize(levels)+5)/6,1);
   int heroY=180,heroHeight=56+planRows*104;
   int decisionY=heroY+heroHeight+12,positionY=decisionY+88;
   int mapY=positionY+24+MathMax(visible,1)*rowHeight+10;
   int mapHeight=62+pointRows*28;
   int height=uiCollapsed ? 122 : uiStatistics ? (statsDetail==2 ? 650 : 570) : uiIndicators ? 592 : mapY+mapHeight+64+MathMax(ArraySize(followMembers)-1,0)*16;
   if(!EnsurePanel(height)) return;
   ArrayResize(uiHits,0);
   panelCanvas.Erase(UIInk(UI_ROOT));
   UIRound(0,0,560,height,UI_ROOT);
   panelCanvas.FillRectangle(0,0,UIPx(559),UIPx(39),UIInk(UI_HEADER));
   string pageTitle=uiStatistics ? "交易统计" : uiIndicators ? "看盘设置" : "T哥点位监控";
   UIText(_Symbol+" · "+pageTitle,16,10,222,11,UI_TEXT);
   UIText("v1.37",242,13,40,8,UI_DIM);
   UIText(TimeToString(TimeGMT()+8*3600,TIME_SECONDS),286,12,100,10,UI_MUTED,true);
   UIButton(uiCollapsed ? "+" : "−",396,7,30,1);
   UIText(启用真实交易 ? "交易模式" : "观察模式",434,13,110,9,启用真实交易 ? UI_ACCENT : UI_WARN,true);
   PageTabs(49);
   ObjectSetString(0,VIEW+"CANVAS",OBJPROP_TOOLTIP,
                   "拖动标题移动面板；−收起 / +展开 · "+feedStatus+
                   " · 来源 "+sourceSender+" · 消息 "+identity+
                   " · 老师来源 "+aiSource+" · "+uiIndicatorNotice+" · 手机TP标记："+markerStatus);
   if(uiCollapsed)
   {
      string compact=uiStatistics ? "统计页 · 点击 + 展开" :
                     uiIndicators ? "看盘页 · 指标显示设置" :
                     "监控 · "+IntegerToString(count)+"单 · "+reason;
      UIText(compact,16,94,526,9,UI_MUTED);
      panelCanvas.Update(); return;
   }
   if(uiStatistics) { StatsPanel(); return; }
   if(uiIndicators) { IndicatorPage(); return; }

   // 一级：账户内本EA的实际持仓；不用“可评估”充当风控状态。
   UIRound(12,88,536,80,UI_CARD);
   UIText("浮动盈亏 / "+AccountInfoString(ACCOUNT_CURRENCY),28,99,222,9,UI_MUTED);
   UIText((pnl>0 ? "+" : "")+DoubleToString(pnl,2),28,122,224,24,
          pnl>0 ? UI_GAIN : pnl<0 ? UI_LOSS : UI_TEXT);
   panelCanvas.FillRectangle(UIPx(266),UIPx(106),UIPx(266),UIPx(150),UIInk(UI_BORDER));
   UIText("持仓",284,100,112,9,UI_MUTED);
   UIText(IntegerToString(count)+" 单",284,123,112,17,UI_TEXT);
   UIText(DoubleToString(volume,2)+" 手",284,148,112,8,UI_DIM);
   UIText("仓位保护",418,100,114,9,UI_MUTED);
   UIText("SL "+IntegerToString(protectedCount)+"/"+IntegerToString(count),418,125,114,12,UI_TEXT);
   UIText("TP "+IntegerToString(tpCount)+"/"+IntegerToString(count),418,148,114,8,UI_DIM);

   // 二级：即时方向独立于整日地图，优先显示方向、价格和来源时间。
   UICard(12,heroY,536,heroHeight,UI_ROW);
   UIText("T哥即时参考",28,heroY+13,200,11,UI_TEXT);
   string aiAt=读取AI即时策略 && aiSourceTime>0 ? TimeToString(aiSourceTime+8*3600,TIME_MINUTES)+" 北京时间" : "等待来源";
   UIText(aiAt,322,heroY+15,208,9,UI_DIM,true);
   if(planCount>0)
      for(int i=0;i<planCount;i++)
      {
         int x=24+(i%2)*260,y=heroY+40+(i/2)*104;
         bool buy=aiPlans[i].sign>0;
         color ink=buy ? UI_ACCENT : UI_SELL;
         UIRound(x,y,252,94,buy ? C'20,47,44' : C'36,32,53');
         UIText(buy ? "BUY / 多" : "SELL / 空",x+12,y+8,104,9,ink);
         UIText(DoubleToString(aiPlans[i].level,_Digits),x+12,y+27,148,18,UI_TEXT);
         UIText(aiPlans[i].market ? "即时市价" : "实时近价",x+160,y+34,80,8,ink,true);
          UIText(StringFormat("允许 %.2f—%.2f",aiPlans[i].level-TEACHER_BAND,aiPlans[i].level+TEACHER_BAND),x+12,y+58,228,8,UI_MUTED);
          UIText(aiPlans[i].status,x+12,y+76,228,7.5,UI_MUTED);
      }
   else
   {
      UIText(读取AI即时策略 ? (aiReady ? "沿用完整点位地图" : "等待AI有效参考") : "按完整点位地图判断",
             28,heroY+47,500,15,读取AI即时策略 && !aiReady ? UI_WARN : UI_TEXT);
   }
   UIText(读取AI即时策略 ? AIPlanCaption() : "M5方向 · M1收线确认",28,heroY+heroHeight-19,502,8,UI_MUTED);

   string trendText=!entryView.ready ? "等待数据" : trend>0 ? "M5偏多" : trend<0 ? "M5偏空" : "M5震荡";
   UIText("当前判断",16,decisionY+3,106,9,UI_DIM);
   UIText(trendText,132,decisionY+3,132,9,UI_MUTED);
   UIText(entryView.method=="T哥实时近价" ? (entryView.reaction ? "tick检查已通过" : "实时tick观察") : entryView.ready ? (entryView.reaction ? "M1反应已确认" : "等待M1反应") : "等待数据",
          336,decisionY+3,204,9,entryView.ready && entryView.reaction ? UI_ACCENT : UI_MUTED,true);
   UIText(reason,16,decisionY+25,526,12,UI_TEXT);
   string detail=entryView.ready ? StringFormat("%s参考 %.2f  ·  距点位 %.2f",
                 entryView.direction>0 ? "多" : "空",entryView.level,entryView.distance) : "有明确方向与价格后，按策略条件评估";
   UIText(detail,16,decisionY+52,372,9,UI_MUTED);
   UIText(StringFormat("每次 %.2f手",每次开仓手数),390,decisionY+52,152,9,UI_DIM,true);

   UIText("持仓明细",16,positionY,220,10,UI_TEXT);
   UIText(count>3 ? "仅显示最近3笔 / 共"+IntegerToString(count)+"笔" : "仅本EA持仓",324,positionY,216,8.5,UI_DIM,true);
   for(int row=0;row<MathMax(visible,1);row++)
   {
      int y=positionY+24+row*rowHeight;
      UICard(12,y,536,rowHeight-6,UI_ROW);
      if(count==0)
      {
         panelCanvas.FillRectangle(UIPx(13),UIPx(y+12),UIPx(15),UIPx(y+45),UIInk(UI_ACCENT));
         UIText("当前没有本EA持仓",28,y+12,480,11,UI_TEXT);
         UIText("等待符合条件的机会 · 成交后显示分批与保护进度",28,y+35,480,9.5,UI_MUTED);
         break;
      }
      if(!PositionSelectByTicket(tickets[row])) continue;
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      color sideInk=buy ? UI_ACCENT : UI_SELL;
      double profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      UIText(buy ? "BUY" : "SELL",24,y+8,54,11,sideInk);
      UIText("#"+IntegerToString((long)tickets[row])+" · "+DoubleToString(PositionGetDouble(POSITION_VOLUME),2)+"手",
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

   // 地图作为次要参考，使用轻量分隔与数字，避免与即时方向争夺视觉注意力。
   UIRound(12,mapY,536,mapHeight,UI_HEADER);
   UIText("完整点位地图",28,mapY+11,180,10,UI_MUTED);
   string source=sourceKind=="teacher" ? "T哥原文" : sourceKind=="" ? "等待来源" : "群成员地图";
   string sourceAt=sourceTime>0 ? TimeToString(sourceTime+8*3600,TIME_DATE|TIME_MINUTES) : "尚未同步";
   UIText(source+" · "+sourceAt,220,mapY+12,312,8,UI_DIM,true);
   for(int i=0;i<ArraySize(levels);i++)
      UIText(DoubleToString(levels[i],_Digits),28+(i%6)*85,mapY+34+(i/6)*28,78,11,feedActive ? UI_TEXT : UI_DIM);
   if(ArraySize(levels)==0) UIText("等待飞书同步完整点位",28,mapY+35,498,10,UI_DIM);
   UIText(SyncStatus(),28,mapY+mapHeight-18,494,8,feedActive ? UI_MUTED : UI_WARN);

   string gate=ExecutionBlock(); MqlTick displayQuote;
   if(gate=="" && feedActive && !FreshQuote(displayQuote)) gate="报价过期/断线，暂停新请求";
   else if(gate=="" && feedActive && displayQuote.ask-displayQuote.bid>最大点差价格) gate="当前点差超过上限";
   if(gate=="") gate=feedActive ? "按策略条件等待机会" : "等待有效点位地图";
   if(ArraySize(followMembers)==0) UIText(FollowCaption(),16,height-49,526,8,UI_DIM);
   else for(int i=0;i<ArraySize(followMembers);i++)
      UIText(FollowMemberCaption(i),16,mapY+mapHeight+15+i*16,526,8,UI_DIM);
   UIText("执行 · "+gate,16,height-29,526,9,pending.kind!=0 ? UI_WARN : UI_MUTED);
   panelCanvas.Update();
}
int OnInit()
{
   if(每次开仓手数<=0 || 最大同时持仓<1 || 最大同时持仓>10 ||
      冲击短窗毫秒<1000 || 冲击短窗毫秒>10000 || !MathIsValidNumber(逆向冲击速度) || 逆向冲击速度<=0 ||
       !MathIsValidNumber(冲击单向比例) || 冲击单向比例<=0.5 || 冲击单向比例>1 ||
       !MathIsValidNumber(恢复回拉价格) || 恢复回拉价格<=0 ||
       最大点差价格<=0 || 学员最大追价价格差<=0 || !MathIsValidNumber(学员最大追价价格差) ||
       学员最大回落价格差<=0 || !MathIsValidNumber(学员最大回落价格差) ||
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
   RestorePending(); RestoreSharedVisits();
   InitView(); InitTgeMobileMarkers();
   fastStarted=TimeGMT(); readyFrom=TimeCurrent(); ReadFeed(); ReadHealth(); ReadAISetups(); ReadMemberFollow(); EventSetTimer(1); Panel();
   return INIT_SUCCEEDED;
}
void OnTimer()
{
   if(busy) return; busy=true;
   ReadFeed(); ReadHealth(); ReadAISetups(); ReadMemberFollow(); Reconcile(); Manage();
   MqlTick sampled;
   if(FreshQuote(sampled)) { RememberFastTick(sampled); UpdateTeacherVisits(sampled); UpdateSharedVisit(sampled); }
   Candidate immediate; ZeroMemory(immediate);
   if(AIMarketSignal(immediate) || MemberFollowSignal(immediate)) Open(immediate);
   if(aiReady && FreshQuote(sampled))
      for(int i=0;i<ArraySize(aiPlans);i++) TeacherEntryAllowed(i,sampled);
   datetime minute=iTime(_Symbol,PERIOD_M1,1);
   if(minute>0 && minute!=lastMinute)
   {
      checkingMinute=minute; Candidate candidate; ZeroMemory(candidate);
      if(Signal(candidate)) Open(candidate);
      string gate=ExecutionBlock();
      DecisionLog("EVALUATE",(gate!="" ? gate+" · " : "")+reason);
      if(!signalRetry) lastMinute=minute;
   }
   SyncTgeMobileMarkers(); Panel(); busy=false;
}
void OnTick()
{
   MqlTick q; if(!FreshQuote(q)) return;
   RememberFastTick(q);
   UpdateTeacherVisits(q); UpdateSharedVisit(q);
   if(busy || pending.kind!=0 || !CanExecute() || !TeacherOwnsZone(q)) return;
   busy=true;
   Candidate immediate; ZeroMemory(immediate);
   if(AIMarketSignal(immediate)) Open(immediate);
   busy=false;
}
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
   EventKillTimer(); StopTgeMobileMarkers();
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
