# v1.56 全范围静态审查（2026-09-15）

后续修复状态：用户授权的下列5项现已在源码修复并加入专项离线回归；下文“未修复”为审查时历史记录。V7保存趋势R、恢复武装和老师计划，旧档缺字段保守保留未知；快保要求正SL；历史先快照ticket；Summary入出量及写入确认；标记撤单跨重启等待历史最终状态再允许替代。既有坏Summary、旧导入标记与旧版本没保存的数据不自动重写/补猜。中风险项不在这5项修复范围内。编译/离线验证不等于券商实盘验收。

范围：正式主文件及递归项目Include，共14个文件、约2.55万行。完成文件/函数索引、六个事件入口的静态调用可达性扫描，以及输入、持仓、交易请求/确认、恢复、消息、手机标记、统计、Canvas关键路径检查。静态调用图不是逐语句形式化证明；未做MT5回测、实时延迟或实盘验证。

## 已修改

- 主文件第17组 `启用老师点位自动反转短线=true`。只改变源码默认值，不覆盖已有set/图表保存参数，不开启MT5全局或实例交易权限。仍需有效老师点位、Hedging账户、新M1信号、风控和权限放行；默认老师文本为空时不会凭空产生老师信号。
- `Include/Trading/TeacherAuto.mqh` 与 `Include/UI/CanvasPanel.mqh` 从主文件原位提取，保留文本和调用顺序；仍依赖主文件类型、输入和全局状态，不宣称完全解耦或仅凭拆文件提速。
- `ClassifySRTradingIntent` 同次分类按需共享完整四根已收M1；不足四根时继续重试，不跨调用缓存，不改变评分/反应公式。

## 高风险：未修复，建议实盘更新前专项处理

1. **恢复字段缺失。** 主文件 `EnsureState` 初始化 `trendRiskReady/trendInitialRisk/trendInitialSL`、`recoveryArmed`及老师TP冻结计划；`Include/Persistence/StateStore.mqh::ShortStateSave/Load` 未保存这些字段。趋势SL已越过入场价后重启，原始R无法重新从风险侧SL获得；老师计划和恢复资格也可能丢失。最小修复：补齐保存/加载/删除与旧版本缺键策略，不能从当前盈利SL猜初始R。涉及恢复语义，未随结构重构修改。
2. **空头快保可误确认SL=0。** 主文件 `ReconcilePendingTradeAction` 的 `pendingFastProtection` 分支覆盖 `slConfirmed`，空头判断仅为 `actualSL <= target+tolerance`，`fastConfirmed`也缺少正SL条件。TP满足时零SL可能被当作已保护并清pending。最小修复：要求服务器实际SL和目标均为有效正价格，保留现有方向/容差检查。
3. **历史循环被回调破坏。** `ShortCheckPartialRequestTimeouts`、`ShortCheckPendingActionTimeouts` 遍历 `HistorySelectByPosition` 结果时调用 `ShortRecordDeal`，后者调用 `HistoryDealSelect`；`TradeJournalImportAvailableHistory`亦通过 `TradeJournalWriteDeal`发生同类问题。选中单条Deal会清除原Deal列表，导致漏处理后续成交。最小修复：先捕获待处理ticket列表，再调用会改变历史选择的处理函数；导入完成标记还需对应实际写入成功。[官方语义](https://www.mql5.com/en/docs/trading/historydealselect)。
4. **最终结算可能早于完整退出历史。** `Include/Journal/TradeSummary.mqh::FinalizeTradeLifecycle` 只要求entryVolume/exitVolume为正且存在lastExit，没有核对退出量是否覆盖入场量；`CleanupStates`随后删状态。如果仓位已消失而最后部分Deal尚未可读，可能把不完整结果永久结算。最小修复：按生命周期分段和手数步长确认完整退出，再写Summary和删除状态；写入返回值也应检查。
5. **自动R/S手机标记撤旧后直接建新。** 主文件 `SyncOneMobileMarker` 调用 `DeleteMobileMarkerOrders` 后继续创建替代单，没有要求旧单已实际撤销；删除函数不检查结果。断线、拒绝或延迟时可能重复标记单。最小修复：独立撤单确认后才创建替代，保留危险距离和Magic隔离。

## 中风险与性能边界

- `CleanupStates`位于Tick开头；待结算失败会每Tick重查历史/日志。宜拆为轻量仓位消失检测与Timer结算，但必须先修完整结算和保留生命周期身份。
- Timer、ChartEvent仍与交易共享EA事件线程。统计缓存失效可扫描90天Deal和CSV；把工作移到Timer并不等于后台并行，也不是硬实时保证。
- `ShortRecordDeal` 的分批归属依赖position id和当前pending阶段，没有完整核对请求order/时间，外部减仓并发可能影响阶段；重启运行期Deal去重集合清空，需要专项补录审查。
- 普通请求和消息部分请求对TIMEOUT/CONNECTION等结果不明的保护不如老师积极模式完整；不可直接全局开启异步模式。
- 通用 `NormalizePrice`仅按Digits，而非Tick Size；特定品种网格不一致时可能拒单。属于价格执行语义，未本轮改变。
- 配置恢复按ChartID和卸载原因决定；重加EA/旧set可覆盖源码默认。默认自动策略与面板“下一单模板”是不同设置，未强制改用户模板。

## 源码优先于旧地图

当前消息状态写VER7，已有 `NewsReconcileRunnerPartial` 同时按真实Deal退出量和剩余仓量确认。旧技能文档关于runner直接提前推进的描述已过时，不能照搬为当前缺陷。当前还存在用户按钮触发的双Stop部署，不是仅手动多空配对。短线StateStore实际为V6，不能套用旧V9文档声称字段已持久化。

## 验证与建议顺序

模块原文展开对照、默认值及权限门禁检查、SR完整/缺失历史读取次数和反应检查、原性能对照与老师交易离线测试；另用MetaEditor隔离编译。均不能替代券商成交、重启、视觉及延迟验证。

建议顺序：空头快保确认 → 状态恢复 → 历史补录/完整结算 → 手机撤挂确认 → 在模拟盘测量事件耗时，再进一步拆分统计和结算调度。本轮不自动加载、下单或替换正在运行的EX5。
