# 消息对冲状态机

证据核对：2026-09-04；正式源码 `EA_交易托管系统_v1.56.mq5` 的 enum 92-102、状态 1637-1730、消息实现 6070-8434。消息模块是现有手动等手数多空的高风险托管路径，不得被改成新的主动双向开仓策略。

## 入口和配对边界

`ManageNewsHedge`（8092）仅在当前下一单模板是 `配置_黄金消息对冲` 或已存在活动消息组合时运行；先要求 `IsHedgingAccount()`，非零售 Hedging 账户直接显示禁用，因为 Netting 不能同时保留多空两腿。

`NewsFindPairCandidates`（6398）遍历当前 `_Symbol` 的仓位，`NewsPositionEligibleSelected`（6379）按消息可管理身份、Magic/comment 和当前品种过滤，统计 BUY/SELL 数量。系统不会为消息模板自动预建一多一空：用户/已有交易先形成候选，`NewsEstablishPair`（7075）才把两腿真实 ticket、`POSITION_IDENTIFIER`、开仓价和配对时间写入状态。

待命期的安全行为已经在代码中固定：手数/时间不匹配、多于一组或同向多单只告警并保留用户处置权；单边孤立仓在 `消息对冲配对等待秒` 超时且 `消息对冲配对失败自动平仓` 开启时可以请求关闭。这是已有“孤立仓保护”行为，不是授权新增主动开仓。

## 阶段和转移

`消息对冲阶段`（92-102）阶段顺序：

```text
待命
  -> 配对安全                 NewsEstablishPair
  -> 箱体冻结                 NewsFreezeBoxByUser（6828）
  -> 释放窗口                 NewsEnableRelease（6875）
  -> 拆锁中                   NewsBeginUnhedge（7409）
  -> 冲击持仓 -> 延续持仓     NewsContinueUnhedge（7451）/ ManageNewsRunner
  -> 组合退出                 NewsRequestGroupExit（6819）/ NewsCloseAll
```

- 配对安全：只保留配对，反复更新/校验候选箱体和两腿灾难 SL；禁止拆锁。
- 箱体冻结：用户确认有效 M1 箱体后冻结 range、宽度、触碰/中轴穿越/箱内收盘比例和缓冲；仍不开放方向。
- 释放窗口：`NewsEnableRelease` 写入开始/到期时间，价格只能在窗口和箱体过滤允许时等待突破确认。
- 拆锁中：根据确认的向上/向下方向选择 runner 和 loser；先落盘再请求 loser 平仓，防止成交瞬间重启丢组合成本。
- 冲击/延续持仓：只有盈利边 runner 存活时运行微回踩、结构 SL、组合浮盈/回撤、R 分批和最长持仓时限。
- 组合退出：所有退出都要经过请求、实际 Deal/仓位确认和重试；有效报价不可用时保留状态等待定时器，而不是假定已平。

## 箱体、点差和突破

`NewsBuildFrozenBox`（6540）只从已收 M1（`CopyRates(..., 1, bars, ...)`）构造高低簇，按触碰次数、中轴穿越、箱内收盘比例、ATR 宽度、当前中价位置等拒绝无效候选。`NewsCalculateFrozenBuffers`（6716）把正常点差、ATR、箱体宽度和 broker 最小距离合成为初始/突破/失败/灾难缓冲，并计算两腿灾难 SL。

释放窗口里 `NewsBreakoutConfirmed`（7112）需要连续确认 tick 和确认毫秒；点差超过 `NewsDynamicSpreadLimit`（7148）时先等待有限毫秒，按 `高点差超时处理_整组退出` 或在仍满足最晚拆锁/剩余 R/R 条件时强制拆锁。`NewsUnlockTooLate`（7330）和 `NewsActualUnlockTooLate`（7203）会拒绝过晚或已过度延伸的拆锁，转入组合退出。所有突破/箱体确认都不能使用第 0 根 K 线。

## loser、runner 和组合盈亏

`NewsBeginUnhedge` 以真实方向选择 `runnerTicket/runnerPositionId` 与 `loserTicket/loserPositionId`；`NewsContinueUnhedge` 先请求关闭仍存在的 loser，Deal 暂不可读时入队。loser 的实际净额来自 `DEAL_PROFIT + DEAL_COMMISSION + DEAL_SWAP + DEAL_FEE`，若尚未知晓才保留 `pendingLoserLossMoney` 估算。

`NewsTryPrepareRunnerRisk`（7736 附近）在 loser 实际关闭且 runner 存活、箱体结构 SL 真实到位后才准备组合 R；`NewsEstimateInitialGroupRiskMoney`（7349）把 loser 实际净额、runner 在实际 SL 的结果和剩余退出成本纳入初始组合风险。`NewsRunnerCombinedMoney`（7523）合并 loser、runner 已实现、runner 浮盈和剩余成本；组合回撤/成本/最长持仓由 `ManageNewsRunner` 和 `NewsManageClock` 共同处理。

runner 的两个阶段分批由 `NewsExecuteRunnerPartial`（7803-7848）发起，手数按最小/step 和保留余量校验。已知风险：当前代码在 `PositionClosePartial` 返回 true 后立即写阶段，并尝试用 `ResultDeal()` 记账；ResultDeal 不可读时先写浮盈比例估算。若发生真实部分成交、延迟 Deal、重启或多 Deal，内部阶段/利润可能暂时领先服务器。此问题已在 `docs/tasks/pending/TASK-001-news-runner-partial-confirmation.md` 建档，除专项任务和用户确认外不得修改。

## SL、全平和确认边界

- `NewsApplyEmergencySL`（6912）在配对/待命异常/箱体无效等阶段给单腿灾难 SL；`NewsMaintainPairStructureSL`（6757）维护两腿结构 SL/撤 TP。两者使用 `manageTrade.PositionModify`，虽会读当前值和 `SLTPValid`，但没有完整复用 `SetPendingTradeAction`/统一 timeout 链。
- `NewsModifyRunnerSL`（7675）和 `NewsEnsureRunnerBoxProtection`（7687）对 runner 只允许更保护的 SL，并立即重新读取当前 SL 判断结构保护；仍需注意它们没有独立持久化 pending action。
- `NewsCloseTicket`（6928）/`NewsCloseAll`（6967）必须保留消息身份闸门；组合退出会保存阶段和原因，再按有效报价请求两腿关闭。`NewsRecordDeal`（7243）只接受当前品种的 `OUT`、`OUT_BY`、`INOUT`，优先用 `DEAL_POSITION_ID` 区分 loser/runner，并用 last deal 字段避免重复。
- `NewsTryPendingDeals`（7369）在 Timer 中补录 HistoryDeal 暂不可读的退出；队列容量由 `NEWS_PENDING_DEAL_CAPACITY` 固定，满队列会记录错误，不能假定无限补录。

## 持久化和已知风险

`NewsHedgeState` 同时保存买/卖/runner/loser 两种身份、阶段、箱体/缓冲、拆锁时点、实际/估算成本、runner 极值、微回踩、分批阶段和待补录 Deal。`NewsHedgeSaveState`（6090）写 `SMA_NH_<login>_<symbol>_<field>`，当前源码版本为 `VER=5`；`NewsHedgeLoadState`（6204）支持旧状态重建，并在 `OnInit` 早于普通面板模板恢复，避免面板切换中断组合风控。

状态标签：

- 已实现：Hedging 账户闸门；等手数/时间配对；已收 M1 箱体；冻结/开放/拆锁/runner/组合退出阶段；灾难 SL、最晚拆锁、点差和组合亏损保护；`DEAL_POSITION_ID` 归属；pending Deal 队列；状态保存/恢复。
- 部分实现/已知风险：消息紧急 SL、runner SL 的服务器确认链比普通短线简化；runner 分批确认是 `TASK-001`；消息 live 检查仍有按 ticket 的路径，需要专项确认 identifier 重绑、Netting/反转不适用性和乱序事件。
- 未验证推测：真实高点差、部分成交、多 Deal、断线、EA 重启时的组合状态时序和实际 broker 费用尚未通过运行日志证明。
