# v1.56 架构与主调用链

证据核对：2026-09-04；正式源码 `EA_交易托管系统_v1.56.mq5`，约 19,535 行。以下行号只是当前辅助锚点；优先使用相对路径、符号和搜索词。旧版、`.bak`、`Backups/`、`_backups/`、`_release/` 不属于正式实现。

## 正式文件边界

主文件在项目根：

`EA_交易托管系统_v1.56.mq5`

它直接引用的项目 Include（源码搜索 `#include "Include/`，约 1414-1418、1855-1859）：

| 文件 | 维护职责 | 主要锚点 |
| --- | --- | --- |
| `Include/Core/Performance.mqh` | `PerformanceMetric`、`PerformanceScope`、计数器和定时输出 | `PerformanceMetric` 4-18，`PerfFlushIfNeeded` |
| `Include/Core/SymbolUtils.mqh` | M1/M5 新 K 标志 `IsNewBar` | `IsNewBar` 9 |
| `Include/Journal/LogUtils.mqh` | `AllowRateLimitedLog`、`PrintRateLimited`，限制高频日志 | 13、55 |
| `Include/Market/ATRCache.mqh` | 以已收 M1 柱缓存 `GetATRPrice` | 9-30 |
| `Include/Market/SupportResistance.mqh` | `SRLevel`、多周期支撑压力聚合、趋势和可视化对象 | `UpdateSupportResistance` 1255；`DetectTrendRegimeM5` 857 |
| `Include/Market/ShortBox.mqh` | 短线箱体资格、箱体 SL/TP、微型箱体和旧箱体对象清理 | `ShortLineBoxTPPrice` 98，`ShortLineBoxSLPrice` 128，`GetShortLineMicroBoxRange` 227 |
| `Include/Persistence/StateStore.mqh` | `TicketState` 的 Global Variables 保存、恢复、删除和重启对账 | `ShortStateSave` 121，`ShortStateLoad` 266，`ShortStateRestoreAll` 516 |
| `Include/Journal/TradeJournal.mqh` | `TradeDeals`、`TradeLifecycle` CSV 和历史导入 | `TradeJournalWriteDeal` 65，`TradeJournalWriteLifecycle` 92 |
| `Include/Journal/TradeSummary.mqh` | 仓位消失后的完整生命周期汇总与最终结算 | `FinalizeTradeLifecycle` 15 |
| `Include/Journal/LifecycleStatistics.mqh` | 按完整 `positionIdentifier` 生命周期聚合统计/走势/复盘 | `CalculateLifecycleStatsByBJRange` 752，`GetCurrentLifecycleStats` 1117 |

主文件顶部的三个交易对象（12-14）职责隔离：`manageTrade` 管现有托管仓位，`markerTrade` 管手机提示挂单/异常成交后的标记仓位，`teacherAutoTrade` 只管老师点位自动反转，并使用独立 `TEACHER_AUTO_SHORT_MAGIC`。不要把 `markerTrade` 或 `teacherAutoTrade` 的 Magic 设到管理对象上。

## 类型、模板和状态所有权

- 输入/enum 大致位于 23-1171。重要 enum：`距离模式`、面板页面/模式/密度、统计周期/筛选/详情、`追踪SL模式`（75-81）、`管理配置模板`（83-90）、`消息对冲阶段`（92-102）、高点差处理模式及老师点位辅助模式。
- `管理配置模板` 的四个正式值是自定义、黄金超短快保、黄金稳健托管、黄金支压止盈、黄金消息对冲。当前参数模板是“下一单/当前显示”的配置；真实入场 Deal 通过 `FreezeConfirmedEntryTemplate` 冻结 `TicketState.adoptedTemplate`，进行中的仓位不能因面板切换改管法。
- `TicketState`（主文件 1460-1584，搜索 `struct TicketState`）以 `ticket` + `positionIdentifier` 记录身份，并分组保存：开仓时间/方向/冻结模板、价格/资金峰谷、恢复武装、初始量、短线/趋势风险 R、老师计划、分批、runner、SL/TP 来源、pending 请求、外部变化、Netting 反转、生命周期阶段、浮盈/浮亏计时、dirty/保存版本。
- `NewsHedgeState`（1637-1730，搜索 `struct NewsHedgeState`）独立维护消息组合的阶段、买卖/runner/loser 的 ticket 和 position id、箱体、拆锁、灾难 SL、实际成本、部分退出和 pending Deal。
- `ShortLineMarketContext`（1782-1854）是短线结构/趋势/波动/箱体的候选上下文；它不等同于服务器确认状态。
- `ConfirmedEntryTemplateStamp`、模板结构缓存和 `states[]` 位于状态区。结构缓存按模板保存/加载，避免持仓循环中反复重算并防止当前面板模板覆盖已冻结模板。

## 事件级调用链

```text
OnInit
  -> 读取配置/面板持久化，清理旧短线对象
  -> NewsHedgeLoadState / ATR handle / 三个 CTrade 配置
  -> Canvas 初始化、老师缓存和自动反转恢复
  -> ShortStateRestoreAll + ReconcilePendingTradeAction
  -> 历史 Deal 导入、EventSetTimer(1)、结构缓存、手机标记、RefreshPanel

OnTick
  -> M1/M5 新 K 标志、短线快价、CleanupStates
  -> 辅助管理开关闸门
  -> 消息模板或已存在消息组合：结构/微 tick -> ManageNewsHedge -> 标记/UI
  -> 普通高点差：只跑 ShortEmergencyRiskManagement，暂停普通细节
  -> 普通结构缓存/ATR -> 遍历 PositionsTotal -> ManagePosition
  -> 恢复显示缓存 -> ManageTeacherAutoReversal -> 手机标记 -> UI

OnTradeTransaction
  -> REQUEST 只记 request/result；POSITION 触发 pending 对账
  -> DEAL_ADD 使统计/Canvas 数据失效，读取 DEAL_POSITION_ID
  -> 入场 Deal 冻结模板，短线 Deal/CSV/生命周期结算，消息 Deal 记账
  -> HistoryDeal 暂不可读时入队，后续由 Timer 补录

OnTimer
  -> 老师 pending、短线 pending Deal/partial/动作超时和逐仓对账
  -> 浮盈时间、状态清理、dirty 状态落盘、周期快照
  -> 消息 pending Deal/时钟、结构/手机标记/UI、性能输出

OnChartEvent -> Canvas/旧面板交互；部分按钮会发真实平仓、消息动作或手机标记撤/同步请求
OnDeinit -> 浮盈观测/日志、强制落盘、老师/消息状态保存、杀定时器、撤标记、删面板、释放 ATR
```

锚点：`OnInit` 17858、`OnTick` 17906、`OnTradeTransaction` 19381、`OnTimer` 19482、`OnDeinit` 19513；`OnChartEvent` 18986。调用链需以当前函数体复查，不要只根据上图推断交易结果。

## 允许和禁止的能力

已实现的默认定位是接管已有仓位并提供保护、统计和显示。手机标记真实 pending order 是既有例外；老师点位自动反转（`ManageTeacherAutoReversal` 12454）是另一个已存在但默认关闭的主动开仓入口，不能在普通维护中扩展或启用。`ManageNewsHedge` 8092 只在手动等手数多空已经存在/被识别后进入配对状态，不应被改成预先双向开仓。

已实现的显示/逻辑边界：Canvas 以 `PanelViewModel` 供 `CPanelRenderer` 渲染，不能以视觉状态替代 `TicketState`、News 状态或服务器读数；但 `OnChartEvent` 的按钮确实可能触发真实动作，UI 修改也要按交易改动审查。

未验证边界：本地图谱没有替代 MT5 实机的 Hedging/Netting、断线、异步/部分成交、重启、手机端或视觉验收；“已实现”只表示源码存在相应路径，不表示服务器环境已验证。
