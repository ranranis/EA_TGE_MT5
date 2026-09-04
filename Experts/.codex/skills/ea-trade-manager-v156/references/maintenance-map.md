# 维护地图、证据来源与更新协议

证据核对：2026-09-04；本文件记录如何接手当前 v1.56，不把历史文档或副本冒充现行源码。行号会漂移，所以每个定位都同时保留“文件 + 符号/搜索词 + 当前辅助行号”。

## 快速定位表

| 任务 | 先读/先搜 | 当前锚点 |
| --- | --- | --- |
| 管理范围/接管/模板冻结 | 主文件 `PositionInScope`、`EnsureState`、`FreezeConfirmedEntryTemplate` | 2979、3117、3266 |
| 请求/服务器确认 | `SetPendingTradeAction`、`ReconcilePendingTradeAction`、`SubmitManagedPositionModify` | 3345、3409、3504 |
| 分批/全平/清理 | `SubmitManagedPartialClose`、`SubmitManagedFullClose`、`CleanupStates` | 3539、3608、3654 |
| 短线/趋势风险 | `ShortEnsureInitialRiskReady`、`ShortConfirmInitialSL`、`TrendFreezeInitialRiskFromServer`、`ManagePosition` | 3973、3807、3378、8436 |
| 箱体/结构/ATR | `RefreshMarketStructureCaches`、Include `UpdateSupportResistance`、`GetShortLineMicroBoxRange` | 10645；`SupportResistance.mqh:1255`；`ShortBox.mqh:227` |
| 消息状态机 | `ManageNewsHedge`、`NewsHedgeState`、`NewsRecordDeal`、`NewsExecuteRunnerPartial` | 8092、1637、7243、7803 |
| 手机标记 | `ManageMobileMarkerOrders`、`SyncOneMobileMarker`、`DeleteMobileMarkerOrders` | 11773、11645、11323 |
| 老师自动反转 | `ManageTeacherAutoReversal`、`SubmitTeacherAutoReversal`、`TeacherAutoReconcilePending` | 12454、12397、12036 |
| 持久化/总结 | Include `ShortStateSave/Load/RestoreAll/Delete`、`FinalizeTradeLifecycle` | `StateStore.mqh:121/266/516/503`；`TradeSummary.mqh:15` |
| 统计/CSV/UI/事件 | Include `TradeJournal*`/`LifecycleStatistics`；主 `RefreshCanvasPanelByDirtyFlags`、`OnChartEvent`、事件入口 | `TradeJournal.mqh:65/92/158`；16655、18986、17858-19534 |

## 接手任何修改的最小流程

1. 先读项目根 `AGENTS.md`、本 Skill 入口和本表对应的 reference；再读直接 Include 的实现，而不是只读面板或旧架构说明。
2. 记录当前正式主文件和直接 Include 的 `git status`、修改时间/哈希；识别用户未提交资产，不覆盖、不格式化无关源码。
3. 搜索 input、enum、全局状态、`TicketState`/`NewsHedgeState`、初始化/保存/恢复/删除、四个事件入口、管理入口、请求、确认、清理、CSV 和图表对象，画出实际调用链。
4. 将需求分类为普通解释/只读审查/低风险显示修改/高风险交易修改。任何会改变真实订单、SL/TP、分批、退出、Deal 归属、账户模式或重启语义的任务，都先给用户最小方案并等待明确确认。
5. 只由一个执行者写同一主文件/状态链；最小范围修改；新增字段走完整生命周期。实现后先做执行者自检，再按用户要求和项目流程编译；不自动提交、推送、合并或启动 MT5。

## 领域更新规则

- 主调用链、模板、事件、状态归属或直接 Include 变化：更新 `architecture.md`，并检查 `trade-lifecycle.md`。
- 请求、retcode、pending、超时、Deal、部分成交、全平、账户模式或结算变化：更新 `trade-lifecycle.md`；涉及字段/版本同时更新 `persistence.md`。
- 初始 SL/R、保本、分批、回撤、追踪、箱体、结构、ATR、Tick/Volume/Stops 变化：更新 `risk-management.md`；若影响消息/手机标记也更新对应 reference。
- 消息阶段、拆锁、runner、组合盈亏、pending Deal 或 `NewsHedgeState` 变化：更新 `news-hedge.md` 与 `persistence.md`。
- 手机真实订单、Magic/comment、撤挂顺序、老师文本或自动反转变化：更新 `mobile-markers.md`；不要把自动反转混写成普通标记。
- Global Variables 键、schema、旧版恢复、清理或 Summary 变化：更新 `persistence.md`，在架构 reference 标出版本事实。
- Canvas、按钮、图表对象、CSV、统计、缓存或性能路径变化：更新 `ui-observability.md`；按钮若发交易请求，还必须回看 `trade-lifecycle.md`。

不要写冗长 changelog。只在受影响 reference 的证据栏更新核对日期/源码版本、变更符号和状态；发现旧文档与源码冲突时注明冲突和源码值，例如当前短线 `V=9` 覆盖旧文档 `V=8`。

## 当前已知问题和待办边界

下列事实来自当前源码/项目资料，只记录，不在普通维护任务中顺手修复：

1. `docs/tasks/pending/TASK-001-news-runner-partial-confirmation.md`：`NewsExecuteRunnerPartial` 可能在真实成交量确认前推进阶段，ResultDeal 不可读时写估算 runner 利润；需要单独高风险专项审查。
2. `NewsApplyEmergencySL`、`NewsModifyRunnerSL` 直接使用 `manageTrade.PositionModify`，未完全复用逐仓统一 pending/超时链。
3. 手机标记撤单没有统一持久化 pending/重启核对；GTC 在 EA 停止、断线或崩溃后可能继续存在，旧单仍在时的替代创建需要服务器级核对。
4. 消息 live 识别仍有按 ticket 的路径；需专项确认 identifier 重绑、乱序、延迟 Deal 和跨重启去重。
5. `NormalizePrice` 当前只按 Digits，通用交易路径未统一显式 Tick Size 对齐；老师点位有独立 tick-size 辅助。该风险已见 TASK-004 资料。
6. 消息 pending Deal 队列容量固定；队列满时记录错误，不能假定无限延迟补录。
7. Global Variables 以 double 存值；老师自动 ulong 已拆分，但短线 ticket/position identifier 的理论精度边界仍存在。
8. 未完成真实 MT5/券商验证：Hedging/Netting、部分成交、断线/重启、GTC 残单、手机端显示、Canvas 视觉和按钮点击都必须由用户最终检查。

已完成任务文档中与地图相关的事实包括 TASK-003 统计时间显示、TASK-004 趋势初始 R/保护、TASK-005 老师点位短线 SLTP、TASK-006 老师自动反转和 TASK-007 五日结构/M5 过滤；它们描述历史修改/验收边界，不取代当前源码。`docs/CODEX_HANDOFF.md`、`docs/CODEX_MQL5_WORKFLOW.md` 和 `docs/test-scenarios/regression-matrix.md` 是维护流程与回归场景入口。

## 外部研究记录

本次地图核对参考了官方 MQL5 文档，未发送账户、订单、私有日志或其他秘密：

- [Position Properties](https://www.mql5.com/en/docs/constants/tradingconstants/positionproperties)：`POSITION_IDENTIFIER` 是生命周期身份，ticket 是当前访问句柄的依据。
- [Deal Properties](https://www.mql5.com/en/docs/constants/tradingconstants/dealproperties)：`DEAL_POSITION_ID`、`DEAL_ENTRY`、费用字段用于归属、入/出/反转和净额核对。
- [OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction)：交易事件可能异步/乱序，不能把单次回调当最终状态。
- [CTrade::PositionModify](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionmodify)、[PositionClosePartial](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionclosepartial)、[PositionClose](https://www.mql5.com/en/docs/standardlibrary/tradeclasses/ctrade/ctradepositionclose)：返回值/retcode 需要结合服务器实际 Position/Deal 确认。
- [Account properties](https://www.mql5.com/en/docs/constants/environment_state/accountinformation)：Hedging/Netting 账户模式决定同时多空和部分关闭请求的实现。

适用结论与本地代码一致，但官方文档不证明本 EA 的每条路径已经在当前券商运行；仍需区分源码事实、服务器接受、真实成交和用户最终验收。

## 本次文档任务的验证边界

本 Skill 创建任务只新增本目录 Markdown 资源，之后运行 `skill-creator/scripts/quick_validate.py` 检查 frontmatter/命名/未完成脚手架，并用文件清单、源码哈希/时间和 Git 状态检查范围。没有编译、启动 MT5、加载 EA、点击面板、截图、模拟订单、真实开仓/平仓或手机端验证。
