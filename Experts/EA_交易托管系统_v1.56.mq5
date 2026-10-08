//+------------------------------------------------------------------+
//| EA_交易托管系统_v1.56.mq5                                         |
//| 交易托管系统：默认主要管理当前图表品种上的已有持仓；老师点位自动反转功能可独立启用。   |
//+------------------------------------------------------------------+
#property strict
#property version "1.56"
#property description "交易托管系统"

#include <Trade/Trade.mqh>
#include <Canvas/Canvas.mqh>
// 真实受管持仓与手机辅助标记必须使用不同的交易对象，避免标记Magic污染退出Deal。
CTrade manageTrade;
CTrade markerTrade;
CTrade teacherAutoTrade;
CTrade newsStopTrade;

// 老师点位自动反转单使用固定独立Magic，避免与手动单、托管单和手机标记混用。
const long TEACHER_AUTO_SHORT_MAGIC = 560006;
const string TEACHER_AUTO_COMMENT_PREFIX = "TEACHER_AUTO_REV";
const int TEACHER_AUTO_PENDING_TIMEOUT_SECONDS = 90;

const string EA版本 = "1.56";

enum 距离模式
{
   距离关闭 = 0,
   固定价格距离 = 1,
   ATR倍数距离 = 2
};

enum 面板页面
{
   页面持仓 = 0,
   页面今日 = 1
};

enum 面板显示模式
{
   面板隐藏 = 0,
   面板迷你 = 1,
   面板完整 = 2
};

enum 面板信息密度
{
   面板信息_简单 = 0,
   面板信息_专业 = 1
};

enum 统计周期模式
{
   统计_日 = 0,
   统计_周 = 1,
   统计_月 = 2
};

enum 统计策略筛选
{
   统计筛选_短线 = 0,
   统计筛选_全部 = 1,
   统计筛选_趋势 = 2,
   统计筛选_普通 = 3,
   统计筛选_消息 = 4
};

enum 统计详情页面
{
   统计详情_总览 = 0,
   统计详情_策略 = 1,
   统计详情_管理 = 2,
   统计详情_执行 = 3,
   统计详情_复盘 = 4,
   统计详情_走势 = 5
};

enum 追踪SL模式
{
   追踪固定距离 = 0,        // 使用原来的固定启动/固定距离
   追踪ATR自适应 = 1,       // 跟随当前M1 ATR自动调整启动距离和追踪距离
   追踪结构自适应 = 2,       // ATR距离 + 最近支撑/压力结构位，优先给行情呼吸空间
   追踪M1前柱结构 = 3       // 用最近M1已收线K线低点/高点作为短线结构防守位
};

enum 管理配置模板
{
   配置_自定义 = 0,          // 完全使用下面所有输入参数
   配置_黄金超短快保 = 1,    // 短线单：适合XAUUSD M1短线，快速保本、分批与结构保护
   配置_黄金稳健托管 = 2,    // 趋势单：长期方向单托管，H1/H4定方向，M30/H1结构保护
   配置_黄金支压止盈 = 3,    // 手动单：只显示R/S和提示，不自动止盈止损、不分批、不改SL/TP
   配置_黄金消息对冲 = 4     // 消息对冲：手动开等手数多空，自动拆亏损边并托管盈利边
};

enum 消息对冲阶段
{
   消息阶段_待命 = 0,
   消息阶段_配对安全 = 1,
   消息阶段_箱体冻结 = 2,
   消息阶段_释放窗口 = 3,
   消息阶段_拆锁中 = 4,
   消息阶段_冲击持仓 = 5,
   消息阶段_延续持仓 = 6,
   消息阶段_组合退出 = 7
};

enum 消息高点差超时处理模式
{
   高点差超时处理_整组退出 = 0,
   高点差超时处理_安全条件满足后强制拆锁 = 1
};

enum 消息双Stop阶段
{
   消息双Stop_空闲 = 0,
   消息双Stop_创建BUY待确认 = 1,
   消息双Stop_创建SELL待确认 = 2,
   消息双Stop_已武装 = 3,
   消息双Stop_OCO撤单中 = 4,
   消息双Stop_全部撤单中 = 5,
   消息双Stop_单边托管 = 6,
   消息双Stop_故障 = 7
};

enum 老师点位短线辅助模式
{
   老师点位辅助_仅TP = 0,
   老师点位辅助_TP与突破保护SL = 1
};

input string          老师点位文本              = "";          // 非空时解析老师点位并用SMA_MARK_K*的TP线同步到手机端
input bool            短线单启用老师点位辅助SLTP = false;       // 独立交易开关；关闭时老师文本只用于手机标记，不改变短线管理
input 老师点位短线辅助模式 老师点位短线模式 = 老师点位辅助_TP与突破保护SL;

input group "17 进阶｜老师点位自动反转短线"
input bool            启用老师点位自动反转短线 = true;          // 默认启用已有老师自动策略；仍需有效点位、交易权限及风控放行
input double          老师点位自动短线固定手数 = 0.01;          // 严格按输入手数校验，不合规时跳过开仓
input double          老师点位自动接近ATR倍数 = 0.35;           // 价格进入老师线附近的ATR自适应区域
input double          老师点位自动接近最大价格 = 1.00;         // 避免高波动时入场区域无限扩大
input double          老师点位自动反转最小影线比例 = 0.30;     // 拒绝影线占K线总振幅的最低比例
input double          老师点位自动反转最大实体比例 = 0.55;     // 放缓K线实体/振幅的最大比例
input double          老师点位自动重新武装距离价格 = 1.00;     // 离开原点位达到该距离后才允许再次触发
input int             老师点位自动冷却秒 = 60;                 // 开仓请求后的最短再次搜索间隔

input group "17A 进阶｜老师点位多周期过滤"
input bool            启用老师点位自动5日结构过滤 = true;       // 老师点位必须位于最近5根已收盘D1的外侧边缘
input double          老师点位自动5日结构边缘比例 = 0.25;       // 取5日高低区间外侧比例，区间中部不参与反转
input double          老师点位自动5日结构最大边缘距离 = 12.0;   // 对大波动日线设置边缘带上限，避免过滤过宽
input bool            启用老师点位自动M5确认 = true;            // M5已收盘拒绝/收回确认后，才交给M1最终触发

input group "17B 进阶｜老师点位积极交易（总开关仍为17组自动反转开关）"
input bool            老师自动使用积极策略 = true;             // false恢复旧反转；仅影响新开仓
input double          老师自动顺势风险百分比 = 0.35;           // 兼容旧set；积极模式现按17组固定手数
input double          老师自动逆势风险百分比 = 0.175;          // 兼容旧set；积极模式现按17组固定手数
input double          老师自动接近M5ATR = 0.35;
input double          老师自动追价上限M5ATR = 0.50;
input double          老师自动突破缓冲M5ATR = 0.15;
input double          老师自动止损缓冲M5ATR = 0.15;
input double          老师自动最低净盈亏比 = 1.50;
input double          老师自动每手往返费用 = 0.0;             // 账户币种；填券商佣金/费用估计，点差另计
input double          老师自动日内亏损上限百分比 = 1.50;      // 当日首次观察净值为基准；触发后只禁新单
input int             老师自动连续止损上限 = 3;
input int             老师自动每点每日尝试上限 = 0;          // 兼容旧set，已停用；不限制每日次数
input int             老师自动止损冷却秒 = 60;
input int             老师自动同时最大持仓 = 5;
input bool            老师自动允许震荡双向 = true;
input double          老师自动贪婪首段R = 2.50;
input double          老师自动贪婪保护R = 1.50;
input datetime        老师自动点位生效时间 = 0;              // 券商服务器时间；0=首次收到这套点位的时间
input datetime        老师自动点位失效时间 = 0;              // 0=生效后24小时；重启不会自动续期

input group "01 常用｜管理范围与模板"
//===================== 管理范围 =====================//
input bool     启用辅助管理          = true;
input bool     只管理手动单          = true;      // true=只管Magic=0；false=管指定Magic
input long     指定管理Magic         = 0;
input bool     管理多单              = true;
input bool     管理空单              = true;
input 管理配置模板 参数配置模板       = 配置_自定义; // 非自定义时，核心风控参数按模板生效，减少手动配置量
管理配置模板 当前参数配置模板 = 配置_自定义; // 面板按钮可运行时切换；初始值来自 input 参数配置模板

// 面板模板只决定下一笔新成交的默认管理方式。已接管持仓在成交确认时冻结模板，
// 后续切换面板配置不能改变旧仓的SL/TP、分批或追踪节奏。
struct ConfirmedEntryTemplateStamp
{
   ulong positionIdentifier;
   int   templateId;
   datetime time;
};
ConfirmedEntryTemplateStamp confirmedEntryTemplateStamps[];

input group "02 常用｜短线初始SL/TP（动态箱体）"
input bool     短线单保留已有初始SLTP = true;     // 接管已有手动SL/TP时不按箱体主动收紧，盈利保护阶段仍可推进SL
input double   短线单初始SL_ATR倍数  = 1.65;      // 初始风险随M1波动变化
input double   短线单初始SL最小价格  = 5.00;
input double   短线单初始SL最大价格  = 10.00;
input double   短线单主TP_ATR倍数     = 2.20;      // 短线单主目标：随波动动态落在5-10价格区间
input double   短线单主TP最小价格     = 5.00;
input double   短线单主TP最大价格     = 12.00;
input double   短线单主TP最小风险回报比 = 1.05;    // 主TP至少尽量覆盖初始风险；仍受主TP最大价格限制
input double   短线单顺势TP价格       = 12.00;      // M5趋势与持仓方向一致时，允许多拿到该目标附近
input double   短线单好行情TP最低价格 = 7.50;      // 趋势和M1动能都支持时，目标尽量不低于该值
input bool     短线单启用箱体边缘TP_SL = true;     // 短线单优先用震荡箱体上下沿动态设置TP/SL

input group "03 常用｜通用初始保护"
//===================== 基础保护 =====================//
input bool     忽略点差过滤          = true;      // true=不因点差过大暂停管理
input int      最大点差点数          = 90;        // 仅用于面板参考；忽略点差过滤=false时才参与拦截
input int      最小修改间隔秒        = 1;
input 距离模式 初始SL模式            = 固定价格距离;
input 距离模式 初始TP模式            = ATR倍数距离;
input double   固定SL价格距离        = 10.0;      // XAUUSD默认约10美元
input double   固定TP价格距离        = 6.0;
input int      ATR周期               = 14;
input double   ATR止损倍数           = 1.5;
input double   ATR止盈倍数           = 2.2;

input group "04 常用｜保本与基础追踪"
//===================== 盈利保护 =====================//
input bool     启用保本              = true;
input double   保本触发价格          = 2.0;
input double   保本锁定价格          = 0.20;
input bool     启用移动止损          = true;
input double   移动止损启动价格      = 3.0;       // 固定追踪模式使用；自适应模式作为兜底/显示参考
input double   移动止损距离价格      = 1.60;      // 固定追踪模式使用；自适应模式作为兜底/显示参考
input int      移动止损最小推进点数  = 20;

input group "05 进阶｜自适应追踪SL"
//===================== 自适应追踪SL =====================//
input 追踪SL模式 跟踪SL模式            = 追踪M1前柱结构;
input double   动态追踪启动ATR倍数    = 1.2;       // ATR越大，越晚启动，避免波动放大时被洗掉
input double   动态追踪距离ATR倍数    = 1.0;       // ATR越大，SL离现价越远
input double   动态追踪最小启动价格   = 2.5;
input double   动态追踪最大启动价格   = 8.0;
input double   动态追踪最小距离价格   = 1.2;
input double   动态追踪最大距离价格   = 4.0;
input double   动态追踪最小推进ATR倍数 = 0.25;      // 波动越大，SL最小推进步长越大，减少频繁微调
input double   结构SL缓冲价格          = 0.30;      // 多单SL放支撑下方，空单SL放压力上方，预留一点缓冲

input group "06 进阶｜M1结构追踪SL"
//===================== M1前柱结构追踪SL =====================//
input int      M1结构追踪K线数        = 1;         // 取最近N根已收M1 K线，BUY用最低点，SELL用最高点；1更激进，3更稳
input double   M1结构SL缓冲价格       = 0.10;      // BUY: 低点-缓冲；SELL: 高点+缓冲
input double   M1结构最小浮盈启动     = 2.5;       // 浮盈不足时不启用M1结构追踪，避免刚入场被噪声扫出
input double   M1结构追踪启动ATR倍数  = 1.2;       // 启动门槛=max(该值, ATR*倍数)
input double   M1结构最小SL距离       = 0.80;      // SL离当前价太近则不更新
input double   M1结构最小SL距离ATR倍数 = 0.60;     // 最小SL距离同时参考ATR，波动大时自动放宽
input bool     M1结构只在新K线更新    = true;      // 只用已收线结构；默认新M1收线后才推进SL，减少来回微调

input group "07 进阶｜阶梯保护与防扫损提醒"
//===================== 阶梯式利润保护/防扫损提醒 =====================//
input bool     启用阶梯式保护        = false;     // 可选备用；默认关闭，主逻辑改为自适应追踪SL
input bool     阶梯保护时暂停贴身追踪  = false;     // 若开启阶梯保护，默认也允许自适应追踪继续工作
input double   阶梯1触发价格          = 3.0;
input double   阶梯1锁定价格          = 0.20;
input double   阶梯2触发价格          = 5.0;
input double   阶梯2锁定价格          = 2.0;
input double   阶梯3触发价格          = 7.0;
input double   阶梯3锁定价格          = 4.0;
input double   阶梯4触发价格          = 10.0;
input double   阶梯4锁定价格          = 6.5;
input bool     启用SL过紧预警         = true;      // 只提醒，不自动纠正用户手动拉紧的SL
input double   SL过紧浮盈阈值         = 2.5;       // 未达到该浮盈时，提前锁利容易被正常回踩扫掉
input double   SL提前锁利容忍价格     = 0.20;      // 未达阈值时，SL锁利超过该值则提示过紧
input double   SL距离当前价过近       = 0.80;      // 当前价到SL小于该距离，也提示容易被扫

input group "08 常用｜止盈参考"
//===================== 支撑压力止盈参考 =====================//
input bool     显示支撑压力TP建议     = true;
input double   TP贴近点位缓冲价格     = 0.20;      // 多单建议TP=压力位-缓冲；空单建议TP=支撑位+缓冲
input double   持仓目标空间不足距离   = 1.0;       // 到最近R/S小于该距离时，提示目标空间不足
input bool     短线单显示推荐止盈点位 = true;       // 短线单持仓后，在面板显示基于R/S的推荐TP
input double   短线单推荐TP最小空间价格 = 2.50;     // 推荐主TP至少要离均价这么远；不足则提示空间窄或看下一档
input bool     短线单空间不足优先看下一档 = true;   // R1/S1空间不足时，优先推荐R2/S2

input group "09 进阶｜短线多段分批细节"
//===================== 分批止盈 =====================//
input bool     启用分批止盈          = true;       // 到最近支撑/压力附近先落袋一部分，剩余仓位继续跟踪SL
input double   分批止盈比例          = 0.50;       // 默认平掉50%仓位
input double   分批止盈接近点位距离  = 0.30;       // BUY接近R1、SELL接近S1到该距离内触发
input double   分批止盈最小浮盈价格  = 2.0;        // 避免刚开仓附近噪声触发
input double   分批止盈目标最小空间价格 = 2.50;      // 目标R/S距离开仓价不足时不分批，避免刚进场附近小线过早平半
input double   分批止盈后保本锁定    = 0.20;       // 分批后，剩余仓位至少尝试锁到开仓价±该距离
input bool     分批后立即保护剩余仓位 = true;       // 分批成功后继续由M1结构追踪SL管理剩余仓位
input bool     短线单分批使用行情节奏 = true;       // 短线单不再死等R/S，按M1高低点和动能犹豫分批
input double   短线单分批最小浮盈价格 = 1.80;
input double   短线单分批最小浮盈ATR倍数 = 0.70;
input double   短线单分批主TP比例上限 = 0.82;      // 浮盈未接近主TP时才用节奏分批；接近主TP交给TP/追踪
input int      短线单分批局部高低回看M1 = 6;
input double   短线单分批靠近高低点最小价格 = 0.30;
input double   短线单分批靠近高低点ATR倍数 = 0.22;
input double   短线单分批震荡实体比例上限 = 0.45; // M1实体/振幅偏小，视为走不动
input double   短线单分批动能回撤ATR倍数 = 0.25;  // 从最大浮盈回撤一点，也允许先落袋
input double   短线单分批利润保护启动价格 = 5.00;  // 到达5美金以上，优先保护一部分利润
input double   短线单分批主TP保护比例 = 0.65;      // 到达主TP的一定比例，也允许先分批
input double   短线单分批利润回吐保护价格 = 0.80;  // 曾经赚到较多后回吐这么多，触发分批保护
input double   短线单分批利润回吐ATR倍数 = 0.30;
input bool     短线单分批手数不足则全平 = true;   // 0.01手无法分批时，达到保护条件直接全收
input double   短线单分批手数不足全平最小盈利 = 5.00;
input bool     短线单启用多段分批止盈 = true;     // 短线单专用：第一段平初始仓位40%，第二段收完剩余仓位
input int      短线单最大分批段数 = 2;            // 当前策略运行逻辑固定最多两段；保留input用于旧.set兼容
input int      短线单分批最小间隔秒 = 45;          // 避免同一波tick连续触发多段，给下一根M1确认行情延续
input double   短线单第1段基础触发盈利 = 4.50;
input double   短线单第1段最早触发盈利 = 3.80;
input double   短线单第1段最晚触发盈利 = 5.50;
input double   短线单第1段基础分批比例 = 0.40;     // 当前两段策略固定使用40%，比例input仅兼容旧.set
input double   短线单第1段最小分批比例 = 0.40;
input double   短线单第1段最大分批比例 = 0.40;
input double   短线单第1段基础锁定利润 = 0.30;
input double   短线单第1段最小锁定利润 = 0.15;
input double   短线单第1段最大锁定利润 = 0.55;
input double   短线单第2段基础触发盈利 = 7.00;
input double   短线单第2段最早触发盈利 = 6.00;
input double   短线单第2段最晚触发盈利 = 8.50;
input double   短线单第2段基础分批比例 = 0.60;     // 当前两段策略第二段直接全平剩余仓位
input double   短线单第2段最小分批比例 = 0.60;
input double   短线单第2段最大分批比例 = 0.60;
input double   短线单第2段基础锁定利润 = 2.20;
input double   短线单第2段最小锁定利润 = 1.50;
input double   短线单第2段最大锁定利润 = 3.20;
input double   短线单第3段基础触发盈利 = 10.00;
input double   短线单第3段最早触发盈利 = 8.50;
input double   短线单第3段最晚触发盈利 = 12.50;
input double   短线单第3段基础分批比例 = 0.50;
input double   短线单第3段最小分批比例 = 0.35;
input double   短线单第3段最大分批比例 = 0.65;
input double   短线单第3段基础锁定利润 = 4.80;
input double   短线单第3段最小锁定利润 = 3.50;
input double   短线单第3段最大锁定利润 = 6.50;
input double   短线单多段分批最小剩余手数 = 0.01;
input bool     短线单多段分批不足则跳过 = true;   // 小手数无法保留尾仓时跳过，避免0.01手反复报错
input bool     短线单尾仓交给结构追踪 = true;

input group "10 进阶｜短线回撤、时间与快保"
//===================== 回撤/时间保护 =====================//
input bool     启用浮盈回撤保护      = true;
input double   回撤保护启动价格      = 4.0;
input double   最大浮盈回撤比例      = 0.35;
input double   回撤后锁定利润比例    = 0.50;
input int      最大持仓分钟数        = 0;         // 0=关闭
input bool     超时后收紧到保本      = true;
input bool     短线单启用成本线快收  = false;     // 默认关闭：不再因持仓时间把原TP机械收近；需要时可手动开启
input group "10B 进阶｜短线箱体、快保与执行细节"
input int      短线单箱体识别回看M1 = 24;          // 仅已收M1；限制在20-30根，专供结构箱体视觉边界确认
input int      短线单箱体摆点强度M1 = 1;           // 局部高低点左右比较根数，1-2
input double   短线单箱体边界聚类ATR倍数 = 0.15;
input double   短线单箱体边界最小容差价格 = 0.20;
input double   短线单箱体候选最小箱内收盘比例 = 0.65;
input double   短线单箱体有效最小箱内收盘比例 = 0.75;
input double   短线单箱体有效最小宽度ATR倍数 = 1.50;
input double   短线单箱体有效最大宽度ATR倍数 = 4.50;
input int      短线单箱体突破失效确认M1 = 2;       // 连续已收M1有效突破后淘汰旧箱体并重新寻找整理区
input group "11 审计与兼容｜生命周期、确认与超时"
//===================== 交易生命周期审计（只记录，不参与交易） =====================//
input bool     启用交易生命周期记录 = true;
input bool     交易生命周期记录原始Deal = true;
input bool     交易生命周期启动时导入终端历史 = true; // 仅能补录经纪商成交，不能倒推过去的Tick级管理轨迹
input int      交易生命周期快照秒数 = 60;          // 开仓期间的状态快照，最小10秒
input bool     启用性能统计 = false;                // 仅测量耗时并定期输出，不写CSV/Global Variables，不参与交易判断
input int      性能统计输出秒数 = 60;               // 统一输出count/avg_us/max_us，最小10秒
input int      短线单SLTP确认超时秒数 = 15;        // 请求已接受但服务器值未确认时，超时后对账并解除请求锁
input int      短线单平仓确认超时秒数 = 20;        // 全平请求超时后按positionIdentifier补录Deal并只重试剩余手数
input int      短线单平仓重试冷却秒数 = 3;         // 全平超时对账后的最小重试间隔
input bool     短线单检测外部手数变化 = true;      // 识别手动加减仓和Netting反转，不把外部减仓冒充策略分批
input double   短线单箱体TP贴边缓冲价格 = 0.30;    // 多单TP=箱体上沿-缓冲；空单TP=箱体下沿+缓冲
input double   短线单箱体SL外侧缓冲价格 = 0.65;    // 多单SL=箱体下沿-缓冲；空单SL=箱体上沿+缓冲
input double   短线单箱体TP最小空间价格 = 3.50;    // 箱体边缘离开仓太近则不用作主TP
input double   短线单箱体TP最大空间价格 = 14.00;   // 过远箱体边缘不强行替代短线TP
input double   短线单箱体SL最小距离价格 = 3.50;    // SL离开仓太近时不用，避免噪声扫
input double   短线单箱体SL最大距离价格 = 10.00;   // SL太宽时不用，避免短线扛单
input double   短线单箱体最低交易评分 = 14.0;      // 弱箱体不再直接参与SL/TP
input int      短线单箱体最低触碰次数 = 2;
input double   短线单箱体TP最小主目标比例 = 0.72;  // 箱体TP至少达到动态主目标一定比例，避免近目标
input bool     短线单箱体允许收近已有TP = true;    // 已有TP若远过箱体边缘，可收近到箱体边
input bool     短线单箱体允许放远已有TP = false;   // 短线单只允许箱体收近TP，不主动把已有短线TP放远
input int      短线单成本线最短犹豫分钟 = 5;       // 持仓后仍在成本附近磨蹭多久，才开始考虑缩小TP
input int      短线单成本线最长犹豫分钟 = 12;      // 波动较大时给更多启动时间，再判断是否磨成本
input double   短线单成本线小TP_ATR倍数 = 1.20;
input double   短线单成本线小TP最小价格 = 3.50;
input double   短线单成本线小TP最大价格 = 4.80;
input bool     短线单浮亏回本直接平仓 = true;     // 短线单专用：曾经浮亏较深，回到小赚/保本直接收
input double   短线单浮亏回本触发ATR倍数 = 1.00;
input double   短线单浮亏回本触发最小价格 = 2.80; // 曾经最大浮亏达到该价格后，回到小赚才直接平仓
input double   短线单回本平仓盈利ATR倍数 = 0.08;
input double   短线单回本平仓最小盈利 = 0.10;
input double   短线单回本平仓最大盈利 = 0.40;
input bool     短线单强顺势不提前快收 = true;   // 趋势顺着持仓且已走出利润时，不缩小TP、不回本快收
input double   短线单强顺势确认ATR倍数 = 0.65;
input double   短线单震荡保本触发ATR倍数 = 0.85;  // 震荡也需走出足够波动后再保本
input double   短线单震荡保本最小价格 = 2.40;
input double   短线单震荡保本最大价格 = 3.40;
input double   短线单好行情保本触发ATR倍数 = 1.35; // 好行情给更大呼吸空间，避免刚启动被噪声扫
input double   短线单好行情保本最小价格 = 3.60;
input double   短线单保本最小风险R = 0.60;       // 保本不得早于初始风险的该比例
input bool     短线单保护需M1收线确认 = true;    // 保本和结构追踪需最近已收M1仍保持足够利润
input double   短线单结构追踪最小风险R = 0.90;   // M1结构追踪至少在接近1R后接管
input double   短线单回撤保护最小风险R = 0.90;   // 回撤保护至少在最大浮盈接近1R后启动
input double   短线单保本锁定最小价格 = 0.08;
input double   短线单好行情保本锁定价格 = 0.20;
input bool     短线单保本锁定使用点差 = true;     // [deprecated] 仅保留旧.set兼容；短线净保本不再把当前点差固定加入SL。
input double   短线单保本点差额外缓冲价格 = 0.00; // [deprecated] 仅保留旧.set兼容。
input double   短线单净保本安全金额每001手 = 0.00; // 按账户货币计算；0表示只覆盖已知成本
input bool     短线单启用快速利润保护 = true;
input int      短线单快速保护观察秒数 = 10;
input double   短线单快速保护启动R = 1.00;
input double   短线单快速保护实体ATR倍数 = 1.50;
input double   短线单快速保护TP完成比例 = 0.70;
// 结构箱体仍使用支撑压力回看窗口；以下微型箱体只服务于强趋势尾仓和快速利润保护，绝不参与初始SL/主TP。
input bool     短线单启用微型箱体保护 = true;
input int      短线单微型箱体回看M1 = 6;              // 5-10根M1，观察当前短线节奏
input double   短线单微型箱体最大高度ATR倍数 = 2.40;  // 超出此范围说明不是整理/回踩，不用作微结构
input double   短线单微型箱体SL缓冲价格 = 0.18;
input double   短线单灾难SL_ATR倍数 = 2.50;
input double   短线单灾难SL点差倍数 = 8.00;
input double   短线单绝对最大风险R = 2.00;
input int      短线单环境确认次数 = 2;
input int      短线单环境最短保持秒 = 45;

input group "12 常用｜趋势单托管"
//===================== 趋势单：消息面自适应托管 =====================//
input bool     趋势单启用消息面自适应 = true;    // 只增强已有持仓管理，不主动开仓
input double   趋势单消息单K实体ATR倍数 = 1.60;  // M1单根实体过大，视为消息/数据波动
input double   趋势单消息3根波动ATR倍数 = 3.20;  // 最近3根M1总波动过大，视为消息/数据波动
input int      趋势单消息点差阈值点数 = 120;     // 点差明显放大时也按消息面托管
input double   趋势单普通SL_ATR倍数 = 2.40;
input double   趋势单普通SL最小价格 = 16.00;
input double   趋势单普通SL最大价格 = 28.00;
input double   趋势单消息SL_ATR倍数 = 3.40;
input double   趋势单消息SL最小价格 = 24.00;
input double   趋势单消息SL最大价格 = 45.00;
input double   趋势单普通TP_ATR倍数 = 5.00;
input double   趋势单普通TP最小价格 = 30.00;
input double   趋势单普通TP最大价格 = 55.00;
input double   趋势单消息顺势TP_ATR倍数 = 7.50;
input double   趋势单消息顺势TP最小价格 = 45.00;
input double   趋势单消息顺势TP最大价格 = 90.00;
input double   趋势单逆势弱势TP_ATR倍数 = 3.20;
input double   趋势单逆势弱势TP最小价格 = 18.00;
input double   趋势单逆势弱势TP最大价格 = 35.00;
input double   趋势单普通保本ATR倍数 = 1.40;
input double   趋势单普通保本最小价格 = 8.00;
input double   趋势单消息顺势保本ATR倍数 = 2.20;
input double   趋势单消息顺势保本最小价格 = 14.00;
input double   趋势单震荡保本ATR倍数 = 1.00;
input double   趋势单震荡保本最小价格 = 6.00;
input double   趋势单保本锁定普通价格 = 0.50;
input double   趋势单保本锁定消息价格 = 1.20;
input ENUM_TIMEFRAMES 趋势主周期 = PERIOD_H1;       // 长期方向单核心判断周期
input ENUM_TIMEFRAMES 趋势过滤周期 = PERIOD_H4;     // 高周期大方向过滤
input ENUM_TIMEFRAMES 结构追踪周期1 = PERIOD_M30;   // 结构追踪主参考之一
input ENUM_TIMEFRAMES 结构追踪周期2 = PERIOD_H1;    // 结构追踪主参考之二
input bool     趋势单启用固定TP = false;            // 长拿模式默认不设置固定TP，趋势没坏就继续拿
input bool     趋势单启用最长持仓 = false;          // 长拿模式默认不按时间强制收紧
input double   趋势单保本触发R = 1.5;
input double   趋势单保本锁定R = 0.10;
input double   趋势单移动止损启动R = 1.5;
input double   趋势单强保护启动R = 2.0;
input bool     趋势单分批止盈启用 = false;          // 默认不分批，完整仓位交给结构和吊灯止损
input double   趋势单结构SL_ATR缓冲 = 0.30;
input double   趋势单ATR吊灯系数_普通 = 3.0;
input double   趋势单ATR吊灯系数_强趋势 = 3.5;
input double   趋势单ATR吊灯系数_趋势减弱 = 2.3;

input group "13 常用｜消息对冲"
//===================== 消息对冲托管 =====================//
// 选择“消息对冲”模板只会武装下一组新成交的对冲单；
// 只识别当前品种、受管范围内、且在真实成交时已冻结为“消息对冲”的一多一空。
// 切换模板绝不能接管、修改或平掉任何既有仓位。
input int      消息对冲配对等待秒 = 45;             // 单边先成交后，等待另一边的最长时间
input bool     启用消息双Stop真实挂单 = false;     // 默认关闭；仅冻结箱体后由面板明确部署
input long     消息双Stop挂单Magic = 910406;
input double   消息双Stop固定手数 = 0.01;
input int      消息双Stop有效秒数 = 120;
input int      消息对冲最大开仓时间差秒 = 90;
input bool     消息对冲配对失败自动平仓 = true;     // 等不到另一边时平掉孤立仓，避免裸奔
input bool     消息对冲无效配对自动全平 = true;     // 兼容旧参数保留；待命期异常组合固定为仅告警，绝不自动平仓
input bool     消息对冲配对后清除TP = true;         // 配对后由组合逻辑退出，不保留单边旧TP
input double   消息对冲手数容差 = 0.001;
input int      消息对冲允许滑点点数 = 180;
input int      消息对冲最大拆锁点差点数 = 250;      // deprecated：仅保留旧.set兼容，不再参与主要拆锁逻辑
input double   消息对冲最大拆锁点差倍数 = 6.00;    // 动态限制=冻结前正常点差×该倍数
input double   消息对冲绝对最大拆锁点差价格 = 2.50; // 0=不设绝对上限
input 消息高点差超时处理模式 消息对冲高点差超时处理 = 高点差超时处理_整组退出;
input double   消息对冲单边止损ATR倍数 = 3.00;
input double   消息对冲单边止损最小价格 = 10.00;
input double   消息对冲单边止损最大价格 = 30.00;
input double   消息对冲每001手组合最大亏损金额 = 25.00;
input int      消息对冲箱体回看M1根数 = 15;
input int      消息对冲箱体最低触碰次数 = 2;
input int      消息对冲箱体最低中轴穿越次数 = 2;
input double   消息对冲箱体最低收盘占比 = 0.70;
input double   消息对冲箱体最小宽度ATR倍数 = 1.50;
input double   消息对冲箱体最大宽度ATR倍数 = 8.00;
input double   消息对冲箱体聚类ATR倍数 = 0.20;
input double   消息对冲箱体聚类点差倍数 = 2.00;
input double   消息对冲箱体最小聚类价格距离 = 0.10;
input int      消息对冲正常点差统计秒数 = 60;
input double   消息对冲初始缓冲点差倍数 = 2.50;
input double   消息对冲初始缓冲ATR倍数 = 0.15;
input double   消息对冲初始缓冲箱体比例 = 0.08;
input double   消息对冲初始缓冲最小价格 = 0.0;
input double   消息对冲初始缓冲最大价格 = 0.0;
input double   消息对冲突破缓冲点差倍数 = 2.00;
input double   消息对冲突破缓冲ATR倍数 = 0.10;
input double   消息对冲突破缓冲箱体比例 = 0.05;
input double   消息对冲失败缓冲点差倍数 = 2.00;
input double   消息对冲失败缓冲ATR倍数 = 0.10;
input double   消息对冲失败缓冲箱体比例 = 0.05;
input double   消息对冲突破ATR倍数 = 1.00;          // 旧参数兼容：冻结箱体模式不再参与突破门槛
input double   消息对冲突破最小价格 = 2.50;         // 旧参数兼容：冻结箱体模式不再参与突破门槛
input double   消息对冲突破点差倍数 = 4.00;         // 旧参数兼容：冻结箱体模式不再参与突破门槛
input double   消息对冲突破区间缓冲ATR倍数 = 0.15; // 旧参数兼容：不与BreakoutBuffer叠加
input int      消息对冲突破确认Tick数 = 3;
input int      消息对冲突破确认毫秒 = 350;
input int      消息对冲最大拆锁等待毫秒 = 1500;
input int      消息对冲开放后有效秒数 = 15;
input int      消息对冲最晚拆锁秒数 = 12;
input double   消息对冲最晚拆锁箱体倍数 = 1.50;
input double   消息对冲最晚拆锁ATR倍数 = 3.00;
input double   消息对冲预期消息波幅价格 = 50.0;
input double   消息对冲最大已运行波幅比例 = 0.45;
input double   消息对冲实际成交后最小剩余盈亏比 = 1.00;
input double   消息对冲灾难缓冲初始缓冲倍数 = 2.00;
input double   消息对冲灾难缓冲ATR倍数 = 0.80;
input double   消息对冲灾难缓冲箱体比例 = 0.35;
input double   消息对冲灾难缓冲点差倍数 = 6.00;
input int      消息对冲假突破观察秒 = 180;
input double   消息对冲假突破回区比例 = 0.35;       // 回到消息前区间内部该比例，视为深度假突破
input int      消息对冲假突破确认Tick数 = 4;
input int      消息对冲假突破确认毫秒 = 500;
input double   消息对冲每001手预估额外成本金额 = 2.00; // 双边手续费、滑点的保守补偿
input double   消息对冲每001手组合保本启动金额 = 6.00;
input double   消息对冲每001手组合锁定金额 = 1.00;
input bool     消息对冲启用两段分批 = true;
input double   消息对冲第1段每001手组合盈利 = 0.00; // 可选固定金额下限；0=只按R触发
input double   消息对冲第2段每001手组合盈利 = 0.00; // 可选固定金额下限；0=只按R触发
input bool     消息对冲启用组合回撤退出 = true;
input double   消息对冲回撤启动每001手组合盈利 = 18.00; // R未Ready时的实际金额峰值回撤启动线
input double   消息对冲最大组合回撤比例 = 0.50;        // R未Ready时使用；R Ready后按阶段比例
input double   消息对冲微型回踩最大比例 = 0.45;
input int      消息对冲第一波阶段秒数 = 15;
input int      消息对冲延续阶段秒数 = 120;
input int      消息对冲组合最长持仓秒数 = 240;
input double   消息对冲第一波最大回撤比例 = 0.45;
input double   消息对冲延续阶段最大回撤比例 = 0.30;
input double   消息对冲后期最大回撤比例 = 0.20;
input int      消息对冲第一波无延续退出秒 = 6;
input int      消息对冲后续无延续退出秒 = 15;
input double   消息对冲第1段盈利R = 0.80;
input double   消息对冲第1段平仓比例 = 0.50;
input double   消息对冲第2段盈利R = 1.50;
input double   消息对冲第2段平仓初始手数比例 = 0.20;
input int      消息对冲第一段最小间隔秒 = 2;
input int      消息对冲第二段最小间隔秒 = 5;
input double   消息对冲每001手最小组合风险金额 = 2.00;

input group "14 常用｜面板与显示"
//===================== 显示 =====================//
input bool     显示简洁面板          = true;
input bool     使用新版Canvas面板    = true;       // true=固定布局单Canvas；false=完整保留v1.55对象式面板
input 面板显示模式 面板默认显示模式   = 面板完整;   // 完整=全部信息；迷你=只看关键交易信息；隐藏=只留展开按钮
input int      面板刷新秒数          = 1;          // 面板对象刷新限频，避免高频tick反复改对象导致卡顿
input int      面板字体大小          = 13;
input int      迷你面板字体大小      = 12;
input string   面板字体              = "Microsoft YaHei";
input int      面板左边距            = 0;           // 默认贴左显示，可拖动调整
input int      面板上边距            = 24;
input int      面板宽度              = 500;
input int      迷你面板宽度          = 390;
input int      面板自动缩回等待秒      = 60;          // 只有出现更长文字时才撑宽；撑宽后至少保持该秒数，避免随tick数字抖动
input bool     允许鼠标拖动面板      = true;       // 鼠标按住面板标题/黑色空白处可拖动，避免挡住快捷下单
input int      面板拖动标题栏高度    = 34;         // 鼠标在面板顶部该高度内按住可拖动
input int      面板行距              = 22;
input int      北京UTC偏移小时       = 8;
input bool     统计页仅统计受管Magic = false;     // false=当前品种全部Magic，true=按受管Magic统计
input double   持仓页浮亏预警金额    = 20.0;      // 仅面板提示：单笔浮亏达到该金额标记为风险
input double   持仓页低空间风险比    = 0.80;      // 仅面板提示：目标空间/SL风险低于该值提示空间不足
input int      今日纪律交易次数提醒  = 10;        // 仅面板提示：当天平仓成交过多时提醒降频

input group "15 进阶｜支撑压力识别与显示"
//===================== 图表支撑压力 =====================//
input bool            显示支撑压力线          = false;       // 默认不在图表回显支撑压力线，避免遮挡K线；面板和手机标记仍然保留
input ENUM_TIMEFRAMES 支撑压力周期            = PERIOD_M1;  // 保留兼容：关闭多周期时使用
input int             支撑压力回看K线数        = 120;        // M1回看K线数，默认约2小时，适合XAUUSD短线执行
input int             支撑压力摆点强度          = 4;          // M1摆点强度
input int             每侧最多显示点位数        = 2;          // 建议1-2，太多容易眼花
input double          支撑压力合并距离价格      = 1.0;        // 相近价格合并为同一支撑/压力区；会结合ATR动态放宽
input bool            支撑压力合并使用ATR       = true;       // true=按当前波动自动放宽合并区间
input double          支撑压力合并ATR倍数       = 0.25;       // 合并距离=max(固定距离, M1 ATR*倍数)
input bool            支撑压力使用高低点密集区   = true;       // true=扫描每根K线高低点形成的反复触碰区，而不只看单个摆点
input int             支撑压力刷新秒数          = 3;          // 避免每秒重算导致卡顿
input bool            面板显示支撑压力          = true;
input bool            支撑压力使用多周期结构    = true;       // true=M1/M5/M15综合；false=只用上面的单周期
input bool            支撑压力启用M1            = true;
input bool            支撑压力启用M5            = true;
input bool            支撑压力启用M15           = true;
input int             支撑压力M5回看K线数       = 48;         // 默认约4小时，过滤M1噪声但不过度引用旧结构
input int             支撑压力M15回看K线数      = 24;         // 默认约6小时，只保留近场高一级结构
input int             支撑压力M5摆点强度        = 3;
input int             支撑压力M15摆点强度       = 2;
input int             支撑压力M1权重            = 1;          // M1结构权重较轻，避免短噪声过强
input int             支撑压力M5权重            = 3;          // M5结构权重更高
input int             支撑压力M15权重           = 5;          // M15结构权重最高
input int             支撑压力近端加权K线数      = 24;         // EMA式近端加权周期，最近结构更重要但不压过强结构
input double          支撑压力近端最大权重倍数   = 1.8;        // 温和上限，避免最近几根K线过度主导R/S
input bool            支撑压力启用触碰强化      = true;       // 高低点多次触碰同一区域时强化该点位
input int             支撑压力最低有效强度      = 6;          // 优先显示反复触碰/多周期共振强区；不足时自动回退弱点位
input bool            支撑压力强度优先排序      = true;       // true=强结构区优先，不再只取离现价最近的小噪声点
input bool            支撑压力启用最终增强版    = true;       // true=多周期关键区域识别：摆点、时段位、密集区、扫单、趋势综合评分
input bool            支撑压力启用有效反应过滤  = true;
input double          支撑压力最小有效反应价格  = 2.00;
input double          支撑压力强反应价格        = 4.00;
input double          支撑压力关键反应价格      = 6.00;
input int             支撑压力反应观察K线数_M1  = 10;
input int             支撑压力反应观察K线数_M5  = 6;
input int             支撑压力反应观察K线数_M15 = 4;
input bool            支撑压力启用时段关键位    = true;
input int             亚洲盘开始小时            = 8;
input int             亚洲盘结束小时            = 15;
input int             伦敦盘开始小时            = 16;
input int             伦敦盘开盘区间分钟        = 60;
input int             纽约盘开始小时            = 21;
input int             纽约盘开盘区间分钟        = 60;
input bool            时段参数使用服务器时间    = true;
input bool            支撑压力启用整数位加权    = true;       // 靠近1/5/10美金整数位时强化，贴近人工看盘关键价
input double          支撑压力整数位容差价格    = 0.30;       // 价格距整数位小于该距离时加权
input bool            支撑压力启用大整数分层权重 = true;
input bool            支撑压力启用近60分钟反应加权 = true;     // 近端刚出现反应的摆点额外加权
input int             支撑压力近反应分钟        = 60;         // 近端反应窗口，默认60分钟
input bool            支撑压力启用扫单失败识别  = true;
input double          扫单最小刺破价格          = 0.30;
input double          扫单最大刺破价格          = 3.00;
input int             扫单确认K线数             = 3;
input double          扫单失败加分              = 10.0;
input bool            支撑压力启用突破回踩确认  = true;
input int             突破回踩观察K线数         = 20;
input double          突破回踩加分              = 5.0;
input bool            支撑压力启用价格密集区    = true;
input int             价格密集区回看M1根数      = 180;
input double          价格密集区分桶大小        = 0.50;
input int             价格密集区最小覆盖次数    = 12;
input int             价格密集区最多候选数      = 5;
input double          价格密集区基础加分        = 4.0;
input bool            支撑压力启用趋势环境过滤  = true;
input int             趋势EMA快线周期           = 20;
input int             趋势EMA慢线周期           = 50;
input int             趋势ADX周期               = 14;
input double          趋势ADX阈值               = 22.0;
input double          顺势点位加权倍数          = 1.20;
input double          逆势点位降权倍数          = 0.75;
input bool            支撑压力启用距离惩罚      = true;
input double          支撑压力距离惩罚强度      = 1.0;
input bool            支撑压力启用过期惩罚      = true;
input int             支撑压力过期分钟          = 240;
input double          支撑压力过期降权倍数      = 0.70;
input int             支撑压力最多显示数量      = 2;
input bool            支撑压力显示负号支撑距离  = true;
input double          支撑压力可交易线最低分    = 12.0;
input double          支撑压力A级线最低分       = 20.0;
input double          支撑压力B级线最低分       = 14.0;
input double          支撑压力接近距离价格      = 1.00;
input bool            支撑压力启用到位提示      = true;
input bool            支撑压力启用高波动保护    = true;
input double          高波动M1实体ATR倍数       = 2.0;
input double          高波动3根M1总波动ATR倍数  = 3.0;
input bool            支撑压力无交易线时允许显示弱观察线 = true;
input double          支撑压力最大交易显示距离价格 = 15.0;

enum MobileMarkerSourceMode
{
   手机标记来源_自动结构 = 0,
   手机标记来源_老师文本 = 1,
   手机标记来源_老师文本无效 = 2
};

input group "16 常用｜手机提示挂单"
//===================== 手机端标记挂单 =====================//
// 说明：手机端MT5不能显示EA画线；本功能用固定极远价位挂单的TP/SL线作为手机端点位标记。
// 压力位使用 Buy Limit 的 TP 线；支撑位使用 Sell Stop 的 SL 线，便于手机端区分。
// 注意：这是真实挂单；建议只在对冲账户、确认券商规则允许时使用。
input bool            启用手机标记挂单          = true;        // 默认开启：用极远挂单的TP/SL线同步支撑压力到手机端
input double          手机标记挂单手数          = 0.01;
input double          手机标记挂单固定价格      = 100.0;       // 固定挂单价，例如XAUUSD=100.00
input int             手机标记每侧点位数        = 2;           // 默认同步R1/R2和S1/S2；建议1-2，太多手机端也会乱
input int             手机标记刷新秒数          = 5;           // 快速同步R/S变化，突破原标记点后尽快换到新点位
input int             手机标记有效分钟          = 0;           // 0=不设置服务器到期时间；旧点位由EA刷新/突破检测主动撤换
input bool            任意交易时撤手机标记       = true;        // 任意模板：当前品种出现真实持仓或真实挂单，就撤掉全部R/S标记挂单
input bool            短线单持仓时撤手机标记      = true;        // 兼容旧参数：全局开关关闭时，短线模板仍可按原行为撤标记
input bool            手机标记突破立即刷新      = true;        // 价格突破当前R/S标记线后，立即重算点位并撤旧挂新
input double          手机标记突破确认缓冲      = 0.0;         // 额外固定确认缓冲；会与下方“大突破”阈值共同取最大值
input bool            手机标记突破需M1收线确认   = true;        // true=只有M1收线确认大突破后，才撤旧挂新
input double          手机标记大突破最小缓冲      = 0.30;        // XAUUSD短线默认：小刺破不算突破，至少收线越过该距离
input double          手机标记大突破ATR倍数       = 0.20;        // 大突破阈值=max(确认缓冲, 最小缓冲, M1 ATR*倍数)
input double          手机标记危险距离          = 20.0;        // 当前价距标记挂单价小于该距离时先撤掉，避免误触发
input long            手机标记挂单Magic         = 910405;

string 配置模板名称()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return "短线单";
   if(当前参数配置模板 == 配置_黄金稳健托管) return "长线单";
   if(当前参数配置模板 == 配置_黄金支压止盈) return "手动单";
   if(当前参数配置模板 == 配置_黄金消息对冲) return "消息对冲";
   return "自定义";
}

string 配置模板面板说明()
{
   if(当前参数配置模板 == 配置_黄金超短快保)
      return "短线单: 风险R+波动TP | 延迟保本 | 自适应分批";
   if(当前参数配置模板 == 配置_黄金稳健托管)
      return "长线单: H1/H4方向 | 无固定TP | 结构退出";
   if(当前参数配置模板 == 配置_黄金支压止盈)
      return "手动单: 只看R/S提示 | 不设SL/TP | 不保本/追踪/分批";
   if(当前参数配置模板 == 配置_黄金消息对冲)
      return "消息对冲: 等手数双向 | 突破拆锁 | 组合回本/保护";
   return "自定义: 完全使用输入参数 | 请自行检查SL/TP/保本/追踪";
}

bool 当前模板使用黄金稳健止损()
{
   return (当前参数配置模板 == 配置_黄金稳健托管);
}

bool 当前模板使用消息对冲()
{
   return (当前参数配置模板 == 配置_黄金消息对冲);
}

bool 当前模板使用支压分段止盈()
{
   return false; // 支压手控版不再执行R1/S1平半或R2/S2全平
}

距离模式 生效_初始SL模式()
{
   if(当前参数配置模板 == 配置_黄金支压止盈) return 距离关闭; // 支压手控版不自动设置初始SL
   return 初始SL模式;
}
距离模式 生效_初始TP模式()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 固定价格距离; // 短线单默认给5-10美金区间内的固定TP，避免首收太慢
   if(当前参数配置模板 == 配置_黄金支压止盈) return 距离关闭; // 支压手控版不自动设置初始TP
   if(当前参数配置模板 == 配置_黄金稳健托管) return 趋势单启用固定TP ? 固定价格距离 : 距离关闭; // 长拿趋势单默认不设置固定TP
   return 初始TP模式;
}
double 生效_固定SL价格距离()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 5.5;
   if(当前模板使用黄金稳健止损()) return 18.0;
   return 固定SL价格距离;
}
double 生效_固定TP价格距离()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 6.0;
   if(当前模板使用黄金稳健止损()) return 35.0;
   return 固定TP价格距离;
}
int 生效_ATR周期()
{
   return ATR周期;
}
double 生效_ATR止损倍数()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 1.1;
   if(当前模板使用黄金稳健止损()) return 2.4;
   return ATR止损倍数;
}
double 生效_ATR止盈倍数()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 1.4;
   if(当前模板使用黄金稳健止损()) return 5.00;
   return ATR止盈倍数;
}
bool 生效_启用保本()
{
   if(当前参数配置模板 == 配置_黄金支压止盈) return false; // 支压手控版不自动保本
   return 启用保本;
}
double 生效_保本触发价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 1.20;
   if(当前模板使用黄金稳健止损()) return 8.00;
   return 保本触发价格;
}
double 生效_保本锁定价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.12;
   if(当前模板使用黄金稳健止损()) return 0.50;
   return 保本锁定价格;
}
bool 生效_启用移动止损()
{
   if(当前参数配置模板 == 配置_黄金支压止盈) return false; // 支压手控版不自动移动止损
   return 启用移动止损;
}
double 生效_移动止损启动价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 1.50;
   if(当前模板使用黄金稳健止损()) return 12.00;
   return 移动止损启动价格;
}
double 生效_移动止损距离价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.95;
   if(当前模板使用黄金稳健止损()) return 7.50;
   return 移动止损距离价格;
}
int 生效_移动止损最小推进点数()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 12;
   if(当前模板使用黄金稳健止损()) return 60;
   return 移动止损最小推进点数;
}
追踪SL模式 生效_跟踪SL模式()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 追踪M1前柱结构;
   if(当前模板使用黄金稳健止损()) return 追踪结构自适应;
   return 跟踪SL模式;
}
double 生效_动态追踪启动ATR倍数()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.90;
   if(当前模板使用黄金稳健止损()) return 3.00;
   return 动态追踪启动ATR倍数;
}
double 生效_动态追踪距离ATR倍数()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.75;
   if(当前模板使用黄金稳健止损()) return 2.60;
   return 动态追踪距离ATR倍数;
}
double 生效_动态追踪最小启动价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 1.50;
   if(当前模板使用黄金稳健止损()) return 8.00;
   return 动态追踪最小启动价格;
}
double 生效_动态追踪最大启动价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 4.80;
   if(当前模板使用黄金稳健止损()) return 20.00;
   return 动态追踪最大启动价格;
}
double 生效_动态追踪最小距离价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.85;
   if(当前模板使用黄金稳健止损()) return 5.00;
   return 动态追踪最小距离价格;
}
double 生效_动态追踪最大距离价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 2.60;
   if(当前模板使用黄金稳健止损()) return 13.00;
   return 动态追踪最大距离价格;
}
double 生效_动态追踪最小推进ATR倍数()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.18;
   if(当前模板使用黄金稳健止损()) return 0.65;
   return 动态追踪最小推进ATR倍数;
}
double 生效_结构SL缓冲价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.18;
   if(当前模板使用黄金稳健止损()) return 1.20;
   return 结构SL缓冲价格;
}
int 生效_M1结构追踪K线数()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 3;
   if(当前模板使用黄金稳健止损()) return 12;
   return M1结构追踪K线数;
}
double 生效_M1结构SL缓冲价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.45;
   if(当前模板使用黄金稳健止损()) return 0.90;
   return M1结构SL缓冲价格;
}
double 生效_M1结构最小浮盈启动()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 4.00; // 至少走出一段利润后才允许M1结构接管
   if(当前模板使用黄金稳健止损()) return 10.00;
   return M1结构最小浮盈启动;
}
double 生效_M1结构追踪启动ATR倍数()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 1.60;
   if(当前模板使用黄金稳健止损()) return 3.20;
   return M1结构追踪启动ATR倍数;
}
double 生效_M1结构最小SL距离()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 1.80;
   if(当前模板使用黄金稳健止损()) return 3.00;
   return M1结构最小SL距离;
}
double 生效_M1结构最小SL距离ATR倍数()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 1.10;
   if(当前模板使用黄金稳健止损()) return 1.60;
   return M1结构最小SL距离ATR倍数;
}
bool 生效_M1结构只在新K线更新(){ return M1结构只在新K线更新; }
bool 生效_启用阶梯式保护()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return false;
   if(当前模板使用黄金稳健止损()) return false; // 长拿趋势单改用R阶梯+结构/吊灯止损
   return 启用阶梯式保护;
}
bool 生效_阶梯保护时暂停贴身追踪(){ return 阶梯保护时暂停贴身追踪; }
double 生效_阶梯1触发价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 2.20;
   if(当前模板使用黄金稳健止损()) return 10.00;
   return 阶梯1触发价格;
}
double 生效_阶梯1锁定价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.15;
   if(当前模板使用黄金稳健止损()) return 0.50;
   return 阶梯1锁定价格;
}
double 生效_阶梯2触发价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 3.50;
   if(当前模板使用黄金稳健止损()) return 18.00;
   return 阶梯2触发价格;
}
double 生效_阶梯2锁定价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 1.00;
   if(当前模板使用黄金稳健止损()) return 4.00;
   return 阶梯2锁定价格;
}
double 生效_阶梯3触发价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 5.00;
   if(当前模板使用黄金稳健止损()) return 28.00;
   return 阶梯3触发价格;
}
double 生效_阶梯3锁定价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 2.40;
   if(当前模板使用黄金稳健止损()) return 10.00;
   return 阶梯3锁定价格;
}
double 生效_阶梯4触发价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 7.00;
   if(当前模板使用黄金稳健止损()) return 40.00;
   return 阶梯4触发价格;
}
double 生效_阶梯4锁定价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 4.20;
   if(当前模板使用黄金稳健止损()) return 20.00;
   return 阶梯4锁定价格;
}
bool 生效_启用分批止盈()
{
   if(当前参数配置模板 == 配置_黄金支压止盈) return false; // 支压手控版不自动分批止盈
   if(当前参数配置模板 == 配置_黄金稳健托管) return false; // 大趋势托管不主动分批，主要靠M5/M15结构追踪和回撤保护吃完整段
   return 启用分批止盈;
}
double 生效_分批止盈比例()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.50;
   if(当前参数配置模板 == 配置_黄金支压止盈) return 0.50;
   if(当前参数配置模板 == 配置_黄金稳健托管) return 0.15;
   return 分批止盈比例;
}
double 生效_分批止盈接近点位距离()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.45;
   if(当前参数配置模板 == 配置_黄金支压止盈) return 0.10;
   if(当前参数配置模板 == 配置_黄金稳健托管) return 1.20;
   return 分批止盈接近点位距离;
}
double 生效_分批止盈最小浮盈价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 1.30;
   if(当前参数配置模板 == 配置_黄金支压止盈) return 0.00;
   if(当前参数配置模板 == 配置_黄金稳健托管) return 18.00;
   return 分批止盈最小浮盈价格;
}
double 生效_分批止盈目标最小空间价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 1.80;
   return 分批止盈目标最小空间价格;
}
double 生效_分批止盈后保本锁定()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.25;
   if(当前模板使用黄金稳健止损()) return 0.50;
   return 分批止盈后保本锁定;
}
bool 生效_分批后立即保护剩余仓位()
{
   if(当前参数配置模板 == 配置_黄金支压止盈) return false; // 支压手控版不自动保护剩余仓位
   return 分批后立即保护剩余仓位;
}
bool 生效_启用浮盈回撤保护()
{
   if(当前参数配置模板 == 配置_黄金支压止盈) return false; // 支压手控版不自动回撤保护
   return 启用浮盈回撤保护;
}
double 生效_回撤保护启动价格()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 4.20;
   if(当前模板使用黄金稳健止损()) return 18.00;
   return 回撤保护启动价格;
}
double 生效_最大浮盈回撤比例()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.38;
   if(当前模板使用黄金稳健止损()) return 0.50;
   return 最大浮盈回撤比例;
}
double 生效_回撤后锁定利润比例()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0.55;
   if(当前模板使用黄金稳健止损()) return 0.45;
   return 回撤后锁定利润比例;
}
int 生效_最大持仓分钟数()
{
   if(当前参数配置模板 == 配置_黄金超短快保) return 0; // 短线单不再因固定30分钟机械推保本，由R/波动/结构统一接管
   if(当前参数配置模板 == 配置_黄金支压止盈) return 0;
   if(当前模板使用黄金稳健止损()) return 趋势单启用最长持仓 ? 2880 : 0;
   return 最大持仓分钟数;
}
bool 生效_超时后收紧到保本()
{
   if(当前参数配置模板 == 配置_黄金支压止盈) return false; // 支压手控版不自动超时收紧
   return 超时后收紧到保本;
}


// 黄金稳健托管用于长期方向单时，核心以H1/H4方向和M30/H1结构保护为主，M1/M5只作为短线噪声参考。
bool 生效_支撑压力使用多周期结构()
{
   if(当前模板使用黄金稳健止损()) return true;
   return 支撑压力使用多周期结构;
}
bool 生效_支撑压力启用M1()
{
   if(当前模板使用黄金稳健止损()) return false;
   return 支撑压力启用M1;
}
bool 生效_支撑压力启用M5()
{
   if(当前模板使用黄金稳健止损()) return true;
   return 支撑压力启用M5;
}
bool 生效_支撑压力启用M15()
{
   if(当前模板使用黄金稳健止损()) return true;
   return 支撑压力启用M15;
}
int 生效_支撑压力M5回看K线数()
{
   if(当前模板使用黄金稳健止损()) return 120; // 约10小时M5，足够覆盖1-2小时趋势的上一级结构
   return 支撑压力M5回看K线数;
}
int 生效_支撑压力M15回看K线数()
{
   if(当前模板使用黄金稳健止损()) return 64; // 约16小时M15，优先识别日内主趋势结构区
   return 支撑压力M15回看K线数;
}
int 生效_支撑压力M5摆点强度()
{
   if(当前模板使用黄金稳健止损()) return 4;
   return 支撑压力M5摆点强度;
}
int 生效_支撑压力M15摆点强度()
{
   if(当前模板使用黄金稳健止损()) return 3;
   return 支撑压力M15摆点强度;
}
int 生效_支撑压力M1权重()
{
   if(当前模板使用黄金稳健止损()) return 0;
   return 支撑压力M1权重;
}
int 生效_支撑压力M5权重()
{
   if(当前模板使用黄金稳健止损()) return 4;
   return 支撑压力M5权重;
}
int 生效_支撑压力M15权重()
{
   if(当前模板使用黄金稳健止损()) return 8;
   return 支撑压力M15权重;
}
int 生效_支撑压力近端加权K线数()
{
   if(当前模板使用黄金稳健止损()) return 48;
   return 支撑压力近端加权K线数;
}
double 生效_支撑压力近端最大权重倍数()
{
   if(当前模板使用黄金稳健止损()) return 1.35; // 防止最近几根M5小结构压过M15主结构
   return 支撑压力近端最大权重倍数;
}
double 生效_支撑压力合并距离价格()
{
   if(当前模板使用黄金稳健止损()) return 1.8;
   return 支撑压力合并距离价格;
}
double 生效_支撑压力合并ATR倍数()
{
   if(当前模板使用黄金稳健止损()) return 0.45;
   return 支撑压力合并ATR倍数;
}
int 生效_支撑压力最低有效强度()
{
   if(当前模板使用黄金稳健止损()) return 10;
   return 支撑压力最低有效强度;
}
double 生效_TP贴近点位缓冲价格()
{
   if(当前模板使用黄金稳健止损()) return 1.20;
   return TP贴近点位缓冲价格;
}
double 生效_持仓目标空间不足距离()
{
   if(当前模板使用黄金稳健止损()) return 3.00;
   return 持仓目标空间不足距离;
}

int 生效_每侧最多显示点位数()
{
   if(当前参数配置模板 == 配置_黄金支压止盈)
      return MathMax(每侧最多显示点位数, 2); // 支压手控版仍保留R1/R2或S1/S2两级线用于观察
   return 每侧最多显示点位数;
}

#define 初始SL模式 生效_初始SL模式()
#define 初始TP模式 生效_初始TP模式()
#define 固定SL价格距离 生效_固定SL价格距离()
#define 固定TP价格距离 生效_固定TP价格距离()
#define ATR周期 生效_ATR周期()
#define ATR止损倍数 生效_ATR止损倍数()
#define ATR止盈倍数 生效_ATR止盈倍数()
#define 启用保本 生效_启用保本()
#define 保本触发价格 生效_保本触发价格()
#define 保本锁定价格 生效_保本锁定价格()
#define 启用移动止损 生效_启用移动止损()
#define 移动止损启动价格 生效_移动止损启动价格()
#define 移动止损距离价格 生效_移动止损距离价格()
#define 移动止损最小推进点数 生效_移动止损最小推进点数()
#define 跟踪SL模式 生效_跟踪SL模式()
#define 动态追踪启动ATR倍数 生效_动态追踪启动ATR倍数()
#define 动态追踪距离ATR倍数 生效_动态追踪距离ATR倍数()
#define 动态追踪最小启动价格 生效_动态追踪最小启动价格()
#define 动态追踪最大启动价格 生效_动态追踪最大启动价格()
#define 动态追踪最小距离价格 生效_动态追踪最小距离价格()
#define 动态追踪最大距离价格 生效_动态追踪最大距离价格()
#define 动态追踪最小推进ATR倍数 生效_动态追踪最小推进ATR倍数()
#define 结构SL缓冲价格 生效_结构SL缓冲价格()
#define M1结构追踪K线数 生效_M1结构追踪K线数()
#define M1结构SL缓冲价格 生效_M1结构SL缓冲价格()
#define M1结构最小浮盈启动 生效_M1结构最小浮盈启动()
#define M1结构追踪启动ATR倍数 生效_M1结构追踪启动ATR倍数()
#define M1结构最小SL距离 生效_M1结构最小SL距离()
#define M1结构最小SL距离ATR倍数 生效_M1结构最小SL距离ATR倍数()
#define M1结构只在新K线更新 生效_M1结构只在新K线更新()
#define 启用阶梯式保护 生效_启用阶梯式保护()
#define 阶梯保护时暂停贴身追踪 生效_阶梯保护时暂停贴身追踪()
#define 阶梯1触发价格 生效_阶梯1触发价格()
#define 阶梯1锁定价格 生效_阶梯1锁定价格()
#define 阶梯2触发价格 生效_阶梯2触发价格()
#define 阶梯2锁定价格 生效_阶梯2锁定价格()
#define 阶梯3触发价格 生效_阶梯3触发价格()
#define 阶梯3锁定价格 生效_阶梯3锁定价格()
#define 阶梯4触发价格 生效_阶梯4触发价格()
#define 阶梯4锁定价格 生效_阶梯4锁定价格()
#define 启用分批止盈 生效_启用分批止盈()
#define 分批止盈比例 生效_分批止盈比例()
#define 分批止盈接近点位距离 生效_分批止盈接近点位距离()
#define 分批止盈最小浮盈价格 生效_分批止盈最小浮盈价格()
#define 分批止盈目标最小空间价格 生效_分批止盈目标最小空间价格()
#define 分批止盈后保本锁定 生效_分批止盈后保本锁定()
#define 分批后立即保护剩余仓位 生效_分批后立即保护剩余仓位()
#define 启用浮盈回撤保护 生效_启用浮盈回撤保护()
#define 回撤保护启动价格 生效_回撤保护启动价格()
#define 最大浮盈回撤比例 生效_最大浮盈回撤比例()
#define 回撤后锁定利润比例 生效_回撤后锁定利润比例()
#define 最大持仓分钟数 生效_最大持仓分钟数()
#define 超时后收紧到保本 生效_超时后收紧到保本()

#define 支撑压力使用多周期结构 生效_支撑压力使用多周期结构()
#define 支撑压力启用M1 生效_支撑压力启用M1()
#define 支撑压力启用M5 生效_支撑压力启用M5()
#define 支撑压力启用M15 生效_支撑压力启用M15()
#define 支撑压力M5回看K线数 生效_支撑压力M5回看K线数()
#define 支撑压力M15回看K线数 生效_支撑压力M15回看K线数()
#define 支撑压力M5摆点强度 生效_支撑压力M5摆点强度()
#define 支撑压力M15摆点强度 生效_支撑压力M15摆点强度()
#define 支撑压力M1权重 生效_支撑压力M1权重()
#define 支撑压力M5权重 生效_支撑压力M5权重()
#define 支撑压力M15权重 生效_支撑压力M15权重()
#define 支撑压力近端加权K线数 生效_支撑压力近端加权K线数()
#define 支撑压力近端最大权重倍数 生效_支撑压力近端最大权重倍数()
#define 支撑压力合并距离价格 生效_支撑压力合并距离价格()
#define 支撑压力合并ATR倍数 生效_支撑压力合并ATR倍数()
#define 支撑压力最低有效强度 生效_支撑压力最低有效强度()
#define TP贴近点位缓冲价格 生效_TP贴近点位缓冲价格()
#define 持仓目标空间不足距离 生效_持仓目标空间不足距离()
#define 每侧最多显示点位数 生效_每侧最多显示点位数()


string   lastStatus = "等待";
ulong    上次完整面板刷新毫秒 = 0;
string   上次面板状态文本 = "";
bool     手机标记禁用已清理 = false;

// M1结构追踪用已收K线高低点，同一根M1内无需对每个持仓重复CopyRates。
datetime 缓存M1结构BarTime = 0;
int      缓存M1结构K线数 = 0;
double   缓存M1结构Low = 0.0;
double   缓存M1结构High = 0.0;
bool     缓存M1结构有效 = false;

面板页面 当前面板页面 = 页面持仓;
面板显示模式 当前面板显示模式 = 面板完整;
面板信息密度 当前面板信息模式 = 面板信息_简单;
int 当前面板左边距 = 0;
int 当前面板上边距 = 0;
int 当前面板宽度 = 0;     // 当前绘制宽度：基础宽度 + 自动撑宽保持
int 当前面板高度 = 0;     // 当前绘制高度：用于整块面板拖动命中检测
int 面板基础宽度缓存 = 0;
int 面板保持宽度 = 0;
datetime 面板最近撑宽时间 = 0;
bool 面板正在拖动 = false;
int  面板拖动起始鼠标X = 0;
int  面板拖动起始鼠标Y = 0;
int  面板拖动起始面板X = 0;
int  面板拖动起始面板Y = 0;
int  上次图表宽度像素 = 0;
int  上次图表高度像素 = 0;
统计周期模式 当前统计周期 = 统计_日;
统计策略筛选 当前统计筛选 = 统计筛选_短线;
统计详情页面 当前统计详情 = 统计详情_总览;
int      当前复盘序号 = 0; // 复盘页按平仓时间倒序，0=最近一笔
int      统计日期偏移天数 = 0; // 0=北京时间今天，-1=昨天；允许查看未来无交易日期
int      统计周偏移周数 = 0;   // 0=本周，-1=上一周，1=下一周
int      统计月偏移月数 = 0;   // 0=本月，-1=上一月，1=下一月

// 统计页点击切换时如果每次都全量扫描历史，会明显卡顿；这里做一个短缓存。
bool       统计缓存有效 = false;
datetime   统计缓存时间 = 0;
int        缓存统计周期 = -1;
int        缓存日偏移 = 999999;
int        缓存周偏移 = 999999;
int        缓存月偏移 = 999999;
struct SRLevel
{
   double   price;
   double   zoneLow;
   double   zoneHigh;
   int      strength;
   double   tradeScore;
   int      qualityGrade;
   int      touches;
   int      tfMask;
   bool     isResistance;
   bool     isSupport;
   bool     tradable;
   bool     observeOnly;
   bool     boxBoundary;
   bool     brokenConfirmed;
   bool     retestConfirmed;
   bool     liquiditySweep;
   bool     sweepFailed;
   bool     effectiveReaction;
   double   maxReaction;
   bool     sessionLevel;
   bool     densityLevel;
   bool     integerConfluence;
   string   statusText;
   datetime lastTime;
};

const int SR_TF_M1       = 1;
const int SR_TF_M5       = 2;
const int SR_TF_M15      = 4;
const int SR_SRC_SESSION = 8;
const int SR_SRC_DENSITY = 16;

SRLevel 缓存压力位[];
SRLevel 缓存支撑位[];
datetime 上次支撑压力刷新时间 = 0;
// 同一图表可同时托管短线和趋势仓，结构缓存必须随冻结模板切换，不能共享最后一次面板模板的结果。
SRLevel 模板缓存压力位_0[], 模板缓存压力位_1[], 模板缓存压力位_2[], 模板缓存压力位_3[], 模板缓存压力位_4[];
SRLevel 模板缓存支撑位_0[], 模板缓存支撑位_1[], 模板缓存支撑位_2[], 模板缓存支撑位_3[], 模板缓存支撑位_4[];
datetime 模板结构缓存刷新时间[5];
int 当前载入结构缓存模板 = -1;
datetime 上次手机标记刷新时间 = 0;
string   手机标记状态 = "关闭";
bool     手机标记挂单面板开关 = true; // 仅控制 SMA_MARK_* 提示挂单；关闭时撤掉提示挂单，不影响真实持仓或普通挂单。
const int MAX_TEACHER_MARKER_LEVELS = 20;
string   缓存老师点位原文 = "";
double   缓存老师点位[];
bool     缓存老师点位有效 = false;
string   缓存老师点位错误 = "";
ulong    缓存老师点位签名 = 0;
int      缓存老师点位数量 = 0;
MobileMarkerSourceMode 手机标记来源模式 = 手机标记来源_自动结构;
bool     手机标记环境Dirty = true;
ulong    上次老师点位同步签名 = 0;
string   上次老师点位同步状态 = "";
uint     老师点位最近错误码 = 0;
string   老师点位最近错误 = "";

struct TeacherAutoEntryState
{
   bool     pending;
   int      pendingDirection;
   double   pendingLevel;
   double   pendingVolume;
   datetime pendingSignalBarTime;
   datetime pendingRequestTime;
   ulong    pendingOrder;
   ulong    pendingDeal;
   int      pendingMode; // 0=旧请求；1..4对应带信号时间的唯一comment
   bool     rearmRequired;
   int      lastDirection;
   double   lastLevel;
   datetime lastEntryTime;
};
TeacherAutoEntryState teacherAutoEntryState;
int teacherAutoInstanceFile = INVALID_HANDLE;
bool teacherAutoStateLoaded = false;
datetime teacherAutoPendingCheckTime = 0;
int teacherActiveATRHandle = INVALID_HANDLE;
int teacherActiveEMAHandle = INVALID_HANDLE;
bool teacherActiveHistoryDirty = true;
bool teacherActiveHistoryReady = false;
ulong teacherActiveLatestDeal = 0;
datetime teacherActiveHistoryTime = 0;
datetime teacherActiveLastStop = 0;
datetime teacherActiveContextDay = 0;
int teacherActiveBias = 0;
double teacherActiveDayHigh = 0.0, teacherActiveDayLow = 0.0;
double teacherActiveFiveHigh = 0.0, teacherActiveFiveLow = 0.0;

string TeacherAutoStateKey(string field)
{
   return StringFormat("S55.AUTO.%I64d.%s.%s", AccountInfoInteger(ACCOUNT_LOGIN), _Symbol, field);
}

double TeacherAutoStateRead(string field, double fallback=0.0)
{
   string key = TeacherAutoStateKey(field);
   return GlobalVariableCheck(key) ? GlobalVariableGet(key) : fallback;
}

void TeacherAutoStateWriteUlong(string field, const ulong value)
{
   GlobalVariableSet(TeacherAutoStateKey(field+"L"), (double)(uint)(value & 0xFFFFFFFF));
   GlobalVariableSet(TeacherAutoStateKey(field+"H"), (double)(uint)(value >> 32));
}

ulong TeacherAutoStateReadUlong(string field)
{
   ulong low = (ulong)MathRound(TeacherAutoStateRead(field+"L"));
   ulong high = (ulong)MathRound(TeacherAutoStateRead(field+"H"));
   return (high << 32) | (low & 0xFFFFFFFF);
}

void TeacherAutoClearPendingStateFields()
{
   teacherAutoEntryState.pending = false;
   teacherAutoEntryState.pendingDirection = 0;
   teacherAutoEntryState.pendingLevel = 0.0;
   teacherAutoEntryState.pendingVolume = 0.0;
   teacherAutoEntryState.pendingSignalBarTime = 0;
   teacherAutoEntryState.pendingRequestTime = 0;
   teacherAutoEntryState.pendingOrder = 0;
   teacherAutoEntryState.pendingDeal = 0;
   teacherAutoEntryState.pendingMode = 0;
}

void TeacherAutoStateSave()
{
   GlobalVariableSet(TeacherAutoStateKey("V"), 1.0);
   GlobalVariableSet(TeacherAutoStateKey("P"), teacherAutoEntryState.pending ? 1.0 : 0.0);
   GlobalVariableSet(TeacherAutoStateKey("PD"), teacherAutoEntryState.pendingDirection);
   GlobalVariableSet(TeacherAutoStateKey("PL"), teacherAutoEntryState.pendingLevel);
   GlobalVariableSet(TeacherAutoStateKey("PV"), teacherAutoEntryState.pendingVolume);
   GlobalVariableSet(TeacherAutoStateKey("PS"), (double)teacherAutoEntryState.pendingSignalBarTime);
   GlobalVariableSet(TeacherAutoStateKey("PR"), (double)teacherAutoEntryState.pendingRequestTime);
   TeacherAutoStateWriteUlong("PO", teacherAutoEntryState.pendingOrder);
   TeacherAutoStateWriteUlong("PE", teacherAutoEntryState.pendingDeal);
   GlobalVariableSet(TeacherAutoStateKey("PM"), teacherAutoEntryState.pendingMode);
   GlobalVariableSet(TeacherAutoStateKey("RR"), teacherAutoEntryState.rearmRequired ? 1.0 : 0.0);
   GlobalVariableSet(TeacherAutoStateKey("LD"), teacherAutoEntryState.lastDirection);
   GlobalVariableSet(TeacherAutoStateKey("LL"), teacherAutoEntryState.lastLevel);
   GlobalVariableSet(TeacherAutoStateKey("LT"), (double)teacherAutoEntryState.lastEntryTime);
}

void TeacherAutoStateLoad()
{
   ZeroMemory(teacherAutoEntryState);
   if((int)MathRound(TeacherAutoStateRead("V")) != 1) return;

   teacherAutoEntryState.pending = TeacherAutoStateRead("P") > 0.5;
   teacherAutoEntryState.pendingDirection = (int)MathRound(TeacherAutoStateRead("PD"));
   teacherAutoEntryState.pendingLevel = TeacherAutoStateRead("PL");
   teacherAutoEntryState.pendingVolume = TeacherAutoStateRead("PV");
   teacherAutoEntryState.pendingSignalBarTime = (datetime)MathRound(TeacherAutoStateRead("PS"));
   teacherAutoEntryState.pendingRequestTime = (datetime)MathRound(TeacherAutoStateRead("PR"));
   teacherAutoEntryState.pendingOrder = TeacherAutoStateReadUlong("PO");
   teacherAutoEntryState.pendingDeal = TeacherAutoStateReadUlong("PE");
   teacherAutoEntryState.pendingMode = (int)TeacherAutoStateRead("PM");
   teacherAutoEntryState.rearmRequired = TeacherAutoStateRead("RR") > 0.5;
   teacherAutoEntryState.lastDirection = (int)MathRound(TeacherAutoStateRead("LD"));
   teacherAutoEntryState.lastLevel = TeacherAutoStateRead("LL");
   teacherAutoEntryState.lastEntryTime = (datetime)MathRound(TeacherAutoStateRead("LT"));

   if(teacherAutoEntryState.pending &&
      (teacherAutoEntryState.pendingDirection != POSITION_TYPE_BUY &&
       teacherAutoEntryState.pendingDirection != POSITION_TYPE_SELL))
   {
      TeacherAutoClearPendingStateFields();
      teacherAutoEntryState.rearmRequired = true;
   }
}

struct TeacherMarkerOrderInfo
{
   ulong ticket;
   string tag;
   int tagIndex;
   ENUM_ORDER_TYPE type;
   double openPrice;
   double tp;
   double volume;
   bool keep;
};

enum ShortRunnerMode
{
   短线尾仓_固定TP = 0,
   短线尾仓_结构追踪,
   短线尾仓_箱体目标,
   短线尾仓_快速退出
};

enum ShortMarketRegime
{
   短线环境_未知 = 0,
   短线环境_震荡,
   短线环境_顺势,
   短线环境_强趋势,
   短线环境_动能衰竭,
   短线环境_箱体边缘,
   短线环境_反向风险
};

enum ShortTradeArchetype
{
   短线类型_未知 = 0,
   短线类型_箱体反转,
   短线类型_箱体突破,
   短线类型_趋势回踩,
   短线类型_扫损接回,
   短线类型_普通手动
};

// 生命周期字段只描述服务器已确认的状态；请求本身单独放在pending中。
enum TradeLifecyclePhase
{
   生命周期_刚接管 = 0,
   生命周期_风险建立中,
   生命周期_正常管理,
   生命周期_退出请求中,
   生命周期_等待最终结算,
   生命周期_已结束,
   生命周期_异常待恢复
};

enum TradeProtectionStage
{
   保护阶段_无有效SL = 0,
   保护阶段_初始风险,
   保护阶段_净保本,
   保护阶段_利润锁定,
   保护阶段_结构追踪
};

enum PendingTradeAction
{
   待确认动作_无 = 0,
   待确认动作_SLTP修改,
   待确认动作_部分平仓,
   待确认动作_全部平仓,
   待确认动作_撤销固定TP,
   待确认动作_快速保护
};

enum TradeExitIntent
{
   退出意图_无 = 0,
   退出意图_固定TP,
   退出意图_SL,
   退出意图_分批止盈,
   退出意图_二级支压全收,
   退出意图_回本退出,
   退出意图_紧急风控,
   退出意图_超时退出,
   退出意图_手动关闭,
   退出意图_消息对冲,
   退出意图_尾仓快速退出,
   退出意图_未知
};

enum TradeSLSource
{
   SL来源_无 = 0,
   SL来源_初始ATR,
   SL来源_初始结构,
   SL来源_初始箱体,
   SL来源_快速净保本,
   SL来源_快速微型箱体,
   SL来源_常规保本,
   SL来源_分批后保护,
   SL来源_M1前柱结构,
   SL来源_微型箱体尾仓,
   SL来源_浮盈回撤锁定,
   SL来源_超时保本,
   SL来源_趋势ATR追踪,
   SL来源_其他,
   SL来源_老师突破保护
};

enum TradeTPSource
{
   TP来源_无 = 0,
   TP来源_初始固定TP,
   TP来源_动态主TP,
   TP来源_箱体目标,
   TP来源_犹豫小TP,
   TP来源_二级支压,
   TP来源_尾仓撤销固定TP,
   TP来源_其他,
   TP来源_老师点位
};

#include "Include/Core/Performance.mqh"
#include "Include/Core/SymbolUtils.mqh"
#include "Include/Journal/LogUtils.mqh"
#include "Include/Market/ATRCache.mqh"
#include "Include/Market/IndicatorHandles.mqh"
#include "Include/Market/SupportResistance.mqh"

string LifecyclePhaseText(int phase)
{
   if(phase == 生命周期_风险建立中) return "风险建立中";
   if(phase == 生命周期_正常管理) return "正常管理";
   if(phase == 生命周期_退出请求中) return "退出请求中";
   if(phase == 生命周期_等待最终结算) return "等待结算";
   if(phase == 生命周期_已结束) return "已结束";
   if(phase == 生命周期_异常待恢复) return "异常待恢复";
   return "刚接管";
}

string ProtectionStageText(int stage)
{
   if(stage == 保护阶段_初始风险) return "初始风险";
   if(stage == 保护阶段_净保本) return "净保本";
   if(stage == 保护阶段_利润锁定) return "利润锁定";
   if(stage == 保护阶段_结构追踪) return "结构追踪";
   return "无有效SL";
}

string PendingActionText(int action)
{
   if(action == 待确认动作_SLTP修改) return "SLTP修改";
   if(action == 待确认动作_部分平仓) return "部分平仓";
   if(action == 待确认动作_全部平仓) return "全部平仓";
   if(action == 待确认动作_撤销固定TP) return "撤固定TP";
   if(action == 待确认动作_快速保护) return "快速保护";
   return "无";
}

enum FloatingPnlTimingState
{
   浮动状态_未知 = 0,
   浮动状态_浮盈,
   浮动状态_近平,
   浮动状态_浮亏
};

const double FLOATING_TIMING_MAX_GAP_SECONDS = 5.0;

struct TicketState
{
   ulong  ticket;
   ulong  positionIdentifier;
   datetime positionOpenTime;
   int    positionDirection;
   int    adoptedTemplate;       // 首次接管时冻结，避免中途切换模板导致统计归类错误。
   double maxProfitPrice;
   double maxLossPrice;
   bool   recoveryArmed;          // 当前组合真实经历深亏后武装；不得由历史maxLoss事后推断。
   datetime recoveryArmedTime;
   double recoveryArmLossPrice;
   double recoveryArmTrigger;
   double maxProfitMoney;
   double maxLossMoney;
   double lifecycleRealizedNetMoney;       // 已实现Deal净收益累计；只用于完整生命周期复盘峰谷。
   double maxLifecycleProfitMoney;         // 生命周期已知最高总盈利，内部保存非负幅度。
   double maxLifecycleLossMoney;           // 生命周期已知最大总亏损，内部保存非负幅度。
   bool   lifecyclePnlEnvelopeInitialized;
   datetime lastM1StructBarTime;
   bool   partialTPDone;
   double initialVolume;
   int      partialTPStage;       // 短线单两段分批：0未分批，1表示首段已确认；2/3仅兼容旧持仓状态
   datetime lastPartialTPTime;    // 上次分批时间，避免连续触发
   double   lastPartialTPProfit;  // 上次分批时的浮盈价格
   bool     shortRiskReady;
   double   shortInitialRisk;      // 仅由服务器真实生效的初始SL冻结，后续推进绝不覆盖。
   double   shortInitialSL;
   double   shortActualInitialSL;
   bool     shortInitialSLConfirmed;
   bool     shortRiskUnknown;
   bool     shortStateManaged;
   bool     teacherActivePlan; // 真实仓位创建时冻结；切换新单策略不改变已有仓位管理
   bool     teacherPlanInitialized; // 逐仓冻结；旧状态或关闭开关时不得在持仓中途自动启用。
   bool     teacherPlanValid;
   ulong    teacherPlanSignature;
   int      teacherPlanMode;
   double   teacherPrimaryTP;
   double   teacherSecondaryTP;
   bool     partialRequestPending;
   int      pendingPartialStage;
   double   pendingPartialVolume;
   double   pendingPartialFilledVolume;
   double   pendingPartialStartVolume;
   datetime pendingPartialRequestTime;
   double   partialFilledVolumeStage1;
   double   partialFilledVolumeStage2;
   double   partialFilledVolumeStage3;
   ulong    lastShortDeal;
   int      runnerMode;
   bool     fixedTPRemoved;
   bool     fastProtectionActivated;
   datetime fastProtectionTime;
   int      confirmedMarketRegime;
   int      candidateMarketRegime;
   int      candidateRegimeCount;
   datetime regimeChangedTime;
   int      tradeArchetype;
   bool     trendRiskReady;        // 仅在服务器真实风险侧SL确认后为true，未确认时禁止R类保护。
   bool     trendRiskUnknown;      // 旧档缺失原始R时禁止用已移动的SL重建风险。
   double   trendInitialRisk;      // 趋势单已确认初始风险R，后续保本/保护按R倍数计算。
   double   trendInitialSL;        // 冻结R时读取到的服务器实际SL，用于重启一致性校验。
   double   trendHighSinceOpen;    // EA接管后记录的最高价，用于多单ATR吊灯
   double   trendLowSinceOpen;     // EA接管后记录的最低价，用于空单ATR吊灯
   datetime lifecycleLastSnapshotTime; // 仅日志节流，不影响任何交易状态
   int      lifecyclePhase;
   int      protectionStage;
   int      pendingAction;
   datetime pendingActionTime;
   ulong    pendingRequestId;
   ulong    pendingOrder;
   ulong    pendingDeal;
   double   pendingRequestedSL;
   double   pendingRequestedTP;
   double   pendingRequestedVolume;
   double   pendingStartVolume;
   int      pendingSLSource;
   int      pendingTPSource;
   int      pendingExitIntent;
   bool     pendingFastProtection;
   double   pendingFastProtectionSL;
   bool     pendingFixedTPRemoval;
   datetime closeDetectedTime;
   int      finalizeRetryCount;
   bool     tradeFinalized;
   int      slModifyCount;
   int      tpModifyCount;
   int      partialFillCount;
   int      lastConfirmedSLSource;
   int      lastConfirmedTPSource;
   int      exitIntent;
   datetime lastManagedModifyTime;
   double   lastKnownVolume;
   double   lastKnownOpenPrice;
   bool     externalVolumeChangeDetected;
   datetime externalVolumeChangeTime;
   double   pendingExitFilledVolume;
   int      pendingRetryCount;
   ulong    lastLifecycleExitDeal;
   datetime lastRegimeClosedBarTime;
   bool     nettingReversalDetected;
   datetime lifecycleSegmentStartTime;
   double   floatingProfitSeconds;              // 生命周期内已观测浮盈时长。
   double   floatingLossSeconds;                // 生命周期内已观测浮亏时长。
   double   floatingFlatSeconds;                // 生命周期内已观测近平时长。
   double   longestFloatingLossSeconds;         // 最长连续浮亏阶段。
   datetime firstFloatingProfitTime;            // 首次观测到有效净浮盈的服务器时间。
   datetime floatingTimingObservationStartTime; // 本终端开始观测该生命周期的时间。
   bool     floatingTimingHasData;
   bool     floatingTimingFinalized;
   int      floatingTimingCurrentState;         // 以下均为运行期字段，不跨终端重启恢复。
   double   floatingTimingCurrentStateSeconds;
   ulong    floatingTimingLastSampleMs;
   bool     floatingTimingSampleReady;
   double   floatingTimingLastPersistObservedSeconds;
   int      floatingTimingSwitchCount;
   bool     floatingTimingEntryCostAttempted;
   bool     stateDirty;             // 仅运行期：持久化字段有变化，等待批量落盘。
   datetime lastStateSaveTime;      // 仅运行期：最近一次完整Global Variables保存时间。
   ulong    stateVersion;           // 仅运行期：每次Mark递增，用于防止漏清dirty。
   ulong    lastSavedVersion;       // 仅运行期：最近一次已落盘的版本。
   bool     entryCostCacheReady;    // 仅运行期：已发生的入场佣金/费用缓存。
   double   cachedEntryCost;
   datetime entryCostCacheTime;
   double   entryCostCacheVolume;
   ulong    entryCostCacheVersion;
};

TicketState states[];

void UpdateAllFloatingPnlTimings();
void FinalizeFloatingPnlTiming(const int stateIdx);
void ResetFloatingPnlTimingForNewLifecycleSegment(const int stateIdx);
void ResetShortTeacherPlan(const int stateIdx);
void FreezeShortTeacherPlan(const int stateIdx, const ENUM_POSITION_TYPE type, const double openPrice);

// MQL5事件串行执行；此作用域只在单个持仓管理调用期间临时提供冻结模板，
// 析构时恢复面板当前配置，避免影响下一笔新单的默认归类和面板显示。
class PositionTemplateScope
{
private:
   管理配置模板 previousTemplate;
public:
   PositionTemplateScope(const int stateIdx)
   {
      previousTemplate = 当前参数配置模板;
      if(stateIdx >= 0 && stateIdx < ArraySize(states))
      {
         int templateId = states[stateIdx].adoptedTemplate;
         if(templateId >= (int)配置_自定义 && templateId <= (int)配置_黄金消息对冲)
            当前参数配置模板 = (管理配置模板)templateId;
      }
   }
   ~PositionTemplateScope()
   {
      当前参数配置模板 = previousTemplate;
   }
};

ulong processedJournalDealTickets[128];
int processedJournalDealCount = 0;

#define SHORT_PENDING_DEAL_CAPACITY 32
ulong pendingShortDealTickets[SHORT_PENDING_DEAL_CAPACITY];
int pendingShortDealCount = 0;
ulong processedShortDealTickets[128];
int processedShortDealCount = 0;

struct ShortFastPricePoint
{
   ulong  timeMsc;
   double mid;
};

#define SHORT_FAST_TICK_CAPACITY 2048
ShortFastPricePoint shortFastTicks[SHORT_FAST_TICK_CAPACITY];
int shortFastTickHead = 0;
int shortFastTickCount = 0;

struct NewsHedgeState
{
   int      stage;
   int      adoptedTemplate;      // 组合首笔真实成交时冻结为消息对冲；切换面板不能中断进行中的组合。
   ulong    waitTicket;
   datetime waitStartTime;
   ulong    buyTicket;
   ulong    sellTicket;
   ulong    runnerTicket;
   ulong    loserTicket;
   ulong    buyPositionId;
   ulong    sellPositionId;
   ulong    runnerPositionId;
   ulong    loserPositionId;
   double   buyOpenPrice;
   double   sellOpenPrice;
   datetime pairTime;
   datetime unhedgeTime;
   ulong    unhedgeTimeMs;
   double   unhedgePrice;
   double   initialGroupRiskMoney;
   bool     loserDealReady;
   bool     runnerRiskReady;
   double   actualRunnerRiskSL;
   double   loserClosePrice;
   ulong    loserCloseTimeMsc;
   datetime groupFlatSince;
   double   actualUnlockExtension;
   double   actualUnlockSlippage;
   double   runnerExtremePrice;
   ulong    lastExtremeTimeMs;
   int      runnerPhase;
   double   microPullbackPrice;
   bool     microPullbackActive;
   bool     microPullbackConfirmed;
   ulong    microPullbackStartMsc;
   bool     microPullbackInvalid;
   double   microImpulseExtreme;
   bool     firstPartialDone;
   bool     secondPartialDone;
   double   referencePrice;
   double   rangeHigh;
   double   rangeLow;
   double   atrAtPair;
   double   hardStopDistance;
   bool     boxValid;
   datetime boxFreezeTime;
   double   boxWidth;
   int      boxHighTouches;
   int      boxLowTouches;
   int      boxMiddleCrosses;
   double   boxCloseInsideRatio;
   double   normalSpreadPrice;
   double   initialBuffer;
   double   breakoutBuffer;
   double   failureBuffer;
   bool     boxFrozenByUser;
   bool     releaseEnabled;
   datetime releaseTime;
   datetime releaseExpireTime;
   ulong    releaseStartMs;
   double   disasterBuffer;
   double   buyDisasterSL;
   double   sellDisasterSL;
   double   runnerStructureSL;
   bool     runnerBoxProtectionApplied;
   int      breakoutDirection;       // 1=向上留BUY，-1=向下留SELL
   int      candidateDirection;
   int      candidateTicks;
   ulong    candidateStartMs;
   int      pendingBreakoutDirection;
   ulong    pendingBreakoutStartMs;
   int      failureTicks;
   ulong    failureStartMs;
   double   breakoutPrice;
   double   pendingLoserLossMoney;
   double   realizedLoserLossMoney;
   double   estimatedExtraCostMoney;
   double   actualCostMoney;
   double   estimatedRemainingExitCostMoney;
   double   realizedRunnerProfitMoney;
   double   runnerPendingEstimateMoney;
   double   maxCombinedMoney;
   double   runnerInitialVolume;
   double   runnerHigh;
   double   runnerLow;
   int      runnerPartialStage;
   bool     runnerPartialPending;
   int      runnerPartialTargetStage;
   double   runnerPartialStageStartVolume;
   double   runnerPartialTargetVolume;
   double   runnerPartialStageStartExitVolume;
   double   runnerPartialFilledVolume;
   double   runnerPartialRequestedVolume;
   datetime runnerPartialRequestTime;
   double   runnerRealizedExitVolume;
   double   runnerActualCostMoney;
   datetime lastPartialTime;
   datetime lastStructureBarTime;
   ulong    lastLoserDeal;
   ulong    lastRunnerDeal;
   double   loserDealNetMoney;
   bool     loserActualKnown;
   int      stopStage;
   long     stopToken;
   ulong    buyStopOrder;
   ulong    sellStopOrder;
   datetime stopRequestTime;
   datetime stopExpireTime;
   bool     buyStopDeletePending;
   bool     sellStopDeletePending;
   datetime buyStopDeleteTime;
   datetime sellStopDeleteTime;
};

NewsHedgeState newsState;
string 消息对冲状态 = "待命";
string 消息对冲箱体拒绝原因 = "";
string 消息对冲退出原因 = "";
datetime 上次消息状态保存时间 = 0;
datetime 上次消息箱体尝试时间 = 0;

bool NewsHedgeGroupActive()
{
   return (newsState.stage != 消息阶段_待命 && newsState.adoptedTemplate == (int)配置_黄金消息对冲);
}

class NewsHedgeTemplateScope
{
private:
   管理配置模板 previousTemplate;
public:
   NewsHedgeTemplateScope()
   {
      previousTemplate = 当前参数配置模板;
      if(NewsHedgeGroupActive()) 当前参数配置模板 = 配置_黄金消息对冲;
   }
   ~NewsHedgeTemplateScope()
   {
      当前参数配置模板 = previousTemplate;
   }
};

struct NewsMicroTickPoint
{
   ulong  timeMsc;
   double bid;
   double ask;
   double mid;
};

NewsMicroTickPoint newsMicroTicks[4096];
int newsMicroHead = 0;
int newsMicroCount = 0;

#define NEWS_PENDING_DEAL_CAPACITY 16
#define NEWS_PARTIAL_TIMEOUT_SECONDS 20
ulong newsPendingDeals[NEWS_PENDING_DEAL_CAPACITY];
int newsPendingDealCount = 0;

ulong newsPairSLLastLogMs[2] = {0,0};
double newsPairSLLastLogged[2] = {0.0,0.0};
bool newsPairSLLastOk[2] = {false,false};
ulong newsRunnerProtectionLastLogMs = 0;
bool newsRunnerProtectionLastLoggedState = false;

struct ShortLineMarketContext
{
   double atrM1;
   double atrM5;
   double lastBody;
   double lastRange;
   double lastUpperWick;
   double lastLowerWick;
   double bodyRatio;
   double closePosRatio;
   double avgBody3;
   double avgRange3;
   double impulseScore;
   double chopScore;
   double trendScore;
   double boxRoom;
   bool   m1BullImpulse;
   bool   m1BearImpulse;
   bool   m5SameDirection;
   bool   nearBoxEdge;
   bool   momentumWeak;
   bool   strongForPosition;
   bool   choppyForPosition;
};

// 短线上下文中的已收盘K线数据只会在新M1/M5出现时变化。
// 多笔短线仓共享这一份基础快照；方向、当前价和箱体距离仍逐仓实时计算。
struct ShortLineSharedBarCache
{
   bool     valid;
   datetime m1CurrentBarTime;
   datetime m5CurrentBarTime;
   double   fallbackAtrM1;
   double   atrM5;
   double   avgBody3;
   double   avgRange3;
   double   lastOpen;
   double   lastClose;
   double   previousM1Close;
   double   lastHigh;
   double   lastLow;
   bool     hasM5DirectionBars;
   double   latestM5Open;
   double   latestM5Close;
   double   previousM5Close;
};

ShortLineSharedBarCache shortLineSharedBarCache;

// 短线结构箱体只由已收 M1 建立；它不写入支撑压力缓存，但有效且未突破时可作为短线初始 SL/TP 候选。
struct ShortVisualBoxEdge
{
   double   price;
   int      touches;
   datetime lastTouchTime;
};

struct ShortVisualBoxState
{
   bool     hasBox;
   bool     validBox;
   bool     frozen;
   datetime scannedClosedBarTime;
   datetime boxStartTime;
   double   boxHigh;
   double   boxLow;
   int      upperTouches;
   int      lowerTouches;
   double   insideCloseRatio;
   double   atrWidth;
};

ShortVisualBoxState shortVisualBox;
#include "Include/Market/ShortBox.mqh"
#include "Include/Persistence/StateStore.mqh"
#include "Include/Journal/TradeJournal.mqh"
#include "Include/Journal/TradeSummary.mqh"
#include "Include/Journal/LifecycleStatistics.mqh"

//===================== v1.56 Canvas 面板架构（仅视图层） =====================//
enum UISeverity
{
   UI_SEVERITY_MUTED = 0,
   UI_SEVERITY_INFO = 1,
   UI_SEVERITY_SUCCESS = 2,
   UI_SEVERITY_WARNING = 3,
   UI_SEVERITY_DANGER = 4
};

enum PanelDirtyFlags
{
   PANEL_DIRTY_NONE = 0,
   PANEL_DIRTY_DATA = 1,
   PANEL_DIRTY_LAYOUT = 2,
   PANEL_DIRTY_STYLE = 4,
   PANEL_DIRTY_RENDER = 8,
   PANEL_DIRTY_HEADER_CLOCK = 16,
   PANEL_DIRTY_ALL = 31
};

enum 持仓显示筛选类型
{
   持仓筛选_全部 = 0,
   持仓筛选_短线,
   持仓筛选_长线,
   持仓筛选_消息,
   持仓筛选_手动
};

enum PanelAction
{
   PANEL_ACTION_NONE = 0,
   PANEL_ACTION_PAGE_HOLDING,
   PANEL_ACTION_PAGE_STATS,
   PANEL_ACTION_DENSITY_TOGGLE,
   PANEL_ACTION_MODE_MINI,
   PANEL_ACTION_MODE_FULL,
   PANEL_ACTION_MODE_HIDE,
   PANEL_ACTION_TEMPLATE_CUSTOM,
   PANEL_ACTION_TEMPLATE_FAST,
   PANEL_ACTION_TEMPLATE_TREND,
   PANEL_ACTION_TEMPLATE_NORMAL,
   PANEL_ACTION_TEMPLATE_NEWS,
   PANEL_ACTION_POSITION_FILTER_ALL,
   PANEL_ACTION_MARKER_TOGGLE,
   PANEL_ACTION_STATS_DAY,
   PANEL_ACTION_STATS_WEEK,
   PANEL_ACTION_STATS_MONTH,
   PANEL_ACTION_PERIOD_PREV,
   PANEL_ACTION_PERIOD_CURRENT,
   PANEL_ACTION_PERIOD_NEXT,
   PANEL_ACTION_FILTER_ALL,
   PANEL_ACTION_FILTER_SHORT,
   PANEL_ACTION_FILTER_TREND,
   PANEL_ACTION_FILTER_NORMAL,
   PANEL_ACTION_FILTER_NEWS,
   PANEL_ACTION_FILTER_NEXT,
   PANEL_ACTION_DETAIL_OVERVIEW,
   PANEL_ACTION_DETAIL_STRATEGY,
   PANEL_ACTION_DETAIL_MANAGE,
   PANEL_ACTION_DETAIL_EXEC,
   PANEL_ACTION_DETAIL_REVIEW,
   PANEL_ACTION_OVERVIEW_BEST_REVIEW,
   PANEL_ACTION_OVERVIEW_WORST_REVIEW,
   PANEL_ACTION_REVIEW_PREV,
   PANEL_ACTION_REVIEW_NEXT,
   PANEL_ACTION_POSITION_PREV,
   PANEL_ACTION_POSITION_NEXT,
   PANEL_ACTION_NEWS_FREEZE,
   PANEL_ACTION_NEWS_RELEASE,
   PANEL_ACTION_NEWS_CANCEL,
   PANEL_ACTION_NEWS_FLAT,
   PANEL_ACTION_DETAIL_TREND,
   PANEL_ACTION_TREND_OPEN_REVIEW,
   PANEL_ACTION_TREND_SELECT
};

const int CANVAS_STATS_TAB_COUNT=4;

enum PanelSurfaceLevel
{
   SURFACE_ROOT = 0,
   SURFACE_HEADER,
   SURFACE_TOOLBAR,
   SURFACE_CONTAINER,
   SURFACE_CARD,
   SURFACE_CARD_RAISED,
   SURFACE_ROW,
   SURFACE_ROW_ALT,
   SURFACE_SELECTED,
   SURFACE_WARNING,
   SURFACE_DANGER
};

enum CanvasControlVisualState
{
   CONTROL_NORMAL = 0,
   CONTROL_HOVER,
   CONTROL_PRESSED,
   CONTROL_SELECTED,
   CONTROL_DISABLED
};

enum BadgeStyle
{
   BADGE_COMPACT = 0,
   BADGE_STATUS
};

struct UIRect
{
   int x;
   int y;
   int w;
   int h;
};

struct PanelTheme
{
   uint root;
   uint background;
   uint header;
   uint toolbar;
   uint container;
   uint card;
   uint cardRaised;
   uint row;
   uint rowAlt;
   uint selected;
   uint surface;
   uint surfaceAlt;
   uint hover;
   uint borderWeak;
   uint borderNormal;
   uint borderStrong;
   uint border;
   uint topHighlight;
   uint bottomShadow;
   uint text;
   uint muted;
   uint dim;
   uint accent;
   uint profit;
   uint loss;
   uint pnlFlat;
   uint directionBuy;
   uint directionSell;
   uint warning;
   uint infoFill;
   uint infoBorder;
   uint infoText;
   uint successFill;
   uint successBorder;
   uint successText;
   uint warningFill;
   uint warningBorder;
   uint warningText;
   uint warningBadgeText;
   uint dangerFill;
   uint dangerBorder;
   uint dangerText;
   uint disabledFill;
   uint disabledText;
};

struct PanelViewState
{
   面板页面 page;
   面板显示模式 displayMode;
   面板信息密度 density;
   统计周期模式 statsPeriod;
   统计策略筛选 statsFilter;
   统计详情页面 statsDetail;
   int dayOffset;
   int weekOffset;
   int monthOffset;
   int reviewIndex;
   int pendingTrendPointIndex;
   int selectedTrendPointIndex;
   bool trendSelectionValid;
   string trendSelectionMessage;
   string statsActionMessage;
   long trendSelectionGeneration;
   int positionPage;
   持仓显示筛选类型 positionFilter;
   int panelX;
   int panelY;
   bool dragging;
   int dragMouseX;
   int dragMouseY;
   int dragPanelX;
   int dragPanelY;
   PanelAction hoverAction;
   PanelAction pressedAction;
   ulong lastClickTick;
   int lastClickX;
   int lastClickY;
   PanelAction lastClickAction;
   ulong suppressClickUntilTick;
};

struct PanelMetrics
{
   double dpiScale;
   int width;
   int height;
   int margin;
   int gap;
   int padding;
   int radius;
   int space2;
   int space4;
   int space6;
   int space8;
   int space10;
   int space12;
   int space16;
   int radiusButton;
   int radiusCard;
   int radiusContainer;
   int radiusBadge;
   int headerHeight;
   int tabHeight;
   int cardHeight;
   int fontHeader;
   int fontTab;
   int fontLabel;
   int fontValue;
   int fontCaption;
   int fontTitle;
   int fontBody;
   int fontSmall;
   string fontName;
};

struct PositionPanelViewModel
{
   ulong ticket;
   long type;
   double volume;
   double openPrice;
   double currentPrice;
   double sl;
   double tp;
   double profit;
   double peakProfit;
   double profitPrice;
   double riskDistance;
   bool hasSL;
   bool hasTP;
   bool hasCurrentPrice;
   bool distanceToSLValid;
   bool distanceToTPValid;
   double distanceToSL;
   double distanceToTP;
   string distanceToSLText;
   string distanceToTPText;
   bool protectedPosition;
   int heldMinutes;
   int templateId;
   string templateName;
   string lifecycleName;
   string protectionText;
   string nextActionText;
   UISeverity severity;
};

struct MiniPanelViewModel
{
   string symbol;
   int managedCount;
   int buyCount;
   int sellCount;
   double floatingProfit;
   int slCount;
   double nearestResistance;
   double nearestSupport;
   UISeverity profitSeverity;
   UISeverity riskSeverity;
};

struct FilteredPositionSummary
{
   int managedCount;
   int buyCount;
   int sellCount;
   double buyLots;
   double sellLots;
   double totalLots;
   double floatingProfit;
   double peakProfit;
   int slCount;
   int tpCount;
   int protectedCount;
   string riskSummary;
};

struct NewsStopPreview
{
   bool     visible;
   bool     priceValid;
   double   volume;
   double   buyStop;
   double   sellStop;
   double   buyDisasterSL;
   double   sellDisasterSL;
   bool     buyLossAvailable;
   bool     sellLossAvailable;
   double   buyLossMoney;
   double   sellLossMoney;
   bool     buyMarginAvailable;
   bool     sellMarginAvailable;
   double   buyMargin;
   double   sellMargin;
   bool     deployValid;
   string   status;
};

struct HoldingPanelViewModel
{
   int managedCount;
   int buyCount;
   int sellCount;
   double buyLots;
   double sellLots;
   double totalLots;
   double floatingProfit;
   double peakProfit;
   int slCount;
   int tpCount;
   int protectedCount;
   bool markerEnabled;
   string riskSummary;
   string resistanceText;
   string supportText;
   string statusText;
   UISeverity statusSeverity;
   NewsStopPreview newsStopPreview;
   PositionPanelViewModel positions[];
   int filteredPositionIndexes[];
   FilteredPositionSummary filteredSummary;
};

struct TrendTradePoint
{
   ulong positionId;
   datetime closeTime;
   double netProfit;
   double cumulativeProfit;
   double peakProfit;
   double drawdown;
   int reviewIndex;
   bool reviewAvailable;
};

struct StatsTrendViewModel
{
   TrendTradePoint points[];
   double cumulativeProfit;
   double currentDrawdown;
   double peakProfit;
   double maxDrawdown;
   double recentProfit;
   int recentCount;
   bool hasData;
   string statusText;
};

struct StatsPanelViewModel
{
   LifecycleStats stats;
   string periodText;
   string rangeText;
   string filterText;
   string insight;
   UISeverity resultSeverity;
   LifecycleReviewItem reviews[];
   StatsTrendViewModel trend;
};

struct ReviewViewCacheKey
{
   int period;
   int filter;
   int dayOffset;
   int weekOffset;
   int monthOffset;
   long tradeGeneration;
   string symbol;
   datetime serverStart;
   datetime serverEnd;
};

struct TrendViewCacheKey
{
   int period;
   int filter;
   int dayOffset;
   int weekOffset;
   int monthOffset;
   long tradeGeneration;
   string symbol;
   datetime serverStart;
   datetime serverEnd;
};

struct PanelViewModel
{
   MiniPanelViewModel mini;
   HoldingPanelViewModel holding;
   StatsPanelViewModel stats;
   double spreadPoints;
   string statusText;
};

struct PanelLayout
{
   UIRect panel;
   UIRect header;
   UIRect headerTitle;
   UIRect headerStatus;
   UIRect mainTabs[5];
   UIRect templateBar;
   UIRect templateTabs[5];
   UIRect markerBadge;
   UIRect positionFilterScope;
   UIRect positionEntryTemplate;
   UIRect metricCards[4];
   UIRect positionsHeader;
   UIRect positionCards[3];
   UIRect positionDirection[3];
   UIRect positionIdentity[3];
   UIRect positionProtection[3];
   UIRect positionProfit[3];
   UIRect positionPrices[3];
   UIRect positionMeta[3];
   UIRect emptyState;
   UIRect emptyTitle;
   UIRect emptyCaption;
   UIRect positionPrev;
   UIRect positionPageLabel;
   UIRect positionNext;
   UIRect supportRow;
   UIRect statusRow;
   UIRect miniSummaryStrip;
   UIRect miniSummaryCells[3];
   UIRect miniSummaryLabels[3];
   UIRect miniSummaryValues[3];
   UIRect miniPositionList;
   UIRect miniPositionListHeader;
   UIRect miniPositionColumns[4];
   UIRect miniSupportFooter;
   UIRect miniR1Rect;
   UIRect miniS1Rect;
   UIRect statsDetailTabs[5];
   UIRect statsToolbar;
   UIRect statsPeriodSelector;
   UIRect statsDateNavigator;
   UIRect statsPeriodTabs[3];
   UIRect statsPeriodNav[3];
   UIRect statsFilterTabs[5];
   UIRect statsSummary[4];
   UIRect statsTableHeader;
   UIRect statsTableRows[12];
   UIRect statsLeftColumn;
   UIRect statsRightColumn;
   UIRect statsLeftRows[7];
   UIRect statsRightRows[7];
   UIRect statsNote;
   UIRect statsPerformanceConclusion;
   UIRect statsPerformanceSampleNote;
   UIRect trendSummary[4];
   UIRect trendCurveCard;
   UIRect trendCurveTitle;
   UIRect trendCurvePlot;
   UIRect trendCurveAxisY;
   UIRect trendCurvePlotInner;
   UIRect trendCurveAxisX;
   UIRect trendBarsCard;
   UIRect trendBarsTitle;
   UIRect trendBarsPlot;
   UIRect trendBarsAxisY;
   UIRect trendBarsPlotInner;
   UIRect trendBarsAxisX;
   UIRect trendStatus;
   UIRect trendSelectionPanel;
   UIRect trendSelectionLine1;
   UIRect trendSelectionLine2;
   UIRect trendReviewButton;
   UIRect trendEmptyState;
   UIRect content;
   UIRect footer;
   UIRect statsFooterText;
   UIRect reviewPrev;
   UIRect reviewNext;
   UIRect reviewNav;
   UIRect reviewSummary;
   UIRect reviewSummaryRows[2];
   UIRect reviewDirection;
   UIRect reviewVolume;
   UIRect reviewNetLabel;
   UIRect reviewNetValue;
   UIRect reviewRValue;
   UIRect reviewDuration;
   UIRect reviewTimeRange;
   UIRect reviewPrice;
   UIRect reviewPriceTitle;
   UIRect reviewPriceRows[4];
   UIRect reviewClassification;
   UIRect reviewClassificationTitle;
   UIRect reviewClassRows[4];
   UIRect reviewManagement;
   UIRect reviewManagementTitle;
   UIRect reviewManageCells[8];
   UIRect reviewHint;
   UIRect newsButtons[4];
};

struct UIHitRegion
{
   UIRect rect;
   PanelAction action;
   bool enabled;
};

UIRect MakeUIRect(int x, int y, int w, int h)
{
   UIRect rect;
   rect.x=x; rect.y=y; rect.w=w; rect.h=h;
   return rect;
}

bool UIContains(const UIRect &rect, int x, int y)
{
   return (x>=rect.x && x<rect.x+rect.w && y>=rect.y && y<rect.y+rect.h);
}

class CPanelRenderer
{
private:
   CCanvas m_canvas;
   bool m_ready;
   int m_width;
   int m_height;
   int m_updateCount;
   bool m_recreated;

public:
   CPanelRenderer(void)
   {
      m_ready=false;
      m_width=0;
      m_height=0;
      m_updateCount=0;
      m_recreated=false;
   }

   bool Ensure(int x, int y, int width, int height)
   {
      m_recreated=false;
      width=MathMax(width,1);
      height=MathMax(height,1);
      bool objectMissing=(ObjectFind(0,"SMA_CANVAS")<0);
      if(!m_ready || objectMissing || width!=m_width || height!=m_height)
      {
         Destroy();
         if(!objectMissing) ObjectDelete(0,"SMA_CANVAS");
         if(!m_canvas.CreateBitmapLabel(ChartID(),0,"SMA_CANVAS",x,y,width,height,COLOR_FORMAT_ARGB_NORMALIZE))
            return false;
         m_ready=true;
         m_recreated=true;
         m_width=width;
         m_height=height;
         ObjectSetInteger(0,"SMA_CANVAS",OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,"SMA_CANVAS",OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,"SMA_CANVAS",OBJPROP_SELECTED,false);
         ObjectSetInteger(0,"SMA_CANVAS",OBJPROP_BACK,false);
         ObjectSetInteger(0,"SMA_CANVAS",OBJPROP_ZORDER,1);
      }
      Move(x,y);
      return true;
   }

   void Destroy(void)
   {
      if(m_ready) m_canvas.Destroy();
      else ObjectDelete(0,"SMA_CANVAS");
      m_ready=false;
      m_width=0;
      m_height=0;
   }

   void Move(int x, int y)
   {
      if(!m_ready) return;
      ObjectSetInteger(0,"SMA_CANVAS",OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0,"SMA_CANVAS",OBJPROP_YDISTANCE,y);
   }

   bool Alive(int width, int height)
   {
      return (m_ready && ObjectFind(0,"SMA_CANVAS")>=0 && m_width==width && m_height==height);
   }

   int Width(void) const { return m_width; }
   int Height(void) const { return m_height; }
   bool Recreated(void) const { return m_recreated; }

   void Begin(uint background)
   {
      if(!m_ready) return;
      m_updateCount=0;
      m_canvas.Erase(background);
   }

   void BeginPartial(void)
   {
      if(!m_ready) return;
      m_updateCount=0;
   }

   void FillRect(const UIRect &rect, uint fill)
   {
      if(!m_ready || rect.w<=0 || rect.h<=0) return;
      m_canvas.FillRectangle(rect.x,rect.y,rect.x+rect.w-1,rect.y+rect.h-1,fill);
   }

   void FillRoundedRect(const UIRect &rect, int radius, uint fill)
   {
      if(!m_ready || rect.w<=0 || rect.h<=0) return;
      int r=MathMax(0,MathMin(radius,MathMin(rect.w,rect.h)/2));
      if(r<=1)
      {
         FillRect(rect,fill);
         return;
      }
      m_canvas.FillRectangle(rect.x+r,rect.y,rect.x+rect.w-r-1,rect.y+rect.h-1,fill);
      m_canvas.FillRectangle(rect.x,rect.y+r,rect.x+rect.w-1,rect.y+rect.h-r-1,fill);
      m_canvas.FillCircle(rect.x+r,rect.y+r,r,fill);
      m_canvas.FillCircle(rect.x+rect.w-r-1,rect.y+r,r,fill);
      m_canvas.FillCircle(rect.x+r,rect.y+rect.h-r-1,r,fill);
      m_canvas.FillCircle(rect.x+rect.w-r-1,rect.y+rect.h-r-1,r,fill);
   }

   void StrokeRoundedRect(const UIRect &rect, int radius, uint border)
   {
      if(!m_ready || rect.w<=0 || rect.h<=0) return;
      int r=MathMax(0,MathMin(radius,MathMin(rect.w,rect.h)/2));
      if(r<=1)
      {
         m_canvas.Rectangle(rect.x,rect.y,rect.x+rect.w-1,rect.y+rect.h-1,border);
         return;
      }
      m_canvas.LineHorizontal(rect.x+r,rect.x+rect.w-r-1,rect.y,border);
      m_canvas.LineHorizontal(rect.x+r,rect.x+rect.w-r-1,rect.y+rect.h-1,border);
      m_canvas.LineVertical(rect.x,rect.y+r,rect.y+rect.h-r-1,border);
      m_canvas.LineVertical(rect.x+rect.w-1,rect.y+r,rect.y+rect.h-r-1,border);
      double rr=(double)r*(double)r;
      for(int dx=0;dx<=r;dx++)
      {
         int dy=(int)MathRound(MathSqrt(MathMax(rr-(double)dx*(double)dx,0.0)));
         m_canvas.PixelSet(rect.x+r-dx,rect.y+r-dy,border);
         m_canvas.PixelSet(rect.x+rect.w-r-1+dx,rect.y+r-dy,border);
         m_canvas.PixelSet(rect.x+r-dx,rect.y+rect.h-r-1+dy,border);
         m_canvas.PixelSet(rect.x+rect.w-r-1+dx,rect.y+rect.h-r-1+dy,border);
      }
   }

   void FillRoundRect(const UIRect &rect, int radius, uint fill, uint border)
   {
      if(!m_ready || rect.w<=0 || rect.h<=0) return;
      int r=MathMax(0,MathMin(radius,MathMin(rect.w,rect.h)/2));
      FillRoundedRect(rect,r,border);
      if(rect.w<=2 || rect.h<=2) return;
      UIRect inner=MakeUIRect(rect.x+1,rect.y+1,rect.w-2,rect.h-2);
      FillRoundedRect(inner,MathMax(r-1,0),fill);
   }

   void Line(int x1, int y1, int x2, int y2, uint colorValue)
   {
      if(!m_ready) return;
      m_canvas.Line(x1,y1,x2,y2,colorValue);
   }

   void LineAA(int x1, int y1, int x2, int y2, uint colorValue)
   {
      if(!m_ready) return;
      m_canvas.LineAA(x1,y1,x2,y2,colorValue);
   }

   void FillCircle(int x, int y, int radius, uint colorValue)
   {
      if(!m_ready || radius<=0) return;
      m_canvas.FillCircle(x,y,radius,colorValue);
   }

   bool FontAvailable(string fontName, int fontSize)
   {
      if(!m_ready || fontName=="") return false;
      return m_canvas.FontSet(fontName,fontSize);
   }

   string Ellipsize(string text, int maxWidth, string fontName, int fontSize)
   {
      if(maxWidth<=0) return "";
      m_canvas.FontSet(fontName,fontSize);
      if(m_canvas.TextWidth(text)<=maxWidth) return text;
      string suffix="...";
      if(m_canvas.TextWidth(suffix)>maxWidth) return "";
      int low=0, high=StringLen(text);
      while(low<high)
      {
         int mid=low+(high-low+1)/2;
         if(m_canvas.TextWidth(StringSubstr(text,0,mid)+suffix)<=maxWidth) low=mid;
         else high=mid-1;
      }
      return StringSubstr(text,0,low)+suffix;
   }

   void Text(const UIRect &rect, string text, uint colorValue, string fontName, int fontSize, int insetX=0, int insetY=0)
   {
      if(!m_ready || rect.w<=0 || rect.h<=0) return;
      string shown=Ellipsize(text,MathMax(rect.w-insetX*2,1),fontName,fontSize);
      m_canvas.TextOut(rect.x+insetX,rect.y+insetY,shown,colorValue);
   }

   int TextWidth(string text, string fontName, int fontSize)
   {
      if(!m_ready) return 0;
      m_canvas.FontSet(fontName,fontSize);
      return m_canvas.TextWidth(text);
   }

   int TextHeight(string text, string fontName, int fontSize)
   {
      if(!m_ready) return 0;
      m_canvas.FontSet(fontName,fontSize);
      return m_canvas.TextHeight(text==""?"中":text);
   }

   void TextVerticalCenter(const UIRect &rect, string text, uint colorValue, string fontName, int fontSize, int alignment=0, int insetX=0)
   {
      if(!m_ready || rect.w<=0 || rect.h<=0) return;
      string shown=Ellipsize(text,MathMax(rect.w-insetX*2,1),fontName,fontSize);
      int tw=m_canvas.TextWidth(shown);
      int th=m_canvas.TextHeight(shown==""?"中":shown);
      int tx=rect.x+insetX;
      if(alignment==1) tx=rect.x+MathMax((rect.w-tw)/2,0);
      else if(alignment==2) tx=rect.x+rect.w-insetX-tw;
      m_canvas.TextOut(tx,rect.y+MathMax((rect.h-th)/2,0),shown,colorValue);
   }

   void TextLeft(const UIRect &rect, string text, uint colorValue, string fontName, int fontSize, int insetX=0)
   {
      TextVerticalCenter(rect,text,colorValue,fontName,fontSize,0,insetX);
   }

   void TextRight(const UIRect &rect, string text, uint colorValue, string fontName, int fontSize, int insetX=0)
   {
      TextVerticalCenter(rect,text,colorValue,fontName,fontSize,2,insetX);
   }

   void TextCenter(const UIRect &rect, string text, uint colorValue, string fontName, int fontSize)
   {
      TextVerticalCenter(rect,text,colorValue,fontName,fontSize,1,0);
   }

   void TextEllipsized(const UIRect &rect, string text, uint colorValue, string fontName, int fontSize, int alignment=0, int insetX=0)
   {
      TextVerticalCenter(rect,text,colorValue,fontName,fontSize,alignment,insetX);
   }

   void Divider(const UIRect &rect, uint colorValue, bool vertical=false)
   {
      if(!m_ready || rect.w<=0 || rect.h<=0) return;
      if(vertical)
         FillRect(MakeUIRect(rect.x+rect.w/2,rect.y,1,rect.h),colorValue);
      else
         FillRect(MakeUIRect(rect.x,rect.y+rect.h/2,rect.w,1),colorValue);
   }

   void Badge(const UIRect &rect, string text, uint fill, uint textColor, string fontName, int fontSize)
   {
      FillRoundRect(rect,MathMax(3,rect.h/4),fill,fill);
      TextCenter(rect,text,textColor,fontName,fontSize);
   }

   bool TextStackFits(int rectHeight, string fontName, int labelFont, int valueFont, int captionFont, int spacing)
   {
      if(!m_ready || rectHeight<=0) return false;
      int total=TextHeight("中",fontName,labelFont)+TextHeight("中",fontName,valueFont)+TextHeight("中",fontName,captionFont)+MathMax(spacing,0)*2;
      return total<=rectHeight;
   }

   void MetricCellCompact(const UIRect &rect, string label, string value, string secondary, uint valueColor,
                          uint labelColor, uint secondaryColor, string fontName, int labelFont, int valueFont, int secondaryFont, int padding=8)
   {
      if(!m_ready || rect.w<=0 || rect.h<=0) return;
      int pad=MathMax(padding,4);
      int labelH=TextHeight(label,fontName,labelFont);
      int valueH=TextHeight(value,fontName,valueFont);
      int secondaryH=TextHeight(secondary,fontName,secondaryFont);
      int topH=MathMax(labelH,secondaryH);
      int lineGap=MathMax(labelH/7,1);
      int totalH=topH+lineGap+valueH;
      if(totalH>rect.h)
      {
         secondary="";
         topH=labelH;
         lineGap=0;
         totalH=topH+valueH;
      }
      int y=rect.y+MathMax((rect.h-totalH)/2,0);
      int innerW=MathMax(rect.w-pad*2,1);
      TextLeft(MakeUIRect(rect.x+pad,y,innerW*52/100,topH),label,labelColor,fontName,labelFont);
      if(secondary!="")
         TextRight(MakeUIRect(rect.x+pad+innerW*52/100,y,innerW*48/100,topH),secondary,secondaryColor,fontName,secondaryFont);
      TextLeft(MakeUIRect(rect.x+pad,y+topH+lineGap,innerW,valueH),value,valueColor,fontName,valueFont);
   }

   void MetricCellThreeLine(const UIRect &rect, string label, string value, string caption, uint valueColor,
                            uint labelColor, uint captionColor, string fontName, int labelFont, int valueFont, int captionFont, int padding=8)
   {
      if(!m_ready || rect.w<=0 || rect.h<=0) return;
      int pad=MathMax(padding,4);
      int lineGap=MathMax(TextHeight("中",fontName,labelFont)/8,1);
      if(!TextStackFits(rect.h,fontName,labelFont,valueFont,captionFont,lineGap))
      {
         MetricCellCompact(rect,label,value,caption,valueColor,labelColor,captionColor,fontName,labelFont,valueFont,captionFont,padding);
         return;
      }
      int labelH=TextHeight(label,fontName,labelFont);
      int valueH=TextHeight(value,fontName,valueFont);
      int captionH=TextHeight(caption,fontName,captionFont);
      int totalH=labelH+valueH+captionH+lineGap*2;
      int y=rect.y+MathMax((rect.h-totalH)/2,0);
      int innerW=MathMax(rect.w-pad*2,1);
      TextLeft(MakeUIRect(rect.x+pad,y,innerW,labelH),label,labelColor,fontName,labelFont);
      y+=labelH+lineGap;
      TextLeft(MakeUIRect(rect.x+pad,y,innerW,valueH),value,valueColor,fontName,valueFont);
      y+=valueH+lineGap;
      TextLeft(MakeUIRect(rect.x+pad,y,innerW,captionH),caption,captionColor,fontName,captionFont);
   }

   void MetricCell(const UIRect &rect, string label, string value, string caption, uint valueColor,
                   uint labelColor, uint captionColor, string fontName, int labelFont, int valueFont, int captionFont, int padding=8)
   {
      MetricCellThreeLine(rect,label,value,caption,valueColor,labelColor,captionColor,fontName,labelFont,valueFont,captionFont,padding);
   }

   void TextBlockTwoLines(const UIRect &rect, string line1, string line2, uint line1Color, uint line2Color,
                          string fontName, int fontSize, int insetX=0, int lineGap=1)
   {
      if(!m_ready || rect.w<=0 || rect.h<=0) return;
      int h1=TextHeight(line1,fontName,fontSize);
      int h2=line2==""?0:TextHeight(line2,fontName,fontSize);
      int gap=line2==""?0:MathMax(lineGap,0);
      int totalH=h1+h2+gap;
      if(totalH>rect.h)
      {
         line2="";
         h2=0;
         gap=0;
         totalH=h1;
      }
      int y=rect.y+MathMax((rect.h-totalH)/2,0);
      TextEllipsized(MakeUIRect(rect.x,y,rect.w,h1),line1,line1Color,fontName,fontSize,0,insetX);
      if(line2!="")
         TextEllipsized(MakeUIRect(rect.x,y+h1+gap,rect.w,h2),line2,line2Color,fontName,fontSize,0,insetX);
   }

   void TableHeader(const UIRect &rect, string col1, string col2, string col3, string col4, string col5,
                    uint fill, uint textColor, string fontName, int fontSize)
   {
      FillRect(MakeUIRect(rect.x+1,rect.y+1,MathMax(rect.w-2,1),MathMax(rect.h-1,1)),fill);
      bool five=(col5!="");
      int inset=MathMax(rect.h*10/28,4);
      int w1=five?rect.w*28/100:rect.w*34/100;
      int rest=rect.w-w1;
      int count=five?4:3;
      int cw=rest/count;
      TextLeft(MakeUIRect(rect.x+inset,rect.y,MathMax(w1-inset*2,1),rect.h),col1,textColor,fontName,fontSize);
      string values[4]={col2,col3,col4,col5};
      int x=rect.x+w1;
      for(int i=0;i<count;i++)
      {
         int width=(i==count-1)?rect.x+rect.w-x:cw;
         TextRight(MakeUIRect(x,rect.y,MathMax(width-inset,1),rect.h),values[i],textColor,fontName,fontSize);
         x+=width;
      }
   }

   void TableRow(const UIRect &rect, string col1, string col2, string col3, string col4, string col5,
                 bool alternate, uint surfaceAlt, uint textColor, uint valueColor, string fontName, int fontSize)
   {
      if(alternate) FillRect(MakeUIRect(rect.x+1,rect.y,MathMax(rect.w-2,1),rect.h),surfaceAlt);
      bool five=(col5!="");
      int inset=MathMax(rect.h*10/29,4);
      int w1=five?rect.w*28/100:rect.w*34/100;
      int rest=rect.w-w1;
      int count=five?4:3;
      int cw=rest/count;
      TextLeft(MakeUIRect(rect.x+inset,rect.y,MathMax(w1-inset*2,1),rect.h),col1,textColor,fontName,fontSize);
      string values[4]={col2,col3,col4,col5};
      int x=rect.x+w1;
      for(int i=0;i<count;i++)
      {
         int width=(i==count-1)?rect.x+rect.w-x:cw;
         TextRight(MakeUIRect(x,rect.y,MathMax(width-inset,1),rect.h),values[i],valueColor,fontName,fontSize);
         x+=width;
      }
   }

   void Button(const UIRect &rect, string text, bool active, uint surface, uint activeFill, uint border, uint textColor, uint activeText, string fontName, int fontSize)
   {
      FillRoundRect(rect,MathMax(3,rect.h/5),active?activeFill:surface,active?activeFill:border);
      m_canvas.FontSet(fontName,fontSize);
      string shown=Ellipsize(text,MathMax(rect.w-8,1),fontName,fontSize);
      int tw=m_canvas.TextWidth(shown);
      int th=m_canvas.TextHeight(shown);
      m_canvas.TextOut(rect.x+MathMax((rect.w-tw)/2,2),rect.y+MathMax((rect.h-th)/2,1),shown,active?activeText:textColor);
   }

   void End(void)
   {
      if(!m_ready || m_updateCount>0) return;
      m_canvas.Update(false);
      m_updateCount++;
   }
};

PanelViewState CanvasPanelState;
PanelTheme CanvasPanelTheme;
PanelMetrics CanvasPanelMetrics;
PanelLayout CanvasPanelLayout;
PanelViewModel CanvasPanelModel;
UIHitRegion CanvasPanelHitRegions[];
CPanelRenderer CanvasPanelRenderer;
string CanvasResolvedFont="Microsoft YaHei UI";
int CanvasPanelDirty=PANEL_DIRTY_ALL;
const bool CANVAS_UI_PERF_LOG=false;
bool CanvasLegacyObjectsCleared=false;
bool CanvasNewsButtonsVisible=false;
string CanvasNewsButtonsSignature="";
bool CanvasMiniModelValid=false;
bool CanvasHoldingModelValid=false;
bool CanvasStatsModelValid=false;
bool CanvasPanelLayoutValid=false;
bool CanvasReviewCacheValid=false;
bool CanvasTrendCacheValid=false;
datetime CanvasLastDisplayedBeijingSecond=0;
string CanvasCachedBeijingClock="";
long CanvasStatsTradeGeneration=0;
ReviewViewCacheKey CanvasReviewCacheKey;
LifecycleReviewItem CanvasReviewCache[];
TrendViewCacheKey CanvasTrendCacheKey;
StatsTrendViewModel CanvasTrendCache;
int CanvasLastChartWidth=0;
int CanvasLastChartHeight=0;
double CanvasLastDpiScale=0.0;

bool RefreshCanvasPanelByDirtyFlags(bool force=false);

void CanvasUIPerfStage(string stage, ulong startedAt, ulong thresholdUs)
{
   if(!CANVAS_UI_PERF_LOG || startedAt<=0) return;
   ulong elapsed=GetMicrosecondCount()-startedAt;
   if(elapsed>=thresholdUs)
      PrintFormat("Canvas UI %s: %I64u us",stage,elapsed);
}

void MarkCanvasPanelDirty(int flags)
{
   CanvasPanelDirty|=flags;
}

void ResetCanvasReviewCacheKey(void)
{
   CanvasReviewCacheKey.period=-1;
   CanvasReviewCacheKey.filter=-1;
   CanvasReviewCacheKey.dayOffset=0;
   CanvasReviewCacheKey.weekOffset=0;
   CanvasReviewCacheKey.monthOffset=0;
   CanvasReviewCacheKey.tradeGeneration=-1;
   CanvasReviewCacheKey.symbol="";
   CanvasReviewCacheKey.serverStart=0;
   CanvasReviewCacheKey.serverEnd=0;
}

void InvalidateCanvasReviewCache(void)
{
   CanvasReviewCacheValid=false;
   ArrayResize(CanvasReviewCache,0);
   ResetCanvasReviewCacheKey();
}

void SyncCanvasStateFromLegacy(void)
{
   CanvasPanelState.page=当前面板页面;
   CanvasPanelState.displayMode=当前面板显示模式;
   CanvasPanelState.density=当前面板信息模式;
   CanvasPanelState.statsPeriod=当前统计周期;
   CanvasPanelState.statsFilter=当前统计筛选;
   CanvasPanelState.statsDetail=当前统计详情;
   if(使用新版Canvas面板 && (CanvasPanelState.statsDetail==统计详情_管理 || CanvasPanelState.statsDetail==统计详情_执行))
   {
      CanvasPanelState.statsDetail=统计详情_总览;
      当前统计详情=统计详情_总览;
   }
   CanvasPanelState.dayOffset=统计日期偏移天数;
   CanvasPanelState.weekOffset=统计周偏移周数;
   CanvasPanelState.monthOffset=统计月偏移月数;
   CanvasPanelState.reviewIndex=当前复盘序号;
   CanvasPanelState.panelX=当前面板左边距;
   CanvasPanelState.panelY=当前面板上边距;
}

void SyncLegacyStateFromCanvas(void)
{
   当前面板页面=CanvasPanelState.page;
   当前面板显示模式=CanvasPanelState.displayMode;
   当前面板信息模式=CanvasPanelState.density;
   当前统计周期=CanvasPanelState.statsPeriod;
   当前统计筛选=CanvasPanelState.statsFilter;
   当前统计详情=CanvasPanelState.statsDetail;
   统计日期偏移天数=CanvasPanelState.dayOffset;
   统计周偏移周数=CanvasPanelState.weekOffset;
   统计月偏移月数=CanvasPanelState.monthOffset;
   当前复盘序号=CanvasPanelState.reviewIndex;
   当前面板左边距=CanvasPanelState.panelX;
   当前面板上边距=CanvasPanelState.panelY;
}

void InitializeCanvasPanelArchitecture(void)
{
   SyncCanvasStateFromLegacy();
   CanvasPanelState.positionPage=0;
   CanvasPanelState.positionFilter=持仓筛选_全部;
   CanvasPanelState.pendingTrendPointIndex=-1;
   CanvasPanelState.selectedTrendPointIndex=-1;
   CanvasPanelState.trendSelectionValid=false;
   CanvasPanelState.trendSelectionMessage="";
   CanvasPanelState.statsActionMessage="";
   CanvasPanelState.trendSelectionGeneration=-1;
   CanvasPanelState.dragging=false;
   CanvasPanelState.hoverAction=PANEL_ACTION_NONE;
   CanvasPanelState.pressedAction=PANEL_ACTION_NONE;
   CanvasPanelState.lastClickTick=0;
   CanvasPanelState.lastClickX=-10000;
   CanvasPanelState.lastClickY=-10000;
   CanvasPanelState.lastClickAction=PANEL_ACTION_NONE;
   CanvasPanelState.suppressClickUntilTick=0;
   ArrayResize(CanvasPanelHitRegions,0);
   InvalidateCanvasReviewCache();
   ArrayResize(CanvasTrendCache.points,0);
   CanvasLegacyObjectsCleared=false;
   CanvasNewsButtonsVisible=(ObjectFind(0,"SMA_BTN_NEWS_FREEZE")>=0 ||
                             ObjectFind(0,"SMA_BTN_NEWS_RELEASE")>=0 ||
                             ObjectFind(0,"SMA_BTN_NEWS_CANCEL")>=0 ||
                             ObjectFind(0,"SMA_BTN_NEWS_FLAT")>=0);
   CanvasNewsButtonsSignature="";
   CanvasMiniModelValid=false;
   CanvasHoldingModelValid=false;
   CanvasStatsModelValid=false;
   CanvasPanelLayoutValid=false;
   CanvasTrendCacheValid=false;
   CanvasLastDisplayedBeijingSecond=0;
   CanvasCachedBeijingClock="";
   上次完整面板刷新毫秒=0;
   UpdateCanvasHeaderClockCache(false);
   CanvasStatsTradeGeneration=0;
   CanvasLastChartWidth=(int)ChartGetInteger(0,CHART_WIDTH_IN_PIXELS,0);
   CanvasLastChartHeight=(int)ChartGetInteger(0,CHART_HEIGHT_IN_PIXELS,0);
   CanvasLastDpiScale=MathMax(0.85,MathMin((double)TerminalInfoInteger(TERMINAL_SCREEN_DPI)/96.0,1.75));
   CanvasPanelDirty=PANEL_DIRTY_ALL;
}

struct TodayStats
{
   datetime bjStartServer;
   datetime bjEndServer;
   datetime bjDate;
   int      entries;
   int      closes;
   int      wins;
   int      losses;
   int      breakevens;
   double   lots;
   double   closeLots;
   double   profit;
   double   points;      // MT5最小报价点数，例如XAUUSD _Point=0.01时，价格差10=1000点
   double   priceDiff;   // 价格差，不除以_Point；例如4500到4510=10.00
   double   grossProfit;
   double   grossLoss;
   double   avgWin;
   double   avgLoss;
   double   profitFactor;
   double   payoffRatio;
   double   bestProfit;
   double   worstProfit;
   int      currentLossStreak;
   int      maxLossStreak;
   int      buyCloses;
   int      sellCloses;
   double   buyProfit;
   double   sellProfit;
   double   totalHoldMinutes;
   double   maxHoldMinutes;
   double   realizedEquityPeak;
   double   maxRealizedDrawdown;
};

TodayStats 缓存统计;
TodayStats 今日纪律缓存;
bool       今日纪律缓存有效 = false;
datetime   今日纪律缓存时间 = 0;

struct CloseDealStat
{
   ulong    deal;
   datetime time;
   double   profit;
   double   points;
   double   priceDiff;
   double   volume;
   double   holdMinutes;
   ENUM_DEAL_TYPE openType;
};

struct EntryDealStat
{
   ulong          positionId;
   datetime       time;
   double         price;
   ENUM_DEAL_TYPE type;
};

bool IsTeacherAutoShortMagic(const long magic)
{
   return (magic == TEACHER_AUTO_SHORT_MAGIC && magic != 手机标记挂单Magic);
}

bool PositionInScope()
{
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;

   long magic = (long)PositionGetInteger(POSITION_MAGIC);
   if(IsTeacherAutoShortMagic(magic))
   {
      ENUM_POSITION_TYPE autoType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(autoType == POSITION_TYPE_BUY && !管理多单) return false;
      if(autoType == POSITION_TYPE_SELL && !管理空单) return false;
      return true;
   }
   if(只管理手动单 && magic != 0)
      return false;
   if(!只管理手动单 && magic != 指定管理Magic)
      return false;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   if(type == POSITION_TYPE_BUY && !管理多单) return false;
   if(type == POSITION_TYPE_SELL && !管理空单) return false;

   return true;
}

bool HasManagedPosition()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionInScope())
         return true;
   }
   return false;
}

bool HasNonMarkerTradeOnCurrentSymbol()
{
   // 任何非手机标记的真实持仓都视为“用户已开始交易”，不受模板、Magic或托管范围限制。
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long magic = (long)PositionGetInteger(POSITION_MAGIC);
      string cmt = PositionGetString(POSITION_COMMENT);
      bool markerPosition = (magic == 手机标记挂单Magic && StringFind(cmt, "SMA_MARK_") == 0);
      if(!markerPosition) return true;
   }

   // 用户手动挂出的限价/止损单也算交易；只排除本EA自己的SMA_MARK_*提示挂单。
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;

      long magic = (long)OrderGetInteger(ORDER_MAGIC);
      string cmt = OrderGetString(ORDER_COMMENT);
      bool markerOrder = (magic == 手机标记挂单Magic && StringFind(cmt, "SMA_MARK_") == 0);
      if(!markerOrder) return true;
   }
   return false;
}

bool MagicInScope(long magic)
{
   if(IsTeacherAutoShortMagic(magic)) return true;
   if(只管理手动单 && magic != 0)
      return false;
   if(!只管理手动单 && magic != 指定管理Magic)
      return false;
   return true;
}

bool DealInScope(ulong deal)
{
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
      return false;
   if(!统计页仅统计受管Magic)
      return true; // 默认按当前图表品种汇总全部Magic，便于和MT5历史记录对账。

   long magic = (long)HistoryDealGetInteger(deal, DEAL_MAGIC);
   return MagicInScope(magic);
}

int FindState(ulong ticket)
{
   for(int i=0; i<ArraySize(states); i++)
   {
      if(states[i].ticket == ticket) return i;
   }
   return -1;
}

int FindConfirmedEntryTemplateStamp(ulong positionIdentifier)
{
   if(positionIdentifier == 0) return -1;
   for(int i=ArraySize(confirmedEntryTemplateStamps)-1; i>=0; i--)
      if(confirmedEntryTemplateStamps[i].positionIdentifier == positionIdentifier)
         return i;
   return -1;
}

void RememberConfirmedEntryTemplate(ulong positionIdentifier, 管理配置模板 tpl)
{
   if(positionIdentifier == 0) return;
   int idx = FindConfirmedEntryTemplateStamp(positionIdentifier);
   if(idx < 0)
   {
      idx = ArraySize(confirmedEntryTemplateStamps);
      ArrayResize(confirmedEntryTemplateStamps, idx+1);
      confirmedEntryTemplateStamps[idx].positionIdentifier = positionIdentifier;
   }
   confirmedEntryTemplateStamps[idx].templateId = (int)tpl;
   confirmedEntryTemplateStamps[idx].time = TimeCurrent();
}

int ConfirmedEntryTemplateOrCurrent(ulong positionIdentifier)
{
   int idx = FindConfirmedEntryTemplateStamp(positionIdentifier);
   if(idx >= 0)
      return confirmedEntryTemplateStamps[idx].templateId;
   return (int)当前参数配置模板;
}

void CleanupConfirmedEntryTemplateStamps()
{
   datetime now = TimeCurrent();
   for(int i=ArraySize(confirmedEntryTemplateStamps)-1; i>=0; i--)
   {
      if(now >= confirmedEntryTemplateStamps[i].time && now-confirmedEntryTemplateStamps[i].time > 10*60)
         ArrayRemove(confirmedEntryTemplateStamps, i, 1);
   }
}

int EnsureState(ulong ticket)
{
   int idx = FindState(ticket);
   if(idx >= 0) return idx;

   int n = ArraySize(states);
   ArrayResize(states, n + 1);
   states[n].ticket = ticket;
   states[n].positionIdentifier = PositionSelectByTicket(ticket) ? (ulong)PositionGetInteger(POSITION_IDENTIFIER) : 0;
   states[n].positionOpenTime = PositionSelectByTicket(ticket) ? (datetime)PositionGetInteger(POSITION_TIME) : 0;
   states[n].positionDirection = PositionSelectByTicket(ticket) ? (int)PositionGetInteger(POSITION_TYPE) : -1;
   states[n].adoptedTemplate = ConfirmedEntryTemplateOrCurrent(states[n].positionIdentifier);
   states[n].maxProfitPrice = 0.0;
   states[n].maxLossPrice = 0.0;
   states[n].recoveryArmed = false;
   states[n].recoveryArmedTime = 0;
   states[n].recoveryArmLossPrice = 0.0;
   states[n].recoveryArmTrigger = 0.0;
   states[n].maxProfitMoney = 0.0;
   states[n].maxLossMoney = 0.0;
   states[n].lifecycleRealizedNetMoney = 0.0;
   states[n].maxLifecycleProfitMoney = 0.0;
   states[n].maxLifecycleLossMoney = 0.0;
   states[n].lifecyclePnlEnvelopeInitialized = false;
   states[n].lastM1StructBarTime = 0;
   states[n].partialTPDone = false;
   states[n].initialVolume = PositionSelectByTicket(ticket) ? PositionGetDouble(POSITION_VOLUME) : 0.0;
   states[n].partialTPStage = 0;
   states[n].lastPartialTPTime = 0;
   states[n].lastPartialTPProfit = 0.0;
   states[n].shortRiskReady = false;
   states[n].shortInitialRisk = 0.0;
   states[n].shortInitialSL = 0.0;
   states[n].shortActualInitialSL = 0.0;
   states[n].shortInitialSLConfirmed = false;
   states[n].shortRiskUnknown = false;
   states[n].shortStateManaged = false;
   states[n].teacherActivePlan =
      IsTeacherAutoShortMagic((long)PositionGetInteger(POSITION_MAGIC)) &&
      StringFind(PositionGetString(POSITION_COMMENT), "TEACHER_ACTIVE_") == 0;
   states[n].teacherPlanInitialized = false;
   states[n].teacherPlanValid = false;
   states[n].teacherPlanSignature = 0;
   states[n].teacherPlanMode = 老师点位辅助_仅TP;
   states[n].teacherPrimaryTP = 0.0;
   states[n].teacherSecondaryTP = 0.0;
   states[n].partialRequestPending = false;
   states[n].pendingPartialStage = 0;
   states[n].pendingPartialVolume = 0.0;
   states[n].pendingPartialFilledVolume = 0.0;
   states[n].pendingPartialStartVolume = 0.0;
   states[n].pendingPartialRequestTime = 0;
   states[n].partialFilledVolumeStage1 = 0.0;
   states[n].partialFilledVolumeStage2 = 0.0;
   states[n].partialFilledVolumeStage3 = 0.0;
   states[n].lastShortDeal = 0;
   states[n].runnerMode = 短线尾仓_固定TP;
   states[n].fixedTPRemoved = false;
   states[n].fastProtectionActivated = false;
   states[n].fastProtectionTime = 0;
   states[n].confirmedMarketRegime = 短线环境_未知;
   states[n].candidateMarketRegime = 短线环境_未知;
   states[n].candidateRegimeCount = 0;
   states[n].regimeChangedTime = 0;
   states[n].tradeArchetype = 短线类型_未知;
   states[n].trendRiskReady = false;
   states[n].trendRiskUnknown = false;
   states[n].trendInitialRisk = 0.0;
   states[n].trendInitialSL = 0.0;
   states[n].trendHighSinceOpen = 0.0;
   states[n].trendLowSinceOpen = 0.0;
   states[n].lifecycleLastSnapshotTime = 0;
   states[n].lifecyclePhase = 生命周期_刚接管;
   states[n].protectionStage = 保护阶段_无有效SL;
   states[n].pendingAction = 待确认动作_无;
   states[n].pendingActionTime = 0;
   states[n].pendingRequestId = 0;
   states[n].pendingOrder = 0;
   states[n].pendingDeal = 0;
   states[n].pendingRequestedSL = 0.0;
   states[n].pendingRequestedTP = 0.0;
   states[n].pendingRequestedVolume = 0.0;
   states[n].pendingStartVolume = 0.0;
   states[n].pendingSLSource = SL来源_无;
   states[n].pendingTPSource = TP来源_无;
   states[n].pendingExitIntent = 退出意图_无;
   states[n].pendingFastProtection = false;
   states[n].pendingFastProtectionSL = 0.0;
   states[n].pendingFixedTPRemoval = false;
   states[n].closeDetectedTime = 0;
   states[n].finalizeRetryCount = 0;
   states[n].tradeFinalized = false;
   states[n].slModifyCount = 0;
   states[n].tpModifyCount = 0;
   states[n].partialFillCount = 0;
   states[n].lastConfirmedSLSource = SL来源_无;
   states[n].lastConfirmedTPSource = TP来源_无;
   states[n].exitIntent = 退出意图_无;
   states[n].lastManagedModifyTime = 0;
   states[n].lastKnownVolume = PositionSelectByTicket(ticket) ? PositionGetDouble(POSITION_VOLUME) : 0.0;
   states[n].lastKnownOpenPrice = PositionSelectByTicket(ticket) ? PositionGetDouble(POSITION_PRICE_OPEN) : 0.0;
   states[n].externalVolumeChangeDetected = false;
   states[n].externalVolumeChangeTime = 0;
   states[n].pendingExitFilledVolume = 0.0;
   states[n].pendingRetryCount = 0;
   states[n].lastLifecycleExitDeal = 0;
   states[n].lastRegimeClosedBarTime = 0;
   states[n].nettingReversalDetected = false;
   states[n].lifecycleSegmentStartTime = 0;
   states[n].floatingProfitSeconds = 0.0;
   states[n].floatingLossSeconds = 0.0;
   states[n].floatingFlatSeconds = 0.0;
   states[n].longestFloatingLossSeconds = 0.0;
   states[n].firstFloatingProfitTime = 0;
   states[n].floatingTimingObservationStartTime = 0;
   states[n].floatingTimingHasData = false;
   states[n].floatingTimingFinalized = false;
   states[n].floatingTimingCurrentState = 浮动状态_未知;
   states[n].floatingTimingCurrentStateSeconds = 0.0;
   states[n].floatingTimingLastSampleMs = 0;
   states[n].floatingTimingSampleReady = false;
   states[n].floatingTimingLastPersistObservedSeconds = 0.0;
   states[n].floatingTimingSwitchCount = 0;
   states[n].floatingTimingEntryCostAttempted = false;
   states[n].stateDirty = false;
   states[n].lastStateSaveTime = 0;
   states[n].stateVersion = 0;
   states[n].lastSavedVersion = 0;
   states[n].entryCostCacheReady = false;
   states[n].cachedEntryCost = 0.0;
   states[n].entryCostCacheTime = 0;
   states[n].entryCostCacheVolume = 0.0;
   states[n].entryCostCacheVersion = 0;
   ShortStateLoad(n);
   if(states[n].positionIdentifier > 0)
      TradeJournalWriteLifecycle(n, "POSITION_ADOPTED",
                                 StringFormat("ea_started_or_position_detected;template=%d", states[n].adoptedTemplate));
   return n;
}

ulong FindOpenPositionTicketByIdentifier(ulong positionIdentifier)
{
   if(positionIdentifier == 0) return 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == positionIdentifier)
         return ticket;
   }
   return 0;
}

void FreezeConfirmedEntryTemplate(ulong positionIdentifier, ENUM_DEAL_ENTRY entry)
{
   if(positionIdentifier == 0) return;
   管理配置模板 entryTemplate = 当前参数配置模板;
   ulong ticket = FindOpenPositionTicketByIdentifier(positionIdentifier);
   if(ticket > 0 && PositionSelectByTicket(ticket) &&
      IsTeacherAutoShortMagic((long)PositionGetInteger(POSITION_MAGIC)))
      entryTemplate = 配置_黄金超短快保;
   RememberConfirmedEntryTemplate(positionIdentifier, entryTemplate);
   if(ticket == 0 || !PositionSelectByTicket(ticket) || !PositionInScope()) return;

   int stateIdx = EnsureState(ticket);
   // 真实加仓/反转成交都会改变当前组合；回本资格必须由新组合重新经历深亏后取得。
   if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT)
   {
      states[stateIdx].recoveryArmed = false;
      states[stateIdx].recoveryArmedTime = 0;
      states[stateIdx].recoveryArmLossPrice = 0.0;
      states[stateIdx].recoveryArmTrigger = 0.0;
   }
   if(entry == DEAL_ENTRY_INOUT && states[stateIdx].adoptedTemplate != (int)entryTemplate)
   {
      states[stateIdx].adoptedTemplate = (int)entryTemplate;
      states[stateIdx].shortRiskReady = false;
      states[stateIdx].shortRiskUnknown = false;
      states[stateIdx].shortInitialRisk = 0.0;
      states[stateIdx].shortInitialSL = 0.0;
      states[stateIdx].shortActualInitialSL = 0.0;
      states[stateIdx].shortInitialSLConfirmed = false;
      states[stateIdx].fixedTPRemoved = false;
      states[stateIdx].partialTPDone = false;
      states[stateIdx].partialTPStage = 0;
   }
   if(entry == DEAL_ENTRY_INOUT)
   {
      states[stateIdx].trendRiskReady = false;
      states[stateIdx].trendRiskUnknown = false;
      states[stateIdx].trendInitialRisk = 0.0;
      states[stateIdx].trendInitialSL = 0.0;
      states[stateIdx].trendHighSinceOpen = 0.0;
      states[stateIdx].trendLowSinceOpen = 0.0;
   }

   bool becameManaged = !states[stateIdx].shortStateManaged;
   states[stateIdx].shortStateManaged = true;
   if(becameManaged || entry == DEAL_ENTRY_INOUT)
   {
      ResetShortTeacherPlan(stateIdx);
      if(entryTemplate == 配置_黄金超短快保 && PositionSelectByTicket(ticket))
         FreezeShortTeacherPlan(stateIdx,
                                (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE),
                                PositionGetDouble(POSITION_PRICE_OPEN));
   }
   MarkShortStateDirty(stateIdx);
   ShortStateSave(stateIdx);
   if(becameManaged || entry == DEAL_ENTRY_INOUT)
      TradeJournalWriteLifecycle(stateIdx, "TEMPLATE_FROZEN_AT_ENTRY",
                                 StringFormat("position_id=%I64u;entry=%d;template=%d",
                                              positionIdentifier, entry, states[stateIdx].adoptedTemplate));
}

bool IsTradeRetcodeAccepted(uint retcode)
{
   return (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED ||
           retcode == TRADE_RETCODE_DONE_PARTIAL || retcode == TRADE_RETCODE_NO_CHANGES);
}

void ClearPendingTradeAction(int stateIdx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return;
   states[stateIdx].pendingAction = 待确认动作_无;
   states[stateIdx].pendingActionTime = 0;
   states[stateIdx].pendingRequestId = 0;
   states[stateIdx].pendingOrder = 0;
   states[stateIdx].pendingDeal = 0;
   states[stateIdx].pendingRequestedSL = 0.0;
   states[stateIdx].pendingRequestedTP = 0.0;
   states[stateIdx].pendingRequestedVolume = 0.0;
   states[stateIdx].pendingStartVolume = 0.0;
   states[stateIdx].pendingSLSource = SL来源_无;
   states[stateIdx].pendingTPSource = TP来源_无;
   states[stateIdx].pendingExitIntent = 退出意图_无;
   states[stateIdx].pendingFastProtection = false;
   states[stateIdx].pendingFastProtectionSL = 0.0;
   states[stateIdx].pendingFixedTPRemoval = false;
   MarkShortStateDirty(stateIdx);
}

void SetPendingTradeAction(int stateIdx, int action, double requestedSL, double requestedTP,
                           double requestedVolume, double startVolume, int slSource, int tpSource,
                           int exitIntent, bool fastProtectionIntent=false, double fastProtectionTarget=0.0,
                           bool fixedTPRemovalIntent=false)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return;
   states[stateIdx].pendingAction = action;
   states[stateIdx].pendingActionTime = TimeCurrent();
   states[stateIdx].pendingOrder = manageTrade.ResultOrder();
   states[stateIdx].pendingDeal = manageTrade.ResultDeal();
   states[stateIdx].pendingRequestedSL = requestedSL;
   states[stateIdx].pendingRequestedTP = requestedTP;
   states[stateIdx].pendingRequestedVolume = requestedVolume;
   states[stateIdx].pendingStartVolume = startVolume;
   states[stateIdx].pendingSLSource = slSource;
   states[stateIdx].pendingTPSource = tpSource;
   states[stateIdx].pendingExitIntent = exitIntent;
   states[stateIdx].pendingFastProtection = fastProtectionIntent;
   states[stateIdx].pendingFastProtectionSL = fastProtectionTarget;
   states[stateIdx].pendingFixedTPRemoval = fixedTPRemovalIntent;
   MarkShortStateDirty(stateIdx);
}

bool TrendLongSLIsRiskSide(ENUM_POSITION_TYPE type, double openPrice, double sl)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tolerance = MathMax(_Point, tickSize > 0.0 ? tickSize : _Point) * 0.5;
   if(openPrice <= 0.0 || sl <= 0.0) return false;
   if(type == POSITION_TYPE_BUY) return sl < openPrice-tolerance;
   if(type == POSITION_TYPE_SELL) return sl > openPrice+tolerance;
   return false;
}

bool TrendFreezeInitialRiskFromServer(int stateIdx, string source)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) ||
      states[stateIdx].adoptedTemplate != (int)配置_黄金稳健托管 ||
      states[stateIdx].trendRiskReady ||
      states[stateIdx].trendRiskUnknown ||
      !PositionSelectByTicket(states[stateIdx].ticket)) return false;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double actualSL = PositionGetDouble(POSITION_SL);
   if(!TrendLongSLIsRiskSide(type, openPrice, actualSL)) return false;

   double risk = MathAbs(openPrice-actualSL);
   if(risk <= MathMax(_Point, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE))) return false;

   states[stateIdx].trendInitialSL = actualSL;
   states[stateIdx].trendInitialRisk = risk;
   states[stateIdx].trendRiskReady = true;
   states[stateIdx].protectionStage = 保护阶段_初始风险;
   if(states[stateIdx].lifecyclePhase == 生命周期_刚接管 ||
      states[stateIdx].lifecyclePhase == 生命周期_风险建立中 ||
      states[stateIdx].lifecyclePhase == 生命周期_异常待恢复)
      states[stateIdx].lifecyclePhase = 生命周期_正常管理;
   MarkShortStateDirty(stateIdx);
   ShortStateSave(stateIdx);
   TradeJournalWriteLifecycle(stateIdx, "TREND_INITIAL_RISK_FROZEN",
                              StringFormat("source=%s;server_sl=%.5f;initial_r=%.5f", source, actualSL, risk));
   return true;
}

// 重新读取服务器持仓确认，避免CTrade调用返回true时内部状态提前完成。
void ReconcilePendingTradeAction(int stateIdx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || states[stateIdx].pendingAction == 待确认动作_无) return;
   if(!PositionSelectByTicket(states[stateIdx].ticket))
   {
      if(states[stateIdx].pendingAction == 待确认动作_全部平仓)
      {
         states[stateIdx].lifecyclePhase = 生命周期_等待最终结算;
         MarkShortStateDirty(stateIdx);
      }
      return;
   }
   double actualSL = PositionGetDouble(POSITION_SL);
   double actualTP = PositionGetDouble(POSITION_TP);
   double tolerance = MathMax(_Point * 1.5, SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) * 1.5);
   if(states[stateIdx].pendingAction == 待确认动作_部分平仓)
   {
      if(!states[stateIdx].partialRequestPending) ClearPendingTradeAction(stateIdx);
      return;
   }
   if(states[stateIdx].pendingAction == 待确认动作_全部平仓) return;

   bool slConfirmed = (states[stateIdx].pendingRequestedSL <= 0.0 || MathAbs(actualSL-states[stateIdx].pendingRequestedSL) <= tolerance);
   if(!slConfirmed && actualSL > 0.0 && states[stateIdx].pendingRequestedSL > 0.0)
   {
      slConfirmed = (states[stateIdx].positionDirection == POSITION_TYPE_BUY) ?
                    (actualSL >= states[stateIdx].pendingRequestedSL-tolerance) :
                    (actualSL <= states[stateIdx].pendingRequestedSL+tolerance);
   }
   bool fastSLValid = MathIsValidNumber(actualSL) && actualSL > 0.0 &&
                       MathIsValidNumber(states[stateIdx].pendingFastProtectionSL) &&
                       states[stateIdx].pendingFastProtectionSL > 0.0;
   if(states[stateIdx].pendingFastProtection)
      slConfirmed = fastSLValid &&
                     ((states[stateIdx].positionDirection == POSITION_TYPE_BUY && actualSL >= states[stateIdx].pendingFastProtectionSL-tolerance) ||
                      (states[stateIdx].positionDirection == POSITION_TYPE_SELL && actualSL <= states[stateIdx].pendingFastProtectionSL+tolerance));
   bool tpConfirmed = (states[stateIdx].pendingRequestedTP < 0.0 || MathAbs(actualTP-states[stateIdx].pendingRequestedTP) <= tolerance);
   bool fastConfirmed = !states[stateIdx].pendingFastProtection ||
                         (fastSLValid &&
                          ((states[stateIdx].positionDirection == POSITION_TYPE_BUY && actualSL >= states[stateIdx].pendingFastProtectionSL-tolerance) ||
                           (states[stateIdx].positionDirection == POSITION_TYPE_SELL && actualSL <= states[stateIdx].pendingFastProtectionSL+tolerance)));
   bool tpRemovalConfirmed = !states[stateIdx].pendingFixedTPRemoval || actualTP <= tolerance;
   if(!slConfirmed || !tpConfirmed || !fastConfirmed || !tpRemovalConfirmed) return;

   if(states[stateIdx].pendingRequestedSL > 0.0 &&
      states[stateIdx].pendingSLSource == SL来源_初始结构)
      TrendFreezeInitialRiskFromServer(stateIdx, "server_modify_confirmed");

   if(states[stateIdx].pendingRequestedSL > 0.0 && states[stateIdx].pendingSLSource != SL来源_无)
   {
      states[stateIdx].lastConfirmedSLSource = states[stateIdx].pendingSLSource;
      states[stateIdx].slModifyCount++;
      int source = states[stateIdx].pendingSLSource;
      if(source == SL来源_初始ATR || source == SL来源_初始结构 || source == SL来源_初始箱体)
         states[stateIdx].protectionStage = 保护阶段_初始风险;
      else if(source == SL来源_快速净保本 || source == SL来源_快速微型箱体 || source == SL来源_常规保本)
         states[stateIdx].protectionStage = 保护阶段_净保本;
      else if(source == SL来源_M1前柱结构 || source == SL来源_微型箱体尾仓 ||
              source == SL来源_趋势ATR追踪 || source == SL来源_老师突破保护)
         states[stateIdx].protectionStage = 保护阶段_结构追踪;
      else if(source == SL来源_分批后保护 || source == SL来源_浮盈回撤锁定 || source == SL来源_超时保本 || source == SL来源_其他)
         states[stateIdx].protectionStage = 保护阶段_利润锁定;
   }
   if(states[stateIdx].pendingRequestedTP >= 0.0 && states[stateIdx].pendingTPSource != TP来源_无)
   {
      states[stateIdx].lastConfirmedTPSource = states[stateIdx].pendingTPSource;
      states[stateIdx].tpModifyCount++;
   }
   if(states[stateIdx].pendingFastProtection)
   {
      states[stateIdx].fastProtectionActivated = true;
      states[stateIdx].fastProtectionTime = TimeCurrent();
      TradeJournalWriteLifecycle(stateIdx, "FAST_PROTECTION_CONFIRMED",
                                 StringFormat("server_sl=%.5f;target_sl=%.5f;source=%d", actualSL, states[stateIdx].pendingFastProtectionSL, states[stateIdx].pendingSLSource));
   }
   if(states[stateIdx].pendingFixedTPRemoval)
   {
      states[stateIdx].fixedTPRemoved = true;
      TradeJournalWriteLifecycle(stateIdx, "FIXED_TP_REMOVE_CONFIRMED", "server_tp=0");
   }
   else if(states[stateIdx].fixedTPRemoved && actualTP > tolerance &&
           (states[stateIdx].pendingTPSource == TP来源_箱体目标 ||
            states[stateIdx].pendingTPSource == TP来源_动态主TP ||
            states[stateIdx].pendingTPSource == TP来源_老师点位))
   {
      states[stateIdx].fixedTPRemoved = false;
      TradeJournalWriteLifecycle(stateIdx, "FIXED_TP_RESTORE_CONFIRMED",
                                 StringFormat("server_tp=%.5f;tp_source=%d", actualTP, states[stateIdx].pendingTPSource));
   }
   if(states[stateIdx].lifecyclePhase == 生命周期_刚接管 || states[stateIdx].lifecyclePhase == 生命周期_风险建立中)
      states[stateIdx].lifecyclePhase = 生命周期_正常管理;
   TradeJournalWriteLifecycle(stateIdx, "SLTP_MODIFY_CONFIRMED",
                              StringFormat("requested_sl=%.5f;actual_sl=%.5f;sl_source=%d;requested_tp=%.5f;actual_tp=%.5f;tp_source=%d",
                                           states[stateIdx].pendingRequestedSL, actualSL, states[stateIdx].pendingSLSource,
                                           states[stateIdx].pendingRequestedTP, actualTP, states[stateIdx].pendingTPSource));
   ClearPendingTradeAction(stateIdx);
   ShortStateSave(stateIdx);
}

bool SubmitManagedPositionModify(ulong ticket, int stateIdx, double requestedSL, double requestedTP,
                                 int slSource, int tpSource, bool fastProtectionIntent=false,
                                 double fastProtectionTarget=0.0, bool fixedTPRemovalIntent=false)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || !PositionSelectByTicket(ticket)) return false;
   states[stateIdx].shortStateManaged = true;
   double oldSL = PositionGetDouble(POSITION_SL), oldTP = PositionGetDouble(POSITION_TP);
   manageTrade.SetDeviationInPoints(30);
   bool sent = manageTrade.PositionModify(ticket, requestedSL, requestedTP);
   uint retcode = manageTrade.ResultRetcode();
   string detail = StringFormat("old_sl=%.5f;requested_sl=%.5f;sl_source=%d;old_tp=%.5f;requested_tp=%.5f;tp_source=%d;retcode=%u;result_comment=%s;order=%I64u;deal=%I64u",
                                oldSL, requestedSL, slSource, oldTP, requestedTP, tpSource, retcode,
                                manageTrade.ResultComment(), manageTrade.ResultOrder(), manageTrade.ResultDeal());
   if(!sent || !IsTradeRetcodeAccepted(retcode))
   {
      TradeJournalWriteLifecycle(stateIdx, "SLTP_MODIFY_FAILED", detail);
      if(fastProtectionIntent) TradeJournalWriteLifecycle(stateIdx, "FAST_PROTECTION_FAILED", detail);
      if(fixedTPRemovalIntent) TradeJournalWriteLifecycle(stateIdx, "FIXED_TP_REMOVE_FAILED", detail);
      return false;
   }
   int action = fastProtectionIntent ? 待确认动作_快速保护 :
                (fixedTPRemovalIntent ? 待确认动作_撤销固定TP : 待确认动作_SLTP修改);
   SetPendingTradeAction(stateIdx, action, requestedSL, requestedTP, 0.0, PositionGetDouble(POSITION_VOLUME),
                         slSource, tpSource, 退出意图_无, fastProtectionIntent, fastProtectionTarget, fixedTPRemovalIntent);
   TradeJournalWriteLifecycle(stateIdx, "SLTP_MODIFY_REQUESTED", detail);
   if(fastProtectionIntent) TradeJournalWriteLifecycle(stateIdx, "FAST_PROTECTION_REQUESTED", detail);
   if(fixedTPRemovalIntent) TradeJournalWriteLifecycle(stateIdx, "FIXED_TP_REMOVE_REQUESTED", detail);
   if(!fixedTPRemovalIntent && states[stateIdx].fixedTPRemoved && requestedTP > 0.0 &&
      (tpSource == TP来源_箱体目标 || tpSource == TP来源_动态主TP || tpSource == TP来源_老师点位))
      TradeJournalWriteLifecycle(stateIdx, "FIXED_TP_RESTORE_REQUESTED", detail);
   states[stateIdx].lastManagedModifyTime = TimeCurrent();
   ShortStateSave(stateIdx);
   return true;
}

bool SubmitManagedPartialClose(ulong ticket, int stateIdx, double closeVolume, int partialStage,
                               int exitIntent, string reason)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || !PositionSelectByTicket(ticket) ||
      states[stateIdx].partialRequestPending || states[stateIdx].pendingAction != 待确认动作_无) return false;
   states[stateIdx].shortStateManaged = true;
   double startVolume = PositionGetDouble(POSITION_VOLUME);
   manageTrade.SetDeviationInPoints(30);
   bool sent = false;
   uint retcode = 0;
   string resultComment = "";
   ulong resultOrder = 0;
   ulong resultDeal = 0;
   if(IsHedgingAccount())
   {
      sent = manageTrade.PositionClosePartial(ticket, closeVolume);
      retcode = manageTrade.ResultRetcode();
      resultComment = manageTrade.ResultComment();
      resultOrder = manageTrade.ResultOrder();
      resultDeal = manageTrade.ResultDeal();
   }
   else
   {
      ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      request.action = TRADE_ACTION_DEAL;
      request.position = ticket; // 绑定现有净额持仓；仓位已消失时应拒绝，不能意外反向开仓。
      request.symbol = _Symbol;
      request.magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      request.volume = MathMin(closeVolume, startVolume);
      request.deviation = 30;
      request.type = positionType == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      request.price = positionType == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      long filling = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
      if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) request.type_filling = ORDER_FILLING_FOK;
      else if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) request.type_filling = ORDER_FILLING_IOC;
      else request.type_filling = ORDER_FILLING_RETURN;
      request.comment = "SMA_NETTING_PARTIAL";
      sent = OrderSend(request, result);
      retcode = result.retcode;
      resultComment = result.comment;
      resultOrder = result.order;
      resultDeal = result.deal;
   }
   if(!sent || !IsTradeRetcodeAccepted(retcode))
   {
      TradeJournalWriteLifecycle(stateIdx, "PARTIAL_CLOSE_FAILED",
                                 StringFormat("stage=%d;requested_volume=%.2f;retcode=%u;result_comment=%s", partialStage, closeVolume, retcode, resultComment));
      return false;
   }
   states[stateIdx].partialRequestPending = true;
   states[stateIdx].pendingPartialStage = partialStage;
   states[stateIdx].pendingPartialVolume = closeVolume;
   states[stateIdx].pendingPartialFilledVolume = 0.0;
   states[stateIdx].pendingPartialStartVolume = startVolume;
   states[stateIdx].pendingPartialRequestTime = TimeCurrent();
   SetPendingTradeAction(stateIdx, 待确认动作_部分平仓, 0.0, 0.0, closeVolume, startVolume,
                          SL来源_无, TP来源_无, exitIntent);
   states[stateIdx].pendingOrder = resultOrder;
   states[stateIdx].pendingDeal = resultDeal;
   TradeJournalWriteLifecycle(stateIdx, "PARTIAL_CLOSE_REQUESTED",
                              StringFormat("stage=%d;requested_volume=%.2f;reason=%s;retcode=%u;order=%I64u;deal=%I64u",
                                            partialStage, closeVolume, reason, retcode, resultOrder, resultDeal));
   states[stateIdx].lastManagedModifyTime = TimeCurrent();
   ShortStateSave(stateIdx);
   return true;
}

bool SubmitManagedFullClose(ulong ticket, int stateIdx, int exitIntent, string reason)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || !PositionSelectByTicket(ticket) ||
      states[stateIdx].pendingAction == 待确认动作_全部平仓) return false;
   states[stateIdx].shortStateManaged = true;
   int preemptedAction = states[stateIdx].pendingAction;
   bool preemptedPartial = states[stateIdx].partialRequestPending;
   double startVolume = PositionGetDouble(POSITION_VOLUME);
   manageTrade.SetDeviationInPoints(30);
   bool sent = manageTrade.PositionClose(ticket);
   uint retcode = manageTrade.ResultRetcode();
   if(!sent || !IsTradeRetcodeAccepted(retcode))
   {
      TradeJournalWriteLifecycle(stateIdx, "FULL_CLOSE_FAILED",
                                 StringFormat("reason=%s;retcode=%u;result_comment=%s", reason, retcode, manageTrade.ResultComment()));
      return false;
   }
   if(preemptedAction != 待确认动作_无 && preemptedAction != 待确认动作_全部平仓)
      TradeJournalWriteLifecycle(stateIdx, "ACTION_PREEMPTED",
                                 StringFormat("old_action=%d;new_action=%d;reason=%s", preemptedAction, 待确认动作_全部平仓, reason));
   if(preemptedPartial)
   {
      states[stateIdx].partialRequestPending = false;
      states[stateIdx].pendingPartialStage = 0;
      states[stateIdx].pendingPartialVolume = 0.0;
      states[stateIdx].pendingPartialFilledVolume = 0.0;
      states[stateIdx].pendingPartialStartVolume = 0.0;
      states[stateIdx].pendingPartialRequestTime = 0;
   }
   if(states[stateIdx].lifecyclePhase != 生命周期_退出请求中)
   {
      states[stateIdx].pendingExitFilledVolume = 0.0;
      states[stateIdx].pendingRetryCount = 0;
   }
   states[stateIdx].lifecyclePhase = 生命周期_退出请求中;
   states[stateIdx].exitIntent = exitIntent;
   SetPendingTradeAction(stateIdx, 待确认动作_全部平仓, 0.0, 0.0, startVolume, startVolume,
                         SL来源_无, TP来源_无, exitIntent);
   TradeJournalWriteLifecycle(stateIdx, "FULL_CLOSE_REQUESTED",
                              StringFormat("reason=%s;requested_volume=%.2f;retcode=%u;order=%I64u;deal=%I64u", reason, startVolume,
                                            retcode, manageTrade.ResultOrder(), manageTrade.ResultDeal()));
   states[stateIdx].lastManagedModifyTime = TimeCurrent();
   ShortStateSave(stateIdx);
   return true;
}

void CleanupStates()
{
   for(int i=ArraySize(states)-1; i>=0; i--)
   {
       if(!SelectPositionForShortState(i))
      {
         FinalizeFloatingPnlTiming(i);
         if(states[i].closeDetectedTime == 0)
         {
            states[i].closeDetectedTime = TimeCurrent();
            states[i].lifecyclePhase = 生命周期_等待最终结算;
            TradeJournalWriteLifecycle(i, "POSITION_CLOSE_DETECTED", "position_no_longer_visible_to_terminal;waiting_history_finalization");
            ShortStateSave(i);
         }
         if(!FinalizeTradeLifecycle(i))
         {
            states[i].finalizeRetryCount++;
            MarkShortStateDirty(i);
            if(states[i].finalizeRetryCount == 1 || states[i].finalizeRetryCount % 15 == 0)
               TradeJournalWriteLifecycle(i, "FINALIZE_RETRY", StringFormat("retry=%d", states[i].finalizeRetryCount));
            continue;
         }
         if(states[i].shortStateManaged) ShortStateDelete(states[i].positionIdentifier);
         int last = ArraySize(states)-1;
         if(i != last) states[i] = states[last];
         ArrayResize(states,last);
      }
   }
}

string FormatSpreadText(double spread)
{
   if(忽略点差过滤)
      return StringFormat("点差 %.0f(忽略)", spread);
   return StringFormat("点差 %.0f/%d", spread, 最大点差点数);
}

bool SpreadOK()
{
   if(忽略点差过滤) return true;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0) return false;
   return ((ask - bid) / _Point <= 最大点差点数);
}

double CurrentSpreadPoints()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0 || _Point <= 0.0) return 0.0;
   return (ask - bid) / _Point;
}

double CurrentSpreadPrice()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return 0.0;
   return MathMax(ask - bid, 0.0);
}

bool ModifyFrequencyOK(int stateIdx)
{
   if(最小修改间隔秒 <= 0) return true;
   if(stateIdx >= 0 && stateIdx < ArraySize(states))
   {
      if(states[stateIdx].lastManagedModifyTime == 0) return true;
      return (TimeCurrent() - states[stateIdx].lastManagedModifyTime >= 最小修改间隔秒);
   }
   return false;
}

double ClampDouble(double value, double minValue, double maxValue)
{
   if(maxValue < minValue) maxValue = minValue;
   return MathMax(minValue, MathMin(value, maxValue));
}

double GetRecentM1RangeAverage(int bars=3)
{
   int n = MathMax(1, bars);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, n, rates);
   if(copied <= 0) return 0.0;

   double sum = 0.0;
   for(int i=0; i<copied; i++)
      sum += MathMax(0.0, rates[i].high - rates[i].low);
   return sum / copied;
}

double GetShortLineVolatilityUnit(double atr)
{
   double recentRange = GetRecentM1RangeAverage(3);
   double unit = MathMax(atr, recentRange);
   if(unit <= 0.0) unit = MathMax(支撑压力合并距离价格, 1.0);
   return unit;
}

double ShortLineDynamicInitialSL(double atr, ENUM_POSITION_TYPE type)
{
   double unit = GetShortLineVolatilityUnit(atr);
   double factor = MathMax(短线单初始SL_ATR倍数, 0.50);
   bool trendWith = ShortLineTrendWithPosition(type);
   bool momentumWith = ShortLineM1MomentumWithPosition(type);

   // 顺势冲量给更大呼吸空间；无趋势/无动能时仍保留最低风险宽度，避免M1噪声直接扫损。
   if(trendWith && momentumWith) factor += 0.20;
   else if(!trendWith && !momentumWith) factor = MathMax(factor - 0.10, 0.50);

   return ClampDouble(unit * factor,
                      MathMax(短线单初始SL最小价格, 0.10),
                      MathMax(短线单初始SL最大价格, 短线单初始SL最小价格));
}

double ShortLineGetRisk(int stateIdx, ENUM_POSITION_TYPE type, double openPrice, double slPrice, double atr)
{
   if(stateIdx >= 0 && stateIdx < ArraySize(states) && states[stateIdx].shortRiskReady &&
      states[stateIdx].shortInitialRisk > 0.0)
      return states[stateIdx].shortInitialRisk;
   return 0.0; // 未经服务器POSITION_SL确认时，绝不以ATR或旧SL猜测R。
}

bool ShortSpreadAllowsNormalManagement()
{
   return SpreadOK();
}

bool ShortSpreadAllowsEmergencyManagement()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   return (bid > 0.0 && ask > bid);
}

bool ShortSLIsRiskSide(ENUM_POSITION_TYPE type, double openPrice, double sl)
{
   return (type == POSITION_TYPE_BUY && sl > 0.0 && sl < openPrice - _Point) ||
          (type == POSITION_TYPE_SELL && sl > openPrice + _Point);
}

double ShortEmergencySLPrice(ENUM_POSITION_TYPE type, double openPrice, double atr)
{
   double brokerDistance = MathMax((double)MathMax((int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                                                    (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)) * _Point,
                                     _Point * 5.0);
   double distance = MathMax(MathMax(MathMax(atr, GetShortLineVolatilityUnit(atr)) * MathMax(短线单灾难SL_ATR倍数, 1.0),
                                      CurrentSpreadPrice() * MathMax(短线单灾难SL点差倍数, 1.0)), brokerDistance);
   return NormalizePrice(type == POSITION_TYPE_BUY ? openPrice-distance : openPrice+distance);
}

bool ShortConfirmInitialSL(int stateIdx, ENUM_POSITION_TYPE type, double openPrice)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || !PositionSelectByTicket(states[stateIdx].ticket)) return false;
   double actualSL = PositionGetDouble(POSITION_SL);
   if(!ShortSLIsRiskSide(type, openPrice, actualSL)) return false;
   states[stateIdx].shortActualInitialSL = actualSL;
   states[stateIdx].shortInitialSLConfirmed = true;
   states[stateIdx].shortInitialRisk = MathAbs(openPrice-actualSL);
   states[stateIdx].shortRiskReady = (states[stateIdx].shortInitialRisk > _Point);
   states[stateIdx].shortRiskUnknown = !states[stateIdx].shortRiskReady;
   MarkShortStateDirty(stateIdx);
   if(states[stateIdx].shortRiskReady)
   {
      states[stateIdx].protectionStage = 保护阶段_初始风险;
      states[stateIdx].lifecyclePhase = 生命周期_正常管理;
      PrintFormat("[短线风险] 初始SL真实确认 ticket=%I64u desired=%.5f actual=%.5f R=%.5f",
                  states[stateIdx].ticket, states[stateIdx].shortInitialSL, actualSL, states[stateIdx].shortInitialRisk);
      ShortStateSave(stateIdx);
      TradeJournalWriteLifecycle(stateIdx, "INITIAL_RISK_FROZEN", "server_sl_confirmed_and_initial_r_ready");
   }
   return states[stateIdx].shortRiskReady;
}

void ShortReconcilePositionShape(int stateIdx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) ||
      !PositionSelectByTicket(states[stateIdx].ticket)) return;
   bool detectExternalChanges = 短线单检测外部手数变化;
   double volume = PositionGetDouble(POSITION_VOLUME);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   int direction = (int)PositionGetInteger(POSITION_TYPE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   bool changed = false;
   if(step <= 0.0) step = 0.01;
   if(tickSize <= 0.0) tickSize = _Point;
   if(states[stateIdx].lastKnownVolume <= 0.0)
   {
      states[stateIdx].lastKnownVolume = volume;
      states[stateIdx].lastKnownOpenPrice = openPrice;
      ShortStateSave(stateIdx);
      return;
   }

   bool volumeAdded = (volume > states[stateIdx].lastKnownVolume + step*0.5);
   bool volumeReduced = (volume < states[stateIdx].lastKnownVolume - step*0.5);
   bool averageChanged = (states[stateIdx].lastKnownOpenPrice > 0.0 &&
                          MathAbs(openPrice-states[stateIdx].lastKnownOpenPrice) > tickSize*1.5);
   bool recoveryIdentityChanged = (direction != states[stateIdx].positionDirection ||
                                   volumeAdded || averageChanged);
   if(recoveryIdentityChanged)
   {
      InvalidateEntryCostCache(stateIdx);
      bool recoveryWasArmed = states[stateIdx].recoveryArmed;
      states[stateIdx].recoveryArmed = false;
      states[stateIdx].recoveryArmedTime = 0;
      states[stateIdx].recoveryArmLossPrice = 0.0;
      states[stateIdx].recoveryArmTrigger = 0.0;
      if(recoveryWasArmed)
         TradeJournalWriteLifecycle(stateIdx, "RECOVERY_DISARMED",
                                    direction != states[stateIdx].positionDirection ?
                                    "position_direction_changed;new_combination_must_requalify" :
                                    "external_add_or_average_price_change;new_combination_must_requalify");
      changed = true;
   }

   if(direction != states[stateIdx].positionDirection)
   {
      // 净持仓反转沿用既有生命周期分段语义：旧段先结算，随后新段从零观测。
      FinalizeFloatingPnlTiming(stateIdx);
      ResetFloatingPnlTimingForNewLifecycleSegment(stateIdx);
      InvalidateEntryCostCache(stateIdx);
      TradeJournalWriteLifecycle(stateIdx, "NETTING_REVERSAL_DETECTED",
                                 StringFormat("old_direction=%d;new_direction=%d;old_open=%.5f;new_open=%.5f;volume=%.2f",
                                              states[stateIdx].positionDirection, direction,
                                              states[stateIdx].lastKnownOpenPrice, openPrice, volume));
      states[stateIdx].positionDirection = direction;
      states[stateIdx].adoptedTemplate = (int)当前参数配置模板;
      states[stateIdx].nettingReversalDetected = true;
      states[stateIdx].trendRiskReady = false;
      states[stateIdx].trendRiskUnknown = false;
      states[stateIdx].trendInitialRisk = 0.0;
      states[stateIdx].trendInitialSL = 0.0;
      states[stateIdx].trendHighSinceOpen = 0.0;
      states[stateIdx].trendLowSinceOpen = 0.0;
      states[stateIdx].lifecycleSegmentStartTime = (datetime)PositionGetInteger(POSITION_TIME_UPDATE);
      if(states[stateIdx].lifecycleSegmentStartTime <= 0) states[stateIdx].lifecycleSegmentStartTime = TimeCurrent();
      states[stateIdx].initialVolume = volume;
      states[stateIdx].shortRiskReady = false;
      states[stateIdx].shortRiskUnknown = false;
      states[stateIdx].shortInitialRisk = 0.0;
      states[stateIdx].shortInitialSL = 0.0;
      states[stateIdx].shortActualInitialSL = 0.0;
      states[stateIdx].shortInitialSLConfirmed = false;
      states[stateIdx].partialTPDone = false;
      states[stateIdx].partialTPStage = 0;
      states[stateIdx].partialFilledVolumeStage1 = 0.0;
      states[stateIdx].partialFilledVolumeStage2 = 0.0;
      states[stateIdx].partialFilledVolumeStage3 = 0.0;
      states[stateIdx].runnerMode = 短线尾仓_固定TP;
      states[stateIdx].fixedTPRemoved = false;
      states[stateIdx].fastProtectionActivated = false;
      states[stateIdx].fastProtectionTime = 0;
      states[stateIdx].tradeArchetype = 短线类型_未知;
      states[stateIdx].maxProfitPrice = 0.0;
      states[stateIdx].maxLossPrice = 0.0;
      states[stateIdx].recoveryArmed = false;
      states[stateIdx].recoveryArmedTime = 0;
      states[stateIdx].recoveryArmLossPrice = 0.0;
      states[stateIdx].recoveryArmTrigger = 0.0;
      states[stateIdx].maxProfitMoney = 0.0;
      states[stateIdx].maxLossMoney = 0.0;
      states[stateIdx].lifecycleRealizedNetMoney = 0.0;
      states[stateIdx].maxLifecycleProfitMoney = 0.0;
      states[stateIdx].maxLifecycleLossMoney = 0.0;
      states[stateIdx].lifecyclePnlEnvelopeInitialized = false;
      states[stateIdx].lifecyclePhase = 生命周期_风险建立中;
      states[stateIdx].protectionStage = 保护阶段_无有效SL;
      ClearPendingTradeAction(stateIdx);
      changed = true;
   }
   else
   {
      // 用户可关闭同方向外部加减仓风控；Netting方向反转的生命周期切段始终必须执行。
      if(!detectExternalChanges)
      {
         if(MathAbs(states[stateIdx].lastKnownVolume-volume) > step*0.1 ||
            MathAbs(states[stateIdx].lastKnownOpenPrice-openPrice) > tickSize*0.1)
         {
            states[stateIdx].lastKnownVolume = volume;
            states[stateIdx].lastKnownOpenPrice = openPrice;
            changed = true;
         }
         if(changed) ShortStateSave(stateIdx);
         return;
      }

      if(volumeAdded || averageChanged)
      {
         states[stateIdx].externalVolumeChangeDetected = true;
         states[stateIdx].externalVolumeChangeTime = TimeCurrent();
         states[stateIdx].shortRiskReady = false;
         states[stateIdx].shortRiskUnknown = true;
         states[stateIdx].shortInitialSLConfirmed = false;
         states[stateIdx].shortInitialRisk = 0.0;
         TradeJournalWriteLifecycle(stateIdx, "EXTERNAL_POSITION_ADD_DETECTED",
                                    StringFormat("old_volume=%.2f;new_volume=%.2f;old_open=%.5f;new_open=%.5f;risk_state=unknown",
                                                 states[stateIdx].lastKnownVolume, volume,
                                                 states[stateIdx].lastKnownOpenPrice, openPrice));
         changed = true;
      }
      else if(states[stateIdx].pendingAction == 待确认动作_无 && volumeReduced)
      {
         states[stateIdx].externalVolumeChangeDetected = true;
         states[stateIdx].externalVolumeChangeTime = TimeCurrent();
         TradeJournalWriteLifecycle(stateIdx, "EXTERNAL_POSITION_REDUCTION_DETECTED",
                                    StringFormat("old_volume=%.2f;new_volume=%.2f;reduced=%.2f",
                                                 states[stateIdx].lastKnownVolume, volume,
                                                 states[stateIdx].lastKnownVolume-volume));
         changed = true;
      }
   }
   if(MathAbs(states[stateIdx].lastKnownVolume-volume) > step*0.1 ||
      MathAbs(states[stateIdx].lastKnownOpenPrice-openPrice) > tickSize*0.1)
   {
      states[stateIdx].lastKnownVolume = volume;
      states[stateIdx].lastKnownOpenPrice = openPrice;
      changed = true;
   }
   if(changed) ShortStateSave(stateIdx);
}

bool ShortEnsureInitialRiskReady(ulong ticket, int stateIdx, ENUM_POSITION_TYPE type, double openPrice, double atr)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || !PositionSelectByTicket(ticket)) return false;
   states[stateIdx].shortStateManaged = true;
   if(states[stateIdx].shortRiskReady) return true;
   if(states[stateIdx].shortRiskUnknown && states[stateIdx].externalVolumeChangeDetected) return false;
   double curSL = PositionGetDouble(POSITION_SL);
   // 已有仍在亏损侧的SL可以作为用户初始SL确认；盈利侧SL不能倒推历史R。
   if(ShortSLIsRiskSide(type, openPrice, curSL))
   {
      states[stateIdx].shortInitialSL = curSL;
      return ShortConfirmInitialSL(stateIdx, type, openPrice);
   }
   if(curSL > 0.0)
   {
      states[stateIdx].shortRiskUnknown = true;
      ShortStateSave(stateIdx);
      return false;
   }

   double atrDistance = ShortLineDynamicInitialSL(atr, type);
   double boxSL = 0.0, boxDistance = 0.0;
   bool hasBoxSL = ShortLineBoxSLPrice(type, openPrice, boxSL, boxDistance);
   double visualBoxSL = 0.0, visualBoxTP = 0.0, visualBoxSLDistance = 0.0, visualBoxTPDistance = 0.0;
   bool hasVisualBoxTargets = ShortLineVisualBoxInitialTargets(type, openPrice, visualBoxSL, visualBoxTP,
                                                                 visualBoxSLDistance, visualBoxTPDistance);
   // 有效未突破的近期箱体优先给出一组配套的 SL/TP；没有时才沿用原 ATR/支压箱体回退。
   double finalDistance = hasVisualBoxTargets ? visualBoxSLDistance :
                          MathMax(atrDistance, hasBoxSL ? boxDistance : 0.0);
   double requestedSL = NormalizePrice(type == POSITION_TYPE_BUY ? openPrice-finalDistance : openPrice+finalDistance);
   if(finalDistance <= 0.0 || !SLTPValid(type, requestedSL, PositionGetDouble(POSITION_TP)))
   {
      double disasterSL = ShortEmergencySLPrice(type, openPrice, atr);
      if(SLTPValid(type, disasterSL, PositionGetDouble(POSITION_TP))) requestedSL = disasterSL;
      else
      {
         PrintRateLimited(StringFormat("short_initial_sl_invalid:%I64u", ticket), 10,
                          StringFormat("[短线风险] 初始SL候选不合规 ticket=%I64u ATR=%.5f box=%.5f，等待重试",
                                       ticket, atrDistance, boxDistance));
         return false;
      }
   }
   states[stateIdx].shortInitialSL = requestedSL;
   PrintRateLimited(StringFormat("short_initial_sl_candidate:%I64u", ticket), 10,
                    StringFormat("[短线风险] 初始SL候选 ticket=%I64u ATR=%.5f cache_box=%.5f visual_box=%.5f visual_tp=%.5f final=%.5f", ticket,
                                 atrDistance, boxDistance, visualBoxSLDistance, visualBoxTPDistance, requestedSL));
   int slSource = hasVisualBoxTargets ? SL来源_初始箱体 :
                  ((hasBoxSL && boxDistance >= atrDistance) ? SL来源_初始箱体 : SL来源_初始ATR);
   states[stateIdx].lifecyclePhase = 生命周期_风险建立中;
   MarkShortStateDirty(stateIdx);
   if(!SubmitManagedPositionModify(ticket, stateIdx, requestedSL, PositionGetDouble(POSITION_TP),
                                   slSource, TP来源_无))
   {
      PrintRateLimited(StringFormat("short_initial_sl_modify:%I64u:%d", ticket, manageTrade.ResultRetcode()), 10,
                       StringFormat("[短线风险] 初始SL修改失败 ticket=%I64u target=%.5f ret=%d %s", ticket, requestedSL,
                                    manageTrade.ResultRetcode(), manageTrade.ResultComment()));
      return false;
   }
   TradeJournalWriteLifecycle(stateIdx, "INITIAL_RISK_REQUESTED",
                              StringFormat("requested_sl=%.5f;sl_source=%d", requestedSL, slSource));
   return false; // 等待下一次服务器持仓刷新后由ShortConfirmInitialSL冻结真实R。
}

double ShortLineLastClosedM1Profit(ENUM_POSITION_TYPE type, double openPrice)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_M1, 1, 1, rates) != 1) return -DBL_MAX;
   return (type == POSITION_TYPE_BUY) ? rates[0].close - openPrice : openPrice - rates[0].close;
}

bool ShortLineProtectionConfirmed(ENUM_POSITION_TYPE type, double openPrice, double requiredProfit)
{
   if(!短线单保护需M1收线确认) return true;
   return (ShortLineLastClosedM1Profit(type, openPrice) >= requiredProfit);
}

double ShortLineDynamicSmallTP(double atr)
{
   double unit = GetShortLineVolatilityUnit(atr);
   double raw = unit * MathMax(短线单成本线小TP_ATR倍数, 0.10);
   return ClampDouble(raw, MathMax(短线单成本线小TP最小价格, 0.10), MathMax(短线单成本线小TP最大价格, 0.10));
}

double ShortLineDynamicMainTP(double atr, ENUM_POSITION_TYPE type)
{
   double unit = GetShortLineVolatilityUnit(atr);
   double raw = unit * MathMax(短线单主TP_ATR倍数, 0.10);
   double tp = ClampDouble(raw, MathMax(短线单主TP最小价格, 0.10), MathMax(短线单主TP最大价格, 短线单主TP最小价格));

   int trend = DetectTrendRegimeM5();
   bool trendWithPosition =
      (type == POSITION_TYPE_BUY && trend > 0) ||
      (type == POSITION_TYPE_SELL && trend < 0);
   if(trendWithPosition)
   {
      bool momentumOK = ShortLineM1MomentumWithPosition(type);
      double trendFloor = momentumOK ? 短线单好行情TP最低价格 : 短线单主TP最小价格;
      tp = MathMax(tp, MathMin(trendFloor, 短线单主TP最大价格));
      if(momentumOK)
         tp = MathMax(tp, MathMin(短线单顺势TP价格, 短线单主TP最大价格));
   }

   return tp;
}

double ShortTeacherTickSize()
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0) tickSize = _Point;
   return MathMax(tickSize, _Point);
}

double NormalizeShortTeacherPrice(const double price, const ENUM_POSITION_TYPE type)
{
   if(price <= 0.0) return 0.0;
   double tickSize = ShortTeacherTickSize();
   double steps = price / tickSize;
   // BUY 的 TP/保护 SL 都应留在线下，SELL 对称留在线上，不能因四舍五入越过老师结构位。
   double aligned = (type == POSITION_TYPE_BUY) ? MathFloor(steps + 1e-9) * tickSize
                                                 : MathCeil(steps - 1e-9) * tickSize;
   return NormalizeDouble(aligned, _Digits);
}

double ShortTeacherTPBuffer()
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (bid > 0.0 && ask > bid) ? ask-bid : 0.0;
   return MathMax(MathMax(TP贴近点位缓冲价格, spread*0.50), ShortTeacherTickSize()*2.0);
}

void ResetShortTeacherPlan(const int stateIdx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return;
   states[stateIdx].teacherPlanInitialized = false;
   states[stateIdx].teacherPlanValid = false;
   states[stateIdx].teacherPlanSignature = 0;
   states[stateIdx].teacherPlanMode = 老师点位辅助_仅TP;
   states[stateIdx].teacherPrimaryTP = 0.0;
   states[stateIdx].teacherSecondaryTP = 0.0;
}

void FreezeShortTeacherPlan(const int stateIdx, const ENUM_POSITION_TYPE type, const double openPrice)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return;
   ResetShortTeacherPlan(stateIdx);
   states[stateIdx].teacherPlanInitialized = true;
   states[stateIdx].teacherPlanMode = (int)老师点位短线模式;
   if(!短线单启用老师点位辅助SLTP || !缓存老师点位有效 || openPrice <= 0.0)
      return;

   double primaryDistance = DBL_MAX;
   double secondaryDistance = DBL_MAX;
   double primary = 0.0;
   double secondary = 0.0;
   double maxDistance = MathMax(短线单主TP最大价格, MathMax(短线单箱体TP最大空间价格, 0.10));
   double tolerance = ShortTeacherTickSize()*0.50;

   for(int i=0; i<ArraySize(缓存老师点位); i++)
   {
      double level = 缓存老师点位[i];
      double distance = (type == POSITION_TYPE_BUY) ? level-openPrice : openPrice-level;
      if(distance <= tolerance || distance > maxDistance + ShortTeacherTPBuffer()) continue;

      if(distance < primaryDistance)
      {
         secondaryDistance = primaryDistance;
         secondary = primary;
         primaryDistance = distance;
         primary = level;
      }
      else if(distance < secondaryDistance && MathAbs(level-primary) > tolerance)
      {
         secondaryDistance = distance;
         secondary = level;
      }
   }

   if(primary <= 0.0) return;
   states[stateIdx].teacherPlanValid = true;
   states[stateIdx].teacherPlanSignature = 缓存老师点位签名;
   states[stateIdx].teacherPrimaryTP = primary;
   states[stateIdx].teacherSecondaryTP = secondary;
   PrintFormat("[老师短线] 计划冻结 id=%I64u mode=%d signature=%I64u primary=%.5f secondary=%.5f",
               states[stateIdx].positionIdentifier, states[stateIdx].teacherPlanMode,
               states[stateIdx].teacherPlanSignature, primary, secondary);
}

bool ShortTeacherPlanEnabled(const int stateIdx)
{
   return (短线单启用老师点位辅助SLTP &&
           stateIdx >= 0 && stateIdx < ArraySize(states) &&
           states[stateIdx].teacherPlanInitialized && states[stateIdx].teacherPlanValid &&
           states[stateIdx].teacherPrimaryTP > 0.0);
}

bool ShortTeacherTargetMetrics(const int stateIdx, const ENUM_POSITION_TYPE type,
                               const double openPrice, const double level,
                               const bool requireMainRules, const bool requireAhead,
                               double &targetPrice, double &targetDistance)
{
   targetPrice = 0.0;
   targetDistance = 0.0;
   if(!ShortTeacherPlanEnabled(stateIdx) || openPrice <= 0.0 || level <= 0.0) return false;

   double rawTarget = (type == POSITION_TYPE_BUY) ? level-ShortTeacherTPBuffer()
                                                   : level+ShortTeacherTPBuffer();
   targetPrice = NormalizeShortTeacherPrice(rawTarget, type);
   targetDistance = (type == POSITION_TYPE_BUY) ? targetPrice-openPrice : openPrice-targetPrice;

   double minDistance = requireMainRules ? MathMax(短线单主TP最小价格, 0.10)
                                          : MathMax(短线单推荐TP最小空间价格, 0.10);
   double maxDistance = MathMax(短线单主TP最大价格, minDistance);
   if(targetDistance < minDistance || targetDistance > maxDistance) return false;
   if(requireMainRules && states[stateIdx].shortRiskReady)
   {
      double riskFloor = states[stateIdx].shortInitialRisk * MathMax(短线单主TP最小风险回报比, 0.10);
      if(targetDistance + ShortTeacherTickSize()*0.50 < riskFloor) return false;
   }

   if(requireAhead)
   {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(bid <= 0.0 || ask <= 0.0) return false;
      double serverDistance = MathMax((double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                                      (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
      serverDistance = MathMax(serverDistance, ShortTeacherTickSize());
      if(type == POSITION_TYPE_BUY && targetPrice <= bid+serverDistance) return false;
      if(type == POSITION_TYPE_SELL && targetPrice >= ask-serverDistance) return false;
   }
   return true;
}

double ShortLineRiskAdjustedBaseMainTP(const int stateIdx, const double atr, const ENUM_POSITION_TYPE type)
{
   double distance = ShortLineDynamicMainTP(atr, type);
   if(stateIdx >= 0 && stateIdx < ArraySize(states) && states[stateIdx].shortRiskReady)
   {
      distance = MathMax(distance,
                         states[stateIdx].shortInitialRisk * MathMax(短线单主TP最小风险回报比, 0.10));
      distance = ClampDouble(distance,
                             MathMax(短线单主TP最小价格, 0.10),
                             MathMax(短线单主TP最大价格, 短线单主TP最小价格));
   }
   return distance;
}

double ShortLineEffectiveMainTPDistance(const int stateIdx, const ENUM_POSITION_TYPE type,
                                        const double openPrice, const double atr,
                                        bool &teacherSelected, double &teacherTargetPrice)
{
   teacherSelected = false;
   teacherTargetPrice = 0.0;
   double baseline = ShortLineRiskAdjustedBaseMainTP(stateIdx, atr, type);
   // 老师主目标必须能通过冻结初始R校验；R尚未由服务器SL确认时完整回退原动态TP。
   if(!ShortTeacherPlanEnabled(stateIdx) || !states[stateIdx].shortRiskReady) return baseline;

   int trend = DetectTrendRegimeM5();
   bool strongWithPosition = ((type == POSITION_TYPE_BUY && trend > 0) ||
                              (type == POSITION_TYPE_SELL && trend < 0)) &&
                             ShortLineM1MomentumWithPosition(type);
   double firstLevel = strongWithPosition && states[stateIdx].teacherSecondaryTP > 0.0 ?
                       states[stateIdx].teacherSecondaryTP : states[stateIdx].teacherPrimaryTP;
   double secondLevel = firstLevel == states[stateIdx].teacherPrimaryTP ?
                        states[stateIdx].teacherSecondaryTP : states[stateIdx].teacherPrimaryTP;
   double distance = 0.0;
   if(ShortTeacherTargetMetrics(stateIdx, type, openPrice, firstLevel, true, true,
                                teacherTargetPrice, distance) ||
      ShortTeacherTargetMetrics(stateIdx, type, openPrice, secondLevel, true, true,
                                teacherTargetPrice, distance))
   {
      teacherSelected = true;
      return distance;
   }
   return baseline;
}

double ShortLineTeacherReferenceDistance(const int stateIdx, const ENUM_POSITION_TYPE type,
                                         const double openPrice, const int stage)
{
   if(!ShortTeacherPlanEnabled(stateIdx)) return 0.0;
   double level = (stage >= 2 && states[stateIdx].teacherSecondaryTP > 0.0) ?
                  states[stateIdx].teacherSecondaryTP : states[stateIdx].teacherPrimaryTP;
   double target = 0.0;
   double distance = 0.0;
   if(!ShortTeacherTargetMetrics(stateIdx, type, openPrice, level, false, false, target, distance))
      return 0.0;
   return distance;
}

double ShortLineEffectivePartialTrigger(const int stateIdx, const ENUM_POSITION_TYPE type,
                                        const double openPrice, const int stage,
                                        const ShortLineMarketContext &ctx, const double baseMainTP)
{
   double trigger = GetShortLineDynamicPartialTrigger(stage, ctx, baseMainTP,
                                                       states[stateIdx].shortInitialRisk);
   double teacherReference = ShortLineTeacherReferenceDistance(stateIdx, type, openPrice, stage);
   if(teacherReference <= 0.0) return trigger;

   double riskFloor = states[stateIdx].shortInitialRisk *
                      (stage == 1 ? 0.70 : (stage == 2 ? 1.10 : 1.50));
   double volatilityFloor = ctx.atrM1 *
                            (stage == 1 ? 1.30 : (stage == 2 ? 1.90 : 2.50));
   double safetyFloor = MathMax(GetShortLineStageTriggerMin(stage), MathMax(riskFloor, volatilityFloor));
   return MathMax(MathMin(trigger, teacherReference), safetyFloor);
}

bool ShortLineTeacherProtectionSL(const int stateIdx, const ENUM_POSITION_TYPE type,
                                  const double openPrice, const double atr, const double profitPrice,
                                  double &candidateSL)
{
   candidateSL = 0.0;
   if(!ShortTeacherPlanEnabled(stateIdx) ||
      states[stateIdx].teacherPlanMode != 老师点位辅助_TP与突破保护SL ||
      !states[stateIdx].shortRiskReady) return false;

   double trigger = MathMax(M1结构最小浮盈启动,
                            atr > 0.0 ? atr*MathMax(M1结构追踪启动ATR倍数, 0.0) : 0.0);
   trigger = MathMax(trigger,
                     states[stateIdx].shortInitialRisk*MathMax(短线单结构追踪最小风险R, 0.10));
   if(profitPrice < trigger || !EnsureShortLineSharedBarCache()) return false;

   double close1 = shortLineSharedBarCache.lastClose;
   double close2 = shortLineSharedBarCache.previousM1Close;
   double confirmBuffer = ShortTeacherTickSize();
   double brokenLevel = 0.0;
   double levels[2];
   levels[0] = states[stateIdx].teacherPrimaryTP;
   levels[1] = states[stateIdx].teacherSecondaryTP;
   for(int i=0; i<2; i++)
   {
      double level = levels[i];
      if(level <= 0.0) continue;
      bool held = (type == POSITION_TYPE_BUY) ?
                  (close1 > level+confirmBuffer && close2 > level+confirmBuffer) :
                  (close1 < level-confirmBuffer && close2 < level-confirmBuffer);
      if(!held) continue;
      if(brokenLevel <= 0.0 ||
         (type == POSITION_TYPE_BUY && level > brokenLevel) ||
         (type == POSITION_TYPE_SELL && level < brokenLevel))
         brokenLevel = level;
   }
   if(brokenLevel <= 0.0) return false;

   double structureBuffer = MathMax(M1结构SL缓冲价格, ShortTeacherTickSize()*2.0);
   double rawSL = (type == POSITION_TYPE_BUY) ? brokenLevel-structureBuffer : brokenLevel+structureBuffer;
   candidateSL = NormalizeShortTeacherPrice(rawSL, type);
   if((type == POSITION_TYPE_BUY && candidateSL <= openPrice) ||
      (type == POSITION_TYPE_SELL && candidateSL >= openPrice)) return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return false;
   double minDistance = MathMax(M1结构最小SL距离,
                                atr > 0.0 ? atr*MathMax(M1结构最小SL距离ATR倍数, 0.0) : 0.0);
   double serverDistance = MathMax((double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL),
                                   (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL))*_Point;
   minDistance = MathMax(minDistance, serverDistance+ShortTeacherTickSize());
   if(type == POSITION_TYPE_BUY && bid-candidateSL < minDistance) return false;
   if(type == POSITION_TYPE_SELL && candidateSL-ask < minDistance) return false;
   return true;
}

bool ShortLineTrendWithPosition(ENUM_POSITION_TYPE type)
{
   int trend = DetectTrendRegimeM5();
   return ((type == POSITION_TYPE_BUY && trend > 0) ||
           (type == POSITION_TYPE_SELL && trend < 0));
}

bool ShortLineStrongTrendWithPosition(ENUM_POSITION_TYPE type, double atr, double profitPrice, double maxProfitPrice)
{
   if(!短线单强顺势不提前快收) return false;
   if(!ShortLineTrendWithPosition(type)) return false;
   if(!ShortLineM1MomentumWithPosition(type)) return false;

   double unit = GetShortLineVolatilityUnit(atr);
   double confirmProfit = MathMax(unit * MathMax(短线单强顺势确认ATR倍数, 0.10), 短线单回本平仓最大盈利);

   // 只有“趋势顺着单子”且利润已经走出来，才允许多拿；刚回本的小赚仍然优先落袋。
   return (profitPrice >= confirmProfit || maxProfitPrice >= confirmProfit * 1.50);
}

double AverageClosedRange(ENUM_TIMEFRAMES tf, int bars)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 1, MathMax(bars, 1), rates);
   if(copied <= 0) return 0.0;

   double sum = 0.0;
   int count = 0;
   for(int i=0; i<copied; i++)
   {
      double range = rates[i].high - rates[i].low;
      if(range <= 0.0) continue;
      sum += range;
      count++;
   }
   return (count > 0) ? sum / count : 0.0;
}

void InitShortLineMarketContext(ShortLineMarketContext &ctx)
{
   ctx.atrM1 = 0.0;
   ctx.atrM5 = 0.0;
   ctx.lastBody = 0.0;
   ctx.lastRange = 0.0;
   ctx.lastUpperWick = 0.0;
   ctx.lastLowerWick = 0.0;
   ctx.bodyRatio = 0.0;
   ctx.closePosRatio = 0.5;
   ctx.avgBody3 = 0.0;
   ctx.avgRange3 = 0.0;
   ctx.impulseScore = 0.0;
   ctx.chopScore = 0.0;
   ctx.trendScore = 0.0;
   ctx.boxRoom = 0.0;
   ctx.m1BullImpulse = false;
   ctx.m1BearImpulse = false;
   ctx.m5SameDirection = false;
   ctx.nearBoxEdge = false;
   ctx.momentumWeak = false;
   ctx.strongForPosition = false;
   ctx.choppyForPosition = false;
}

bool EnsureShortLineSharedBarCache()
{
   datetime m1Key = lastM1BarTime;
   datetime m5Key = lastM5BarTime;
   if(shortLineSharedBarCache.valid &&
      shortLineSharedBarCache.m1CurrentBarTime == m1Key &&
      shortLineSharedBarCache.m5CurrentBarTime == m5Key)
      return true;

   MqlRates m1[];
   ArraySetAsSeries(m1, true);
   int copiedM1 = CopyRates(_Symbol, PERIOD_M1, 1, 14, m1);
   if(copiedM1 < 3)
      return false;

   double m1RangeSum = 0.0;
   int m1RangeCount = 0;
   for(int i=0; i<copiedM1; i++)
   {
      double range = m1[i].high - m1[i].low;
      if(range <= 0.0) continue;
      m1RangeSum += range;
      m1RangeCount++;
   }

   double bodySum3 = 0.0;
   double rangeSum3 = 0.0;
   for(int i=0; i<3; i++)
   {
      double range = m1[i].high - m1[i].low;
      double body = MathAbs(m1[i].close - m1[i].open);
      if(range <= 0.0) continue;
      bodySum3 += body;
      rangeSum3 += range;
   }

   MqlRates m5[];
   ArraySetAsSeries(m5, true);
   int copiedM5 = CopyRates(_Symbol, PERIOD_M5, 1, 5, m5);
   double m5RangeSum = 0.0;
   int m5RangeCount = 0;
   for(int i=0; i<copiedM5; i++)
   {
      double range = m5[i].high - m5[i].low;
      if(range <= 0.0) continue;
      m5RangeSum += range;
      m5RangeCount++;
   }

   shortLineSharedBarCache.m1CurrentBarTime = m1Key;
   shortLineSharedBarCache.m5CurrentBarTime = m5Key;
   shortLineSharedBarCache.fallbackAtrM1 = (m1RangeCount > 0) ? m1RangeSum / m1RangeCount : 0.0;
   shortLineSharedBarCache.atrM5 = (m5RangeCount > 0) ? m5RangeSum / m5RangeCount : 0.0;
   shortLineSharedBarCache.avgBody3 = bodySum3 / 3.0;
   shortLineSharedBarCache.avgRange3 = rangeSum3 / 3.0;
   shortLineSharedBarCache.lastOpen = m1[0].open;
   shortLineSharedBarCache.lastClose = m1[0].close;
   shortLineSharedBarCache.previousM1Close = m1[1].close;
   shortLineSharedBarCache.lastHigh = m1[0].high;
   shortLineSharedBarCache.lastLow = m1[0].low;
   shortLineSharedBarCache.hasM5DirectionBars = (copiedM5 >= 2);
   shortLineSharedBarCache.latestM5Open = (copiedM5 >= 1) ? m5[0].open : 0.0;
   shortLineSharedBarCache.latestM5Close = (copiedM5 >= 1) ? m5[0].close : 0.0;
   shortLineSharedBarCache.previousM5Close = (copiedM5 >= 2) ? m5[1].close : 0.0;

   // M5历史尚未完整时保留本次可用数据，但下一次调用继续尝试补齐，
   // 避免把临时缺失永久缓存到下一根K线。
   shortLineSharedBarCache.valid = (copiedM5 >= 2);
   return true;
}

bool BuildShortLineMarketContext(ENUM_POSITION_TYPE type, double openPrice, double currentPrice,
                                 double atr, ShortLineMarketContext &ctx)
{
   PerformanceScope perfScope(PERF_BUILD_SHORT_CONTEXT);
   InitShortLineMarketContext(ctx);
   if(!EnsureShortLineSharedBarCache()) return false;

   ctx.atrM1 = (atr > 0.0) ? atr : shortLineSharedBarCache.fallbackAtrM1;
   ctx.atrM5 = shortLineSharedBarCache.atrM5;
   if(ctx.atrM5 <= 0.0) ctx.atrM5 = ctx.atrM1;

   ctx.avgBody3 = shortLineSharedBarCache.avgBody3;
   ctx.avgRange3 = shortLineSharedBarCache.avgRange3;

   double open1 = shortLineSharedBarCache.lastOpen;
   double close1 = shortLineSharedBarCache.lastClose;
   ctx.lastRange = shortLineSharedBarCache.lastHigh - shortLineSharedBarCache.lastLow;
   ctx.lastBody = MathAbs(close1 - open1);
   if(ctx.lastRange <= 0.0) return false;

   ctx.lastUpperWick = shortLineSharedBarCache.lastHigh - MathMax(open1, close1);
   ctx.lastLowerWick = MathMin(open1, close1) - shortLineSharedBarCache.lastLow;
   ctx.bodyRatio = ctx.lastBody / ctx.lastRange;
   ctx.closePosRatio = (close1 - shortLineSharedBarCache.lastLow) / ctx.lastRange;

   ctx.m1BullImpulse = (close1 > open1 && ctx.bodyRatio >= 0.55 && ctx.closePosRatio >= 0.65);
   ctx.m1BearImpulse = (close1 < open1 && ctx.bodyRatio >= 0.55 && ctx.closePosRatio <= 0.35);

   if(shortLineSharedBarCache.hasM5DirectionBars)
   {
      if(type == POSITION_TYPE_BUY)
         ctx.m5SameDirection = (shortLineSharedBarCache.latestM5Close > shortLineSharedBarCache.latestM5Open ||
                                shortLineSharedBarCache.latestM5Close > shortLineSharedBarCache.previousM5Close);
      else
         ctx.m5SameDirection = (shortLineSharedBarCache.latestM5Close < shortLineSharedBarCache.latestM5Open ||
                                shortLineSharedBarCache.latestM5Close < shortLineSharedBarCache.previousM5Close);
   }

   SRLevel edge;
   bool hasEdge = false;
   if(type == POSITION_TYPE_BUY)
      hasEdge = GetShortLineBoxEdge(true, currentPrice, edge);
   else
      hasEdge = GetShortLineBoxEdge(false, currentPrice, edge);
   if(hasEdge)
   {
      ctx.boxRoom = (type == POSITION_TYPE_BUY) ? edge.price - currentPrice : currentPrice - edge.price;
      double edgeNear = MathMax(1.00, MathMax(ctx.atrM1 * 0.75, 短线单箱体TP贴边缓冲价格 * 2.0));
      ctx.nearBoxEdge = (ctx.boxRoom >= 0.0 && ctx.boxRoom <= edgeNear);
   }

   bool impulseForPosition = (type == POSITION_TYPE_BUY) ? ctx.m1BullImpulse : ctx.m1BearImpulse;
   ctx.strongForPosition = (impulseForPosition && ctx.m5SameDirection);

   bool adverseClose = (type == POSITION_TYPE_BUY) ? (ctx.closePosRatio < 0.45) : (ctx.closePosRatio > 0.55);
   bool adverseWick = (type == POSITION_TYPE_BUY) ?
      (ctx.lastUpperWick > MathMax(ctx.lastBody * 1.20, ctx.lastRange * 0.35)) :
      (ctx.lastLowerWick > MathMax(ctx.lastBody * 1.20, ctx.lastRange * 0.35));
   bool shrinkingBody = (ctx.avgRange3 > 0.0 && ctx.avgBody3 / ctx.avgRange3 <= MathMax(短线单分批震荡实体比例上限, 0.10));
   ctx.momentumWeak = (adverseClose || adverseWick || shrinkingBody);
   ctx.choppyForPosition = (shrinkingBody || !ctx.m5SameDirection || (!impulseForPosition && ctx.bodyRatio <= 0.45));

   ctx.impulseScore = ctx.bodyRatio * 10.0 + (ctx.m5SameDirection ? 3.0 : 0.0);
   ctx.chopScore = (shrinkingBody ? 4.0 : 0.0) + (!ctx.m5SameDirection ? 3.0 : 0.0) + (adverseWick ? 2.0 : 0.0);
   ctx.trendScore = ctx.m5SameDirection ? 1.0 : -1.0;
   return true;
}

string ShortLineContextTag(const ShortLineMarketContext &ctx)
{
   if(ctx.strongForPosition) return "顺势";
   if(ctx.nearBoxEdge) return "箱体边";
   if(ctx.momentumWeak) return "衰竭";
   if(ctx.choppyForPosition) return "震荡";
   return "普通";
}

void ShortLineDynamicBEConfigFromContext(ENUM_POSITION_TYPE type, double atr,
                                         double profitPrice, double maxProfitPrice,
                                         const ShortLineMarketContext &ctx, bool hasCtx,
                                         double &beTrigger, double &beLock)
{
   beTrigger = 保本触发价格;
   beLock = 保本锁定价格;
   if(当前参数配置模板 != 配置_黄金超短快保) return;

   double unit = GetShortLineVolatilityUnit(atr);
   // 净保本在ManagePosition中用OrderCalcProfit按账户货币反算；这里不再把当前点差当固定距离。

   bool strongTrend = (hasCtx && ctx.strongForPosition) ||
                      ShortLineStrongTrendWithPosition(type, atr, profitPrice, maxProfitPrice);
   if(strongTrend)
   {
      beTrigger = MathMax(短线单好行情保本最小价格, unit * MathMax(短线单好行情保本触发ATR倍数, 0.10));
       beLock = MathMax(短线单好行情保本锁定价格, 短线单保本锁定最小价格);
      return;
   }

   beTrigger = MathMax(短线单震荡保本最小价格, unit * MathMax(短线单震荡保本触发ATR倍数, 0.10));
   if(hasCtx)
   {
      if(ctx.choppyForPosition)
         beTrigger = MathMin(beTrigger, MathMax(短线单震荡保本最小价格 + 0.20, 短线单震荡保本最小价格));
      if(ctx.momentumWeak)
         beTrigger = MathMin(beTrigger, MathMax(短线单震荡保本最小价格 + 0.15, 短线单震荡保本最小价格));
      if(ctx.avgRange3 > 0.0 && ctx.atrM1 > ctx.avgRange3 * 1.20)
         beTrigger = MathMax(beTrigger, 短线单震荡保本最大价格 - 0.20);
   }
   beTrigger = ClampDouble(beTrigger,
                           MathMax(短线单震荡保本最小价格, 0.10),
                           MathMax(短线单震荡保本最大价格, 短线单震荡保本最小价格));
   beLock = MathMax(短线单保本锁定最小价格, 保本锁定价格);
}

void ShortLineDynamicBEConfig(ENUM_POSITION_TYPE type, double openPrice, double currentPrice,
                              double atr, double profitPrice, double maxProfitPrice,
                              double &beTrigger, double &beLock)
{
   ShortLineMarketContext ctx;
   bool hasCtx = BuildShortLineMarketContext(type, openPrice, currentPrice, atr, ctx);
   ShortLineDynamicBEConfigFromContext(type, atr, profitPrice, maxProfitPrice,
                                       ctx, hasCtx, beTrigger, beLock);
}

int ShortLineDynamicHesitationMinutes(double atr)
{
   int minM = MathMax(短线单成本线最短犹豫分钟, 1);
   int maxM = MathMax(短线单成本线最长犹豫分钟, minM);
   double recentRange = GetRecentM1RangeAverage(3);
   double ratio = (atr > 0.0) ? recentRange / atr : 1.0;

   if(ratio <= 0.75) return minM;
   if(ratio >= 1.60) return maxM;
   double k = (ratio - 0.75) / (1.60 - 0.75);
   return (int)MathRound(minM + (maxM - minM) * k);
}

double ShortLineDynamicRecoveryLossTrigger(double atr)
{
   double unit = GetShortLineVolatilityUnit(atr);
   return MathMax(短线单浮亏回本触发最小价格, unit * MathMax(短线单浮亏回本触发ATR倍数, 0.10));
}

double ShortLineDynamicRecoveryProfitMin(double atr)
{
   double unit = GetShortLineVolatilityUnit(atr);
   double raw = MathMax(短线单回本平仓最小盈利, unit * MathMax(短线单回本平仓盈利ATR倍数, 0.0));
   return ClampDouble(raw, MathMax(短线单回本平仓最小盈利, 0.0), MathMax(短线单回本平仓最大盈利, 短线单回本平仓最小盈利));
}

void ShortObserveRecoveryArm(int stateIdx, double profitPrice, double atr)
{
   if(当前参数配置模板 != 配置_黄金超短快保 || !短线单浮亏回本直接平仓 ||
      stateIdx < 0 || stateIdx >= ArraySize(states) || states[stateIdx].recoveryArmed ||
      profitPrice >= 0.0)
      return;

   double lossPrice = -profitPrice;
   double trigger = ShortLineDynamicRecoveryLossTrigger(atr);
   if(lossPrice < trigger) return;

   states[stateIdx].recoveryArmed = true;
   states[stateIdx].recoveryArmedTime = TimeCurrent();
   states[stateIdx].recoveryArmLossPrice = lossPrice;
   states[stateIdx].recoveryArmTrigger = trigger;
   MarkShortStateDirty(stateIdx);
   ShortStateSave(stateIdx);
   TradeJournalWriteLifecycle(stateIdx, "RECOVERY_ARMED",
                              StringFormat("observed_loss=%.5f;frozen_trigger=%.5f;atr=%.5f",
                                           lossPrice, trigger, atr));
}

bool TrendPositionWithM5(ENUM_POSITION_TYPE type)
{
   int trend = DetectTrendRegimeM5();
   return ((type == POSITION_TYPE_BUY && trend > 0) ||
           (type == POSITION_TYPE_SELL && trend < 0));
}

bool TrendM1MomentumWithPosition(ENUM_POSITION_TYPE type)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, 5, rates);
   if(copied < 3) return false;

   double progress = rates[0].close - rates[copied - 1].open;
   double bodySum = 0.0;
   int sameDirBars = 0;
   for(int i=0; i<copied; i++)
   {
      double body = rates[i].close - rates[i].open;
      bodySum += body;
      if(type == POSITION_TYPE_BUY && body > 0.0) sameDirBars++;
      if(type == POSITION_TYPE_SELL && body < 0.0) sameDirBars++;
   }

   if(type == POSITION_TYPE_BUY)
      return (progress > 0.0 && bodySum > 0.0 && sameDirBars >= 3);
   return (progress < 0.0 && bodySum < 0.0 && sameDirBars >= 3);
}

bool TrendNewsVolatilityMode(double atr)
{
   if(!趋势单启用消息面自适应) return false;
   if(atr <= 0.0) atr = MathMax(GetRecentM1RangeAverage(14), 1.0);

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, 3, rates);
   if(copied < 3) return false;

   double totalRange = 0.0;
   double maxBody = 0.0;
   for(int i=0; i<copied; i++)
   {
      totalRange += MathMax(0.0, rates[i].high - rates[i].low);
      maxBody = MathMax(maxBody, MathAbs(rates[i].close - rates[i].open));
   }

   bool bodySpike = (maxBody >= atr * MathMax(趋势单消息单K实体ATR倍数, 0.10));
   bool rangeSpike = (totalRange >= atr * MathMax(趋势单消息3根波动ATR倍数, 0.10));
   bool spreadSpike = (趋势单消息点差阈值点数 > 0 && CurrentSpreadPoints() >= 趋势单消息点差阈值点数);
   return (bodySpike || rangeSpike || spreadSpike);
}

int TrendTradeRegime(ENUM_POSITION_TYPE type, double atr)
{
   bool trendOK = TrendPositionWithM5(type);
   bool momentumOK = TrendM1MomentumWithPosition(type);
   bool newsVol = TrendNewsVolatilityMode(atr);
   if(newsVol && trendOK && momentumOK) return 2; // 消息面顺势
   if(trendOK && momentumOK) return 1;            // 普通顺势
   return 0;                                      // 震荡/逆势/趋势不足
}

double TrendDynamicInitialSL(double atr, ENUM_POSITION_TYPE type)
{
   double unit = MathMax(atr, GetRecentM1RangeAverage(5));
   if(unit <= 0.0) unit = 8.0;

   int regime = TrendTradeRegime(type, atr);
   if(regime == 2)
      return ClampDouble(unit * MathMax(趋势单消息SL_ATR倍数, 0.10), 趋势单消息SL最小价格, 趋势单消息SL最大价格);

   return ClampDouble(unit * MathMax(趋势单普通SL_ATR倍数, 0.10), 趋势单普通SL最小价格, 趋势单普通SL最大价格);
}

double TrendDynamicInitialTP(double atr, ENUM_POSITION_TYPE type)
{
   double unit = MathMax(atr, GetRecentM1RangeAverage(5));
   if(unit <= 0.0) unit = 8.0;

   int regime = TrendTradeRegime(type, atr);
   if(regime == 2)
      return ClampDouble(unit * MathMax(趋势单消息顺势TP_ATR倍数, 0.10), 趋势单消息顺势TP最小价格, 趋势单消息顺势TP最大价格);
   if(regime == 1)
      return ClampDouble(unit * MathMax(趋势单普通TP_ATR倍数, 0.10), 趋势单普通TP最小价格, 趋势单普通TP最大价格);

   return ClampDouble(unit * MathMax(趋势单逆势弱势TP_ATR倍数, 0.10), 趋势单逆势弱势TP最小价格, 趋势单逆势弱势TP最大价格);
}

void TrendDynamicBEConfig(ENUM_POSITION_TYPE type, double atr, double &beTrigger, double &beLock)
{
   if(!当前模板使用黄金稳健止损()) return;

   double unit = MathMax(atr, GetRecentM1RangeAverage(5));
   if(unit <= 0.0) unit = 8.0;

   int regime = TrendTradeRegime(type, atr);
   if(regime == 2)
   {
      beTrigger = MathMax(趋势单消息顺势保本最小价格, unit * MathMax(趋势单消息顺势保本ATR倍数, 0.10));
      beLock = MathMax(趋势单保本锁定消息价格, 0.0);
   }
   else if(regime == 1)
   {
      beTrigger = MathMax(趋势单普通保本最小价格, unit * MathMax(趋势单普通保本ATR倍数, 0.10));
      beLock = MathMax(趋势单保本锁定普通价格, 0.0);
   }
   else
   {
      beTrigger = MathMax(趋势单震荡保本最小价格, unit * MathMax(趋势单震荡保本ATR倍数, 0.10));
      beLock = MathMax(趋势单保本锁定普通价格, 0.0);
   }
}

void TrendAdjustTrailConfig(ENUM_POSITION_TYPE type, double atr, double &trigger, double &distance, double &minStep)
{
   if(!当前模板使用黄金稳健止损() || !趋势单启用消息面自适应) return;

   double unit = MathMax(atr, GetRecentM1RangeAverage(5));
   if(unit <= 0.0) unit = 8.0;

   int regime = TrendTradeRegime(type, atr);
   if(regime == 2)
   {
      trigger = MathMax(trigger, unit * 2.80);
      distance = MathMax(distance, unit * 2.40);
      minStep = MathMax(minStep, unit * 0.60);
   }
   else if(regime == 0)
   {
      trigger = MathMin(trigger, MathMax(unit * 1.40, 趋势单震荡保本最小价格));
      distance = MathMin(distance, MathMax(unit * 1.20, 3.0));
      minStep = MathMax(minStep, unit * 0.35);
   }
}

bool TrendLongCopyBufferValue(int handle, int bufferIndex, int shift, double &value)
{
   value = 0.0;
   if(handle == INVALID_HANDLE) return false;
   double buf[1];
   bool ok = (CopyBuffer(handle, bufferIndex, shift, 1, buf) == 1);
   if(ok) value = buf[0];
   return ok;
}

bool TrendLongMA(ENUM_TIMEFRAMES tf, int period, int shift, double &value)
{
   int handle = GetManagedIndicatorHandle(MANAGED_EMA, tf, period);
   return TrendLongCopyBufferValue(handle, 0, shift, value);
}

bool TrendLongATR(ENUM_TIMEFRAMES tf, int period, double &value)
{
   int handle = GetManagedIndicatorHandle(MANAGED_ATR, tf, period);
   return TrendLongCopyBufferValue(handle, 0, 1, value);
}

bool TrendLongADX(ENUM_TIMEFRAMES tf, int period, double &value)
{
   int handle = GetManagedIndicatorHandle(MANAGED_ADX, tf, period);
   return TrendLongCopyBufferValue(handle, 0, 1, value);
}

bool TrendLongLastClose(ENUM_TIMEFRAMES tf, double &closeValue)
{
   closeValue = 0.0;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, tf, 1, 1, rates) != 1) return false;
   closeValue = rates[0].close;
   return true;
}

double NormalizeTrendPriceToTick(double price)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0.0) tickSize = _Point;
   if(tickSize <= 0.0) return NormalizeDouble(price, _Digits);
   return NormalizeDouble(MathRound(price/tickSize)*tickSize, _Digits);
}

int TrendLongH4Direction()
{
   double close1, ema20, ema50, atrH4;
   if(!TrendLongLastClose(趋势过滤周期, close1)) return 0;
   if(!TrendLongMA(趋势过滤周期, 20, 1, ema20)) return 0;
   if(!TrendLongMA(趋势过滤周期, 50, 1, ema50)) return 0;
   if(!TrendLongATR(趋势过滤周期, ATR周期, atrH4)) atrH4 = MathMax(MathAbs(ema20 - ema50), 1.0);

   double tolerance = MathMax(atrH4 * 0.10, _Point * 10);
   if(close1 > ema50 && ema20 >= ema50 - tolerance) return 1;
   if(close1 < ema50 && ema20 <= ema50 + tolerance) return -1;
   return 0;
}

int TrendLongH1State(ENUM_POSITION_TYPE type)
{
   double close1, ema20, ema50, adx, atrH1;
   if(!TrendLongLastClose(趋势主周期, close1)) return 0;
   if(!TrendLongMA(趋势主周期, 20, 1, ema20)) return 0;
   if(!TrendLongMA(趋势主周期, 50, 1, ema50)) return 0;
   if(!TrendLongADX(趋势主周期, 趋势ADX周期, adx)) adx = 0.0;
   if(!TrendLongATR(趋势主周期, ATR周期, atrH1)) atrH1 = MathMax(MathAbs(ema20 - ema50), 1.0);

   double breakBuffer = MathMax(atrH1 * 0.08, _Point * 10);
   if(type == POSITION_TYPE_BUY)
   {
      if(close1 < ema50 - breakBuffer) return -1;                 // 结构破坏
      if(close1 > ema20 && ema20 > ema50 && adx >= 趋势ADX阈值) return 2; // 强趋势
      if(close1 >= ema50) return 1;                                // 顺势/回调
      return 0;                                                    // 趋势减弱
   }

   if(close1 > ema50 + breakBuffer) return -1;
   if(close1 < ema20 && ema20 < ema50 && adx >= 趋势ADX阈值) return 2;
   if(close1 <= ema50) return 1;
   return 0;
}

string TrendLongDirectionText(int dir)
{
   if(dir > 0) return "多";
   if(dir < 0) return "空";
   return "震荡";
}

string TrendLongStateText(int state)
{
   if(state >= 2) return "顺势强";
   if(state == 1) return "顺势";
   if(state == 0) return "趋势减弱";
   return "结构破坏";
}

bool TrendLongStructureSL(ENUM_POSITION_TYPE type, ENUM_TIMEFRAMES tf, double refPrice, double atrH1, double &slPrice)
{
   slPrice = 0.0;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, tf, 1, 90, rates);
   if(copied < 12) return false;

   int strength = (tf == PERIOD_H1 ? 2 : 3);
   double level = 0.0;
   bool found = false;

   for(int i=strength; i<copied-strength; i++)
   {
      bool swing = true;
      for(int j=1; j<=strength; j++)
      {
         if(type == POSITION_TYPE_BUY)
         {
            if(rates[i].low >= rates[i-j].low || rates[i].low >= rates[i+j].low)
            {
               swing = false;
               break;
            }
         }
         else
         {
            if(rates[i].high <= rates[i-j].high || rates[i].high <= rates[i+j].high)
            {
               swing = false;
               break;
            }
         }
      }

      if(!swing) continue;
      level = (type == POSITION_TYPE_BUY) ? rates[i].low : rates[i].high;
      found = true;
      break; // ArraySetAsSeries=true，先遇到的是最近有效结构
   }

   if(!found)
   {
      level = (type == POSITION_TYPE_BUY) ? rates[0].low : rates[0].high;
      for(int i=1; i<copied; i++)
      {
         if(type == POSITION_TYPE_BUY && rates[i].low < level) level = rates[i].low;
         if(type == POSITION_TYPE_SELL && rates[i].high > level) level = rates[i].high;
      }
   }

   double buffer = MathMax(atrH1 * MathMax(趋势单结构SL_ATR缓冲, 0.05), _Point * 10);
   if(type == POSITION_TYPE_BUY)
   {
      slPrice = NormalizeTrendPriceToTick(level - buffer);
      return (slPrice > 0.0 && slPrice < refPrice);
   }

   slPrice = NormalizeTrendPriceToTick(level + buffer);
   return (slPrice > refPrice);
}

bool TrendLongInitialSLPrice(ENUM_POSITION_TYPE type, double openPrice, double &slPrice, double &risk)
{
   slPrice = 0.0;
   risk = 0.0;
   double atrH1 = 0.0;
   if(!TrendLongATR(趋势主周期, ATR周期, atrH1) || atrH1 <= 0.0) return false;

   double slM30 = 0.0, slH1 = 0.0;
   bool hasM30 = TrendLongStructureSL(type, 结构追踪周期1, openPrice, atrH1, slM30);
   bool hasH1 = TrendLongStructureSL(type, 结构追踪周期2, openPrice, atrH1, slH1);
   double minRisk = MathMax(atrH1 * 0.80, _Point * 50);

   if(type == POSITION_TYPE_BUY)
   {
      if(hasM30 && openPrice - slM30 >= minRisk) slPrice = slM30;
      else if(hasH1) slPrice = slH1;
      else slPrice = NormalizeTrendPriceToTick(openPrice - atrH1 * 1.20);
      if(openPrice - slPrice < minRisk) slPrice = NormalizeTrendPriceToTick(openPrice - minRisk);
      risk = openPrice - slPrice;
      return (risk > 0.0);
   }

   if(hasM30 && slM30 - openPrice >= minRisk) slPrice = slM30;
   else if(hasH1) slPrice = slH1;
   else slPrice = NormalizeTrendPriceToTick(openPrice + atrH1 * 1.20);
   if(slPrice - openPrice < minRisk) slPrice = NormalizeTrendPriceToTick(openPrice + minRisk);
   risk = slPrice - openPrice;
   return (risk > 0.0);
}

double TrendLongGetRisk(int stateIdx)
{
   if(stateIdx >= 0 && stateIdx < ArraySize(states) &&
      states[stateIdx].trendRiskReady && states[stateIdx].trendInitialRisk > 0.0)
      return states[stateIdx].trendInitialRisk;
   return 0.0;
}

bool TrendLongSLNotTooClose(ENUM_POSITION_TYPE type, double candidateSL, double bid, double ask, double atrH1)
{
   double minDistance = MathMax(atrH1 * 0.65, _Point * 50);
   if(type == POSITION_TYPE_BUY) return (bid - candidateSL >= minDistance);
   return (candidateSL - ask >= minDistance);
}

bool ApplyTrendLongProtection(int stateIdx, ENUM_POSITION_TYPE type, double openPrice, double curSL,
                              double bid, double ask, double profitPrice, double &newSL,
                              int &newSLSource, string &source)
{
   source = "";
   if(!当前模板使用黄金稳健止损() || stateIdx < 0 || stateIdx >= ArraySize(states) ||
      !states[stateIdx].trendRiskReady) return false;

   double atrH1 = 0.0;
   if(!TrendLongATR(趋势主周期, ATR周期, atrH1) || atrH1 <= 0.0)
      atrH1 = MathMax(GetRecentM1RangeAverage(14), 1.0);

   double risk = TrendLongGetRisk(stateIdx);
   if(risk <= 0.0) return false;

   // maxProfitPrice 已持久化；用它重建重启前的有利极值，避免另扫历史或让吊灯从当前价重新开始。
   if(type == POSITION_TYPE_BUY)
   {
      double recoveredHigh = openPrice+MathMax(states[stateIdx].maxProfitPrice, 0.0);
      if(states[stateIdx].trendHighSinceOpen <= 0.0) states[stateIdx].trendHighSinceOpen = MathMax(openPrice, bid);
      states[stateIdx].trendHighSinceOpen = MathMax(states[stateIdx].trendHighSinceOpen, MathMax(recoveredHigh, bid));
   }
   else
   {
      double recoveredLow = openPrice-MathMax(states[stateIdx].maxProfitPrice, 0.0);
      if(states[stateIdx].trendLowSinceOpen <= 0.0) states[stateIdx].trendLowSinceOpen = MathMin(openPrice, ask);
      states[stateIdx].trendLowSinceOpen = MathMin(states[stateIdx].trendLowSinceOpen, MathMin(recoveredLow, ask));
   }

   double profitR = profitPrice / risk;
   double maxR = states[stateIdx].maxProfitPrice / risk;
   int h1State = TrendLongH1State(type);
   bool changed = false;

   double lockR = -1.0;
   if(maxR >= 5.0) lockR = 2.0;
   else if(maxR >= 4.0) lockR = 1.5;
   else if(maxR >= 3.0) lockR = 1.0;
   else if(maxR >= 2.0) lockR = 0.5;
   else if(profitR >= MathMax(趋势单保本触发R, 1.0)) lockR = MathMax(趋势单保本锁定R, 0.10);

   if(lockR >= 0.0)
   {
      double minLock = (lockR <= 0.10 ? MathMax(risk * lockR, 0.50) : risk * lockR);
      double lockSL = NormalizeTrendPriceToTick((type == POSITION_TYPE_BUY) ? openPrice + minLock : openPrice - minLock);
      if(MoreProtective(type, lockSL, newSL))
      {
         newSL = lockSL;
         newSLSource = (lockR <= 0.10 ? SL来源_常规保本 : SL来源_其他);
         source = (lockR <= 0.10 ? "保本0.1R" : StringFormat("锁%.1fR", lockR));
         changed = true;
      }
   }

   if(profitR >= MathMax(趋势单移动止损启动R, 1.5))
   {
      double slM30 = 0.0, slH1 = 0.0;
      if(TrendLongStructureSL(type, 结构追踪周期1, (type == POSITION_TYPE_BUY ? bid : ask), atrH1, slM30) &&
         TrendLongSLNotTooClose(type, slM30, bid, ask, atrH1) &&
         MoreProtective(type, slM30, newSL))
      {
         newSL = slM30;
         newSLSource = SL来源_趋势ATR追踪;
         source = "M30结构SL";
         changed = true;
      }
      if(TrendLongStructureSL(type, 结构追踪周期2, (type == POSITION_TYPE_BUY ? bid : ask), atrH1, slH1) &&
         TrendLongSLNotTooClose(type, slH1, bid, ask, atrH1) &&
         MoreProtective(type, slH1, newSL))
      {
         newSL = slH1;
         newSLSource = SL来源_趋势ATR追踪;
         source = "H1结构SL";
         changed = true;
      }
   }

   if(maxR >= MathMax(趋势单强保护启动R, 2.0))
   {
      double coef = 趋势单ATR吊灯系数_普通;
      if(h1State >= 2) coef = 趋势单ATR吊灯系数_强趋势;
      else if(h1State <= 0) coef = 趋势单ATR吊灯系数_趋势减弱;

      double chandelier = (type == POSITION_TYPE_BUY) ?
         NormalizeTrendPriceToTick(states[stateIdx].trendHighSinceOpen - atrH1 * coef) :
         NormalizeTrendPriceToTick(states[stateIdx].trendLowSinceOpen + atrH1 * coef);
      if(TrendLongSLNotTooClose(type, chandelier, bid, ask, atrH1) &&
         MoreProtective(type, chandelier, newSL))
      {
         newSL = chandelier;
         newSLSource = SL来源_趋势ATR追踪;
         source = "ATR吊灯SL";
         changed = true;
      }
   }

   if(h1State < 0 && maxR >= 1.0)
   {
      double breakSL = (type == POSITION_TYPE_BUY) ?
         NormalizeTrendPriceToTick(MathMax(openPrice + risk * 0.10, bid - atrH1 * 1.20)) :
         NormalizeTrendPriceToTick(MathMin(openPrice - risk * 0.10, ask + atrH1 * 1.20));
      if(TrendLongSLNotTooClose(type, breakSL, bid, ask, atrH1) &&
         MoreProtective(type, breakSL, newSL))
      {
         newSL = breakSL;
         newSLSource = SL来源_其他;
         source = "趋势破坏收紧";
         changed = true;
      }
   }

   return changed;
}

string TrendLongProtectionText(double risk, double profitPrice, double maxProfitPrice)
{
   if(risk <= 0.0) return "未建R";
   double r = profitPrice / risk;
   double maxR = maxProfitPrice / risk;
   if(maxR >= 5.0) return "锁2R/结构追踪";
   if(maxR >= 4.0) return "锁1.5R";
   if(maxR >= 3.0) return "锁1R";
   if(maxR >= 2.0) return "锁0.5R";
   if(r >= 1.5) return "结构追踪中";
   if(r >= MathMax(趋势单保本触发R, 1.0)) return "已到保本区";
   return "未保本";
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price, _Digits);
}

double DistanceByMode(距离模式 mode, double fixedDistance, double atr, double atrMult)
{
   if(mode == 固定价格距离) return fixedDistance;
   if(mode == ATR倍数距离 && atr > 0) return atr * atrMult;
   return 0.0;
}

double ClampPriceDistance(double value, double minValue, double maxValue)
{
   double v = value;
   if(minValue > 0.0 && v < minValue) v = minValue;
   if(maxValue > 0.0 && maxValue >= minValue && v > maxValue) v = maxValue;
   return v;
}

void GetAdaptiveTrailConfig(double atr, double &trigger, double &distance, double &minStep)
{
   trigger  = 移动止损启动价格;
   distance = 移动止损距离价格;
   minStep  = 移动止损最小推进点数 * _Point;

   if(跟踪SL模式 == 追踪固定距离)
      return;

   // ATR来自M1，代表当前短线噪声宽度。波动越大，追踪越晚、越宽；波动越小，追踪自动收紧。
   if(atr > 0.0)
   {
      trigger  = ClampPriceDistance(atr * 动态追踪启动ATR倍数, 动态追踪最小启动价格, 动态追踪最大启动价格);
      distance = ClampPriceDistance(atr * 动态追踪距离ATR倍数, 动态追踪最小距离价格, 动态追踪最大距离价格);
      minStep  = MathMax(minStep, atr * 动态追踪最小推进ATR倍数);
   }

   if(trigger <= 0.0) trigger = 移动止损启动价格;
   if(distance <= 0.0) distance = 移动止损距离价格;
   if(minStep <= 0.0) minStep = _Point;
}

string FormatTrailModeName()
{
   if(跟踪SL模式 == 追踪固定距离) return "固定";
   if(跟踪SL模式 == 追踪ATR自适应) return "ATR";
   if(跟踪SL模式 == 追踪结构自适应) return "结构";
   return "M1前柱";
}

bool GetCachedM1Structure(double &minLow, double &maxHigh, datetime &lastClosedBarTime)
{
   minLow = 0.0;
   maxHigh = 0.0;
   lastClosedBarTime = 0;

   int n = MathMax(M1结构追踪K线数, 1);
   datetime lastClosedM1 = iTime(_Symbol, PERIOD_M1, 1);
   if(lastClosedM1 <= 0) return false;

   if(缓存M1结构有效 && 缓存M1结构BarTime == lastClosedM1 && 缓存M1结构K线数 == n)
   {
      minLow = 缓存M1结构Low;
      maxHigh = 缓存M1结构High;
      lastClosedBarTime = 缓存M1结构BarTime;
      return (minLow > 0.0 && maxHigh > 0.0);
   }

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, n, rates);
   if(copied < n) return false;

   minLow = rates[0].low;
   maxHigh = rates[0].high;
   for(int i=1; i<copied; i++)
   {
      if(rates[i].low < minLow) minLow = rates[i].low;
      if(rates[i].high > maxHigh) maxHigh = rates[i].high;
   }

   缓存M1结构Low = minLow;
   缓存M1结构High = maxHigh;
   缓存M1结构BarTime = rates[0].time;
   缓存M1结构K线数 = n;
   缓存M1结构有效 = true;
   lastClosedBarTime = 缓存M1结构BarTime;
   return true;
}

bool CalculateM1PreviousBarsStructureSL(ENUM_POSITION_TYPE type, double atr, double &candidateSL, double &minDistance, datetime &lastClosedBarTime)
{
   candidateSL = 0.0;
   minDistance = 0.0;
   lastClosedBarTime = 0;

   double minLow = 0.0;
   double maxHigh = 0.0;
   if(!GetCachedM1Structure(minLow, maxHigh, lastClosedBarTime)) return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return false;

   double spreadPrice = ask - bid;
   minDistance = MathMax(M1结构最小SL距离, spreadPrice * 3.0);
   if(atr > 0.0) minDistance = MathMax(minDistance, atr * M1结构最小SL距离ATR倍数);

   if(type == POSITION_TYPE_BUY)
   {
      candidateSL = NormalizePrice(minLow - M1结构SL缓冲价格);
      if(candidateSL <= 0.0 || candidateSL >= bid) return false;
      if((bid - candidateSL) < minDistance) return false;
      return true;
   }

   if(type == POSITION_TYPE_SELL)
   {
      candidateSL = NormalizePrice(maxHigh + M1结构SL缓冲价格);
      if(candidateSL <= 0.0 || candidateSL <= ask) return false;
      if((candidateSL - ask) < minDistance) return false;
      return true;
   }

   return false;
}

bool MoreProtective(ENUM_POSITION_TYPE type, double candidateSL, double currentSL)
{
   if(candidateSL <= 0) return false;
   if(currentSL <= 0) return true;
   if(type == POSITION_TYPE_BUY) return (candidateSL > currentSL);
   if(type == POSITION_TYPE_SELL) return (candidateSL < currentSL);
   return false;
}

bool SLTPValid(ENUM_POSITION_TYPE type, double sl, double tp)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0) return false;

   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist = MathMax(stopsLevel, freezeLevel) * _Point;

   if(type == POSITION_TYPE_BUY)
   {
      if(sl > 0 && sl >= bid) return false;
      if(tp > 0 && tp <= bid) return false;
      if(sl > 0 && (bid - sl) < minDist) return false;
      if(tp > 0 && (tp - bid) < minDist) return false;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      if(sl > 0 && sl <= ask) return false;
      if(tp > 0 && tp >= ask) return false;
      if(sl > 0 && (sl - ask) < minDist) return false;
      if(tp > 0 && (ask - tp) < minDist) return false;
   }

   return true;
}


double NormalizeVolumeDown(double volume)
{
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;

   volume = MathMax(0.0, MathMin(volume, maxVol));
   double steps = MathFloor(volume / step + 1e-8);
   double v = steps * step;

   int digits = 0;
   double tmpStep = step;
   while(tmpStep < 1.0 && digits < 8)
   {
      tmpStep *= 10.0;
      digits++;
   }
   return NormalizeDouble(v, digits);
}

bool GetPartialCloseVolume(double positionVolume, double &closeVolume)
{
   closeVolume = 0.0;
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(minVol <= 0.0) minVol = 0.01;
   if(step <= 0.0) step = 0.01;

   double ratio = MathMax(0.01, MathMin(分批止盈比例, 0.99));
   double rawClose = positionVolume * ratio;
   closeVolume = NormalizeVolumeDown(rawClose);

   if(closeVolume < minVol) return false;
   double remain = NormalizeVolumeDown(positionVolume - closeVolume);
   if(remain < minVol) return false;
   if(closeVolume >= positionVolume) return false;
   return true;
}

void GetShortLineStageBounds(int stage,
                             double &triggerBase, double &triggerMin, double &triggerMax,
                             double &ratioBase, double &ratioMin, double &ratioMax,
                             double &lockBase, double &lockMin, double &lockMax)
{
   stage = MathMax(1, MathMin(stage, 3));
   if(stage == 1)
   {
      triggerBase = 短线单第1段基础触发盈利;
      triggerMin = 短线单第1段最早触发盈利;
      triggerMax = 短线单第1段最晚触发盈利;
      ratioBase = 短线单第1段基础分批比例;
      ratioMin = 短线单第1段最小分批比例;
      ratioMax = 短线单第1段最大分批比例;
      lockBase = 短线单第1段基础锁定利润;
      lockMin = 短线单第1段最小锁定利润;
      lockMax = 短线单第1段最大锁定利润;
      return;
   }
   if(stage == 2)
   {
      triggerBase = 短线单第2段基础触发盈利;
      triggerMin = 短线单第2段最早触发盈利;
      triggerMax = 短线单第2段最晚触发盈利;
      ratioBase = 短线单第2段基础分批比例;
      ratioMin = 短线单第2段最小分批比例;
      ratioMax = 短线单第2段最大分批比例;
      lockBase = 短线单第2段基础锁定利润;
      lockMin = 短线单第2段最小锁定利润;
      lockMax = 短线单第2段最大锁定利润;
      return;
   }

   triggerBase = 短线单第3段基础触发盈利;
   triggerMin = 短线单第3段最早触发盈利;
   triggerMax = 短线单第3段最晚触发盈利;
   ratioBase = 短线单第3段基础分批比例;
   ratioMin = 短线单第3段最小分批比例;
   ratioMax = 短线单第3段最大分批比例;
   lockBase = 短线单第3段基础锁定利润;
   lockMin = 短线单第3段最小锁定利润;
   lockMax = 短线单第3段最大锁定利润;
}

double GetShortLineStageTriggerMin(int stage)
{
   stage = MathMax(1, MathMin(stage, 3));
   if(stage == 1) return 短线单第1段最早触发盈利;
   if(stage == 2) return 短线单第2段最早触发盈利;
   return 短线单第3段最早触发盈利;
}

double GetShortLineDynamicPartialTrigger(int stage, const ShortLineMarketContext &ctx,
                                         double baseMainTP, double initialRisk=0.0)
{
   double triggerBase, triggerMin, triggerMax, ratioBase, ratioMin, ratioMax, lockBase, lockMin, lockMax;
   GetShortLineStageBounds(stage, triggerBase, triggerMin, triggerMax, ratioBase, ratioMin, ratioMax, lockBase, lockMin, lockMax);

   double v = triggerBase;
   if(ctx.strongForPosition)
   {
      v += (stage == 1 ? 0.30 : (stage == 2 ? 0.55 : 0.85));
   }
   else if(ctx.choppyForPosition || ctx.momentumWeak)
   {
      v -= (stage == 1 ? 0.30 : (stage == 2 ? 0.50 : 0.70));
   }
   if(ctx.nearBoxEdge)
      v -= ctx.strongForPosition ? (stage == 1 ? 0.08 : (stage == 2 ? 0.15 : 0.25))
                                 : (stage == 1 ? 0.20 : (stage == 2 ? 0.35 : 0.50));
   if(ctx.avgRange3 > 0.0 && ctx.atrM1 > ctx.avgRange3 * 1.25)
      v += (stage == 1 ? 0.15 : (stage == 2 ? 0.30 : 0.45));

   if(baseMainTP > 0.0 && stage >= 2)
      v = MathMin(v, baseMainTP * (stage == 2 ? 0.85 : 1.05));

   // 先限制行情微调，再应用真实初始风险和当前波动下限。
   // floor是安全下限，不能再被固定“最晚触发”上限反向截断。
   double adaptiveTrigger = ClampDouble(v, MathMax(triggerMin, 0.10), MathMax(triggerMax, triggerMin));
   double riskFloor = 0.0;
   if(initialRisk > 0.0)
      riskFloor = initialRisk * (stage == 1 ? 0.70 : (stage == 2 ? 1.10 : 1.50));
   double volatilityFloor = ctx.atrM1 * (stage == 1 ? 1.30 : (stage == 2 ? 1.90 : 2.50));
   return MathMax(adaptiveTrigger, MathMax(riskFloor, volatilityFloor));
}

double GetShortLineDynamicPartialRatio(int stage, const ShortLineMarketContext &ctx)
{
   // 两段策略的仓位比例不再随行情动态漂移：首段固定平初始仓位40%，次段由全平路径收完剩余。
   if(stage == 1) return 0.40;
   return 1.00;
}

double GetShortLineDynamicStageLockProfit(int stage, const ShortLineMarketContext &ctx)
{
   double triggerBase, triggerMin, triggerMax, ratioBase, ratioMin, ratioMax, lockBase, lockMin, lockMax;
   GetShortLineStageBounds(stage, triggerBase, triggerMin, triggerMax, ratioBase, ratioMin, ratioMax, lockBase, lockMin, lockMax);

   double v = lockBase;
   if(ctx.strongForPosition)
   {
      v -= (stage == 1 ? 0.05 : (stage == 2 ? 0.30 : 0.55));
   }
   else if(ctx.choppyForPosition || ctx.momentumWeak)
   {
      v += (stage == 1 ? 0.07 : (stage == 2 ? 0.35 : 0.55));
   }
   if(ctx.nearBoxEdge)
      v += ctx.strongForPosition ? (stage == 1 ? 0.02 : (stage == 2 ? 0.08 : 0.12))
                                 : (stage == 1 ? 0.04 : (stage == 2 ? 0.20 : 0.30));

   return ClampDouble(v, MathMax(lockMin, 0.0), MathMax(lockMax, lockMin));
}

int GetShortLineNextPartialStage(int stateIdx, ENUM_POSITION_TYPE type, double openPrice,
                                 double profitPrice, const ShortLineMarketContext &ctx,
                                 double baseMainTP, bool rhythmSignal)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return 0;
   int maxStage = MathMin(MathMax(短线单最大分批段数, 1), 2);
   int nextStage = states[stateIdx].partialTPStage + 1;
   if(nextStage > maxStage || nextStage > 2) return 0;

   double trigger = ShortLineEffectivePartialTrigger(stateIdx, type, openPrice, nextStage, ctx, baseMainTP);
   if(profitPrice >= trigger) return nextStage;

   // M1节奏/箱体边缘只能提前一点点，不能让第一段在1.8-2.0美元附近过早触发。
   double stageMin = GetShortLineStageTriggerMin(nextStage);
   double riskFloor = states[stateIdx].shortInitialRisk *
                      (nextStage == 1 ? 0.70 : (nextStage == 2 ? 1.10 : 1.50));
   double volatilityFloor = ctx.atrM1 *
                            (nextStage == 1 ? 1.30 : (nextStage == 2 ? 1.90 : 2.50));
   double earlyTrigger = MathMax(MathMax(stageMin, trigger * 0.90),
                                 MathMax(riskFloor, volatilityFloor));
   if(profitPrice >= earlyTrigger &&
      (rhythmSignal || ctx.choppyForPosition || ctx.momentumWeak || ctx.nearBoxEdge))
      return nextStage;

   return 0;
}

bool GetShortLineStagePartialCloseVolume(int stage, double initialVolume, double currentVolume,
                                         double dynamicRatio, double &closeVolume)
{
   closeVolume = 0.0;
   if(stage != 1) return false; // 第二段必须走全平确认路径，不能再作为部分平仓计算。
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(minVol <= 0.0) minVol = 0.01;
   double minRemain = MathMax(minVol, MathMax(短线单多段分批最小剩余手数, 0.0));
   // 第一段40%始终以首次接管时的初始手数为基准，不能随剩余手数漂移。
   double baseVolume = initialVolume;
   if(baseVolume <= 0.0) return false;

   closeVolume = NormalizeVolumeDown(baseVolume * ClampDouble(dynamicRatio, 0.01, 0.95));
   if(closeVolume < minVol) return false;
   if(closeVolume >= currentVolume) return false;

   double remain = NormalizeVolumeDown(currentVolume - closeVolume);
   if(remain < minRemain) return false;
   return true;
}

void GetShortLineDynamicDrawdownProtection(const ShortLineMarketContext &ctx,
                                           double &startProfit, double &drawdownRatio, double &lockRatio)
{
   startProfit = 5.00;
   drawdownRatio = 0.45;
   lockRatio = 0.48;

   if(ctx.strongForPosition)
   {
      startProfit = 5.80;
      drawdownRatio = 0.50;
      lockRatio = 0.44;
   }
   else if(ctx.choppyForPosition || ctx.momentumWeak)
   {
      startProfit = 4.60;
      drawdownRatio = 0.40;
      lockRatio = 0.52;
   }
   if(ctx.nearBoxEdge)
   {
      drawdownRatio -= ctx.strongForPosition ? 0.01 : 0.02;
      lockRatio += ctx.strongForPosition ? 0.01 : 0.03;
   }

   startProfit = ClampDouble(startProfit, 4.50, 6.50);
   drawdownRatio = ClampDouble(drawdownRatio, 0.38, 0.52);
   lockRatio = ClampDouble(lockRatio, 0.40, 0.58);
}

bool ShortLineM1StallingForPartial(ENUM_POSITION_TYPE type, double atr, double profitPrice, double maxProfitPrice)
{
   double unit = GetShortLineVolatilityUnit(atr);
   bool weakMomentum = !ShortLineM1MomentumWithPosition(type);
   bool profitPullback = (maxProfitPrice > profitPrice &&
                          (maxProfitPrice - profitPrice) >= unit * MathMax(短线单分批动能回撤ATR倍数, 0.0));

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   // 短线节奏判断只使用已收线M1，避免当前未收K线跳动导致分批信号反复变。
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, 4, rates);
   if(copied < 2) return (weakMomentum || profitPullback);

   double ratioSum = 0.0;
   int ratioCount = 0;
   for(int i=0; i<copied; i++)
   {
      double range = rates[i].high - rates[i].low;
      if(range <= 0.0) continue;
      ratioSum += MathAbs(rates[i].close - rates[i].open) / range;
      ratioCount++;
   }

   bool smallBodies = false;
   if(ratioCount > 0)
      smallBodies = ((ratioSum / ratioCount) <= MathMax(短线单分批震荡实体比例上限, 0.05));

   return (weakMomentum || smallBodies || profitPullback);
}

bool ShortLineNearLocalExtremeForPartial(ENUM_POSITION_TYPE type, double atr, double openPrice,
                                         double &targetPrice, double &distance)
{
   targetPrice = 0.0;
   distance = 0.0;

   int lookback = MathMax(短线单分批局部高低回看M1, 2);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   // 局部高低点只取已收线M1，避免用未收线高低点提前误触发。
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, lookback, rates);
   if(copied < 2) return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return false;

   double localHigh = rates[0].high;
   double localLow = rates[0].low;
   for(int i=1; i<copied; i++)
   {
      if(rates[i].high > localHigh) localHigh = rates[i].high;
      if(rates[i].low < localLow) localLow = rates[i].low;
   }

   double buffer = MathMax(短线单分批靠近高低点最小价格,
                           GetShortLineVolatilityUnit(atr) * MathMax(短线单分批靠近高低点ATR倍数, 0.01));

   if(type == POSITION_TYPE_BUY)
   {
      targetPrice = localHigh;
      distance = localHigh - bid;
      if(distance < 0.0) distance = 0.0;
      if((targetPrice - openPrice) < MathMax(短线单分批最小浮盈价格, 0.0)) return false;
      return (distance <= buffer);
   }

   if(type == POSITION_TYPE_SELL)
   {
      targetPrice = localLow;
      distance = ask - localLow;
      if(distance < 0.0) distance = 0.0;
      if((openPrice - targetPrice) < MathMax(短线单分批最小浮盈价格, 0.0)) return false;
      return (distance <= buffer);
   }

   return false;
}

bool ShortLineProfitProtectionPartial(int stateIdx, ENUM_POSITION_TYPE type, double atr, double openPrice,
                                      double profitPrice, double maxProfitPrice,
                                      double &targetPrice, double &distance)
{
   targetPrice = 0.0;
   distance = 0.0;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return false;

   double unit = GetShortLineVolatilityUnit(atr);
   bool teacherSelected = false;
   double teacherTarget = 0.0;
   double mainTP = ShortLineEffectiveMainTPDistance(stateIdx, type, openPrice, atr,
                                                     teacherSelected, teacherTarget);
   double protectStart = MathMax(短线单分批利润保护启动价格,
                                 mainTP > 0.0 ? mainTP * MathMax(短线单分批主TP保护比例, 0.10) : 0.0);
   if(profitPrice >= protectStart)
   {
      targetPrice = (type == POSITION_TYPE_BUY) ? bid : ask;
      distance = 0.0;
      return true;
   }

   double givebackNeed = MathMax(短线单分批利润回吐保护价格,
                                 unit * MathMax(短线单分批利润回吐ATR倍数, 0.0));
   if(maxProfitPrice >= protectStart &&
      profitPrice > 0.0 &&
      (maxProfitPrice - profitPrice) >= givebackNeed)
   {
      targetPrice = (type == POSITION_TYPE_BUY) ? bid : ask;
      distance = maxProfitPrice - profitPrice;
      return true;
   }

   return false;
}

bool ShouldShortLineDynamicPartialTakeProfit(int stateIdx, ENUM_POSITION_TYPE type, double openPrice,
                                             double profitPrice, double &targetPrice, double &distance)
{
   targetPrice = 0.0;
   distance = 0.0;
   if(当前参数配置模板 != 配置_黄金超短快保) return false;
   if(!短线单分批使用行情节奏) return false;

   double atr = 0.0;
   GetATRPrice(atr);
   double unit = GetShortLineVolatilityUnit(atr);
   double minProfit = MathMax(短线单分批最小浮盈价格, unit * MathMax(短线单分批最小浮盈ATR倍数, 0.0));
   if(profitPrice < minProfit) return false;

   double maxProfitPrice = (stateIdx >= 0 && stateIdx < ArraySize(states)) ? states[stateIdx].maxProfitPrice : profitPrice;
   if(ShortLineProfitProtectionPartial(stateIdx, type, atr, openPrice, profitPrice, maxProfitPrice, targetPrice, distance))
      return true;

   bool teacherSelected = false;
   double teacherTarget = 0.0;
   double mainTP = ShortLineEffectiveMainTPDistance(stateIdx, type, openPrice, atr,
                                                     teacherSelected, teacherTarget);
   if(mainTP > 0.0 && profitPrice >= mainTP * ClampDouble(短线单分批主TP比例上限, 0.10, 1.00))
      return false; // 已接近主TP时不再用“节奏提前分批”抢跑，交给固定TP或尾仓保护。

   if(ShortLineStrongTrendWithPosition(type, atr, profitPrice, maxProfitPrice))
      return false;

   if(!ShortLineM1StallingForPartial(type, atr, profitPrice, maxProfitPrice))
      return false;

   return ShortLineNearLocalExtremeForPartial(type, atr, openPrice, targetPrice, distance);
}

bool ShouldPartialTakeProfit(int stateIdx, ENUM_POSITION_TYPE type, double openPrice, double volume, double profitPrice, double &targetPrice, double &distance)
{
   targetPrice = 0.0;
   distance = 0.0;
   if(!启用分批止盈) return false;
   if(profitPrice < 分批止盈最小浮盈价格) return false;

   // 短线单使用风险R+波动TP时，分批止盈按M1局部高低点和动能犹豫判断，不再死等R/S。
   if(当前参数配置模板 == 配置_黄金超短快保)
   {
      if(短线单分批使用行情节奏)
         return ShouldShortLineDynamicPartialTakeProfit(stateIdx, type, openPrice, profitPrice, targetPrice, distance);
      return false;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return false;

   double touchBuffer = MathMax(分批止盈接近点位距离, _Point * 2);

   // 支压手控版已关闭自动分段止盈；以下分支仅在重新启用 当前模板使用支压分段止盈() 时生效。
   if(当前模板使用支压分段止盈())
   {
      if(type == POSITION_TYPE_BUY)
      {
         if(ArraySize(缓存压力位) < 1) return false;
         targetPrice = 缓存压力位[0].price;
         distance = targetPrice - bid;
         return (bid >= targetPrice - touchBuffer);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         if(ArraySize(缓存支撑位) < 1) return false;
         targetPrice = 缓存支撑位[0].price;
         distance = ask - targetPrice;
         return (ask <= targetPrice + touchBuffer);
      }
      return false;
   }

   SRLevel level;
   if(type == POSITION_TYPE_BUY)
   {
      if(!GetNearestResistance(bid, level)) return false;
      targetPrice = level.price;
      distance = level.price - bid;
      if(distance < 0.0) return false;
      double targetSpace = targetPrice - openPrice;
      if(分批止盈目标最小空间价格 > 0.0 && targetSpace < 分批止盈目标最小空间价格) return false;
      return (distance <= 分批止盈接近点位距离);
   }
   else if(type == POSITION_TYPE_SELL)
   {
      if(!GetNearestSupport(ask, level)) return false;
      targetPrice = level.price;
      distance = ask - level.price;
      if(distance < 0.0) return false;
      double targetSpace = openPrice - targetPrice;
      if(分批止盈目标最小空间价格 > 0.0 && targetSpace < 分批止盈目标最小空间价格) return false;
      return (distance <= 分批止盈接近点位距离);
   }
   return false;
}

bool ShouldFullTakeProfitAtSecondSR(ENUM_POSITION_TYPE type, double profitPrice, double &targetPrice, double &distance)
{
   targetPrice = 0.0;
   distance = 0.0;
   if(!当前模板使用支压分段止盈()) return false;
   if(profitPrice < 0.0) return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return false;

   double touchBuffer = MathMax(分批止盈接近点位距离, _Point * 2);
   if(type == POSITION_TYPE_BUY)
   {
      if(ArraySize(缓存压力位) < 2) return false;
      targetPrice = 缓存压力位[1].price;
      distance = targetPrice - bid;
      return (bid >= targetPrice - touchBuffer);
   }
   else if(type == POSITION_TYPE_SELL)
   {
      if(ArraySize(缓存支撑位) < 2) return false;
      targetPrice = 缓存支撑位[1].price;
      distance = ask - targetPrice;
      return (ask <= targetPrice + touchBuffer);
   }
   return false;
}

bool ExecuteFullTakeProfitAtSecondSR(ulong ticket, int stateIdx, ENUM_POSITION_TYPE type, double profitPrice)
{
   if(!当前模板使用支压分段止盈()) return false;

   double targetPrice = 0.0;
   double distance = 0.0;
   if(!ShouldFullTakeProfitAtSecondSR(type, profitPrice, targetPrice, distance))
      return false;

   if(!ModifyFrequencyOK(stateIdx))
   {
      lastStatus = "二级支压全止盈等待: 修改间隔保护";
      return true;
   }

   if(SubmitManagedFullClose(ticket, stateIdx, 退出意图_二级支压全收, "secondary_sr_take_profit"))
   {
      string dir = (type == POSITION_TYPE_BUY) ? "多" : "空";
      lastStatus = StringFormat("二级支压全止盈: %s 触达%.2f 距%.2f", dir, targetPrice, distance);
      return true;
   }

   lastStatus = StringFormat("二级支压全止盈失败 ticket=%I64u ret=%d %s", ticket, manageTrade.ResultRetcode(), manageTrade.ResultComment());
   return true; // 已触发二级线，避免同一轮退而执行R1平半；下个tick继续尝试全平。
}

bool ExecuteShortLineMultiStagePartial(ulong ticket, int stateIdx, ENUM_POSITION_TYPE type,
                                       double openPrice, double volume, double profitPrice, double atr,
                                       const ShortLineMarketContext &marketCtx, bool hasMarketCtx)
{
   if(当前参数配置模板 != 配置_黄金超短快保) return false;
   if(!短线单启用多段分批止盈) return false;
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return false;
   if(!states[stateIdx].shortRiskReady) return false;
   if(states[stateIdx].partialRequestPending) return true;
   if(states[stateIdx].partialTPStage >= MathMin(MathMax(短线单最大分批段数, 1), 2)) return false;
   if(states[stateIdx].lastPartialTPTime > 0 &&
      TimeCurrent() - states[stateIdx].lastPartialTPTime < MathMax(短线单分批最小间隔秒, 0))
      return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return false;

   ShortLineMarketContext ctx = marketCtx;
   if(!hasMarketCtx)
   {
      InitShortLineMarketContext(ctx);
      ctx.atrM1 = GetShortLineVolatilityUnit(atr);
      ctx.atrM5 = ctx.atrM1;
   }

   bool teacherSelected = false;
   double teacherTarget = 0.0;
   double baseMainTP = ShortLineEffectiveMainTPDistance(stateIdx, type, openPrice, atr,
                                                         teacherSelected, teacherTarget);
   double rhythmTarget = 0.0;
   double rhythmDistance = 0.0;
   bool rhythmSignal = ShouldShortLineDynamicPartialTakeProfit(stateIdx, type, openPrice, profitPrice, rhythmTarget, rhythmDistance);
   int stage = GetShortLineNextPartialStage(stateIdx, type, openPrice, profitPrice, ctx,
                                             baseMainTP, rhythmSignal);
   if(stage <= 0) return false;
   double effectiveTrigger = ShortLineEffectivePartialTrigger(stateIdx, type, openPrice,
                                                               stage, ctx, baseMainTP);
   double riskFloor = states[stateIdx].shortInitialRisk *
                      (stage == 1 ? 0.70 : (stage == 2 ? 1.10 : 1.50));
   double volatilityFloor = ctx.atrM1 *
                            (stage == 1 ? 1.30 : (stage == 2 ? 1.90 : 2.50));
   string triggerAudit = StringFormat("stage=%d;effective_trigger=%.5f;risk_floor=%.5f;volatility_floor=%.5f;teacher=%d;teacher_target=%.5f",
                                      stage, effectiveTrigger, riskFloor, volatilityFloor,
                                      teacherSelected ? 1 : 0, teacherTarget);

   // 首段真实成交确认后，第二段直接收完服务器上的全部剩余仓位。
   // 完成状态仍由OnTradeTransaction中的真实退出Deal/持仓消失确认，不能以请求返回值提前推进。
   if(stage == 2)
   {
      if(!ModifyFrequencyOK(stateIdx))
      {
         lastStatus = "短线第2段全收等待: 修改间隔保护";
         return true;
      }

      if(SubmitManagedFullClose(ticket, stateIdx, 退出意图_分批止盈,
                                "short_stage2_close_remaining;" + triggerAudit))
      {
         lastStatus = StringFormat("短线第2段全收请求已发送: 剩余%.2f手，等待真实Deal确认 盈%.2f %s",
                                   volume, profitPrice, ShortLineContextTag(ctx));
         return true;
      }

      lastStatus = StringFormat("短线第2段全收失败 ticket=%I64u ret=%d %s",
                                ticket, manageTrade.ResultRetcode(), manageTrade.ResultComment());
      return false;
   }

   double ratio = GetShortLineDynamicPartialRatio(stage, ctx);
   double closeVolume = 0.0;
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(minVol <= 0.0) minVol = 0.01;
   double fullCloseNeed = MathMax(短线单分批手数不足全平最小盈利,
                                   ShortLineEffectivePartialTrigger(stateIdx, type, openPrice,
                                                                    stage, ctx, baseMainTP));
   if(volume <= minVol + 0.0000001 &&
      短线单分批手数不足则全平 &&
      profitPrice >= fullCloseNeed)
   {
      if(!ModifyFrequencyOK(stateIdx))
      {
         lastStatus = "短线全收等待: 修改间隔保护";
         return true;
      }

      if(SubmitManagedFullClose(ticket, stateIdx, 退出意图_分批止盈,
                                "short_volume_too_small;" + triggerAudit))
      {
         lastStatus = StringFormat("短线全收: 0.01手无法分批，盈利%.2f直接收", profitPrice);
         return true;
      }

      lastStatus = StringFormat("短线全收失败 ticket=%I64u ret=%d %s", ticket, manageTrade.ResultRetcode(), manageTrade.ResultComment());
      return false;
   }

   if(!GetShortLineStagePartialCloseVolume(stage, states[stateIdx].initialVolume, volume, ratio, closeVolume))
   {
      if(!短线单多段分批不足则跳过 &&
         短线单分批手数不足则全平 &&
         profitPrice >= fullCloseNeed)
      {
         if(!ModifyFrequencyOK(stateIdx))
         {
            lastStatus = "短线全收等待: 修改间隔保护";
            return true;
         }

         if(SubmitManagedFullClose(ticket, stateIdx, 退出意图_分批止盈,
                                   "short_stage_volume_too_small;" + triggerAudit))
         {
            lastStatus = StringFormat("短线全收: 第%d段手数不足，盈利%.2f直接收", stage, profitPrice);
            return true;
         }

         lastStatus = StringFormat("短线全收失败 ticket=%I64u ret=%d %s", ticket, manageTrade.ResultRetcode(), manageTrade.ResultComment());
         return false;
      }

      lastStatus = "短线分批跳过: 手数太小，交给保本/结构追踪";
      return false;
   }

   // 同一阶段曾部分成交后，只补齐阶段目标，绝不再次按完整目标手数重复平仓。
   double alreadyFilled = ShortStageFilledVolume(stateIdx, stage);
   if(alreadyFilled > 0.0)
   {
      closeVolume = NormalizeVolumeDown(closeVolume-alreadyFilled);
      if(closeVolume < minVol)
      {
         lastStatus = "短线分批等待: 本阶段已成交量接近目标";
         return true;
      }
   }

   if(!ModifyFrequencyOK(stateIdx))
   {
      lastStatus = "短线分批等待: 修改间隔保护";
      return true;
   }

   if(SubmitManagedPartialClose(ticket, stateIdx, closeVolume, stage, 退出意图_分批止盈,
                                "short_multistage;" + triggerAudit))
   {
      lastStatus = StringFormat("短线第%d段请求已发送: %.2f手，等待真实Deal确认 盈%.2f %s", stage, closeVolume, profitPrice, ShortLineContextTag(ctx));
      return true;
   }
   lastStatus = StringFormat("短线分批失败 ticket=%I64u ret=%d %s", ticket, manageTrade.ResultRetcode(), manageTrade.ResultComment());
   return false;
}

bool ExecutePartialTakeProfit(ulong ticket, int stateIdx, ENUM_POSITION_TYPE type, double openPrice,
                              double volume, double profitPrice, double atr,
                              const ShortLineMarketContext &shortCtx, bool hasShortCtx)
{
   if(!启用分批止盈) return false;
   if(当前参数配置模板 == 配置_黄金超短快保 && 短线单启用多段分批止盈)
      return ExecuteShortLineMultiStagePartial(ticket, stateIdx, type, openPrice, volume, profitPrice,
                                                atr, shortCtx, hasShortCtx);
   if(states[stateIdx].partialTPDone) return false;

   double targetPrice = 0.0;
   double distance = 0.0;
   if(!ShouldPartialTakeProfit(stateIdx, type, openPrice, volume, profitPrice, targetPrice, distance))
      return false;

   double closeVolume = 0.0;
   if(!GetPartialCloseVolume(volume, closeVolume))
   {
      if(当前参数配置模板 == 配置_黄金超短快保 &&
         短线单分批手数不足则全平 &&
         profitPrice >= MathMax(短线单分批手数不足全平最小盈利, 短线单分批利润保护启动价格))
      {
         if(!ModifyFrequencyOK(stateIdx))
         {
            lastStatus = "短线收菜等待: 修改间隔保护";
            return true;
         }

         if(SubmitManagedFullClose(ticket, stateIdx, 退出意图_分批止盈, "normal_partial_volume_too_small"))
         {
            string dirFull = (type == POSITION_TYPE_BUY) ? "多" : "空";
            lastStatus = StringFormat("短线全收: %s 手数不足分批，盈利%.2f直接收", dirFull, profitPrice);
            return true;
         }

         lastStatus = StringFormat("短线全收失败 ticket=%I64u ret=%d %s", ticket, manageTrade.ResultRetcode(), manageTrade.ResultComment());
         return false;
      }

      lastStatus = "分批止盈跳过: 手数不足以部分平仓";
      return false;
   }

   if(!ModifyFrequencyOK(stateIdx)) return false;

   if(SubmitManagedPartialClose(ticket, stateIdx, closeVolume, 1, 退出意图_分批止盈, "normal_partial"))
   {
      string dir = (type == POSITION_TYPE_BUY) ? "多" : "空";
      lastStatus = StringFormat("分批止盈请求: %s %.2f手，等待真实Deal 点位%.2f 距%.2f", dir, closeVolume, targetPrice, distance);
      return true;
   }

   lastStatus = StringFormat("分批止盈失败 ticket=%I64u ret=%d %s", ticket, manageTrade.ResultRetcode(), manageTrade.ResultComment());
   return false;
}

bool ExecuteShortLineRecoveryExit(ulong ticket, int stateIdx, ENUM_POSITION_TYPE type, double profitPrice, double atr)
{
   if(当前参数配置模板 != 配置_黄金超短快保) return false;
   if(!短线单浮亏回本直接平仓) return false;
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || !states[stateIdx].recoveryArmed) return false;
   double armTolerance = MathMax(_Point * 0.5, 0.00000001);
   if(states[stateIdx].recoveryArmedTime <= 0 ||
      states[stateIdx].recoveryArmLossPrice <= 0.0 ||
      states[stateIdx].recoveryArmTrigger <= 0.0 ||
      states[stateIdx].recoveryArmLossPrice + armTolerance < states[stateIdx].recoveryArmTrigger)
   {
      states[stateIdx].recoveryArmed = false;
      states[stateIdx].recoveryArmedTime = 0;
      states[stateIdx].recoveryArmLossPrice = 0.0;
      states[stateIdx].recoveryArmTrigger = 0.0;
      MarkShortStateDirty(stateIdx);
      ShortStateSave(stateIdx);
      TradeJournalWriteLifecycle(stateIdx, "RECOVERY_DISARMED",
                                 "runtime_arm_invariant_failed;fail_closed");
      return false;
   }
   double lossTrigger = states[stateIdx].recoveryArmTrigger;
   double profitMin = ShortLineDynamicRecoveryProfitMin(atr);
   if(profitPrice < profitMin) return false;
   // 深亏后的回本只允许“当前利润已经走出来”时豁免；历史峰值不能压制本次小幅回本退出。
   if(ShortLineStrongTrendWithPosition(type, atr, profitPrice, 0.0)) return false;

   double knownEntryCost = 0.0;
   if(!EnsureEntryCostCache(stateIdx))
   {
      lastStatus = "短线回本快收等待: 入场成本暂不可读";
      PrintRateLimited(StringFormat("recovery_cost_wait:%I64u", ticket), 10,
                       StringFormat("[短线回本] 入场成本暂不可读 ticket=%I64u，暂不按回本退出", ticket));
      return false;
   }
   knownEntryCost = states[stateIdx].cachedEntryCost;
   double volume = PositionGetDouble(POSITION_VOLUME);
   double safetyMoney = MathMax(短线单净保本安全金额每001手, 0.0) * volume / 0.01;
   double knownCostNet = PositionGetDouble(POSITION_PROFIT) +
                         PositionGetDouble(POSITION_SWAP) +
                         knownEntryCost;
   if(knownCostNet < safetyMoney)
   {
      lastStatus = StringFormat("短线回本快收等待: 已知成本后净额 %.2f < 安全 %.2f",
                                knownCostNet, safetyMoney);
      return false;
   }

   if(!ModifyFrequencyOK(stateIdx))
   {
      lastStatus = "短线回本快收等待: 修改间隔保护";
      return true;
   }

   TradeJournalWriteLifecycle(stateIdx, "RECOVERY_CLOSE_REQUEST",
                              StringFormat("armed_time=%d;arm_loss=%.5f;frozen_trigger=%.5f;recovery_profit=%.5f;known_cost_net=%.2f;safety_money=%.2f",
                                           (int)states[stateIdx].recoveryArmedTime,
                                           states[stateIdx].recoveryArmLossPrice,
                                           lossTrigger, profitPrice, knownCostNet, safetyMoney));
   // 失败请求也必须进入现有修改冷却，避免每个市场Tick连续重发。
   states[stateIdx].lastManagedModifyTime = TimeCurrent();
   MarkShortStateDirty(stateIdx);
   ShortStateSave(stateIdx);
   if(SubmitManagedFullClose(ticket, stateIdx, 退出意图_回本退出, "recovery_close"))
   {
      lastStatus = StringFormat("短线回本快收: 武装浮亏%.2f/阈%.2f，已知成本后净额%.2f，等待真实Deal",
                                states[stateIdx].recoveryArmLossPrice, lossTrigger, knownCostNet);
      return true;
   }

   lastStatus = StringFormat("短线回本快收失败 ticket=%I64u ret=%d %s", ticket, manageTrade.ResultRetcode(), manageTrade.ResultComment());
   // 回本全退意图已成立；即使本次请求失败，也不能在同一Tick降级执行分批或其他修改。
   return true;
}

//===================== 消息对冲状态机 =====================//
string NewsHedgeKey(string suffix)
{
   return "SMA_NH_" + IntegerToString((long)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + _Symbol + "_" + suffix;
}

void NewsHedgeWriteUlong(string suffix, ulong value)
{
   GlobalVariableSet(NewsHedgeKey(suffix+"L"), (double)(uint)(value & 0xFFFFFFFF));
   GlobalVariableSet(NewsHedgeKey(suffix+"H"), (double)(uint)(value >> 32));
}

ulong NewsHedgeReadUlong(string suffix)
{
   ulong low=(ulong)(uint)MathRound(NewsHedgeRead(suffix+"L"));
   ulong high=(ulong)(uint)MathRound(NewsHedgeRead(suffix+"H"));
   return low | (high << 32);
}

void NewsHedgeDeletePersistence()
{
   string keys[] = {"VER","ST","ATM","BT","STK","RT","LT","BI","SI","RI","LI","BOP","SOP","PT","UT","UTM","UP","IGR","LDR","RRR","ARSL","LCP","LCT","GFS","AUE","AUS","REP","LET","RPH",
                    "MPP","MPA","MPC","MPST","MPI","MIE","FPD","SPD","REF","RH","RL","ATR","HSD","DIR",
                    "BV","BFT","BW","BHT","BLT","BMC","BCI","NSP","IB","BB","FB","BFU","REL","RELT","RELE","RSM",
                    "DB","BDSL","SDSL","RSL","RBP",
                    "BPR","PLM","RLM","COST","AC","REC","RRP","RPE","MAX","RIV","HI","LO","PS","RPP","RPTS","RPSV","RPTV","RPSE","RPFV","RPRV","RPRT","RREV","RAC","LPT","LSB",
                     "LLD","LRD","PDEAL","PDC","LDN","LAK",
                     "NSS","NST","NSBL","NSBH","NSSL","NSSH","NSRQ","NSEX","NSBD","NSSD","NSBT","NSST"};
   for(int i=0; i<ArraySize(keys); i++)
      GlobalVariableDel(NewsHedgeKey(keys[i]));
   for(int i=0; i<NEWS_PENDING_DEAL_CAPACITY; i++)
      GlobalVariableDel(NewsHedgeKey("PD"+IntegerToString(i)));
}

void NewsHedgeSaveState(bool force=true)
{
   datetime now = TimeCurrent();
   if(!force && 上次消息状态保存时间 > 0 && now == 上次消息状态保存时间) return;
   上次消息状态保存时间 = now;
   GlobalVariableSet(NewsHedgeKey("VER"), 7.0);
   GlobalVariableSet(NewsHedgeKey("ST"),  newsState.stage);
   GlobalVariableSet(NewsHedgeKey("ATM"), newsState.adoptedTemplate);
   GlobalVariableSet(NewsHedgeKey("BT"),  (double)newsState.buyTicket);
   GlobalVariableSet(NewsHedgeKey("STK"), (double)newsState.sellTicket);
   GlobalVariableSet(NewsHedgeKey("RT"),  (double)newsState.runnerTicket);
   GlobalVariableSet(NewsHedgeKey("LT"),  (double)newsState.loserTicket);
   GlobalVariableSet(NewsHedgeKey("BI"),  (double)newsState.buyPositionId);
   GlobalVariableSet(NewsHedgeKey("SI"),  (double)newsState.sellPositionId);
   GlobalVariableSet(NewsHedgeKey("RI"),  (double)newsState.runnerPositionId);
   GlobalVariableSet(NewsHedgeKey("LI"),  (double)newsState.loserPositionId);
   GlobalVariableSet(NewsHedgeKey("BOP"), newsState.buyOpenPrice);
   GlobalVariableSet(NewsHedgeKey("SOP"), newsState.sellOpenPrice);
   GlobalVariableSet(NewsHedgeKey("PT"),  (double)newsState.pairTime);
   GlobalVariableSet(NewsHedgeKey("UT"),  (double)newsState.unhedgeTime);
   GlobalVariableSet(NewsHedgeKey("UTM"), (double)newsState.unhedgeTimeMs);
   GlobalVariableSet(NewsHedgeKey("UP"),  newsState.unhedgePrice);
   GlobalVariableSet(NewsHedgeKey("IGR"), newsState.initialGroupRiskMoney);
   GlobalVariableSet(NewsHedgeKey("LDR"), newsState.loserDealReady ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("RRR"), newsState.runnerRiskReady ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("ARSL"),newsState.actualRunnerRiskSL);
   GlobalVariableSet(NewsHedgeKey("LCP"), newsState.loserClosePrice);
   GlobalVariableSet(NewsHedgeKey("LCT"), (double)newsState.loserCloseTimeMsc);
   GlobalVariableSet(NewsHedgeKey("GFS"), (double)newsState.groupFlatSince);
   GlobalVariableSet(NewsHedgeKey("AUE"), newsState.actualUnlockExtension);
   GlobalVariableSet(NewsHedgeKey("AUS"), newsState.actualUnlockSlippage);
   GlobalVariableSet(NewsHedgeKey("REP"), newsState.runnerExtremePrice);
   GlobalVariableSet(NewsHedgeKey("LET"), (double)newsState.lastExtremeTimeMs);
   GlobalVariableSet(NewsHedgeKey("RPH"), newsState.runnerPhase);
   GlobalVariableSet(NewsHedgeKey("MPP"), newsState.microPullbackPrice);
   GlobalVariableSet(NewsHedgeKey("MPA"), newsState.microPullbackActive ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("MPC"), newsState.microPullbackConfirmed ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("MPST"),(double)newsState.microPullbackStartMsc);
   GlobalVariableSet(NewsHedgeKey("MPI"), newsState.microPullbackInvalid ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("MIE"), newsState.microImpulseExtreme);
   GlobalVariableSet(NewsHedgeKey("FPD"), newsState.firstPartialDone ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("SPD"), newsState.secondPartialDone ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("REF"), newsState.referencePrice);
   GlobalVariableSet(NewsHedgeKey("RH"),  newsState.rangeHigh);
   GlobalVariableSet(NewsHedgeKey("RL"),  newsState.rangeLow);
   GlobalVariableSet(NewsHedgeKey("ATR"), newsState.atrAtPair);
   GlobalVariableSet(NewsHedgeKey("HSD"), newsState.hardStopDistance);
   GlobalVariableSet(NewsHedgeKey("BV"),  newsState.boxValid ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("BFT"), (double)newsState.boxFreezeTime);
   GlobalVariableSet(NewsHedgeKey("BW"),  newsState.boxWidth);
   GlobalVariableSet(NewsHedgeKey("BHT"), newsState.boxHighTouches);
   GlobalVariableSet(NewsHedgeKey("BLT"), newsState.boxLowTouches);
   GlobalVariableSet(NewsHedgeKey("BMC"), newsState.boxMiddleCrosses);
   GlobalVariableSet(NewsHedgeKey("BCI"), newsState.boxCloseInsideRatio);
   GlobalVariableSet(NewsHedgeKey("NSP"), newsState.normalSpreadPrice);
   GlobalVariableSet(NewsHedgeKey("IB"),  newsState.initialBuffer);
   GlobalVariableSet(NewsHedgeKey("BB"),  newsState.breakoutBuffer);
   GlobalVariableSet(NewsHedgeKey("FB"),  newsState.failureBuffer);
   GlobalVariableSet(NewsHedgeKey("BFU"), newsState.boxFrozenByUser ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("REL"), newsState.releaseEnabled ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("RELT"),(double)newsState.releaseTime);
   GlobalVariableSet(NewsHedgeKey("RELE"),(double)newsState.releaseExpireTime);
   GlobalVariableSet(NewsHedgeKey("RSM"), (double)newsState.releaseStartMs);
   GlobalVariableSet(NewsHedgeKey("DB"),  newsState.disasterBuffer);
   GlobalVariableSet(NewsHedgeKey("BDSL"),newsState.buyDisasterSL);
   GlobalVariableSet(NewsHedgeKey("SDSL"),newsState.sellDisasterSL);
   GlobalVariableSet(NewsHedgeKey("RSL"), newsState.runnerStructureSL);
   GlobalVariableSet(NewsHedgeKey("RBP"), newsState.runnerBoxProtectionApplied ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("DIR"), newsState.breakoutDirection);
   GlobalVariableSet(NewsHedgeKey("BPR"), newsState.breakoutPrice);
   GlobalVariableSet(NewsHedgeKey("PLM"), newsState.pendingLoserLossMoney);
   GlobalVariableSet(NewsHedgeKey("RLM"), newsState.realizedLoserLossMoney);
   GlobalVariableSet(NewsHedgeKey("COST"),newsState.estimatedExtraCostMoney);
   GlobalVariableSet(NewsHedgeKey("AC"),  newsState.actualCostMoney);
   GlobalVariableSet(NewsHedgeKey("REC"), newsState.estimatedRemainingExitCostMoney);
   GlobalVariableSet(NewsHedgeKey("RRP"), newsState.realizedRunnerProfitMoney);
   GlobalVariableSet(NewsHedgeKey("RPE"), newsState.runnerPendingEstimateMoney);
   GlobalVariableSet(NewsHedgeKey("MAX"), newsState.maxCombinedMoney);
   GlobalVariableSet(NewsHedgeKey("RIV"), newsState.runnerInitialVolume);
   GlobalVariableSet(NewsHedgeKey("HI"),  newsState.runnerHigh);
   GlobalVariableSet(NewsHedgeKey("LO"),  newsState.runnerLow);
   GlobalVariableSet(NewsHedgeKey("PS"),  newsState.runnerPartialStage);
   GlobalVariableSet(NewsHedgeKey("RPP"), newsState.runnerPartialPending ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("RPTS"),newsState.runnerPartialTargetStage);
   GlobalVariableSet(NewsHedgeKey("RPSV"),newsState.runnerPartialStageStartVolume);
   GlobalVariableSet(NewsHedgeKey("RPTV"),newsState.runnerPartialTargetVolume);
   GlobalVariableSet(NewsHedgeKey("RPSE"),newsState.runnerPartialStageStartExitVolume);
   GlobalVariableSet(NewsHedgeKey("RPFV"),newsState.runnerPartialFilledVolume);
   GlobalVariableSet(NewsHedgeKey("RPRV"),newsState.runnerPartialRequestedVolume);
   GlobalVariableSet(NewsHedgeKey("RPRT"),(double)newsState.runnerPartialRequestTime);
   GlobalVariableSet(NewsHedgeKey("RREV"),newsState.runnerRealizedExitVolume);
   GlobalVariableSet(NewsHedgeKey("RAC"), newsState.runnerActualCostMoney);
   GlobalVariableSet(NewsHedgeKey("LPT"), (double)newsState.lastPartialTime);
   GlobalVariableSet(NewsHedgeKey("LSB"), (double)newsState.lastStructureBarTime);
   GlobalVariableSet(NewsHedgeKey("LLD"), (double)newsState.lastLoserDeal);
   GlobalVariableSet(NewsHedgeKey("LRD"), (double)newsState.lastRunnerDeal);
   GlobalVariableSet(NewsHedgeKey("PDC"), newsPendingDealCount);
   for(int i=0; i<NEWS_PENDING_DEAL_CAPACITY; i++)
      GlobalVariableSet(NewsHedgeKey("PD"+IntegerToString(i)), (double)newsPendingDeals[i]);
   GlobalVariableSet(NewsHedgeKey("LDN"), newsState.loserDealNetMoney);
   GlobalVariableSet(NewsHedgeKey("LAK"), newsState.loserActualKnown ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("NSS"), newsState.stopStage);
   GlobalVariableSet(NewsHedgeKey("NST"), (double)newsState.stopToken);
   NewsHedgeWriteUlong("NSB", newsState.buyStopOrder);
   NewsHedgeWriteUlong("NSS", newsState.sellStopOrder);
   GlobalVariableSet(NewsHedgeKey("NSRQ"), (double)newsState.stopRequestTime);
   GlobalVariableSet(NewsHedgeKey("NSEX"), (double)newsState.stopExpireTime);
   GlobalVariableSet(NewsHedgeKey("NSBD"), newsState.buyStopDeletePending ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("NSSD"), newsState.sellStopDeletePending ? 1.0 : 0.0);
   GlobalVariableSet(NewsHedgeKey("NSBT"), (double)newsState.buyStopDeleteTime);
   GlobalVariableSet(NewsHedgeKey("NSST"), (double)newsState.sellStopDeleteTime);
}

double NewsHedgeRead(string suffix, double fallback=0.0)
{
   string key = NewsHedgeKey(suffix);
   return GlobalVariableCheck(key) ? GlobalVariableGet(key) : fallback;
}

void NewsHedgeReset(bool clearPersistent=true)
{
   ZeroMemory(newsState);
   newsState.stage = 消息阶段_待命;
   newsState.stopStage = 消息双Stop_空闲;
   消息对冲状态 = "待命: 请下等手数BUY+SELL";
   消息对冲箱体拒绝原因 = "";
   消息对冲退出原因 = "";
   newsMicroHead = 0;
   newsMicroCount = 0;
   ArrayInitialize(newsPendingDeals, 0);
   newsPendingDealCount = 0;
   上次消息箱体尝试时间 = 0;
   if(clearPersistent) NewsHedgeDeletePersistence();
}

bool NewsRefreshRunnerDealTotals(bool adjustActualCost);
bool NewsReconcileRunnerPartial(bool refreshHistory);
void NewsMigrateLegacyRunnerPartialState(bool legacyFirstDone, bool legacySecondDone, int legacyStage);

void NewsHedgeLoadState()
{
   ZeroMemory(newsState);
   int version = (int)MathRound(NewsHedgeRead("VER", 0.0));
   int stage = (int)MathRound(NewsHedgeRead("ST", 0.0));
   if(stage < 消息阶段_待命 || stage > 消息阶段_组合退出)
   {
      NewsHedgeReset(true);
      return;
   }

   newsState.stage = stage;
   newsState.adoptedTemplate = (int)MathRound(NewsHedgeRead("ATM", stage == 消息阶段_待命 ? (double)配置_自定义 : (double)配置_黄金消息对冲));
   if(stage != 消息阶段_待命 && newsState.adoptedTemplate != (int)配置_黄金消息对冲)
      newsState.adoptedTemplate = (int)配置_黄金消息对冲;
   newsState.buyTicket = (ulong)NewsHedgeRead("BT");
   newsState.sellTicket = (ulong)NewsHedgeRead("STK");
   newsState.runnerTicket = (ulong)NewsHedgeRead("RT");
   newsState.loserTicket = (ulong)NewsHedgeRead("LT");
   newsState.buyPositionId = (ulong)NewsHedgeRead("BI");
   newsState.sellPositionId = (ulong)NewsHedgeRead("SI");
   newsState.runnerPositionId = (ulong)NewsHedgeRead("RI");
   newsState.loserPositionId = (ulong)NewsHedgeRead("LI");
   newsState.buyOpenPrice = NewsHedgeRead("BOP");
   newsState.sellOpenPrice = NewsHedgeRead("SOP");
   newsState.pairTime = (datetime)NewsHedgeRead("PT");
   newsState.unhedgeTime = (datetime)NewsHedgeRead("UT");
   newsState.unhedgeTimeMs = (ulong)NewsHedgeRead("UTM");
   newsState.unhedgePrice = NewsHedgeRead("UP");
   newsState.initialGroupRiskMoney = NewsHedgeRead("IGR");
   newsState.loserDealReady = (NewsHedgeRead("LDR") > 0.5);
   newsState.runnerRiskReady = (NewsHedgeRead("RRR") > 0.5);
   newsState.actualRunnerRiskSL = NewsHedgeRead("ARSL");
   newsState.loserClosePrice = NewsHedgeRead("LCP");
   newsState.loserCloseTimeMsc = (ulong)NewsHedgeRead("LCT");
   newsState.groupFlatSince = (datetime)NewsHedgeRead("GFS");
   newsState.actualUnlockExtension = NewsHedgeRead("AUE");
   newsState.actualUnlockSlippage = NewsHedgeRead("AUS");
   newsState.runnerExtremePrice = NewsHedgeRead("REP");
   newsState.lastExtremeTimeMs = (ulong)NewsHedgeRead("LET");
   newsState.runnerPhase = (int)MathRound(NewsHedgeRead("RPH"));
   newsState.microPullbackPrice = NewsHedgeRead("MPP");
   newsState.microPullbackActive = (NewsHedgeRead("MPA") > 0.5);
   newsState.microPullbackConfirmed = (NewsHedgeRead("MPC") > 0.5);
   newsState.microPullbackStartMsc = (ulong)NewsHedgeRead("MPST");
   newsState.microPullbackInvalid = (NewsHedgeRead("MPI") > 0.5);
   newsState.microImpulseExtreme = NewsHedgeRead("MIE");
   newsState.firstPartialDone = (NewsHedgeRead("FPD") > 0.5);
   newsState.secondPartialDone = (NewsHedgeRead("SPD") > 0.5);
   newsState.referencePrice = NewsHedgeRead("REF");
   newsState.rangeHigh = NewsHedgeRead("RH");
   newsState.rangeLow = NewsHedgeRead("RL");
   newsState.atrAtPair = NewsHedgeRead("ATR");
   newsState.hardStopDistance = NewsHedgeRead("HSD");
   newsState.boxValid = (NewsHedgeRead("BV") > 0.5);
   newsState.boxFreezeTime = (datetime)NewsHedgeRead("BFT");
   newsState.boxWidth = NewsHedgeRead("BW");
   newsState.boxHighTouches = (int)MathRound(NewsHedgeRead("BHT"));
   newsState.boxLowTouches = (int)MathRound(NewsHedgeRead("BLT"));
   newsState.boxMiddleCrosses = (int)MathRound(NewsHedgeRead("BMC"));
   newsState.boxCloseInsideRatio = NewsHedgeRead("BCI");
   newsState.normalSpreadPrice = NewsHedgeRead("NSP");
   newsState.initialBuffer = NewsHedgeRead("IB");
   newsState.breakoutBuffer = NewsHedgeRead("BB");
   newsState.failureBuffer = NewsHedgeRead("FB");
   newsState.boxFrozenByUser = (NewsHedgeRead("BFU") > 0.5);
   newsState.releaseEnabled = (NewsHedgeRead("REL") > 0.5);
   newsState.releaseTime = (datetime)NewsHedgeRead("RELT");
   newsState.releaseExpireTime = (datetime)NewsHedgeRead("RELE");
   newsState.releaseStartMs = (ulong)NewsHedgeRead("RSM");
   newsState.disasterBuffer = NewsHedgeRead("DB");
   newsState.buyDisasterSL = NewsHedgeRead("BDSL");
   newsState.sellDisasterSL = NewsHedgeRead("SDSL");
   newsState.runnerStructureSL = NewsHedgeRead("RSL");
   newsState.runnerBoxProtectionApplied = (NewsHedgeRead("RBP") > 0.5);
   newsState.breakoutDirection = (int)MathRound(NewsHedgeRead("DIR"));
   newsState.breakoutPrice = NewsHedgeRead("BPR");
   newsState.pendingLoserLossMoney = NewsHedgeRead("PLM");
   newsState.realizedLoserLossMoney = NewsHedgeRead("RLM");
   newsState.estimatedExtraCostMoney = NewsHedgeRead("COST");
   newsState.actualCostMoney = NewsHedgeRead("AC");
   newsState.estimatedRemainingExitCostMoney = NewsHedgeRead("REC");
   newsState.realizedRunnerProfitMoney = NewsHedgeRead("RRP");
   newsState.runnerPendingEstimateMoney = NewsHedgeRead("RPE");
   newsState.maxCombinedMoney = NewsHedgeRead("MAX");
   newsState.runnerInitialVolume = NewsHedgeRead("RIV");
   newsState.runnerHigh = NewsHedgeRead("HI");
   newsState.runnerLow = NewsHedgeRead("LO");
   newsState.runnerPartialStage = (int)MathRound(NewsHedgeRead("PS"));
   newsState.runnerPartialPending = (NewsHedgeRead("RPP") > 0.5);
   newsState.runnerPartialTargetStage = (int)MathRound(NewsHedgeRead("RPTS"));
   newsState.runnerPartialStageStartVolume = NewsHedgeRead("RPSV");
   newsState.runnerPartialTargetVolume = NewsHedgeRead("RPTV");
   newsState.runnerPartialStageStartExitVolume = NewsHedgeRead("RPSE");
   newsState.runnerPartialFilledVolume = NewsHedgeRead("RPFV");
   newsState.runnerPartialRequestedVolume = NewsHedgeRead("RPRV");
   newsState.runnerPartialRequestTime = (datetime)NewsHedgeRead("RPRT");
   newsState.runnerRealizedExitVolume = NewsHedgeRead("RREV");
   newsState.runnerActualCostMoney = NewsHedgeRead("RAC");
   newsState.lastPartialTime = (datetime)NewsHedgeRead("LPT");
   newsState.lastStructureBarTime = (datetime)NewsHedgeRead("LSB");
   newsState.lastLoserDeal = (ulong)NewsHedgeRead("LLD");
   newsState.lastRunnerDeal = (ulong)NewsHedgeRead("LRD");
   newsPendingDealCount = (int)MathRound(NewsHedgeRead("PDC"));
   newsPendingDealCount = MathMax(0, MathMin(newsPendingDealCount, NEWS_PENDING_DEAL_CAPACITY));
   for(int i=0; i<NEWS_PENDING_DEAL_CAPACITY; i++)
      newsPendingDeals[i] = (ulong)NewsHedgeRead("PD"+IntegerToString(i));
   ulong legacyPendingDeal = (ulong)NewsHedgeRead("PDEAL");
   if(newsPendingDealCount == 0 && legacyPendingDeal > 0)
   {
      newsPendingDeals[0] = legacyPendingDeal;
      newsPendingDealCount = 1;
   }
   newsState.loserDealNetMoney = NewsHedgeRead("LDN");
   newsState.loserActualKnown = (NewsHedgeRead("LAK") > 0.5);
   newsState.stopStage = (int)MathRound(NewsHedgeRead("NSS"));
   newsState.stopToken = (long)MathRound(NewsHedgeRead("NST"));
   newsState.buyStopOrder = NewsHedgeReadUlong("NSB");
   newsState.sellStopOrder = NewsHedgeReadUlong("NSS");
   newsState.stopRequestTime = (datetime)NewsHedgeRead("NSRQ");
   newsState.stopExpireTime = (datetime)NewsHedgeRead("NSEX");
   newsState.buyStopDeletePending = (NewsHedgeRead("NSBD") > 0.5);
   newsState.sellStopDeletePending = (NewsHedgeRead("NSSD") > 0.5);
   newsState.buyStopDeleteTime = (datetime)NewsHedgeRead("NSBT");
   newsState.sellStopDeleteTime = (datetime)NewsHedgeRead("NSST");
   if(newsState.stopStage < 消息双Stop_空闲 || newsState.stopStage > 消息双Stop_故障)
      newsState.stopStage = 消息双Stop_故障;
   if(version < 4)
   {
      newsState.loserDealReady = newsState.loserActualKnown;
      newsState.runnerRiskReady = false;
      newsState.actualRunnerRiskSL = 0.0;
      if(newsState.buyOpenPrice <= 0.0 && newsState.buyTicket > 0 && PositionSelectByTicket(newsState.buyTicket))
         newsState.buyOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      if(newsState.sellOpenPrice <= 0.0 && newsState.sellTicket > 0 && PositionSelectByTicket(newsState.sellTicket))
         newsState.sellOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   }
   if(newsState.actualRunnerRiskSL <= 0.0) newsState.runnerRiskReady = false;
   ulong nowMs = GetTickCount64();
   if(version < 3 && stage != 消息阶段_待命)
   {
      bool buyAlive = (newsState.buyTicket > 0 && PositionSelectByTicket(newsState.buyTicket));
      bool sellAlive = (newsState.sellTicket > 0 && PositionSelectByTicket(newsState.sellTicket));
      bool runnerAlive = (newsState.runnerTicket > 0 && PositionSelectByTicket(newsState.runnerTicket));
      if(buyAlive && sellAlive)
      {
         newsState.stage = 消息阶段_配对安全;
         newsState.boxFrozenByUser = false;
         newsState.releaseEnabled = false;
         newsState.releaseTime = 0;
         newsState.releaseExpireTime = 0;
      }
      else if(runnerAlive || buyAlive != sellAlive)
      {
         if(!runnerAlive)
         {
            newsState.runnerTicket = buyAlive ? newsState.buyTicket : newsState.sellTicket;
            newsState.runnerPositionId = buyAlive ? newsState.buyPositionId : newsState.sellPositionId;
            newsState.breakoutDirection = buyAlive ? 1 : -1;
         }
         newsState.stage = 消息阶段_冲击持仓;
         newsState.releaseEnabled = false;
         if(newsState.unhedgeTime <= 0) newsState.unhedgeTime = TimeCurrent();
         newsState.runnerPhase = 1;
      }
      else
      {
         NewsHedgeReset(true);
         return;
      }
   }
   if(newsState.releaseTime > 0)
   {
      ulong elapsed = (ulong)MathMax((long)(TimeCurrent()-newsState.releaseTime), 0) * 1000;
      newsState.releaseStartMs = nowMs > elapsed ? nowMs-elapsed : 0;
   }
   if(newsState.unhedgeTime > 0)
   {
      ulong elapsed = (ulong)MathMax((long)(TimeCurrent()-newsState.unhedgeTime), 0) * 1000;
      newsState.unhedgeTimeMs = nowMs > elapsed ? nowMs-elapsed : 0;
      newsState.lastExtremeTimeMs = nowMs;
   }
   if(version > 0 && version < 6)
      NewsMigrateLegacyRunnerPartialState(newsState.firstPartialDone, newsState.secondPartialDone,
                                          newsState.runnerPartialStage);
   else
   {
      NewsRefreshRunnerDealTotals(true);
      NewsReconcileRunnerPartial(false);
   }
   if(newsState.stage == 消息阶段_待命) 消息对冲状态 = "待命: 请下等手数BUY+SELL";
   else if(newsState.stage == 消息阶段_配对安全) 消息对冲状态 = "已恢复配对安全，禁止拆锁";
   else if(newsState.stage == 消息阶段_箱体冻结) 消息对冲状态 = "已恢复冻结箱体，等待开放";
   else if(newsState.stage == 消息阶段_释放窗口) 消息对冲状态 = "已恢复释放窗口";
   else if(newsState.stage == 消息阶段_拆锁中) 消息对冲状态 = "已恢复拆锁";
   else if(newsState.stage == 消息阶段_冲击持仓) 消息对冲状态 = "已恢复冲击持仓";
   else if(newsState.stage == 消息阶段_延续持仓) 消息对冲状态 = "已恢复延续持仓";
   else 消息对冲状态 = "已恢复组合退出";
}

bool NewsPositionExists(ulong ticket)
{
   return (ticket > 0 && PositionSelectByTicket(ticket));
}

bool NewsPositionEligibleSelected()
{
   if(PositionGetString(POSITION_SYMBOL) != _Symbol) return false;
   long magic = (long)PositionGetInteger(POSITION_MAGIC);
   string cmt = PositionGetString(POSITION_COMMENT);
   if(magic == 消息双Stop挂单Magic &&
      (NewsStopCommentMatches(cmt,1) || NewsStopCommentMatches(cmt,-1))) return true;
   if(magic == 手机标记挂单Magic && StringFind(cmt, "SMA_MARK_") == 0) return false;
   if(只管理手动单 && magic != 0) return false;
   if(!只管理手动单 && magic != 指定管理Magic) return false;

   // 消息对冲只能管理“真实入场成交时”已冻结为消息模板的仓位。
   // 这里严禁 EnsureState()/按当前模板补接管：否则用户只是切换面板，
   // 原有短线、趋势或普通仓会被误判为待配对消息仓。
   ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
   int stateIdx = FindState(ticket);
   if(stateIdx < 0) return false;
   if(states[stateIdx].adoptedTemplate != (int)配置_黄金消息对冲) return false;
   return true;
}

bool NewsFindPairCandidates(ulong &buyTicket, ulong &sellTicket, int &buyCount, int &sellCount)
{
   buyTicket = 0;
   sellTicket = 0;
   buyCount = 0;
   sellCount = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !NewsPositionEligibleSelected()) continue;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(type == POSITION_TYPE_BUY)
      {
         buyCount++;
         buyTicket = tk;
      }
      else if(type == POSITION_TYPE_SELL)
      {
         sellCount++;
         sellTicket = tk;
      }
   }
   return (buyCount == 1 && sellCount == 1);
}

double NewsPositionMoney(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0.0;
   return PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
}

double NewsPositionVolume(ulong ticket)
{
   return PositionSelectByTicket(ticket) ? PositionGetDouble(POSITION_VOLUME) : 0.0;
}

double NewsMoneyScale(double per001, double volume)
{
   return MathMax(per001, 0.0) * MathMax(volume, 0.0) / 0.01;
}

double NewsPriceDistanceToMoney(double priceDistance, double volume)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT),
                              SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS));
   if(tickSize <= 0.0 || tickValue <= 0.0 || volume <= 0.0) return 0.0;
   return priceDistance / tickSize * tickValue * volume;
}

double NewsMoneyToPriceDistance(double money, double volume)
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT),
                              SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS));
   if(tickSize <= 0.0 || tickValue <= 0.0 || volume <= 0.0) return 0.0;
   return MathMax(money, 0.0) / (tickValue * volume) * tickSize;
}

struct NewsBoxCluster
{
   double   price;
   int      seedCount;
   int      touches;
   datetime latestTime;
};

double NewsBrokerMinimumStopDistance()
{
   long stops = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)(MathMax(stops, freeze) + 1) * _Point;
}

double NewsOptionalBufferLimits(double value, double minimumValue, double maximumValue)
{
   if(minimumValue > 0.0) value = MathMax(value, minimumValue);
   if(maximumValue > 0.0) value = MathMin(value, maximumValue);
   return value;
}

double NewsNormalSpreadPrice(bool &usedTickMedian)
{
   usedTickMedian = false;
   int seconds = MathMax(消息对冲正常点差统计秒数, 1);
   ulong toMs = (ulong)TimeCurrent() * 1000;
   ulong fromMs = toMs > (ulong)seconds * 1000 ? toMs - (ulong)seconds * 1000 : 0;
   MqlTick ticks[];
   int copied = CopyTicksRange(_Symbol, ticks, COPY_TICKS_INFO, fromMs, toMs);
   double samples[];
   if(copied > 0)
   {
      for(int i=0; i<copied; i++)
      {
         if(ticks[i].ask <= ticks[i].bid || ticks[i].bid <= 0.0) continue;
         int n = ArraySize(samples);
         ArrayResize(samples, n + 1);
         samples[n] = ticks[i].ask - ticks[i].bid;
      }
   }
   int count = ArraySize(samples);
   if(count >= 5)
   {
      ArraySort(samples);
      usedTickMedian = true;
      double median = (count % 2 == 1) ? samples[count / 2] : (samples[count / 2 - 1] + samples[count / 2]) * 0.5;
      PrintFormat("[消息箱体] normalSpread=%.5f 来源=%d秒Tick中位数 样本=%d", median, seconds, count);
      return median;
   }
   double fallback = MathMax(CurrentSpreadPrice(), _Point);
   PrintFormat("[消息箱体] normalSpread=%.5f 来源=当前点差降级 Tick样本=%d", fallback, count);
   return fallback;
}

void NewsAddBoxCluster(NewsBoxCluster &clusters[], double price, datetime barTime, double clusterDistance)
{
   int best = -1;
   double bestDistance = DBL_MAX;
   for(int i=0; i<ArraySize(clusters); i++)
   {
      double d = MathAbs(clusters[i].price - price);
      if(d <= clusterDistance && d < bestDistance)
      {
         best = i;
         bestDistance = d;
      }
   }
   if(best < 0)
   {
      int n = ArraySize(clusters);
      ArrayResize(clusters, n + 1);
      clusters[n].price = price;
      clusters[n].seedCount = 1;
      clusters[n].touches = 0;
      clusters[n].latestTime = barTime;
      return;
   }
   clusters[best].price = (clusters[best].price * clusters[best].seedCount + price) / (clusters[best].seedCount + 1);
   clusters[best].seedCount++;
   clusters[best].latestTime = MathMax(clusters[best].latestTime, barTime);
}

bool NewsBuildFrozenBox(double midPrice,
                        double atr,
                        double normalSpread,
                        double &boxHigh,
                        double &boxLow,
                        int &highTouches,
                        int &lowTouches,
                        int &middleCrosses,
                        double &closeInsideRatio,
                        string &rejectReason)
{
   boxHigh = 0.0;
   boxLow = 0.0;
   highTouches = 0;
   lowTouches = 0;
   middleCrosses = 0;
   closeInsideRatio = 0.0;
   rejectReason = "";

   int bars = MathMax(消息对冲箱体回看M1根数, 6);
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, bars, rates);
   if(copied < bars)
   {
      rejectReason = StringFormat("已收M1不足: %d/%d", copied, bars);
      Print("[消息箱体] 拒绝: " + rejectReason);
      return false;
   }

   double clusterDistance = MathMax(MathMax(normalSpread * MathMax(消息对冲箱体聚类点差倍数, 0.0),
                                             atr * MathMax(消息对冲箱体聚类ATR倍数, 0.0)),
                                    MathMax(消息对冲箱体最小聚类价格距离, _Point));
   PrintFormat("[消息箱体] 回看 %s -> %s 根数=%d ATR=%.5f 聚类距=%.5f",
               TimeToString(rates[copied-1].time, TIME_DATE|TIME_MINUTES),
               TimeToString(rates[0].time, TIME_DATE|TIME_MINUTES), copied, atr, clusterDistance);

   NewsBoxCluster highs[];
   NewsBoxCluster lows[];
   for(int i=1; i<copied-1; i++)
   {
      if(rates[i].high >= rates[i-1].high && rates[i].high >= rates[i+1].high)
         NewsAddBoxCluster(highs, rates[i].high, rates[i].time, clusterDistance);
      if(rates[i].low <= rates[i-1].low && rates[i].low <= rates[i+1].low)
         NewsAddBoxCluster(lows, rates[i].low, rates[i].time, clusterDistance);
   }
   if(ArraySize(highs) == 0 || ArraySize(lows) == 0)
   {
      rejectReason = "缺少可聚类的局部高点或低点";
      Print("[消息箱体] 拒绝: " + rejectReason);
      return false;
   }

   for(int c=0; c<ArraySize(highs); c++)
   {
      double sum = 0.0;
      highs[c].touches = 0;
      int lastTouchIndex = -1000;
      for(int i=0; i<copied; i++)
      {
         if(MathAbs(rates[i].high - highs[c].price) > clusterDistance) continue;
         if(lastTouchIndex >= 0 && i - lastTouchIndex < 2) continue;
         sum += rates[i].high;
         highs[c].touches++;
         lastTouchIndex = i;
         highs[c].latestTime = MathMax(highs[c].latestTime, rates[i].time);
      }
      if(highs[c].touches > 0) highs[c].price = sum / highs[c].touches;
      PrintFormat("[消息箱体] 高簇%d price=%.5f touches=%d latest=%s", c+1, highs[c].price, highs[c].touches,
                  TimeToString(highs[c].latestTime, TIME_DATE|TIME_MINUTES));
   }
   for(int c=0; c<ArraySize(lows); c++)
   {
      double sum = 0.0;
      lows[c].touches = 0;
      int lastTouchIndex = -1000;
      for(int i=0; i<copied; i++)
      {
         if(MathAbs(rates[i].low - lows[c].price) > clusterDistance) continue;
         if(lastTouchIndex >= 0 && i - lastTouchIndex < 2) continue;
         sum += rates[i].low;
         lows[c].touches++;
         lastTouchIndex = i;
         lows[c].latestTime = MathMax(lows[c].latestTime, rates[i].time);
      }
      if(lows[c].touches > 0) lows[c].price = sum / lows[c].touches;
      PrintFormat("[消息箱体] 低簇%d price=%.5f touches=%d latest=%s", c+1, lows[c].price, lows[c].touches,
                  TimeToString(lows[c].latestTime, TIME_DATE|TIME_MINUTES));
   }

   int bestHigh = -1;
   int bestLow = -1;
   double bestHighScore = -DBL_MAX;
   double bestLowScore = -DBL_MAX;
   datetime oldest = rates[copied-1].time;
   for(int c=0; c<ArraySize(highs); c++)
   {
      if(highs[c].price <= midPrice) continue;
      double score = highs[c].touches * 1000.0 + (highs[c].latestTime - oldest) / 60.0 -
                     MathAbs(highs[c].price - midPrice) / MathMax(atr, _Point);
      if(score > bestHighScore) { bestHighScore = score; bestHigh = c; }
   }
   for(int c=0; c<ArraySize(lows); c++)
   {
      if(lows[c].price >= midPrice) continue;
      double score = lows[c].touches * 1000.0 + (lows[c].latestTime - oldest) / 60.0 -
                     MathAbs(midPrice - lows[c].price) / MathMax(atr, _Point);
      if(score > bestLowScore) { bestLowScore = score; bestLow = c; }
   }
   if(bestHigh < 0 || bestLow < 0)
   {
      rejectReason = "当前中价上下没有成对有效簇";
      Print("[消息箱体] 拒绝: " + rejectReason);
      return false;
   }

   boxHigh = highs[bestHigh].price;
   boxLow = lows[bestLow].price;
   highTouches = highs[bestHigh].touches;
   lowTouches = lows[bestLow].touches;
   double width = boxHigh - boxLow;
   if(width <= 0.0 || midPrice <= boxLow || midPrice >= boxHigh)
   {
      rejectReason = "当前中价不在候选箱体内部";
      Print("[消息箱体] 拒绝: " + rejectReason);
      return false;
   }
   int minTouches = MathMax(消息对冲箱体最低触碰次数, 1);
   if(highTouches < minTouches || lowTouches < minTouches)
   {
      rejectReason = StringFormat("触碰不足 H%d/L%d 最低%d", highTouches, lowTouches, minTouches);
      Print("[消息箱体] 拒绝: " + rejectReason);
      return false;
   }

   double middle = (boxHigh + boxLow) * 0.5;
   double middleBand = MathMax(normalSpread * 0.5, _Point);
   int lastSide = 0;
   int inside = 0;
   for(int i=copied-1; i>=0; i--)
   {
      if(rates[i].close >= boxLow && rates[i].close <= boxHigh) inside++;
      int side = rates[i].close > middle + middleBand ? 1 : (rates[i].close < middle - middleBand ? -1 : 0);
      if(side != 0)
      {
         if(lastSide != 0 && side != lastSide) middleCrosses++;
         lastSide = side;
      }
   }
   closeInsideRatio = (double)inside / copied;
   if(middleCrosses < MathMax(消息对冲箱体最低中轴穿越次数, 0))
   {
      rejectReason = StringFormat("中轴穿越不足 %d/%d", middleCrosses, 消息对冲箱体最低中轴穿越次数);
      Print("[消息箱体] 拒绝: " + rejectReason);
      return false;
   }
   if(closeInsideRatio < ClampDouble(消息对冲箱体最低收盘占比, 0.10, 1.00))
   {
      rejectReason = StringFormat("箱内收盘占比不足 %.0f%%/%.0f%%", closeInsideRatio*100.0,
                                  ClampDouble(消息对冲箱体最低收盘占比, 0.10, 1.00)*100.0);
      Print("[消息箱体] 拒绝: " + rejectReason);
      return false;
   }
   double minWidth = atr * MathMax(消息对冲箱体最小宽度ATR倍数, 0.10);
   double maxWidth = atr * MathMax(消息对冲箱体最大宽度ATR倍数, 消息对冲箱体最小宽度ATR倍数);
   if(width < minWidth || width > maxWidth)
   {
      rejectReason = StringFormat("箱宽%.5f不在ATR范围%.5f-%.5f", width, minWidth, maxWidth);
      Print("[消息箱体] 拒绝: " + rejectReason);
      return false;
   }
   PrintFormat("[消息箱体] 接受 Low=%.5f High=%.5f Width=%.5f H触%d L触%d 中轴%d 箱内收盘=%.1f%%",
               boxLow, boxHigh, width, highTouches, lowTouches, middleCrosses, closeInsideRatio*100.0);
   return true;
}

void NewsCalculateFrozenBuffers()
{
   double brokerMin = NewsBrokerMinimumStopDistance();
   double initialSpread = newsState.normalSpreadPrice * MathMax(消息对冲初始缓冲点差倍数, 0.0);
   double initialAtr = newsState.atrAtPair * MathMax(消息对冲初始缓冲ATR倍数, 0.0);
   double initialBox = newsState.boxWidth * MathMax(消息对冲初始缓冲箱体比例, 0.0);
   newsState.initialBuffer = NewsOptionalBufferLimits(MathMax(MathMax(initialSpread, initialAtr), MathMax(initialBox, brokerMin)),
                                                       消息对冲初始缓冲最小价格, 消息对冲初始缓冲最大价格);
   double breakoutSpread = newsState.normalSpreadPrice * MathMax(消息对冲突破缓冲点差倍数, 0.0);
   double breakoutAtr = newsState.atrAtPair * MathMax(消息对冲突破缓冲ATR倍数, 0.0);
   double breakoutBox = newsState.boxWidth * MathMax(消息对冲突破缓冲箱体比例, 0.0);
   newsState.breakoutBuffer = MathMax(MathMax(breakoutSpread, breakoutAtr), MathMax(breakoutBox, brokerMin));
   double failureSpread = newsState.normalSpreadPrice * MathMax(消息对冲失败缓冲点差倍数, 0.0);
   double failureAtr = newsState.atrAtPair * MathMax(消息对冲失败缓冲ATR倍数, 0.0);
   double failureBox = newsState.boxWidth * MathMax(消息对冲失败缓冲箱体比例, 0.0);
   newsState.failureBuffer = MathMax(MathMax(failureSpread, failureAtr), MathMax(failureBox, brokerMin));
   double disasterInitial = newsState.initialBuffer * MathMax(消息对冲灾难缓冲初始缓冲倍数, 0.0);
   double disasterAtr = newsState.atrAtPair * MathMax(消息对冲灾难缓冲ATR倍数, 0.0);
   double disasterBox = newsState.boxWidth * MathMax(消息对冲灾难缓冲箱体比例, 0.0);
   double disasterSpread = newsState.normalSpreadPrice * MathMax(消息对冲灾难缓冲点差倍数, 0.0);
   newsState.disasterBuffer = MathMax(MathMax(disasterInitial, disasterAtr),
                                      MathMax(MathMax(disasterBox, disasterSpread), brokerMin));
   newsState.buyDisasterSL = NormalizePrice(newsState.rangeLow - newsState.disasterBuffer);
   newsState.sellDisasterSL = NormalizePrice(newsState.rangeHigh + newsState.disasterBuffer);
   PrintFormat("[消息箱体] InitialBuffer=%.5f [spread %.5f atr %.5f box %.5f broker %.5f]",
               newsState.initialBuffer, initialSpread, initialAtr, initialBox, brokerMin);
   PrintFormat("[消息箱体] BreakoutBuffer=%.5f [spread %.5f atr %.5f box %.5f broker %.5f]",
               newsState.breakoutBuffer, breakoutSpread, breakoutAtr, breakoutBox, brokerMin);
   PrintFormat("[消息箱体] FailureBuffer=%.5f [spread %.5f atr %.5f box %.5f broker %.5f]",
               newsState.failureBuffer, failureSpread, failureAtr, failureBox, brokerMin);
   PrintFormat("[消息箱体] DisasterBuffer=%.5f [initial %.5f atr %.5f box %.5f spread %.5f broker %.5f] SL BUY %.5f SELL %.5f",
               newsState.disasterBuffer, disasterInitial, disasterAtr, disasterBox, disasterSpread, brokerMin,
               newsState.buyDisasterSL, newsState.sellDisasterSL);
}

void NewsBuildFrozenStopPreview(NewsStopPreview &preview)
{
   preview.visible=(newsState.stage==消息阶段_箱体冻结 && newsState.boxFrozenByUser && newsState.boxValid);
   preview.priceValid=false;
   preview.volume=0.0;
   preview.buyStop=0.0;
   preview.sellStop=0.0;
   preview.buyDisasterSL=0.0;
   preview.sellDisasterSL=0.0;
   preview.buyLossAvailable=false;
   preview.sellLossAvailable=false;
   preview.buyLossMoney=0.0;
   preview.sellLossMoney=0.0;
   preview.buyMarginAvailable=false;
   preview.sellMarginAvailable=false;
   preview.buyMargin=0.0;
   preview.sellMargin=0.0;
   preview.deployValid=false;
   preview.status="";
   if(!preview.visible) return;

   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double minVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double volumeStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(tickSize<=0.0 || bid<=0.0 || ask<=0.0 || ask<=bid)
   {
      preview.status="预览不可用：Tick size 或 Bid/Ask 无效";
      return;
   }
    if(minVolume<=0.0 || maxVolume<minVolume || volumeStep<=0.0)
    {
       preview.status="预览不可用：最小手数或手数步长无效";
       return;
    }
   double requestedVolume=启用消息双Stop真实挂单 ? 消息双Stop固定手数 : minVolume;
   double alignedVolume=MathRound(requestedVolume/volumeStep)*volumeStep;
   if(requestedVolume<minVolume-1e-8 || requestedVolume>maxVolume+1e-8 ||
      MathAbs(alignedVolume-requestedVolume)>1e-8)
   {
      preview.status=StringFormat("预览不可用：固定手数%.4f不符合 min %.4f / max %.4f / step %.4f",
                                  requestedVolume,minVolume,maxVolume,volumeStep);
      return;
   }
   if(newsState.rangeHigh<=newsState.rangeLow || newsState.breakoutBuffer<=0.0 || newsState.disasterBuffer<=0.0)
   {
      preview.status="预览不可用：冻结箱体或缓冲无效";
      return;
   }

   preview.volume=NormalizeDouble(alignedVolume,8);
   preview.buyStop=NormalizeDouble(MathCeil((newsState.rangeHigh+newsState.breakoutBuffer)/tickSize-1e-10)*tickSize,_Digits);
   preview.sellStop=NormalizeDouble(MathFloor((newsState.rangeLow-newsState.breakoutBuffer)/tickSize+1e-10)*tickSize,_Digits);
   preview.buyDisasterSL=NormalizeDouble(MathFloor((newsState.rangeLow-newsState.disasterBuffer)/tickSize+1e-10)*tickSize,_Digits);
   preview.sellDisasterSL=NormalizeDouble(MathCeil((newsState.rangeHigh+newsState.disasterBuffer)/tickSize-1e-10)*tickSize,_Digits);

   double minDistance=MathMax((double)MathMax((int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL),
                                               (int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))*_Point,tickSize);
   if(preview.buyStop<ask+minDistance || preview.sellStop>bid-minDistance ||
      preview.buyDisasterSL>=preview.buyStop-minDistance || preview.sellDisasterSL<=preview.sellStop+minDistance)
   {
      preview.status="预览不可用：候选价不满足 Bid/Ask、StopsLevel 或 FreezeLevel";
      return;
   }
   double result=0.0;
   if(OrderCalcProfit(ORDER_TYPE_BUY,_Symbol,preview.volume,preview.buyStop,preview.buyDisasterSL,result) && result<0.0)
   {
      preview.buyLossAvailable=true;
      preview.buyLossMoney=-result;
   }
   if(OrderCalcProfit(ORDER_TYPE_SELL,_Symbol,preview.volume,preview.sellStop,preview.sellDisasterSL,result) && result<0.0)
   {
      preview.sellLossAvailable=true;
      preview.sellLossMoney=-result;
   }
   if(OrderCalcMargin(ORDER_TYPE_BUY_STOP,_Symbol,preview.volume,preview.buyStop,result))
   {
      preview.buyMarginAvailable=true;
      preview.buyMargin=result;
   }
   if(OrderCalcMargin(ORDER_TYPE_SELL_STOP,_Symbol,preview.volume,preview.sellStop,result))
   {
      preview.sellMarginAvailable=true;
      preview.sellMargin=result;
   }
   double spread=ask-bid;
   double spreadLimit=NewsDynamicSpreadLimit();
   double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   bool spreadOk=(spreadLimit>0.0 && spread<=spreadLimit);
   bool marginOk=(preview.buyMarginAvailable && preview.sellMarginAvailable &&
                  preview.buyMargin+preview.sellMargin<=MathMax(freeMargin,0.0));
   bool calculationValid=(preview.buyLossAvailable && preview.sellLossAvailable && marginOk && spreadOk);
   preview.deployValid=(启用消息双Stop真实挂单 && calculationValid);
   preview.priceValid=calculationValid;
   if(!spreadOk)
      preview.status=StringFormat("预览不可用：当前点差%.5f超过上限%.5f",spread,spreadLimit);
   else if(!marginOk)
      preview.status=StringFormat("预览不可用：双单保证金%.2f超过可用%.2f",
                                  preview.buyMargin+preview.sellMargin,freeMargin);
   else if(!preview.buyLossAvailable || !preview.sellLossAvailable)
      preview.status="预览不可用：风险金额计算失败";
   else
      preview.status=启用消息双Stop真实挂单 ? "双Stop可部署" : "最小手数预览（真实挂单关闭）";
}

string NewsStopComment(int side)
{
   return "SMA_NSO_"+IntegerToString(newsState.stopToken)+(side>0 ? "_B" : "_S");
}

bool NewsStopCommentMatches(string comment,int side)
{
   return (newsState.stopToken>0 && comment==NewsStopComment(side));
}

bool NewsStopOrderSelected(int side)
{
   if(OrderGetString(ORDER_SYMBOL)!=_Symbol ||
      (long)OrderGetInteger(ORDER_MAGIC)!=消息双Stop挂单Magic) return false;
   ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
   if(side>0 && type!=ORDER_TYPE_BUY_STOP) return false;
   if(side<0 && type!=ORDER_TYPE_SELL_STOP) return false;
   return NewsStopCommentMatches(OrderGetString(ORDER_COMMENT),side);
}

bool NewsStopPositionSelected(int side)
{
   if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
      (long)PositionGetInteger(POSITION_MAGIC)!=消息双Stop挂单Magic) return false;
   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   if(side>0 && type!=POSITION_TYPE_BUY) return false;
   if(side<0 && type!=POSITION_TYPE_SELL) return false;
   ulong positionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   ulong expectedId=side>0 ? newsState.buyPositionId : newsState.sellPositionId;
   if(expectedId>0) return positionId==expectedId;
   return NewsStopCommentMatches(PositionGetString(POSITION_COMMENT),side);
}

void NewsRecoverStopPositionIds()
{
   bool changed=false;
   if(newsState.buyPositionId==0 && newsState.buyStopOrder>0 && HistoryOrderSelect(newsState.buyStopOrder))
   {
      ulong positionId=(ulong)HistoryOrderGetInteger(newsState.buyStopOrder,ORDER_POSITION_ID);
      if(positionId>0) { newsState.buyPositionId=positionId; changed=true; }
   }
   if(newsState.sellPositionId==0 && newsState.sellStopOrder>0 && HistoryOrderSelect(newsState.sellStopOrder))
   {
      ulong positionId=(ulong)HistoryOrderGetInteger(newsState.sellStopOrder,ORDER_POSITION_ID);
      if(positionId>0) { newsState.sellPositionId=positionId; changed=true; }
   }
   if(changed) NewsHedgeSaveState();
}

ulong NewsFindStopOrder(int side,int &count)
{
   ulong found=0;
   count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || !NewsStopOrderSelected(side)) continue;
      found=ticket;
      count++;
   }
   return found;
}

ulong NewsFindStopPosition(int side,int &count)
{
   ulong found=0;
   count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !NewsStopPositionSelected(side)) continue;
      found=ticket;
      count++;
   }
   return found;
}

bool NewsHasAnyStrategyStopObject()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(OrderGetTicket(i)==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((long)OrderGetInteger(ORDER_MAGIC)==消息双Stop挂单Magic &&
         StringFind(OrderGetString(ORDER_COMMENT),"SMA_NSO_")==0) return true;
   }
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      if(PositionGetTicket(i)==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC)==消息双Stop挂单Magic &&
         StringFind(PositionGetString(POSITION_COMMENT),"SMA_NSO_")==0) return true;
   }
   return false;
}

bool NewsSubmitStopOrder(int side,const NewsStopPreview &preview)
{
   newsStopTrade.SetExpertMagicNumber(消息双Stop挂单Magic);
   newsStopTrade.SetDeviationInPoints(MathMax(消息对冲允许滑点点数,0));
   datetime expiration=newsState.stopExpireTime;
   bool sent=side>0 ?
      newsStopTrade.BuyStop(preview.volume,preview.buyStop,_Symbol,preview.buyDisasterSL,0.0,
                            ORDER_TIME_SPECIFIED,expiration,NewsStopComment(side)) :
      newsStopTrade.SellStop(preview.volume,preview.sellStop,_Symbol,preview.sellDisasterSL,0.0,
                             ORDER_TIME_SPECIFIED,expiration,NewsStopComment(side));
   uint retcode=newsStopTrade.ResultRetcode();
   if(!sent || !IsTradeRetcodeAccepted(retcode))
   {
      PrintFormat("[消息双Stop] %s创建请求失败 ret=%u %s",side>0?"BUY":"SELL",retcode,newsStopTrade.ResultComment());
      return false;
   }
   ulong order=newsStopTrade.ResultOrder();
   if(side>0) newsState.buyStopOrder=order;
   else newsState.sellStopOrder=order;
   newsState.stopRequestTime=TimeCurrent();
   NewsHedgeSaveState();
   PrintFormat("[消息双Stop] %s创建请求已受理 order=%I64u ret=%u，等待服务器订单确认",
               side>0?"BUY":"SELL",order,retcode);
   return true;
}

void NewsRequestStopDelete(int side,ulong ticket)
{
   if(ticket==0 || !OrderSelect(ticket)) return;
   datetime now=TimeCurrent();
   bool pending=side>0 ? newsState.buyStopDeletePending : newsState.sellStopDeletePending;
   datetime last=side>0 ? newsState.buyStopDeleteTime : newsState.sellStopDeleteTime;
   if(last>0 && now-last<5) return;
   newsStopTrade.SetExpertMagicNumber(消息双Stop挂单Magic);
   bool sent=newsStopTrade.OrderDelete(ticket);
   uint retcode=newsStopTrade.ResultRetcode();
   bool accepted=(sent && IsTradeRetcodeAccepted(retcode));
   if(side>0)
   {
      newsState.buyStopDeletePending=accepted;
      newsState.buyStopDeleteTime=now;
   }
   else
   {
      newsState.sellStopDeletePending=accepted;
      newsState.sellStopDeleteTime=now;
   }
   PrintFormat("[消息双Stop] %s撤单请求 order=%I64u accepted=%d ret=%u %s",
               side>0?"BUY":"SELL",ticket,accepted,retcode,newsStopTrade.ResultComment());
   NewsHedgeSaveState();
}

bool NewsStopOrderCancellationConfirmed(ulong ticket)
{
   if(ticket==0) return true;
   if(OrderSelect(ticket)) return false;
   if(!HistoryOrderSelect(ticket)) return false;
   ENUM_ORDER_STATE state=(ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket,ORDER_STATE);
   return (state==ORDER_STATE_CANCELED || state==ORDER_STATE_EXPIRED || state==ORDER_STATE_REJECTED);
}

void NewsStopSetFault(string reason)
{
   newsState.stopStage=消息双Stop_故障;
   消息对冲状态="双Stop故障，需人工处理: "+reason;
   lastStatus=消息对冲状态;
   Print("[消息双Stop安全] "+消息对冲状态);
   NewsHedgeSaveState();
}

void NewsAdoptStopPair(ulong buyTicket,ulong sellTicket)
{
   if(!NewsPairValid(buyTicket,sellTicket))
   {
      NewsStopSetFault("双边成交但手数或身份无法安全配对");
      return;
   }
   newsState.buyTicket=buyTicket;
   newsState.sellTicket=sellTicket;
   newsState.runnerTicket=0;
   newsState.loserTicket=0;
   newsState.runnerPositionId=0;
   newsState.loserPositionId=0;
   newsState.runnerRiskReady=false;
   newsState.actualRunnerRiskSL=0.0;
   newsState.buyPositionId=NewsPositionIdentifier(buyTicket);
   newsState.sellPositionId=NewsPositionIdentifier(sellTicket);
   if(PositionSelectByTicket(buyTicket)) newsState.buyOpenPrice=PositionGetDouble(POSITION_PRICE_OPEN);
   if(PositionSelectByTicket(sellTicket)) newsState.sellOpenPrice=PositionGetDouble(POSITION_PRICE_OPEN);
   newsState.pairTime=TimeCurrent();
   newsState.stage=消息阶段_箱体冻结;
   newsState.stopStage=消息双Stop_空闲;
   newsState.releaseEnabled=false;
   NewsMaintainPairStructureSL();
   NewsHedgeSaveState();
   消息对冲状态="双Stop均已成交：保留等手数锁仓，已接入消息箱体状态机";
   lastStatus=消息对冲状态;
}

void NewsAdoptSingleStopRunner(ulong ticket,int direction)
{
   if(!PositionSelectByTicket(ticket) || !NewsStopPositionSelected(direction))
   {
      NewsStopSetFault("单边成交仓身份校验失败");
      return;
   }
   ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double volume=PositionGetDouble(POSITION_VOLUME);
   double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
   double targetSL=direction>0 ? newsState.buyDisasterSL : newsState.sellDisasterSL;
   double currentSL=PositionGetDouble(POSITION_SL);
   if((currentSL<=0.0 || MoreProtective(type,targetSL,currentSL)) && SLTPValid(type,targetSL,0.0))
      manageTrade.PositionModify(ticket,targetSL,0.0);
   newsState.runnerTicket=ticket;
   newsState.runnerPositionId=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   newsState.runnerInitialVolume=volume;
   newsState.breakoutDirection=direction;
   newsState.breakoutPrice=openPrice;
   newsState.unhedgePrice=openPrice;
   newsState.unhedgeTime=TimeCurrent();
   newsState.unhedgeTimeMs=GetTickCount64();
   newsState.lastExtremeTimeMs=newsState.unhedgeTimeMs;
   newsState.loserTicket=0;
   newsState.loserPositionId=0;
   newsState.loserDealReady=true;
   newsState.loserActualKnown=true;
   newsState.loserDealNetMoney=0.0;
   newsState.pendingLoserLossMoney=0.0;
   newsState.stage=消息阶段_冲击持仓;
   newsState.stopStage=消息双Stop_单边托管;
   NewsHedgeSaveState();
   消息对冲状态=StringFormat("双Stop单边%s成交：另一边已确认撤销，交给现有runner托管",direction>0?"BUY":"SELL");
   lastStatus=消息对冲状态;
}

void NewsReconcileStopDeployment()
{
   if(newsState.stopToken<=0 || newsState.stopStage==消息双Stop_空闲 ||
      newsState.stopStage==消息双Stop_故障) return;
   int previousStopStage=newsState.stopStage;
   bool wasSingleRunner=(newsState.stopStage==消息双Stop_单边托管);
   NewsRecoverStopPositionIds();
   int buyOrderCount=0,sellOrderCount=0,buyPositionCount=0,sellPositionCount=0;
   ulong buyOrder=NewsFindStopOrder(1,buyOrderCount);
   ulong sellOrder=NewsFindStopOrder(-1,sellOrderCount);
   ulong buyPosition=NewsFindStopPosition(1,buyPositionCount);
   ulong sellPosition=NewsFindStopPosition(-1,sellPositionCount);
   if(buyOrderCount>1 || sellOrderCount>1 || buyPositionCount>1 || sellPositionCount>1)
   {
      NewsStopSetFault("服务器上出现重复订单或仓位");
      return;
   }
   if(buyOrder>0) newsState.buyStopOrder=buyOrder;
   if(sellOrder>0) newsState.sellStopOrder=sellOrder;
   if(buyOrder==0) newsState.buyStopDeletePending=false;
   if(sellOrder==0) newsState.sellStopDeletePending=false;

   bool anyPosition=(buyPositionCount+sellPositionCount>0);
   if(anyPosition)
   {
      if(buyPositionCount==1 && sellPositionCount==1 && !NewsPairValid(buyPosition,sellPosition))
      {
         NewsStopSetFault("双边已成交但手数不等，禁止自动撤单或平仓");
         return;
      }
      newsState.stopStage=消息双Stop_OCO撤单中;
      if(buyOrder>0) NewsRequestStopDelete(1,buyOrder);
      if(sellOrder>0) NewsRequestStopDelete(-1,sellOrder);
      if(buyOrder>0 || sellOrder>0)
      {
         消息对冲状态="双Stop已触发，OCO撤销另一边等待服务器确认";
         NewsHedgeSaveState();
         return;
      }
      if(buyPositionCount==1 && sellPositionCount==1) NewsAdoptStopPair(buyPosition,sellPosition);
      else if(buyPositionCount==1)
      {
         if(wasSingleRunner && newsState.breakoutDirection<0)
         {
            NewsStopSetFault("原SELL runner已不可见但BUY迟到成交，无法安全形成锁仓");
            return;
         }
         bool sellNeverAccepted=(newsState.sellStopOrder==0 &&
                                 (previousStopStage==消息双Stop_创建BUY待确认 ||
                                  previousStopStage==消息双Stop_全部撤单中));
         if(!sellNeverAccepted && !NewsStopOrderCancellationConfirmed(newsState.sellStopOrder))
         {
            newsState.stopStage=消息双Stop_OCO撤单中;
            消息对冲状态="BUY已成交，对侧SELL订单尚未获得历史撤销/到期/拒绝确认";
            lastStatus=消息对冲状态;
            NewsHedgeSaveState();
            return;
         }
         if(wasSingleRunner)
         {
            newsState.stopStage=消息双Stop_单边托管;
            NewsHedgeSaveState();
         }
         else NewsAdoptSingleStopRunner(buyPosition,1);
      }
      else if(sellPositionCount==1)
      {
         if(wasSingleRunner && newsState.breakoutDirection>0)
         {
            NewsStopSetFault("原BUY runner已不可见但SELL迟到成交，无法安全形成锁仓");
            return;
         }
         if(newsState.buyStopOrder==0 || !NewsStopOrderCancellationConfirmed(newsState.buyStopOrder))
         {
            newsState.stopStage=消息双Stop_OCO撤单中;
            消息对冲状态="SELL已成交，对侧BUY订单尚未获得历史撤销/到期/拒绝确认";
            lastStatus=消息对冲状态;
            NewsHedgeSaveState();
            return;
         }
         if(wasSingleRunner)
         {
            newsState.stopStage=消息双Stop_单边托管;
            NewsHedgeSaveState();
         }
         else NewsAdoptSingleStopRunner(sellPosition,-1);
      }
      else NewsStopSetFault("成交仓方向无法唯一确定");
      return;
   }

   datetime now=TimeCurrent();
   bool expired=(newsState.stopExpireTime>0 && now>=newsState.stopExpireTime);
   if(expired && newsState.stopStage!=消息双Stop_全部撤单中)
      newsState.stopStage=消息双Stop_全部撤单中;
   if(newsState.stopStage==消息双Stop_全部撤单中)
   {
      if(buyOrder>0) NewsRequestStopDelete(1,buyOrder);
      if(sellOrder>0) NewsRequestStopDelete(-1,sellOrder);
      if(buyOrder==0 && sellOrder==0)
      {
         bool buyConfirmed=NewsStopOrderCancellationConfirmed(newsState.buyStopOrder);
         bool sellConfirmed=NewsStopOrderCancellationConfirmed(newsState.sellStopOrder);
         if(buyConfirmed && sellConfirmed)
         {
            NewsHedgeReset(true);
            消息对冲状态=expired?"双Stop已到期且服务器确认无遗留挂单":"用户取消已确认，无遗留挂单";
            lastStatus=消息对冲状态;
         }
         else
         {
            消息对冲状态="双Stop活动单已不可见，仍等待历史订单确认撤销/到期";
            lastStatus=消息对冲状态;
            NewsHedgeSaveState();
         }
      }
      else
      {
         消息对冲状态="双Stop撤单中，等待服务器确认";
         NewsHedgeSaveState();
      }
      return;
   }

   NewsStopPreview preview;
   NewsBuildFrozenStopPreview(preview);
   if(newsState.stopStage==消息双Stop_创建BUY待确认)
   {
      if(buyOrder>0)
      {
         if(!preview.deployValid)
         {
            newsState.stopStage=消息双Stop_全部撤单中;
            NewsHedgeSaveState();
            NewsRequestStopDelete(1,buyOrder);
            return;
         }
         newsState.stopStage=消息双Stop_创建SELL待确认;
         newsState.stopRequestTime=now;
         NewsHedgeSaveState();
         if(!NewsSubmitStopOrder(-1,preview))
         {
            newsState.stopStage=消息双Stop_全部撤单中;
            NewsHedgeSaveState();
            NewsRequestStopDelete(1,buyOrder);
         }
      }
      else if(now-newsState.stopRequestTime>=8)
      {
         newsState.stopStage=消息双Stop_全部撤单中;
         NewsHedgeSaveState();
      }
      return;
   }
   if(newsState.stopStage==消息双Stop_创建SELL待确认)
   {
      if(buyOrder>0 && sellOrder>0)
      {
         newsState.stopStage=消息双Stop_已武装;
         NewsHedgeSaveState();
         消息对冲状态=StringFormat("双Stop ARMED | BUY #%I64u / SELL #%I64u",buyOrder,sellOrder);
         lastStatus=消息对冲状态;
      }
      else if(now-newsState.stopRequestTime>=8)
      {
         newsState.stopStage=消息双Stop_全部撤单中;
         NewsHedgeSaveState();
         if(buyOrder>0) NewsRequestStopDelete(1,buyOrder);
         if(sellOrder>0) NewsRequestStopDelete(-1,sellOrder);
      }
      return;
   }
   if(newsState.stopStage==消息双Stop_已武装 && (buyOrder==0 || sellOrder==0))
   {
      newsState.stopStage=消息双Stop_全部撤单中;
      NewsHedgeSaveState();
      if(buyOrder>0) NewsRequestStopDelete(1,buyOrder);
      if(sellOrder>0) NewsRequestStopDelete(-1,sellOrder);
   }
}

bool NewsDeployStopPair()
{
   if(!启用消息双Stop真实挂单)
   {
      lastStatus="消息双Stop参数开关已关闭，未发送任何订单";
      return false;
   }
   bool magicConflict=(消息双Stop挂单Magic<=0 || 消息双Stop挂单Magic==手机标记挂单Magic ||
                       消息双Stop挂单Magic==TEACHER_AUTO_SHORT_MAGIC ||
                       (!只管理手动单 && 消息双Stop挂单Magic==指定管理Magic));
   if(!IsHedgingAccount() || magicConflict)
   {
      lastStatus=!IsHedgingAccount() ? "双Stop部署拒绝：非Hedging账户" : "双Stop部署拒绝：Magic无效或与现有交易对象冲突";
      return false;
   }
   if(newsState.stage!=消息阶段_箱体冻结 || !newsState.boxFrozenByUser || !newsState.boxValid ||
      newsState.stopStage!=消息双Stop_空闲 || newsState.buyTicket>0 || newsState.sellTicket>0)
   {
      lastStatus="双Stop部署拒绝：阶段、箱体或已有消息仓不允许";
      return false;
   }
   if(NewsHasAnyStrategyStopObject())
   {
      lastStatus="双Stop部署拒绝：服务器存在未对账的SMA_NSO订单或仓位，需人工处理";
      return false;
   }
   NewsStopPreview preview;
   NewsBuildFrozenStopPreview(preview);
   if(!preview.deployValid)
   {
      lastStatus=preview.status;
      return false;
   }
   newsState.stopToken=(long)TimeCurrent();
   if(newsState.stopToken<=0) newsState.stopToken=1;
   newsState.stopExpireTime=TimeCurrent()+MathMax(消息双Stop有效秒数,10);
   newsState.stopRequestTime=TimeCurrent();
   newsState.stopStage=消息双Stop_创建BUY待确认;
   newsState.buyStopOrder=0;
   newsState.sellStopOrder=0;
   NewsHedgeSaveState();
   if(!NewsSubmitStopOrder(1,preview))
   {
      newsState.stopStage=消息双Stop_空闲;
      newsState.stopToken=0;
      newsState.stopExpireTime=0;
      NewsHedgeSaveState();
      lastStatus="BUY Stop请求失败，未创建SELL Stop";
      return false;
   }
   消息对冲状态="BUY Stop请求已受理，等待服务器确认后再创建SELL Stop";
   lastStatus=消息对冲状态;
   return true;
}

void NewsCancelStopDeployment()
{
   if(newsState.stopToken<=0)
   {
      lastStatus="当前没有本策略双Stop生命周期";
      return;
   }
   int buyPositions=0,sellPositions=0;
   NewsFindStopPosition(1,buyPositions);
   NewsFindStopPosition(-1,sellPositions);
   if(buyPositions+sellPositions>0 && newsState.stopStage==消息双Stop_空闲)
   {
      lastStatus="取消仅撤未成交挂单；已成交消息仓位保留并继续托管";
      return;
   }
   newsState.stopStage=消息双Stop_全部撤单中;
   NewsHedgeSaveState();
   NewsReconcileStopDeployment();
}

ulong NewsPositionIdentifier(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0;
   return (ulong)PositionGetInteger(POSITION_IDENTIFIER);
}

bool NewsMaintainPairStructureSL()
{
   if(!newsState.boxValid || !newsState.boxFrozenByUser) return false;
   bool buyOk = false;
   bool sellOk = false;
   ulong tickets[2] = {newsState.buyTicket, newsState.sellTicket};
   ENUM_POSITION_TYPE types[2] = {POSITION_TYPE_BUY, POSITION_TYPE_SELL};
   double targets[2] = {newsState.buyDisasterSL, newsState.sellDisasterSL};
   for(int i=0; i<2; i++)
   {
      if(!PositionSelectByTicket(tickets[i])) continue;
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double emergencySL = NormalizePrice(types[i] == POSITION_TYPE_BUY ?
                                           openPrice-newsState.hardStopDistance :
                                           openPrice+newsState.hardStopDistance);
      bool oldEmergency = (curSL > 0.0 && MathAbs(curSL-emergencySL) <= MathMax(_Point*3.0, newsState.normalSpreadPrice*0.25));
      double targetSL = curSL;
      if(curSL <= 0.0 || oldEmergency || MoreProtective(types[i], targets[i], curSL)) targetSL = targets[i];
      double targetTP = 消息对冲配对后清除TP ? 0.0 : curTP;
      bool ok = true;
      bool submitted = (MathAbs(targetSL-curSL) >= _Point || MathAbs(targetTP-curTP) >= _Point);
      if(submitted)
      {
         if(!SLTPValid(types[i], targetSL, targetTP)) ok = false;
         else
         {
            manageTrade.SetDeviationInPoints(MathMax(消息对冲允许滑点点数, 0));
            ok = manageTrade.PositionModify(tickets[i], targetSL, targetTP);
         }
      }
      ulong nowMs = GetTickCount64();
      bool stateChanged = (MathAbs(curSL-newsPairSLLastLogged[i]) >= _Point || ok != newsPairSLLastOk[i]);
      bool timeDue = (newsPairSLLastLogMs[i] == 0 || nowMs-newsPairSLLastLogMs[i] >= 1000);
      if(submitted || !ok || stateChanged || timeDue)
      {
         PrintRateLimited(StringFormat("news_disaster_sl:%I64u:%d:%d:%d", tickets[i], submitted, ok, manageTrade.ResultRetcode()), 10,
                          StringFormat("[消息灾难SL] %s ticket=%I64u old=%.5f target=%.5f submitted=%d emergencyOwned=%d ok=%d ret=%d %s",
                                       types[i] == POSITION_TYPE_BUY ? "BUY" : "SELL", tickets[i], curSL, targetSL,
                                       submitted, oldEmergency, ok, manageTrade.ResultRetcode(), manageTrade.ResultComment()));
         newsPairSLLastLogMs[i] = nowMs;
         newsPairSLLastLogged[i] = curSL;
         newsPairSLLastOk[i] = ok;
      }
      if(i == 0) buyOk = ok; else sellOk = ok;
   }
   return buyOk && sellOk;
}

string NewsStageName()
{
   if(newsState.stage == 消息阶段_待命) return "待命";
   if(newsState.stage == 消息阶段_配对安全) return "配对安全";
   if(newsState.stage == 消息阶段_箱体冻结) return "箱体冻结";
   if(newsState.stage == 消息阶段_释放窗口) return "释放窗口";
   if(newsState.stage == 消息阶段_拆锁中) return "拆锁中";
   if(newsState.stage == 消息阶段_冲击持仓) return "冲击持仓";
   if(newsState.stage == 消息阶段_延续持仓) return "延续持仓";
   return "组合退出";
}

void NewsRequestGroupExit(string reason)
{
   消息对冲退出原因 = reason;
   newsState.stage = 消息阶段_组合退出;
   newsState.releaseEnabled = false;
   NewsHedgeSaveState();
   NewsCloseAll(reason);
}

bool NewsFreezeBoxByUser()
{
   if(newsState.stage == 消息阶段_待命 && 启用消息双Stop真实挂单)
   {
      if(!IsHedgingAccount())
      {
         lastStatus="冻结失败：双Stop只允许在Hedging账户使用";
         return false;
      }
      ulong buyTicket=0,sellTicket=0;
      int buyCount=0,sellCount=0;
      NewsFindPairCandidates(buyTicket,sellTicket,buyCount,sellCount);
      if(buyCount+sellCount>0 || NewsHasAnyStrategyStopObject())
      {
         消息对冲状态="冻结失败: 已有消息仓位或未对账的SMA_NSO对象";
         lastStatus=消息对冲状态;
         return false;
      }
      double atr=0.0;
      GetATRPrice(atr);
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      if(bid<=0.0 || ask<=bid) return false;
      NewsHedgeReset(true);
      newsState.adoptedTemplate=(int)配置_黄金消息对冲;
      newsState.referencePrice=(bid+ask)*0.5;
      newsState.atrAtPair=atr>0.0 ? atr : MathMax(GetRecentM1RangeAverage(14),_Point*10.0);
      newsState.hardStopDistance=ClampDouble(newsState.atrAtPair*MathMax(消息对冲单边止损ATR倍数,0.10),
                                             MathMax(消息对冲单边止损最小价格,0.10),
                                             MathMax(消息对冲单边止损最大价格,消息对冲单边止损最小价格));
      if(!NewsRefreshCandidateBox(true) || newsState.referencePrice<=newsState.rangeLow ||
         newsState.referencePrice>=newsState.rangeHigh)
      {
         string reason=消息对冲箱体拒绝原因=="" ? "候选箱体无效" : 消息对冲箱体拒绝原因;
         NewsHedgeReset(true);
         消息对冲状态="冻结失败: "+reason;
         lastStatus=消息对冲状态;
         return false;
      }
      newsState.boxFrozenByUser=true;
      newsState.boxFreezeTime=TimeCurrent();
      newsState.stage=消息阶段_箱体冻结;
      newsState.releaseEnabled=false;
      NewsCalculateFrozenBuffers();
      NewsHedgeSaveState();
      NewsStopPreview preview;
      NewsBuildFrozenStopPreview(preview);
      消息对冲状态=preview.deployValid ? "箱体已冻结：风险预览有效，等待面板明确部署双Stop" : preview.status;
      lastStatus=消息对冲状态;
      return true;
   }
   if(newsState.stage != 消息阶段_配对安全)
   {
      消息对冲状态 = "冻结不可用: 当前阶段" + NewsStageName();
      lastStatus = 消息对冲状态;
      return false;
   }
   if(!NewsPairValid(newsState.buyTicket, newsState.sellTicket) || !NewsRefreshCandidateBox(true))
   {
      消息对冲状态 = "冻结失败: " + (消息对冲箱体拒绝原因 == "" ? "配对或候选箱体无效" : 消息对冲箱体拒绝原因);
      lastStatus = 消息对冲状态;
      return false;
   }
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double mid = (bid+ask)*0.5;
   if(mid <= newsState.rangeLow || mid >= newsState.rangeHigh)
   {
      消息对冲状态 = "冻结失败: 当前价格不在候选箱体内部";
      lastStatus = 消息对冲状态;
      return false;
   }
   if(!PositionSelectByTicket(newsState.buyTicket)) return false;
   double buyOpen = PositionGetDouble(POSITION_PRICE_OPEN);
   if(!PositionSelectByTicket(newsState.sellTicket)) return false;
   double sellOpen = PositionGetDouble(POSITION_PRICE_OPEN);
   if(buyOpen <= newsState.rangeLow || buyOpen >= newsState.rangeHigh ||
      sellOpen <= newsState.rangeLow || sellOpen >= newsState.rangeHigh)
   {
      消息对冲状态 = "冻结失败: 多空开仓价不在箱体内部";
      lastStatus = 消息对冲状态;
      return false;
   }
   newsState.boxFrozenByUser = true;
   newsState.boxFreezeTime = TimeCurrent();
   newsState.stage = 消息阶段_箱体冻结;
   newsState.releaseEnabled = false;
   NewsCalculateFrozenBuffers();
   bool slOk = NewsMaintainPairStructureSL();
   NewsHedgeSaveState();
   消息对冲状态 = StringFormat("箱体已冻结 %.2f-%.2f | 灾难SL %s | 等待开放",
                                newsState.rangeLow, newsState.rangeHigh, slOk ? "就绪" : "重试");
   lastStatus = 消息对冲状态;
   return true;
}

bool NewsEnableRelease()
{
   if(newsState.stage != 消息阶段_箱体冻结 || !newsState.boxFrozenByUser || !newsState.boxValid)
   {
      消息对冲状态 = "请先冻结有效箱体";
      lastStatus = 消息对冲状态;
      return false;
   }
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= bid) return false;
   double mid = (bid+ask)*0.5;
   double edgeTolerance = MathMin(newsState.breakoutBuffer,
                                  MathMax(newsState.normalSpreadPrice*2.0, NewsBrokerMinimumStopDistance()));
   if(mid < newsState.rangeLow-edgeTolerance || mid > newsState.rangeHigh+edgeTolerance)
   {
      NewsRequestGroupExit("消息前箱体已失效");
      return false;
   }
   newsState.releaseEnabled = true;
   newsState.releaseTime = TimeCurrent();
   newsState.releaseExpireTime = newsState.releaseTime + MathMax(消息对冲开放后有效秒数, 1);
   newsState.releaseStartMs = GetTickCount64();
   newsState.stage = 消息阶段_释放窗口;
   newsState.candidateDirection = 0;
   newsState.candidateTicks = 0;
   newsState.candidateStartMs = 0;
   newsState.pendingBreakoutDirection = 0;
   newsState.pendingBreakoutStartMs = 0;
   newsMicroHead = 0;
   newsMicroCount = 0;
   NewsHedgeSaveState();
   消息对冲状态 = StringFormat("已开放拆锁 | 有效%d秒", MathMax(消息对冲开放后有效秒数, 1));
   lastStatus = 消息对冲状态;
   return true;
}

bool NewsApplyEmergencySL(ulong ticket, ENUM_POSITION_TYPE type, double distance)
{
   if(!PositionSelectByTicket(ticket)) return false;
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   double candidate = NormalizePrice(type == POSITION_TYPE_BUY ? openPrice - distance : openPrice + distance);
   double targetSL = curSL;
   if(curSL <= 0.0 || MoreProtective(type, candidate, curSL)) targetSL = candidate;
   double targetTP = 消息对冲配对后清除TP ? 0.0 : curTP;
   if(MathAbs(targetSL - curSL) < _Point && MathAbs(targetTP - curTP) < _Point) return true;
   if(!SLTPValid(type, targetSL, targetTP)) return false;
   manageTrade.SetDeviationInPoints(MathMax(消息对冲允许滑点点数, 0));
   return manageTrade.PositionModify(ticket, targetSL, targetTP);
}

bool NewsCloseTicket(ulong ticket)
{
   if(!NewsPositionExists(ticket)) return true;
   // 最终交易闸门：即使恢复状态或候选扫描出现异常，消息模块也绝不能
   // 向未在真实入场时冻结为消息模板的仓位发送市价平仓请求。
   if(!NewsPositionEligibleSelected())
   {
      PrintFormat("[消息安全] 拒绝非消息冻结仓平仓 ticket=%I64u", ticket);
      return false;
   }
   manageTrade.SetDeviationInPoints(MathMax(消息对冲允许滑点点数, 0));
   return manageTrade.PositionClose(ticket);
}

void NewsCloseEligiblePositions(string reason)
{
   // 仅允许由消息面板中的“取消本次消息/紧急全平”显式调用。
   // 自动配对扫描不得再调用本函数，避免配置切换或异常组合越权全平。
   ulong tickets[];
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !NewsPositionEligibleSelected()) continue;
      int n = ArraySize(tickets);
      ArrayResize(tickets, n + 1);
      tickets[n] = tk;
   }
   bool allOk = true;
   for(int i=0; i<ArraySize(tickets); i++)
   {
      if(!NewsCloseTicket(tickets[i])) allOk = false;
      if(NewsPositionExists(tickets[i])) allOk = false;
   }
   消息对冲状态 = allOk ? reason + "，已全平" : reason + "，部分平仓失败将重试";
   lastStatus = 消息对冲状态;
   PrintFormat("[消息平仓] 用户明确指令 reason=%s tickets=%d success=%d",
               reason, ArraySize(tickets), allOk);
}

void NewsCloseAll(string reason)
{
   if(newsState.stage != 消息阶段_待命)
   {
      newsState.stage = 消息阶段_组合退出;
      newsState.releaseEnabled = false;
      if(消息对冲退出原因 == "") 消息对冲退出原因 = reason;
   }
   bool hadBuy = NewsPositionExists(newsState.buyTicket);
   bool okBuy = NewsCloseTicket(newsState.buyTicket);
   if(hadBuy && okBuy)
   {
      ulong deal = manageTrade.ResultDeal();
      if(deal > 0 && !NewsRecordDeal(deal, "组合退出BUY")) NewsEnqueuePendingDeal(deal);
   }
   bool hadSell = NewsPositionExists(newsState.sellTicket);
   bool okSell = NewsCloseTicket(newsState.sellTicket);
   if(hadSell && okSell)
   {
      ulong deal = manageTrade.ResultDeal();
      if(deal > 0 && !NewsRecordDeal(deal, "组合退出SELL")) NewsEnqueuePendingDeal(deal);
   }
   bool hadRunner = NewsPositionExists(newsState.runnerTicket);
   bool okRunner = NewsCloseTicket(newsState.runnerTicket);
   if(hadRunner && okRunner)
   {
      ulong deal = manageTrade.ResultDeal();
      if(deal > 0 && !NewsRecordDeal(deal, "组合退出Runner")) NewsEnqueuePendingDeal(deal);
   }
   if(!NewsPositionExists(newsState.buyTicket) && !NewsPositionExists(newsState.sellTicket) && !NewsPositionExists(newsState.runnerTicket))
   {
      if(newsState.groupFlatSince <= 0) newsState.groupFlatSince = TimeCurrent();
      if(newsPendingDealCount > 0 || newsState.runnerPartialTargetStage > 0 ||
         TimeCurrent()-newsState.groupFlatSince < 2)
      {
         消息对冲状态 = StringFormat("%s，仓位已平，等待成交确认 %d笔", reason, newsPendingDealCount);
         lastStatus = 消息对冲状态;
         NewsHedgeSaveState();
         return;
      }
      double loserNet = newsState.loserActualKnown ? newsState.loserDealNetMoney : -newsState.pendingLoserLossMoney;
      double finalCombined = loserNet + newsState.realizedRunnerProfitMoney;
      PrintFormat("[消息箱体] 最终组合退出 reason=%s result=%.2f runnerRealized=%.2f loserNet=%.2f actualCost=%.2f",
                  reason, finalCombined, newsState.realizedRunnerProfitMoney,
                  loserNet, newsState.actualCostMoney);
      NewsHedgeReset(true);
      消息对冲状态 = reason + "，已全平";
      lastStatus = 消息对冲状态;
   }
   else
   {
      消息对冲状态 = reason + StringFormat("，平仓重试 B%d/S%d/R%d", okBuy, okSell, okRunner);
      lastStatus = 消息对冲状态;
      NewsHedgeSaveState();
   }
}

bool NewsPairValid(ulong buyTicket, ulong sellTicket)
{
   if(!PositionSelectByTicket(buyTicket)) return false;
   double buyVol = PositionGetDouble(POSITION_VOLUME);
   datetime buyTime = (datetime)PositionGetInteger(POSITION_TIME);
   bool stopBuy=NewsStopPositionSelected(1);
   if(!PositionSelectByTicket(sellTicket)) return false;
   double sellVol = PositionGetDouble(POSITION_VOLUME);
   datetime sellTime = (datetime)PositionGetInteger(POSITION_TIME);
   bool stopSell=NewsStopPositionSelected(-1);

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double volTolerance = MathMax(消息对冲手数容差, step * 0.5);
   if(MathAbs(buyVol - sellVol) > volTolerance) return false;
   if(stopBuy && stopSell) return true;
   return (MathAbs((double)(buyTime - sellTime)) <= MathMax(消息对冲最大开仓时间差秒, 1));
}

bool NewsRefreshCandidateBox(bool refreshSpread)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= bid) return false;
   if(refreshSpread || newsState.normalSpreadPrice <= 0.0)
   {
      bool usedTickMedian = false;
      newsState.normalSpreadPrice = NewsNormalSpreadPrice(usedTickMedian);
   }
   double boxHigh = 0.0, boxLow = 0.0, closeInsideRatio = 0.0;
   int highTouches = 0, lowTouches = 0, middleCrosses = 0;
   string rejectReason = "";
   if(!NewsBuildFrozenBox((bid+ask)*0.5, newsState.atrAtPair, newsState.normalSpreadPrice,
                          boxHigh, boxLow, highTouches, lowTouches, middleCrosses,
                          closeInsideRatio, rejectReason))
   {
      newsState.boxValid = false;
      newsState.rangeHigh = 0.0;
      newsState.rangeLow = 0.0;
      newsState.boxWidth = 0.0;
      消息对冲箱体拒绝原因 = rejectReason;
      return false;
   }
   newsState.boxValid = true;
   newsState.rangeHigh = boxHigh;
   newsState.rangeLow = boxLow;
   newsState.boxWidth = boxHigh-boxLow;
   newsState.boxHighTouches = highTouches;
   newsState.boxLowTouches = lowTouches;
   newsState.boxMiddleCrosses = middleCrosses;
   newsState.boxCloseInsideRatio = closeInsideRatio;
   消息对冲箱体拒绝原因 = "";
   NewsCalculateFrozenBuffers();
   return true;
}

bool NewsEstablishPair(ulong buyTicket, ulong sellTicket, double atr)
{
   消息对冲箱体拒绝原因 = "";
   if(!NewsPairValid(buyTicket, sellTicket)) return false;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return false;
   double mid = (bid + ask) * 0.5;
   NewsHedgeReset(true);
   newsState.stage = 消息阶段_配对安全;
   newsState.adoptedTemplate = (int)配置_黄金消息对冲;
   newsState.buyTicket = buyTicket;
   newsState.sellTicket = sellTicket;
   newsState.buyPositionId = NewsPositionIdentifier(buyTicket);
   newsState.sellPositionId = NewsPositionIdentifier(sellTicket);
   if(PositionSelectByTicket(buyTicket)) newsState.buyOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   if(PositionSelectByTicket(sellTicket)) newsState.sellOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   newsState.pairTime = TimeCurrent();
   newsState.referencePrice = mid;
   newsState.atrAtPair = atr > 0.0 ? atr : MathMax(GetRecentM1RangeAverage(14), _Point * 10.0);
   newsState.hardStopDistance = ClampDouble(newsState.atrAtPair * MathMax(消息对冲单边止损ATR倍数, 0.10),
                                            MathMax(消息对冲单边止损最小价格, 0.10),
                                            MathMax(消息对冲单边止损最大价格, 消息对冲单边止损最小价格));
   bool candidateOk = NewsRefreshCandidateBox(true);
   double pairVol = MathMax(NewsPositionVolume(buyTicket), NewsPositionVolume(sellTicket));
   newsState.estimatedExtraCostMoney = NewsMoneyScale(消息对冲每001手预估额外成本金额, pairVol);
   newsState.estimatedRemainingExitCostMoney = newsState.estimatedExtraCostMoney;
   NewsApplyEmergencySL(buyTicket, POSITION_TYPE_BUY, newsState.hardStopDistance);
   NewsApplyEmergencySL(sellTicket, POSITION_TYPE_SELL, newsState.hardStopDistance);
   NewsHedgeSaveState();
   消息对冲状态 = candidateOk ?
      StringFormat("配对安全 | 候选箱体%.2f-%.2f | 请在消息前冻结", newsState.rangeLow, newsState.rangeHigh) :
      "配对安全 | 当前无有效候选箱体: " + 消息对冲箱体拒绝原因;
   lastStatus = 消息对冲状态;
   return true;
}

bool NewsBreakoutConfirmed(int direction)
{
   ulong nowMs = GetTickCount64();
   if(direction == 0)
   {
      newsState.candidateDirection = 0;
      newsState.candidateTicks = 0;
      newsState.candidateStartMs = 0;
      return false;
   }
   if(newsState.candidateDirection != direction)
   {
      newsState.candidateDirection = direction;
      newsState.candidateTicks = 1;
      newsState.candidateStartMs = nowMs;
      return false;
   }
   newsState.candidateTicks++;
   return (newsState.candidateTicks >= MathMax(消息对冲突破确认Tick数, 1) &&
           nowMs - newsState.candidateStartMs >= (ulong)MathMax(消息对冲突破确认毫秒, 0));
}

double NewsEstimateRemainingExitCost(double volume)
{
   return NewsMoneyScale(MathMax(消息对冲每001手预估额外成本金额, 0.0) * 0.5, volume);
}

ulong NewsCurrentTickTimeMsc()
{
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick) && tick.time_msc > 0) return (ulong)tick.time_msc;
   return (ulong)TimeCurrent()*1000;
}

double NewsDynamicSpreadLimit()
{
   double dynamicLimit = newsState.normalSpreadPrice * MathMax(消息对冲最大拆锁点差倍数, 0.0);
   if(消息对冲绝对最大拆锁点差价格 > 0.0)
      return MathMin(dynamicLimit, 消息对冲绝对最大拆锁点差价格);
   return dynamicLimit;
}

bool NewsPendingDealContains(ulong dealTicket)
{
   for(int i=0; i<newsPendingDealCount; i++)
      if(newsPendingDeals[i] == dealTicket) return true;
   return false;
}

bool NewsEnqueuePendingDeal(ulong dealTicket)
{
   if(dealTicket == 0 || NewsPendingDealContains(dealTicket)) return true;
   if(newsPendingDealCount >= NEWS_PENDING_DEAL_CAPACITY)
   {
      PrintRateLimited("news_pending_queue_full", 10,
                       StringFormat("[消息成交] 待补录队列已满，拒绝覆盖 deal=%I64u capacity=%d",
                                    dealTicket, NEWS_PENDING_DEAL_CAPACITY));
      return false;
   }
   newsPendingDeals[newsPendingDealCount++] = dealTicket;
   NewsHedgeSaveState();
   PrintFormat("[消息成交] deal=%I64u 已加入待补录队列 count=%d", dealTicket, newsPendingDealCount);
   return true;
}

void NewsRemovePendingDealAt(int index)
{
   if(index < 0 || index >= newsPendingDealCount) return;
   for(int i=index; i<newsPendingDealCount-1; i++) newsPendingDeals[i] = newsPendingDeals[i+1];
   newsPendingDealCount--;
   newsPendingDeals[newsPendingDealCount] = 0;
}

double NewsDesiredRunnerStructureSL()
{
   if(!newsState.boxValid || newsState.breakoutDirection == 0) return 0.0;
   return NormalizePrice(newsState.breakoutDirection > 0 ?
                         newsState.rangeHigh-newsState.failureBuffer :
                         newsState.rangeLow+newsState.failureBuffer);
}

void NewsUpdateActualUnlockMetrics()
{
   if(!newsState.loserDealReady || newsState.loserClosePrice <= 0.0 || newsState.breakoutDirection == 0) return;
   newsState.actualUnlockExtension = newsState.breakoutDirection > 0 ?
                                     newsState.loserClosePrice-newsState.rangeHigh :
                                     newsState.rangeLow-newsState.loserClosePrice;
   newsState.actualUnlockSlippage = newsState.breakoutPrice > 0.0 ?
                                    MathAbs(newsState.loserClosePrice-newsState.breakoutPrice) : 0.0;
}

bool NewsActualUnlockTooLate(string &reason)
{
   reason = "";
   NewsUpdateActualUnlockMetrics();
   if(!newsState.loserDealReady || newsState.breakoutDirection == 0) return false;
   double maxExtension = NewsMaxUnlockExtension();
   if(newsState.actualUnlockExtension > maxExtension)
   {
      reason = StringFormat("实际成交延伸%.2f超过允许%.2f", newsState.actualUnlockExtension, maxExtension);
      return true;
   }
   if(!NewsPositionExists(newsState.runnerTicket) || !NewsQuoteValid()) return false;
   double currentPrice = newsState.breakoutDirection > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentExtension = MathMax(newsState.breakoutDirection > 0 ? currentPrice-newsState.rangeHigh :
                                     newsState.rangeLow-currentPrice, 0.0);
   double structureSL = newsState.runnerStructureSL > 0.0 ? newsState.runnerStructureSL : NewsDesiredRunnerStructureSL();
   double riskDistance = newsState.breakoutDirection > 0 ? currentPrice-structureSL : structureSL-currentPrice;
   double expectedTotal = 消息对冲预期消息波幅价格 > 0.0 ? 消息对冲预期消息波幅价格 : maxExtension;
   double remainingDistance = MathMax(expectedTotal-currentExtension, 0.0);
   double rr = riskDistance > _Point ? remainingDistance/riskDistance : 0.0;
   if(riskDistance <= _Point || rr < MathMax(消息对冲实际成交后最小剩余盈亏比, 0.0))
   {
      reason = StringFormat("实际成交后剩余盈亏比%.2f低于%.2f", rr, MathMax(消息对冲实际成交后最小剩余盈亏比, 0.0));
      return true;
   }
   return false;
}

double NewsEstimateDisasterLoserLoss(int direction, double volume)
{
   double openPrice = direction > 0 ? newsState.sellOpenPrice : newsState.buyOpenPrice;
   double stopPrice = direction > 0 ? newsState.sellDisasterSL : newsState.buyDisasterSL;
   ENUM_ORDER_TYPE orderType = direction > 0 ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   double profitAtStop = 0.0;
   if(openPrice > 0.0 && stopPrice > 0.0 && volume > 0.0 &&
      OrderCalcProfit(orderType, _Symbol, volume, openPrice, stopPrice, profitAtStop))
      return MathMax(-profitAtStop, 0.0);
   return NewsPriceDistanceToMoney(MathAbs(stopPrice-openPrice), volume);
}

bool NewsSelectRunnerPosition(double &volume)
{
   volume = 0.0;
   if(newsState.runnerPositionId == 0) return false;
   ulong ticket = newsState.runnerTicket;
   if(ticket == 0 || !PositionSelectByTicket(ticket) ||
      (ulong)PositionGetInteger(POSITION_IDENTIFIER) != newsState.runnerPositionId)
   {
      ticket = FindOpenPositionTicketByIdentifier(newsState.runnerPositionId);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) return false;
   }
   if(!NewsPositionEligibleSelected()) return false;
   newsState.runnerTicket = ticket;
   volume = PositionGetDouble(POSITION_VOLUME);
   return true;
}

bool NewsRefreshRunnerDealTotals(bool adjustActualCost)
{
   if(newsState.runnerPositionId == 0 || !HistorySelectByPosition(newsState.runnerPositionId)) return false;
   double netTotal = 0.0;
   double exitVolume = 0.0;
   double costTotal = 0.0;
   datetime cutoff = newsState.unhedgeTime > 0 ? newsState.unhedgeTime : newsState.pairTime;
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0 || (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != newsState.runnerPositionId) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT) continue;
      if(cutoff > 0 && (datetime)HistoryDealGetInteger(deal, DEAL_TIME) < cutoff) continue;
      double commission = HistoryDealGetDouble(deal, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(deal, DEAL_SWAP);
      double fee = HistoryDealGetDouble(deal, DEAL_FEE);
      netTotal += HistoryDealGetDouble(deal, DEAL_PROFIT) + commission + swap + fee;
      exitVolume += HistoryDealGetDouble(deal, DEAL_VOLUME);
      costTotal += MathMax(-(commission+swap+fee), 0.0);
   }
   if(adjustActualCost)
      newsState.actualCostMoney = MathMax(newsState.actualCostMoney + costTotal-newsState.runnerActualCostMoney, 0.0);
   newsState.runnerActualCostMoney = costTotal;
   newsState.realizedRunnerProfitMoney = netTotal;
   newsState.runnerRealizedExitVolume = exitVolume;
   newsState.runnerPendingEstimateMoney = 0.0;
   return true;
}

void NewsClearRunnerPartialRequest(bool clearTarget)
{
   newsState.runnerPartialPending = false;
   newsState.runnerPartialRequestedVolume = 0.0;
   if(clearTarget)
   {
      newsState.runnerPartialRequestTime = 0;
      newsState.runnerPartialTargetStage = 0;
      newsState.runnerPartialStageStartVolume = 0.0;
      newsState.runnerPartialTargetVolume = 0.0;
      newsState.runnerPartialStageStartExitVolume = 0.0;
      newsState.runnerPartialFilledVolume = 0.0;
   }
}

bool NewsReconcileRunnerPartial(bool refreshHistory)
{
   if(newsState.runnerPartialTargetStage <= 0) return false;
   if(refreshHistory && !NewsRefreshRunnerDealTotals(true)) return false;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   double currentVolume = 0.0;
   bool runnerAlive = NewsSelectRunnerPosition(currentVolume);
   if(!runnerAlive) currentVolume = 0.0;
   double requiredFill = MathMax(newsState.runnerPartialStageStartVolume-newsState.runnerPartialTargetVolume, 0.0);
   double actualFill = MathMax(newsState.runnerRealizedExitVolume-newsState.runnerPartialStageStartExitVolume, 0.0);
   newsState.runnerPartialFilledVolume = actualFill;
   bool dealConfirmed = (actualFill > step*0.5 && actualFill+step*0.5 >= requiredFill);
   bool volumeConfirmed = (currentVolume <= newsState.runnerPartialTargetVolume+step*0.5);
   if(dealConfirmed && volumeConfirmed)
   {
      int completedStage = newsState.runnerPartialTargetStage;
      if(completedStage == 1) newsState.firstPartialDone = true;
      else
      {
         newsState.firstPartialDone = true;
         newsState.secondPartialDone = true;
      }
      newsState.runnerPartialStage = MathMax(newsState.runnerPartialStage, completedStage);
      newsState.lastPartialTime = TimeCurrent();
      newsState.estimatedRemainingExitCostMoney = NewsEstimateRemainingExitCost(currentVolume);
      PrintFormat("[消息成交] 第%d段真实确认 filled=%.2f required=%.2f remaining=%.2f target=%.2f realizedNet=%.2f",
                  completedStage, actualFill, requiredFill, currentVolume,
                  newsState.runnerPartialTargetVolume, newsState.realizedRunnerProfitMoney);
      NewsClearRunnerPartialRequest(true);
      NewsHedgeSaveState();
      消息对冲状态 = StringFormat("消息第%d段已由真实Deal确认 %.2f手，剩余%.2f",
                                   completedStage, actualFill, currentVolume);
      lastStatus = 消息对冲状态;
      return true;
   }
   if(!newsState.runnerPartialPending || newsState.runnerPartialRequestTime <= 0 ||
      TimeCurrent()-newsState.runnerPartialRequestTime < NEWS_PARTIAL_TIMEOUT_SECONDS) return false;
   if(!runnerAlive || volumeConfirmed)
   {
      PrintRateLimited("news_runner_partial_wait_deal", 10,
                       StringFormat("[消息成交] 第%d段仓量已到目标或仓位消失，但真实Deal量尚不足 filled=%.2f required=%.2f，继续等待",
                                    newsState.runnerPartialTargetStage, actualFill, requiredFill));
      return false;
   }
   PrintFormat("[消息成交] 第%d段请求超时，按服务器剩余量补发差额 current=%.2f target=%.2f actualFill=%.2f",
               newsState.runnerPartialTargetStage, currentVolume,
               newsState.runnerPartialTargetVolume, actualFill);
   NewsClearRunnerPartialRequest(false);
   NewsHedgeSaveState();
   return false;
}

void NewsMigrateLegacyRunnerPartialState(bool legacyFirstDone, bool legacySecondDone, int legacyStage)
{
   newsState.realizedRunnerProfitMoney -= newsState.runnerPendingEstimateMoney;
   newsState.runnerPendingEstimateMoney = 0.0;
   newsState.firstPartialDone = false;
   newsState.secondPartialDone = false;
   newsState.runnerPartialStage = 0;
   NewsClearRunnerPartialRequest(true);
   NewsRefreshRunnerDealTotals(false);
   double currentVolume = 0.0;
   bool runnerAlive = NewsSelectRunnerPosition(currentVolume);
   if(!runnerAlive) currentVolume = 0.0;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(step <= 0.0) step = 0.01;
   if(minVol <= 0.0) minVol = step;
   double initialVolume = newsState.runnerInitialVolume;
   double close1 = NormalizeVolumeDown(initialVolume * ClampDouble(消息对冲第1段平仓比例, 0.05, 0.90));
   if(close1 >= initialVolume) close1 = NormalizeVolumeDown(initialVolume-minVol);
   double target1 = NormalizeVolumeDown(MathMax(initialVolume-close1, 0.0));
   bool firstConfirmed = (close1 >= minVol && newsState.runnerRealizedExitVolume+step*0.5 >= close1 &&
                          currentVolume <= target1+step*0.5);
   if(legacyFirstDone && firstConfirmed)
   {
      newsState.firstPartialDone = true;
      newsState.runnerPartialStage = 1;
   }
   else if(legacyFirstDone || legacyStage >= 1)
   {
      newsState.runnerPartialTargetStage = 1;
      newsState.runnerPartialStageStartVolume = initialVolume;
      newsState.runnerPartialTargetVolume = target1;
      newsState.runnerPartialStageStartExitVolume = 0.0;
      newsState.runnerPartialFilledVolume = newsState.runnerRealizedExitVolume;
      newsState.runnerPartialPending = true;
      newsState.runnerPartialRequestTime = newsState.lastPartialTime > 0 ? newsState.lastPartialTime : TimeCurrent();
   }
   if(newsState.firstPartialDone && (legacySecondDone || legacyStage >= 2))
   {
      double close2 = NormalizeVolumeDown(initialVolume * ClampDouble(消息对冲第2段平仓初始手数比例, 0.05, 0.90));
      if(close2 >= target1) close2 = NormalizeVolumeDown(target1-minVol);
      double target2 = NormalizeVolumeDown(MathMax(target1-close2, 0.0));
      bool secondConfirmed = (close2 >= minVol && newsState.runnerRealizedExitVolume+step*0.5 >= close1+close2 &&
                              currentVolume <= target2+step*0.5);
      if(secondConfirmed)
      {
         newsState.secondPartialDone = true;
         newsState.runnerPartialStage = 2;
      }
      else
      {
         newsState.runnerPartialTargetStage = 2;
         newsState.runnerPartialStageStartVolume = target1;
         newsState.runnerPartialTargetVolume = target2;
         newsState.runnerPartialStageStartExitVolume = close1;
         newsState.runnerPartialFilledVolume = MathMax(newsState.runnerRealizedExitVolume-close1, 0.0);
         newsState.runnerPartialPending = true;
         newsState.runnerPartialRequestTime = newsState.lastPartialTime > 0 ? newsState.lastPartialTime : TimeCurrent();
      }
   }
   NewsHedgeSaveState();
}

bool NewsRecordDeal(ulong dealTicket, string source)
{
   if(dealTicket == 0 || !HistoryDealSelect(dealTicket)) return false;
   if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) return false;
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT) return false;
   ulong positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
   double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
   double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
   double fee = HistoryDealGetDouble(dealTicket, DEAL_FEE);
   double net = profit + commission + swap + fee;
   double price = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
   ulong dealTimeMsc = (ulong)HistoryDealGetInteger(dealTicket, DEAL_TIME_MSC);
   if(dealTimeMsc == 0) dealTimeMsc = (ulong)HistoryDealGetInteger(dealTicket, DEAL_TIME)*1000;
   ENUM_DEAL_REASON reason = (ENUM_DEAL_REASON)HistoryDealGetInteger(dealTicket, DEAL_REASON);

   bool pairSide = (positionId > 0 && (positionId == newsState.buyPositionId || positionId == newsState.sellPositionId));
   bool loserSide = (positionId > 0 && positionId == newsState.loserPositionId);
   bool runnerSide = (positionId > 0 && positionId == newsState.runnerPositionId);
   bool pairedStage = (newsState.stage == 消息阶段_配对安全 || newsState.stage == 消息阶段_箱体冻结 ||
                       newsState.stage == 消息阶段_释放窗口 || newsState.stage == 消息阶段_组合退出);
   bool accountAsLoser = (loserSide || (pairSide && pairedStage && !runnerSide));
   if(accountAsLoser && dealTicket == newsState.lastLoserDeal) return true;
   if(runnerSide && dealTicket == newsState.lastRunnerDeal) return true;
   if(accountAsLoser && dealTicket != newsState.lastLoserDeal)
   {
      newsState.lastLoserDeal = dealTicket;
      newsState.loserPositionId = positionId;
      newsState.loserDealNetMoney += net;
      newsState.loserActualKnown = true;
      newsState.loserDealReady = true;
      newsState.loserClosePrice = price;
      newsState.loserCloseTimeMsc = dealTimeMsc;
      newsState.realizedLoserLossMoney = MathMax(-newsState.loserDealNetMoney, 0.0);
      newsState.pendingLoserLossMoney = MathMax(newsState.pendingLoserLossMoney, newsState.realizedLoserLossMoney);
      newsState.actualCostMoney += MathMax(-(commission+swap+fee), 0.0);
      NewsUpdateActualUnlockMetrics();
      PrintFormat("[消息成交] %s loser deal=%I64u pos=%I64u reason=%d price=%.5f timeMsc=%I64u extension=%.5f slip=%.5f profit=%.2f commission=%.2f swap=%.2f fee=%.2f net=%.2f",
                   source, dealTicket, positionId, reason, price, newsState.loserCloseTimeMsc,
                   newsState.actualUnlockExtension, newsState.actualUnlockSlippage,
                   profit, commission, swap, fee, net);
      if(reason == DEAL_REASON_SL)
         PrintFormat("[消息成交] 服务器SL触发 position=%I64u actualLoss=%.2f", positionId, newsState.realizedLoserLossMoney);
      NewsHedgeSaveState();
      if(newsState.breakoutDirection != 0 && newsState.stage != 消息阶段_组合退出 && NewsPositionExists(newsState.runnerTicket))
      {
         string actualLateReason = "";
         if(NewsActualUnlockTooLate(actualLateReason))
         {
            PrintFormat("[消息短时] 实际拆锁成交过晚 price=%.5f extension=%.5f slip=%.5f reason=%s",
                        newsState.loserClosePrice, newsState.actualUnlockExtension, newsState.actualUnlockSlippage, actualLateReason);
            NewsRequestGroupExit("实际拆锁成交过晚，放弃追消息");
            return true;
         }
         NewsTryPrepareRunnerRisk();
      }
      return true;
   }
   if(runnerSide && dealTicket != newsState.lastRunnerDeal)
   {
      newsState.lastRunnerDeal = dealTicket;
      if(!NewsRefreshRunnerDealTotals(true)) return false;
      newsState.estimatedRemainingExitCostMoney = NewsEstimateRemainingExitCost(NewsPositionVolume(newsState.runnerTicket));
      PrintFormat("[消息成交] %s runner deal=%I64u pos=%I64u reason=%d price=%.5f profit=%.2f commission=%.2f swap=%.2f fee=%.2f net=%.2f",
                  source, dealTicket, positionId, reason, price, profit, commission, swap, fee, net);
      NewsReconcileRunnerPartial(false);
      NewsHedgeSaveState();
      return true;
   }
   return false;
}

double NewsMaxUnlockExtension()
{
   double structural = MathMax(newsState.boxWidth * MathMax(消息对冲最晚拆锁箱体倍数, 0.0),
                               newsState.atrAtPair * MathMax(消息对冲最晚拆锁ATR倍数, 0.0));
   if(消息对冲预期消息波幅价格 > 0.0)
      structural = MathMin(structural, 消息对冲预期消息波幅价格 * ClampDouble(消息对冲最大已运行波幅比例, 0.05, 1.0));
   return structural;
}

bool NewsUnlockTooLate(int direction, double midPrice, string &reason)
{
   reason = "";
   int elapsed = newsState.releaseTime > 0 ? (int)(TimeCurrent()-newsState.releaseTime) : 0;
   double extension = direction > 0 ? midPrice-newsState.rangeHigh : newsState.rangeLow-midPrice;
   double maximum = NewsMaxUnlockExtension();
   if(elapsed > MathMax(消息对冲最晚拆锁秒数, 1))
      reason = StringFormat("开放后%d秒超过最晚拆锁%d秒", elapsed, MathMax(消息对冲最晚拆锁秒数, 1));
   else if(extension > maximum)
      reason = StringFormat("已延伸%.2f超过允许%.2f", extension, maximum);
   if(reason != "")
   {
      PrintFormat("[消息短时] 拆锁过晚 dir=%d extension=%.5f max=%.5f elapsed=%d reason=%s",
                  direction, extension, maximum, elapsed, reason);
      return true;
   }
   return false;
}

double NewsEstimateInitialGroupRiskMoney()
{
   if(!newsState.loserDealReady || newsState.actualRunnerRiskSL <= 0.0 ||
      !PositionSelectByTicket(newsState.runnerTicket)) return 0.0;
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double volume = PositionGetDouble(POSITION_VOLUME);
   double profitAtSL = 0.0;
   ENUM_ORDER_TYPE orderType = type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   if(!OrderCalcProfit(orderType, _Symbol, volume, openPrice, newsState.actualRunnerRiskSL, profitAtSL))
      profitAtSL = -NewsPriceDistanceToMoney(MathAbs(openPrice-newsState.actualRunnerRiskSL), volume);
   double loserNet = newsState.loserDealNetMoney;
   double groupAtSL = loserNet + newsState.realizedRunnerProfitMoney + profitAtSL - newsState.estimatedRemainingExitCostMoney;
   double minRisk = NewsMoneyScale(消息对冲每001手最小组合风险金额, MathMax(newsState.runnerInitialVolume, volume));
   double risk = MathMax(-groupAtSL, MathMax(minRisk, 0.01));
   PrintFormat("[消息短时] 初始组合风险Ready R=%.2f loserNet=%.2f runnerAtActualSL=%.2f remainingCost=%.2f actualSL=%.5f",
               risk, loserNet, profitAtSL, newsState.estimatedRemainingExitCostMoney, newsState.actualRunnerRiskSL);
   return risk;
}

void NewsTryPendingDeals()
{
   bool changed = false;
   static ulong lastUnmatchedLogMs = 0;
   for(int i=0; i<newsPendingDealCount; i++)
   {
      ulong deal = newsPendingDeals[i];
      if(deal == 0 || !HistoryDealSelect(deal)) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      bool recordableExit = (HistoryDealGetString(deal, DEAL_SYMBOL) == _Symbol &&
                             (entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT));
      if(!recordableExit)
      {
         PrintFormat("[消息成交] deal=%I64u 不是当前品种的出场成交，移出待补录队列 entry=%d", deal, entry);
         NewsRemovePendingDealAt(i);
         i--;
         changed = true;
         continue;
      }
      if(NewsRecordDeal(deal, "延迟成交补录"))
      {
         NewsRemovePendingDealAt(i);
         i--;
         changed = true;
      }
      else
      {
         ulong nowMs = GetTickCount64();
         if(lastUnmatchedLogMs == 0 || nowMs-lastUnmatchedLogMs >= 1000)
         {
            PrintRateLimited(StringFormat("news_pending_unmatched:%I64u", deal), 10,
                             StringFormat("[消息成交] deal=%I64u 历史已可读但尚未匹配当前消息组，保留队列 count=%d",
                                          deal, newsPendingDealCount));
            lastUnmatchedLogMs = nowMs;
         }
      }
   }
   if(changed) NewsHedgeSaveState();
}

void NewsBeginUnhedge(int direction, string reason)
{
   if(newsState.stage != 消息阶段_释放窗口 || !newsState.releaseEnabled) return;
   double mid = (SymbolInfoDouble(_Symbol, SYMBOL_BID)+SymbolInfoDouble(_Symbol, SYMBOL_ASK))*0.5;
   string lateReason = "";
   if(NewsUnlockTooLate(direction, mid, lateReason))
   {
      NewsRequestGroupExit("拆锁过晚，放弃追消息: " + lateReason);
      return;
   }
   newsState.breakoutDirection = direction;
   newsState.runnerTicket = direction > 0 ? newsState.buyTicket : newsState.sellTicket;
   newsState.loserTicket = direction > 0 ? newsState.sellTicket : newsState.buyTicket;
   newsState.runnerPositionId = direction > 0 ? newsState.buyPositionId : newsState.sellPositionId;
   newsState.loserPositionId = direction > 0 ? newsState.sellPositionId : newsState.buyPositionId;
   newsState.runnerRiskReady = false;
   newsState.actualRunnerRiskSL = 0.0;
   newsState.initialGroupRiskMoney = 0.0;
   newsState.runnerStructureSL = NewsDesiredRunnerStructureSL();
   newsState.runnerBoxProtectionApplied = false;
   if(NewsPositionExists(newsState.loserTicket))
      newsState.pendingLoserLossMoney = MathMax(newsState.pendingLoserLossMoney,
                                                MathMax(-NewsPositionMoney(newsState.loserTicket), 0.0));
   newsState.breakoutPrice = mid;
   NewsUpdateActualUnlockMetrics();
   if(newsState.loserDealReady)
   {
      string actualLateReason = "";
      if(NewsActualUnlockTooLate(actualLateReason))
      {
         PrintFormat("[消息短时] 服务器成交后二次检查失败 extension=%.5f slip=%.5f reason=%s",
                     newsState.actualUnlockExtension, newsState.actualUnlockSlippage, actualLateReason);
         NewsRequestGroupExit("实际拆锁成交过晚，放弃追消息");
         return;
      }
   }
   newsState.stage = 消息阶段_拆锁中;
   NewsHedgeSaveState(); // 先落盘再发平仓，防止成交瞬间重启后丢失组合成本。
   消息对冲状态 = reason + (NewsPositionExists(newsState.loserTicket) ? "，正在平亏损边" : "，亏损边已由服务器关闭");
   lastStatus = 消息对冲状态;
}

void NewsContinueUnhedge()
{
   if(newsState.stage != 消息阶段_拆锁中) return;
   bool loserWasAlive = NewsPositionExists(newsState.loserTicket);
   if(loserWasAlive)
   {
      if(!NewsCloseTicket(newsState.loserTicket))
      {
         消息对冲状态 = StringFormat("拆锁失败 ret=%d %s", manageTrade.ResultRetcode(), manageTrade.ResultComment());
         lastStatus = 消息对冲状态;
         return;
      }

      // 优先使用本次平仓成交的实际结果；若券商SL、重启恢复或成交历史暂不可读，
      // 再退回拆锁前已经持久化的浮亏估算，避免把组合保本线算得过低。
      ulong closeDeal = manageTrade.ResultDeal();
      if(closeDeal > 0 && !NewsRecordDeal(closeDeal, "主动拆锁")) NewsEnqueuePendingDeal(closeDeal);
      if(NewsPositionExists(newsState.loserTicket))
      {
         消息对冲状态 = "拆锁请求已发送但亏损边仍在，下一tick重试";
         lastStatus = 消息对冲状态;
         NewsHedgeSaveState();
         return;
      }
   }
   if(!NewsPositionExists(newsState.runnerTicket))
   {
      NewsCloseAll("盈利边丢失");
      return;
   }

   if(!newsState.loserActualKnown)
      newsState.realizedLoserLossMoney = MathMax(newsState.pendingLoserLossMoney, 0.0);
   if(newsState.unhedgeTime <= 0)
   {
      newsState.unhedgeTime = TimeCurrent();
      newsState.unhedgeTimeMs = GetTickCount64();
      newsState.runnerInitialVolume = NewsPositionVolume(newsState.runnerTicket);
      if(PositionSelectByTicket(newsState.runnerTicket))
      {
         double px = newsState.breakoutDirection > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         newsState.unhedgePrice = px;
         newsState.runnerHigh = px;
         newsState.runnerLow = px;
         newsState.runnerExtremePrice = px;
         newsState.lastExtremeTimeMs = newsState.unhedgeTimeMs;
      }
      newsState.maxCombinedMoney = -DBL_MAX;
      newsState.runnerPhase = 1;
      newsState.microPullbackPrice = 0.0;
      newsState.microPullbackActive = false;
      newsState.microPullbackConfirmed = false;
      newsState.microPullbackStartMsc = 0;
      newsState.microPullbackInvalid = false;
      newsState.microImpulseExtreme = newsState.runnerExtremePrice;
      newsMicroHead = 0;
      newsMicroCount = 0;
      newsState.firstPartialDone = false;
      newsState.secondPartialDone = false;
      newsState.runnerPartialStage = 0;
      NewsClearRunnerPartialRequest(true);
      newsState.runnerRealizedExitVolume = 0.0;
      newsState.runnerActualCostMoney = 0.0;
   }
   if(newsState.runnerStructureSL <= 0.0) newsState.runnerStructureSL = NewsDesiredRunnerStructureSL();
   newsState.estimatedRemainingExitCostMoney = NewsEstimateRemainingExitCost(NewsPositionVolume(newsState.runnerTicket));
   newsState.releaseEnabled = false;
   newsState.stage = 消息阶段_冲击持仓;
   NewsTryPrepareRunnerRisk();
   NewsHedgeSaveState();
   消息对冲状态 = StringFormat("已拆锁 | 亏损%s %.2f | R %s | 冲击持仓",
                                newsState.loserDealReady ? "实际" : "估算", newsState.realizedLoserLossMoney,
                                newsState.runnerRiskReady ? DoubleToString(newsState.initialGroupRiskMoney,2) : "等待成交和真实SL");
   lastStatus = 消息对冲状态;
}

double NewsRunnerCombinedMoney()
{
   double loserNet = newsState.loserActualKnown ? newsState.loserDealNetMoney : -newsState.pendingLoserLossMoney;
   return loserNet + newsState.realizedRunnerProfitMoney + NewsPositionMoney(newsState.runnerTicket) -
          newsState.estimatedRemainingExitCostMoney;
}

bool NewsFailureConfirmed(bool failure)
{
   ulong nowMs = GetTickCount64();
   if(!failure)
   {
      newsState.failureTicks = 0;
      newsState.failureStartMs = 0;
      return false;
   }
   if(newsState.failureTicks <= 0)
   {
      newsState.failureTicks = 1;
      newsState.failureStartMs = nowMs;
      return false;
   }
   newsState.failureTicks++;
   return (newsState.failureTicks >= MathMax(消息对冲假突破确认Tick数, 1) &&
           nowMs - newsState.failureStartMs >= (ulong)MathMax(消息对冲假突破确认毫秒, 0));
}

void NewsPushMicroTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0.0 || tick.ask <= tick.bid) return;
   ulong timeMsc = tick.time_msc > 0 ? (ulong)tick.time_msc : GetTickCount64();
   if(newsMicroCount > 0)
   {
      int last = (newsMicroHead-1+4096)%4096;
      if(newsMicroTicks[last].timeMsc == timeMsc &&
         MathAbs(newsMicroTicks[last].bid-tick.bid) < _Point && MathAbs(newsMicroTicks[last].ask-tick.ask) < _Point) return;
   }
   newsMicroTicks[newsMicroHead].timeMsc = timeMsc;
   newsMicroTicks[newsMicroHead].bid = tick.bid;
   newsMicroTicks[newsMicroHead].ask = tick.ask;
   newsMicroTicks[newsMicroHead].mid = (tick.bid+tick.ask)*0.5;
   newsMicroHead = (newsMicroHead+1)%4096;
   if(newsMicroCount < 4096) newsMicroCount++;
}

bool NewsMicroRecentExtreme(bool wantHigh, ulong lookbackMs, ulong excludeNewestMs, ulong startMsc, double &value)
{
   value = wantHigh ? -DBL_MAX : DBL_MAX;
   if(newsMicroCount <= 0) return false;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return false;
   ulong nowMsc = tick.time_msc > 0 ? (ulong)tick.time_msc : GetTickCount64();
   int found = 0;
   for(int n=0; n<newsMicroCount; n++)
   {
      int idx = (newsMicroHead-1-n+4096)%4096;
      ulong tm = newsMicroTicks[idx].timeMsc;
      if(nowMsc > tm && nowMsc-tm > lookbackMs) break;
      if(startMsc > 0 && tm < startMsc) break;
      if(nowMsc >= tm && nowMsc-tm < excludeNewestMs) continue;
      value = wantHigh ? MathMax(value, newsMicroTicks[idx].mid) : MathMin(value, newsMicroTicks[idx].mid);
      found++;
   }
   return found >= 2;
}

bool NewsMicroPullbackStructure(ENUM_POSITION_TYPE type, double atr, double &candidateSL)
{
   candidateSL = 0.0;
   if(newsState.microPullbackConfirmed || newsState.microPullbackInvalid || newsState.unhedgeTime <= 0) return false;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= bid) return false;
   double pullbackMin = MathMax(MathMax(newsState.normalSpreadPrice*3.0, atr*0.08), newsState.boxWidth*0.05);
   double swingBuffer = MathMax(MathMax(newsState.normalSpreadPrice*2.0, atr*0.08), NewsBrokerMinimumStopDistance());
   double maxRatio = ClampDouble(消息对冲微型回踩最大比例, 0.10, 0.90);
   if(type == POSITION_TYPE_BUY)
   {
      double impulseExtreme = newsState.microPullbackActive && newsState.microImpulseExtreme > 0.0 ?
                              newsState.microImpulseExtreme : newsState.runnerHigh;
      double wave = MathMax(impulseExtreme-newsState.unhedgePrice, pullbackMin);
      double retrace = impulseExtreme-bid;
      if(!newsState.microPullbackActive && retrace >= pullbackMin && retrace <= wave*maxRatio &&
         bid > newsState.rangeHigh-newsState.failureBuffer)
      {
         newsState.microPullbackActive = true;
         newsState.microPullbackPrice = bid;
         newsState.microPullbackStartMsc = NewsCurrentTickTimeMsc();
         newsState.microImpulseExtreme = newsState.runnerHigh;
      }
      if(!newsState.microPullbackActive) return false;
      newsState.microPullbackPrice = MathMin(newsState.microPullbackPrice, bid);
      if(retrace > wave*maxRatio)
      {
         newsState.microPullbackActive = false;
         newsState.microPullbackInvalid = true;
         PrintFormat("[消息微回踩] BUY首次回踩过深失效 retrace=%.5f max=%.5f impulse=%.5f",
                     retrace, wave*maxRatio, newsState.microImpulseExtreme);
         NewsHedgeSaveState();
         return false;
      }
      double microHigh = 0.0;
      if(NewsMicroRecentExtreme(true, 2000, 200, newsState.microPullbackStartMsc, microHigh) && bid > microHigh &&
         bid-newsState.microPullbackPrice >= pullbackMin*0.30)
      {
         candidateSL = NormalizePrice(newsState.microPullbackPrice-swingBuffer);
         newsState.microPullbackConfirmed = true;
         newsState.microPullbackActive = false;
         PrintFormat("[消息微回踩] BUY确认 low=%.5f recentHigh=%.5f SL=%.5f", newsState.microPullbackPrice, microHigh, candidateSL);
         return true;
      }
   }
   else
   {
      double impulseExtreme = newsState.microPullbackActive && newsState.microImpulseExtreme > 0.0 ?
                              newsState.microImpulseExtreme : newsState.runnerLow;
      double wave = MathMax(newsState.unhedgePrice-impulseExtreme, pullbackMin);
      double retrace = ask-impulseExtreme;
      if(!newsState.microPullbackActive && retrace >= pullbackMin && retrace <= wave*maxRatio &&
         ask < newsState.rangeLow+newsState.failureBuffer)
      {
         newsState.microPullbackActive = true;
         newsState.microPullbackPrice = ask;
         newsState.microPullbackStartMsc = NewsCurrentTickTimeMsc();
         newsState.microImpulseExtreme = newsState.runnerLow;
      }
      if(!newsState.microPullbackActive) return false;
      newsState.microPullbackPrice = MathMax(newsState.microPullbackPrice, ask);
      if(retrace > wave*maxRatio)
      {
         newsState.microPullbackActive = false;
         newsState.microPullbackInvalid = true;
         PrintFormat("[消息微回踩] SELL首次回踩过深失效 retrace=%.5f max=%.5f impulse=%.5f",
                     retrace, wave*maxRatio, newsState.microImpulseExtreme);
         NewsHedgeSaveState();
         return false;
      }
      double microLow = 0.0;
      if(NewsMicroRecentExtreme(false, 2000, 200, newsState.microPullbackStartMsc, microLow) && ask < microLow &&
         newsState.microPullbackPrice-ask >= pullbackMin*0.30)
      {
         candidateSL = NormalizePrice(newsState.microPullbackPrice+swingBuffer);
         newsState.microPullbackConfirmed = true;
         newsState.microPullbackActive = false;
         PrintFormat("[消息微回踩] SELL确认 high=%.5f recentLow=%.5f SL=%.5f", newsState.microPullbackPrice, microLow, candidateSL);
         return true;
      }
   }
   return false;
}

bool NewsModifyRunnerSL(ENUM_POSITION_TYPE type, double candidateSL)
{
   if(!PositionSelectByTicket(newsState.runnerTicket)) return false;
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   candidateSL = NormalizePrice(candidateSL);
   if(!MoreProtective(type, candidateSL, curSL)) return false;
   if(!SLTPValid(type, candidateSL, curTP)) return false;
   manageTrade.SetDeviationInPoints(MathMax(消息对冲允许滑点点数, 0));
   return manageTrade.PositionModify(newsState.runnerTicket, candidateSL, curTP);
}

bool NewsEnsureRunnerBoxProtection(ENUM_POSITION_TYPE type)
{
   if(!newsState.boxValid || newsState.runnerStructureSL <= 0.0) return false;
   if(!PositionSelectByTicket(newsState.runnerTicket)) return false;
   double curSL = PositionGetDouble(POSITION_SL);
   bool alreadyProtected = (type == POSITION_TYPE_BUY) ?
                           (curSL > 0.0 && curSL >= newsState.runnerStructureSL - _Point) :
                           (curSL > 0.0 && curSL <= newsState.runnerStructureSL + _Point);
   if(alreadyProtected)
   {
      newsState.runnerBoxProtectionApplied = true;
      ulong nowMs = GetTickCount64();
      if(!newsRunnerProtectionLastLoggedState || newsRunnerProtectionLastLogMs == 0 ||
         nowMs-newsRunnerProtectionLastLogMs >= 1000)
      {
         PrintFormat("[消息箱体] 剩余单结构SL已真实生效 ticket=%I64u actualSL=%.5f target=%.5f",
                     newsState.runnerTicket, curSL, newsState.runnerStructureSL);
         newsRunnerProtectionLastLogMs = nowMs;
         newsRunnerProtectionLastLoggedState = true;
      }
      return true;
   }
   bool sent = NewsModifyRunnerSL(type, newsState.runnerStructureSL);
   if(!PositionSelectByTicket(newsState.runnerTicket)) return false;
   curSL = PositionGetDouble(POSITION_SL);
   newsState.runnerBoxProtectionApplied = (type == POSITION_TYPE_BUY) ?
                                          (curSL > 0.0 && curSL >= newsState.runnerStructureSL - _Point) :
                                          (curSL > 0.0 && curSL <= newsState.runnerStructureSL + _Point);
   ulong nowMs = GetTickCount64();
   bool stateChanged = (newsState.runnerBoxProtectionApplied != newsRunnerProtectionLastLoggedState);
   bool timeDue = (newsRunnerProtectionLastLogMs == 0 || nowMs-newsRunnerProtectionLastLogMs >= 1000);
   if(newsState.runnerBoxProtectionApplied)
   {
      PrintFormat("[消息箱体] 剩余单结构SL已设置 ticket=%I64u SL=%.5f", newsState.runnerTicket, curSL);
      newsRunnerProtectionLastLogMs = nowMs;
      newsRunnerProtectionLastLoggedState = true;
   }
   else if(stateChanged || timeDue)
   {
      PrintRateLimited(StringFormat("news_runner_sl_retry:%I64u:%d", newsState.runnerTicket, manageTrade.ResultRetcode()), 10,
                       StringFormat("[消息箱体] 剩余单结构SL待重试 ticket=%I64u target=%.5f sent=%d ret=%d %s",
                                    newsState.runnerTicket, newsState.runnerStructureSL, sent,
                                    manageTrade.ResultRetcode(), manageTrade.ResultComment()));
      newsRunnerProtectionLastLogMs = nowMs;
      newsRunnerProtectionLastLoggedState = false;
   }
   return newsState.runnerBoxProtectionApplied;
}

bool NewsTryPrepareRunnerRisk()
{
   if(newsState.runnerRiskReady) return true;
   if(!newsState.loserDealReady || NewsPositionExists(newsState.loserTicket) ||
      !NewsPositionExists(newsState.runnerTicket)) return false;
   if(newsState.runnerStructureSL <= 0.0) newsState.runnerStructureSL = NewsDesiredRunnerStructureSL();
   if(newsState.runnerStructureSL <= 0.0) return false;
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   if(!NewsEnsureRunnerBoxProtection(type) || !PositionSelectByTicket(newsState.runnerTicket)) return false;
   double actualSL = PositionGetDouble(POSITION_SL);
   bool structureProtected = type == POSITION_TYPE_BUY ?
                             (actualSL > 0.0 && actualSL >= newsState.runnerStructureSL-_Point) :
                             (actualSL > 0.0 && actualSL <= newsState.runnerStructureSL+_Point);
   if(!structureProtected) return false;
   newsState.actualRunnerRiskSL = actualSL;
   newsState.initialGroupRiskMoney = NewsEstimateInitialGroupRiskMoney();
   newsState.runnerRiskReady = (newsState.initialGroupRiskMoney > 0.0);
   if(newsState.runnerRiskReady)
   {
      PrintFormat("[消息短时] runner风险Ready actualSL=%.5f R=%.2f loserDealReady=%d",
                  newsState.actualRunnerRiskSL, newsState.initialGroupRiskMoney, newsState.loserDealReady);
      NewsHedgeSaveState();
   }
   return newsState.runnerRiskReady;
}

bool NewsPullbackStructureSL(ENUM_POSITION_TYPE type, double atr, double &candidate, datetime &barTime)
{
   candidate = 0.0;
   barTime = 0;
   if(newsState.unhedgeTime <= 0 || !newsState.boxValid) return false;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, PERIOD_M1, 1, 8, rates);
   if(copied < 4) return false;
   double buffer = MathMax(MathMax(newsState.normalSpreadPrice * 2.0, atr * 0.10), NewsBrokerMinimumStopDistance());
   for(int i=1; i<copied-1; i++)
   {
      if(rates[i].time < newsState.unhedgeTime + 60) continue;
      if(type == POSITION_TYPE_BUY)
      {
         bool swing = rates[i].low <= rates[i-1].low && rates[i].low <= rates[i+1].low;
         bool heldBox = rates[i].low >= newsState.rangeHigh - newsState.failureBuffer;
         bool resumed = rates[0].close > rates[i].high;
         if(swing && heldBox && resumed)
         {
            candidate = NormalizePrice(rates[i].low - buffer);
            barTime = rates[i].time;
            return true;
         }
      }
      else
      {
         bool swing = rates[i].high >= rates[i-1].high && rates[i].high >= rates[i+1].high;
         bool heldBox = rates[i].high <= newsState.rangeLow + newsState.failureBuffer;
         bool resumed = rates[0].close < rates[i].low;
         if(swing && heldBox && resumed)
         {
            candidate = NormalizePrice(rates[i].high + buffer);
            barTime = rates[i].time;
            return true;
         }
      }
   }
   return false;
}

bool NewsExecuteRunnerPartial(double ratio, double combinedMoney, int stage)
{
   if(newsState.runnerPartialPending) return false;
   double volume = 0.0;
   if(!NewsSelectRunnerPosition(volume)) return false;
   // 与全平使用同一身份闸门，防止损坏的恢复状态把普通仓当作消息尾仓分批。
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(minVol <= 0.0) minVol = 0.01;
   if(newsState.runnerInitialVolume <= 0.0) newsState.runnerInitialVolume = volume;
   if(!NewsRefreshRunnerDealTotals(true))
   {
      PrintRateLimited("news_runner_partial_history_wait", 10,
                       "[消息成交] runner历史暂不可读，拒绝发送分批请求");
      return false;
   }
   if(newsState.runnerPartialTargetStage != stage)
   {
      double stageCloseVolume = NormalizeVolumeDown(newsState.runnerInitialVolume * ClampDouble(ratio, 0.05, 0.90));
      if(stageCloseVolume >= volume) stageCloseVolume = NormalizeVolumeDown(volume-minVol);
      newsState.runnerPartialTargetStage = stage;
      newsState.runnerPartialStageStartVolume = volume;
      newsState.runnerPartialTargetVolume = NormalizeVolumeDown(MathMax(volume-stageCloseVolume, 0.0));
      newsState.runnerPartialStageStartExitVolume = newsState.runnerRealizedExitVolume;
      newsState.runnerPartialFilledVolume = 0.0;
      NewsHedgeSaveState();
   }
   if(newsState.runnerPartialRequestTime > 0 &&
      TimeCurrent()-newsState.runnerPartialRequestTime < NEWS_PARTIAL_TIMEOUT_SECONDS) return false;
   double closeVolume = NormalizeVolumeDown(volume-newsState.runnerPartialTargetVolume);
   double remain = NormalizeVolumeDown(volume-closeVolume);
   if(closeVolume < minVol || remain < minVol)
   {
      PrintRateLimited(StringFormat("news_runner_partial_min:%d", stage), 10,
                       StringFormat("[消息短时] 第%d段当前差额不满足最小手数，不推进阶段 current=%.2f targetRemain=%.2f close=%.2f min=%.2f",
                                    stage, volume, newsState.runnerPartialTargetVolume, closeVolume, minVol));
      return false;
   }

   newsState.runnerPartialPending = true;
   newsState.runnerPartialRequestedVolume = closeVolume;
   newsState.runnerPartialRequestTime = TimeCurrent();
   NewsHedgeSaveState(); // 先锁定请求，防止同步Deal事件或重启造成同阶段重复发送。
   manageTrade.SetDeviationInPoints(MathMax(消息对冲允许滑点点数, 0));
   bool sent = manageTrade.PositionClosePartial(newsState.runnerTicket, closeVolume);
   uint retcode = manageTrade.ResultRetcode();
   if(!sent || !IsTradeRetcodeAccepted(retcode))
   {
      PrintFormat("[消息成交] 第%d段请求拒绝 volume=%.2f retcode=%u comment=%s",
                  stage, closeVolume, retcode, manageTrade.ResultComment());
      NewsClearRunnerPartialRequest(false);
      NewsHedgeSaveState();
      return false;
   }
   ulong closeDeal = manageTrade.ResultDeal();
   if(closeDeal > 0 && !NewsRecordDeal(closeDeal, "盈利边分批")) NewsEnqueuePendingDeal(closeDeal);
   NewsHedgeSaveState();
   消息对冲状态 = StringFormat("消息第%d段请求 %.2f手已受理，等待真实Deal与剩余仓量确认，组合%.2f",
                                stage, closeVolume, combinedMoney);
   lastStatus = 消息对冲状态;
   return true;
}

bool NewsQuoteValid()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick)) return false;
   return (tick.bid > 0.0 && tick.ask > tick.bid);
}

int NewsRunnerElapsedSeconds()
{
   if(newsState.unhedgeTime <= 0) return 0;
   return (int)MathMax((long)(TimeCurrent()-newsState.unhedgeTime), 0);
}

int NewsExtremeAgeSeconds()
{
   if(newsState.lastExtremeTimeMs <= 0) return 0;
   ulong nowMs = GetTickCount64();
   return nowMs >= newsState.lastExtremeTimeMs ? (int)((nowMs-newsState.lastExtremeTimeMs)/1000) : 0;
}

double NewsPhaseDrawdownRatio(int phase)
{
   if(phase <= 1) return ClampDouble(消息对冲第一波最大回撤比例, 0.10, 0.90);
   if(phase == 2) return ClampDouble(消息对冲延续阶段最大回撤比例, 0.05, 0.80);
   return ClampDouble(消息对冲后期最大回撤比例, 0.05, 0.70);
}

void ManageNewsRunner(double atr)
{
   NewsReconcileRunnerPartial(false);
   double volume = 0.0;
   if(!NewsSelectRunnerPosition(volume))
   {
      if(newsState.runnerPartialTargetStage > 0)
      {
         消息对冲状态 = "runner仓位已消失，等待真实退出Deal确认";
         lastStatus = 消息对冲状态;
         return;
      }
      PrintFormat("[消息短时] 剩余边结束 已实现=%.2f 亏损边=%.2f 实际成本=%.2f",
                  newsState.realizedRunnerProfitMoney, newsState.realizedLoserLossMoney, newsState.actualCostMoney);
      NewsRequestGroupExit("消息仓已结束");
      return;
   }
   if(!NewsQuoteValid())
   {
      消息对冲状态 = "消息持仓等待有效报价";
      lastStatus = 消息对冲状态;
      return;
   }

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   if(newsState.runnerInitialVolume <= 0.0) newsState.runnerInitialVolume = volume;
   double scaleVolume = MathMax(newsState.runnerInitialVolume, 0.01);
   double combined = NewsRunnerCombinedMoney();
   if(newsState.maxCombinedMoney <= -DBL_MAX / 2.0) newsState.maxCombinedMoney = combined;
   newsState.maxCombinedMoney = MathMax(newsState.maxCombinedMoney, combined);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double mid = (bid + ask) * 0.5;
   double px = type == POSITION_TYPE_BUY ? bid : ask;
   ulong nowMs = GetTickCount64();
   bool newExtreme = false;
   double meaningfulExtremeStep = MathMax(MathMax(newsState.normalSpreadPrice*0.50,
                                                   newsState.atrAtPair*0.02), _Point*5.0);
   if(newsState.runnerHigh <= 0.0) newsState.runnerHigh = px;
   if(newsState.runnerLow <= 0.0) newsState.runnerLow = px;
   if(newsState.runnerExtremePrice <= 0.0) newsState.runnerExtremePrice = px;
   if(type == POSITION_TYPE_BUY)
   {
      newsState.runnerHigh = MathMax(newsState.runnerHigh, px);
      if(px >= newsState.runnerExtremePrice+meaningfulExtremeStep)
      {
         newsState.runnerExtremePrice = px;
         newExtreme = true;
      }
   }
   else
   {
      newsState.runnerLow = MathMin(newsState.runnerLow, px);
      if(px <= newsState.runnerExtremePrice-meaningfulExtremeStep)
      {
         newsState.runnerExtremePrice = px;
         newExtreme = true;
      }
   }
   if(newExtreme || newsState.lastExtremeTimeMs <= 0) newsState.lastExtremeTimeMs = nowMs;
   if(newExtreme && !newsState.microPullbackActive && !newsState.microPullbackConfirmed && !newsState.microPullbackInvalid)
      newsState.microImpulseExtreme = newsState.runnerExtremePrice;

   int elapsed = NewsRunnerElapsedSeconds();
   int phase = elapsed <= MathMax(消息对冲第一波阶段秒数, 1) ? 1 :
               (elapsed <= MathMax(消息对冲延续阶段秒数, 消息对冲第一波阶段秒数+1) ? 2 : 3);
   if(newsState.runnerPhase != phase)
   {
      newsState.runnerPhase = phase;
      newsState.stage = phase == 1 ? 消息阶段_冲击持仓 : 消息阶段_延续持仓;
      NewsHedgeSaveState();
   }
   if(elapsed >= MathMax(消息对冲组合最长持仓秒数, 1))
   {
      NewsRequestGroupExit("消息最长持仓到期");
      return;
   }

   if(newsState.boxValid)
   {
      NewsTryPrepareRunnerRisk();
      double deepDistance = newsState.boxWidth * ClampDouble(消息对冲假突破回区比例, 0.05, 0.95);
      bool boundaryFailure = newsState.breakoutDirection > 0 ?
                             (mid <= newsState.rangeHigh - newsState.failureBuffer) :
                             (mid >= newsState.rangeLow + newsState.failureBuffer);
      bool deepFailure = newsState.breakoutDirection > 0 ?
                         (mid <= newsState.rangeHigh - deepDistance) :
                         (mid >= newsState.rangeLow + deepDistance);
      if(deepFailure)
      {
         PrintFormat("[消息箱体] 深度假突破退出 mid=%.5f box=%.5f-%.5f", mid, newsState.rangeLow, newsState.rangeHigh);
         NewsCloseAll("深度进入箱体退出");
         return;
      }
      if(NewsFailureConfirmed(boundaryFailure))
      {
         PrintFormat("[消息箱体] 边界失效退出 mid=%.5f structureSL=%.5f", mid, newsState.runnerStructureSL);
         NewsCloseAll("箱体突破边界失效");
         return;
      }
   }
   else
   {
      double emergency = newsState.hardStopDistance > 0.0 ? newsState.hardStopDistance :
                         ClampDouble(MathMax(atr, newsState.atrAtPair)*MathMax(消息对冲单边止损ATR倍数, 0.10),
                                     MathMax(消息对冲单边止损最小价格, 0.10),
                                     MathMax(消息对冲单边止损最大价格, 消息对冲单边止损最小价格));
      NewsApplyEmergencySL(newsState.runnerTicket, type, emergency);
   }

   double pairLossLimit = NewsMoneyScale(消息对冲每001手组合最大亏损金额, scaleVolume);
   if(pairLossLimit > 0.0 && combined <= -pairLossLimit)
   {
      NewsCloseAll("组合最大亏损保护");
      return;
   }

   double riskMoney = newsState.runnerRiskReady ? newsState.initialGroupRiskMoney : 0.0;
   double combinedR = newsState.runnerRiskReady && riskMoney > 0.0 ? combined/riskMoney : 0.0;
   double allowedDrawdown = NewsPhaseDrawdownRatio(phase);
   if(消息对冲启用组合回撤退出)
   {
      double ddStart = newsState.runnerRiskReady ? riskMoney*0.50 :
                       NewsMoneyScale(消息对冲回撤启动每001手组合盈利, scaleVolume);
      double ddLimit = newsState.runnerRiskReady ? allowedDrawdown :
                       ClampDouble(消息对冲最大组合回撤比例, 0.10, 0.90);
      if(newsState.maxCombinedMoney >= ddStart && newsState.maxCombinedMoney > 0.0)
      {
         double ddRatio = (newsState.maxCombinedMoney - combined) / newsState.maxCombinedMoney;
         if(ddRatio >= ddLimit)
         {
            NewsRequestGroupExit(StringFormat("消息%s回撤%.0f%%", newsState.runnerRiskReady ? "阶段R" : "实际金额峰值", ddRatio*100.0));
            return;
         }
      }
   }

   if(消息对冲启用两段分批 && newsState.runnerRiskReady)
   {
      double trigger1 = MathMax(riskMoney*MathMax(消息对冲第1段盈利R, 0.0),
                                NewsMoneyScale(消息对冲第1段每001手组合盈利, scaleVolume));
      double trigger2 = MathMax(riskMoney*MathMax(消息对冲第2段盈利R, 0.0),
                                NewsMoneyScale(消息对冲第2段每001手组合盈利, scaleVolume));
      if(!newsState.firstPartialDone && elapsed >= MathMax(消息对冲第一段最小间隔秒, 0) && combined >= trigger1)
      {
         if(NewsExecuteRunnerPartial(消息对冲第1段平仓比例, combined, 1)) return;
      }
      if(newsState.firstPartialDone && !newsState.secondPartialDone &&
         elapsed >= MathMax(消息对冲第二段最小间隔秒, 0) && combined >= trigger2)
      {
         if(NewsExecuteRunnerPartial(消息对冲第2段平仓初始手数比例, combined, 2)) return;
      }
   }

   double microSL = 0.0;
   if(newsState.boxValid && NewsMicroPullbackStructure(type, atr > 0.0 ? atr : newsState.atrAtPair, microSL))
   {
      if(NewsModifyRunnerSL(type, microSL))
      {
         newsState.runnerStructureSL = microSL;
         NewsHedgeSaveState();
      }
   }

   // Tick结构是主方案；60秒后才允许使用已收M1摆点作为降级保护。
   double pullbackSL = 0.0;
   datetime pullbackTime = 0;
   if(elapsed >= 60 && NewsPullbackStructureSL(type, atr > 0.0 ? atr : newsState.atrAtPair, pullbackSL, pullbackTime) &&
      pullbackTime != newsState.lastStructureBarTime)
   {
      if(NewsModifyRunnerSL(type, pullbackSL))
      {
         newsState.lastStructureBarTime = pullbackTime;
         PrintFormat("[消息箱体] 有效回踩结构SL time=%s SL=%.5f", TimeToString(pullbackTime, TIME_DATE|TIME_MINUTES), pullbackSL);
         NewsHedgeSaveState();
      }
   }

   // 组合保本：盈利边必须先覆盖已实现亏损、预估成本和锁定金额，不能按单边开仓价假保本。
   double beStart = NewsMoneyScale(消息对冲每001手组合保本启动金额, scaleVolume);
   if(combined >= beStart)
   {
      double loserNet = newsState.loserActualKnown ? newsState.loserDealNetMoney : -newsState.pendingLoserLossMoney;
      double lockMoney = NewsMoneyScale(消息对冲每001手组合锁定金额, scaleVolume);
      double targetMoney = lockMoney-loserNet-newsState.realizedRunnerProfitMoney+
                           newsState.estimatedRemainingExitCostMoney;
      double lockDistance = NewsMoneyToPriceDistance(MathMax(targetMoney, 0.0), volume);
      double beSL = type == POSITION_TYPE_BUY ? openPrice + lockDistance : openPrice - lockDistance;
      NewsModifyRunnerSL(type, beSL);
   }

   double pullbackMin = MathMax(MathMax(newsState.normalSpreadPrice*3.0,
                                        MathMax(atr, newsState.atrAtPair)*0.08), newsState.boxWidth*0.05);
   double priceRetrace = type == POSITION_TYPE_BUY ? newsState.runnerHigh-bid : ask-newsState.runnerLow;
   int extremeAge = NewsExtremeAgeSeconds();
   if(newsState.runnerRiskReady && phase == 1 && elapsed >= 3 &&
      extremeAge >= MathMax(消息对冲第一波无延续退出秒, 1) && combinedR < 0.50)
   {
      NewsRequestGroupExit("第一波无延续且不足0.5R");
      return;
   }
   if(phase >= 2 && extremeAge >= MathMax(消息对冲后续无延续退出秒, 1) && priceRetrace >= pullbackMin)
   {
      NewsRequestGroupExit("后续无新极值且已明显回撤");
      return;
   }

   NewsHedgeSaveState(false);
   string microState = newsState.microPullbackConfirmed ? "已确认" :
                       (newsState.microPullbackInvalid ? "已失效" : (newsState.microPullbackActive ? "观察" : "等待"));
   string riskState = newsState.runnerRiskReady ? DoubleToString(combinedR,2)+"R" : "R等待";
   消息对冲状态 = StringFormat("%s%s | %ds | %s | 峰值%.2f | 回撤限%.0f%% | 微回踩%s",
                                phase == 1 ? "冲击" : (phase == 2 ? "延续" : "后期"),
                                type == POSITION_TYPE_BUY ? "BUY" : "SELL", elapsed, riskState,
                                newsState.maxCombinedMoney, allowedDrawdown*100.0,
                                microState);
   lastStatus = 消息对冲状态;
}

void ManageNewsHedge(double atr)
{
   if(!当前模板使用消息对冲() && !NewsHedgeGroupActive()) return;
   NewsHedgeTemplateScope templateScope;
   if(!IsHedgingAccount())
   {
      消息对冲状态 = "非对冲账户禁用: 无法同时持有多空";
      lastStatus = 消息对冲状态;
      return;
   }
   NewsReconcileStopDeployment();
   NewsTryPendingDeals();

   if(newsState.stage == 消息阶段_组合退出)
   {
      if(NewsQuoteValid()) NewsCloseAll(消息对冲退出原因 == "" ? "组合退出重试" : 消息对冲退出原因);
      else 消息对冲状态 = "组合退出等待有效报价";
      lastStatus = 消息对冲状态;
      return;
   }

   if(newsState.stage == 消息阶段_拆锁中)
   {
      NewsContinueUnhedge();
      return;
   }
   if(newsState.stage == 消息阶段_冲击持仓 || newsState.stage == 消息阶段_延续持仓)
   {
      ManageNewsRunner(atr);
      return;
   }
   if(newsState.stopStage==消息双Stop_创建BUY待确认 ||
      newsState.stopStage==消息双Stop_创建SELL待确认 ||
      newsState.stopStage==消息双Stop_已武装 ||
      newsState.stopStage==消息双Stop_OCO撤单中 ||
      newsState.stopStage==消息双Stop_全部撤单中 ||
      newsState.stopStage==消息双Stop_故障) return;
   if(newsState.stage==消息阶段_箱体冻结 && newsState.stopToken==0 &&
      newsState.buyTicket==0 && newsState.sellTicket==0)
   {
      消息对冲状态="箱体已冻结：等待用户明确部署双Stop";
      lastStatus=消息对冲状态;
      return;
   }

   ulong buyTicket = 0, sellTicket = 0;
   int buyCount = 0, sellCount = 0;
   bool hasPair = NewsFindPairCandidates(buyTicket, sellTicket, buyCount, sellCount);

   if(newsState.stage == 消息阶段_待命)
   {
      if(hasPair)
      {
         if(上次消息箱体尝试时间 == TimeCurrent()) return;
         上次消息箱体尝试时间 = TimeCurrent();
         if(!NewsPairValid(buyTicket, sellTicket))
         {
            // 待命阶段的异常组合只能拒绝和告警，绝不能自动平仓。
            // 自动全平曾导致仅切换消息模板时误平旧仓；即使用户保存了旧参数，
            // 也必须以这个安全边界为准。
            string warning = "配对拒绝（不自动平仓）: 手数或开仓时间不匹配";
            bool changed = (消息对冲状态 != warning);
            消息对冲状态 = warning;
            lastStatus = warning;
            if(changed)
               PrintFormat("[消息安全] %s buy=%I64u sell=%I64u", warning, buyTicket, sellTicket);
         }
         else if(!NewsEstablishPair(buyTicket, sellTicket, atr))
         {
            string reason = 消息对冲箱体拒绝原因 == "" ? "箱体或报价无效" : 消息对冲箱体拒绝原因;
            double unit = atr > 0.0 ? atr : MathMax(GetRecentM1RangeAverage(14), 1.0);
            double hardDist = ClampDouble(unit * MathMax(消息对冲单边止损ATR倍数, 0.10),
                                           MathMax(消息对冲单边止损最小价格, 0.10),
                                           MathMax(消息对冲单边止损最大价格, 消息对冲单边止损最小价格));
            NewsApplyEmergencySL(buyTicket, POSITION_TYPE_BUY, hardDist);
            NewsApplyEmergencySL(sellTicket, POSITION_TYPE_SELL, hardDist);
            string warning = "箱体无效，禁止拆锁且不自动平仓: " + reason;
            bool changed = (消息对冲状态 != warning);
            消息对冲状态 = warning;
            lastStatus = warning;
            if(changed)
               PrintFormat("[消息安全] %s buy=%I64u sell=%I64u", warning, buyTicket, sellTicket);
         }
         return;
      }

      int total = buyCount + sellCount;
      if(total == 0)
      {
         newsState.waitTicket = 0;
         newsState.waitStartTime = 0;
         消息对冲状态 = "待命: 请下等手数BUY+SELL";
         return;
      }
      if(total > 1)
      {
         // 多于一组或同向多单属于待命期异常，只告警并保留仓位处置权给用户。
         string warning = StringFormat("拒绝配对（不自动平仓）: 多%d/空%d，请只保留一组", buyCount, sellCount);
         bool changed = (消息对冲状态 != warning);
         消息对冲状态 = warning;
         lastStatus = warning;
         if(changed) PrintFormat("[消息安全] %s", warning);
         return;
      }

      ulong singleTicket = buyCount == 1 ? buyTicket : sellTicket;
      if(newsState.waitTicket != singleTicket)
      {
         newsState.waitTicket = singleTicket;
         newsState.waitStartTime = TimeCurrent();
      }
      if(PositionSelectByTicket(singleTicket))
      {
         ENUM_POSITION_TYPE singleType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double unit = atr > 0.0 ? atr : MathMax(GetRecentM1RangeAverage(14), 1.0);
         double hardDist = ClampDouble(unit * MathMax(消息对冲单边止损ATR倍数, 0.10),
                                       MathMax(消息对冲单边止损最小价格, 0.10),
                                       MathMax(消息对冲单边止损最大价格, 消息对冲单边止损最小价格));
         NewsApplyEmergencySL(singleTicket, singleType, hardDist);
      }
      int waited = (int)(TimeCurrent() - newsState.waitStartTime);
      if(消息对冲配对失败自动平仓 && waited >= MathMax(消息对冲配对等待秒, 1))
      {
         if(NewsCloseTicket(singleTicket))
         {
            newsState.waitTicket = 0;
            newsState.waitStartTime = 0;
            消息对冲状态 = "配对超时，孤立仓已平";
            lastStatus = 消息对冲状态;
         }
         else
            消息对冲状态 = "配对超时，孤立仓平仓重试";
         return;
      }
      消息对冲状态 = StringFormat("等待另一边 %d/%d秒", waited, MathMax(消息对冲配对等待秒, 1));
      return;
   }

   if((newsState.stage == 消息阶段_箱体冻结 || newsState.stage == 消息阶段_释放窗口) &&
      (!newsState.boxValid || !newsState.boxFrozenByUser))
   {
      NewsRequestGroupExit("冻结箱体状态无效，保护退出");
      return;
   }

   // 开放前任何一侧消失都不能被解释为消息方向；开放后也必须通过位置和最晚拆锁过滤。
   bool buyAlive = NewsPositionExists(newsState.buyTicket);
   bool sellAlive = NewsPositionExists(newsState.sellTicket);
   if(!buyAlive || !sellAlive)
   {
      if(buyAlive != sellAlive)
      {
         double midNow = (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK)) * 0.5;
         ulong remaining = buyAlive ? newsState.buyTicket : newsState.sellTicket;
         int direction = buyAlive ? 1 : -1;
         if(newsState.stage != 消息阶段_释放窗口 || !newsState.releaseEnabled)
         {
            NewsRequestGroupExit("开放拆锁前一侧消失，关闭剩余边");
            return;
         }
         bool remainingWithMove = (buyAlive && midNow >= newsState.rangeHigh - newsState.failureBuffer) ||
                                  (sellAlive && midNow <= newsState.rangeLow + newsState.failureBuffer);
         if(!remainingWithMove)
         {
            NewsRequestGroupExit("箱体内一侧异常消失，关闭剩余边");
            return;
         }
         string lateReason = "";
         if(NewsUnlockTooLate(direction, midNow, lateReason))
         {
            NewsRequestGroupExit("服务器拆锁过晚，放弃顶部追单: " + lateReason);
            return;
         }
         double vol = NewsPositionVolume(remaining);
         if(!newsState.loserDealReady)
            newsState.pendingLoserLossMoney = MathMax(newsState.pendingLoserLossMoney,
                                                      NewsEstimateDisasterLoserLoss(direction, vol));
         NewsBeginUnhedge(direction, buyAlive ? "SELL已由服务器灾难SL关闭" : "BUY已由服务器灾难SL关闭");
         NewsContinueUnhedge();
      }
      else
         NewsRequestGroupExit("消息对冲两侧均已结束");
      return;
   }

   if(!NewsPairValid(newsState.buyTicket, newsState.sellTicket))
   {
      NewsCloseAll("配对后手数失衡保护");
      return;
   }

   double pairVol = MathMax(NewsPositionVolume(newsState.buyTicket), NewsPositionVolume(newsState.sellTicket));
   double pairMoney = NewsPositionMoney(newsState.buyTicket) + NewsPositionMoney(newsState.sellTicket) -
                      newsState.estimatedRemainingExitCostMoney;
   double pairLossLimit = NewsMoneyScale(消息对冲每001手组合最大亏损金额, pairVol);
   if(pairLossLimit > 0.0 && pairMoney <= -pairLossLimit)
   {
      NewsCloseAll("对冲阶段组合最大亏损");
      return;
   }

   if(newsState.stage == 消息阶段_配对安全)
   {
      datetime now = TimeCurrent();
      if(上次消息箱体尝试时间 <= 0 || now-上次消息箱体尝试时间 >= 5)
      {
         上次消息箱体尝试时间 = now;
         NewsRefreshCandidateBox(false);
      }
      NewsApplyEmergencySL(newsState.buyTicket, POSITION_TYPE_BUY, newsState.hardStopDistance);
      NewsApplyEmergencySL(newsState.sellTicket, POSITION_TYPE_SELL, newsState.hardStopDistance);
      消息对冲状态 = newsState.boxValid ?
         StringFormat("配对安全 | 候选箱体%.2f-%.2f | 未开放禁止拆锁", newsState.rangeLow, newsState.rangeHigh) :
         "配对安全 | 候选箱体无效: " + 消息对冲箱体拒绝原因;
      lastStatus = 消息对冲状态;
      NewsHedgeSaveState(false);
      return;
   }

   NewsMaintainPairStructureSL();
   if(newsState.stage == 消息阶段_箱体冻结)
   {
      消息对冲状态 = StringFormat("箱体已冻结 %.2f-%.2f | 灾难缓冲%.2f | 等待开放",
                                   newsState.rangeLow, newsState.rangeHigh, newsState.disasterBuffer);
      lastStatus = 消息对冲状态;
      return;
   }

   if(newsState.stage != 消息阶段_释放窗口 || !newsState.releaseEnabled)
   {
      NewsRequestGroupExit("未知消息阶段，保护退出");
      return;
   }

   int releaseElapsed = newsState.releaseTime > 0 ? (int)MathMax((long)(TimeCurrent()-newsState.releaseTime), 0) : 0;
   if((newsState.releaseExpireTime > 0 && TimeCurrent() >= newsState.releaseExpireTime) ||
      releaseElapsed > MathMax(消息对冲最晚拆锁秒数, 1))
   {
      NewsRequestGroupExit("开放窗口结束仍未拆锁");
      return;
   }

   double spreadPrice = CurrentSpreadPrice();
   double spreadLimit = NewsDynamicSpreadLimit();
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double mid = (bid + ask) * 0.5;
   double upLine = newsState.rangeHigh + newsState.breakoutBuffer;
   double downLine = newsState.rangeLow - newsState.breakoutBuffer;
   bool up = (mid >= upLine);
   bool down = (mid <= downLine);
   int direction = up ? 1 : (down ? -1 : 0);
   bool confirmed = NewsBreakoutConfirmed(direction);
   if(direction == 0)
   {
      newsState.pendingBreakoutDirection = 0;
      newsState.pendingBreakoutStartMs = 0;
   }
   bool spreadTooHigh = (spreadLimit > 0.0 && spreadPrice > spreadLimit);
   if(confirmed)
   {
      if(spreadTooHigh)
      {
         ulong nowMs = GetTickCount64();
         if(newsState.pendingBreakoutDirection != direction)
         {
            newsState.pendingBreakoutDirection = direction;
            newsState.pendingBreakoutStartMs = nowMs;
         }
         ulong waitedMs = nowMs - newsState.pendingBreakoutStartMs;
         if(waitedMs < (ulong)MathMax(消息对冲最大拆锁等待毫秒, 0))
         {
            消息对冲状态 = StringFormat("%s突破已确认 | 点差%.2f>动态限%.2f | 等待 %I64u/%dms",
                                         direction > 0 ? "向上" : "向下", spreadPrice, spreadLimit, waitedMs,
                                         MathMax(消息对冲最大拆锁等待毫秒, 0));
            lastStatus = 消息对冲状态;
            return;
         }
         if(消息对冲高点差超时处理 == 高点差超时处理_整组退出)
         {
            PrintFormat("[消息箱体] 高点差等待超时，整组退出 dir=%d spread=%.5f limit=%.5f waited=%I64u",
                        direction, spreadPrice, spreadLimit, waitedMs);
            NewsRequestGroupExit("高点差等待超时，整组退出");
            return;
         }
         string highSpreadLateReason = "";
         if(NewsUnlockTooLate(direction, mid, highSpreadLateReason))
         {
            NewsRequestGroupExit("高点差超时且拆锁不再安全: "+highSpreadLateReason);
            return;
         }
         PrintFormat("[消息箱体] 高点差超时但安全条件仍满足，允许强制拆锁 dir=%d spread=%.5f limit=%.5f",
                     direction, spreadPrice, spreadLimit);
      }
      NewsBeginUnhedge(direction, direction > 0 ? "向上突破确认" : "向下突破确认");
      NewsContinueUnhedge();
      return;
   }

   ulong elapsedMs = newsState.candidateStartMs > 0 ? GetTickCount64() - newsState.candidateStartMs : 0;
   if(direction != 0)
      消息对冲状态 = StringFormat("%s突破候选 | 越界%.2f | tick%d/%d | %I64ums/%dms%s",
                                   direction > 0 ? "向上" : "向下",
                                   direction > 0 ? mid-upLine : downLine-mid,
                                   newsState.candidateTicks, MathMax(消息对冲突破确认Tick数, 1), elapsedMs,
                                   MathMax(消息对冲突破确认毫秒, 0), spreadTooHigh ? " | 点差超过动态限制" : "");
   else
      消息对冲状态 = StringFormat("释放窗口 %d/%d秒 | 箱体%.2f-%.2f | 等待消息突破",
                                   releaseElapsed, MathMax(消息对冲开放后有效秒数, 1),
                                   newsState.rangeLow, newsState.rangeHigh);
   lastStatus = 消息对冲状态;
}

void NewsManageClock()
{
   if(!NewsHedgeGroupActive()) return;
   NewsHedgeTemplateScope templateScope;
   bool quoteOk = NewsQuoteValid();
   if(newsState.stage == 消息阶段_组合退出)
   {
      if(quoteOk) NewsCloseAll(消息对冲退出原因 == "" ? "组合退出定时重试" : 消息对冲退出原因);
      else
      {
         消息对冲状态 = "组合退出等待有效报价";
         lastStatus = 消息对冲状态;
      }
      return;
   }

   if(newsState.stage == 消息阶段_释放窗口 || newsState.stage == 消息阶段_拆锁中)
   {
      int elapsed = newsState.releaseTime > 0 ? (int)MathMax((long)(TimeCurrent()-newsState.releaseTime), 0) : 0;
      bool expired = (newsState.releaseExpireTime > 0 && TimeCurrent() >= newsState.releaseExpireTime);
      bool tooLate = (elapsed > MathMax(消息对冲最晚拆锁秒数, 1));
      if(expired || tooLate)
      {
         if(quoteOk) NewsRequestGroupExit(expired ? "开放拆锁窗口超时" : "最晚拆锁时间超时");
         else
         {
            消息对冲状态 = "拆锁时限已到，等待有效报价全平";
            lastStatus = 消息对冲状态;
         }
         return;
      }
   }

   if((newsState.stage == 消息阶段_冲击持仓 || newsState.stage == 消息阶段_延续持仓) &&
      NewsRunnerElapsedSeconds() >= MathMax(消息对冲组合最长持仓秒数, 1))
   {
      if(quoteOk) NewsRequestGroupExit("消息最长持仓到期");
      else
      {
         消息对冲状态 = "最长持仓已到，等待有效报价全平";
         lastStatus = 消息对冲状态;
      }
   }
}

void ManagePosition(ulong ticket, double atr)
{
   PerformanceScope perfScope(PERF_MANAGE_POSITION);
   PerformanceScope perfSingleScope(PERF_MANAGE_POSITION_SINGLE);
   if(!PositionSelectByTicket(ticket)) return;
   if(!PositionInScope()) return;

   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double curSL = PositionGetDouble(POSITION_SL);
   double curTP = PositionGetDouble(POSITION_TP);
   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double profitPrice = (type == POSITION_TYPE_BUY) ? (bid - openPrice) : (openPrice - ask);

   int stateIdx = EnsureState(ticket);
   bool becameManaged = !states[stateIdx].shortStateManaged;
   states[stateIdx].shortStateManaged = true;
   if(becameManaged)
   {
      MarkShortStateDirty(stateIdx);
      ShortStateSave(stateIdx);
      TradeJournalWriteLifecycle(stateIdx, "TEMPLATE_FROZEN_AT_ADOPTION",
                                 StringFormat("ticket=%I64u;template=%d", ticket, states[stateIdx].adoptedTemplate));
   }
   PositionTemplateScope templateScope(stateIdx);
   // 逐仓模板切换只读取/更新数据缓存，图表对象由OnTick收尾统一绘制，避免箱体闪烁和重置。
   RefreshMarketStructureCaches(false, false);
   bool shortLine = (当前参数配置模板 == 配置_黄金超短快保);
   if(shortLine && becameManaged && !states[stateIdx].teacherPlanInitialized)
   {
      FreezeShortTeacherPlan(stateIdx, type, openPrice);
      MarkShortStateDirty(stateIdx);
      ShortStateSave(stateIdx);
      TradeJournalWriteLifecycle(stateIdx, "TEACHER_SHORT_PLAN_FROZEN",
                                 StringFormat("enabled=%d;valid=%d;mode=%d;signature=%I64u;primary=%.5f;secondary=%.5f",
                                              短线单启用老师点位辅助SLTP ? 1 : 0,
                                              states[stateIdx].teacherPlanValid ? 1 : 0,
                                              states[stateIdx].teacherPlanMode,
                                              states[stateIdx].teacherPlanSignature,
                                              states[stateIdx].teacherPrimaryTP,
                                              states[stateIdx].teacherSecondaryTP));
   }
   // pending期间也只读观察真实浮亏，避免最长数十秒的成交确认窗口漏掉回本武装；
   // 这里只冻结资格，不发送任何交易请求。
   if(shortLine) ShortObserveRecoveryArm(stateIdx, profitPrice, atr);
   ReconcilePendingTradeAction(stateIdx);
   if(shortLine) ShortReconcilePositionShape(stateIdx);
   if(states[stateIdx].lifecyclePhase == 生命周期_等待最终结算 ||
      states[stateIdx].lifecyclePhase == 生命周期_已结束) return;
   if(states[stateIdx].pendingAction != 待确认动作_无) return;
   bool stateChanged = false;
   if(profitPrice > states[stateIdx].maxProfitPrice)
   {
      states[stateIdx].maxProfitPrice = profitPrice;
      stateChanged = true;
   }
   if(profitPrice < 0.0 && -profitPrice > states[stateIdx].maxLossPrice)
   {
      states[stateIdx].maxLossPrice = -profitPrice;
      stateChanged = true;
   }
   double positionMoney = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   if(positionMoney > states[stateIdx].maxProfitMoney) { states[stateIdx].maxProfitMoney = positionMoney; stateChanged = true; }
   if(positionMoney < 0.0 && -positionMoney > states[stateIdx].maxLossMoney) { states[stateIdx].maxLossMoney = -positionMoney; stateChanged = true; }
   if(states[stateIdx].initialVolume <= 0.0)
   {
      states[stateIdx].initialVolume = PositionGetDouble(POSITION_VOLUME);
      stateChanged = true;
   }

   double volume = PositionGetDouble(POSITION_VOLUME);
   double shortInitialRisk = 0.0;
   bool shortRiskReady = false;
   if(shortLine)
   {
      ShortEnsureInitialRiskReady(ticket, stateIdx, type, openPrice, atr);
      if(!PositionSelectByTicket(ticket)) return;
      curSL = PositionGetDouble(POSITION_SL);
      curTP = PositionGetDouble(POSITION_TP);
      volume = PositionGetDouble(POSITION_VOLUME);
      shortInitialRisk = ShortLineGetRisk(stateIdx, type, openPrice, curSL, atr);
      shortRiskReady = states[stateIdx].shortRiskReady;
      if(stateChanged) MarkShortStateDirty(stateIdx);
   }
   else if(当前模板使用黄金稳健止损() && stateChanged)
      MarkShortStateDirty(stateIdx);

   if(states[stateIdx].teacherActivePlan)
   {
      ManageTeacherActivePosition(ticket, stateIdx, type, openPrice, profitPrice);
      return; // 积极单复用统一请求/确认，不再叠加旧短线快保和两段分批
   }

   ShortLineMarketContext shortCtx;
   InitShortLineMarketContext(shortCtx);
   bool hasShortCtx = false;
   if(shortLine)
   {
      hasShortCtx = BuildShortLineMarketContext(type, openPrice, (type == POSITION_TYPE_BUY ? bid : ask), atr, shortCtx);
      if(hasShortCtx)
      {
         ClassifyShortTradeArchetype(stateIdx, type, openPrice, shortCtx);
         ShortUpdateMarketRegime(stateIdx, shortCtx);
      }
   }

   if(ExecuteShortLineRecoveryExit(ticket, stateIdx, type, profitPrice, atr)) return;

   // 支压手控版不再自动触达R/S平仓；这里保留通用调用，实际由 当前模板使用支压分段止盈() 控制。
   if(ExecuteFullTakeProfitAtSecondSR(ticket, stateIdx, type, profitPrice)) return;

   // 分批止盈：趋势单长拿默认不做主动分批，避免完整方向仓被短线节奏拆掉。
   // 普通分批模板每个position只执行一次；支压手控版已关闭分批。
   if(!当前模板使用黄金稳健止损() || 趋势单分批止盈启用)
      ExecutePartialTakeProfit(ticket, stateIdx, type, openPrice, volume, profitPrice,
                               atr, shortCtx, hasShortCtx);
   if(states[stateIdx].pendingAction != 待确认动作_无) return;
   if(!PositionSelectByTicket(ticket)) return;
   curSL = PositionGetDouble(POSITION_SL);
   curTP = PositionGetDouble(POSITION_TP);
   volume = PositionGetDouble(POSITION_VOLUME);

   double newSL = curSL;
   double newTP = curTP;
   int slSource = SL来源_无;
   int tpSource = TP来源_无;
   bool fastProtectionIntent = false;
   double fastProtectionTarget = 0.0;
   bool fixedTPRemovalIntent = false;
   bool pendingM1StructUpdate = false;
   datetime pendingM1StructBarTime = 0;
   double visualBoxSL = 0.0, visualBoxTP = 0.0, visualBoxSLDistance = 0.0, visualBoxTPDistance = 0.0;
   bool hasVisualBoxTargets = (shortLine &&
                               ShortLineVisualBoxInitialTargets(type, openPrice, visualBoxSL, visualBoxTP,
                                                                 visualBoxSLDistance, visualBoxTPDistance));

   if(当前模板使用黄金稳健止损())
   {
      if(curSL > 0.0 && !states[stateIdx].trendRiskReady)
         TrendFreezeInitialRiskFromServer(stateIdx, "server_sl_at_adoption");

      if(curSL <= 0.0)
      {
         double trendInitialSL = 0.0;
         double trendInitialRisk = 0.0;
         if(TrendLongInitialSLPrice(type, openPrice, trendInitialSL, trendInitialRisk))
         {
            if(MoreProtective(type, trendInitialSL, newSL))
            {
               newSL = trendInitialSL;
               slSource = SL来源_初始结构;
            }
         }
      }
   }
   else
   {
      double initSLDist = DistanceByMode(初始SL模式, 固定SL价格距离, atr, ATR止损倍数);
      if(当前参数配置模板 == 配置_黄金超短快保)
         initSLDist = ShortLineDynamicInitialSL(atr, type);
      double shortBoxSL = 0.0;
      double shortBoxSLDist = 0.0;
      if(当前参数配置模板 == 配置_黄金超短快保 &&
         ShortLineBoxSLPrice(type, openPrice, shortBoxSL, shortBoxSLDist))
      {
         // 箱体只能把初始SL放到更远的有效结构外侧，不能把波动SL收近。
         initSLDist = MathMax(initSLDist, shortBoxSLDist);
      }
      if(hasVisualBoxTargets)
      {
         // 近期有效箱体在低波动时允许给出小于 ATR 下限的成对初始风险；服务器距离仍由 SLTPValid 校验。
         initSLDist = visualBoxSLDistance;
         shortBoxSL = visualBoxSL;
      }
      if(curSL <= 0 && initSLDist > 0)
      {
         double sl = (type == POSITION_TYPE_BUY) ? openPrice - initSLDist : openPrice + initSLDist;
         if(MoreProtective(type, NormalizePrice(sl), newSL))
         {
            newSL = NormalizePrice(sl);
            slSource = hasVisualBoxTargets ? SL来源_初始箱体 : SL来源_初始ATR;
         }
      }
      else if(shortBoxSL > 0.0 &&
              !短线单保留已有初始SLTP &&
              MoreProtective(type, NormalizePrice(shortBoxSL), newSL))
      {
         newSL = NormalizePrice(shortBoxSL);
         slSource = SL来源_初始箱体;
      }
   }

   double initTPDist = DistanceByMode(初始TP模式, 固定TP价格距离, atr, ATR止盈倍数);
   double dynamicShortTPDist = 0.0;
   bool teacherTPSelected = false;
   double teacherTPPrice = 0.0;
   bool useTeacherTPForInitial = false;
   if(当前参数配置模板 == 配置_黄金超短快保)
   {
      dynamicShortTPDist = ShortLineEffectiveMainTPDistance(stateIdx, type, openPrice, atr,
                                                            teacherTPSelected, teacherTPPrice);
      initTPDist = dynamicShortTPDist;
      useTeacherTPForInitial = teacherTPSelected;
   }
   else if(当前模板使用黄金稳健止损())
      initTPDist = 趋势单启用固定TP ? TrendDynamicInitialTP(atr, type) : 0.0;
   double shortBoxTP = 0.0;
   double shortBoxTPDist = 0.0;
   bool hasShortBoxTP = (当前参数配置模板 == 配置_黄金超短快保 &&
                         ShortLineBoxTPPrice(type, openPrice, shortBoxTP, shortBoxTPDist));
   bool useShortBoxTPForInitial = false;
   if(hasVisualBoxTargets)
   {
      // 老师目标与可视箱体都属于前方障碍位，采用更近的有效目标，避免越过先到结构。
      if(!teacherTPSelected || visualBoxTPDistance < dynamicShortTPDist)
      {
         initTPDist = visualBoxTPDistance;
         useShortBoxTPForInitial = true;
         useTeacherTPForInitial = false;
         shortBoxTP = visualBoxTP;
      }
   }
   else if(hasShortBoxTP &&
       shortBoxTPDist > 0.0 &&
       dynamicShortTPDist > 0.0 &&
       shortBoxTPDist < dynamicShortTPDist &&
       shortBoxTPDist >= dynamicShortTPDist * ClampDouble(短线单箱体TP最小主目标比例, 0.10, 1.00) &&
       shortBoxTPDist >= 短线单箱体TP最小空间价格)
   {
      initTPDist = shortBoxTPDist;
      useShortBoxTPForInitial = true;
      useTeacherTPForInitial = false;
   }
   bool shortFixedTPRemoved = (shortLine && states[stateIdx].fixedTPRemoved);
   if(curTP <= 0 && initTPDist > 0 && !shortFixedTPRemoved)
   {
      double tp = useShortBoxTPForInitial ? shortBoxTP :
                  (useTeacherTPForInitial ? teacherTPPrice :
                   ((type == POSITION_TYPE_BUY) ? openPrice + initTPDist : openPrice - initTPDist));
      newTP = NormalizePrice(tp);
      tpSource = useShortBoxTPForInitial ? TP来源_箱体目标 :
                 (useTeacherTPForInitial ? TP来源_老师点位 : TP来源_动态主TP);
   }
   else if(useTeacherTPForInitial && !shortFixedTPRemoved && !短线单保留已有初始SLTP)
   {
      double normalizedTeacherTP = NormalizePrice(teacherTPPrice);
      if(MathAbs(normalizedTeacherTP-newTP) >= _Point)
      {
         newTP = normalizedTeacherTP;
         tpSource = TP来源_老师点位;
      }
   }
   else if(hasShortBoxTP && !shortFixedTPRemoved)
   {
      bool canTightenTP =
         !短线单保留已有初始SLTP &&
         短线单箱体允许收近已有TP &&
         ((type == POSITION_TYPE_BUY && shortBoxTP > SymbolInfoDouble(_Symbol, SYMBOL_BID) && shortBoxTP < newTP) ||
          (type == POSITION_TYPE_SELL && shortBoxTP < SymbolInfoDouble(_Symbol, SYMBOL_ASK) && shortBoxTP > newTP));
      bool canExtendTP =
         !短线单保留已有初始SLTP &&
         短线单箱体允许放远已有TP &&
         states[stateIdx].maxProfitPrice < MathMax(短线单分批利润保护启动价格, 短线单箱体TP最小空间价格) &&
         ((type == POSITION_TYPE_BUY && shortBoxTP > newTP) ||
          (type == POSITION_TYPE_SELL && shortBoxTP < newTP));

      if(canTightenTP || canExtendTP)
      {
         newTP = NormalizePrice(shortBoxTP);
         tpSource = TP来源_箱体目标;
      }
   }
   else if(当前参数配置模板 == 配置_黄金超短快保 && !shortFixedTPRemoved &&
            !短线单保留已有初始SLTP &&
            initTPDist > 0 &&
           ShortLineTrendWithPosition(type) &&
           states[stateIdx].maxProfitPrice >= MathMax(短线单主TP最小价格 * 0.50, 保本触发价格))
   {
      double trendTP = NormalizePrice((type == POSITION_TYPE_BUY) ? openPrice + initTPDist : openPrice - initTPDist);
      if((type == POSITION_TYPE_BUY && trendTP > newTP) ||
         (type == POSITION_TYPE_SELL && trendTP < newTP))
      {
         newTP = trendTP;
      }
   }

    if(当前参数配置模板 == 配置_黄金超短快保 &&
       短线单启用成本线快收 &&
       (!短线单保留已有初始SLTP || curTP <= 0.0) && !shortFixedTPRemoved)
   {
      int heldSeconds = (int)(TimeCurrent() - openTime);
      int hesitateMinutes = ShortLineDynamicHesitationMinutes(atr);
      double smallTPDist = ShortLineDynamicSmallTP(atr);
      bool strongTrend = ShortLineStrongTrendWithPosition(type, atr, profitPrice, states[stateIdx].maxProfitPrice);
      if(!strongTrend &&
         smallTPDist > 0.0 &&
         heldSeconds >= hesitateMinutes * 60 &&
         states[stateIdx].maxProfitPrice < smallTPDist &&
         profitPrice < smallTPDist)
      {
         double smallTP = (type == POSITION_TYPE_BUY) ? openPrice + smallTPDist : openPrice - smallTPDist;
         smallTP = NormalizePrice(smallTP);
         if(newTP <= 0.0 ||
            (type == POSITION_TYPE_BUY && smallTP < newTP) ||
            (type == POSITION_TYPE_SELL && smallTP > newTP))
         {
            newTP = smallTP;
            tpSource = TP来源_犹豫小TP;
         }
       }
    }

    if(shortLine && hasShortCtx && states[stateIdx].partialTPDone)
    {
       ShortUpdateRunnerMode(stateIdx, shortCtx);
       if(states[stateIdx].runnerMode == 短线尾仓_结构追踪 && 短线单尾仓交给结构追踪 && curTP > 0.0)
       {
          newTP = 0.0;
          tpSource = TP来源_尾仓撤销固定TP;
          fixedTPRemovalIntent = true;
          PrintFormat("[短线尾仓] 强趋势确认，撤销固定TP ticket=%I64u，交给结构追踪", ticket);
       }
       else if(states[stateIdx].fixedTPRemoved && curTP <= 0.0 &&
               (states[stateIdx].runnerMode == 短线尾仓_固定TP || states[stateIdx].runnerMode == 短线尾仓_箱体目标))
       {
          double restoreTP = 0.0;
          int restoreSource = TP来源_动态主TP;
          if(states[stateIdx].runnerMode == 短线尾仓_箱体目标 && hasShortBoxTP)
          {
             restoreTP = shortBoxTP;
             restoreSource = TP来源_箱体目标;
          }
          else if(useTeacherTPForInitial && teacherTPPrice > 0.0)
          {
             restoreTP = teacherTPPrice;
             restoreSource = TP来源_老师点位;
          }
          else if(initTPDist > 0.0)
             restoreTP = type == POSITION_TYPE_BUY ? openPrice+initTPDist : openPrice-initTPDist;
          restoreTP = NormalizePrice(restoreTP);
          bool ahead = (type == POSITION_TYPE_BUY && restoreTP > bid+_Point) ||
                       (type == POSITION_TYPE_SELL && restoreTP < ask-_Point);
          if(restoreTP > 0.0 && ahead)
          {
             newTP = restoreTP;
             tpSource = restoreSource;
             PrintFormat("[短线尾仓] 行情降级，准备恢复TP ticket=%I64u target=%.5f source=%d", ticket, restoreTP, restoreSource);
          }
       }
       else if(states[stateIdx].runnerMode == 短线尾仓_快速退出 &&
               states[stateIdx].fixedTPRemoved && curTP <= 0.0 &&
               (states[stateIdx].confirmedMarketRegime == 短线环境_动能衰竭 ||
                states[stateIdx].confirmedMarketRegime == 短线环境_反向风险))
       {
          if(ModifyFrequencyOK(stateIdx) &&
             SubmitManagedFullClose(ticket, stateIdx, 退出意图_尾仓快速退出, "runner_regime_deteriorated"))
          {
             lastStatus = "短线尾仓：趋势失效，已请求快速退出";
             return;
          }
       }
    }

    if(shortLine && shortRiskReady && hasShortCtx)
    {
       double fastSL = 0.0;
       int fastSource = SL来源_无;
       if(ShortFastProtectionCandidate(ticket, stateIdx, type, profitPrice, atr, shortCtx, fastSL, fastSource) &&
          MoreProtective(type, fastSL, newSL))
       {
          newSL = fastSL;
          slSource = fastSource;
          fastProtectionIntent = true;
          fastProtectionTarget = fastSL;
       }
    }

   double activeBETrigger = 保本触发价格;
   double activeBELock = 保本锁定价格;
   if(!当前模板使用黄金稳健止损())
      ShortLineDynamicBEConfigFromContext(type, atr, profitPrice, states[stateIdx].maxProfitPrice,
                                          shortCtx, hasShortCtx, activeBETrigger, activeBELock);

   if(当前参数配置模板 == 配置_黄金超短快保 && shortInitialRisk > 0.0)
      activeBETrigger = MathMax(activeBETrigger,
                                shortInitialRisk * MathMax(短线单保本最小风险R, 0.10));

   bool beConfirmed = (当前参数配置模板 != 配置_黄金超短快保 ||
                       ShortLineProtectionConfirmed(type, openPrice, activeBETrigger));
   if(!当前模板使用黄金稳健止损() && 启用保本 && (!shortLine || shortRiskReady) &&
      profitPrice >= activeBETrigger && beConfirmed)
    {
       double be = 0.0;
       if(shortLine)
       {
          double safetyMoney = MathMax(短线单净保本安全金额每001手, 0.0) * volume / 0.01;
          be = ShortCalculateNetBreakEvenPrice(ticket, safetyMoney);
       }
       if(be <= 0.0)
          be = (type == POSITION_TYPE_BUY) ? openPrice + activeBELock : openPrice - activeBELock;
       if(MoreProtective(type, NormalizePrice(be), newSL)) { newSL = NormalizePrice(be); slSource = SL来源_常规保本; }
   }

   if(分批后立即保护剩余仓位 && states[stateIdx].partialTPDone)
   {
      double partialLock = 分批止盈后保本锁定;
      if(当前参数配置模板 == 配置_黄金超短快保 &&
         短线单启用多段分批止盈 &&
         states[stateIdx].partialTPStage > 0 && hasShortCtx)
         partialLock = GetShortLineDynamicStageLockProfit(states[stateIdx].partialTPStage, shortCtx);

      double partialBE = (type == POSITION_TYPE_BUY) ? openPrice + partialLock : openPrice - partialLock;
      if(MoreProtective(type, NormalizePrice(partialBE), newSL)) { newSL = NormalizePrice(partialBE); slSource = SL来源_分批后保护; }
   }

   string trendSLSource = "";
   if(当前模板使用黄金稳健止损())
   {
      double beforeTrendSL = newSL;
      if(ApplyTrendLongProtection(stateIdx, type, openPrice, curSL, bid, ask, profitPrice,
                                  newSL, slSource, trendSLSource) &&
         MathAbs(newSL - beforeTrendSL) >= _Point &&
         trendSLSource != "")
      {
         lastStatus = "长线单: " + trendSLSource;
      }
   }

   // 阶梯式保护：只在浮盈跨过关键台阶时移动SL，避免贴身追踪被黄金M1正常回踩扫掉。
   if(启用阶梯式保护)
   {
      double lockProfit = -1.0;
      if(阶梯4触发价格 > 0.0 && profitPrice >= 阶梯4触发价格) lockProfit = 阶梯4锁定价格;
      else if(阶梯3触发价格 > 0.0 && profitPrice >= 阶梯3触发价格) lockProfit = 阶梯3锁定价格;
      else if(阶梯2触发价格 > 0.0 && profitPrice >= 阶梯2触发价格) lockProfit = 阶梯2锁定价格;
      else if(阶梯1触发价格 > 0.0 && profitPrice >= 阶梯1触发价格) lockProfit = 阶梯1锁定价格;

      if(lockProfit >= 0.0)
      {
         double stepSL = (type == POSITION_TYPE_BUY) ? openPrice + lockProfit : openPrice - lockProfit;
         if(MoreProtective(type, NormalizePrice(stepSL), newSL)) { newSL = NormalizePrice(stepSL); slSource = SL来源_其他; }
      }
   }

   double trailTrigger = 移动止损启动价格;
   double trailDistance = 移动止损距离价格;
   double trailMinStep = 移动止损最小推进点数 * _Point;
   GetAdaptiveTrailConfig(atr, trailTrigger, trailDistance, trailMinStep);
   TrendAdjustTrailConfig(type, atr, trailTrigger, trailDistance, trailMinStep);

    if(!当前模板使用黄金稳健止损() && (!shortLine || shortRiskReady) && 启用移动止损 && (!启用阶梯式保护 || !阶梯保护时暂停贴身追踪) && profitPrice >= trailTrigger)
   {
      double trailSL = 0.0;
      bool hasTrailSL = false;
      bool m1StructCandidate = false;
      datetime m1StructCandidateBarTime = 0;

      bool useMicroBoxRunnerTrail =
         shortLine && 短线单尾仓交给结构追踪 && states[stateIdx].partialTPDone &&
         states[stateIdx].runnerMode == 短线尾仓_结构追踪;

      if(跟踪SL模式 == 追踪M1前柱结构 || useMicroBoxRunnerTrail)
      {
         // 常规M1结构仍按原逻辑运行；只有第一段成交后确认强趋势的尾仓，
         // 才改用最近5-10根已收M1组成的微型箱体，让趋势有正常回踩空间。
         double m1MinDistance = 0.0;
         datetime lastClosedBar = 0;
         double m1Trigger = MathMax(M1结构最小浮盈启动, atr > 0.0 ? atr * M1结构追踪启动ATR倍数 : 0.0);
         if(当前参数配置模板 == 配置_黄金超短快保 && shortInitialRisk > 0.0)
            m1Trigger = MathMax(m1Trigger,
                                shortInitialRisk * MathMax(短线单结构追踪最小风险R, 0.10));

         if(profitPrice >= m1Trigger &&
            ShortLineProtectionConfirmed(type, openPrice, m1Trigger) &&
            (useMicroBoxRunnerTrail ?
               ShortLineMicroBoxStructureSL(type, atr, false, trailSL, m1MinDistance, lastClosedBar) :
               CalculateM1PreviousBarsStructureSL(type, atr, trailSL, m1MinDistance, lastClosedBar)))
         {
            if(!M1结构只在新K线更新 || states[stateIdx].lastM1StructBarTime != lastClosedBar)
            {
               hasTrailSL = true;
               m1StructCandidate = true;
               m1StructCandidateBarTime = lastClosedBar;
            }
         }
      }
      else
      {
         // 自适应基础追踪：波动大则给更宽距离，波动小则自动收紧。
         double trail = (type == POSITION_TYPE_BUY) ? bid - trailDistance : ask + trailDistance;
         trailSL = NormalizePrice(trail);
         hasTrailSL = true;

         // 结构自适应：尽量把SL放在最近支撑/压力外侧，而不是贴着当前价格。
         if(跟踪SL模式 == 追踪结构自适应)
         {
            SRLevel lv;
            if(type == POSITION_TYPE_BUY && GetNearestSupport(bid, lv))
            {
               double structSL = NormalizePrice(lv.price - 结构SL缓冲价格);
               // BUY取更宽松的保护位：结构位若低于ATR追踪位，优先结构位，避免刚好被回踩扫掉。
               if(structSL > 0.0 && structSL < trailSL && structSL < bid)
                  trailSL = structSL;
            }
            else if(type == POSITION_TYPE_SELL && GetNearestResistance(ask, lv))
            {
               double structSL = NormalizePrice(lv.price + 结构SL缓冲价格);
               // SELL取更宽松的保护位：结构位若高于ATR追踪位，优先结构位。
               if(structSL > 0.0 && structSL > trailSL && structSL > ask)
                  trailSL = structSL;
            }
         }
      }

      if(hasTrailSL && MoreProtective(type, trailSL, newSL))
      {
         if(newSL <= 0 ||
            (type == POSITION_TYPE_BUY && trailSL >= newSL + trailMinStep) ||
            (type == POSITION_TYPE_SELL && trailSL <= newSL - trailMinStep))
         {
            newSL = trailSL;
            slSource = useMicroBoxRunnerTrail ? SL来源_微型箱体尾仓 : SL来源_M1前柱结构;
            if(跟踪SL模式 == 追踪M1前柱结构 || useMicroBoxRunnerTrail)
            {
               pendingM1StructUpdate = m1StructCandidate;
               pendingM1StructBarTime = m1StructCandidateBarTime;
            }
         }
      }
   }

   if(shortLine && shortRiskReady)
   {
      double teacherProtectionSL = 0.0;
      if(ShortLineTeacherProtectionSL(stateIdx, type, openPrice, atr, profitPrice, teacherProtectionSL) &&
         MoreProtective(type, teacherProtectionSL, newSL) &&
         (newSL <= 0.0 ||
          (type == POSITION_TYPE_BUY && teacherProtectionSL >= newSL+trailMinStep) ||
          (type == POSITION_TYPE_SELL && teacherProtectionSL <= newSL-trailMinStep)))
      {
         newSL = teacherProtectionSL;
         slSource = SL来源_老师突破保护;
         pendingM1StructUpdate = false;
         pendingM1StructBarTime = 0;
      }
   }

   double ddStartProfit = 回撤保护启动价格;
   double ddMaxRatio = 最大浮盈回撤比例;
   double ddLockRatio = 回撤后锁定利润比例;
   if(当前参数配置模板 == 配置_黄金超短快保)
   {
      if(hasShortCtx)
         GetShortLineDynamicDrawdownProtection(shortCtx, ddStartProfit, ddMaxRatio, ddLockRatio);
      if(shortInitialRisk > 0.0)
         ddStartProfit = MathMax(ddStartProfit,
                                 shortInitialRisk * MathMax(短线单回撤保护最小风险R, 0.10));
   }

    if(!当前模板使用黄金稳健止损() && (!shortLine || shortRiskReady) && 启用浮盈回撤保护 && states[stateIdx].maxProfitPrice >= ddStartProfit)
   {
      double maxProfit = states[stateIdx].maxProfitPrice;
      if(maxProfit > 0)
      {
         double drawdownRatio = (maxProfit - profitPrice) / maxProfit;
         if(drawdownRatio >= ddMaxRatio)
         {
            double lockProfit = maxProfit * ddLockRatio;
            double lockSL = (type == POSITION_TYPE_BUY) ? openPrice + lockProfit : openPrice - lockProfit;
            double normalizedLockSL = NormalizePrice(lockSL);
            if(MoreProtective(type, normalizedLockSL, newSL))
            {
               newSL = normalizedLockSL;
               slSource = SL来源_浮盈回撤锁定;
               pendingM1StructUpdate = false;
               pendingM1StructBarTime = 0;
            }
         }
      }
   }

    if(!当前模板使用黄金稳健止损() && 最大持仓分钟数 > 0 && 超时后收紧到保本)
   {
      int heldSeconds = (int)(TimeCurrent() - openTime);
      if(heldSeconds >= 最大持仓分钟数 * 60 && profitPrice > 0)
      {
         double timeoutSL = (type == POSITION_TYPE_BUY) ? openPrice + 保本锁定价格 : openPrice - 保本锁定价格;
         double normalizedTimeoutSL = NormalizePrice(timeoutSL);
         if(MoreProtective(type, normalizedTimeoutSL, newSL))
         {
            newSL = normalizedTimeoutSL;
            slSource = SL来源_超时保本;
            pendingM1StructUpdate = false;
            pendingM1StructBarTime = 0;
         }
      }
   }

   bool needSL = (newSL > 0 && MathAbs(newSL - curSL) >= _Point);
    bool needTP = (MathAbs(newTP - curTP) >= _Point);
   if(!needSL && !needTP) return;

   double sendSL = needSL ? newSL : curSL;
   double sendTP = needTP ? newTP : curTP;
   if(!SLTPValid(type, sendSL, sendTP))
   {
      lastStatus = "跳过: SL/TP距离不合法";
      return;
   }

   if(!ModifyFrequencyOK(stateIdx)) return;

   if(SubmitManagedPositionModify(ticket, stateIdx, sendSL, sendTP, slSource, tpSource,
                                  fastProtectionIntent, fastProtectionTarget, fixedTPRemovalIntent))
   {
      states[stateIdx].lastManagedModifyTime = TimeCurrent();
      MarkShortStateDirty(stateIdx);
      lastStatus = StringFormat("已更新 ticket=%I64u SL=%.2f TP=%.2f", ticket, sendSL, sendTP);
   }
   else
   {
      lastStatus = StringFormat("修改失败 ticket=%I64u ret=%d %s", ticket, manageTrade.ResultRetcode(), manageTrade.ResultComment());
   }
}



int 当前面板基础宽度()
{
   if(当前面板显示模式 == 面板迷你)
      return MathMax(迷你面板宽度, 390);
   if(当前面板显示模式 == 面板隐藏)
      return 230;
   return MathMax(面板宽度, 280);
}

void BeginPanelAutoWidth(int baseWidth)
{
   datetime now = TimeCurrent();
   int base = MathMax(baseWidth, 230);
   面板基础宽度缓存 = base;

   if(面板保持宽度 < base)
      面板保持宽度 = base;

   // 只有超过保持时间后，才允许从“曾经撑宽”的宽度回落到基础宽度。
   // 如果当前刷新里仍有长文字，后续 SetPanelLine 会立刻重新撑宽，不会出现文字出框。
   int waitSec = MathMax(面板自动缩回等待秒, 0);
   if(waitSec <= 0 || (面板最近撑宽时间 > 0 && now - 面板最近撑宽时间 >= waitSec))
      面板保持宽度 = base;

   当前面板宽度 = 面板保持宽度;
}

void ResetPanelWidthNow(int width)
{
   int w = MathMax(width, 230);
   面板基础宽度缓存 = w;
   面板保持宽度 = w;
   当前面板宽度 = w;
   面板最近撑宽时间 = 0;
   ApplyPanelAutoWidth();
}

void ApplyPanelAutoWidth()
{
   if(ObjectFind(0, "SMA_PANEL_BG") >= 0)
      SetObjectIntegerIfChanged("SMA_PANEL_BG", OBJPROP_XSIZE, 当前面板宽度);
}

int EstimateTextPixelWidth(string text, int fontSize)
{
   // MQL图表对象没有稳定的跨字体自动测宽接口，这里按字符类型估算：
   // 中文/全角字符按约1个字号宽度，ASCII按约0.62个字号宽度。
   // 估算略偏宽，目的是保证边框永远包住文字。
   int w = 0;
   int n = StringLen(text);
   for(int i=0; i<n; i++)
   {
      ushort ch = StringGetCharacter(text, i);
      if(ch <= 0x007F)
         w += (int)MathCeil(fontSize * 0.62);
      else
         w += (int)MathCeil(fontSize * 1.05);
   }
   return w;
}

int PanelHeaderControlWidth()
{
   // 顶栏为 5 个 46px 按钮、4 个 5px 间距和右侧 10px 留白。
   return 5*46 + 4*5 + 10;
}

void EnsurePanelWidthForText(string text, int fontSize, int reservedRight)
{
   int base = (面板基础宽度缓存 > 0 ? 面板基础宽度缓存 : 当前面板基础宽度());
   // 左侧 12px、文字和右侧内容之间 12px、边框 10px；标题行还必须预留完整按钮区。
   int padding = 34 + MathMax(reservedRight, 0);
   int need = EstimateTextPixelWidth(text, fontSize) + padding;
   if(need < base)
      need = base;

   // 只在出现更长文字时撑宽；普通数字跳动变短不会立即缩，避免每 tick 忽宽忽窄。
   if(need > 面板保持宽度)
   {
      面板保持宽度 = need;
      面板最近撑宽时间 = TimeCurrent();
      当前面板宽度 = 面板保持宽度;
      ApplyPanelAutoWidth();
   }
}

// 面板采用交易终端常见的深色仪表盘配色：一层背景、一层标题栏、低饱和导航，
// 只用青绿表示当前选中，红/橙保留给风险和不可逆动作，避免满屏高饱和色抢信息。
color PanelInkColor()        { return C'12,20,31'; }
color PanelBackgroundColor() { return C'15,23,35'; }
color PanelHeaderColor()     { return C'24,35,52'; }
color PanelSurfaceColor()    { return C'31,45,64'; }
color PanelBorderColor()     { return C'54,70,92'; }
color PanelTextColor()       { return C'225,232,241'; }
color PanelMutedTextColor()  { return C'155,170,190'; }
color PanelAccentColor()     { return C'33,211,196'; }

void DrawPanelSurface(string name, int x, int y, int width, int height, color background, color border, int zorder)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   SetObjectIntegerIfChanged(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   SetObjectIntegerIfChanged(name, OBJPROP_XDISTANCE, 当前面板左边距 + x);
   SetObjectIntegerIfChanged(name, OBJPROP_YDISTANCE, 当前面板上边距 + y);
   SetObjectIntegerIfChanged(name, OBJPROP_XSIZE, MathMax(width, 1));
   SetObjectIntegerIfChanged(name, OBJPROP_YSIZE, MathMax(height, 1));
   SetObjectIntegerIfChanged(name, OBJPROP_BGCOLOR, background);
   SetObjectIntegerIfChanged(name, OBJPROP_BORDER_COLOR, border);
   SetObjectIntegerIfChanged(name, OBJPROP_BACK, false);
   SetObjectIntegerIfChanged(name, OBJPROP_SELECTABLE, false);
   SetObjectIntegerIfChanged(name, OBJPROP_SELECTED, false);
   SetObjectIntegerIfChanged(name, OBJPROP_ZORDER, zorder);
}

void DrawPanelChrome()
{
   int width = (当前面板宽度 > 0 ? 当前面板宽度 : 当前面板基础宽度());
   DrawPanelSurface("SMA_UI_HEADER", 0, 0, width, 38, PanelHeaderColor(), PanelBorderColor(), 1);
   DrawPanelSurface("SMA_UI_ACCENT", 0, 0, 4, 38, PanelAccentColor(), PanelAccentColor(), 2);
   DrawPanelSurface("SMA_UI_DIVIDER", 0, 38, width, 1, PanelBorderColor(), PanelBorderColor(), 2);
}

void DeletePanelNavigationSurfaces()
{
   ObjectDelete(0, "SMA_UI_TEMPLATE_NAV");
   ObjectDelete(0, "SMA_UI_STATS_NAV");
}

void SetPanelLine(string name, int y, string text, color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   int fontSize = (name == "SMA_PANEL_1") ? MathMax(面板字体大小, 12) : MathMax(面板字体大小-1, 10);
   SetObjectIntegerIfChanged(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   SetObjectIntegerIfChanged(name, OBJPROP_XDISTANCE, 当前面板左边距 + 12);
   SetObjectIntegerIfChanged(name, OBJPROP_YDISTANCE, 当前面板上边距 + y);
   SetObjectIntegerIfChanged(name, OBJPROP_FONTSIZE, fontSize);
   SetObjectStringIfChanged(name, OBJPROP_FONT, 面板字体);
   SetObjectStringIfChanged(name, OBJPROP_TEXT, text);
   EnsurePanelWidthForText(text, fontSize, name == "SMA_PANEL_1" ? PanelHeaderControlWidth() : 0);
   SetObjectIntegerIfChanged(name, OBJPROP_COLOR, clr);
   SetObjectIntegerIfChanged(name, OBJPROP_SELECTABLE, false);
   SetObjectIntegerIfChanged(name, OBJPROP_ZORDER, 10);
}

void SetObjectIntegerIfChanged(string name, ENUM_OBJECT_PROPERTY_INTEGER prop, long value)
{
   if(ObjectGetInteger(0, name, prop) == value)
      return;
   ObjectSetInteger(0, name, prop, value);
}

void SetObjectStringIfChanged(string name, ENUM_OBJECT_PROPERTY_STRING prop, string value)
{
   if(ObjectGetString(0, name, prop) == value)
      return;
   ObjectSetString(0, name, prop, value);
}

void DrawPanelBackground(int height)
{
   int requestedHeight = MathMax(height, 120);
   // 仓页最终高度会在内容绘制完成后自适应。刷新开始时不先缩小背景，
   // 避免同一帧内“缩小再拉长”造成黑色背景闪烁。
   if(当前面板页面 == 页面持仓 && 当前面板高度 > requestedHeight)
      requestedHeight = 当前面板高度;
   当前面板高度 = requestedHeight;
   BeginPanelAutoWidth(MathMax(面板宽度, 280));
   string name = "SMA_PANEL_BG";
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   SetObjectIntegerIfChanged(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   SetObjectIntegerIfChanged(name, OBJPROP_XDISTANCE, 当前面板左边距);
   SetObjectIntegerIfChanged(name, OBJPROP_YDISTANCE, 当前面板上边距);
   SetObjectIntegerIfChanged(name, OBJPROP_XSIZE, 当前面板宽度);
   SetObjectIntegerIfChanged(name, OBJPROP_YSIZE, 当前面板高度);
   SetObjectIntegerIfChanged(name, OBJPROP_BGCOLOR, PanelBackgroundColor());
   SetObjectIntegerIfChanged(name, OBJPROP_BORDER_COLOR, PanelBorderColor());
   SetObjectIntegerIfChanged(name, OBJPROP_BACK, false);
   SetObjectIntegerIfChanged(name, OBJPROP_SELECTABLE, 允许鼠标拖动面板);
   SetObjectIntegerIfChanged(name, OBJPROP_SELECTED, false);
   SetObjectIntegerIfChanged(name, OBJPROP_ZORDER, 0);
   DrawPanelChrome();
}

void CreatePanelButton(string name, string text, int x, int y, int w, int h, bool active)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   bool danger = (name == "SMA_BTN_NEWS_FLAT");
   bool warning = (name == "SMA_BTN_NEWS_CANCEL");
   color background = active ? PanelAccentColor() : PanelSurfaceColor();
   color border = active ? PanelAccentColor() : PanelBorderColor();
   color textColor = active ? PanelInkColor() : PanelTextColor();
   if(danger)
   {
      background = active ? C'228,82,91' : C'105,49,61';
      border = active ? C'248,113,113' : C'139,61,75';
      textColor = active ? clrWhite : PanelMutedTextColor();
   }
   else if(warning)
   {
      background = active ? C'245,158,11' : C'99,74,35';
      border = active ? C'251,191,36' : C'132,99,42';
      textColor = active ? PanelInkColor() : PanelMutedTextColor();
   }
   SetObjectIntegerIfChanged(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   SetObjectIntegerIfChanged(name, OBJPROP_XDISTANCE, 当前面板左边距 + x);
   SetObjectIntegerIfChanged(name, OBJPROP_YDISTANCE, 当前面板上边距 + y);
   SetObjectIntegerIfChanged(name, OBJPROP_XSIZE, w);
   SetObjectIntegerIfChanged(name, OBJPROP_YSIZE, h);
   SetObjectIntegerIfChanged(name, OBJPROP_FONTSIZE, MathMax(面板字体大小-2, 10));
   SetObjectStringIfChanged(name, OBJPROP_FONT, 面板字体);
   SetObjectStringIfChanged(name, OBJPROP_TEXT, text);
   SetObjectIntegerIfChanged(name, OBJPROP_COLOR, textColor);
   SetObjectIntegerIfChanged(name, OBJPROP_BGCOLOR, background);
   SetObjectIntegerIfChanged(name, OBJPROP_BORDER_COLOR, border);
   SetObjectIntegerIfChanged(name, OBJPROP_STATE, false);
   SetObjectIntegerIfChanged(name, OBJPROP_ZORDER, 100);
}

void DrawTemplateButtons(int x, int y)
{
   ObjectDelete(0, "SMA_UI_STATS_NAV");
   int navWidth = MathMax(当前面板宽度-16, 350);
   DrawPanelSurface("SMA_UI_TEMPLATE_NAV", 8, y-4, navWidth, 56, C'20,31,46', PanelBorderColor(), 2);
   int gap = 5;
   int bwCustom = 66;
   int bwFast   = 76;
   int bwTrend  = 86;
   int bwSRTP   = 86;
   int bwNews   = 90;

   int bx = x;
   CreatePanelButton("SMA_BTN_CFG_CUSTOM", "自定义", bx, y, bwCustom, 22, 当前参数配置模板 == 配置_自定义);
   bx += bwCustom + gap;
   CreatePanelButton("SMA_BTN_CFG_FAST", "短线单", bx, y, bwFast, 22, 当前参数配置模板 == 配置_黄金超短快保);
   bx += bwFast + gap;
   CreatePanelButton("SMA_BTN_CFG_TREND", "长线单", bx, y, bwTrend, 22, 当前参数配置模板 == 配置_黄金稳健托管);
   bx += bwTrend + gap;
   CreatePanelButton("SMA_BTN_CFG_SRTP", "手动单", bx, y, bwSRTP, 22, 当前参数配置模板 == 配置_黄金支压止盈);
   bx += bwSRTP + gap;
   CreatePanelButton("SMA_BTN_CFG_NEWS", "消息对冲", bx, y, bwNews, 22, 当前参数配置模板 == 配置_黄金消息对冲);
}

bool RebuildATRHandleForCurrentTemplate()
{
   // ATR周期是input，面板模板切换不改变句柄参数；只在缺失时创建。
   if(atrHandle != INVALID_HANDLE) return true;

   atrHandle = iATR(_Symbol, PERIOD_M1, ATR周期);
   if(atrHandle == INVALID_HANDLE)
   {
      PrintRateLimited("atr_handle_rebuild_failed", 10,
                       StringFormat("ATR句柄重建失败，ATR周期=%d", ATR周期));
      lastStatus = "模板已切换，但ATR重建失败";
      return false;
   }
   return true;
}


string 配置模板持久化Key()
{
   // 用 ChartID 做键，周期切换、重新编译和无关参数修改后沿用上次面板选择。
   return "SMA_CFG_" + IntegerToString((long)ChartID());
}

string 配置模板输入持久化Key()
{
   return "SMA_CFG_INPUT_" + IntegerToString((long)ChartID());
}

string 面板信息模式持久化Key()
{
   return "SMA_PANEL_VIEW_" + IntegerToString((long)ChartID());
}

string 手机标记挂单开关持久化Key()
{
   // v1.56 Canvas 面板默认重新启用提示挂单，避免旧版保存的“关闭”状态覆盖新版默认值。
   // 新键仍保留用户在 v1.56 中主动开关后的持久化选择。
   return "SMA_MARKER_ENABLED_V156_" + IntegerToString((long)ChartID());
}

void 保存手机标记挂单面板开关()
{
   GlobalVariableSet(手机标记挂单开关持久化Key(), 手机标记挂单面板开关 ? 1.0 : 0.0);
}

bool 读取持久化手机标记挂单面板开关()
{
   if(!启用手机标记挂单) return false;
   string key = 手机标记挂单开关持久化Key();
   if(!GlobalVariableCheck(key)) return true;
   return (GlobalVariableGet(key) > 0.5);
}

bool 当前启用手机标记挂单()
{
   return (启用手机标记挂单 && 手机标记挂单面板开关);
}

void 保存面板信息模式()
{
   GlobalVariableSet(面板信息模式持久化Key(), (double)((int)当前面板信息模式));
}

面板信息密度 读取持久化面板信息模式()
{
   string key = 面板信息模式持久化Key();
   if(!GlobalVariableCheck(key)) return 面板信息_简单;
   int value = (int)MathRound(GlobalVariableGet(key));
   return value == (int)面板信息_专业 ? 面板信息_专业 : 面板信息_简单;
}

string 配置模板重载原因Key()
{
   return "SMA_CFG_REASON_" + IntegerToString((long)ChartID());
}

bool 配置模板值有效(int v)
{
   return (v >= (int)配置_自定义 && v <= (int)配置_黄金消息对冲);
}

void 保存当前配置模板()
{
   GlobalVariableSet(配置模板持久化Key(), (double)((int)当前参数配置模板));
}

void 保存配置模板输入值(管理配置模板 inputTemplate)
{
   GlobalVariableSet(配置模板输入持久化Key(), (double)((int)inputTemplate));
}

void 保存配置模板重载原因(const int reason)
{
   GlobalVariableSet(配置模板重载原因Key(), (double)reason);
}

int 读取上次重载原因()
{
   string key = 配置模板重载原因Key();
   if(!GlobalVariableCheck(key))
      return -1;
   return (int)MathRound(GlobalVariableGet(key));
}

管理配置模板 读取持久化配置模板(管理配置模板 fallback)
{
   int lastReason = 读取上次重载原因();
   bool restoreRuntimeSelection = (lastReason == REASON_CHARTCHANGE ||
                                   lastReason == REASON_RECOMPILE ||
                                   lastReason == REASON_CLOSE);

   // 修改老师点位等无关 input 时保留面板选择；只有参数配置模板本身变化才采用新的 input。
   if(lastReason == REASON_PARAMETERS)
   {
      string inputKey = 配置模板输入持久化Key();
      if(GlobalVariableCheck(inputKey))
      {
         int previousInput = (int)MathRound(GlobalVariableGet(inputKey));
         restoreRuntimeSelection = (配置模板值有效(previousInput) &&
                                    previousInput == (int)fallback);
      }
   }

   if(!restoreRuntimeSelection)
      return fallback;

   string key = 配置模板持久化Key();
   if(!GlobalVariableCheck(key))
      return fallback;

   int v = (int)MathRound(GlobalVariableGet(key));
   if(!配置模板值有效(v))
      return fallback;

   return (管理配置模板)v;
}

void ApplyPanelConfigTemplate(管理配置模板 tpl)
{
   PerformanceScope perfScope(PERF_TEMPLATE_SWITCH);
   if(当前参数配置模板 == tpl)
      return;

   if(NewsHedgeGroupActive())
      NewsHedgeSaveState();
   当前参数配置模板 = tpl;
   if(当前模板使用消息对冲() && !NewsHedgeGroupActive())
      NewsHedgeLoadState();
   保存当前配置模板();
   RebuildATRHandleForCurrentTemplate();
   // 先保存旧模板完整缓存，再载入目标模板；有效期与逐仓管理保持一致。
   RefreshMarketStructureCaches(false);
   // 点击先完成本地切换；下一个Tick/Timer沿原入口核对并同步真实标记订单。
   手机标记环境Dirty=true;
   lastStatus = "已切换配置: " + 配置模板名称();
   上次面板状态文本 = "";
}

void ClearPanelLines()
{
   for(int i=1; i<=48; i++)
      ObjectDelete(0, "SMA_PANEL_" + IntegerToString(i));
}

void ClearPanelLinesFrom(int startLine)
{
   for(int i=MathMax(startLine, 1); i<=48; i++)
      ObjectDelete(0, "SMA_PANEL_" + IntegerToString(i));
}

void SetPanelLineEx(string name, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   SetObjectIntegerIfChanged(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   SetObjectIntegerIfChanged(name, OBJPROP_XDISTANCE, 当前面板左边距 + 12);
   SetObjectIntegerIfChanged(name, OBJPROP_YDISTANCE, 当前面板上边距 + y);
   SetObjectIntegerIfChanged(name, OBJPROP_FONTSIZE, fontSize);
   SetObjectStringIfChanged(name, OBJPROP_FONT, 面板字体);
   SetObjectStringIfChanged(name, OBJPROP_TEXT, text);
   // 迷你/隐藏模式的标题栏只有单个按钮，不占用完整的 5 按钮顶栏。
   EnsurePanelWidthForText(text, fontSize, 0);
   SetObjectIntegerIfChanged(name, OBJPROP_COLOR, clr);
   SetObjectIntegerIfChanged(name, OBJPROP_SELECTABLE, false);
   SetObjectIntegerIfChanged(name, OBJPROP_ZORDER, 10);
}

void SetMiniPanelLine(string name, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   SetObjectIntegerIfChanged(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   SetObjectIntegerIfChanged(name, OBJPROP_XDISTANCE, 当前面板左边距 + 12);
   SetObjectIntegerIfChanged(name, OBJPROP_YDISTANCE, 当前面板上边距 + y);
   SetObjectIntegerIfChanged(name, OBJPROP_FONTSIZE, fontSize);
   SetObjectStringIfChanged(name, OBJPROP_FONT, 面板字体);
   SetObjectStringIfChanged(name, OBJPROP_TEXT, text);
   SetObjectIntegerIfChanged(name, OBJPROP_COLOR, clr);
   SetObjectIntegerIfChanged(name, OBJPROP_SELECTABLE, false);
   SetObjectIntegerIfChanged(name, OBJPROP_ZORDER, 10);
}

void DrawPanelBackgroundEx(int width, int height)
{
   当前面板高度 = MathMax(height, 40);
   ResetPanelWidthNow(MathMax(width, 230));
   string name = "SMA_PANEL_BG";
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   SetObjectIntegerIfChanged(name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   SetObjectIntegerIfChanged(name, OBJPROP_XDISTANCE, 当前面板左边距);
   SetObjectIntegerIfChanged(name, OBJPROP_YDISTANCE, 当前面板上边距);
   SetObjectIntegerIfChanged(name, OBJPROP_XSIZE, 当前面板宽度);
   SetObjectIntegerIfChanged(name, OBJPROP_YSIZE, 当前面板高度);
   SetObjectIntegerIfChanged(name, OBJPROP_BGCOLOR, PanelBackgroundColor());
   SetObjectIntegerIfChanged(name, OBJPROP_BORDER_COLOR, PanelBorderColor());
   SetObjectIntegerIfChanged(name, OBJPROP_BACK, false);
   SetObjectIntegerIfChanged(name, OBJPROP_SELECTABLE, 允许鼠标拖动面板);
   SetObjectIntegerIfChanged(name, OBJPROP_SELECTED, false);
   SetObjectIntegerIfChanged(name, OBJPROP_ZORDER, 0);
   DrawPanelChrome();
}

void ResizePanelBackgroundHeight(int height)
{
   string name = "SMA_PANEL_BG";
   if(ObjectFind(0, name) < 0)
      return;

   当前面板高度 = MathMax(height, 120);
   SetObjectIntegerIfChanged(name, OBJPROP_YSIZE, 当前面板高度);
}

void DeletePanelButtons()
{
   ObjectDelete(0, "SMA_BTN_POS");
   ObjectDelete(0, "SMA_BTN_DAY");
   ObjectDelete(0, "SMA_BTN_STAT_DAY");
   ObjectDelete(0, "SMA_BTN_STAT_WEEK");
   ObjectDelete(0, "SMA_BTN_STAT_MONTH");
   ObjectDelete(0, "SMA_BTN_PREV_DAY");
   ObjectDelete(0, "SMA_BTN_TODAY");
   ObjectDelete(0, "SMA_BTN_NEXT_DAY");
   ObjectDelete(0, "SMA_BTN_PREV_WEEK");
   ObjectDelete(0, "SMA_BTN_THIS_WEEK");
   ObjectDelete(0, "SMA_BTN_NEXT_WEEK");
   ObjectDelete(0, "SMA_BTN_PREV_MONTH");
   ObjectDelete(0, "SMA_BTN_THIS_MONTH");
   ObjectDelete(0, "SMA_BTN_NEXT_MONTH");
   DeleteLifecycleStatsButtons();
   ObjectDelete(0, "SMA_BTN_PANEL_MINI");
   ObjectDelete(0, "SMA_BTN_PANEL_FULL");
   ObjectDelete(0, "SMA_BTN_PANEL_HIDE");
   ObjectDelete(0, "SMA_BTN_VIEW_TOGGLE");
   ObjectDelete(0, "SMA_BTN_CFG_CUSTOM");
   ObjectDelete(0, "SMA_BTN_CFG_FAST");
   ObjectDelete(0, "SMA_BTN_CFG_TREND");
   ObjectDelete(0, "SMA_BTN_CFG_SRTP");
   ObjectDelete(0, "SMA_BTN_CFG_NEWS");
   ObjectDelete(0, "SMA_BTN_MARKER_VIS");
   ObjectDelete(0, "SMA_BTN_NEWS_FREEZE");
   ObjectDelete(0, "SMA_BTN_NEWS_RELEASE");
   ObjectDelete(0, "SMA_BTN_NEWS_CANCEL");
   ObjectDelete(0, "SMA_BTN_NEWS_FLAT");
   DeletePanelNavigationSurfaces();
}

void DrawCollapsedPanel()
{
   DrawPanelBackgroundEx(230, 40);
   DeletePanelNavigationSurfaces();
   SetPanelLineEx("SMA_PANEL_1", 12, "交易托管 v" + EA版本 + " · 已隐藏", PanelAccentColor(), 11);
   ClearPanelLinesFrom(2);
   CreatePanelButton("SMA_BTN_PANEL_FULL", "展开", 164, 7, 54, 25, true);
}

void DrawPanelHeaderButtons()
{
   int w = (当前面板宽度 > 0 ? 当前面板宽度 : 面板宽度);
   int bw = 46;
   int gap = 5;
   int minHeaderWidth = PanelHeaderControlWidth() + 180;
   if(w < minHeaderWidth)
   {
      当前面板宽度 = minHeaderWidth;
      ApplyPanelAutoWidth();
      w = minHeaderWidth;
   }
   // 内容文本可能在本次刷新中撑宽，标题栏也要同步延展，不能留下右侧黑边。
   DrawPanelChrome();
   int bx = w - (bw * 5 + gap * 4 + 10);
   CreatePanelButton("SMA_BTN_POS", "持仓", bx, 7, bw, 25, 当前面板页面 == 页面持仓);
   CreatePanelButton("SMA_BTN_DAY", "统计", bx + (bw + gap), 7, bw, 25, 当前面板页面 == 页面今日);
   CreatePanelButton("SMA_BTN_VIEW_TOGGLE", 当前面板信息模式 == 面板信息_简单 ? "详细" : "简洁",
                     bx + (bw + gap) * 2, 7, bw, 25, false);
   CreatePanelButton("SMA_BTN_PANEL_MINI", "迷你", bx + (bw + gap) * 3, 7, bw, 25, 当前面板显示模式 == 面板迷你);
   CreatePanelButton("SMA_BTN_PANEL_HIDE", "隐藏", bx + (bw + gap) * 4, 7, bw, 25, false);
}

string FormatNearestSRLine(double midPrice)
{
   string r = "R1 -";
   string sp = "S1 -";
   if(ArraySize(缓存压力位) > 0)
      r = StringFormat("R1 %.2f 距+%.2f", 缓存压力位[0].price, 缓存压力位[0].price - midPrice);
   if(ArraySize(缓存支撑位) > 0)
      sp = StringFormat("S1 %.2f 距%.2f", 缓存支撑位[0].price, 缓存支撑位[0].price - midPrice);
   return r + " | " + sp;
}

void DrawMiniPanel(double bid, double ask, double spread, color spreadColor, double midPrice)
{
   int miniW = (迷你面板宽度 > 390 ? 迷你面板宽度 : 390);
   DrawPanelBackgroundEx(miniW, 154);
   DeletePanelNavigationSurfaces();

   int bw = 46;
   int gap = 5;
   int bx = miniW - (bw * 4 + gap * 3 + 10);
   CreatePanelButton("SMA_BTN_POS", "持仓", bx, 7, bw, 25, false);
   CreatePanelButton("SMA_BTN_DAY", "统计", bx + (bw + gap), 7, bw, 25, false);
   CreatePanelButton("SMA_BTN_PANEL_FULL", "展开", bx + (bw + gap) * 2, 7, bw, 25, true);
   CreatePanelButton("SMA_BTN_PANEL_HIDE", "隐藏", bx + (bw + gap) * 3, 7, bw, 25, false);

   int managed=0, buyCount=0, sellCount=0;
   int slCount=0, tpCount=0, protectedCount=0, noSLCount=0, lossWarnCount=0;
   double buyLots=0, sellLots=0, buyPV=0.0, sellPV=0.0, floatingProfit=0.0, maxProfitPrice=0.0;
   double maxProfitDrawdownRatio = -1.0;
   string riskText = "[空] 无持仓";
   color riskColor = clrSilver;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!PositionInScope()) continue;
      managed++;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      floatingProfit += profit;
      if(sl > 0) slCount++; else noSLCount++;
      if(tp > 0) tpCount++;
      if(profit < 0.0 && MathAbs(profit) >= 持仓页浮亏预警金额) lossWarnCount++;

      double profitPrice = (type == POSITION_TYPE_BUY) ? (bid - openPrice) : (openPrice - ask);
      if(profitPrice > maxProfitPrice) maxProfitPrice = profitPrice;
      int stateIdx = FindState((ulong)PositionGetInteger(POSITION_TICKET));
      if(stateIdx >= 0 && states[stateIdx].maxProfitPrice > 0.0)
      {
         double ddRatio = (states[stateIdx].maxProfitPrice - profitPrice) / states[stateIdx].maxProfitPrice;
         if(ddRatio > maxProfitDrawdownRatio) maxProfitDrawdownRatio = ddRatio;
      }
      if(sl > 0)
      {
         if(type == POSITION_TYPE_BUY && sl >= openPrice) protectedCount++;
         if(type == POSITION_TYPE_SELL && sl <= openPrice) protectedCount++;
      }
      if(type == POSITION_TYPE_BUY) { buyCount++; buyLots += volume; buyPV += openPrice * volume; }
      if(type == POSITION_TYPE_SELL) { sellCount++; sellLots += volume; sellPV += openPrice * volume; }
   }

   if(managed > 0)
   {
      riskText = "[等] 待保护";
      riskColor = clrWhite;
      if(noSLCount > 0) { riskText = "[危] 无SL"; riskColor = LegacyDangerColor(); }
      else if(lossWarnCount > 0) { riskText = "[危] 浮亏"; riskColor = LegacyDangerColor(); }
      else if(protectedCount == managed) { riskText = "[安] 已保护"; riskColor = LegacySafeColor(); }
   }

   string ddText = (maxProfitDrawdownRatio >= 0.0) ?
      StringFormat("%.0f%%/%.0f%%", maxProfitDrawdownRatio * 100.0, 最大浮盈回撤比例 * 100.0) :
      "-";
   color profitColor = floatingProfit > 0.005 ? LegacyProfitColor() : (floatingProfit < -0.005 ? LegacyLossColor() : LegacyFlatColor());
   color topColor = (spreadColor == LegacyDangerColor() ? LegacyDangerColor() : riskColor);
   double buyAvg = (buyLots > 0.0) ? buyPV / buyLots : 0.0;
   double sellAvg = (sellLots > 0.0) ? sellPV / sellLots : 0.0;
   color miniTPColor = clrSilver;
   string miniTPAdviceText = FormatShortLineTPAdviceText(buyCount, buyAvg, sellCount, sellAvg, bid, ask, miniTPColor);

   // 迷你面板右侧有按钮，标题必须短，避免和按钮互相盖住。
   SetMiniPanelLine("SMA_PANEL_1", 12, StringFormat("%s  ·  %s", _Symbol, managed > 0 ? "托管中" : "空仓"), topColor, 11);
   SetMiniPanelLine("SMA_PANEL_2", 40, StringFormat("浮盈 %s | 回撤 %s | 最大距 %.2f", FormatMiniSignedProfit(floatingProfit,2), ddText, maxProfitPrice), profitColor, 迷你面板字体大小);
   SetMiniPanelLine("SMA_PANEL_3", 40 + 面板行距, StringFormat("风险: %s | SL %d/%d | TP %d/%d", riskText, slCount, managed, tpCount, managed), riskColor, 迷你面板字体大小);
   SetMiniPanelLine("SMA_PANEL_4", 40 + 面板行距*2, StringFormat("持仓 %d | 多%d %.2f | 空%d %.2f", managed, buyCount, buyLots, sellCount, sellLots), clrWhite, 迷你面板字体大小);
   SetMiniPanelLine("SMA_PANEL_5", 40 + 面板行距*3, FormatSRMiniLine(缓存压力位, true, midPrice), clrTomato, 迷你面板字体大小);
   SetMiniPanelLine("SMA_PANEL_6", 40 + 面板行距*4, FormatSRMiniLine(缓存支撑位, false, midPrice), clrLime, 迷你面板字体大小);
   if(当前是短线单模板() && managed > 0 && 短线单显示推荐止盈点位)
      SetMiniPanelLine("SMA_PANEL_7", 40 + 面板行距*5, miniTPAdviceText, miniTPColor, 迷你面板字体大小);
   else
      SetMiniPanelLine("SMA_PANEL_7", 40 + 面板行距*5, "状态: " + lastStatus, clrYellow, 迷你面板字体大小);
   ClearPanelLinesFrom(8);
   ResizePanelBackgroundHeight(40 + 面板行距 * 6 + 12);

   int finalW = miniW;
   当前面板宽度 = miniW;
   ApplyPanelAutoWidth();
   bx = finalW - (bw * 4 + gap * 3 + 10);
   CreatePanelButton("SMA_BTN_POS", "持仓", bx, 7, bw, 25, false);
   CreatePanelButton("SMA_BTN_DAY", "统计", bx + (bw + gap), 7, bw, 25, false);
   CreatePanelButton("SMA_BTN_PANEL_FULL", "展开", bx + (bw + gap) * 2, 7, bw, 25, true);
   CreatePanelButton("SMA_BTN_PANEL_HIDE", "隐藏", bx + (bw + gap) * 3, 7, bw, 25, false);
}

string FormatHeldMinutes(int minutes)
{
   if(minutes < 0) minutes = 0;
   int h = minutes / 60;
   int m = minutes % 60;
   if(h > 0) return StringFormat("%dh%02dm", h, m);
   return StringFormat("%dm", m);
}

string FormatTriggerNeed(double need, bool triggered)
{
   if(triggered) return "已触发";
   if(need < 0.0) return "-";
   return DoubleToString(need, 2);
}

string FormatSignedPrice(double value)
{
   if(value > 0.0) return "+" + DoubleToString(value, 2);
   return DoubleToString(value, 2);
}

string FormatMarkerSafetyText()
{
   if(!启用手机标记挂单) return "手机标记: 配置关闭";
   if(!手机标记挂单面板开关) return "手机标记: 面板已关闭";
   return "手机标记: 真挂单 | " + 手机标记状态;
}

int HoldingPanelY(int panelLine)
{
   // 模板栏下方保留提示挂单开关；消息模板另有一排消息操作按钮。
   int baseY = 当前模板使用消息对冲() ? 132 : 102;
   return baseY + 面板行距 * (panelLine - 2);
}

string FormatBJDate(datetime bjTime)
{
   MqlDateTime dt;
   TimeToStruct(bjTime, dt);
   return StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day);
}

datetime ConvertServerTimeToBeijing(datetime serverTime)
{
   if(serverTime <= 0) return 0;
   datetime tradeServerNow = TimeTradeServer();
   if(tradeServerNow <= 0) tradeServerNow = TimeCurrent();
   datetime gmtNow = TimeGMT();
   int serverOffset = (int)(tradeServerNow - gmtNow);
   datetime gmtTime = serverTime - serverOffset;
   return gmtTime + 北京UTC偏移小时 * 3600;
}

string FormatBeijingTime(datetime serverTime)
{
   datetime bjTime = ConvertServerTimeToBeijing(serverTime);
   return bjTime > 0 ? TimeToString(bjTime, TIME_DATE|TIME_MINUTES) : "--";
}

string FormatBeijingTimeCompact(datetime serverTime)
{
   datetime bjTime = ConvertServerTimeToBeijing(serverTime);
   MqlDateTime value;
   if(bjTime <= 0 || !TimeToStruct(bjTime, value)) return "--";
   return StringFormat("%02d.%02d %02d:%02d", value.mon, value.day, value.hour, value.min);
}

datetime GetBJTodayZero()
{
   datetime nowBj = TimeGMT() + 北京UTC偏移小时 * 3600;
   MqlDateTime dt;
   TimeToStruct(nowBj, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

datetime GetBJDayZero(datetime bjTime)
{
   MqlDateTime dt;
   TimeToStruct(bjTime, dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

datetime GetBJMonday(datetime bjDate)
{
   datetime dayZero = GetBJDayZero(bjDate);
   MqlDateTime dt;
   TimeToStruct(dayZero, dt);
   int dow = dt.day_of_week; // 0=Sunday, 1=Monday, ... 6=Saturday
   int backDays = (dow == 0) ? 6 : (dow - 1);
   return dayZero - backDays * 86400;
}

datetime GetBJMonthStart(datetime bjDate)
{
   MqlDateTime dt;
   TimeToStruct(GetBJDayZero(bjDate), dt);
   dt.day = 1;
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

datetime AddBJMonths(datetime bjMonthStart, int monthOffset)
{
   MqlDateTime dt;
   TimeToStruct(GetBJMonthStart(bjMonthStart), dt);

   int totalMonths = dt.year * 12 + (dt.mon - 1) + monthOffset;
   int newYear = totalMonths / 12;
   int newMonth = totalMonths % 12 + 1;

   dt.year = newYear;
   dt.mon = newMonth;
   dt.day = 1;
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   return StructToTime(dt);
}

void GetBeijingRangeServerRange(datetime bjStart, datetime bjEnd, datetime &serverStart, datetime &serverEnd)
{
   datetime tradeServerNow = TimeTradeServer();
   if(tradeServerNow <= 0) tradeServerNow = TimeCurrent();
   int serverOffset = (int)(tradeServerNow - TimeGMT());
   serverStart = (bjStart - 北京UTC偏移小时 * 3600) + serverOffset;
   serverEnd   = (bjEnd   - 北京UTC偏移小时 * 3600) + serverOffset;
}

void GetBeijingDayServerRange(int dayOffset, datetime &serverStart, datetime &serverEnd, datetime &bjDate)
{
   bjDate = GetBJTodayZero() + dayOffset * 86400;
   GetBeijingRangeServerRange(bjDate, bjDate + 86400, serverStart, serverEnd);
}

bool FindEntryInCache(ulong positionId, EntryDealStat &entries[], double &entryPrice, ENUM_DEAL_TYPE &entryType, datetime &entryTime)
{
   entryPrice = 0.0;
   entryTime = 0;
   datetime bestTime = 0;
   bool found = false;

   for(int i=0; i<ArraySize(entries); i++)
   {
      if(entries[i].positionId != positionId) continue;
      if(!found || entries[i].time < bestTime)
      {
         entryPrice = entries[i].price;
         entryType = entries[i].type;
         entryTime = entries[i].time;
         bestTime = entries[i].time;
         found = true;
      }
   }
   return (found && entryPrice > 0.0);
}

bool FindPositionEntry(ulong positionId, double &entryPrice, ENUM_DEAL_TYPE &entryType)
{
   entryPrice = 0.0;
   int total = HistoryDealsTotal();
   for(int i=0; i<total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID) != positionId) continue;
      if((int)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;

      entryPrice = HistoryDealGetDouble(deal, DEAL_PRICE);
      entryType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
      return (entryPrice > 0);
   }
   return false;
}

void SortCloseDealsByTime(CloseDealStat &arr[])
{
   int n = ArraySize(arr);
   for(int i=1; i<n; i++)
   {
      CloseDealStat key = arr[i];
      int j = i - 1;
      while(j >= 0 && arr[j].time > key.time)
      {
         arr[j + 1] = arr[j];
         j--;
      }
      arr[j + 1] = key;
   }
}

void CalculateStatsByBJRange(datetime bjStart, datetime bjEnd, TodayStats &st)
{
   ZeroMemory(st);
   st.bjDate = bjStart;
   GetBeijingRangeServerRange(bjStart, bjEnd, st.bjStartServer, st.bjEndServer);

   // 为了计算跨日/跨周持仓的点数，向前额外选 30 天找入场成交。
   // 只 HistorySelect 一次，并用缓存数组匹配入场价，避免每个平仓成交都重复遍历历史导致卡顿。
   datetime searchStart = st.bjStartServer - 30 * 86400;
   if(!HistorySelect(searchStart, st.bjEndServer))
      return;

   EntryDealStat entries[];
   CloseDealStat closeDeals[];
   int total = HistoryDealsTotal();
   // 预分配，避免历史成交较多时循环内反复ArrayResize造成卡顿。
   ArrayResize(entries, total);
   ArrayResize(closeDeals, total);
   int entryCount = 0;
   int closeCount = 0;

   for(int i=0; i<total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      if(!DealInScope(deal)) continue;

      datetime dealTime = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      int entry = (int)HistoryDealGetInteger(deal, DEAL_ENTRY);
      ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;

      if(entry == DEAL_ENTRY_IN)
      {
         ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
         int en = entryCount++;
         entries[en].positionId = positionId;
         entries[en].time = dealTime;
         entries[en].price = HistoryDealGetDouble(deal, DEAL_PRICE);
         entries[en].type = dealType;

         if(dealTime >= st.bjStartServer && dealTime < st.bjEndServer)
         {
            st.entries++;
            st.lots += HistoryDealGetDouble(deal, DEAL_VOLUME);
         }
         continue;
      }

      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;
      if(dealTime < st.bjStartServer || dealTime >= st.bjEndServer) continue;

      double p = HistoryDealGetDouble(deal, DEAL_PROFIT)
               + HistoryDealGetDouble(deal, DEAL_SWAP)
               + HistoryDealGetDouble(deal, DEAL_COMMISSION);

      ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      double entryPrice = 0.0;
      ENUM_DEAL_TYPE openType = DEAL_TYPE_BUY;
      datetime entryTime = 0;
      double dealPoints = 0.0;
      double dealPriceDiff = 0.0;
      double holdMinutes = 0.0;
      if(FindEntryInCache(positionId, entries, entryPrice, openType, entryTime))
      {
         double exitPrice = HistoryDealGetDouble(deal, DEAL_PRICE);
         if(openType == DEAL_TYPE_BUY)
            dealPriceDiff = exitPrice - entryPrice;
         else if(openType == DEAL_TYPE_SELL)
            dealPriceDiff = entryPrice - exitPrice;

         // MT5点数按最小报价单位_Point计算；价格差保留交易者直观看到的黄金价格波动。
         if(_Point > 0.0)
            dealPoints = dealPriceDiff / _Point;
         if(entryTime > 0 && dealTime > entryTime)
            holdMinutes = (double)(dealTime - entryTime) / 60.0;
      }

      int n = closeCount++;
      closeDeals[n].deal = deal;
      closeDeals[n].time = dealTime;
      closeDeals[n].profit = p;
      closeDeals[n].points = dealPoints;
      closeDeals[n].priceDiff = dealPriceDiff;
      closeDeals[n].volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
      closeDeals[n].holdMinutes = holdMinutes;
      closeDeals[n].openType = openType;
   }

   ArrayResize(entries, entryCount);
   ArrayResize(closeDeals, closeCount);
   SortCloseDealsByTime(closeDeals);

   double cumProfit = 0.0;
   double winSum = 0.0;
   double lossSum = 0.0;

   for(int i=0; i<ArraySize(closeDeals); i++)
   {
      double p = closeDeals[i].profit;
      st.profit += p;
      st.points += closeDeals[i].points;
      st.priceDiff += closeDeals[i].priceDiff;
      st.closes++;
      st.closeLots += closeDeals[i].volume;
      st.totalHoldMinutes += closeDeals[i].holdMinutes;
      if(closeDeals[i].holdMinutes > st.maxHoldMinutes)
         st.maxHoldMinutes = closeDeals[i].holdMinutes;
      if(closeDeals[i].openType == DEAL_TYPE_BUY)
      {
         st.buyCloses++;
         st.buyProfit += p;
      }
      else if(closeDeals[i].openType == DEAL_TYPE_SELL)
      {
         st.sellCloses++;
         st.sellProfit += p;
      }

      if(st.closes == 1 || p > st.bestProfit) st.bestProfit = p;
      if(st.closes == 1 || p < st.worstProfit) st.worstProfit = p;

      if(p > 0)
      {
         st.wins++;
         st.grossProfit += p;
         winSum += p;
         st.currentLossStreak = 0;
      }
      else if(p < 0)
      {
         st.losses++;
         st.grossLoss += p; // 存负数，显示更直观。
         lossSum += p;
         st.currentLossStreak++;
         if(st.currentLossStreak > st.maxLossStreak)
            st.maxLossStreak = st.currentLossStreak;
      }
      else
      {
         st.breakevens++;
      }

      // 已实现盈亏曲线回撤，不包含当前浮盈浮亏。
      cumProfit += p;
      if(st.closes == 1 || cumProfit > st.realizedEquityPeak)
         st.realizedEquityPeak = cumProfit;
      double dd = st.realizedEquityPeak - cumProfit;
      if(dd > st.maxRealizedDrawdown)
         st.maxRealizedDrawdown = dd;
   }

   st.avgWin = (st.wins > 0) ? winSum / st.wins : 0.0;
   st.avgLoss = (st.losses > 0) ? lossSum / st.losses : 0.0;
   st.profitFactor = (MathAbs(st.grossLoss) > 0.0) ? st.grossProfit / MathAbs(st.grossLoss) : 0.0;
   st.payoffRatio = (MathAbs(st.avgLoss) > 0.0 && st.avgWin > 0.0) ? st.avgWin / MathAbs(st.avgLoss) : 0.0;
}

void CalculateTodayStats(TodayStats &st)
{
   datetime bjStart = GetBJTodayZero() + 统计日期偏移天数 * 86400;
   CalculateStatsByBJRange(bjStart, bjStart + 86400, st);
}

void CalculateWeekStats(TodayStats &st)
{
   datetime thisMonday = GetBJMonday(GetBJTodayZero());
   datetime bjStart = thisMonday + 统计周偏移周数 * 7 * 86400;
   // 周统计固定为北京时间周一 00:00 到周六 00:00，即周一至周五。
   CalculateStatsByBJRange(bjStart, bjStart + 5 * 86400, st);
}

void CalculateMonthStats(TodayStats &st)
{
   datetime thisMonth = GetBJMonthStart(GetBJTodayZero());
   datetime bjStart = AddBJMonths(thisMonth, 统计月偏移月数);
   datetime bjEnd = AddBJMonths(bjStart, 1);
   CalculateStatsByBJRange(bjStart, bjEnd, st);
}

void InvalidateStatsCache(bool preserveCompletedLifecycleTrades=false)
{
   统计缓存有效 = false;
   今日纪律缓存有效 = false;
   InvalidateLifecycleStatsCache(preserveCompletedLifecycleTrades);
   // UI 复盘缓存与业务统计缓存使用同一失效入口，但不改变统计口径。
   InvalidateCanvasReviewCache();
   CanvasTrendCacheValid=false;
   ArrayResize(CanvasTrendCache.points,0);
   CanvasStatsModelValid=false;
   CanvasStatsTradeGeneration++;
}

void GetCurrentStats(TodayStats &st)
{
   datetime now = TimeCurrent();
   if(统计缓存有效 &&
      缓存统计周期 == (int)当前统计周期 &&
      缓存日偏移 == 统计日期偏移天数 &&
      缓存周偏移 == 统计周偏移周数 &&
      缓存月偏移 == 统计月偏移月数 &&
      now - 统计缓存时间 <= 10)
   {
      st = 缓存统计;
      return;
   }

   if(当前统计周期 == 统计_日)
      CalculateTodayStats(st);
   else if(当前统计周期 == 统计_周)
      CalculateWeekStats(st);
   else
      CalculateMonthStats(st);

   缓存统计 = st;
   统计缓存有效 = true;
   统计缓存时间 = now;
   缓存统计周期 = (int)当前统计周期;
   缓存日偏移 = 统计日期偏移天数;
   缓存周偏移 = 统计周偏移周数;
   缓存月偏移 = 统计月偏移月数;
}

void GetTodayDisciplineStats(TodayStats &st)
{
   datetime now = TimeCurrent();
   if(今日纪律缓存有效 && now - 今日纪律缓存时间 <= 10)
   {
      st = 今日纪律缓存;
      return;
   }

   datetime bjStart = GetBJTodayZero();
   CalculateStatsByBJRange(bjStart, bjStart + 86400, st);
   今日纪律缓存 = st;
   今日纪律缓存有效 = true;
   今日纪律缓存时间 = now;
}

string LifecycleStatsFilterText()
{
   if(当前统计筛选 == 统计筛选_短线) return "短线";
   if(当前统计筛选 == 统计筛选_趋势) return "长线";
   if(当前统计筛选 == 统计筛选_普通) return "手动";
   if(当前统计筛选 == 统计筛选_消息) return "消息";
   return "全部";
}

string LifecycleStatsPeriodText()
{
   if(当前统计周期 == 统计_周) return "周统计";
   if(当前统计周期 == 统计_月) return "月统计";
   return "日统计";
}

string LifecycleStatsArchetypeText(int archetype)
{
   if(archetype == 短线类型_箱体反转) return "箱体反转";
   if(archetype == 短线类型_箱体突破) return "箱体突破";
   if(archetype == 短线类型_趋势回踩) return "趋势回踩";
   if(archetype == 短线类型_扫损接回) return "扫损接回";
   if(archetype == 短线类型_普通手动) return "普通手动";
   return "类型未知";
}

string LifecycleStatsSampleText(int trades)
{
   if(trades < 10) return "样本不足";
   if(trades < 30) return "仅供观察";
   return "样本可用";
}

string LifecycleStatsSignedMoney(double value)
{
   if(value > 0.005) return "+"+DoubleToString(value, 2);
   if(value < -0.005) return DoubleToString(value, 2);
   return "0.00";
}

string LifecycleStatsSignedR(double value)
{
   if(value > 0.005) return "+"+DoubleToString(value, 2)+"R";
   if(value < -0.005) return DoubleToString(value, 2)+"R";
   return "0.00R";
}

color LegacyProfitColor() { return C'255,122,89'; }
color LegacyLossColor()   { return C'77,163,255'; }
color LegacyFlatColor()   { return clrSilver; }
color LegacySafeColor()   { return C'105,221,210'; }
color LegacyDangerColor() { return C'240,98,146'; }

color LifecycleStatsResultColor(double value)
{
   if(value > 0.005) return LegacyProfitColor();
   if(value < -0.005) return LegacyLossColor();
   return LegacyFlatColor();
}

void GetLifecycleStatsInsight(const LifecycleStats &st, string &text, color &clr)
{
   if(st.trades == 0)
   {
      text = "暂无已完成交易，等平仓后再看结果";
      clr = clrSilver;
      return;
   }
   if(st.trades < 10)
   {
      text = "交易还不多，先按计划做，别急着因为几笔结果改变方法";
      clr = clrOrange;
      return;
   }
   if(st.currentLossStreak >= 3)
   {
      text = "连续亏损偏多，建议降低频率，等下一次明确机会";
      clr = LegacyDangerColor();
      return;
   }
   if(st.netProfit < -0.005 || (st.profitFactor > 0.0 && st.profitFactor < 1.0))
   {
      text = "当前结果不占优，优先控制风险，不要用加频率追回亏损";
      clr = clrOrange;
      return;
   }
   if(st.profitFactor >= 1.30)
   {
      text = "当前结果健康，继续按原来的风险和节奏执行";
      clr = LegacySafeColor();
      return;
   }
   text = "结果接近平衡，保持原计划，继续观察而不是急着调整";
   clr = clrSilver;
}

string LifecycleReviewDirectionText(int direction)
{
   if(direction == POSITION_TYPE_BUY) return "多单";
   if(direction == POSITION_TYPE_SELL) return "空单";
   return "方向未知";
}

string LifecycleReviewExitIntentText(int intent)
{
   if(intent == 退出意图_固定TP) return "固定止盈";
   if(intent == 退出意图_SL) return "止损离场";
   if(intent == 退出意图_分批止盈) return "分批止盈";
   if(intent == 退出意图_二级支压全收) return "支撑压力全收";
   if(intent == 退出意图_回本退出) return "回本快收";
   if(intent == 退出意图_紧急风控) return "紧急风控";
   if(intent == 退出意图_超时退出) return "超时退出";
   if(intent == 退出意图_手动关闭) return "手动关闭";
   if(intent == 退出意图_消息对冲) return "消息对冲";
   if(intent == 退出意图_尾仓快速退出) return "尾仓快速退出";
   return "未记录";
}

string LifecycleReviewActualExitText(long reason)
{
   if(reason == DEAL_REASON_SL) return "服务器止损";
   if(reason == DEAL_REASON_TP) return "服务器止盈";
   if(reason == DEAL_REASON_EXPERT) return "EA执行";
   if(reason == DEAL_REASON_CLIENT || reason == DEAL_REASON_MOBILE || reason == DEAL_REASON_WEB) return "手动操作";
   if(reason == DEAL_REASON_SO) return "强制平仓";
   return reason > 0 ? "其他服务器原因" : "未记录";
}

string LifecycleReviewRunnerText(int runnerMode)
{
   if(runnerMode == 短线尾仓_结构追踪) return "结构追踪";
   if(runnerMode == 短线尾仓_箱体目标) return "箱体目标";
   if(runnerMode == 短线尾仓_快速退出) return "快速退出";
   return "固定目标";
}

string FormatReviewDuration(double seconds)
{
   long totalSeconds=(long)MathRound(MathMax(seconds,0.0));
   if(totalSeconds<60) return StringFormat("%d秒",(int)totalSeconds);
   long totalMinutes=totalSeconds/60;
   int remainingSeconds=(int)(totalSeconds%60);
   if(totalMinutes<60)
      return remainingSeconds>0 ? StringFormat("%d分%d秒",(int)totalMinutes,remainingSeconds) :
                                  StringFormat("%d分",(int)totalMinutes);
   long totalHours=totalMinutes/60;
   int remainingMinutes=(int)(totalMinutes%60);
   if(totalHours<24)
      return remainingMinutes>0 ? StringFormat("%d小时%02d分",(int)totalHours,remainingMinutes) :
                                  StringFormat("%d小时",(int)totalHours);
   long days=totalHours/24;
   int remainingHours=(int)(totalHours%24);
   return remainingHours>0 ? StringFormat("%d天%02d小时",(int)days,remainingHours) :
                             StringFormat("%d天",(int)days);
}

string FormatReviewDurationWithRatio(double seconds,double observedSeconds)
{
   if(observedSeconds<=0.0) return "未记录";
   int ratio=(int)MathRound(100.0*MathMax(seconds,0.0)/observedSeconds);
   ratio=MathMax(0,MathMin(ratio,100));
   return FormatReviewDuration(seconds)+" · "+IntegerToString(ratio)+"%";
}

string FormatFirstProfitTiming(const LifecycleReviewItem &item)
{
   if(!item.floatingTimingHasData || item.floatingTimingObservedSeconds<=0.0) return "未记录";
   if(item.firstFloatingProfitTime<=0) return "未观测浮盈";
   bool adoptedMidway=(item.openTime>0 && item.floatingTimingObservationStartTime>item.openTime+2);
   if(adoptedMidway)
   {
      if(item.firstFloatingProfitTime<=item.floatingTimingObservationStartTime+2) return "接管时已盈";
      return "接管后 "+FormatReviewDuration((double)(item.firstFloatingProfitTime-item.floatingTimingObservationStartTime));
   }
   return FormatReviewDuration((double)MathMax((long)(item.firstFloatingProfitTime-item.openTime),0));
}

void PrefixLifecycleReviewTimingCoverage(const LifecycleReviewItem &item,string &text)
{
   if(!item.floatingTimingHasData || item.floatingTimingObservedSeconds<=0.0)
   {
      text="时长数据未记录；"+text;
      return;
   }
   if(item.floatingTimingCoverageRatio>0.0 && item.floatingTimingCoverageRatio<0.95)
   {
      int coverage=(int)MathRound(item.floatingTimingCoverageRatio*100.0);
      text=StringFormat("盈亏时长覆盖%d%%，未观测时段未计入；%s",coverage,text);
   }
}

void GetLifecycleReviewInsight(const LifecycleReviewItem &item, string &text, color &clr)
{
   if(item.initialRMoney <= 0.0)
   {
      text = "风险记录不完整，本单只看实际盈亏和管理经过";
      clr = clrOrange;
      return;
   }
   if(item.net > 0.005 && item.captureRatio >= 0.65)
   {
      text = "盈利拿住较好：实际结果保留了大部分已记录浮盈";
      clr = LegacySafeColor();
      return;
   }
   if(item.net > 0.005 && item.captureRatio > 0.0 && item.captureRatio < 0.35)
   {
      text = "本单盈利，但从最高浮盈回吐较多，可回看保护和离场时机";
      clr = clrOrange;
      return;
   }
   if(item.net < -0.005 && item.maxProfitMoney > 0.005)
   {
      text = "曾转为盈利后仍收亏，可回看保本和分批是否过晚";
      clr = clrOrange;
      return;
   }
   text = item.net > 0.005 ? "本单盈利，结合进场和离场过程继续复盘" : "本单亏损，重点回看入场环境和初始风险";
   clr = LifecycleStatsResultColor(item.net);
}

void DeleteLifecycleStatsButtons()
{
   string names[] = {"SMA_BTN_FILTER_SHORT","SMA_BTN_FILTER_ALL","SMA_BTN_FILTER_TREND","SMA_BTN_FILTER_NORMAL","SMA_BTN_FILTER_NEWS",
                     "SMA_BTN_DETAIL_OVERVIEW","SMA_BTN_DETAIL_STRATEGY","SMA_BTN_DETAIL_MANAGE","SMA_BTN_DETAIL_EXEC","SMA_BTN_DETAIL_REVIEW",
                     "SMA_BTN_REVIEW_PREV","SMA_BTN_REVIEW_NEXT"};
   for(int i=0; i<ArraySize(names); i++) ObjectDelete(0, names[i]);
}

void DrawLifecycleStatsNavigation()
{
   ObjectDelete(0, "SMA_UI_TEMPLATE_NAV");
   int navWidth = MathMax(当前面板宽度-16, 350);
   DrawPanelSurface("SMA_UI_STATS_NAV", 8, 38, navWidth, 106, C'20,31,46', PanelBorderColor(), 2);
   CreatePanelButton("SMA_BTN_STAT_DAY", "日统计", 12, 40, 64, 22, 当前统计周期 == 统计_日);
   CreatePanelButton("SMA_BTN_STAT_WEEK", "周统计", 82, 40, 64, 22, 当前统计周期 == 统计_周);
   CreatePanelButton("SMA_BTN_STAT_MONTH", "月统计", 152, 40, 64, 22, 当前统计周期 == 统计_月);

   if(当前统计周期 == 统计_日)
   {
      CreatePanelButton("SMA_BTN_PREV_DAY", "前一天", 12, 66, 64, 22, false);
      CreatePanelButton("SMA_BTN_TODAY", "今日", 82, 66, 52, 22, 统计日期偏移天数 == 0);
      CreatePanelButton("SMA_BTN_NEXT_DAY", "后一天", 140, 66, 64, 22, false);
      ObjectDelete(0, "SMA_BTN_PREV_WEEK"); ObjectDelete(0, "SMA_BTN_THIS_WEEK"); ObjectDelete(0, "SMA_BTN_NEXT_WEEK");
      ObjectDelete(0, "SMA_BTN_PREV_MONTH"); ObjectDelete(0, "SMA_BTN_THIS_MONTH"); ObjectDelete(0, "SMA_BTN_NEXT_MONTH");
   }
   else if(当前统计周期 == 统计_周)
   {
      CreatePanelButton("SMA_BTN_PREV_WEEK", "前一周", 12, 66, 64, 22, false);
      CreatePanelButton("SMA_BTN_THIS_WEEK", "本周", 82, 66, 52, 22, 统计周偏移周数 == 0);
      CreatePanelButton("SMA_BTN_NEXT_WEEK", "后一周", 140, 66, 64, 22, false);
      ObjectDelete(0, "SMA_BTN_PREV_DAY"); ObjectDelete(0, "SMA_BTN_TODAY"); ObjectDelete(0, "SMA_BTN_NEXT_DAY");
      ObjectDelete(0, "SMA_BTN_PREV_MONTH"); ObjectDelete(0, "SMA_BTN_THIS_MONTH"); ObjectDelete(0, "SMA_BTN_NEXT_MONTH");
   }
   else
   {
      CreatePanelButton("SMA_BTN_PREV_MONTH", "前月", 12, 66, 52, 22, false);
      CreatePanelButton("SMA_BTN_THIS_MONTH", "本月", 70, 66, 52, 22, 统计月偏移月数 == 0);
      CreatePanelButton("SMA_BTN_NEXT_MONTH", "后月", 128, 66, 52, 22, false);
      ObjectDelete(0, "SMA_BTN_PREV_DAY"); ObjectDelete(0, "SMA_BTN_TODAY"); ObjectDelete(0, "SMA_BTN_NEXT_DAY");
      ObjectDelete(0, "SMA_BTN_PREV_WEEK"); ObjectDelete(0, "SMA_BTN_THIS_WEEK"); ObjectDelete(0, "SMA_BTN_NEXT_WEEK");
   }

   CreatePanelButton("SMA_BTN_FILTER_ALL", "全部", 12, 94, 52, 22, 当前统计筛选 == 统计筛选_全部);
   CreatePanelButton("SMA_BTN_FILTER_SHORT", "短线", 68, 94, 52, 22, 当前统计筛选 == 统计筛选_短线);
   CreatePanelButton("SMA_BTN_FILTER_TREND", "长线", 124, 94, 52, 22, 当前统计筛选 == 统计筛选_趋势);
   CreatePanelButton("SMA_BTN_FILTER_NEWS", "消息", 180, 94, 52, 22, 当前统计筛选 == 统计筛选_消息);
   CreatePanelButton("SMA_BTN_FILTER_NORMAL", "手动", 236, 94, 52, 22, 当前统计筛选 == 统计筛选_普通);

   CreatePanelButton("SMA_BTN_DETAIL_OVERVIEW", "总览", 12, 120, 62, 22, 当前统计详情 == 统计详情_总览);
   CreatePanelButton("SMA_BTN_DETAIL_STRATEGY", "表现", 78, 120, 62, 22, 当前统计详情 == 统计详情_策略);
   CreatePanelButton("SMA_BTN_DETAIL_MANAGE", "管理", 144, 120, 62, 22, 当前统计详情 == 统计详情_管理);
   CreatePanelButton("SMA_BTN_DETAIL_EXEC", "执行", 210, 120, 62, 22, 当前统计详情 == 统计详情_执行);
   CreatePanelButton("SMA_BTN_DETAIL_REVIEW", "复盘", 276, 120, 62, 22, 当前统计详情 == 统计详情_复盘);
   if(当前统计详情 != 统计详情_复盘)
   {
      ObjectDelete(0, "SMA_BTN_REVIEW_PREV");
      ObjectDelete(0, "SMA_BTN_REVIEW_NEXT");
   }
}

void DrawLifecycleStatisticsPage(double spread, color spreadColor)
{
   LifecycleStats st;
   GetCurrentLifecycleStats(st);
   string periodText = LifecycleStatsPeriodText();
   string rangeText = FormatBJDate(st.bjDate);
   if(当前统计周期 == 统计_周) rangeText += "-"+FormatBJDate(st.bjDate+4*86400);
   else if(当前统计周期 == 统计_月) rangeText += "-"+FormatBJDate(AddBJMonths(st.bjDate,1)-86400);

   // 筛选和周期已由下方高亮按钮表达；标题只保留页面身份，避免与右侧顶栏竞争宽度。
   SetPanelLine("SMA_PANEL_1", 12, StringFormat("%s  ·  交易统计", _Symbol), clrAqua);
   DrawLifecycleStatsNavigation();

   int line=2;
   int y0=当前统计详情 == 统计详情_复盘 ? 178 : 150;
   double winRate = st.trades > 0 ? 100.0*st.wins/st.trades : 0.0;
   double avgNet = st.trades > 0 ? st.netProfit/st.trades : 0.0;
   double avgR = st.riskKnownTrades > 0 ? st.totalRealizedR/st.riskKnownTrades : 0.0;
   double avgHold = st.trades > 0 ? st.totalHoldMinutes/st.trades : 0.0;
   double totalCost = st.commission+st.swap+st.fee;
   string pf = st.profitFactor > 0.0 ? DoubleToString(st.profitFactor,2) : "-";
   color profitColor = LifecycleStatsResultColor(st.netProfit);
   color sampleColor = st.trades < 10 ? clrOrange : (st.trades < 30 ? clrSilver : LegacySafeColor());
   string insight;
   color insightColor;
   GetLifecycleStatsInsight(st, insight, insightColor);

   SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2),
                StringFormat("周期: %s | %s | 北京时间", rangeText, FormatSpreadText(spread)), spreadColor); line++;
   SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2),
                StringFormat("已完成 %d 笔 | 胜/亏/平 %d/%d/%d | %s", st.trades, st.wins, st.losses, st.breakevens, LifecycleStatsSampleText(st.trades)), sampleColor); line++;

   if(当前统计详情 == 统计详情_总览)
   {
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("【收益】净收益 %s | 平均每笔 %s", LifecycleStatsSignedMoney(st.netProfit), LifecycleStatsSignedMoney(avgNet)), profitColor); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("赚 %s | 亏 %s | 手续成本 %.2f", LifecycleStatsSignedMoney(st.grossProfit), LifecycleStatsSignedMoney(-MathAbs(st.grossLoss)), MathAbs(totalCost)), clrWhite); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("胜率 %.1f%% | 赚钱效率 %s | 平均赚 %s / 平均亏 %s", winRate, pf, LifecycleStatsSignedMoney(st.avgWin), LifecycleStatsSignedMoney(-MathAbs(st.avgLoss))), clrAqua); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("【风险】最大回撤 %.2f | 最好 %s | 最差 %s", st.maxRealizedDrawdown, LifecycleStatsSignedMoney(st.bestProfit), LifecycleStatsSignedMoney(st.worstProfit)), st.maxRealizedDrawdown>0 ? clrOrange : clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("连亏: 当前 %d 笔 | 最多 %d 笔 | 平均持仓 %.0f 分钟", st.currentLossStreak, st.maxLossStreak, avgHold), st.currentLossStreak>=2 ? clrOrange : clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("【风险收益】总 %s | 平均 %s/笔 | 有风险记录 %d/%d 笔", st.riskKnownTrades>0 ? LifecycleStatsSignedR(st.totalRealizedR) : "-", st.riskKnownTrades>0 ? LifecycleStatsSignedR(avgR) : "-", st.riskKnownTrades, st.trades), clrAqua); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("【拿单】平均可走 %.2fR | 不利波动 %.2fR | 实际拿住 %.1f%%", st.avgMfeR, st.avgMaeR, st.avgCaptureRatio*100.0), clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("多单 %s（%d笔） | 空单 %s（%d笔）", LifecycleStatsSignedMoney(st.buyProfit), st.buyTrades, LifecycleStatsSignedMoney(st.sellProfit), st.sellTrades), clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), "提示: "+insight, insightColor); line++;
   }
   else if(当前统计详情 == 统计详情_策略)
   {
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("【哪种单赚钱】已分类 %d/%d 笔", st.metadataTrades, st.trades), st.metadataTrades<st.trades ? clrOrange : clrSilver); line++;
      for(int a=1; a<=5; a++)
      {
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2),
                      StringFormat("%s: %d笔 | 净收益 %s | 风险收益 %s", LifecycleStatsArchetypeText(a), st.archetypeTrades[a], LifecycleStatsSignedMoney(st.archetypeProfit[a]), LifecycleStatsSignedR(st.archetypeR[a])),
                      LifecycleStatsResultColor(st.archetypeProfit[a])); line++;
      }
      string sessionNames[] = {"亚洲盘","伦敦盘","纽约盘","清淡/换日"};
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), "【哪个时段赚钱】", clrAqua); line++;
      for(int s=0; s<4; s++)
      {
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2),
                      StringFormat("%s: %d笔 | 净收益 %s | 风险收益 %s", sessionNames[s], st.sessionTrades[s], LifecycleStatsSignedMoney(st.sessionProfit[s]), LifecycleStatsSignedR(st.sessionR[s])),
                      LifecycleStatsResultColor(st.sessionProfit[s])); line++;
      }
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("方向对比: 多 %s | 空 %s", LifecycleStatsSignedMoney(st.buyProfit), LifecycleStatsSignedMoney(st.sellProfit)), clrSilver); line++;
   }
   else if(当前统计详情 == 统计详情_管理)
   {
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("【风险保护】已确认起始风险 %d/%d 笔 | 平均 %.2f", st.riskKnownTrades, st.trades, st.avgInitialRMoney), st.riskKnownTrades<st.trades ? clrOrange : clrAqua); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("【拿单质量】平均可走 %.2fR | 不利波动 %.2fR | 实际拿住 %.1f%%", st.avgMfeR, st.avgMaeR, st.avgCaptureRatio*100.0), clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("分批离场: %d笔 | 计划 %d 段 | 实际成交 %d 次", st.partialTrades, st.partialStagesTotal, st.partialFillTotal), clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("快速保护: %d笔（占 %.1f%%） | 固定目标撤销 %d笔", st.fastProtectionTrades, st.trades>0 ? 100.0*st.fastProtectionTrades/st.trades : 0.0, st.fixedTPRemovedTrades), clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("尾仓处理: 结构%d | 固定%d | 箱体%d | 快退%d", st.runnerStructureTrades, st.runnerFixedTrades, st.runnerBoxTrades, st.runnerFastExitTrades), clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("保护调整: 止损 %d 次 | 止盈 %d 次", st.slModifyTotal, st.tpModifyTotal), clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("本页结果: 净收益 %s | 手续成本 %.2f", LifecycleStatsSignedMoney(st.netProfit), MathAbs(totalCost)), profitColor); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), "说明: 只统计已完整结束的单子", clrDimGray); line++;
   }
   else if(当前统计详情 == 统计详情_执行)
   {
      int sltpSuccess = st.sltpConfirmed;
      int sltpTotal = st.sltpConfirmed+st.sltpFailed;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("【执行是否顺畅】完整交易 %d 笔 | 实际退出成交 %d 笔", st.trades, st.exitDeals), clrWhite); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("止损/止盈设置: 确认 %d | 失败 %d | 确认率 %s", st.sltpConfirmed, st.sltpFailed, sltpTotal>0 ? DoubleToString(100.0*sltpSuccess/sltpTotal,1)+"%" : "-"), st.sltpFailed>0 ? clrOrange : clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("分批离场: 请求 %d | 实际成交 %d", st.partialRequested, st.partialFillEvents), clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("全部平仓: 确认 %d | 失败 %d", st.fullCloseFilled, st.fullCloseFailed), st.fullCloseFailed>0 ? clrOrange : clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("快速保护: 确认 %d | 失败 %d", st.fastProtectionConfirmed, st.fastProtectionFailed), st.fastProtectionFailed>0 ? clrOrange : clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("手续费成本 %.2f | 数据已分类 %d/%d 笔", MathAbs(totalCost), st.metadataTrades, st.trades), st.metadataTrades<st.trades ? clrOrange : clrSilver); line++;
      SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), "说明: 这里专门看有没有执行失败，不代表收益好坏", clrDimGray); line++;
   }
   else if(当前统计详情 == 统计详情_复盘)
   {
      LifecycleReviewItem reviews[];
      GetCurrentLifecycleReviewItems(st, reviews);
      int reviewCount = ArraySize(reviews);
      CreatePanelButton("SMA_BTN_REVIEW_PREV", "上一单", 12, 146, 72, 22, false);
      CreatePanelButton("SMA_BTN_REVIEW_NEXT", "下一单", 90, 146, 72, 22, false);
      if(reviewCount <= 0)
      {
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), "当前筛选和周期内，还没有可复盘的完整托管单", clrSilver); line++;
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), "说明: 复盘只读取 EA 已结算写入的完整档案，旧历史不会凭空补造管理过程", clrDimGray); line++;
      }
      else
      {
         if(当前复盘序号 < 0) 当前复盘序号 = 0;
         if(当前复盘序号 >= reviewCount) 当前复盘序号 = reviewCount-1;
         LifecycleReviewItem item = reviews[当前复盘序号];
         double reviewHighestProfit = LifecycleReviewHighestFloatingProfit(item);
         double reviewMaximumLoss = LifecycleReviewMaximumFloatingLoss(item);
         double holdMinutes = item.closeTime > item.openTime ? (double)(item.closeTime-item.openTime)/60.0 : 0.0;
         string reviewInsight;
         color reviewInsightColor;
         GetLifecycleReviewInsight(item, reviewInsight, reviewInsightColor);
         PrefixLifecycleReviewTimingCoverage(item,reviewInsight);
         string legacyProfitDuration="未记录";
         string legacyLossDuration="未记录";
         string legacyFirstProfit="未记录";
         string legacyLongestLoss="未记录";
         if(item.floatingTimingHasData && item.floatingTimingObservedSeconds>0.0)
         {
            legacyProfitDuration=FormatReviewDurationWithRatio(item.floatingProfitSeconds,item.floatingTimingObservedSeconds);
            legacyLossDuration=FormatReviewDurationWithRatio(item.floatingLossSeconds,item.floatingTimingObservedSeconds);
            legacyFirstProfit=FormatFirstProfitTiming(item);
            legacyLongestLoss=FormatReviewDuration(item.longestFloatingLossSeconds);
         }

         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("【%s复盘】%s | 第 %d / %d 笔（最新在前） | 编号 %I64u", periodText, rangeText, 当前复盘序号+1, reviewCount, item.positionId), clrAqua); line++;
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("【结果】净收益 %s | 风险收益 %s | 手续成本 %.2f", LifecycleStatsSignedMoney(item.net), item.initialRMoney>0.0 ? LifecycleStatsSignedR(item.realizedR) : "-", MathAbs(item.commission+item.swap+item.fee)), LifecycleStatsResultColor(item.net)); line++;
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("模式: %s | 类型: %s | %s", 简化面板模板名称(item.templateId), LifecycleStatsArchetypeText(item.archetype), LifecycleReviewDirectionText(item.direction)), clrWhite); line++;
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("北京时间: %s → %s | 持仓 %.0f 分钟", FormatBeijingTime(item.openTime), FormatBeijingTime(item.closeTime), holdMinutes), clrSilver); line++;
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("进场 %.2f手 @ %s | 平仓 %.2f手 @ %s", item.entryVolume, DoubleToString(item.entryPrice,_Digits), item.exitVolume, DoubleToString(item.exitPrice,_Digits)), clrSilver); line++;
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("初始保护: SL %s | 初始风险 %.2f | 风险金额 %.2f", item.initialSL>0.0 ? DoubleToString(item.initialSL,_Digits) : "未记录", item.initialRPrice, item.initialRMoney), item.initialRMoney>0.0 ? clrSilver : clrOrange); line++;
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("过程: 最高浮盈 %s | 最大浮亏 %s | 可走 %.2fR | 实际拿住 %.1f%%", LifecycleStatsSignedMoney(reviewHighestProfit), LifecycleStatsSignedMoney(-reviewMaximumLoss), item.mfeR, item.captureRatio*100.0), clrSilver); line++;
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("分批退出 %d次 | 浮盈时长 %s", item.partialFills, legacyProfitDuration), item.floatingProfitSeconds>0.0?LegacyProfitColor():clrSilver); line++;
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("SL调整 %d次 | 浮亏时长 %s", item.slModifyCount, legacyLossDuration), item.floatingLossSeconds>0.0?LegacyLossColor():clrSilver); line++;
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("TP调整 %d次 | 首次观测浮盈 %s", item.tpModifyCount, legacyFirstProfit), clrSilver); line++;
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), StringFormat("实际退出 %s | 最长浮亏 %s", LifecycleReviewActualExitText(item.actualExitReason), legacyLongestLoss), item.longestFloatingLossSeconds>0.0?LegacyLossColor():clrWhite); line++;
         SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), "复盘提示: "+reviewInsight, reviewInsightColor); line++;
      }
   }

   SetPanelLine("SMA_PANEL_"+IntegerToString(line), y0+面板行距*(line-2), "状态: "+lastStatus, clrYellow); line++;
   for(int k=line; k<=48; k++) ObjectDelete(0, "SMA_PANEL_"+IntegerToString(k));
   ResizePanelBackgroundHeight(y0+面板行距*(line-2)+12);
   DrawPanelHeaderButtons();
}

// 支撑压力/结构箱体的唯一外部刷新入口；面板和显示函数只读取缓存。
// 数组复制只发生在模板切换/刷新时，避免每Tick重新扫描多周期K线。
bool ValidTemplateCacheId(int templateId)
{
   return (templateId >= (int)配置_自定义 && templateId <= (int)配置_黄金消息对冲);
}

void CopySRLevelCache(SRLevel &destination[], const SRLevel &source[])
{
   int count = ArraySize(source);
   ArrayResize(destination, count);
   for(int i=0; i<count; i++)
      destination[i] = source[i];
}

void SaveCurrentStructureCache(int templateId)
{
   if(!ValidTemplateCacheId(templateId)) return;
   if(templateId == (int)配置_自定义)
   {
      CopySRLevelCache(模板缓存压力位_0, 缓存压力位); CopySRLevelCache(模板缓存支撑位_0, 缓存支撑位);
   }
   else if(templateId == (int)配置_黄金超短快保)
   {
      CopySRLevelCache(模板缓存压力位_1, 缓存压力位); CopySRLevelCache(模板缓存支撑位_1, 缓存支撑位);
   }
   else if(templateId == (int)配置_黄金稳健托管)
   {
      CopySRLevelCache(模板缓存压力位_2, 缓存压力位); CopySRLevelCache(模板缓存支撑位_2, 缓存支撑位);
   }
   else if(templateId == (int)配置_黄金支压止盈)
   {
      CopySRLevelCache(模板缓存压力位_3, 缓存压力位); CopySRLevelCache(模板缓存支撑位_3, 缓存支撑位);
   }
   else
   {
      CopySRLevelCache(模板缓存压力位_4, 缓存压力位); CopySRLevelCache(模板缓存支撑位_4, 缓存支撑位);
   }
   模板结构缓存刷新时间[templateId] = 上次支撑压力刷新时间;
}

void LoadStructureCache(int templateId)
{
   if(!ValidTemplateCacheId(templateId)) return;
   if(templateId == (int)配置_自定义)
   {
      CopySRLevelCache(缓存压力位, 模板缓存压力位_0); CopySRLevelCache(缓存支撑位, 模板缓存支撑位_0);
   }
   else if(templateId == (int)配置_黄金超短快保)
   {
      CopySRLevelCache(缓存压力位, 模板缓存压力位_1); CopySRLevelCache(缓存支撑位, 模板缓存支撑位_1);
   }
   else if(templateId == (int)配置_黄金稳健托管)
   {
      CopySRLevelCache(缓存压力位, 模板缓存压力位_2); CopySRLevelCache(缓存支撑位, 模板缓存支撑位_2);
   }
   else if(templateId == (int)配置_黄金支压止盈)
   {
      CopySRLevelCache(缓存压力位, 模板缓存压力位_3); CopySRLevelCache(缓存支撑位, 模板缓存支撑位_3);
   }
   else
   {
      CopySRLevelCache(缓存压力位, 模板缓存压力位_4); CopySRLevelCache(缓存支撑位, 模板缓存支撑位_4);
   }
   上次支撑压力刷新时间 = 模板结构缓存刷新时间[templateId];
}

bool RefreshMarketStructureCaches(bool force=false, bool updateVisuals=true)
{
   int templateId = (int)当前参数配置模板;
   if(!ValidTemplateCacheId(templateId)) templateId = (int)配置_自定义;
   if(当前载入结构缓存模板 != templateId)
   {
      if(ValidTemplateCacheId(当前载入结构缓存模板))
         SaveCurrentStructureCache(当前载入结构缓存模板);
      LoadStructureCache(templateId);
      当前载入结构缓存模板 = templateId;
   }

   // 逐仓管理只读取结构数据。模板缓存仍在有效期内时，载入后直接复用，
   // 避免每笔持仓重复进入UpdateSupportResistance并再次复制相同数组。
   datetime now = TimeCurrent();
   if(!force &&
       模板结构缓存刷新时间[templateId] > 0 &&
       now - 模板结构缓存刷新时间[templateId] < 支撑压力刷新秒数)
   {
      if(updateVisuals)
      {
         if(显示支撑压力线) DrawSupportResistanceLines();
         else DeleteSRObjects();
      }
      return (ArraySize(缓存压力位) > 0 || ArraySize(缓存支撑位) > 0);
   }

   bool refreshed = UpdateSupportResistance(force, updateVisuals);
   SaveCurrentStructureCache(templateId);
   return refreshed;
}

string FormatSRPanelText(SRLevel &arr[], bool resistance, double refPrice)
{
   if(ArraySize(arr) <= 0) return resistance ? "压力: -" : "支撑: -";

   string prefix = resistance ? "压力: " : "支撑: ";
   string text = prefix;
   int maxShow = MathMin(ArraySize(arr), MathMin(MathMax(每侧最多显示点位数, 0), 2)); // 面板只显示最近2个，避免太长。
   for(int i=0; i<maxShow; i++)
   {
      double dist = arr[i].price - refPrice;
      string tag = resistance ? ("R" + IntegerToString(i+1)) : ("S" + IntegerToString(i+1));
      string one = StringFormat("%s %.2f x%d 距%+.2f", tag, arr[i].price, arr[i].strength, dist);
      if(i > 0) text += " | ";
      text += one;
   }
   return text;
}

string FormatSRCompactLine(SRLevel &arr[], bool resistance)
{
   if(ArraySize(arr) <= 0) return resistance ? "R: -" : "S: -";

   string text = resistance ? "R: " : "S: ";
   int maxShow = MathMin(ArraySize(arr), 2);
   for(int i=0; i<maxShow; i++)
   {
      if(i > 0) text += " / ";
      text += StringFormat("%.2f x%d", arr[i].price, arr[i].strength);
   }
   return text;
}

string FormatSRCompactLineWithDistance(SRLevel &arr[], bool resistance, double refPrice)
{
   if(ArraySize(arr) <= 0 || refPrice <= 0.0)
   {
      if(支撑压力启用最终增强版 && !支撑压力无交易线时允许显示弱观察线)
         return resistance ? "R: 无高质量做空位" : "S: 无高质量做多位";
      return resistance ? "R: -" : "S: -";
   }

   string text = resistance ? "R: " : "S: ";
   int maxCount = 支撑压力启用最终增强版 ? MathMax(支撑压力最多显示数量, 1) : 2;
   int maxShow = MathMin(ArraySize(arr), MathMin(maxCount, 3));
   for(int i=0; i<maxShow; i++)
   {
      if(i > 0) text += " / ";
      double diffPrice = arr[i].price - refPrice;
      if(!resistance && !支撑压力显示负号支撑距离)
         diffPrice = MathAbs(diffPrice);
      string tag = resistance ? ("R" + IntegerToString(i + 1)) : ("S" + IntegerToString(i + 1));
      string sign = diffPrice >= 0.0 ? "+" : "";
      string flag = "";
      if(arr[i].liquiditySweep) flag = " 扫";
      else if(arr[i].boxBoundary) flag = " 箱";
      else if(arr[i].sessionLevel) flag = " 时";
      else if(arr[i].densityLevel) flag = " 密";
      string status = 支撑压力启用最终增强版 ? SRActionText(arr[i], resistance, false) : ("x" + IntegerToString(arr[i].strength));
      text += StringFormat("%s %.2f 距%s%.2f %s%s", tag, arr[i].price, sign, diffPrice, status, 支撑压力启用最终增强版 ? flag : "");
   }
   return text;
}

string MiniSRStatusText(const SRLevel &lv, bool resistance)
{
   if(!支撑压力启用最终增强版)
      return "x" + IntegerToString(lv.strength);
   return SRActionText(lv, resistance, true);
}

string FormatSRMiniLine(SRLevel &arr[], bool resistance, double refPrice)
{
   string prefix = resistance ? "R: " : "S: ";
   if(ArraySize(arr) <= 0 || refPrice <= 0.0)
      return prefix + "-";

   SRLevel lv = arr[0];
   double diffPrice = lv.price - refPrice;
   if(!resistance && !支撑压力显示负号支撑距离)
      diffPrice = MathAbs(diffPrice);
   string sign = diffPrice >= 0.0 ? "+" : "";
   string flag = "";
   if(lv.liquiditySweep) flag = "扫";
   else if(lv.boxBoundary) flag = "箱";
   else if(lv.sessionLevel) flag = "时";
   else if(lv.densityLevel) flag = "密";
   return StringFormat("%s1 %.2f %s%.1f %s%s",
                       resistance ? "R" : "S",
                       lv.price,
                       sign,
                       diffPrice,
                       MiniSRStatusText(lv, resistance),
                       flag);
}

bool GetNearestResistance(double refPrice, SRLevel &level)
{
   bool found = false;
   double bestDist = 0.0;
   for(int i=0; i<ArraySize(缓存压力位); i++)
   {
      if(缓存压力位[i].price <= refPrice) continue;
      double d = 缓存压力位[i].price - refPrice;
      if(!found || d < bestDist)
      {
         level = 缓存压力位[i];
         bestDist = d;
         found = true;
      }
   }
   return found;
}

bool GetNearestSupport(double refPrice, SRLevel &level)
{
   bool found = false;
   double bestDist = 0.0;
   for(int i=0; i<ArraySize(缓存支撑位); i++)
   {
      if(缓存支撑位[i].price >= refPrice) continue;
      double d = refPrice - 缓存支撑位[i].price;
      if(!found || d < bestDist)
      {
         level = 缓存支撑位[i];
         bestDist = d;
         found = true;
      }
   }
   return found;
}

string FormatTPAdviceText(double refPrice, bool hasBuy, bool hasSell, color &lineColor)
{
   lineColor = clrSilver;
   if(refPrice <= 0.0) return "TP参考: -";

   string parts = "TP参考: ";
   bool hasAny = false;

   if(hasBuy)
   {
      SRLevel r;
      if(GetNearestResistance(refPrice, r))
      {
         double dist = r.price - refPrice;
         double suggestTP = NormalizePrice(r.price - TP贴近点位缓冲价格);
         parts += StringFormat("多≈%.2f(R1距+%.2f)", suggestTP, dist);
         hasAny = true;
         if(dist <= 持仓目标空间不足距离) lineColor = clrOrange;
      }
   }

   if(hasSell)
   {
      SRLevel s;
      if(GetNearestSupport(refPrice, s))
      {
         double dist = refPrice - s.price;
         double suggestTP = NormalizePrice(s.price + TP贴近点位缓冲价格);
         if(hasAny) parts += " | ";
         parts += StringFormat("空≈%.2f(S1距-%.2f)", suggestTP, dist);
         hasAny = true;
         if(dist <= 持仓目标空间不足距离) lineColor = clrOrange;
      }
   }

   if(!hasAny) return "TP参考: -";
   return parts;
}


bool 当前是短线单模板()
{
   return 当前参数配置模板 == 配置_黄金超短快保;
}

string FormatShortTPLevelTag(bool resistance, int index, const SRLevel &lv)
{
   string side = resistance ? "R" : "S";
   string grade = 支撑压力启用最终增强版 ? SRGradeText(lv.qualityGrade) : ("x" + IntegerToString(lv.strength));
   return side + IntegerToString(index + 1) + grade;
}

bool SelectShortTPFromLevels(SRLevel &levels[], bool resistance, double avgPrice, double curPrice,
                             double &tpPrice, int &levelIndex, double &distFromCurrent, double &profitFromAvg,
                             bool &spaceNarrow)
{
   levelIndex = -1;
   tpPrice = 0.0;
   distFromCurrent = 0.0;
   profitFromAvg = 0.0;
   spaceNarrow = false;

   int fallback = -1;
   double fallbackTP = 0.0;
   double fallbackCurDist = 0.0;
   double fallbackProfit = 0.0;
   bool foundStrong = false;

   int maxScan = MathMin(ArraySize(levels), 3);
   for(int i=0; i<maxScan; i++)
   {
      double candidateTP = resistance ? NormalizePrice(levels[i].price - TP贴近点位缓冲价格)
                                      : NormalizePrice(levels[i].price + TP贴近点位缓冲价格);
      double curDist = resistance ? (candidateTP - curPrice) : (curPrice - candidateTP);
      double profitSpace = resistance ? (candidateTP - avgPrice) : (avgPrice - candidateTP);

      // 已经越过或没有盈利空间的点位，不作为推荐止盈。
      if(curDist <= 0.0 || profitSpace <= 0.0)
         continue;

      if(fallback < 0)
      {
         fallback = i;
         fallbackTP = candidateTP;
         fallbackCurDist = curDist;
         fallbackProfit = profitSpace;
      }

      if(profitSpace >= 短线单推荐TP最小空间价格)
      {
         levelIndex = i;
         tpPrice = candidateTP;
         distFromCurrent = curDist;
         profitFromAvg = profitSpace;
         foundStrong = true;
         break;
      }

      if(!短线单空间不足优先看下一档)
         break;
   }

   if(!foundStrong && fallback >= 0)
   {
      levelIndex = fallback;
      tpPrice = fallbackTP;
      distFromCurrent = fallbackCurDist;
      profitFromAvg = fallbackProfit;
      spaceNarrow = true;
      return true;
   }

   return foundStrong;
}

string FormatShortLineTPAdviceText(int buyCount, double buyAvg, int sellCount, double sellAvg,
                                   double bid, double ask, color &lineColor)
{
   lineColor = clrSilver;
   if(!短线单显示推荐止盈点位 || !当前是短线单模板())
      return "短线TP: -";
   if(buyCount <= 0 && sellCount <= 0)
      return "短线TP: 空仓后显示";

   string text = "短线TP: ";
   bool hasAny = false;
   bool anyNarrow = false;

   if(buyCount > 0 && buyAvg > 0.0)
   {
      double tp=0.0, dist=0.0, profit=0.0;
      int idx=-1;
      bool narrow=false;
      if(SelectShortTPFromLevels(缓存压力位, true, buyAvg, bid, tp, idx, dist, profit, narrow))
      {
         string tag = FormatShortTPLevelTag(true, idx, 缓存压力位[idx]);
         text += StringFormat("多 %.2f[%s 距+%.2f 利+%.2f%s]", tp, tag, dist, profit, narrow ? " 窄" : "");
         hasAny = true;
         if(narrow) anyNarrow = true;
      }
      else
      {
         text += "多 无上方R";
         hasAny = true;
         anyNarrow = true;
      }
   }

   if(sellCount > 0 && sellAvg > 0.0)
   {
      if(hasAny) text += " | ";
      double tp=0.0, dist=0.0, profit=0.0;
      int idx=-1;
      bool narrow=false;
      if(SelectShortTPFromLevels(缓存支撑位, false, sellAvg, ask, tp, idx, dist, profit, narrow))
      {
         string tag = FormatShortTPLevelTag(false, idx, 缓存支撑位[idx]);
         text += StringFormat("空 %.2f[%s 距-%.2f 利+%.2f%s]", tp, tag, dist, profit, narrow ? " 窄" : "");
         hasAny = true;
         if(narrow) anyNarrow = true;
      }
      else
      {
         text += "空 无下方S";
         hasAny = true;
         anyNarrow = true;
      }
   }

   if(!hasAny)
      return "短线TP: -";

   lineColor = anyNarrow ? clrOrange : clrAqua;
   return text;
}

string MergeSLWarning(string current, string add)
{
   if(add == "") return current;
   if(current == "正常" || current == "") return add;
   if(StringFind(current, add) >= 0) return current;
   return current + "; " + add;
}


string TrimTeacherMarkerText(string text)
{
   StringTrimLeft(text);
   StringTrimRight(text);
   return text;
}

double TeacherMarkerTickSize()
{
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0.0) tickSize=_Point;
   return tickSize;
}

double TeacherMarkerPriceTolerance()
{
   return MathMax(TeacherMarkerTickSize()*0.5,_Point*0.5);
}

double NormalizeTeacherMarkerPrice(double price)
{
   if(price<=0.0) return 0.0;
   double tickSize=TeacherMarkerTickSize();
   if(tickSize>0.0) price=MathRound(price/tickSize)*tickSize;
   return NormalizeDouble(price,_Digits);
}

bool AddUniqueTeacherMarkerLevel(double value,double &levels[])
{
   double normalized=NormalizeTeacherMarkerPrice(value);
   if(normalized<=0.0) return false;
   double tolerance=TeacherMarkerPriceTolerance();
   for(int i=0;i<ArraySize(levels);i++)
      if(MathAbs(levels[i]-normalized)<=tolerance) return true;
   int size=ArraySize(levels);
   if(ArrayResize(levels,size+1)!=size+1) return false;
   levels[size]=normalized;
   return true;
}

bool ParseTeacherMarkerLevels(const string sourceText,double &levels[],string &errorText)
{
   ArrayResize(levels,0);
   errorText="";
   string text=TrimTeacherMarkerText(sourceText);
   if(text=="")
   {
      errorText="EMPTY_TEXT";
      return false;
   }

   int scanStart=0;
   int scanEnd=StringLen(text);
   string keyword="点位更新";
   int keywordPos=StringFind(text,keyword);
   if(keywordPos>=0)
   {
      scanStart=keywordPos+StringLen(keyword);
      int bracketFull=StringFind(text,"（",scanStart);
      int bracketAscii=StringFind(text,"(",scanStart);
      if(bracketFull>=0) scanEnd=bracketFull;
      if(bracketAscii>=0 && bracketAscii<scanEnd) scanEnd=bracketAscii;
   }
   if(scanEnd<scanStart) scanEnd=scanStart;
   string parseText=StringSubstr(text,scanStart,scanEnd-scanStart);

   string token="";
   int dotCount=0;
   int invalidSegments=0;
   int length=StringLen(parseText);
   for(int i=0;i<=length;i++)
   {
      bool atEnd=(i==length);
      ushort ch=atEnd?0:StringGetCharacter(parseText,i);
      bool isDigit=(!atEnd && ch>=(ushort)'0' && ch<=(ushort)'9');
      bool isDot=(!atEnd && (ch==(ushort)'.' || ch==0xFF0E || ch==0x3002));
      if(isDigit)
      {
         token+=StringSubstr(parseText,i,1);
         continue;
      }
      if(isDot)
      {
         token+=".";
         dotCount++;
         continue;
      }
      if(token=="")
      {
         dotCount=0;
         continue;
      }

      bool validToken=(dotCount<=1 && token!=".");
      double parsed=validToken?StringToDouble(token):0.0;
      if(!validToken || parsed<=0.0 || !AddUniqueTeacherMarkerLevel(parsed,levels))
         invalidSegments++;
      token="";
      dotCount=0;
   }

   if(ArraySize(levels)>1) ArraySort(levels);
   int count=ArraySize(levels);
   if(count>MAX_TEACHER_MARKER_LEVELS)
   {
      errorText=StringFormat("TOO_MANY_LEVELS count=%d max=%d",count,MAX_TEACHER_MARKER_LEVELS);
      if(invalidSegments>0) errorText+=StringFormat(" invalid_segments=%d",invalidSegments);
      return false;
   }
   if(count<=0)
   {
      errorText="NO_VALID_LEVEL";
      if(invalidSegments>0) errorText+=StringFormat(" invalid_segments=%d",invalidSegments);
      return false;
   }
   if(invalidSegments>0) errorText=StringFormat("INVALID_SEGMENTS count=%d",invalidSegments);
   return true;
}

ulong TeacherMarkerHashText(const string text)
{
   ulong hash=1469598103934665603;
   int length=StringLen(text);
   for(int i=0;i<length;i++)
   {
      hash^=(ulong)StringGetCharacter(text,i);
      hash*=1099511628211;
   }
   return hash;
}

ulong TeacherMarkerResultSignature(const double &levels[])
{
   string canonical=_Symbol+"|"+IntegerToString(_Digits)+"|"+
                    DoubleToString(TeacherMarkerTickSize(),_Digits)+"|"+IntegerToString(ArraySize(levels));
   for(int i=0;i<ArraySize(levels);i++) canonical+="|"+DoubleToString(levels[i],_Digits);
   return TeacherMarkerHashText(canonical);
}

string TeacherMarkerLevelsText(const double &levels[])
{
   string result="";
   for(int i=0;i<ArraySize(levels);i++)
   {
      if(result!="") result+=",";
      result+=DoubleToString(levels[i],_Digits);
   }
   return result;
}

string TeacherMarkerInvalidStatusText()
{
   if(StringFind(缓存老师点位错误,"TOO_MANY_LEVELS")==0)
      return StringFormat("老师点位过多：%d条，最大%d条",缓存老师点位数量,MAX_TEACHER_MARKER_LEVELS);
   return "老师点位解析失败";
}

void RefreshTeacherMarkerCache()
{
   缓存老师点位原文=老师点位文本;
   缓存老师点位有效=false;
   缓存老师点位错误="";
   缓存老师点位签名=0;
   缓存老师点位数量=0;
   ArrayResize(缓存老师点位,0);

   string trimmed=TrimTeacherMarkerText(老师点位文本);
   if(trimmed=="")
   {
      手机标记来源模式=手机标记来源_自动结构;
      手机标记环境Dirty=true;
      Print("MOBILE_MARKER_SOURCE mode=AUTO_STRUCTURE");
      return;
   }

   double parsed[];
   string parseError="";
   bool parsedOk=ParseTeacherMarkerLevels(老师点位文本,parsed,parseError);
   缓存老师点位数量=ArraySize(parsed);
   缓存老师点位错误=parseError;
   if(parsedOk)
   {
      ArrayResize(缓存老师点位,缓存老师点位数量);
      ArrayCopy(缓存老师点位,parsed,0,0,缓存老师点位数量);
      缓存老师点位有效=true;
      缓存老师点位签名=TeacherMarkerResultSignature(缓存老师点位);
      手机标记来源模式=手机标记来源_老师文本;
      PrintFormat("TEACHER_LEVELS_PARSED count=%d levels=%s signature=%I64u%s",
                  缓存老师点位数量,TeacherMarkerLevelsText(缓存老师点位),缓存老师点位签名,
                  parseError==""?"":" warning="+parseError);
      Print("MOBILE_MARKER_SOURCE mode=TEACHER_TEXT");
   }
   else
   {
      ArrayResize(缓存老师点位,0);
      手机标记来源模式=手机标记来源_老师文本无效;
      PrintFormat("TEACHER_LEVELS_PARSE_FAILED reason=%s",缓存老师点位错误);
      Print("MOBILE_MARKER_SOURCE mode=TEACHER_TEXT_INVALID");
   }
   手机标记环境Dirty=true;
}

bool IsHedgingAccount()
{
   ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   return (mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
}

bool NormalizeMarkerVolume(double requested, double &volume)
{
   volume = 0.0;
   double minVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVol = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(minVol <= 0.0 || maxVol <= 0.0 || step <= 0.0) return false;

   // 标记挂单是真实订单。用户输入小于最小手数时，不自动放大手数，避免风险超预期。
   if(requested + 1e-12 < minVol)
      return false;

   double steps = MathFloor((requested - minVol) / step + 1e-9);
   volume = minVol + steps * step;
   if(volume > maxVol) volume = maxVol;
   volume = NormalizeDouble(volume, 2);
   return (volume >= minVol && volume <= maxVol);
}

bool IsMobileMarkerTag(string cmt)
{
   return (StringFind(cmt, "SMA_MARK_") == 0);
}

bool IsTeacherMobileMarkerTag(string cmt)
{
   return (StringFind(cmt,"SMA_MARK_K")==0);
}

bool IsAutomaticMobileMarkerTag(string cmt)
{
   return (StringFind(cmt,"SMA_MARK_R")==0 || StringFind(cmt,"SMA_MARK_S")==0);
}

int TeacherMobileMarkerTagIndex(string cmt)
{
   if(StringLen(cmt)!=12 || StringFind(cmt,"SMA_MARK_K")!=0) return -1;
   string suffix=StringSubstr(cmt,10,2);
   ushort first=StringGetCharacter(suffix,0);
   ushort second=StringGetCharacter(suffix,1);
   if(first<48 || first>57 || second<48 || second>57) return -1;
   int index=(int)StringToInteger(suffix);
   return (index>=1 && index<=MAX_TEACHER_MARKER_LEVELS)?index:-1;
}

bool IsMobileMarkerOrderSelected(string tag="")
{
   if(OrderGetString(ORDER_SYMBOL) != _Symbol) return false;
   if((long)OrderGetInteger(ORDER_MAGIC) != 手机标记挂单Magic) return false;

   string cmt = OrderGetString(ORDER_COMMENT);
   if(tag != "" && cmt != tag) return false;
   return IsMobileMarkerTag(cmt);
}

int CountMobileMarkerOrdersBySource(bool teacherSource,bool automaticSource)
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong tk=OrderGetTicket(i);
      if(tk==0 || !IsMobileMarkerOrderSelected()) continue;
      string tag=OrderGetString(ORDER_COMMENT);
      if((teacherSource && IsTeacherMobileMarkerTag(tag)) ||
         (automaticSource && IsAutomaticMobileMarkerTag(tag))) count++;
   }
   return count;
}

int CountAllMobileMarkerOrders()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong tk=OrderGetTicket(i);
      if(tk==0 || !IsMobileMarkerOrderSelected()) continue;
      count++;
   }
   return count;
}

#include "Include/Trading/MobileMarkerSafety.mqh"

void RequestDeleteMobileMarkerOrdersBySource(bool teacherSource,bool automaticSource,string reason)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong tk=OrderGetTicket(i);
      if(tk==0 || !IsMobileMarkerOrderSelected()) continue;
      string tag=OrderGetString(ORDER_COMMENT);
      bool selected=(teacherSource && IsTeacherMobileMarkerTag(tag)) ||
                    (automaticSource && IsAutomaticMobileMarkerTag(tag));
      if(!selected) continue;
      bool submitted=RequestMobileMarkerDelete(tk);
      uint retcode=markerTrade.ResultRetcode();
      if(submitted)
         PrintFormat("MOBILE_MARKER_DELETE_REQUEST ticket=%I64u tag=%s reason=%s ret=%u",tk,tag,reason,retcode);
   }
}

bool FindMobileMarkerOrder(string tag, ulong &ticket, double &price, double &sl, double &tp, ENUM_ORDER_TYPE &type)
{
   ticket = 0;
   price = 0.0;
   sl = 0.0;
   tp = 0.0;
   type = WRONG_VALUE;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(!IsMobileMarkerOrderSelected(tag)) continue;

      ticket = tk;
      price = OrderGetDouble(ORDER_PRICE_OPEN);
      sl = OrderGetDouble(ORDER_SL);
      tp = OrderGetDouble(ORDER_TP);
      type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      return true;
   }
   return false;
}

void DeleteMobileMarkerOrders(string tag="")
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      ulong tk = OrderGetTicket(i);
      if(tk == 0) continue;
      if(!IsMobileMarkerOrderSelected(tag)) continue;
      RequestMobileMarkerDelete(tk);
   }
}

void CloseMobileMarkerPositions()
{
   // 如果极端行情导致标记挂单成交，尽量立刻平掉该Magic持仓。
   // 注意：本功能仅建议在对冲账户使用；净额账户可能与真实持仓合并，因此禁用创建。
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != 手机标记挂单Magic) continue;
      markerTrade.PositionClose(tk);
   }
}

// 检查当前价格是否已经突破手机端标记线。
// 压力R用Buy Limit的TP线显示：中价 >= TP + 缓冲，视为压力已被突破，需要换到新的上方压力。
// 支撑S用Sell Stop的SL线显示：中价 <= SL - 缓冲，视为支撑已被跌破，需要换到新的下方支撑。
bool MobileMarkerLevelBroken()
{
   if(!当前启用手机标记挂单() || !手机标记突破立即刷新) return false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return false;

   double buffer = GetConfirmedBreakoutBuffer();
   double checkPrice = (bid + ask) / 2.0;
   if(手机标记突破需M1收线确认)
   {
      datetime t; double c;
      if(!GetLastClosedM1(t, c)) return false;
      checkPrice = c;
   }

   int markerCount = MathMin(MathMax(手机标记每侧点位数, 1), 2);

   for(int i=0; i<markerCount; i++)
   {
      ulong tk; double price, sl, tp; ENUM_ORDER_TYPE type;

      string rTag = "SMA_MARK_R" + IntegerToString(i + 1);
      if(FindMobileMarkerOrder(rTag, tk, price, sl, tp, type))
      {
         // 小幅刺破压力不撤；只有M1收线站上“压力+大突破缓冲”才撤旧挂新。
         if(type == ORDER_TYPE_BUY_LIMIT && tp > 0.0 && checkPrice >= tp + buffer)
            return true;
      }

      string sTag = "SMA_MARK_S" + IntegerToString(i + 1);
      if(FindMobileMarkerOrder(sTag, tk, price, sl, tp, type))
      {
         // 小幅刺破支撑不撤；只有M1收线跌破“支撑-大突破缓冲”才撤旧挂新。
         if(type == ORDER_TYPE_SELL_STOP && sl > 0.0 && checkPrice <= sl - buffer)
            return true;
      }
   }

   return false;
}

bool MarkerBuyLimitTPValid(double markerPrice, double tp)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask <= 0.0 || markerPrice <= 0.0 || tp <= 0.0) return false;

   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist = MathMax(stopsLevel, freezeLevel) * _Point;
   if(minDist < _Point) minDist = _Point;

   // Buy Limit 必须在当前Ask下方；TP必须在挂单价上方。
   if(ask - markerPrice < minDist) return false;
   if(tp - markerPrice < minDist) return false;
   return true;
}

bool MarkerSellStopSLValid(double markerPrice, double sl)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0.0 || markerPrice <= 0.0 || sl <= 0.0) return false;

   int stopsLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist = MathMax(stopsLevel, freezeLevel) * _Point;
   if(minDist < _Point) minDist = _Point;

   // Sell Stop 必须在当前Bid下方；SL必须在挂单价上方。
   if(bid - markerPrice < minDist) return false;
   if(sl - markerPrice < minDist) return false;
   return true;
}

int CollectTeacherMobileMarkerOrders(TeacherMarkerOrderInfo &orders[])
{
   ArrayResize(orders,0);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong tk=OrderGetTicket(i);
      if(tk==0 || !IsMobileMarkerOrderSelected()) continue;
      string tag=OrderGetString(ORDER_COMMENT);
      if(!IsTeacherMobileMarkerTag(tag)) continue;
      int size=ArraySize(orders);
      if(ArrayResize(orders,size+1)!=size+1) break;
      orders[size].ticket=tk;
      orders[size].tag=tag;
      orders[size].tagIndex=TeacherMobileMarkerTagIndex(tag);
      orders[size].type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      orders[size].openPrice=OrderGetDouble(ORDER_PRICE_OPEN);
      orders[size].tp=OrderGetDouble(ORDER_TP);
      orders[size].volume=OrderGetDouble(ORDER_VOLUME_INITIAL);
      orders[size].keep=false;
   }
   return ArraySize(orders);
}

bool TeacherMarkerOrderMatchesLevel(const TeacherMarkerOrderInfo &orderInfo,double level,
                                    double markerPrice,double markerVolume)
{
   if(orderInfo.type!=ORDER_TYPE_BUY_LIMIT) return false;
   double priceTolerance=TeacherMarkerPriceTolerance();
   if(MathAbs(orderInfo.openPrice-markerPrice)>priceTolerance) return false;
   if(MathAbs(orderInfo.tp-level)>priceTolerance) return false;
   double volumeStep=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double volumeTolerance=MathMax(volumeStep*0.5,1e-8);
   if(MathAbs(orderInfo.volume-markerVolume)>volumeTolerance) return false;
   return MarkerBuyLimitTPValid(markerPrice,level);
}

string NextUnusedTeacherMarkerTag(bool &usedTags[])
{
   for(int i=1;i<=MAX_TEACHER_MARKER_LEVELS;i++)
   {
      if(i<ArraySize(usedTags) && usedTags[i]) continue;
      if(i<ArraySize(usedTags)) usedTags[i]=true;
      return "SMA_MARK_K"+StringFormat("%02d",i);
   }
   return "";
}

bool SubmitTeacherMobileMarker(double target,string tag)
{
   if(!ReconcileMobileMarkerDeletes()) return false;
   double markerPrice=NormalizePrice(手机标记挂单固定价格);
   double normalizedTarget=NormalizeTeacherMarkerPrice(target);
   double volume=0.0;
   if(!NormalizeMarkerVolume(手机标记挂单手数,volume))
   {
      老师点位最近错误码=0;
      老师点位最近错误="手数低于最小值";
      return false;
   }
   if(!MarkerBuyLimitTPValid(markerPrice,normalizedTarget))
   {
      老师点位最近错误码=0;
      老师点位最近错误="老师点位价规不合法";
      return false;
   }

   ENUM_ORDER_TYPE_TIME typeTime=ORDER_TIME_GTC;
   datetime expiration=0;
   if(手机标记有效分钟>0)
   {
      typeTime=ORDER_TIME_SPECIFIED;
      expiration=TimeCurrent()+手机标记有效分钟*60;
   }
   markerTrade.SetExpertMagicNumber(手机标记挂单Magic);
   bool submitted=markerTrade.BuyLimit(volume,markerPrice,_Symbol,0.0,normalizedTarget,
                                       typeTime,expiration,tag);
   if(!submitted && markerTrade.ResultRetcode()==10022 && typeTime!=ORDER_TIME_GTC)
      submitted=markerTrade.BuyLimit(volume,markerPrice,_Symbol,0.0,normalizedTarget,
                                     ORDER_TIME_GTC,0,tag);

   老师点位最近错误码=markerTrade.ResultRetcode();
   老师点位最近错误=markerTrade.ResultComment();
   if(submitted)
      PrintFormat("TEACHER_MARKER_CREATE_REQUEST tag=%s target=%s ret=%u order=%I64u",
                  tag,DoubleToString(normalizedTarget,_Digits),老师点位最近错误码,markerTrade.ResultOrder());
   else
      PrintFormat("TEACHER_MARKER_CREATE_FAILED tag=%s target=%s ret=%u comment=%s",
                  tag,DoubleToString(normalizedTarget,_Digits),老师点位最近错误码,老师点位最近错误);
   return submitted;
}

void SetTeacherMarkerSyncStatus(string status,int expected,int active,int failed)
{
   bool changed=(status!=上次老师点位同步状态 || 缓存老师点位签名!=上次老师点位同步签名);
   手机标记状态=status;
   if(changed)
   {
      lastStatus=status;
      PrintFormat("TEACHER_MARKERS_SYNCED expected=%d active=%d failed=%d signature=%I64u last_ret=%u last_error=%s",
                  expected,active,failed,缓存老师点位签名,老师点位最近错误码,老师点位最近错误);
      上次老师点位同步状态=status;
      上次老师点位同步签名=缓存老师点位签名;
   }
}

void SyncTeacherMobileMarkers(const bool force)
{
   int expected=ArraySize(缓存老师点位);
   if(!缓存老师点位有效 || expected<=0)
   {
      string status=TeacherMarkerInvalidStatusText();
      SetTeacherMarkerSyncStatus(status,expected,0,expected);
      return;
   }

   老师点位最近错误码=0;
   老师点位最近错误="";
   double markerPrice=NormalizePrice(手机标记挂单固定价格);
   double markerVolume=0.0;
   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(bid<=0.0 || ask<=0.0)
   {
      SetTeacherMarkerSyncStatus("老师点位：等待行情",expected,0,expected);
      return;
   }
   if(markerPrice<=0.0 || bid-markerPrice<=手机标记危险距离)
   {
      RequestDeleteMobileMarkerOrdersBySource(true,false,"teacher_marker_danger_distance");
      SetTeacherMarkerSyncStatus("老师点位：接近触发已撤",expected,0,expected);
      return;
   }
   if(!NormalizeMarkerVolume(手机标记挂单手数,markerVolume))
   {
      RequestDeleteMobileMarkerOrdersBySource(true,false,"teacher_marker_invalid_volume");
      老师点位最近错误="手数低于最小值";
      SetTeacherMarkerSyncStatus("老师点位：手数低于最小值",expected,0,expected);
      return;
   }

   TeacherMarkerOrderInfo current[];
   CollectTeacherMobileMarkerOrders(current);
   bool levelMatched[];
   ArrayResize(levelMatched,expected);
   ArrayInitialize(levelMatched,false);
   bool usedTags[];
   ArrayResize(usedTags,MAX_TEACHER_MARKER_LEVELS+1);
   ArrayInitialize(usedTags,false);
   for(int j=0;j<ArraySize(current);j++)
      if(current[j].tagIndex>=1 && current[j].tagIndex<ArraySize(usedTags)) usedTags[current[j].tagIndex]=true;

   for(int i=0;i<expected;i++)
   {
      for(int j=0;j<ArraySize(current);j++)
      {
         if(current[j].keep) continue;
         if(!TeacherMarkerOrderMatchesLevel(current[j],缓存老师点位[i],markerPrice,markerVolume)) continue;
         current[j].keep=true;
         levelMatched[i]=true;
         break;
      }
   }

   for(int j=0;j<ArraySize(current);j++)
   {
      if(current[j].keep) continue;
      bool submitted=RequestMobileMarkerDelete(current[j].ticket);
      uint retcode=markerTrade.ResultRetcode();
      if(submitted)
         PrintFormat("TEACHER_MARKER_DELETE_REQUEST ticket=%I64u tag=%s reason=not_in_target_set ret=%u",
                     current[j].ticket,current[j].tag,retcode);
   }

   if(!ReconcileMobileMarkerDeletes())
   {
      SetTeacherMarkerSyncStatus("老师点位：等待旧订单撤销/成交结算确认",expected,0,expected);
      return;
   }
   for(int i=0;i<expected;i++)
   {
      if(levelMatched[i]) continue;
      string tag=NextUnusedTeacherMarkerTag(usedTags);
      if(tag=="")
      {
         老师点位最近错误="无可用老师标记编号，等待旧订单撤销确认";
         continue;
      }
      SubmitTeacherMobileMarker(缓存老师点位[i],tag);
   }

   TeacherMarkerOrderInfo actual[];
   CollectTeacherMobileMarkerOrders(actual);
   bool actualMatched[];
   ArrayResize(actualMatched,expected);
   ArrayInitialize(actualMatched,false);
   int active=0;
   for(int i=0;i<expected;i++)
   {
      for(int j=0;j<ArraySize(actual);j++)
      {
         if(!TeacherMarkerOrderMatchesLevel(actual[j],缓存老师点位[i],markerPrice,markerVolume)) continue;
         actualMatched[i]=true;
         active++;
         break;
      }
   }
   int failed=MathMax(expected-active,0);
   int extras=MathMax(ArraySize(actual)-active,0);
   string status="";
   if(active==expected && extras==0)
      status=StringFormat("老师点位：已同步%d条",expected);
   else if(extras>0)
      status=StringFormat("老师点位：%d/%d条，撤销中",active,expected);
   else
      status=StringFormat("老师点位：%d/%d条，%d条失败",active,expected,failed);
   SetTeacherMarkerSyncStatus(status,expected,active,failed);
}

bool SyncOneMobileMarker(string tag, double targetPrice, bool resistanceAsBuyTP)
{
   if(targetPrice <= 0.0)
   {
      DeleteMobileMarkerOrders(tag);
      return false;
   }

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0.0 || ask <= 0.0) return false;

   double markerPrice = NormalizePrice(手机标记挂单固定价格);
   double target = NormalizePrice(targetPrice);
   if(markerPrice <= 0.0) return false;

   // 如果已有标记挂单离当前价过近，先撤掉，防止真的成交。
   ulong oldTicket = 0;
   double oldPrice = 0.0;
   double oldSL = 0.0;
   double oldTP = 0.0;
   ENUM_ORDER_TYPE oldType = WRONG_VALUE;
   if(FindMobileMarkerOrder(tag, oldTicket, oldPrice, oldSL, oldTP, oldType))
   {
      if(bid - oldPrice <= 手机标记危险距离)
      {
         DeleteMobileMarkerOrders(tag);
         手机标记状态 = "接近触发，已请求撤单";
         return false;
      }

      double oldTarget = resistanceAsBuyTP ? oldTP : oldSL;
      ENUM_ORDER_TYPE needType = resistanceAsBuyTP ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_STOP;
      if(oldType == needType && MathAbs(oldPrice - markerPrice) <= _Point * 5)
      {
         if(MathAbs(oldTarget - target) <= _Point * 5)
            return true;

         // 价格只是小幅刺破旧R/S时，旧点位仍有参考价值，不因为重算出的新点位不同就立刻撤换。
         double mid = (bid + ask) / 2.0;
         bool isPiercingOld = resistanceAsBuyTP ? (mid >= oldTarget) : (mid <= oldTarget);
         if(oldTarget > 0.0 && isPiercingOld && !SRLevelConfirmedBroken(oldTarget, resistanceAsBuyTP))
            return true;
      }

      DeleteMobileMarkerOrders(tag);
   }

   if(!ReconcileMobileMarkerDeletes())
   {
      手机标记状态 = "等待旧标记撤销/成交结算确认";
      return false;
   }
   double vol = 0.0;
   if(!NormalizeMarkerVolume(手机标记挂单手数, vol))
   {
      手机标记状态 = "手数低于最小值";
      return false;
   }

   // 手机标记不是靠服务器到期来更新；默认使用GTC，由EA根据R/S变化或突破事件主动撤旧挂新。
   // 某些服务器不接受过短的ORDER_TIME_SPECIFIED，使用GTC更稳。
   ENUM_ORDER_TYPE_TIME typeTime = ORDER_TIME_GTC;
   datetime expiration = 0;
   if(手机标记有效分钟 > 0)
   {
      typeTime = ORDER_TIME_SPECIFIED;
      expiration = TimeCurrent() + 手机标记有效分钟 * 60;
   }

   markerTrade.SetExpertMagicNumber(手机标记挂单Magic);

   bool priceRuleOk = false;
   if(resistanceAsBuyTP)
   {
      // 压力位：用多单的TP线显示。手机端看到TP线即可识别为压力。
      priceRuleOk = MarkerBuyLimitTPValid(markerPrice, target);
      if(!priceRuleOk)
      {
         手机标记状态 = "R价规不合法";
         return false;
      }
   }
   else
   {
      // 支撑位：用空单的SL线显示。手机端看到SL线即可识别为支撑。
      priceRuleOk = MarkerSellStopSLValid(markerPrice, target);
      if(!priceRuleOk)
      {
         手机标记状态 = "S价规不合法";
         return false;
      }
   }

   bool ok = false;
   if(resistanceAsBuyTP)
      ok = markerTrade.BuyLimit(vol, markerPrice, _Symbol, 0.0, target, typeTime, expiration, tag);
   else
      ok = markerTrade.SellStop(vol, markerPrice, _Symbol, target, 0.0, typeTime, expiration, tag);

   // 兼容保底：如果用户手动设置了有效分钟，而服务器拒绝到期时间，则退回GTC。
   if(!ok && markerTrade.ResultRetcode() == 10022 && typeTime != ORDER_TIME_GTC)
   {
      if(resistanceAsBuyTP)
         ok = markerTrade.BuyLimit(vol, markerPrice, _Symbol, 0.0, target, ORDER_TIME_GTC, 0, tag);
      else
         ok = markerTrade.SellStop(vol, markerPrice, _Symbol, target, 0.0, ORDER_TIME_GTC, 0, tag);

      if(ok)
      {
         手机标记状态 = "GTC兼容";
         lastStatus = "手机标记: 已改用GTC，突破后由EA即时撤换";
         return true;
      }
   }

   uint retcode=markerTrade.ResultRetcode();
   if(retcode==TRADE_RETCODE_MARKET_CLOSED)
   {
      手机标记状态 = "休市等待";
      lastStatus = "休市：提示挂单等待开市同步";
      return false;
   }
   if(!ok)
   {
      手机标记状态 = StringFormat("下单失败%d", retcode);
      lastStatus = "手机标记挂单失败: " + markerTrade.ResultComment();
      return false;
   }

   return true;
}

void ManageMobileMarkerOrders(bool force=false)
{
   PerformanceScope perfScope(PERF_MOBILE_MARKERS);
   if(force && 缓存老师点位原文!=老师点位文本)
      RefreshTeacherMarkerCache();
   datetime now=TimeCurrent();
   ReconcileMobileMarkerDeletes();
   if(!当前启用手机标记挂单())
   {
      手机标记状态 = 启用手机标记挂单 ? "面板已关闭" : "配置关闭";
      if(手机标记环境Dirty) force=true;
      bool cleanupDue=force || 上次手机标记刷新时间<=0 ||
                      now-上次手机标记刷新时间>=手机标记刷新秒数;
      if(cleanupDue)
      {
         int remaining=CountAllMobileMarkerOrders();
         if(remaining>0)
         {
            DeleteMobileMarkerOrders();
            remaining=CountAllMobileMarkerOrders();
         }
         手机标记禁用已清理=(remaining==0 && ArraySize(mobileMarkerDeleteTickets)==0);
         if(remaining>0)
            手机标记状态=StringFormat("%s：撤销中%d",手机标记状态,remaining);
         上次手机标记刷新时间=now;
      }
      手机标记环境Dirty=false;
      return;
   }
   手机标记禁用已清理 = false;

   if(手机标记环境Dirty) force=true;
   bool effectiveForce=force;

   if(手机标记来源模式==手机标记来源_老师文本无效)
   {
      if(IsHedgingAccount()) CloseMobileMarkerPositions();
      if(!force && 上次手机标记刷新时间>0 && now-上次手机标记刷新时间<手机标记刷新秒数)
         return;
      DeleteMobileMarkerOrders();
      string invalidStatus=TeacherMarkerInvalidStatusText();
      SetTeacherMarkerSyncStatus(invalidStatus,缓存老师点位数量,0,缓存老师点位数量);
      上次手机标记刷新时间=now;
      手机标记环境Dirty=false;
      return;
   }

   if(!IsHedgingAccount())
   {
      手机标记状态 = "非对冲账户禁用";
      DeleteMobileMarkerOrders();
      上次手机标记刷新时间=now;
      手机标记环境Dirty=false;
      return;
   }

   CloseMobileMarkerPositions();

   if(手机标记来源模式==手机标记来源_老师文本)
   {
      if(!force && 上次手机标记刷新时间>0 && now-上次手机标记刷新时间<手机标记刷新秒数)
         return;
      int automaticCount=CountMobileMarkerOrdersBySource(false,true);
      if(automaticCount>0)
      {
         RequestDeleteMobileMarkerOrdersBySource(false,true,"switch_to_teacher_source");
         automaticCount=CountMobileMarkerOrdersBySource(false,true);
         if(automaticCount>0)
         {
            SetTeacherMarkerSyncStatus("老师点位：切换中，正在撤自动标记",缓存老师点位数量,0,缓存老师点位数量);
            上次手机标记刷新时间=now;
            手机标记环境Dirty=false;
            return;
         }
      }
      SyncTeacherMobileMarkers(effectiveForce);
      上次手机标记刷新时间=now;
      手机标记环境Dirty=false;
      return;
   }

   int teacherCount=CountMobileMarkerOrdersBySource(true,false);
   if(teacherCount>0)
   {
      RequestDeleteMobileMarkerOrdersBySource(true,false,"switch_to_auto_source");
      teacherCount=CountMobileMarkerOrdersBySource(true,false);
      if(teacherCount>0)
      {
         手机标记状态="自动R/S：正在撤老师标记";
         lastStatus=手机标记状态;
         上次手机标记刷新时间=now;
         手机标记环境Dirty=false;
         return;
      }
   }

   if(任意交易时撤手机标记 && HasNonMarkerTradeOnCurrentSymbol())
   {
      DeleteMobileMarkerOrders();
      手机标记状态 = "已有交易已撤";
      上次手机标记刷新时间 = now;
      手机标记环境Dirty=false;
      return;
   }

   if(当前参数配置模板 == 配置_黄金超短快保 &&
      短线单持仓时撤手机标记 &&
      HasManagedPosition())
   {
      DeleteMobileMarkerOrders();
      手机标记状态 = "短线持仓已撤";
      上次手机标记刷新时间 = now;
      手机标记环境Dirty=false;
      return;
   }

   bool broken = MobileMarkerLevelBroken();
   if(broken)
   {
      // M1收线确认大突破后才重算R/S；小幅刺破继续保留旧点位参考。
      RefreshMarketStructureCaches(true);
      force = true;
      手机标记状态 = "突破刷新";
   }

   if(!force && 上次手机标记刷新时间 > 0 && now - 上次手机标记刷新时间 < 手机标记刷新秒数)
      return;

   if(ArraySize(缓存压力位) <= 0 && ArraySize(缓存支撑位) <= 0)
   {
      手机标记状态 = "无R/S点位";
      DeleteMobileMarkerOrders();
      上次手机标记刷新时间 = now;
      手机标记环境Dirty=false;
      return;
   }

   int markerCount = MathMin(MathMax(手机标记每侧点位数, 1), 2); // 手机端默认只同步两档，避免线太多。
   int okRCount = 0;
   int okSCount = 0;

   for(int i=0; i<2; i++)
   {
      string rTag = "SMA_MARK_R" + IntegerToString(i + 1);
      if(i < markerCount && i < ArraySize(缓存压力位))
      {
         if(SyncOneMobileMarker(rTag, 缓存压力位[i].price, true)) // 多单TP = 压力位
            okRCount++;
      }
      else
      {
         DeleteMobileMarkerOrders(rTag);
      }

      string sTag = "SMA_MARK_S" + IntegerToString(i + 1);
      if(i < markerCount && i < ArraySize(缓存支撑位))
      {
         if(SyncOneMobileMarker(sTag, 缓存支撑位[i].price, false)) // 空单SL = 支撑位
            okSCount++;
      }
      else
      {
         DeleteMobileMarkerOrders(sTag);
      }
   }

   上次手机标记刷新时间 = now;
   if(okRCount > 0 || okSCount > 0)
      手机标记状态 = StringFormat("R%d多TP/S%d空SL", okRCount, okSCount);
   else if(手机标记状态 == "")
      手机标记状态 = "同步失败";
   手机标记环境Dirty=false;
}

#include "Include/Trading/TeacherAuto.mqh"

string 简化面板模板名称(int templateId)
{
   if(templateId == (int)配置_黄金超短快保) return "短线";
   if(templateId == (int)配置_黄金稳健托管) return "长线";
   if(templateId == (int)配置_黄金支压止盈) return "手动";
   if(templateId == (int)配置_黄金消息对冲) return "对冲";
   return "自定义";
}

string 简化面板下一步提示(int templateId, ENUM_POSITION_TYPE type, double openPrice, double sl, double tp)
{
   bool profitLocked = (sl > 0.0 && ((type == POSITION_TYPE_BUY && sl >= openPrice) ||
                                     (type == POSITION_TYPE_SELL && sl <= openPrice)));
   if(templateId == (int)配置_黄金支压止盈)
      return "只提示，不会自动修改你的单子";
   if(templateId == (int)配置_黄金消息对冲)
      return NewsHedgeGroupActive() ? "对冲组合继续风控和拆锁" : "等待另一边配对";
   if(templateId == (int)配置_黄金稳健托管)
      return profitLocked ? "已保护利润，继续跟随趋势" : "等待走出利润后再保护";
   if(templateId == (int)配置_黄金超短快保)
      return profitLocked ? "已保护，按短线节奏跟随" : (tp > 0.0 ? "等待保本或到止盈" : "等待保本后跟随");
   return profitLocked ? "已保护，继续按自定义规则管理" : "等待达到保护条件";
}

void DrawSimpleHoldingPanel(double bid, double ask, double spread, color spreadColor)
{
   int panelHeight = 170;
   DrawPanelBackground(panelHeight);
   DeleteLifecycleStatsButtons();
   ObjectDelete(0, "SMA_BTN_STAT_DAY");
   ObjectDelete(0, "SMA_BTN_STAT_WEEK");
   ObjectDelete(0, "SMA_BTN_STAT_MONTH");
   ObjectDelete(0, "SMA_BTN_NEWS_FREEZE");
   ObjectDelete(0, "SMA_BTN_NEWS_RELEASE");
   ObjectDelete(0, "SMA_BTN_NEWS_CANCEL");
   ObjectDelete(0, "SMA_BTN_NEWS_FLAT");

    // 当前模板由下方高亮卡片表示，标题不再重复显示，给右侧顶栏留出稳定空间。
    SetPanelLine("SMA_PANEL_1", 12,
                 StringFormat("%s  ·  %s", _Symbol,
                              HasManagedPosition() ? "托管中" : "空仓"), spreadColor);
    DrawTemplateButtons(12, 42);
    CreatePanelButton("SMA_BTN_MARKER_VIS",
                      当前启用手机标记挂单() ? "提示挂单：开" : (启用手机标记挂单 ? "提示挂单：关" : "提示挂单：配置关"),
                      12, 70, 126, 22, 启用手机标记挂单);

   int line = 2;
   int managed = 0;
   int noSLCount = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket) || !PositionInScope()) continue;
      managed++;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int stateIdx = FindState(ticket);
      int templateId = stateIdx >= 0 ? states[stateIdx].adoptedTemplate : (int)当前参数配置模板;
      double currentPrice = type == POSITION_TYPE_BUY ? bid : ask;
      double profitPrice = type == POSITION_TYPE_BUY ? currentPrice-openPrice : openPrice-currentPrice;
      int heldMinutes = (int)MathMax((long)(TimeCurrent()-openTime), 0) / 60;
      bool profitLocked = (sl > 0.0 && ((type == POSITION_TYPE_BUY && sl >= openPrice) ||
                                        (type == POSITION_TYPE_SELL && sl <= openPrice)));
      color profitColor = profit > 0.005 ? LegacyProfitColor() : (profit < -0.005 ? LegacyLossColor() : LegacyFlatColor());
      color protectionColor = sl <= 0.0 ? LegacyDangerColor() : (profitLocked ? LegacySafeColor() : clrGold);
      if(sl <= 0.0) noSLCount++;

       int y = 102 + (managed-1) * 面板行距 * 5;
      SetPanelLine("SMA_PANEL_" + IntegerToString(line++), y,
                   StringFormat("%d. %s %.2f手 | 开 %.2f | 现 %.2f", managed,
                                type == POSITION_TYPE_BUY ? "多" : "空", volume, openPrice, currentPrice), clrWhite);
      SetPanelLine("SMA_PANEL_" + IntegerToString(line++), y + 面板行距,
                   StringFormat("盈亏 %s | 浮动 %s | 持有 %d 分钟", FormatMiniSignedProfit(profit,2), FormatMiniSignedProfit(profitPrice,2), heldMinutes), profitColor);
      SetPanelLine("SMA_PANEL_" + IntegerToString(line++), y + 面板行距 * 2,
                   StringFormat("类型：%s（已锁定） | %s", 简化面板模板名称(templateId),
                                sl > 0.0 ? (profitLocked ? "已锁利润" : "止损已设") : "没有止损"), protectionColor);
      string slText = sl > 0.0 ? StringFormat("SL %.2f（距%.2f）", sl, MathAbs(currentPrice-sl)) : "SL 未设置";
      string tpText = tp > 0.0 ? StringFormat("TP %.2f（距%.2f）", tp, MathAbs(tp-currentPrice)) : "TP 不固定";
      SetPanelLine("SMA_PANEL_" + IntegerToString(line++), y + 面板行距 * 3,
                   "保护价：" + slText + " | " + tpText, protectionColor);
      SetPanelLine("SMA_PANEL_" + IntegerToString(line++), y + 面板行距 * 4,
                   "脚本：" + 简化面板下一步提示(templateId, type, openPrice, sl, tp), clrSilver);
   }

    int footerY = 102 + managed * 面板行距 * 5 + 4;
   color riskColor = noSLCount > 0 ? LegacyDangerColor() : (managed > 0 ? LegacySafeColor() : clrSilver);
   string riskText = managed == 0 ? "账户风险：当前没有受管持仓" :
                     (noSLCount > 0 ? StringFormat("账户风险：有 %d 单没有止损", noSLCount) : "账户风险：所有受管单均已设止损");
   SetPanelLine("SMA_PANEL_" + IntegerToString(line++), footerY, riskText, riskColor);
   SetPanelLine("SMA_PANEL_" + IntegerToString(line++), footerY + 面板行距,
                "提示：右上角“专业”可查看箱体、分批、统计等详细信息", clrDimGray);
   ClearPanelLinesFrom(line);
   ResizePanelBackgroundHeight(footerY + 面板行距 * 2 + 12);
   DrawPanelHeaderButtons();
}

uint CanvasThemeBackground() { return CanvasPanelTheme.background; }
uint CanvasThemeHeader()     { return CanvasPanelTheme.header; }
uint CanvasThemeCard()       { return CanvasPanelTheme.surface; }
uint CanvasThemeSurfaceAlt() { return CanvasPanelTheme.surfaceAlt; }
uint CanvasThemeHover()      { return CanvasPanelTheme.hover; }
uint CanvasThemeBorder()     { return CanvasPanelTheme.border; }
uint CanvasThemeText()       { return CanvasPanelTheme.text; }
uint CanvasThemeMuted()      { return CanvasPanelTheme.muted; }
uint CanvasThemeDim()        { return CanvasPanelTheme.dim; }
uint CanvasThemeAccent()     { return CanvasPanelTheme.accent; }
uint CanvasThemeProfit()     { return CanvasPanelTheme.profit; }
uint CanvasThemeLoss()       { return CanvasPanelTheme.loss; }
uint CanvasThemeSuccess()    { return CanvasPanelTheme.successText; }
uint CanvasThemeDanger()     { return CanvasPanelTheme.dangerText; }
uint CanvasThemeWarning()    { return CanvasPanelTheme.warning; }

uint CanvasPnLColor(double value)
{
   if(value>0.005) return CanvasPanelTheme.profit;
   if(value<-0.005) return CanvasPanelTheme.loss;
   return CanvasPanelTheme.pnlFlat;
}

#include "Include/UI/CanvasPanel.mqh"

void ShowPanel()
{
   if(!显示简洁面板) return;

   if(使用新版Canvas面板 && (当前面板显示模式==面板迷你 || 当前面板显示模式==面板隐藏))
   {
      ShowCanvasMiniOrHiddenPanel();
      return;
   }
   if(使用新版Canvas面板 && 当前面板显示模式==面板完整 && 当前面板页面==页面持仓)
   {
      ShowCanvasHoldingPanel();
      return;
   }
   if(使用新版Canvas面板 && 当前面板显示模式==面板完整 && 当前面板页面==页面今日)
   {
      ShowCanvasStatsPanel();
      return;
   }
   if(ObjectFind(0,"SMA_CANVAS")>=0) CanvasPanelRenderer.Destroy();
   CanvasLegacyObjectsCleared=false;
   CanvasPanelLayoutValid=false;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double spread = (bid > 0 && ask > 0) ? (ask - bid) / _Point : 0;
   color spreadColor = (忽略点差过滤 || spread <= 最大点差点数) ? clrWhite : LegacyDangerColor();
   double midPrice = (bid > 0 && ask > 0) ? (bid + ask) / 2.0 : 0.0;

   if(当前面板显示模式 == 面板隐藏)
   {
      DrawCollapsedPanel();
      return;
   }

   if(当前面板显示模式 == 面板迷你)
   {
      DrawMiniPanel(bid, ask, spread, spreadColor, midPrice);
      return;
   }

   if(当前面板页面 == 页面持仓 && 当前面板信息模式 == 面板信息_简单)
   {
      DrawSimpleHoldingPanel(bid, ask, spread, spreadColor);
      return;
   }

   int panelHeight = (当前面板页面 == 页面今日) ? 470 : 450;
   DrawPanelBackground(panelHeight);

   if(当前面板页面 == 页面今日)
   {
      // 配置模板切换按钮只放在“仓”页面；统计页强制清掉，避免残留。
      ObjectDelete(0, "SMA_BTN_CFG_CUSTOM");
      ObjectDelete(0, "SMA_BTN_CFG_FAST");
      ObjectDelete(0, "SMA_BTN_CFG_TREND");
      ObjectDelete(0, "SMA_BTN_CFG_SRTP");
      ObjectDelete(0, "SMA_BTN_CFG_NEWS");
      ObjectDelete(0, "SMA_BTN_MARKER_VIS");

      DrawLifecycleStatisticsPage(spread, spreadColor);
      return;

      TodayStats st;
      GetCurrentStats(st);

      double winRate = (st.closes > 0) ? (100.0 * st.wins / st.closes) : 0.0;
      color profitColor = st.profit > 0.005 ? LegacyProfitColor() : (st.profit < -0.005 ? LegacyLossColor() : LegacyFlatColor());
      color pfColor = clrSilver;
      if(st.closes >= 3 && st.profitFactor > 0.0 && st.profitFactor < 1.0) pfColor = LegacyDangerColor();
      else if(st.profitFactor >= 1.2) pfColor = LegacySafeColor();
      color streakColor = st.currentLossStreak >= 3 ? LegacyDangerColor() : (st.currentLossStreak >= 2 ? clrOrange : clrSilver);

      string pfText = (st.profitFactor > 0.0) ? DoubleToString(st.profitFactor, 2) : "-";
      string payoffText = (st.payoffRatio > 0.0) ? DoubleToString(st.payoffRatio, 2) : "-";
      string rangeText = 统计页仅统计受管Magic ? (只管理手动单 ? "当前品种受管Magic=0" : "当前品种受管Magic=" + (string)指定管理Magic) : "当前品种全部Magic";

      string periodText = "";
      string periodRangeText = "";
      if(当前统计周期 == 统计_日)
      {
         periodText = "日统计";
         periodRangeText = FormatBJDate(st.bjDate);
      }
      else if(当前统计周期 == 统计_周)
      {
         periodText = "周统计";
         periodRangeText = FormatBJDate(st.bjDate) + "-" + FormatBJDate(st.bjDate + 4 * 86400);
      }
      else
      {
         periodText = "月统计";
         periodRangeText = FormatBJDate(st.bjDate) + "-" + FormatBJDate(AddBJMonths(st.bjDate, 1) - 86400);
      }

      SetPanelLine("SMA_PANEL_1", 12, StringFormat("交易统计 | %s | %s", periodText, _Symbol), clrAqua);

      double avgNet = (st.closes > 0) ? st.profit / st.closes : 0.0;
      double avgHoldMinutes = (st.closes > 0) ? st.totalHoldMinutes / st.closes : 0.0;
      double netPerLot = (st.closeLots > 0.0) ? st.profit / st.closeLots : 0.0;
      double avgPriceDiff = (st.closes > 0) ? st.priceDiff / st.closes : 0.0;
      string buyProfitText = (st.buyCloses > 0) ? DoubleToString(st.buyProfit, 2) : "-";
      string sellProfitText = (st.sellCloses > 0) ? DoubleToString(st.sellProfit, 2) : "-";

      CreatePanelButton("SMA_BTN_STAT_DAY", "日统计", 12, 40, 64, 22, 当前统计周期 == 统计_日);
      CreatePanelButton("SMA_BTN_STAT_WEEK", "周统计", 82, 40, 64, 22, 当前统计周期 == 统计_周);
      CreatePanelButton("SMA_BTN_STAT_MONTH", "月统计", 152, 40, 64, 22, 当前统计周期 == 统计_月);

      if(当前统计周期 == 统计_日)
      {
         CreatePanelButton("SMA_BTN_PREV_DAY", "前一天", 12, 66, 64, 22, false);
         CreatePanelButton("SMA_BTN_TODAY", "今日", 82, 66, 52, 22, 统计日期偏移天数 == 0);
         CreatePanelButton("SMA_BTN_NEXT_DAY", "后一天", 140, 66, 64, 22, false);
         ObjectDelete(0, "SMA_BTN_PREV_WEEK");
         ObjectDelete(0, "SMA_BTN_THIS_WEEK");
         ObjectDelete(0, "SMA_BTN_NEXT_WEEK");
         ObjectDelete(0, "SMA_BTN_PREV_MONTH");
         ObjectDelete(0, "SMA_BTN_THIS_MONTH");
         ObjectDelete(0, "SMA_BTN_NEXT_MONTH");
      }
      else if(当前统计周期 == 统计_周)
      {
         CreatePanelButton("SMA_BTN_PREV_WEEK", "前一周", 12, 66, 64, 22, false);
         CreatePanelButton("SMA_BTN_THIS_WEEK", "本周", 82, 66, 52, 22, 统计周偏移周数 == 0);
         CreatePanelButton("SMA_BTN_NEXT_WEEK", "后一周", 140, 66, 64, 22, false);
         ObjectDelete(0, "SMA_BTN_PREV_DAY");
         ObjectDelete(0, "SMA_BTN_TODAY");
         ObjectDelete(0, "SMA_BTN_NEXT_DAY");
         ObjectDelete(0, "SMA_BTN_PREV_MONTH");
         ObjectDelete(0, "SMA_BTN_THIS_MONTH");
         ObjectDelete(0, "SMA_BTN_NEXT_MONTH");
      }
      else
      {
         CreatePanelButton("SMA_BTN_PREV_MONTH", "前月", 12, 66, 52, 22, false);
         CreatePanelButton("SMA_BTN_THIS_MONTH", "本月", 70, 66, 52, 22, 统计月偏移月数 == 0);
         CreatePanelButton("SMA_BTN_NEXT_MONTH", "后月", 128, 66, 52, 22, false);
         ObjectDelete(0, "SMA_BTN_PREV_DAY");
         ObjectDelete(0, "SMA_BTN_TODAY");
         ObjectDelete(0, "SMA_BTN_NEXT_DAY");
         ObjectDelete(0, "SMA_BTN_PREV_WEEK");
         ObjectDelete(0, "SMA_BTN_THIS_WEEK");
         ObjectDelete(0, "SMA_BTN_NEXT_WEEK");
      }

      int y0 = 96;
      // 统计页布局按模块分组：周期/交易量/胜率/盈亏/效率/方向/持仓时长/极值/风控。
      SetPanelLine("SMA_PANEL_2", y0, StringFormat("周期: %s | %s | 北京时间", periodText, periodRangeText), clrWhite);
      SetPanelLine("SMA_PANEL_3", y0 + 面板行距, StringFormat("范围: %s | %s", rangeText, FormatSpreadText(spread)), spreadColor);

      SetPanelLine("SMA_PANEL_4", y0 + 面板行距 * 2, StringFormat("成交: 入%d / 平%d | 入场手数: %.2f | 平仓手数: %.2f", st.entries, st.closes, st.lots, st.closeLots), clrWhite);
      SetPanelLine("SMA_PANEL_5", y0 + 面板行距 * 3, StringFormat("胜负: 胜%d / 负%d / 平%d | 胜率: %.1f%%", st.wins, st.losses, st.breakevens, winRate), st.wins >= st.losses ? LegacySafeColor() : clrOrange);

      SetPanelLine("SMA_PANEL_6", y0 + 面板行距 * 4, StringFormat("盈亏: %s | 单均: %s | 每手: %s", FormatMiniSignedProfit(st.profit,2), FormatMiniSignedProfit(avgNet,2), FormatMiniSignedProfit(netPerLot,2)), profitColor);
      SetPanelLine("SMA_PANEL_7", y0 + 面板行距 * 5, StringFormat("价格: 总差 %s | 单均 %s | MT5点 %s", FormatMiniSignedProfit(st.priceDiff,2), FormatMiniSignedProfit(avgPriceDiff,2), FormatMiniSignedProfit(st.points,0)), profitColor);
      SetPanelLine("SMA_PANEL_8", y0 + 面板行距 * 6, StringFormat("总盈: %s | 总亏: %s | PF: %s", FormatMiniSignedProfit(st.grossProfit,2), FormatMiniSignedProfit(-MathAbs(st.grossLoss),2), pfText), pfColor);
      SetPanelLine("SMA_PANEL_9", y0 + 面板行距 * 7, StringFormat("均盈: %s | 均亏: %s | 盈亏比: %s", FormatMiniSignedProfit(st.avgWin,2), FormatMiniSignedProfit(-MathAbs(st.avgLoss),2), payoffText), clrSilver);

      SetPanelLine("SMA_PANEL_10", y0 + 面板行距 * 8, StringFormat("方向: 多%d 笔/%s | 空%d 笔/%s", st.buyCloses, buyProfitText, st.sellCloses, sellProfitText), (st.buyProfit + st.sellProfit) >= 0.0 ? clrSilver : clrOrange);
      SetPanelLine("SMA_PANEL_11", y0 + 面板行距 * 9, StringFormat("持仓时长: 平均 %.0f 分钟 | 最长 %.0f 分钟", avgHoldMinutes, st.maxHoldMinutes), clrSilver);
      SetPanelLine("SMA_PANEL_12", y0 + 面板行距 * 10, StringFormat("单笔极值: 最佳 %.2f | 最差 %.2f", st.bestProfit, st.worstProfit), clrSilver);
      SetPanelLine("SMA_PANEL_13", y0 + 面板行距 * 11, StringFormat("连亏: 当前 %d | 最大 %d", st.currentLossStreak, st.maxLossStreak), streakColor);
      SetPanelLine("SMA_PANEL_14", y0 + 面板行距 * 12, StringFormat("回撤: 已实现DD %.2f | 峰值 %.2f", st.maxRealizedDrawdown, st.realizedEquityPeak), st.maxRealizedDrawdown > 0 ? clrOrange : clrSilver);

      SetPanelLine("SMA_PANEL_15", y0 + 面板行距 * 13, StringFormat("统计区间: %s 至 %s", FormatBeijingTime(st.bjStartServer), FormatBeijingTime(st.bjEndServer)), clrDimGray);
      SetPanelLine("SMA_PANEL_16", y0 + 面板行距 * 14, "状态: " + lastStatus, clrYellow);
      for(int k=17; k<=24; k++)
         ObjectDelete(0, "SMA_PANEL_" + IntegerToString(k));
      ResizePanelBackgroundHeight(y0 + 面板行距 * 15 + 10);
      DrawPanelHeaderButtons(); // 固定宽度模式下刷新顶部按钮位置
      return;
   }

   ObjectDelete(0, "SMA_BTN_STAT_DAY");
   ObjectDelete(0, "SMA_BTN_STAT_WEEK");
   ObjectDelete(0, "SMA_BTN_STAT_MONTH");
   ObjectDelete(0, "SMA_BTN_PREV_DAY");
   ObjectDelete(0, "SMA_BTN_TODAY");
   ObjectDelete(0, "SMA_BTN_NEXT_DAY");
   ObjectDelete(0, "SMA_BTN_PREV_WEEK");
   ObjectDelete(0, "SMA_BTN_THIS_WEEK");
   ObjectDelete(0, "SMA_BTN_NEXT_WEEK");
   ObjectDelete(0, "SMA_BTN_PREV_MONTH");
   ObjectDelete(0, "SMA_BTN_THIS_MONTH");
   ObjectDelete(0, "SMA_BTN_NEXT_MONTH");
   DeleteLifecycleStatsButtons();

   // 先写正式仓页标题，避免刷新过程中露出旧的“Manual Assist EA”占位标题。
   SetPanelLine("SMA_PANEL_1", 12,
                StringFormat("%s | %s | %s",
                             _Symbol,
                             HasManagedPosition() ? "托管中" : "空仓",
                             FormatSpreadText(spread)),
                spreadColor);

    // 配置模板按钮只在“仓”页面显示，避免统计页拥挤和误触。
    DrawTemplateButtons(12, 40);
    CreatePanelButton("SMA_BTN_MARKER_VIS",
                      当前启用手机标记挂单() ? "提示挂单：开" : (启用手机标记挂单 ? "提示挂单：关" : "提示挂单：配置关"),
                      12, 68, 126, 22, 启用手机标记挂单);
   int managed = 0;
   int buyCount = 0, sellCount = 0;
   int slCount = 0, tpCount = 0;
   int protectedCount = 0, trailingReadyCount = 0, drawdownWatchCount = 0;
   double buyLots = 0.0, sellLots = 0.0;
   double buyPV = 0.0, sellPV = 0.0;
   double floatingProfit = 0.0;
   double maxProfitPrice = 0.0;
   int maxHeldMinutes = 0;
   int noSLCount = 0, noTPCount = 0, timeoutCount = 0, lossWarnCount = 0;
   int partialDoneCount = 0;
   int maxPartialStage = 0;
   double nearestBE = -1.0, nearestTrail = -1.0, nearestDD = -1.0, nearestPartial = -1.0;
   bool beTriggered = false, trailTriggered = false, ddTriggered = false, partialTriggered = false;
   double maxProfitDrawdownRatio = -1.0;
   double bestTargetSpace = -1.0, worstTargetSpace = -1.0;
   double worstSLRiskDistance = -1.0, worstSpaceRiskRatio = -1.0;
   bool hasSpaceRiskRatio = false;
   bool hasTrendPanelPosition = false;
   bool trendPanelMixed = false;
   ENUM_POSITION_TYPE trendPanelType = POSITION_TYPE_BUY;
   double trendPanelRisk = 0.0;
   double trendPanelProfit = 0.0;
   double trendPanelMaxProfit = 0.0;
   string slWarningText = "正常";
   color slWarningColor = LegacySafeColor();

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
      if(!PositionInScope()) continue;

      managed++;
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double profit = PositionGetDouble(POSITION_PROFIT)
                    + PositionGetDouble(POSITION_SWAP);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

      if(sl > 0) slCount++;
      else noSLCount++;
      if(tp > 0) tpCount++;
      else noTPCount++;
      floatingProfit += profit;

      double bidNow = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double askNow = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profitPrice = (type == POSITION_TYPE_BUY) ? (bidNow - openPrice) : (openPrice - askNow);
      if(profitPrice > maxProfitPrice) maxProfitPrice = profitPrice;
      if(profit < 0.0 && MathAbs(profit) >= 持仓页浮亏预警金额)
         lossWarnCount++;

      int stateIdx = FindState((ulong)PositionGetInteger(POSITION_TICKET));
      if(当前模板使用黄金稳健止损())
      {
         double r = 0.0;
         if(stateIdx >= 0 && states[stateIdx].trendRiskReady && states[stateIdx].trendInitialRisk > 0.0)
            r = states[stateIdx].trendInitialRisk;

         if(!hasTrendPanelPosition)
         {
            hasTrendPanelPosition = true;
            trendPanelType = type;
            trendPanelRisk = r;
            trendPanelProfit = profitPrice;
            trendPanelMaxProfit = (stateIdx >= 0) ? states[stateIdx].maxProfitPrice : profitPrice;
         }
         else if(type != trendPanelType)
         {
            trendPanelMixed = true;
         }
      }
      if(stateIdx >= 0)
      {
         if(states[stateIdx].partialTPDone) partialDoneCount++;
         if(states[stateIdx].partialTPStage > maxPartialStage)
            maxPartialStage = states[stateIdx].partialTPStage;
         if(states[stateIdx].maxProfitPrice > 0.0)
         {
            double ddRatio = (states[stateIdx].maxProfitPrice - profitPrice) / states[stateIdx].maxProfitPrice;
            if(ddRatio > maxProfitDrawdownRatio)
               maxProfitDrawdownRatio = ddRatio;
         }
      }

      if(当前参数配置模板 == 配置_黄金超短快保 &&
         短线单启用多段分批止盈 &&
         启用分批止盈 &&
         stateIdx >= 0 &&
         states[stateIdx].partialTPStage < MathMin(MathMax(短线单最大分批段数, 1), 2))
      {
         double localATRForPartial = 0.0;
         GetATRPrice(localATRForPartial);
         ShortLineMarketContext panelCtx;
         if(BuildShortLineMarketContext(type, openPrice, (type == POSITION_TYPE_BUY ? bidNow : askNow), localATRForPartial, panelCtx))
         {
            bool panelTeacherSelected = false;
            double panelTeacherTarget = 0.0;
            double baseMainTP = ShortLineEffectiveMainTPDistance(stateIdx, type, openPrice,
                                                                  localATRForPartial,
                                                                  panelTeacherSelected,
                                                                  panelTeacherTarget);
            int nextStage = states[stateIdx].partialTPStage + 1;
            double nextTrigger = ShortLineEffectivePartialTrigger(stateIdx, type, openPrice,
                                                                   nextStage, panelCtx, baseMainTP);
            double needPartial = MathMax(nextTrigger - profitPrice, 0.0);
            if(needPartial <= 0.0)
               partialTriggered = true;
            else if(nearestPartial < 0.0 || needPartial < nearestPartial)
               nearestPartial = needPartial;
         }
      }

      if(启用SL过紧预警 && sl > 0)
      {
         double lockProfit = (type == POSITION_TYPE_BUY) ? (sl - openPrice) : (openPrice - sl);
         double distToSL = (type == POSITION_TYPE_BUY) ? (bidNow - sl) : (sl - askNow);

         if(profitPrice > 0.0 && profitPrice < SL过紧浮盈阈值 && lockProfit > SL提前锁利容忍价格)
         {
            slWarningText = MergeSLWarning(slWarningText, "锁太早，容易被扫");
            slWarningColor = clrOrange;
         }
         if(profitPrice > 0.0 && distToSL > 0.0 && distToSL < SL距离当前价过近)
         {
            slWarningText = MergeSLWarning(slWarningText, "SL贴脸，别太紧");
            slWarningColor = clrOrange;
         }
      }

      if(sl > 0)
      {
         if(type == POSITION_TYPE_BUY && sl >= openPrice) protectedCount++;
         if(type == POSITION_TYPE_SELL && sl <= openPrice) protectedCount++;
      }

      double localTrailTrigger = 移动止损启动价格;
      double localTrailDistance = 移动止损距离价格;
      double localTrailStep = 移动止损最小推进点数 * _Point;
      double localATR = 0.0;
      GetATRPrice(localATR);
      GetAdaptiveTrailConfig(localATR, localTrailTrigger, localTrailDistance, localTrailStep);
      double panelShortRisk = 0.0;
      if(当前参数配置模板 == 配置_黄金超短快保)
      {
         panelShortRisk = (stateIdx >= 0 && states[stateIdx].shortRiskReady) ?
            states[stateIdx].shortInitialRisk : 0.0;
         localTrailTrigger = MathMax(M1结构最小浮盈启动,
                                     localATR > 0.0 ? localATR * M1结构追踪启动ATR倍数 : 0.0);
         localTrailTrigger = MathMax(localTrailTrigger,
                                     panelShortRisk * MathMax(短线单结构追踪最小风险R, 0.10));
      }
      if(profitPrice >= localTrailTrigger)
      {
         trailingReadyCount++;
         trailTriggered = true;
      }
      else if(启用移动止损)
      {
         double need = localTrailTrigger - profitPrice;
         if(need >= 0.0 && (nearestTrail < 0.0 || need < nearestTrail))
            nearestTrail = need;
      }
      double panelDDStart = 回撤保护启动价格;
      if(当前参数配置模板 == 配置_黄金超短快保)
      {
         ShortLineMarketContext panelDDCtx;
         double panelDDRatio = 最大浮盈回撤比例;
         double panelDDLock = 回撤后锁定利润比例;
         if(BuildShortLineMarketContext(type, openPrice, (type == POSITION_TYPE_BUY ? bidNow : askNow), localATR, panelDDCtx))
            GetShortLineDynamicDrawdownProtection(panelDDCtx, panelDDStart, panelDDRatio, panelDDLock);
         panelDDStart = MathMax(panelDDStart,
                                panelShortRisk * MathMax(短线单回撤保护最小风险R, 0.10));
      }
      if(profitPrice >= panelDDStart)
      {
         drawdownWatchCount++;
         ddTriggered = true;
      }
      else if(启用浮盈回撤保护)
      {
         double need = panelDDStart - profitPrice;
         if(need >= 0.0 && (nearestDD < 0.0 || need < nearestDD))
            nearestDD = need;
      }
      double panelBETrigger = 保本触发价格;
      double panelBELock = 保本锁定价格;
      if(当前参数配置模板 == 配置_黄金超短快保)
      {
         double panelMaxProfit = (stateIdx >= 0) ? states[stateIdx].maxProfitPrice : profitPrice;
         ShortLineDynamicBEConfig(type, openPrice, (type == POSITION_TYPE_BUY ? bidNow : askNow),
                                  localATR, profitPrice, panelMaxProfit, panelBETrigger, panelBELock);
         panelBETrigger = MathMax(panelBETrigger,
                                  panelShortRisk * MathMax(短线单保本最小风险R, 0.10));
      }
      bool panelBEConfirmed = (当前参数配置模板 != 配置_黄金超短快保 ||
                               ShortLineProtectionConfirmed(type, openPrice, panelBETrigger));
      if(profitPrice >= panelBETrigger && panelBEConfirmed)
      {
         beTriggered = true;
      }
      else if(启用保本)
      {
         double need = panelBETrigger - profitPrice;
         if(need >= 0.0 && (nearestBE < 0.0 || need < nearestBE))
            nearestBE = need;
      }

      int heldMinutes = (int)((TimeCurrent() - openTime) / 60);
      if(heldMinutes > maxHeldMinutes) maxHeldMinutes = heldMinutes;
      if(最大持仓分钟数 > 0 && heldMinutes >= 最大持仓分钟数)
         timeoutCount++;

      double targetSpace = -1.0;
      SRLevel targetLevel;
      if(type == POSITION_TYPE_BUY && GetNearestResistance(bidNow, targetLevel))
         targetSpace = targetLevel.price - bidNow;
      else if(type == POSITION_TYPE_SELL && GetNearestSupport(askNow, targetLevel))
         targetSpace = askNow - targetLevel.price;

      if(targetSpace >= 0.0)
      {
         if(bestTargetSpace < 0.0 || targetSpace > bestTargetSpace)
            bestTargetSpace = targetSpace;
         if(worstTargetSpace < 0.0 || targetSpace < worstTargetSpace)
            worstTargetSpace = targetSpace;

         if(sl > 0.0)
         {
            double riskDistance = (type == POSITION_TYPE_BUY) ? (bidNow - sl) : (sl - askNow);
            if(riskDistance > 0.0)
            {
               double ratio = targetSpace / riskDistance;
               if(!hasSpaceRiskRatio || ratio < worstSpaceRiskRatio)
               {
                  worstSpaceRiskRatio = ratio;
                  worstSLRiskDistance = riskDistance;
                  hasSpaceRiskRatio = true;
               }
            }
         }

         bool canStillPartial = (stateIdx < 0 || !states[stateIdx].partialTPDone);
         if(当前参数配置模板 == 配置_黄金超短快保 && 短线单启用多段分批止盈 && stateIdx >= 0)
            canStillPartial = (states[stateIdx].partialTPStage < MathMin(MathMax(短线单最大分批段数, 1), 2));
         if(启用分批止盈 && canStillPartial)
         {
            double needProfit = MathMax(分批止盈最小浮盈价格 - profitPrice, 0.0);
            double needDistance = MathMax(targetSpace - 分批止盈接近点位距离, 0.0);
            double needPartial = MathMax(needProfit, needDistance);
            if(needPartial <= 0.0)
               partialTriggered = true;
            else if(nearestPartial < 0.0 || needPartial < nearestPartial)
               nearestPartial = needPartial;
         }
      }

      if(type == POSITION_TYPE_BUY)
      {
         buyCount++;
         buyLots += volume;
         buyPV += openPrice * volume;
      }
      else if(type == POSITION_TYPE_SELL)
      {
         sellCount++;
         sellLots += volume;
         sellPV += openPrice * volume;
      }
   }

   double buyAvg = (buyLots > 0) ? buyPV / buyLots : 0.0;
   double sellAvg = (sellLots > 0) ? sellPV / sellLots : 0.0;
   string rangeText = 只管理手动单 ? "当前品种手动单Magic=0" : "当前品种指定Magic=" + (string)指定管理Magic;
   string timeLimitText = (最大持仓分钟数 > 0) ? StringFormat("%s/%dm", FormatHeldMinutes(maxHeldMinutes), 最大持仓分钟数) : FormatHeldMinutes(maxHeldMinutes);
   color profitColor = floatingProfit > 0.005 ? LegacyProfitColor() : (floatingProfit < -0.005 ? LegacyLossColor() : LegacyFlatColor());
   if(slWarningText != "正常")
      slWarningColor = clrOrange;
   color tpAdviceColor = clrSilver;
   string tpAdviceText = 显示支撑压力TP建议 ? FormatTPAdviceText(midPrice, buyCount > 0, sellCount > 0, tpAdviceColor) : "TP参考: -";
   color shortTPAdviceColor = clrSilver;
   string shortTPAdviceText = FormatShortLineTPAdviceText(buyCount, buyAvg, sellCount, sellAvg, bid, ask, shortTPAdviceColor);
   double panelATR = 0.0;
   GetATRPrice(panelATR);
   double panelTrailTrigger = 移动止损启动价格;
   double panelTrailDistance = 移动止损距离价格;
   double panelTrailMinStep = 移动止损最小推进点数 * _Point;
   GetAdaptiveTrailConfig(panelATR, panelTrailTrigger, panelTrailDistance, panelTrailMinStep);
   string trailText = StringFormat("追踪[%s] 启%.2f/距%.2f | ATR %.2f", FormatTrailModeName(), panelTrailTrigger, panelTrailDistance, panelATR);
   string partialText = "分批: 关闭";
   if(启用分批止盈)
   {
      if(当前参数配置模板 == 配置_黄金超短快保 && 短线单启用多段分批止盈)
      {
         int maxStage = MathMin(MathMax(短线单最大分批段数, 1), 2);
         partialText = StringFormat("分批: 第%d/%d段 | %s",
                                    maxPartialStage,
                                    maxStage,
                                    partialTriggered ? "可落袋" : "动态等待");
      }
      else
      {
         partialText = StringFormat("分批: %s | 已%d/%d | 距触发 %s",
                                    partialTriggered ? "到位，可落袋" : "等点位",
                                    partialDoneCount,
                                    managed,
                                    FormatTriggerNeed(nearestPartial, partialTriggered || partialDoneCount > 0));
      }
   }

   string spaceText = "目标空间: -";
   color spaceColor = clrSilver;
   if(worstTargetSpace >= 0.0)
   {
      spaceText = StringFormat("目标空间: 近%.2f/好%.2f", worstTargetSpace, bestTargetSpace);
      if(hasSpaceRiskRatio)
      {
         spaceText += StringFormat(" | SL风险距%.2f | 比%.2f", worstSLRiskDistance, worstSpaceRiskRatio);
         if(worstSpaceRiskRatio < 持仓页低空间风险比)
            spaceColor = clrOrange;
         else if(worstSpaceRiskRatio >= 1.2)
            spaceColor = LegacySafeColor();
      }
   }

   if(当前模板使用黄金稳健止损())
   {
      int h4Dir = TrendLongH4Direction();
      int h1State = hasTrendPanelPosition ? TrendLongH1State(trendPanelType) : 0;
      double curR = (trendPanelRisk > 0.0) ? trendPanelProfit / trendPanelRisk : 0.0;
      double maxR = (trendPanelRisk > 0.0) ? trendPanelMaxProfit / trendPanelRisk : 0.0;
      string dirWarn = "";
      if(hasTrendPanelPosition && !trendPanelMixed)
      {
         bool h4WithPosition = (trendPanelType == POSITION_TYPE_BUY && h4Dir > 0) ||
                               (trendPanelType == POSITION_TYPE_SELL && h4Dir < 0);
         if(!h4WithPosition) dirWarn = " | 高周期不强";
      }

      trailText = trendPanelMixed ?
         "长线: 多空混合 | 长拿托管建议单方向管理" :
         StringFormat("长线: H4%s | H1%s%s | R %s/峰 %s",
                      TrendLongDirectionText(h4Dir),
                      TrendLongStateText(h1State),
                      dirWarn,
                      LifecycleStatsSignedR(curR),
                      LifecycleStatsSignedR(maxR));
      partialText = hasTrendPanelPosition ?
         ("保护: " + TrendLongProtectionText(trendPanelRisk, trendPanelProfit, trendPanelMaxProfit)) :
         "保护: 等待持仓";
      spaceText = (trendPanelRisk > 0.0) ?
         StringFormat("长线R: 初始R %.2f | 当前 %s | 最大 %s", trendPanelRisk, LifecycleStatsSignedR(curR), LifecycleStatsSignedR(maxR)) :
         "长线R: 等待结构SL建立";
      spaceColor = (curR >= 1.0 ? LegacySafeColor() : clrSilver);
      tpAdviceText = "TP: 无固定TP | 结构破坏/吊灯止损退出";
      tpAdviceColor = clrAqua;
   }

   TodayStats dayStats;
   GetTodayDisciplineStats(dayStats);
   string disciplineText = StringFormat("今日纪律: 平%d | 盈亏 %s | 连亏 %d", dayStats.closes, FormatMiniSignedProfit(dayStats.profit,2), dayStats.currentLossStreak);
   color disciplineColor = clrSilver;
   if(dayStats.profit < 0.0 && dayStats.currentLossStreak >= 2)
   {
      disciplineText += " | 收手冷静";
      disciplineColor = LegacyDangerColor();
   }
   else if(dayStats.currentLossStreak >= 2 || (今日纪律交易次数提醒 > 0 && dayStats.closes >= 今日纪律交易次数提醒))
   {
      disciplineText += " | 降频，别上头";
      disciplineColor = clrOrange;
   }
   else if(dayStats.profit > 0.0 && dayStats.profitFactor >= 1.2)
   {
      disciplineText += " | 节奏不错";
      disciplineColor = LegacySafeColor();
   }

   string riskState = "无持仓";
   color riskColor = clrSilver;
   if(managed > 0)
   {
      riskState = "正常，雷达安静";
      riskColor = clrWhite;
      if(noSLCount > 0)
      {
         riskState = "高风险: 无SL，没系安全带";
         riskColor = LegacyDangerColor();
      }
      else if(lossWarnCount > 0)
      {
         riskState = "高风险: 浮亏冒烟";
         riskColor = LegacyDangerColor();
      }
      else if(timeoutCount > 0)
      {
         riskState = "偏危险: 恋战太久";
         riskColor = clrOrange;
      }
      else if(hasSpaceRiskRatio && worstSpaceRiskRatio < 持仓页低空间风险比)
      {
         riskState = "偏危险: 前方有点窄";
         riskColor = clrOrange;
      }
      else if(maxProfitDrawdownRatio >= 0.0 && maxProfitDrawdownRatio >= 最大浮盈回撤比例 * 0.80)
      {
         riskState = "偏危险: 利润在缩水";
         riskColor = clrOrange;
      }
      else if(protectedCount == managed)
      {
         riskState = "安全，防守在线";
         riskColor = LegacySafeColor();
      }
   }

   string ddText = (maxProfitDrawdownRatio >= 0.0) ?
      StringFormat("%.0f%%/%.0f%%", maxProfitDrawdownRatio * 100.0, 最大浮盈回撤比例 * 100.0) :
      "-";
   color ddColor = clrSilver;
   if(maxProfitDrawdownRatio >= 最大浮盈回撤比例) ddColor = LegacyDangerColor();
   else if(maxProfitDrawdownRatio >= 最大浮盈回撤比例 * 0.80) ddColor = clrOrange;

   string markerLine = FormatMarkerSafetyText();
   color markerColor = !当前启用手机标记挂单() ? clrDimGray :
      ((StringFind(手机标记状态, "R") >= 0 || StringFind(手机标记状态, "同步") >= 0 || StringFind(手机标记状态, "GTC") >= 0) ? clrAqua : clrOrange);

   string riskBadge = "[空] 无持仓";
   if(managed > 0)
   {
      riskBadge = "[等] 待保护";
      if(noSLCount > 0) riskBadge = "[危] 无SL";
      else if(lossWarnCount > 0) riskBadge = "[危] 浮亏";
      else if(timeoutCount > 0) riskBadge = "[警] 超时";
      else if(hasSpaceRiskRatio && worstSpaceRiskRatio < 持仓页低空间风险比) riskBadge = "[警] 空间窄";
      else if(maxProfitDrawdownRatio >= 0.0 && maxProfitDrawdownRatio >= 最大浮盈回撤比例 * 0.80) riskBadge = "[警] 回撤预警";
      else if(protectedCount == managed) riskBadge = "[安] 已保护";
   }

   color topColor = riskColor;
   if(spreadColor == LegacyDangerColor()) topColor = LegacyDangerColor();
   string topManageText = managed > 0 ? "托管中" : "空仓";
   SetPanelLine("SMA_PANEL_1", 12, StringFormat("%s | %s | %s", _Symbol, topManageText, FormatSpreadText(spread)), topColor);

   int line = 2;
   SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), StringFormat("浮盈 %s | 最大浮盈距 %.2f | 回撤 %s", FormatMiniSignedProfit(floatingProfit,2), maxProfitPrice, ddText), profitColor); line++;
   SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), StringFormat("风险: %s | %s", riskBadge, riskState), riskColor); line++;
   SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), StringFormat("持仓: %d单 | 多%d %.2f手 | 空%d %.2f手", managed, buyCount, buyLots, sellCount, sellLots), clrWhite); line++;
   SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), StringFormat("均价: 多 %s | 空 %s",
                                                buyLots > 0 ? DoubleToString(buyAvg, _Digits) : "-",
                                                sellLots > 0 ? DoubleToString(sellAvg, _Digits) : "-"), clrSilver); line++;
   SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), StringFormat("保护: SL %d/%d | TP %d/%d | 保本 %d/%d", slCount, managed, tpCount, managed, protectedCount, managed), slCount == managed ? clrWhite : clrOrange); line++;
   SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), StringFormat("异常: 无SL %d | 无TP %d | 超时 %d | 浮亏 %d", noSLCount, noTPCount, timeoutCount, lossWarnCount), (noSLCount > 0 || lossWarnCount > 0) ? LegacyDangerColor() : (timeoutCount > 0 ? clrOrange : clrSilver)); line++;

   SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), StringFormat("距触发: 保本 %s | 追踪 %s | 回撤 %s", FormatTriggerNeed(nearestBE, beTriggered), FormatTriggerNeed(nearestTrail, trailTriggered), FormatTriggerNeed(nearestDD, ddTriggered)), clrSilver); line++;
    SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), spaceText, spaceColor); line++;
    if(当前是短线单模板())
    {
       int shortCount=0, shortReady=0, shortUnknown=0, shortPending=0, shortFast=0;
       int stageCounts[4]={0,0,0,0};
       int runnerCounts[4]={0,0,0,0};
       double shortInitialLots=0.0, shortCurrentLots=0.0;
       double totalInitialRiskMoney=0.0, totalCurrentSLRiskMoney=0.0;
       ulong singlePositionId=0;
       for(int i=0; i<ArraySize(states); i++)
       {
          if(!states[i].shortStateManaged || !PositionSelectByTicket(states[i].ticket)) continue;
          shortCount++;
          singlePositionId=states[i].positionIdentifier;
          double currentVolume=PositionGetDouble(POSITION_VOLUME);
          double openPrice=PositionGetDouble(POSITION_PRICE_OPEN);
          double serverSL=PositionGetDouble(POSITION_SL);
          ENUM_POSITION_TYPE shortType=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
          shortInitialLots += states[i].initialVolume;
          shortCurrentLots += currentVolume;
          if(states[i].shortRiskReady) shortReady++;
          if(states[i].shortRiskUnknown) shortUnknown++;
          if(states[i].pendingAction != 待确认动作_无 || states[i].partialRequestPending) shortPending++;
          if(states[i].fastProtectionActivated) shortFast++;
          int stage=MathMin(MathMax(states[i].partialTPStage,0),3);
          int runner=MathMin(MathMax(states[i].runnerMode,0),3);
          stageCounts[stage]++;
          runnerCounts[runner]++;

          ENUM_ORDER_TYPE orderType=shortType==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
          if(states[i].shortRiskReady && states[i].shortInitialRisk>0.0 && states[i].initialVolume>0.0)
          {
             double initialStop=shortType==POSITION_TYPE_BUY ? openPrice-states[i].shortInitialRisk : openPrice+states[i].shortInitialRisk;
             double initialRiskResult=0.0;
             if(OrderCalcProfit(orderType,_Symbol,states[i].initialVolume,openPrice,initialStop,initialRiskResult) && initialRiskResult<0.0)
                totalInitialRiskMoney += -initialRiskResult;
          }
          if(serverSL>0.0 && currentVolume>0.0)
          {
             double currentSLResult=0.0;
             if(OrderCalcProfit(orderType,_Symbol,currentVolume,openPrice,serverSL,currentSLResult) && currentSLResult<0.0)
                totalCurrentSLRiskMoney += -currentSLResult;
          }
       }
       if(shortCount>0)
       {
          SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                       StringFormat("短线组合: %d笔%s | 初始%.2f手/当前%.2f手", shortCount,
                                    shortCount==1 ? StringFormat(" ID%I64u",singlePositionId) : "", shortInitialLots, shortCurrentLots), clrWhite); line++;
          SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                       StringFormat("组合风险: 初始%.2f | 当前SL亏损风险%.2f | Ready %d/%d 未知%d",
                                    totalInitialRiskMoney,totalCurrentSLRiskMoney,shortReady,shortCount,shortUnknown),
                       (shortReady==shortCount && shortUnknown==0) ? clrAqua : clrOrange); line++;
          SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                       StringFormat("分批分布: 0段%d | 1段%d | 2段%d | 3段%d | 待确认%d",
                                    stageCounts[0],stageCounts[1],stageCounts[2],stageCounts[3],shortPending), shortPending>0 ? clrOrange : clrSilver); line++;
          SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                       StringFormat("尾仓: 固定%d | 结构%d | 箱体%d | 快退%d | 快保%d",
                                    runnerCounts[0],runnerCounts[1],runnerCounts[2],runnerCounts[3],shortFast), clrSilver); line++;
       }
    }
    if(当前是短线单模板() && managed > 0 && 短线单显示推荐止盈点位)
   {
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), shortTPAdviceText, shortTPAdviceColor); line++;
   }
   SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), partialText, 启用分批止盈 ? clrAqua : clrDimGray); line++;
   if(当前模板使用消息对冲())
   {
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), "消息: " + 消息对冲状态, clrAqua);
      line++;
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                   StringFormat("阶段: %s | 箱体: %s%s %.2f-%.2f | 宽%.2f", NewsStageName(),
                                newsState.boxFrozenByUser ? "冻结" : "候选", newsState.boxValid ? "有效" : "无效",
                                newsState.rangeLow, newsState.rangeHigh, newsState.boxWidth),
                   newsState.boxValid ? clrAqua : LegacyDangerColor()); line++;
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                   StringFormat("触碰: 高%d 低%d | 中轴%d | 开放%s", newsState.boxHighTouches,
                                newsState.boxLowTouches, newsState.boxMiddleCrosses, newsState.releaseEnabled ? "是" : "否"),
                   clrSilver); line++;
       SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                    StringFormat("缓冲: 突破%.2f / 灾难%.2f | 灾难SL B%.2f S%.2f", newsState.breakoutBuffer,
                                  newsState.disasterBuffer, newsState.buyDisasterSL, newsState.sellDisasterSL), clrSilver); line++;
       NewsStopPreview preview;
       NewsBuildFrozenStopPreview(preview);
       if(preview.visible)
       {
          if(preview.priceValid)
             SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                          StringFormat("最小手数预览 %.2f | Buy Stop %.2f / 灾难SL %.2f | Sell Stop %.2f / 灾难SL %.2f",
                                       preview.volume,preview.buyStop,preview.buyDisasterSL,preview.sellStop,preview.sellDisasterSL),clrAqua);
          else
             SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),preview.status,LegacyDangerColor());
          line++;
          SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                       StringFormat("双边最坏损失: B%s + S%s = %s",
                                    preview.buyLossAvailable ? DoubleToString(preview.buyLossMoney,2) : "不可用",
                                    preview.sellLossAvailable ? DoubleToString(preview.sellLossMoney,2) : "不可用",
                                    (preview.buyLossAvailable && preview.sellLossAvailable) ? DoubleToString(preview.buyLossMoney+preview.sellLossMoney,2) : "不可用"),
                       (preview.buyLossAvailable && preview.sellLossAvailable) ? clrAqua : clrOrange); line++;
          SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                       StringFormat("两单保证金: B%s + S%s = %s | %s",
                                    preview.buyMarginAvailable ? DoubleToString(preview.buyMargin,2) : "不可用",
                                    preview.sellMarginAvailable ? DoubleToString(preview.sellMargin,2) : "不可用",
                                    (preview.buyMarginAvailable && preview.sellMarginAvailable) ? DoubleToString(preview.buyMargin+preview.sellMargin,2) : "不可用",
                                    preview.status),
                       (preview.buyMarginAvailable && preview.sellMarginAvailable) ? clrSilver : clrOrange); line++;
       }
       double newsSpreadNow = CurrentSpreadPrice();
      double newsSpreadLimit = NewsDynamicSpreadLimit();
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                   StringFormat("点差: 当前%.2f | 动态限制%.2f | 冻结前正常%.2f", newsSpreadNow,
                                newsSpreadLimit, newsState.normalSpreadPrice),
                   (newsSpreadLimit > 0.0 && newsSpreadNow > newsSpreadLimit) ? LegacyDangerColor() : clrSilver); line++;

      int releaseElapsed = newsState.releaseTime > 0 ? (int)MathMax((long)(TimeCurrent()-newsState.releaseTime), 0) : 0;
      int releaseRemain = newsState.releaseExpireTime > 0 ? (int)MathMax((long)(newsState.releaseExpireTime-TimeCurrent()), 0) : 0;
      int unlockRemain = newsState.releaseTime > 0 ? MathMax(消息对冲最晚拆锁秒数-releaseElapsed, 0) : 0;
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                   StringFormat("释放: 已运行%ds | 窗口余%ds | 最晚拆锁余%ds", releaseElapsed, releaseRemain, unlockRemain),
                   newsState.releaseEnabled ? clrAqua : clrSilver); line++;

      int displayDir = newsState.breakoutDirection != 0 ? newsState.breakoutDirection : newsState.candidateDirection;
      double extension = 0.0;
      if(displayDir > 0) extension = MathMax(midPrice-newsState.rangeHigh, 0.0);
      else if(displayDir < 0) extension = MathMax(newsState.rangeLow-midPrice, 0.0);
      else extension = MathMax(MathMax(midPrice-newsState.rangeHigh, newsState.rangeLow-midPrice), 0.0);
      double maxExtension = NewsMaxUnlockExtension();
      bool unlockLate = newsState.releaseTime > 0 &&
                        (releaseElapsed > MathMax(消息对冲最晚拆锁秒数, 1) || extension > maxExtension);
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                   StringFormat("拆锁: 方向%d | 延伸%.2f/%.2f | %s", displayDir, extension, maxExtension,
                                 unlockLate ? "已过晚" : "可执行"), unlockLate ? LegacyDangerColor() : clrSilver); line++;
      string actualUnlockPriceText = newsState.loserDealReady && newsState.loserClosePrice > 0.0 ?
                                     DoubleToString(newsState.loserClosePrice, _Digits) : "等待";
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                   StringFormat("实际拆锁: 成交价%s | 延伸%.2f | 滑点%.2f", actualUnlockPriceText,
                                newsState.actualUnlockExtension, newsState.actualUnlockSlippage),
                   newsState.loserDealReady ? clrAqua : clrOrange); line++;

      double panelRunnerSL = 0.0;
      bool panelRunnerSLReal = false;
      if(newsState.runnerTicket > 0 && PositionSelectByTicket(newsState.runnerTicket))
      {
         ENUM_POSITION_TYPE panelRunnerType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         panelRunnerSL = PositionGetDouble(POSITION_SL);
         panelRunnerSLReal = newsState.runnerStructureSL > 0.0 &&
                             (panelRunnerType == POSITION_TYPE_BUY ?
                              (panelRunnerSL > 0.0 && panelRunnerSL >= newsState.runnerStructureSL-_Point) :
                              (panelRunnerSL > 0.0 && panelRunnerSL <= newsState.runnerStructureSL+_Point));
      }
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                   StringFormat("就绪: 亏损Deal %s | 结构SL %s %.2f | R %s", newsState.loserDealReady ? "是" : "否",
                                panelRunnerSLReal ? "已生效" : "未生效", panelRunnerSL,
                                newsState.runnerRiskReady ? "Ready" : "等待"),
                   newsState.runnerRiskReady ? clrAqua : clrOrange); line++;

      bool runnerStage = (newsState.stage == 消息阶段_冲击持仓 || newsState.stage == 消息阶段_延续持仓);
      double newsCombined = runnerStage ? NewsRunnerCombinedMoney() :
                            (NewsPositionMoney(newsState.buyTicket) + NewsPositionMoney(newsState.sellTicket) -
                             newsState.estimatedRemainingExitCostMoney);
      double newsR = newsState.runnerRiskReady && newsState.initialGroupRiskMoney > 0.0 ?
                     newsCombined/newsState.initialGroupRiskMoney : 0.0;
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                   StringFormat("组合: 当前%.2f / %s | 峰值%.2f | 亏损腿%.2f", newsCombined,
                                newsState.runnerRiskReady ? DoubleToString(newsR,2)+"R" : "R等待",
                                 newsState.maxCombinedMoney <= -DBL_MAX/2.0 ? 0.0 : newsState.maxCombinedMoney,
                                 newsState.realizedLoserLossMoney), clrAqua); line++;
      double panelLoserLoss = newsState.loserActualKnown ? newsState.realizedLoserLossMoney : newsState.pendingLoserLossMoney;
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                   StringFormat("亏损口径: %s %.2f | 待补录Deal %d/%d",
                                newsState.loserActualKnown ? "实际" : "估算", panelLoserLoss,
                                newsPendingDealCount, NEWS_PENDING_DEAL_CAPACITY),
                   newsState.loserActualKnown ? clrSilver : clrOrange); line++;
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                   StringFormat("成本: 实际%.2f | 预计剩余退出%.2f", newsState.actualCostMoney,
                                newsState.estimatedRemainingExitCostMoney), clrSilver); line++;

      int holdElapsed = NewsRunnerElapsedSeconds();
      int holdRemain = runnerStage ? MathMax(消息对冲组合最长持仓秒数-holdElapsed, 0) : 消息对冲组合最长持仓秒数;
      int extremeAge = runnerStage ? NewsExtremeAgeSeconds() : 0;
      double phaseDD = NewsPhaseDrawdownRatio(newsState.runnerPhase <= 0 ? 1 : newsState.runnerPhase);
      string microState = newsState.microPullbackConfirmed ? "已确认" :
                          (newsState.microPullbackInvalid ? "已失效" : (newsState.microPullbackActive ? "观察中" : "等待"));
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line),
                   StringFormat("短时: 阶段%d | 回撤限%.0f%% | 最长余%ds | 极值距今%ds | 回踩%s",
                                newsState.runnerPhase, phaseDD*100.0, holdRemain, extremeAge, microState), clrSilver); line++;
   }
   if(当前模板使用黄金稳健止损())
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), trailText, clrAqua);
   else
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), StringFormat("追踪: 候选%d | 回撤观察%d | 最长持仓 %s", trailingReadyCount, drawdownWatchCount, timeLimitText), ddColor);
   line++;

   if(面板显示支撑压力 && midPrice > 0.0)
   {
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), FormatSRCompactLineWithDistance(缓存压力位, true, midPrice), clrTomato); line++;
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), FormatSRCompactLineWithDistance(缓存支撑位, false, midPrice), clrLime); line++;
   }

   SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), tpAdviceText, tpAdviceColor); line++;
   if(启用SL过紧预警)
   {
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), "SL状态: " + slWarningText, slWarningColor); line++;
   }
   SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), markerLine, markerColor); line++;
   SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), 配置模板面板说明(), clrDimGray); line++;
   if(启用阶梯式保护)
   {
      SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), StringFormat("阶梯: %.1f→%.1f | %.1f→%.1f | %.1f→%.1f", 阶梯1触发价格, 阶梯1锁定价格, 阶梯2触发价格, 阶梯2锁定价格, 阶梯3触发价格, 阶梯3锁定价格), clrDimGray); line++;
   }
   SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), disciplineText, disciplineColor); line++;
   SetPanelLine("SMA_PANEL_" + IntegerToString(line), HoldingPanelY(line), "状态: " + lastStatus, clrYellow); line++;

   int finalPanelHeight = HoldingPanelY(line)+10;
    if(当前模板使用消息对冲())
    {
       int newsButtonY = 98;
      bool preEntryFreeze = (启用消息双Stop真实挂单 && newsState.stage == 消息阶段_待命 && !NewsHasAnyStrategyStopObject());
      bool freezeEnabled = (newsState.stage == 消息阶段_配对安全 || preEntryFreeze);
      bool stopDeploy = (启用消息双Stop真实挂单 && newsState.stage == 消息阶段_箱体冻结 &&
                         newsState.boxFrozenByUser && newsState.boxValid && newsState.buyTicket==0 && newsState.sellTicket==0 &&
                         newsState.stopStage==消息双Stop_空闲);
      bool manualRelease = (newsState.stage == 消息阶段_箱体冻结 && newsState.boxFrozenByUser && newsState.boxValid &&
                            newsState.buyTicket>0 && newsState.sellTicket>0);
      bool releaseEnabled = (stopDeploy || manualRelease);
      bool cancelEnabled = (newsState.stage != 消息阶段_待命 || newsState.waitTicket > 0 || newsState.stopToken>0);
      bool flatEnabled = (managed > 0 || newsState.runnerTicket>0 || newsState.buyTicket>0 || newsState.sellTicket>0);
      CreatePanelButton("SMA_BTN_NEWS_FREEZE", freezeEnabled ? "冻结箱体" : "冻结不可用", 12, newsButtonY, 112, 24, freezeEnabled);
      CreatePanelButton("SMA_BTN_NEWS_RELEASE", stopDeploy ? "部署双Stop" : (releaseEnabled ? "开放拆锁" : "开放不可用"), 130, newsButtonY, 112, 24, releaseEnabled);
      CreatePanelButton("SMA_BTN_NEWS_CANCEL", "取消本次", 248, newsButtonY, 106, 24, cancelEnabled);
      CreatePanelButton("SMA_BTN_NEWS_FLAT", "消息紧急全平", 360, newsButtonY, 128, 24, flatEnabled);
      finalPanelHeight = MathMax(finalPanelHeight, newsButtonY+34);
    }
    else
    {
       ObjectDelete(0, "SMA_BTN_NEWS_FREEZE");
      ObjectDelete(0, "SMA_BTN_NEWS_RELEASE");
      ObjectDelete(0, "SMA_BTN_NEWS_CANCEL");
      ObjectDelete(0, "SMA_BTN_NEWS_FLAT");
   }

   for(int k=line; k<=48; k++)
      ObjectDelete(0, "SMA_PANEL_" + IntegerToString(k));

   ResizePanelBackgroundHeight(finalPanelHeight);
   DrawPanelHeaderButtons(); // 固定宽度模式下刷新顶部按钮位置
}

void DeletePanel()
{
   CanvasPanelRenderer.Destroy();
   ObjectDelete(0, "SMA_PANEL_BG");
   ObjectDelete(0, "SMA_UI_HEADER");
   ObjectDelete(0, "SMA_UI_ACCENT");
   ObjectDelete(0, "SMA_UI_DIVIDER");
   DeletePanelNavigationSurfaces();
   ObjectDelete(0, "SMA_BTN_POS");
   ObjectDelete(0, "SMA_BTN_DAY");
   ObjectDelete(0, "SMA_BTN_STAT_DAY");
   ObjectDelete(0, "SMA_BTN_STAT_WEEK");
   ObjectDelete(0, "SMA_BTN_STAT_MONTH");
   ObjectDelete(0, "SMA_BTN_PREV_DAY");
   ObjectDelete(0, "SMA_BTN_TODAY");
   ObjectDelete(0, "SMA_BTN_NEXT_DAY");
   ObjectDelete(0, "SMA_BTN_PREV_WEEK");
   ObjectDelete(0, "SMA_BTN_THIS_WEEK");
   ObjectDelete(0, "SMA_BTN_NEXT_WEEK");
   ObjectDelete(0, "SMA_BTN_PREV_MONTH");
   ObjectDelete(0, "SMA_BTN_THIS_MONTH");
   ObjectDelete(0, "SMA_BTN_NEXT_MONTH");
   ObjectDelete(0, "SMA_BTN_PANEL_MINI");
   ObjectDelete(0, "SMA_BTN_PANEL_FULL");
   ObjectDelete(0, "SMA_BTN_PANEL_HIDE");
   ObjectDelete(0, "SMA_BTN_VIEW_TOGGLE");
   ObjectDelete(0, "SMA_BTN_CFG_CUSTOM");
   ObjectDelete(0, "SMA_BTN_CFG_FAST");
   ObjectDelete(0, "SMA_BTN_CFG_TREND");
   ObjectDelete(0, "SMA_BTN_CFG_SRTP");
   ObjectDelete(0, "SMA_BTN_CFG_NEWS");
   ObjectDelete(0, "SMA_BTN_MARKER_VIS");
   ObjectDelete(0, "SMA_BTN_NEWS_FREEZE");
   ObjectDelete(0, "SMA_BTN_NEWS_RELEASE");
   ObjectDelete(0, "SMA_BTN_NEWS_CANCEL");
   ObjectDelete(0, "SMA_BTN_NEWS_FLAT");
   DeleteLifecycleStatsButtons();
   ClearPanelLines();
   DeleteSRObjects();
   DeleteLegacyShortLineBoxChartObjects();
   CanvasLegacyObjectsCleared=false;
   CanvasNewsButtonsVisible=false;
   CanvasNewsButtonsSignature="";
   CanvasPanelLayoutValid=false;
   CanvasMiniModelValid=false;
   CanvasHoldingModelValid=false;
   CanvasStatsModelValid=false;
   InvalidateCanvasReviewCache();
   ArrayResize(CanvasPanelHitRegions,0);
}

bool PanelCoreObjectsAlive()
{
   if(使用新版Canvas面板)
   {
      if(!CanvasPanelRenderer.Alive(CanvasPanelMetrics.width,CanvasPanelMetrics.height)) return false;
      if(当前面板显示模式==面板完整 && 当前面板页面==页面持仓 && 当前模板使用消息对冲() &&
         (ObjectFind(0,"SMA_BTN_NEWS_FREEZE")<0 || ObjectFind(0,"SMA_BTN_NEWS_RELEASE")<0 ||
          ObjectFind(0,"SMA_BTN_NEWS_CANCEL")<0 || ObjectFind(0,"SMA_BTN_NEWS_FLAT")<0))
         return false;
      return true;
   }

   if(ObjectFind(0, "SMA_PANEL_BG") < 0)
      return false;
   if(ObjectFind(0, "SMA_UI_HEADER") < 0 ||
      ObjectFind(0, "SMA_UI_ACCENT") < 0 ||
      ObjectFind(0, "SMA_UI_DIVIDER") < 0)
      return false;

   if(当前面板显示模式 == 面板隐藏)
      return (ObjectFind(0, "SMA_BTN_PANEL_FULL") >= 0);

   if(当前面板显示模式 == 面板迷你)
   {
      return (ObjectFind(0, "SMA_BTN_POS") >= 0 &&
              ObjectFind(0, "SMA_BTN_DAY") >= 0 &&
              ObjectFind(0, "SMA_BTN_PANEL_FULL") >= 0 &&
              ObjectFind(0, "SMA_BTN_PANEL_HIDE") >= 0);
   }

   if(ObjectFind(0, "SMA_BTN_POS") < 0 ||
      ObjectFind(0, "SMA_BTN_DAY") < 0 ||
      ObjectFind(0, "SMA_BTN_VIEW_TOGGLE") < 0 ||
      ObjectFind(0, "SMA_BTN_PANEL_MINI") < 0 ||
      ObjectFind(0, "SMA_BTN_PANEL_HIDE") < 0)
      return false;

   if(当前面板页面 == 页面持仓 &&
       (ObjectFind(0, "SMA_BTN_CFG_CUSTOM") < 0 ||
        ObjectFind(0, "SMA_BTN_CFG_FAST") < 0 ||
        ObjectFind(0, "SMA_BTN_CFG_TREND") < 0 ||
        ObjectFind(0, "SMA_BTN_CFG_SRTP") < 0 ||
        ObjectFind(0, "SMA_BTN_CFG_NEWS") < 0 ||
        ObjectFind(0, "SMA_BTN_MARKER_VIS") < 0))
      return false;

   if(当前面板页面 == 页面持仓 && 当前模板使用消息对冲() &&
      (ObjectFind(0, "SMA_BTN_NEWS_FREEZE") < 0 ||
       ObjectFind(0, "SMA_BTN_NEWS_RELEASE") < 0 ||
       ObjectFind(0, "SMA_BTN_NEWS_CANCEL") < 0 ||
       ObjectFind(0, "SMA_BTN_NEWS_FLAT") < 0))
      return false;

   if(当前面板页面 == 页面今日)
   {
      if(ObjectFind(0, "SMA_BTN_STAT_DAY") < 0 ||
         ObjectFind(0, "SMA_BTN_STAT_WEEK") < 0 ||
         ObjectFind(0, "SMA_BTN_STAT_MONTH") < 0 ||
         ObjectFind(0, "SMA_BTN_FILTER_SHORT") < 0 ||
         ObjectFind(0, "SMA_BTN_FILTER_ALL") < 0 ||
         ObjectFind(0, "SMA_BTN_FILTER_TREND") < 0 ||
         ObjectFind(0, "SMA_BTN_FILTER_NORMAL") < 0 ||
         ObjectFind(0, "SMA_BTN_FILTER_NEWS") < 0 ||
         ObjectFind(0, "SMA_BTN_DETAIL_OVERVIEW") < 0 ||
         ObjectFind(0, "SMA_BTN_DETAIL_STRATEGY") < 0 ||
         ObjectFind(0, "SMA_BTN_DETAIL_MANAGE") < 0 ||
         ObjectFind(0, "SMA_BTN_DETAIL_EXEC") < 0 ||
         ObjectFind(0, "SMA_BTN_DETAIL_REVIEW") < 0)
         return false;

      if(当前统计周期 == 统计_日)
         return (ObjectFind(0, "SMA_BTN_PREV_DAY") >= 0 &&
                 ObjectFind(0, "SMA_BTN_TODAY") >= 0 &&
                 ObjectFind(0, "SMA_BTN_NEXT_DAY") >= 0);
      if(当前统计周期 == 统计_周)
         return (ObjectFind(0, "SMA_BTN_PREV_WEEK") >= 0 &&
                 ObjectFind(0, "SMA_BTN_THIS_WEEK") >= 0 &&
                 ObjectFind(0, "SMA_BTN_NEXT_WEEK") >= 0);
      return (ObjectFind(0, "SMA_BTN_PREV_MONTH") >= 0 &&
              ObjectFind(0, "SMA_BTN_THIS_MONTH") >= 0 &&
              ObjectFind(0, "SMA_BTN_NEXT_MONTH") >= 0);
   }

   return true;
}

void RefreshPanel(bool force=false)
{
   PerformanceScope perfScope(PERF_PANEL_REFRESH);
   if(使用新版Canvas面板) UpdateCanvasHeaderClockCache(显示简洁面板);
   if(!显示简洁面板) return;

   ulong nowMs=GetTickCount64();
   ulong intervalMs=(ulong)MathMax(面板刷新秒数,1)*1000;
   bool fullRefreshDue=(上次完整面板刷新毫秒==0 || nowMs-上次完整面板刷新毫秒>=intervalMs);
   string key = IntegerToString((int)当前面板页面) + "|" + IntegerToString((int)当前面板显示模式) + "|" + IntegerToString((int)当前统计周期) + "|" + IntegerToString((int)当前参数配置模板) + "|" + IntegerToString((int)当前统计筛选) + "|" + IntegerToString((int)当前统计详情) + "|" + IntegerToString(统计日期偏移天数) + "|" + IntegerToString(统计周偏移周数) + "|" + IntegerToString(统计月偏移月数);

   if(使用新版Canvas面板)
   {
      bool scheduledFullRefresh=false;
      if(!PanelCoreObjectsAlive())
      {
         MarkCanvasPanelDirty(PANEL_DIRTY_LAYOUT|PANEL_DIRTY_RENDER);
         if(!CanvasCurrentViewModelValid()) MarkCanvasPanelDirty(PANEL_DIRTY_DATA);
      }
      if(!force)
      {
         if(fullRefreshDue)
         {
            MarkCanvasPanelDirty(PANEL_DIRTY_DATA);
            scheduledFullRefresh=true;
         }
      }
      else if(CanvasPanelDirty==PANEL_DIRTY_NONE)
      {
         MarkCanvasPanelDirty(PANEL_DIRTY_RENDER);
         if(!CanvasCurrentViewModelValid()) MarkCanvasPanelDirty(PANEL_DIRTY_DATA);
      }
      if(CanvasPanelDirty==PANEL_DIRTY_NONE) return;
      if(RefreshCanvasPanelByDirtyFlags(force))
      {
         // 使用本次节流判断时的单调时间作锚点，避免把绘制耗时累积到下一周期。
         if(scheduledFullRefresh) 上次完整面板刷新毫秒=nowMs;
         上次面板状态文本=key;
      }
      return;
   }

   if(!PanelCoreObjectsAlive()) force=true;

   // 状态文字、手机标记结果和价格会高频变化，但面板只按刷新秒数更新。
   // 否则每次 lastStatus 变化都会绕过节流，顶部按钮和文字容易肉眼闪烁。
   if(!force && !fullRefreshDue)
      return;

   ShowPanel();
   上次完整面板刷新毫秒=nowMs;
   上次面板状态文本 = key;
   ChartRedraw(0);
}

int OnInit()
{
   if(启用老师点位自动反转短线 && 老师自动使用积极策略 &&
      (老师点位自动短线固定手数<=0 ||
       老师自动接近M5ATR<=0 || 老师自动追价上限M5ATR<老师自动接近M5ATR ||
       老师自动突破缓冲M5ATR<=0 || 老师自动止损缓冲M5ATR<=0 ||
       老师自动最低净盈亏比<1 || 老师自动每手往返费用<0 ||
       老师自动日内亏损上限百分比<=0 || 老师自动日内亏损上限百分比>10 ||
       老师自动连续止损上限<1 || 老师自动止损冷却秒<0 ||
       老师自动同时最大持仓<1 || 老师自动同时最大持仓>5 || 老师自动贪婪首段R<1.5 || 老师自动贪婪保护R<1 ||
       (老师自动点位失效时间>0 && 老师自动点位生效时间>0 && 老师自动点位失效时间<=老师自动点位生效时间)))
   { Print("[老师积极] 参数不合法，初始化终止"); return INIT_PARAMETERS_INCORRECT; }
   // 独占文件句柄防止同终端同品种多个实例竞相占用第5个名额；不带SHARE标志。
   teacherAutoInstanceFile=FileOpen(StringFormat("TeacherAuto_%I64d_%s.lock",AccountInfoInteger(ACCOUNT_LOGIN),_Symbol),FILE_BIN|FILE_READ|FILE_WRITE);
   if(teacherAutoInstanceFile==INVALID_HANDLE)
   { Print("[老师自动] 同账户同品种已有实例或无法取得实例锁；本实例不启动"); return INIT_FAILED; }
   if(启用老师点位自动反转短线 && 老师自动使用积极策略 &&
      AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("[老师积极] 非Hedging账户：禁止新开多仓/双向单，保留已有仓位管理");
   CanvasPanelRenderer.Destroy();
   当前参数配置模板 = 读取持久化配置模板(参数配置模板);
   保存配置模板输入值(参数配置模板);
   当前面板信息模式 = 读取持久化面板信息模式();
   手机标记挂单面板开关 = 读取持久化手机标记挂单面板开关();
   保存当前配置模板();
   DeleteLegacyShortLineBoxChartObjects();
   // 进行中的消息组合独立于面板“下一单”模板；必须始终恢复，避免重启后停止风控。
   NewsHedgeLoadState();
   atrHandle = iATR(_Symbol, PERIOD_M1, ATR周期);
   if(atrHandle == INVALID_HANDLE)
   {
      Print("ATR句柄创建失败");
      return INIT_FAILED;
   }

   manageTrade.SetDeviationInPoints(30);
   markerTrade.SetDeviationInPoints(30);
   newsStopTrade.SetExpertMagicNumber(消息双Stop挂单Magic);
   newsStopTrade.SetDeviationInPoints(MathMax(消息对冲允许滑点点数,0));
   teacherAutoTrade.SetExpertMagicNumber(TEACHER_AUTO_SHORT_MAGIC);
   teacherAutoTrade.SetDeviationInPoints(30);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   当前面板左边距 = 面板左边距;
   当前面板上边距 = 面板上边距;
   上次图表宽度像素 = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   上次图表高度像素 = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   lastM1BarTime = iTime(_Symbol, PERIOD_M1, 0);
   lastM5BarTime = iTime(_Symbol, PERIOD_M5, 0);
   currentTickHasNewM1Bar = false;
   currentTickHasNewM5Bar = false;
   ClampPanelPosition();
   当前面板显示模式 = 面板默认显示模式;
   InitializeCanvasPanelArchitecture();
   lastStatus = "初始化完成: " + 配置模板名称();
   RefreshTeacherMarkerCache();
   TeacherAutoStateLoad();
   teacherAutoStateLoaded=true;
   TeacherAutoReconcilePending();
   if(启用老师点位自动反转短线 && 老师自动使用积极策略) TeacherActivePlanValid();
   TeacherActiveRefreshRisk();
   ShortStateRestoreAll();
   for(int i=0; i<ArraySize(states); i++) ReconcilePendingTradeAction(i);
   TradeJournalImportAvailableHistory();
   EventSetTimer(1);
   NewsReconcileStopDeployment();
   RefreshMarketStructureCaches(true);
   ManageMobileMarkerOrders(true);
   RefreshPanel(true);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   PerformanceScope perfScope(PERF_ON_TICK);
   // 6A只建立统一频率标志；交易与结构调用仍保留原入口，6B验证后再消除重复入口。
   currentTickHasNewM1Bar = IsNewBar(PERIOD_M1, lastM1BarTime);
   currentTickHasNewM5Bar = IsNewBar(PERIOD_M5, lastM5BarTime);
   // 价格序列只读；即使面板当前切到趋势配置，也要让已冻结的短线仓持续拥有快保所需的近期报价。
   ShortPushFastPriceTick();
   CleanupStates();

   if(!启用辅助管理)
   {
      lastStatus = "辅助管理关闭";
      return;
   }

   // 消息对冲必须在极端点差下仍执行灾难止损与组合最大亏损保护，
   // 因此不走通用SpreadOK拦截；方向拆锁由它自己的点差阈值控制。
   if(当前模板使用消息对冲() || NewsHedgeGroupActive())
   {
      NewsHedgeTemplateScope templateScope;
      RefreshMarketStructureCaches(false, false);
      NewsPushMicroTick();
      double newsAtr = 0.0;
      GetATRPrice(newsAtr);
      ManageNewsHedge(newsAtr);
      ManageMobileMarkerOrders(false);
      return;
   }

   if(!ShortSpreadAllowsNormalManagement())
   {
      // 高点差只暂停普通分批/TP/细微追踪；短线单的灾难SL和绝对风险保护仍必须执行。
      double emergencyATR = 0.0;
      GetATRPrice(emergencyATR);
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket > 0) ShortEmergencyRiskManagement(ticket, emergencyATR);
      }
      lastStatus = "点差过大：普通操作暂停，紧急风险保护仍执行";
      RefreshMarketStructureCaches(false, false);
      ManageMobileMarkerOrders(false);
      return;
   }

   // Tick只准备交易数据；周期绘图交给Timer，按钮仍由ChartEvent即时刷新。
   RefreshMarketStructureCaches(false, false);

   double atr = 0.0;
   GetATRPrice(atr);

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      ManagePosition(ticket, atr);
   }

   // 持仓循环可能载入过其他冻结模板；收尾恢复当前面板模板的结构显示和手机标记参考。
   RefreshMarketStructureCaches(false, false);

   ManageTeacherAutoReversal();
   ManageMobileMarkerOrders(false);
}



bool ShortProcessedDealContains(ulong deal)
{
   for(int i=0; i<processedShortDealCount; i++) if(processedShortDealTickets[i] == deal) return true;
   return false;
}

void ShortMarkDealProcessed(ulong deal)
{
   if(deal == 0 || ShortProcessedDealContains(deal)) return;
   if(processedShortDealCount >= ArraySize(processedShortDealTickets))
   {
      for(int i=1; i<processedShortDealCount; i++) processedShortDealTickets[i-1] = processedShortDealTickets[i];
      processedShortDealCount--;
   }
   processedShortDealTickets[processedShortDealCount++] = deal;
}

bool ShortEnqueuePendingDeal(ulong deal)
{
   if(deal == 0) return false;
   for(int i=0; i<pendingShortDealCount; i++) if(pendingShortDealTickets[i] == deal) return true;
   if(pendingShortDealCount >= SHORT_PENDING_DEAL_CAPACITY)
   {
      PrintRateLimited("short_pending_queue_full", 10,
                       StringFormat("[短线成交] 待补录队列已满，拒绝覆盖 deal=%I64u", deal));
      return false;
   }
   pendingShortDealTickets[pendingShortDealCount++] = deal;
   PrintFormat("[短线成交] deal=%I64u 加入待补录队列 count=%d", deal, pendingShortDealCount);
   return true;
}

void ShortRemovePendingDeal(int index)
{
   if(index < 0 || index >= pendingShortDealCount) return;
   for(int i=index; i<pendingShortDealCount-1; i++) pendingShortDealTickets[i] = pendingShortDealTickets[i+1];
   pendingShortDealTickets[--pendingShortDealCount] = 0;
}

int FindShortStateByPositionIdentifier(ulong positionIdentifier)
{
   for(int i=0; i<ArraySize(states); i++)
      if(states[i].shortStateManaged && states[i].positionIdentifier == positionIdentifier) return i;
   return -1;
}

bool SelectPositionForShortState(int stateIdx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return false;
   if(states[stateIdx].ticket > 0 && PositionSelectByTicket(states[stateIdx].ticket)) return true;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) != states[stateIdx].positionIdentifier) continue;
      states[stateIdx].ticket = ticket;
      return true;
   }
   return false;
}

double ShortStageFilledVolume(int stateIdx, int stage)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return 0.0;
   if(stage == 1) return states[stateIdx].partialFilledVolumeStage1;
   if(stage == 2) return states[stateIdx].partialFilledVolumeStage2;
   if(stage == 3) return states[stateIdx].partialFilledVolumeStage3;
   return 0.0;
}

void ShortSetStageFilledVolume(int stateIdx, int stage, double value)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return;
   if(stage == 1) states[stateIdx].partialFilledVolumeStage1 = value;
   else if(stage == 2) states[stateIdx].partialFilledVolumeStage2 = value;
   else if(stage == 3) states[stateIdx].partialFilledVolumeStage3 = value;
}

bool ShortRecordDeal(ulong dealTicket, string source)
{
   if(dealTicket == 0 || !HistoryDealSelect(dealTicket)) return false;
   TradeJournalWriteDeal(dealTicket, source);
   if(ShortProcessedDealContains(dealTicket)) return true;
   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_OUT &&
      entry != DEAL_ENTRY_OUT_BY && entry != DEAL_ENTRY_INOUT) return false;
   ulong positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   int stateIdx = FindShortStateByPositionIdentifier(positionId);
   if(stateIdx < 0) return false;
   if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol) return false;
   datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
   if(states[stateIdx].lifecycleSegmentStartTime > 0 &&
      dealTime < states[stateIdx].lifecycleSegmentStartTime) return false;

   bool reversalEntry = (states[stateIdx].nettingReversalDetected && entry == DEAL_ENTRY_INOUT &&
                         states[stateIdx].lifecycleSegmentStartTime > 0 &&
                         MathAbs((long)(dealTime-states[stateIdx].lifecycleSegmentStartTime)) <= 2);
   if(entry == DEAL_ENTRY_IN || reversalEntry)
   {
      // 净持仓反转的INOUT成交沿用既有分段口径，不把旧方向退出结果计入新生命周期。
      if(!reversalEntry)
      {
         states[stateIdx].lifecycleRealizedNetMoney +=
            HistoryDealGetDouble(dealTicket, DEAL_PROFIT)+
            HistoryDealGetDouble(dealTicket, DEAL_COMMISSION)+
            HistoryDealGetDouble(dealTicket, DEAL_SWAP)+
            HistoryDealGetDouble(dealTicket, DEAL_FEE);
         MarkShortStateDirty(stateIdx);
      }
      ShortMarkDealProcessed(dealTicket);
      ShortStateSave(stateIdx);
      return true;
   }

   double filled = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
   if(filled <= 0.0) return false;
   ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
   bool directionMatches = (states[stateIdx].positionDirection == POSITION_TYPE_BUY && dealType == DEAL_TYPE_SELL) ||
                           (states[stateIdx].positionDirection == POSITION_TYPE_SELL && dealType == DEAL_TYPE_BUY);
   if(!directionMatches) return false;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   int stage = states[stateIdx].pendingPartialStage;
   states[stateIdx].lastShortDeal = dealTicket;
   states[stateIdx].lastLifecycleExitDeal = dealTicket;
   states[stateIdx].lifecycleRealizedNetMoney +=
      HistoryDealGetDouble(dealTicket, DEAL_PROFIT)+
      HistoryDealGetDouble(dealTicket, DEAL_COMMISSION)+
      HistoryDealGetDouble(dealTicket, DEAL_SWAP)+
      HistoryDealGetDouble(dealTicket, DEAL_FEE);
   MarkShortStateDirty(stateIdx);
   ShortMarkDealProcessed(dealTicket);

   if(states[stateIdx].pendingAction == 待确认动作_全部平仓)
   {
      states[stateIdx].pendingExitFilledVolume += filled;
      bool stillOpen = SelectPositionForShortState(stateIdx);
      double remaining = stillOpen ? PositionGetDouble(POSITION_VOLUME) : 0.0;
      if(stillOpen && remaining > step*0.5)
      {
         states[stateIdx].lastKnownVolume = remaining;
         TradeJournalWriteLifecycle(stateIdx, "FULL_CLOSE_PARTIAL_FILL",
                                    StringFormat("deal=%I64u;filled=%.2f;total_filled=%.2f;remaining=%.2f;source=%s",
                                                 dealTicket, filled, states[stateIdx].pendingExitFilledVolume, remaining, source));
      }
      else
      {
         FinalizeFloatingPnlTiming(stateIdx);
         states[stateIdx].lifecyclePhase = 生命周期_等待最终结算;
         TradeJournalWriteLifecycle(stateIdx, "FULL_CLOSE_FILL",
                                    StringFormat("deal=%I64u;filled=%.2f;total_filled=%.2f;source=%s",
                                                 dealTicket, filled, states[stateIdx].pendingExitFilledVolume, source));
         ClearPendingTradeAction(stateIdx);
      }
      ShortStateSave(stateIdx);
      return true;
   }

   if(!states[stateIdx].partialRequestPending || stage <= 0 || stage > 3)
   {
      long reason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
      if(reason == DEAL_REASON_TP) states[stateIdx].exitIntent = 退出意图_固定TP;
      else if(reason == DEAL_REASON_SL) states[stateIdx].exitIntent = 退出意图_SL;
      else if(states[stateIdx].exitIntent == 退出意图_无) states[stateIdx].exitIntent = 退出意图_手动关闭;
      states[stateIdx].externalVolumeChangeDetected = true;
      states[stateIdx].externalVolumeChangeTime = TimeCurrent();
      if(SelectPositionForShortState(stateIdx))
         states[stateIdx].lastKnownVolume = PositionGetDouble(POSITION_VOLUME);
      else
         FinalizeFloatingPnlTiming(stateIdx);
      TradeJournalWriteLifecycle(stateIdx, "EXTERNAL_POSITION_REDUCTION_DEAL",
                                 StringFormat("deal=%I64u;filled=%.2f;reason=%d;source=%s", dealTicket, filled, reason, source));
      ShortStateSave(stateIdx);
      return true;
   }

   states[stateIdx].pendingPartialFilledVolume += filled;
   states[stateIdx].partialFillCount++;
   ShortSetStageFilledVolume(stateIdx, stage, ShortStageFilledVolume(stateIdx, stage) + filled);
   PrintFormat("[短线成交] %s deal=%I64u id=%I64u stage=%d filled=%.2f total=%.2f target=%.2f", source,
               dealTicket, positionId, stage, filled, states[stateIdx].pendingPartialFilledVolume,
               states[stateIdx].pendingPartialVolume);
   if(states[stateIdx].pendingPartialFilledVolume + step*0.5 >= states[stateIdx].pendingPartialVolume)
   {
      states[stateIdx].partialTPStage = MathMax(states[stateIdx].partialTPStage, stage);
      states[stateIdx].partialTPDone = true;
      states[stateIdx].lastPartialTPTime = TimeCurrent();
      states[stateIdx].partialRequestPending = false;
      states[stateIdx].pendingPartialStage = 0;
      states[stateIdx].pendingPartialVolume = 0.0;
      states[stateIdx].pendingPartialFilledVolume = 0.0;
      states[stateIdx].pendingPartialStartVolume = 0.0;
      states[stateIdx].pendingPartialRequestTime = 0;
      ClearPendingTradeAction(stateIdx);
      PrintFormat("[短线成交] 第%d段真实成交确认完成 id=%I64u", stage, positionId);
   }
   if(SelectPositionForShortState(stateIdx))
      states[stateIdx].lastKnownVolume = PositionGetDouble(POSITION_VOLUME);
   else
      FinalizeFloatingPnlTiming(stateIdx);
   ShortStateSave(stateIdx);
   TradeJournalWriteLifecycle(stateIdx, "PARTIAL_CLOSE_FILL", StringFormat("stage=%d;deal=%I64u;filled_volume=%.2f;source=%s", stage, dealTicket, filled, source));
   if(!states[stateIdx].partialRequestPending)
      TradeJournalWriteLifecycle(stateIdx, "PARTIAL_STAGE_CONFIRMED", StringFormat("stage=%d;deal=%I64u", stage, dealTicket));
   return true;
}

void ShortProcessPendingDeals()
{
   for(int i=0; i<pendingShortDealCount; i++)
   {
      ulong deal = pendingShortDealTickets[i];
      if(!HistoryDealSelect(deal)) continue;
      ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      int stateIdx = FindShortStateByPositionIdentifier(positionId);
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(stateIdx >= 0 && (entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT))
         InvalidateEntryCostCache(stateIdx);
      ShortRecordDeal(deal, "延迟补录");
      ShortRemovePendingDeal(i);
      i--;
   }
}

void ShortCheckPartialRequestTimeouts()
{
   for(int i=0; i<ArraySize(states); i++)
   {
      if(!states[i].shortStateManaged || !states[i].partialRequestPending || states[i].pendingPartialRequestTime <= 0) continue;
      if(TimeCurrent()-states[i].pendingPartialRequestTime < MathMax(短线单分批最小间隔秒, 20)) continue;
      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0.0) step = 0.01;
      // 交易事件可能延迟或丢失；超时后按positionIdentifier补录未处理的真实退出Deal。
      if(states[i].positionIdentifier == 0 || !HistorySelectByPosition(states[i].positionIdentifier)) continue;
      ulong deals[];
      if(!SnapshotSelectedDealTickets(deals) || ArraySize(deals)==0) continue;
      bool historyReady=true;
      {
         for(int d=0; d<ArraySize(deals); d++)
         {
            ulong deal = deals[d];
            if(deal == 0 || ShortProcessedDealContains(deal)) continue;
            if(!HistoryDealSelect(deal)) { historyReady=false; continue; }
            if((datetime)HistoryDealGetInteger(deal, DEAL_TIME) < states[i].pendingPartialRequestTime) continue;
            ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
               if(!ShortRecordDeal(deal, "timeout_reconcile")) historyReady=false;
         }
      }
      if(!historyReady) continue; // 未读全真实成交时不能解除请求锁并补发。
      if(!states[i].partialRequestPending) continue;
      if(!PositionSelectByTicket(states[i].ticket))
      {
         states[i].lifecyclePhase = 生命周期_等待最终结算;
         MarkShortStateDirty(i);
         TradeJournalWriteLifecycle(i, "PARTIAL_POSITION_CLOSED", "position_closed_while_partial_pending");
         continue;
      }
      double currentVolume = PositionGetDouble(POSITION_VOLUME);
      double reduced = MathMax(states[i].pendingPartialStartVolume-currentVolume, 0.0);
      if(reduced <= step*0.5 && states[i].pendingPartialFilledVolume <= step*0.5)
      {
         PrintFormat("[短线成交] 分批请求超时未成交 ticket=%I64u stage=%d，允许重试", states[i].ticket, states[i].pendingPartialStage);
         states[i].partialRequestPending = false;
         states[i].pendingPartialStage = 0;
         states[i].pendingPartialVolume = 0.0;
         states[i].pendingPartialFilledVolume = 0.0;
         states[i].pendingPartialStartVolume = 0.0;
         states[i].pendingPartialRequestTime = 0;
         ClearPendingTradeAction(i);
         TradeJournalWriteLifecycle(i, "PARTIAL_TIMEOUT_NO_FILL", "no_volume_change_and_no_exit_deal");
         ShortStateSave(i);
      }
      else
      {
         TradeJournalWriteLifecycle(i, "PARTIAL_TIMEOUT_PARTIAL_FILL",
                                    StringFormat("stage=%d;requested=%.2f;filled=%.2f;position_reduced=%.2f",
                                                 states[i].pendingPartialStage, states[i].pendingPartialVolume,
                                                 states[i].pendingPartialFilledVolume, reduced));
         // 保留本阶段的已成交累计；清除请求锁，让下一次只补尚未成交的阶段手数。
         states[i].partialRequestPending = false;
         states[i].pendingPartialRequestTime = 0;
         ClearPendingTradeAction(i);
         ShortStateSave(i);
      }
   }
}

void ShortCheckPendingActionTimeouts()
{
   for(int i=0; i<ArraySize(states); i++)
   {
      if(!states[i].shortStateManaged || states[i].pendingAction == 待确认动作_无 ||
         states[i].pendingActionTime <= 0 || states[i].pendingAction == 待确认动作_部分平仓) continue;
      ReconcilePendingTradeAction(i);
      if(states[i].pendingAction == 待确认动作_无) continue;

      int action = states[i].pendingAction;
      int timeoutSeconds = (action == 待确认动作_全部平仓) ?
                           MathMax(短线单平仓确认超时秒数, 5) : MathMax(短线单SLTP确认超时秒数, 5);
      if(TimeCurrent()-states[i].pendingActionTime < timeoutSeconds) continue;

      if(action == 待确认动作_全部平仓)
      {
         datetime requestTime = states[i].pendingActionTime;
         if(states[i].positionIdentifier == 0 || !HistorySelectByPosition(states[i].positionIdentifier)) continue;
         ulong deals[];
         if(!SnapshotSelectedDealTickets(deals) || ArraySize(deals)==0) continue;
         bool historyReady=true;
         {
            for(int d=0; d<ArraySize(deals); d++)
            {
               ulong deal = deals[d];
               if(deal == 0 || ShortProcessedDealContains(deal)) continue;
               if(!HistoryDealSelect(deal)) { historyReady=false; continue; }
               if((datetime)HistoryDealGetInteger(deal, DEAL_TIME) < requestTime) continue;
               ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
               if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY || entry == DEAL_ENTRY_INOUT)
                  if(!ShortRecordDeal(deal, "full_close_timeout_reconcile")) historyReady=false;
            }
         }
         if(!historyReady) continue;
         if(states[i].pendingAction == 待确认动作_无) continue;
         if(!SelectPositionForShortState(i))
         {
            states[i].lifecyclePhase = 生命周期_等待最终结算;
            TradeJournalWriteLifecycle(i, "FULL_CLOSE_FILL",
                                       StringFormat("position_not_visible;reconciled_filled=%.2f;last_deal=%I64u",
                                                    states[i].pendingExitFilledVolume, states[i].lastLifecycleExitDeal));
            ClearPendingTradeAction(i);
            ShortStateSave(i);
            continue;
         }

         double remaining = PositionGetDouble(POSITION_VOLUME);
         int exitIntent = states[i].pendingExitIntent;
         double filled = states[i].pendingExitFilledVolume;
         states[i].pendingRetryCount++;
         TradeJournalWriteLifecycle(i, filled > 0.0 ? "FULL_CLOSE_TIMEOUT_PARTIAL_FILL" : "FULL_CLOSE_TIMEOUT_NO_FILL",
                                    StringFormat("retry=%d;filled=%.2f;remaining=%.2f;last_deal=%I64u",
                                                 states[i].pendingRetryCount, filled, remaining, states[i].lastLifecycleExitDeal));
         ClearPendingTradeAction(i);
         ShortStateSave(i);
         if(TimeCurrent()-states[i].lastManagedModifyTime >= MathMax(短线单平仓重试冷却秒数, 1))
         {
            if(!SubmitManagedFullClose(states[i].ticket, i, exitIntent, "full_close_timeout_remaining"))
            {
               states[i].lifecyclePhase = 生命周期_正常管理;
               MarkShortStateDirty(i);
            }
         }
         continue;
      }

      double actualSL = 0.0, actualTP = 0.0;
      if(SelectPositionForShortState(i))
      {
         actualSL = PositionGetDouble(POSITION_SL);
         actualTP = PositionGetDouble(POSITION_TP);
      }
      string detail = StringFormat("action=%d;requested_sl=%.5f;server_sl=%.5f;requested_tp=%.5f;server_tp=%.5f;elapsed=%d",
                                   action, states[i].pendingRequestedSL, actualSL,
                                   states[i].pendingRequestedTP, actualTP,
                                   (int)(TimeCurrent()-states[i].pendingActionTime));
      TradeJournalWriteLifecycle(i, "SLTP_MODIFY_FAILED", detail);
      if(states[i].pendingFastProtection) TradeJournalWriteLifecycle(i, "FAST_PROTECTION_FAILED", detail);
      if(states[i].pendingFixedTPRemoval) TradeJournalWriteLifecycle(i, "FIXED_TP_REMOVE_FAILED", detail);
      if(states[i].fixedTPRemoved && states[i].pendingRequestedTP > 0.0)
         TradeJournalWriteLifecycle(i, "FIXED_TP_RESTORE_FAILED", detail);
      ClearPendingTradeAction(i);
      if(states[i].lifecyclePhase == 生命周期_风险建立中) states[i].lifecyclePhase = 生命周期_异常待恢复;
      ShortStateSave(i);
   }
}

int ShortCandidateMarketRegime(const ShortLineMarketContext &ctx)
{
   if(ctx.momentumWeak && !ctx.m5SameDirection) return 短线环境_反向风险;
   if(ctx.strongForPosition && !ctx.nearBoxEdge) return 短线环境_强趋势;
   if(ctx.nearBoxEdge) return 短线环境_箱体边缘;
   if(ctx.momentumWeak) return 短线环境_动能衰竭;
   if(ctx.choppyForPosition) return 短线环境_震荡;
   if(ctx.m5SameDirection) return 短线环境_顺势;
   return 短线环境_未知;
}

void ShortUpdateMarketRegime(int stateIdx, const ShortLineMarketContext &ctx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return;
   int candidate = ShortCandidateMarketRegime(ctx);
   bool immediateRisk = (candidate == 短线环境_反向风险);
   datetime closedBarTime = iTime(_Symbol, PERIOD_M1, 1);
   if(!immediateRisk)
   {
      if(closedBarTime <= 0 || states[stateIdx].lastRegimeClosedBarTime == closedBarTime) return;
      states[stateIdx].lastRegimeClosedBarTime = closedBarTime;
   }
   if(candidate != states[stateIdx].candidateMarketRegime)
   {
      states[stateIdx].candidateMarketRegime = candidate;
      states[stateIdx].candidateRegimeCount = 1;
   }
   else if(!immediateRisk)
      states[stateIdx].candidateRegimeCount++;
   bool holdElapsed = (states[stateIdx].regimeChangedTime == 0 || TimeCurrent()-states[stateIdx].regimeChangedTime >= MathMax(短线单环境最短保持秒, 0));
   if((immediateRisk || (holdElapsed && states[stateIdx].candidateRegimeCount >= MathMax(短线单环境确认次数, 2))) &&
      states[stateIdx].confirmedMarketRegime != candidate)
   {
      PrintFormat("[短线环境] id=%I64u %d->%d，候选确认=%d", states[stateIdx].positionIdentifier,
                  states[stateIdx].confirmedMarketRegime, candidate, states[stateIdx].candidateRegimeCount);
      states[stateIdx].confirmedMarketRegime = candidate;
      states[stateIdx].regimeChangedTime = TimeCurrent();
      ShortStateSave(stateIdx);
      TradeJournalWriteLifecycle(stateIdx, "MARKET_REGIME_CHANGED", StringFormat("regime=%d;candidate_confirmations=%d", candidate, states[stateIdx].candidateRegimeCount));
   }
   else if(!immediateRisk)
      MarkShortStateDirty(stateIdx);
}

bool ShortReadKnownEntryCost(ulong positionIdentifier, double &cost, datetime segmentStartTime=0)
{
   PerformanceScope perfScope(PERF_HISTORY_QUERY);
   cost = 0.0;
   if(positionIdentifier == 0 || !HistorySelectByPosition(positionIdentifier)) return false;
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY);
      datetime dealTime = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      if(segmentStartTime > 0)
      {
         // Netting反转的新段只统计分段开始后的入场成本；INOUT费用无法可靠拆分，
         // 计入整笔是保守口径，不会把“已知成本后净额”高估。
         if(dealTime + 2 < segmentStartTime ||
            (entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT))
            continue;
      }
      else if(entry != DEAL_ENTRY_IN)
         continue;
      cost += HistoryDealGetDouble(deal, DEAL_COMMISSION) + HistoryDealGetDouble(deal, DEAL_FEE);
   }
   return true;
}

double ShortKnownEntryCost(ulong positionIdentifier)
{
   double cost = 0.0;
   ShortReadKnownEntryCost(positionIdentifier, cost);
   return cost;
}

void InvalidateEntryCostCache(int stateIdx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return;
   states[stateIdx].entryCostCacheReady = false;
   states[stateIdx].cachedEntryCost = 0.0;
   states[stateIdx].entryCostCacheTime = 0;
   states[stateIdx].entryCostCacheVolume = 0.0;
   states[stateIdx].entryCostCacheVersion++;
   states[stateIdx].floatingTimingEntryCostAttempted = false;
}

bool EnsureEntryCostCache(int stateIdx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || states[stateIdx].positionIdentifier == 0)
      return false;
   if(states[stateIdx].entryCostCacheReady) return true;

   double cost = 0.0;
   if(!ShortReadKnownEntryCost(states[stateIdx].positionIdentifier, cost,
                               states[stateIdx].lifecycleSegmentStartTime)) return false;
   states[stateIdx].cachedEntryCost = cost;
   states[stateIdx].entryCostCacheTime = TimeCurrent();
   // 调用方均已选中对应持仓；直接复用当前选择，避免一次额外Position选择。
   states[stateIdx].entryCostCacheVolume = PositionGetDouble(POSITION_VOLUME);
   states[stateIdx].entryCostCacheReady = true;
   return true;
}

double FloatingPnlTimingInitialRiskMoney(const int stateIdx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || !states[stateIdx].shortRiskReady ||
      states[stateIdx].shortInitialRisk <= _Point || states[stateIdx].initialVolume <= 0.0)
      return 0.0;

   double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   if(entryPrice <= 0.0) entryPrice = states[stateIdx].lastKnownOpenPrice;
   if(entryPrice <= 0.0) return 0.0;
   ENUM_ORDER_TYPE orderType = states[stateIdx].positionDirection == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double riskClose = states[stateIdx].positionDirection == POSITION_TYPE_BUY ?
                      entryPrice-states[stateIdx].shortInitialRisk : entryPrice+states[stateIdx].shortInitialRisk;
   double initialRiskMoney = 0.0;
   if(!OrderCalcProfit(orderType,_Symbol,states[stateIdx].initialVolume,entryPrice,riskClose,initialRiskMoney))
      return 0.0;
   return MathAbs(initialRiskMoney);
}

void UpdateLifecyclePnlEnvelope(const int stateIdx,const double lifecycleCurrentNet)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return;
   bool changed = !states[stateIdx].lifecyclePnlEnvelopeInitialized;
   if(lifecycleCurrentNet > states[stateIdx].maxLifecycleProfitMoney)
   {
      states[stateIdx].maxLifecycleProfitMoney = lifecycleCurrentNet;
      changed = true;
   }
   if(lifecycleCurrentNet < 0.0)
   {
      double lossMagnitude = -lifecycleCurrentNet;
      if(lossMagnitude > states[stateIdx].maxLifecycleLossMoney)
      {
         states[stateIdx].maxLifecycleLossMoney = lossMagnitude;
         changed = true;
      }
   }
   states[stateIdx].lifecyclePnlEnvelopeInitialized = true;
   if(changed) MarkShortStateDirty(stateIdx);
}

bool ReadFloatingPnlTimingState(const int stateIdx,
                                int &pnlState,
                                double &floatingNet,
                                double &flatThreshold)
{
   pnlState = 浮动状态_未知;
   floatingNet = 0.0;
   flatThreshold = 0.01;
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || !states[stateIdx].shortStateManaged ||
      states[stateIdx].floatingTimingFinalized || !SelectPositionForShortState(stateIdx))
      return false;

   double volume = PositionGetDouble(POSITION_VOLUME);
   double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
   if(volume <= 0.0 || currentPrice <= 0.0)
      return true; // 持仓仍在但行情无效：本次作为未知状态，不伪造0收益。

   double knownEntryCost = 0.0;
   if(states[stateIdx].entryCostCacheReady)
      knownEntryCost = states[stateIdx].cachedEntryCost;
   else if(!states[stateIdx].floatingTimingEntryCostAttempted)
   {
      // 每个缓存版本最多尝试一次历史查询；失败后安全退化，不在每秒重复扫描。
      states[stateIdx].floatingTimingEntryCostAttempted = true;
      if(EnsureEntryCostCache(stateIdx))
         knownEntryCost = states[stateIdx].cachedEntryCost;
   }

   double currentPositionFloatingNet = PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   floatingNet = currentPositionFloatingNet+knownEntryCost;
   UpdateLifecyclePnlEnvelope(stateIdx,
                              states[stateIdx].lifecycleRealizedNetMoney+currentPositionFloatingNet);
   double initialRiskMoney = FloatingPnlTimingInitialRiskMoney(stateIdx);
   flatThreshold = MathMax(0.01,initialRiskMoney*0.005);
   if(floatingNet > flatThreshold) pnlState = 浮动状态_浮盈;
   else if(floatingNet < -flatThreshold) pnlState = 浮动状态_浮亏;
   else pnlState = 浮动状态_近平;
   return true;
}

void AccumulateFloatingPnlTimingInterval(const int stateIdx,const double elapsedSeconds)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || elapsedSeconds <= 0.0) return;
   int state = states[stateIdx].floatingTimingCurrentState;
   if(state == 浮动状态_浮盈)
      states[stateIdx].floatingProfitSeconds += elapsedSeconds;
   else if(state == 浮动状态_浮亏)
   {
      states[stateIdx].floatingLossSeconds += elapsedSeconds;
      states[stateIdx].floatingTimingCurrentStateSeconds += elapsedSeconds;
      states[stateIdx].longestFloatingLossSeconds = MathMax(states[stateIdx].longestFloatingLossSeconds,
                                                            states[stateIdx].floatingTimingCurrentStateSeconds);
   }
   else if(state == 浮动状态_近平)
      states[stateIdx].floatingFlatSeconds += elapsedSeconds;
   else
      return;
   states[stateIdx].floatingTimingHasData = true;
}

void UpdateFloatingPnlTiming(const int stateIdx)
{
   int currentState = 浮动状态_未知;
   double floatingNet = 0.0;
   double flatThreshold = 0.01;
   if(!ReadFloatingPnlTimingState(stateIdx,currentState,floatingNet,flatThreshold)) return;

   ulong nowMs = GetTickCount64();
   datetime now = TimeCurrent();
   if(!states[stateIdx].floatingTimingSampleReady)
   {
      states[stateIdx].floatingTimingCurrentState = currentState;
      states[stateIdx].floatingTimingCurrentStateSeconds = 0.0;
      states[stateIdx].floatingTimingLastSampleMs = nowMs;
      states[stateIdx].floatingTimingSampleReady = true;
      if(currentState == 浮动状态_未知) return;
      if(states[stateIdx].floatingTimingObservationStartTime == 0)
         states[stateIdx].floatingTimingObservationStartTime = now;
      if(currentState == 浮动状态_浮盈 && states[stateIdx].firstFloatingProfitTime == 0)
         states[stateIdx].firstFloatingProfitTime = now;
      MarkShortStateDirty(stateIdx);
      return;
   }

   double elapsedSeconds = (double)(nowMs-states[stateIdx].floatingTimingLastSampleMs)/1000.0;
   states[stateIdx].floatingTimingLastSampleMs = nowMs;
   if(elapsedSeconds > FLOATING_TIMING_MAX_GAP_SECONDS)
   {
      // 卡顿、休眠或离线长间隔的状态未知，不能硬归类到中断前状态。
      states[stateIdx].floatingTimingCurrentState = currentState;
      states[stateIdx].floatingTimingCurrentStateSeconds = 0.0;
      if(currentState != 浮动状态_未知 && states[stateIdx].floatingTimingObservationStartTime == 0)
      {
         states[stateIdx].floatingTimingObservationStartTime = now;
         MarkShortStateDirty(stateIdx);
      }
      if(currentState == 浮动状态_浮盈 && states[stateIdx].firstFloatingProfitTime == 0)
      {
         states[stateIdx].firstFloatingProfitTime = now;
         MarkShortStateDirty(stateIdx);
      }
      return;
   }

   if(elapsedSeconds > 0.0)
      AccumulateFloatingPnlTimingInterval(stateIdx,elapsedSeconds);

   bool importantChange = false;
   if(currentState != states[stateIdx].floatingTimingCurrentState)
   {
      states[stateIdx].floatingTimingSwitchCount++;
      states[stateIdx].floatingTimingCurrentState = currentState;
      states[stateIdx].floatingTimingCurrentStateSeconds = 0.0;
      importantChange = true;
   }
   if(currentState != 浮动状态_未知 && states[stateIdx].floatingTimingObservationStartTime == 0)
   {
      states[stateIdx].floatingTimingObservationStartTime = now;
      importantChange = true;
   }
   if(currentState == 浮动状态_浮盈 && states[stateIdx].firstFloatingProfitTime == 0)
   {
      states[stateIdx].firstFloatingProfitTime = now;
      importantChange = true;
   }
   if(importantChange) MarkShortStateDirty(stateIdx);

   double observedSeconds = states[stateIdx].floatingProfitSeconds+
                            states[stateIdx].floatingLossSeconds+
                            states[stateIdx].floatingFlatSeconds;
   if(observedSeconds-states[stateIdx].floatingTimingLastPersistObservedSeconds >= 10.0)
   {
      states[stateIdx].floatingTimingLastPersistObservedSeconds = observedSeconds;
      MarkShortStateDirty(stateIdx);
   }
}

void UpdateAllFloatingPnlTimings()
{
   for(int i=0;i<ArraySize(states);i++)
      UpdateFloatingPnlTiming(i);
}

void FinalizeFloatingPnlTiming(const int stateIdx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || states[stateIdx].floatingTimingFinalized) return;
   if(states[stateIdx].floatingTimingSampleReady)
   {
      ulong nowMs = GetTickCount64();
      double elapsedSeconds = (double)(nowMs-states[stateIdx].floatingTimingLastSampleMs)/1000.0;
      if(elapsedSeconds > 0.0 && elapsedSeconds <= FLOATING_TIMING_MAX_GAP_SECONDS)
         AccumulateFloatingPnlTimingInterval(stateIdx,elapsedSeconds);
      states[stateIdx].floatingTimingLastSampleMs = nowMs;
   }
   states[stateIdx].floatingTimingFinalized = true;
   MarkShortStateDirty(stateIdx);
}

void ResetFloatingPnlTimingForNewLifecycleSegment(const int stateIdx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states)) return;
   states[stateIdx].floatingProfitSeconds = 0.0;
   states[stateIdx].floatingLossSeconds = 0.0;
   states[stateIdx].floatingFlatSeconds = 0.0;
   states[stateIdx].longestFloatingLossSeconds = 0.0;
   states[stateIdx].firstFloatingProfitTime = 0;
   states[stateIdx].floatingTimingObservationStartTime = 0;
   states[stateIdx].floatingTimingHasData = false;
   states[stateIdx].floatingTimingFinalized = false;
   states[stateIdx].floatingTimingCurrentState = 浮动状态_未知;
   states[stateIdx].floatingTimingCurrentStateSeconds = 0.0;
   states[stateIdx].floatingTimingLastSampleMs = 0;
   states[stateIdx].floatingTimingSampleReady = false;
   states[stateIdx].floatingTimingLastPersistObservedSeconds = 0.0;
   states[stateIdx].floatingTimingSwitchCount = 0;
   states[stateIdx].floatingTimingEntryCostAttempted = false;
   MarkShortStateDirty(stateIdx);
}

double ShortCalculateNetBreakEvenPrice(ulong ticket, double safetyMoney)
{
   if(!PositionSelectByTicket(ticket)) return 0.0;
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double open = PositionGetDouble(POSITION_PRICE_OPEN);
   double volume = PositionGetDouble(POSITION_VOLUME);
   double current = type == POSITION_TYPE_BUY ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(open <= 0.0 || volume <= 0.0 || current <= 0.0) return 0.0;
   // 只缓存历史中已经发生的入场佣金/费用；动态Swap与未来出场安全金额仍按原公式实时处理。
   ulong positionIdentifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   double knownEntryCost = 0.0;
   int stateIdx = FindShortStateByPositionIdentifier(positionIdentifier);
   if(stateIdx >= 0)
   {
      if(EnsureEntryCostCache(stateIdx)) knownEntryCost = states[stateIdx].cachedEntryCost;
   }
   else
      knownEntryCost = ShortKnownEntryCost(positionIdentifier);
   double knownCosts = knownEntryCost + PositionGetDouble(POSITION_SWAP);
   ENUM_ORDER_TYPE orderType = type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double lo = type == POSITION_TYPE_BUY ? open : current;
   double hi = type == POSITION_TYPE_BUY ? current : open;
   if(hi <= lo + _Point) return 0.0;
   for(int i=0; i<28; i++)
   {
      double mid = (lo+hi)*0.5, gross = 0.0;
      if(!OrderCalcProfit(orderType, _Symbol, volume, open, mid, gross)) return 0.0;
      bool sufficient = (gross + knownCosts >= safetyMoney);
      if(type == POSITION_TYPE_BUY)
      {
         if(sufficient) hi = mid; else lo = mid;
      }
      else
      {
         if(sufficient) lo = mid; else hi = mid;
      }
   }
   double result = NormalizePrice(type == POSITION_TYPE_BUY ? hi : lo);
   PrintRateLimited(StringFormat("short_net_be:%I64u", ticket), 10,
                    StringFormat("[短线净保本] ticket=%I64u price=%.5f safety=%.2f knownEntryCost=%.2f exitCost=由安全金额覆盖",
                                 ticket, result, safetyMoney, knownCosts));
   return result;
}

void ShortPushFastPriceTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.bid <= 0.0 || tick.ask <= tick.bid) return;
   shortFastTicks[shortFastTickHead].timeMsc = (ulong)tick.time_msc;
   shortFastTicks[shortFastTickHead].mid = (tick.bid+tick.ask)*0.5;
   shortFastTickHead = (shortFastTickHead+1) % SHORT_FAST_TICK_CAPACITY;
   if(shortFastTickCount < SHORT_FAST_TICK_CAPACITY) shortFastTickCount++;
}

bool ShortFastMoveInWindow(ENUM_POSITION_TYPE type, double requiredMove)
{
   if(shortFastTickCount < 2 || requiredMove <= 0.0) return false;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.time_msc == 0) return false;
   ulong windowMs = (ulong)MathMax(短线单快速保护观察秒数, 1)*1000;
   ulong tickMsc = (ulong)tick.time_msc;
   ulong fromMsc = tickMsc > windowMs ? tickMsc-windowMs : (ulong)0;
   double currentMid = (tick.bid+tick.ask)*0.5;
   double minMid = currentMid, maxMid = currentMid;
   int used = 0;
   for(int n=0; n<shortFastTickCount; n++)
   {
      int idx = (shortFastTickHead-1-n+SHORT_FAST_TICK_CAPACITY) % SHORT_FAST_TICK_CAPACITY;
      if(shortFastTicks[idx].timeMsc < fromMsc) break;
      minMid = MathMin(minMid, shortFastTicks[idx].mid);
      maxMid = MathMax(maxMid, shortFastTicks[idx].mid);
      used++;
   }
   if(used < 2) return false;
   return type == POSITION_TYPE_BUY ? (currentMid-minMid >= requiredMove) : (maxMid-currentMid >= requiredMove);
}

bool ShortFastProtectionCandidate(ulong ticket, int stateIdx, ENUM_POSITION_TYPE type, double profitPrice,
                                  double atr, const ShortLineMarketContext &ctx, double &candidateSL, int &candidateSource)
{
   candidateSL = 0.0;
   candidateSource = SL来源_无;
   if(!短线单启用快速利润保护 || stateIdx < 0 || stateIdx >= ArraySize(states) ||
      !states[stateIdx].shortRiskReady || states[stateIdx].fastProtectionActivated) return false;
   double rTrigger = states[stateIdx].shortInitialRisk * MathMax(短线单快速保护启动R, 0.10);
   double openPrice = PositionSelectByTicket(ticket) ? PositionGetDouble(POSITION_PRICE_OPEN) : 0.0;
   bool teacherSelected = false;
   double teacherTarget = 0.0;
   double tp = ShortLineEffectiveMainTPDistance(stateIdx, type, openPrice, atr,
                                                 teacherSelected, teacherTarget);
   bool fastBody = (ctx.lastBody >= MathMax(ctx.atrM1, _Point) * MathMax(短线单快速保护实体ATR倍数, 0.10));
   bool nearTP = (tp > 0.0 && profitPrice >= tp * ClampDouble(短线单快速保护TP完成比例, 0.10, 1.00));
   bool fastMove = ShortFastMoveInWindow(type, rTrigger);
   if(profitPrice < rTrigger || (!fastBody && !nearTP && !fastMove)) return false;
   double volume = PositionSelectByTicket(ticket) ? PositionGetDouble(POSITION_VOLUME) : 0.0;
   double safety = MathMax(短线单净保本安全金额每001手, 0.0) * volume / 0.01;
   candidateSL = ShortCalculateNetBreakEvenPrice(ticket, safety);
   if(candidateSL <= 0.0) return false;
   // 不等待M1收线的快速保护可参考正在形成的微型箱体，但净保本始终是最低保护底线。
   // 因此微箱体只会把SL进一步推向盈利方向，绝不会让它退回到净保本以下。
   double microSL = 0.0, microMinDistance = 0.0;
   datetime microBarTime = 0;
   bool microRaisedProtection =
      ShortLineMicroBoxStructureSL(type, atr, true, microSL, microMinDistance, microBarTime) &&
      MoreProtective(type, microSL, candidateSL);
   if(microRaisedProtection) candidateSL = microSL;
   candidateSource = microRaisedProtection ? SL来源_快速微型箱体 : SL来源_快速净保本;
   return true;
}

void ShortUpdateRunnerMode(int stateIdx, const ShortLineMarketContext &ctx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || !states[stateIdx].partialTPDone) return;
   int wanted = 短线尾仓_固定TP;
   int regime = states[stateIdx].confirmedMarketRegime;
   if(regime == 短线环境_强趋势 && 短线单尾仓交给结构追踪) wanted = 短线尾仓_结构追踪;
   else if(regime == 短线环境_箱体边缘 || regime == 短线环境_震荡) wanted = 短线尾仓_箱体目标;
   else if(regime == 短线环境_动能衰竭 || regime == 短线环境_反向风险) wanted = 短线尾仓_快速退出;
   if(states[stateIdx].runnerMode != wanted)
   {
      states[stateIdx].runnerMode = wanted;
      PrintFormat("[短线尾仓] id=%I64u mode=%d", states[stateIdx].positionIdentifier, wanted);
      ShortStateSave(stateIdx);
      TradeJournalWriteLifecycle(stateIdx, "RUNNER_MODE_CHANGED", StringFormat("runner_mode=%d", wanted));
   }
}

void ClassifyShortTradeArchetype(int stateIdx, ENUM_POSITION_TYPE type, double openPrice,
                                 const ShortLineMarketContext &ctx)
{
   if(stateIdx < 0 || stateIdx >= ArraySize(states) || states[stateIdx].tradeArchetype != 短线类型_未知) return;
   datetime classificationTime = states[stateIdx].lifecycleSegmentStartTime > 0 ?
                                 states[stateIdx].lifecycleSegmentStartTime : states[stateIdx].positionOpenTime;
   if(classificationTime <= 0 || TimeCurrent()-classificationTime > 10*60) return;
   int openShift = iBarShift(_Symbol, PERIOD_M1, classificationTime, false);
   int signalShift = openShift >= 0 ? openShift+1 : -1;
   if(signalShift < 1 || Bars(_Symbol, PERIOD_M1) <= signalShift+2) return;

   double signalOpen = iOpen(_Symbol, PERIOD_M1, signalShift);
   double signalHigh = iHigh(_Symbol, PERIOD_M1, signalShift);
   double signalLow = iLow(_Symbol, PERIOD_M1, signalShift);
   double signalClose = iClose(_Symbol, PERIOD_M1, signalShift);
   if(signalOpen <= 0.0 || signalHigh <= 0.0 || signalLow <= 0.0 || signalClose <= 0.0) return;

   int archetype = 短线类型_普通手动;
   bool hasValidBox = RefreshShortVisualBoxState() && shortVisualBox.hasBox && shortVisualBox.validBox &&
                      shortVisualBox.boxHigh > shortVisualBox.boxLow;
   if(hasValidBox)
   {
      double buffer = MathMax(MathMax(ctx.atrM1, _Point)*0.15, CurrentSpreadPrice()*2.0);
      bool upperSweep = signalHigh > shortVisualBox.boxHigh && signalClose <= shortVisualBox.boxHigh;
      bool lowerSweep = signalLow < shortVisualBox.boxLow && signalClose >= shortVisualBox.boxLow;
      bool upBreak = signalClose > shortVisualBox.boxHigh+buffer;
      bool downBreak = signalClose < shortVisualBox.boxLow-buffer;
      double ratio = ClampDouble((openPrice-shortVisualBox.boxLow)/(shortVisualBox.boxHigh-shortVisualBox.boxLow), 0.0, 1.0);
      if((type == POSITION_TYPE_BUY && lowerSweep) || (type == POSITION_TYPE_SELL && upperSweep))
         archetype = 短线类型_扫损接回;
      else if((type == POSITION_TYPE_BUY && upBreak) || (type == POSITION_TYPE_SELL && downBreak))
         archetype = 短线类型_箱体突破;
      else if((type == POSITION_TYPE_BUY && ratio <= 0.25) || (type == POSITION_TYPE_SELL && ratio >= 0.75))
         archetype = 短线类型_箱体反转;
      else if(ctx.m5SameDirection)
         archetype = 短线类型_趋势回踩;
   }
   else if(ctx.m5SameDirection)
      archetype = 短线类型_趋势回踩;

   states[stateIdx].tradeArchetype = archetype;
   ShortStateSave(stateIdx);
   TradeJournalWriteLifecycle(stateIdx, "TRADE_ARCHETYPE_CLASSIFIED",
                              StringFormat("archetype=%d;signal_shift=%d;box_valid=%d", archetype, signalShift, hasValidBox ? 1 : 0));
}

void ShortEmergencyRiskManagement(ulong ticket, double atr)
{
   if(!ShortSpreadAllowsEmergencyManagement()) return;
   if(!PositionSelectByTicket(ticket) || !PositionInScope()) return;
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   int stateIdx = EnsureState(ticket);
   PositionTemplateScope templateScope(stateIdx);
   if(当前参数配置模板 != 配置_黄金超短快保) return;
   bool becameManaged = !states[stateIdx].shortStateManaged;
   states[stateIdx].shortStateManaged = true;
   if(becameManaged) MarkShortStateDirty(stateIdx);
   bool ready = ShortEnsureInitialRiskReady(ticket, stateIdx, type, openPrice, atr);
   if(!PositionSelectByTicket(ticket)) return;
   double curSL = PositionGetDouble(POSITION_SL);
   if(curSL <= 0.0)
      PrintRateLimited(StringFormat("short_high_spread_no_sl:%I64u", ticket), 10,
                       StringFormat("[短线风险] 高点差下仍无SL ticket=%I64u，持续尝试灾难保护", ticket));
   if(!ready || states[stateIdx].shortInitialRisk <= 0.0) return;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double loss = type == POSITION_TYPE_BUY ? openPrice-bid : ask-openPrice;
   if(loss >= states[stateIdx].shortInitialRisk * MathMax(短线单绝对最大风险R, 1.0))
   {
      TradeJournalWriteLifecycle(stateIdx, "EMERGENCY_CLOSE_REQUEST", StringFormat("loss=%.5f;initial_r=%.5f", loss, states[stateIdx].shortInitialRisk));
      if(SubmitManagedFullClose(ticket, stateIdx, 退出意图_紧急风控, "absolute_risk_guard"))
         PrintFormat("[短线风险] 高点差绝对风险退出 ticket=%I64u loss=%.5f R=%.5f", ticket, loss, states[stateIdx].shortInitialRisk);
   }
}

int CurrentPanelWidth()
{
   // 拖动命中范围必须使用“实际绘制宽度”，否则自动撑宽后右侧区域会拖不动。
   if(当前面板宽度 > 0)
      return 当前面板宽度;
   if(当前面板显示模式 == 面板迷你)
      return MathMax(迷你面板宽度, 390);
   if(当前面板显示模式 == 面板隐藏)
      return 232;
   return MathMax(面板宽度, 280);
}

int CurrentPanelHeight()
{
   if(当前面板高度 > 0)
      return 当前面板高度;
   if(当前面板显示模式 == 面板隐藏)
      return 58;
   if(当前面板显示模式 == 面板迷你)
      return 170;
   return 430;
}

bool IsPointInPanelButtonArea(const int x, const int y)
{
   // 所有按钮都是 OBJ_BUTTON，拖动时只避开按钮，其他文字/空白区域都允许拖。
   int total = ObjectsTotal(0, 0, -1);
   for(int i=total-1; i>=0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, "SMA_BTN_") != 0)
         continue;

      int bx = (int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE);
      int by = (int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE);
      int bw = (int)ObjectGetInteger(0, name, OBJPROP_XSIZE);
      int bh = (int)ObjectGetInteger(0, name, OBJPROP_YSIZE);
      if(x >= bx && x <= bx + bw && y >= by && y <= by + bh)
         return true;
   }
   return false;
}

bool IsPanelObjectName(string name)
{
   return (StringFind(name, "SMA_PANEL_") == 0 || StringFind(name, "SMA_BTN_") == 0);
}

void MoveExistingPanelObjects(const int dx, const int dy)
{
   if(dx == 0 && dy == 0)
      return;

   int total = ObjectsTotal(0, 0, -1);
   for(int i=total-1; i>=0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(!IsPanelObjectName(name))
         continue;

      int ox = (int)ObjectGetInteger(0, name, OBJPROP_XDISTANCE);
      int oy = (int)ObjectGetInteger(0, name, OBJPROP_YDISTANCE);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, ox + dx);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, oy + dy);
   }
}

bool IsPointInPanelDragArea(const int x, const int y)
{
   if(!允许鼠标拖动面板) return false;

   int w = CurrentPanelWidth();
   int h = CurrentPanelHeight();

   if(x < 当前面板左边距 || x > 当前面板左边距 + w)
      return false;
   if(y < 当前面板上边距 || y > 当前面板上边距 + h)
      return false;

   // 原来只允许拖顶部标题栏，实盘使用很容易点不中；现在整块面板非按钮区域都可拖动。
   if(IsPointInPanelButtonArea(x, y))
      return false;

   return true;
}

bool LeftMouseDownFromMask(const string maskText)
{
   int mask = (int)StringToInteger(maskText);
   return ((mask & 1) == 1);
}

void ClampPanelPosition()
{
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int maxX = (cw > 80 ? cw - 80 : 0);
   int maxY = (ch > 40 ? ch - 40 : 0);
   if(当前面板左边距 < 0) 当前面板左边距 = 0;
   if(当前面板上边距 < 0) 当前面板上边距 = 0;
   if(当前面板左边距 > maxX) 当前面板左边距 = maxX;
   if(当前面板上边距 > maxY) 当前面板上边距 = maxY;
}

void ApplyDraggedPanelPosition()
{
   if(!允许鼠标拖动面板) return;
   if(ObjectFind(0, "SMA_PANEL_BG") < 0) return;
   当前面板左边距 = (int)ObjectGetInteger(0, "SMA_PANEL_BG", OBJPROP_XDISTANCE);
   当前面板上边距 = (int)ObjectGetInteger(0, "SMA_PANEL_BG", OBJPROP_YDISTANCE);
   ClampPanelPosition();
   ObjectSetInteger(0, "SMA_PANEL_BG", OBJPROP_SELECTED, false);
   上次面板状态文本 = "";
   RefreshPanel(true);
   ChartRedraw(0);
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   PerformanceScope perfScope(PERF_ON_CHART_EVENT);
   if(HandleCanvasMiniChartEvent(id,lparam,dparam,sparam)) return;

   if(id == CHARTEVENT_CHART_CHANGE)
   {
      // 垂直缩放/拉伸价格轴也会高频触发 CHART_CHANGE。
      // 旧逻辑每次都删除按钮和文字再重绘，导致面板闪烁。
      // 这里仅在图表像素尺寸真的变化时刷新面板；普通价格比例变化不碰面板对象。
      int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
      int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
      bool sizeChanged = (cw != 上次图表宽度像素 || ch != 上次图表高度像素);
      上次图表宽度像素 = cw;
      上次图表高度像素 = ch;

      if(!sizeChanged)
         return;

      面板正在拖动 = false;
      ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
      int oldX = 当前面板左边距;
      int oldY = 当前面板上边距;
      ClampPanelPosition();
      MoveExistingPanelObjects(当前面板左边距 - oldX, 当前面板上边距 - oldY);
      上次面板状态文本 = "";
      RefreshPanel(true);
      return;
   }

   // MT5里矩形背景对象经常需要先选中才可拖动；这里改成“按住面板标题栏/黑色空白处拖动”，不依赖对象选中。
   if(id == CHARTEVENT_MOUSE_MOVE && 允许鼠标拖动面板)
   {
      int mx = (int)lparam;
      int my = (int)dparam;
      bool leftDown = LeftMouseDownFromMask(sparam);

      if(leftDown)
      {
         if(!面板正在拖动 && IsPointInPanelDragArea(mx, my))
         {
            面板正在拖动 = true;
            面板拖动起始鼠标X = mx;
            面板拖动起始鼠标Y = my;
            面板拖动起始面板X = 当前面板左边距;
            面板拖动起始面板Y = 当前面板上边距;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
         }

         if(面板正在拖动)
         {
            int oldX = 当前面板左边距;
            int oldY = 当前面板上边距;
            当前面板左边距 = 面板拖动起始面板X + (mx - 面板拖动起始鼠标X);
            当前面板上边距 = 面板拖动起始面板Y + (my - 面板拖动起始鼠标Y);
            ClampPanelPosition();
            MoveExistingPanelObjects(当前面板左边距 - oldX, 当前面板上边距 - oldY);
            上次面板状态文本 = "";
            ChartRedraw(0);
            return;
         }
      }
      else
      {
         if(面板正在拖动)
         {
            面板正在拖动 = false;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
            上次面板状态文本 = "";
            RefreshPanel(true);
            ChartRedraw(0);
            return;
         }
      }
   }

   if(id == CHARTEVENT_OBJECT_DRAG && sparam == "SMA_PANEL_BG")
   {
      ApplyDraggedPanelPosition();
      return;
   }

   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == "SMA_BTN_NEWS_FREEZE" || sparam == "SMA_BTN_NEWS_RELEASE" ||
      sparam == "SMA_BTN_NEWS_CANCEL" || sparam == "SMA_BTN_NEWS_FLAT")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      if(sparam == "SMA_BTN_NEWS_FREEZE")
         NewsFreezeBoxByUser();
      else if(sparam == "SMA_BTN_NEWS_RELEASE")
      {
         if(newsState.stage==消息阶段_箱体冻结 && newsState.buyTicket==0 && newsState.sellTicket==0)
            NewsDeployStopPair();
         else NewsEnableRelease();
      }
      else if(sparam == "SMA_BTN_NEWS_CANCEL")
      {
         if(newsState.stopToken>0)
            NewsCancelStopDeployment();
         else if(newsState.stage != 消息阶段_待命)
            NewsRequestGroupExit("用户取消本次消息");
         else
         {
            NewsCloseEligiblePositions("用户取消本次消息");
            newsState.waitStartTime = TimeCurrent()-MathMax(消息对冲配对等待秒, 1);
         }
      }
      else
      {
         if(newsState.stage != 消息阶段_待命)
            NewsRequestGroupExit("用户消息紧急全平");
         else
         {
            NewsCloseEligiblePositions("用户消息紧急全平");
            newsState.waitStartTime = TimeCurrent()-MathMax(消息对冲配对等待秒, 1);
         }
      }
      RefreshPanel(true);
      ChartRedraw(0);
      return;
   }

   if(sparam == "SMA_BTN_PANEL_MINI")
   {
      当前面板显示模式 = 面板迷你;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      DeletePanelButtons();
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
      return;
   }
   else if(sparam == "SMA_BTN_MARKER_VIS")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      if(!启用手机标记挂单)
      {
         lastStatus = "提示挂单受参数开关关闭，未执行任何订单操作";
      }
      else
      {
         // MT5 不能只隐藏某一张真实挂单的价格线；关闭即撤 SMA_MARK_* 提示挂单，开启后按原规则重建。
         手机标记挂单面板开关 = !手机标记挂单面板开关;
         保存手机标记挂单面板开关();
         ManageMobileMarkerOrders(true);
         lastStatus = 手机标记挂单面板开关 ? "提示挂单开启：正在同步" : "提示挂单关闭：已请求撤销";
      }
      RefreshPanel(true);
      ChartRedraw(0);
      return;
   }
   else if(sparam == "SMA_BTN_VIEW_TOGGLE")
   {
      当前面板信息模式 = 当前面板信息模式 == 面板信息_简单 ? 面板信息_专业 : 面板信息_简单;
      保存面板信息模式();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      DeletePanelButtons();
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
      return;
   }
   else if(sparam == "SMA_BTN_PANEL_FULL")
   {
      当前面板显示模式 = 面板完整;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      DeletePanelButtons();
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
      return;
   }
   else if(sparam == "SMA_BTN_PANEL_HIDE")
   {
      当前面板显示模式 = 面板隐藏;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      DeletePanelButtons();
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
      return;
   }

   if(sparam == "SMA_BTN_CFG_CUSTOM" || sparam == "SMA_BTN_CFG_FAST" || sparam == "SMA_BTN_CFG_TREND" ||
      sparam == "SMA_BTN_CFG_SRTP" || sparam == "SMA_BTN_CFG_NEWS")
   {
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      if(sparam == "SMA_BTN_CFG_CUSTOM") ApplyPanelConfigTemplate(配置_自定义);
      else if(sparam == "SMA_BTN_CFG_FAST") ApplyPanelConfigTemplate(配置_黄金超短快保);
      else if(sparam == "SMA_BTN_CFG_TREND") ApplyPanelConfigTemplate(配置_黄金稳健托管);
      else if(sparam == "SMA_BTN_CFG_SRTP") ApplyPanelConfigTemplate(配置_黄金支压止盈);
      else if(sparam == "SMA_BTN_CFG_NEWS") ApplyPanelConfigTemplate(配置_黄金消息对冲);
      DeletePanelButtons();
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
      return;
   }

   if(sparam == "SMA_BTN_POS")
   {
      当前面板页面 = 页面持仓;
      if(当前面板显示模式 == 面板迷你) 当前面板显示模式 = 面板完整;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      DeletePanelButtons();
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_DAY")
   {
      当前面板页面 = 页面今日;
      if(当前面板显示模式 == 面板迷你) 当前面板显示模式 = 面板完整;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      DeletePanelButtons();
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_FILTER_SHORT" || sparam == "SMA_BTN_FILTER_ALL" ||
           sparam == "SMA_BTN_FILTER_TREND" || sparam == "SMA_BTN_FILTER_NORMAL" ||
           sparam == "SMA_BTN_FILTER_NEWS")
   {
      当前面板页面 = 页面今日;
      if(sparam == "SMA_BTN_FILTER_SHORT") 当前统计筛选 = 统计筛选_短线;
      else if(sparam == "SMA_BTN_FILTER_ALL") 当前统计筛选 = 统计筛选_全部;
      else if(sparam == "SMA_BTN_FILTER_TREND") 当前统计筛选 = 统计筛选_趋势;
      else if(sparam == "SMA_BTN_FILTER_NORMAL") 当前统计筛选 = 统计筛选_普通;
      else 当前统计筛选 = 统计筛选_消息;
      当前复盘序号 = 0;
      InvalidateStatsCache(true);
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_DETAIL_OVERVIEW" || sparam == "SMA_BTN_DETAIL_STRATEGY" ||
           sparam == "SMA_BTN_DETAIL_MANAGE" || sparam == "SMA_BTN_DETAIL_EXEC" || sparam == "SMA_BTN_DETAIL_REVIEW")
   {
      当前面板页面 = 页面今日;
      if(sparam == "SMA_BTN_DETAIL_OVERVIEW") 当前统计详情 = 统计详情_总览;
      else if(sparam == "SMA_BTN_DETAIL_STRATEGY") 当前统计详情 = 统计详情_策略;
      else if(sparam == "SMA_BTN_DETAIL_MANAGE") 当前统计详情 = 统计详情_管理;
      else if(sparam == "SMA_BTN_DETAIL_EXEC") 当前统计详情 = 统计详情_执行;
      else 当前统计详情 = 统计详情_复盘;
      当前复盘序号 = 0;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_REVIEW_PREV" || sparam == "SMA_BTN_REVIEW_NEXT")
   {
      // 复盘按最新在前排列：上一单查看更早交易，下一单回到更近交易。
      if(sparam == "SMA_BTN_REVIEW_PREV") 当前复盘序号++;
      else 当前复盘序号 = MathMax(当前复盘序号-1, 0);
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_STAT_DAY")
   {
      当前面板页面 = 页面今日;
      当前统计周期 = 统计_日;
      当前复盘序号 = 0;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_STAT_WEEK")
   {
      当前面板页面 = 页面今日;
      当前统计周期 = 统计_周;
      当前复盘序号 = 0;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_STAT_MONTH")
   {
      当前面板页面 = 页面今日;
      当前统计周期 = 统计_月;
      当前复盘序号 = 0;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_PREV_DAY")
   {
      当前面板页面 = 页面今日;
      当前统计周期 = 统计_日;
      统计日期偏移天数--;
      当前复盘序号 = 0;
      InvalidateStatsCache();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_TODAY")
   {
      当前面板页面 = 页面今日;
      当前统计周期 = 统计_日;
      统计日期偏移天数 = 0;
      当前复盘序号 = 0;
      InvalidateStatsCache();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_NEXT_DAY")
   {
      当前面板页面 = 页面今日;
      当前统计周期 = 统计_日;
      统计日期偏移天数++;
      当前复盘序号 = 0;
      InvalidateStatsCache();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_PREV_WEEK")
   {
      当前面板页面 = 页面今日;
      当前统计周期 = 统计_周;
      统计周偏移周数--;
      当前复盘序号 = 0;
      InvalidateStatsCache();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_THIS_WEEK")
   {
      当前面板页面 = 页面今日;
      当前统计周期 = 统计_周;
      统计周偏移周数 = 0;
      当前复盘序号 = 0;
      InvalidateStatsCache();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_NEXT_WEEK")
   {
      当前面板页面 = 页面今日;
      当前统计周期 = 统计_周;
      统计周偏移周数++;
      当前复盘序号 = 0;
      InvalidateStatsCache();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_PREV_MONTH")
   {
      当前面板页面 = 页面今日;
      当前统计周期 = 统计_月;
      统计月偏移月数--;
      当前复盘序号 = 0;
      InvalidateStatsCache();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_THIS_MONTH")
   {
      当前面板页面 = 页面今日;
      当前统计周期 = 统计_月;
      统计月偏移月数 = 0;
      当前复盘序号 = 0;
      InvalidateStatsCache();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
   else if(sparam == "SMA_BTN_NEXT_MONTH")
   {
      当前面板页面 = 页面今日;
      当前统计周期 = 统计_月;
      统计月偏移月数++;
      当前复盘序号 = 0;
      InvalidateStatsCache();
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ClearPanelLines();
      RefreshPanel(true);
      ChartRedraw(0);
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   PerformanceScope perfScope(PERF_ON_TRADE_TRANSACTION);
   if(trans.symbol==_Symbol || request.symbol==_Symbol)
      手机标记环境Dirty=true;
   if(trans.type == TRADE_TRANSACTION_REQUEST)
   {
      for(int i=0; i<ArraySize(states); i++)
      {
         if(request.position != states[i].ticket && request.position != states[i].positionIdentifier) continue;
         TradeJournalWriteLifecycle(i, "TRADE_REQUEST_RESULT",
                                    StringFormat("action=%d;position=%I64u;order=%I64u;volume=%.2f;price=%.5f;sl=%.5f;tp=%.5f;retcode=%u;comment=%s;request_id=%I64u;result_order=%I64u;result_deal=%I64u",
                                                 request.action, request.position, request.order, request.volume, request.price,
                                                 request.sl, request.tp, result.retcode, result.comment, result.request_id, result.order, result.deal));
         break;
      }
      return;
   }
   if(trans.type == TRADE_TRANSACTION_POSITION)
   {
      for(int i=0; i<ArraySize(states); i++)
      {
         if(trans.position == states[i].ticket || trans.position == states[i].positionIdentifier)
            ReconcilePendingTradeAction(i);
      }
      return;
   }
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0) return;
   teacherActiveHistoryDirty=true; // 即使Deal暂不可读，也先阻止下一单，Timer历史对账后解除
   teacherActiveLatestDeal=trans.deal;
   // 统计页按真实Deal事件失效，普通Tick不重复扫描历史。
   InvalidateStatsCache();
   if(使用新版Canvas面板)
   {
      CanvasMiniModelValid=false;
      CanvasHoldingModelValid=false;
      MarkCanvasPanelDirty(PANEL_DIRTY_DATA);
   }
   bool shortRelated = false;
   ulong dealPositionId = 0;
   if(HistoryDealSelect(trans.deal)) dealPositionId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   for(int i=0; i<ArraySize(states); i++)
   {
      if(!states[i].shortStateManaged) continue;
      if(dealPositionId == states[i].positionIdentifier || trans.position == states[i].ticket || trans.position == states[i].positionIdentifier)
      {
         shortRelated = true;
         break;
      }
   }
   if(!HistoryDealSelect(trans.deal))
   {
      if(shortRelated) ShortEnqueuePendingDeal(trans.deal);
      if(newsState.stage == 消息阶段_待命) return;
      bool related = (trans.position == newsState.buyTicket || trans.position == newsState.sellTicket ||
                      trans.position == newsState.runnerTicket || trans.position == newsState.loserTicket ||
                      trans.position == newsState.buyPositionId || trans.position == newsState.sellPositionId ||
                      trans.position == newsState.runnerPositionId || trans.position == newsState.loserPositionId);
      if(related) NewsEnqueuePendingDeal(trans.deal);
      return;
   }
   ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if((dealEntry==DEAL_ENTRY_IN || dealEntry==DEAL_ENTRY_INOUT) &&
      HistoryDealGetString(trans.deal,DEAL_SYMBOL)==_Symbol &&
      (long)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)==消息双Stop挂单Magic && newsState.stopToken>0)
   {
      string stopComment=HistoryDealGetString(trans.deal,DEAL_COMMENT);
      if(NewsStopCommentMatches(stopComment,1)) newsState.buyPositionId=dealPositionId;
      else if(NewsStopCommentMatches(stopComment,-1)) newsState.sellPositionId=dealPositionId;
      else
      {
         NewsStopSetFault("收到本Magic入场Deal，但comment与当前配对令牌不匹配");
         return;
      }
      NewsHedgeSaveState();
   }
   bool teacherAutoEntryDeal =
      HistoryDealGetString(trans.deal, DEAL_SYMBOL) == _Symbol &&
      (long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == TEACHER_AUTO_SHORT_MAGIC &&
      (dealEntry == DEAL_ENTRY_IN || dealEntry == DEAL_ENTRY_INOUT);
   if(teacherAutoEntryDeal)
      TeacherAutoConfirmEntryDeal(trans.deal, dealPositionId);
   if((dealEntry == DEAL_ENTRY_IN || dealEntry == DEAL_ENTRY_INOUT) &&
      HistoryDealGetString(trans.deal, DEAL_SYMBOL) == _Symbol &&
      MagicInScope((long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC)))
   {
      // 只以已经加入历史的真实入场Deal为准，绝不在下单请求返回时提前冻结模板。
      FreezeConfirmedEntryTemplate(dealPositionId, dealEntry);
   }
   int stateIdx = FindShortStateByPositionIdentifier(dealPositionId);
   if(stateIdx >= 0 && (dealEntry == DEAL_ENTRY_IN || dealEntry == DEAL_ENTRY_INOUT))
      InvalidateEntryCostCache(stateIdx);
   ShortRecordDeal(trans.deal, "OnTradeTransaction");
   TradeJournalWriteDeal(trans.deal, "OnTradeTransaction");
   if(stateIdx >= 0)
   {
      if((dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY) &&
         !SelectPositionForShortState(stateIdx))
         FinalizeFloatingPnlTiming(stateIdx);
      ReconcilePendingTradeAction(stateIdx);
      if(states[stateIdx].pendingAction == 待确认动作_全部平仓 && !PositionSelectByTicket(states[stateIdx].ticket))
      {
         states[stateIdx].lifecyclePhase = 生命周期_等待最终结算;
         MarkShortStateDirty(stateIdx);
      }
   }
   if(newsState.stage == 消息阶段_待命) return;
   bool related = (dealPositionId == newsState.buyPositionId || dealPositionId == newsState.sellPositionId ||
                   dealPositionId == newsState.runnerPositionId || dealPositionId == newsState.loserPositionId ||
                   trans.position == newsState.buyTicket || trans.position == newsState.sellTicket ||
                   trans.position == newsState.runnerTicket || trans.position == newsState.loserTicket ||
                   trans.position == newsState.buyPositionId || trans.position == newsState.sellPositionId ||
                   trans.position == newsState.runnerPositionId || trans.position == newsState.loserPositionId);
   if(!related) return;
   NewsRecordDeal(trans.deal, "OnTradeTransaction");
}

void OnTimer()
{
   PerformanceScope perfScope(PERF_ON_TIMER);
   TeacherActiveRefreshRisk();
   TeacherAutoReconcilePending();
   ShortProcessPendingDeals();
   ShortCheckPartialRequestTimeouts();
   ShortCheckPendingActionTimeouts();
   for(int i=0; i<ArraySize(states); i++) ReconcilePendingTradeAction(i);
   UpdateAllFloatingPnlTimings();
   CleanupStates();
   CleanupConfirmedEntryTemplateStamps();
   FlushAllDirtyShortStates(false);
   TradeJournalWriteSnapshots();
   NewsReconcileStopDeployment();
   NewsTryPendingDeals();
   NewsReconcileRunnerPartial(true);
   NewsManageClock();
   if(NewsHedgeGroupActive())
   {
      NewsHedgeTemplateScope displayScope;
      RefreshMarketStructureCaches(false);
      ManageMobileMarkerOrders(false);
      RefreshPanel(false);
   }
   else
   {
      RefreshMarketStructureCaches(false);
      ManageMobileMarkerOrders(false);
      RefreshPanel(false);
   }
   PerfFlushIfNeeded();
}

void OnDeinit(const int reason)
{
   ReleaseManagedIndicatorHandles();
   if(!teacherAutoStateLoaded)
   {
      if(teacherAutoInstanceFile!=INVALID_HANDLE) { FileClose(teacherAutoInstanceFile); teacherAutoInstanceFile=INVALID_HANDLE; }
      return; // 初始化未取得实例所有权时，不覆盖其他实例持久化状态
   }
   if(teacherActiveATRHandle!=INVALID_HANDLE) { IndicatorRelease(teacherActiveATRHandle); teacherActiveATRHandle=INVALID_HANDLE; }
   if(teacherActiveEMAHandle!=INVALID_HANDLE) { IndicatorRelease(teacherActiveEMAHandle); teacherActiveEMAHandle=INVALID_HANDLE; }
   // 只结算仍可观测的当前短段，不把仍在持有的仓位标记为生命周期结束。
   UpdateAllFloatingPnlTimings();
   for(int i=0; i<ArraySize(states); i++)
      TradeJournalWriteLifecycle(i, "EA_DEINIT", StringFormat("reason=%d", reason));
   FlushAllDirtyShortStates(true);
   TeacherAutoStateSave();
   if(teacherAutoInstanceFile!=INVALID_HANDLE) { FileClose(teacherAutoInstanceFile); teacherAutoInstanceFile=INVALID_HANDLE; }
   if(NewsHedgeGroupActive())
      NewsHedgeSaveState();
   保存当前配置模板();
   保存配置模板输入值(参数配置模板);
   保存配置模板重载原因(reason);
   EventKillTimer();
   DeleteMobileMarkerOrders();
   DeletePanel();
   if(atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(atrHandle);
      atrHandle = INVALID_HANDLE;
   }
}
//+------------------------------------------------------------------+
