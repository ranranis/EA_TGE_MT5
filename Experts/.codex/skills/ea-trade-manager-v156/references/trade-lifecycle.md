# 交易生命周期、请求确认与结算

证据核对：2026-09-04；正式源码 `EA_交易托管系统_v1.56.mq5`。行号是辅助锚点，定位时同时搜索函数名。这里的“已实现”描述源码路径，不等于已在真实券商环境验收。

## 身份和管理范围

1. `PositionInScope`（主文件 2979，搜索 `PositionInScope()`）先按当前 `_Symbol`、Magic/手动单设置和多空开关判断管理范围；`MagicInScope`（3046）用于 Deal/统计范围。手机标记 Magic 不应流入普通托管。
2. `EnsureState`（3117）在首次看到受管仓位时建立 `TicketState`，从服务器读取当前 ticket、`POSITION_IDENTIFIER`、开仓时间、方向、初始量、服务器 SL/TP 和运行期默认值，然后调用 `ShortStateLoad`。`FindState`（3067）按当前 ticket 找的是访问项；`FindShortStateByPositionIdentifier`（18017）才是生命周期归属锚。
3. `SelectPositionForShortState`（18024）先尝试保存的 ticket，再遍历当前仓位匹配 `POSITION_IDENTIFIER`，用于 ticket 切换/重绑。`FindOpenPositionTicketByIdentifier`（3253）为入场 Deal 和老师自动单找当前访问 ticket。
4. `FreezeConfirmedEntryTemplate`（3266）只有真实入场 `DEAL_ENTRY_IN`/`INOUT` 且历史 Deal 可读时才把模板写入状态；Netting `INOUT` 会重置需要重新确认的生命周期字段。面板切换不应改变已有仓位的 `adoptedTemplate`。

## 四阶段不变量

每个动作都要能指出当前阶段：

```text
候选值/意图
  -> CTrade 或 OrderSend 请求
  -> retcode/request_id/order/deal 的服务器受理记录
  -> POSITION_SL/TP/volume 消失或真实 DEAL 的最终确认
```

`CTrade` bool、`ResultRetcode()` 的受理类值、返回的 order/deal ticket 都不能单独推进“已保护、已分批、已平仓、已撤 TP”状态。计算函数只产生候选值；请求函数写 pending；事件/轮询读取服务器再清 pending。

## SL/TP 修改请求

- `SetPendingTradeAction`/`ClearPendingTradeAction`（3324、3345）保存动作类型、目标 SL/TP、来源、退出意图、请求时间和结果句柄。
- `SubmitManagedPositionModify`（3504）先重读当前仓位，调用 `manageTrade.PositionModify`，记录 retcode/comment/order/deal；受理后设置 `待确认动作_SLTP修改`、`快速保护` 或 `撤销固定TP`，随后由 `ReconcilePendingTradeAction`（3409）读 `POSITION_SL/TP`，按 tick/point 容差和方向判断服务器是否达到目标。
- 对保护性 SL，`ReconcilePendingTradeAction` 只有实际 SL 到位才更新 `lastConfirmedSLSource`、`protectionStage`、快保已确认和初始风险冻结；TP 撤销只有实际 `POSITION_TP` 接近 0 才确认撤销。请求失败只记失败日志，不写完成状态。
- `ShortCheckPendingActionTimeouts`（18261）和 `ShortCheckPartialRequestTimeouts`（18202）在 `OnTimer` 处理超时；超时会对账、解除锁或按剩余量有限重试，不能无条件重发。
- 当前路径仍需要逐调用方检查：消息 `NewsApplyEmergencySL`（6912）和 `NewsModifyRunnerSL`（7675）直接使用 `manageTrade.PositionModify`，没有完全复用短线统一 pending 链。不要把“消息函数读回了 SL”泛化为所有请求已具有同等超时/重启语义。

## 分批平仓和部分成交

`SubmitManagedPartialClose`（3539）有账户模式分支：

- Hedging 使用 `manageTrade.PositionClosePartial(ticket, closeVolume)`。
- Netting 使用反向 `TRADE_ACTION_DEAL`，设置 `request.position=ticket`、当前品种、原仓 Magic、反向订单类型和按 `SYMBOL_FILLING_MODE` 选择的 filling；代码注释明确要求仓位消失时拒绝，不能意外反向开仓。

请求受理后保存 `partialRequestPending`、阶段、请求量、开始量、已填量、时间、result order/deal，并等待 `DEAL_ENTRY_OUT`/`OUT_BY`/`INOUT` 的真实成交累计。`ShortRecordDeal`（18056）按 `DEAL_POSITION_ID` 找状态，处理费用和已实现净额，运行期用 processed Deal ticket 去重；超时路径按 `HistorySelectByPosition(positionIdentifier)` 补录。

短线两段分批入口在 `ExecuteShortLineMultiStagePartial`/`ExecutePartialTakeProfit`（约 5740-5990），第二段在剩余手数不足时可以转为全平请求。阶段字段只能在真实 Deal/真实剩余量条件下推进；不要用“请求发送成功”直接把 `partialTPDone` 当作成交。

已知专门风险：消息 runner 的 `NewsExecuteRunnerPartial`（7803-7848）目前在 `PositionClosePartial` 返回 true 后推进阶段；若 `ResultDeal()` 不可读则先按浮盈比例写入估算利润。该事实已记录在 `docs/tasks/pending/TASK-001-news-runner-partial-confirmation.md`，不得在其他任务中顺手修复或淡化。

## 全平、仓位消失和最终结算

- `SubmitManagedFullClose`（3608）拒绝已有全平 pending，记录被抢占的动作，清理被全平抢占的 partial pending，设置 `生命周期_退出请求中` 与 `待确认动作_全部平仓`，但仍要等真实退出 Deal/仓位消失。
- `OnTradeTransaction`（19381）收到 `TRADE_TRANSACTION_DEAL_ADD` 后调用 `ShortRecordDeal`、`TradeJournalWriteDeal` 和 pending 对账；退出后仓位不可见时将生命周期转为 `生命周期_等待最终结算`。
- `CleanupStates`（3654）发现 `SelectPositionForShortState` 失败后先记录 `POSITION_CLOSE_DETECTED`，调用 `FinalizeTradeLifecycle`；只有 `TradeSummary` 写入/已存在完整 Summary 后才 `ShortStateDelete(positionIdentifier)` 并从数组移除。`FinalizeTradeLifecycle`（`Include/Journal/TradeSummary.mqh:15`）用 `HistorySelectByPosition` 聚合 entry/exit、费用、净额、R 和峰谷，避免仓位刚消失就删状态。
- 退出 Deal 的 Magic 不能独立证明归属；必须结合 `DEAL_POSITION_ID`、保存的 position identifier、symbol 和生命周期分段。`DEAL_ENTRY_INOUT` 可能同时改变净额仓位方向，不能机械解释为旧仓完整退出。

## 事件、队列和恢复

- `OnTradeTransaction` 对 `TRADE_TRANSACTION_REQUEST` 只写 request/result；对 `TRADE_TRANSACTION_POSITION` 触发 `ReconcilePendingTradeAction`；对 `DEAL_ADD` 先尝试 `HistoryDealSelect`，不可读时把 Deal 放入短线/消息 pending 队列。
- `OnTimer` 顺序包含 `ShortProcessPendingDeals`、两个超时检查、逐状态对账、`NewsTryPendingDeals`、`NewsManageClock`。因此延迟 Deal 可能在交易事件之后由定时器补录；不要假定单一事件顺序。
- `OnInit` 执行 `ShortStateRestoreAll`、逐状态 pending 对账、`TeacherAutoReconcilePending`、`NewsHedgeLoadState`；`OnDeinit` 只强制落盘和清理对象，不应把仍持有的仓位标记为完成。
- `ShortReconcilePositionShape`（3830）检测外部加仓、减仓、均价/方向变化；外部组合变化会让 R 重新变为未知、清理不应继承的分批/恢复状态，并记录生命周期分段。真实 Netting 反转需要单独审查。

## 状态分类

- 已实现：短线统一 SL/TP、分批、全平动作有 pending 字段、retcode 日志、`POSITION_*`/Deal 对账、超时和重启落盘路径；普通短线 Deal 处理优先 identifier。
- 部分实现/逐调用方审查：消息紧急 SL、runner SL 和消息 runner 分批没有完全复用统一 pending；运行期 processed Deal 集合不跨重启，跨重启重复边界需通过历史/日志验证。
- 已知待办：`TASK-001-news-runner-partial-confirmation.md` 的 runner 部分成交确认专项；不要把其“源码行为已确认”误写成“真实后果已实盘确认”。
- 未验证推测：不同券商 filling、异步/部分成交、Hedging ticket 切换、Netting `INOUT`、断线和立即重启的事件序列未在本地图谱中实测。
