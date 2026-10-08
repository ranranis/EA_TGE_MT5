# 风险、SL/TP、R、分批与结构保护

2026-09-15 五项修复：`ReconcilePendingTradeAction`排除零/负/非有限SL和快保目标，避免空头误确认；趋势原始R/老师计划/回本武装新增V7持久化。旧档缺原始R设置`trendRiskUnknown`阻止从已移动SL重新冻结；不改变当前服务器SL，不以新文本替换旧老师计划。完整退出和撤挂确认同步修复，见生命周期与持久化地图。

2026-09-15 性能修订：`TrendLongMA/ATR/ADX` 和 `DetectTrendRegimeM5` 通过 `IndicatorHandles.mqh` 复用指标资源；仍按原buffer/shift读取，不缓存候选SL、实时价格或服务器状态。价格密集区索引改造保留候选计数、价格及同分顺序，离线1000组及边界对照通过。没有修改输入阈值、仓位管理调用或请求确认链；运行期响应和策略等价仍需MT5回测验证。

2026-09-13 贪婪多仓修订（取代下段首版相关数值）：积极单统一使用17组固定手数默认0.01，不再按0.35%/0.175%计算，后两项仅兼容旧set。持仓最多5笔、日内停机不变。初始SL及净RR门槛不放宽，初始目标上限3R改5R，但仍截在最近有效障碍前，区间模式另受对侧边界限制。`ManageTeacherActivePosition` 默认2.5R才请求半仓、1.5R以后结构支持才保本；最小量无法分批时不强制全平，继续整仓跟踪三根已收M5＋至少0.25ATR缓冲。原SL只能收紧，快保与紧急风险路径仍隔离。已有积极单也使用新的保护阈值；固定手数不代表固定资金风险，更长持仓可能占满名额并扩大浮盈回吐。

2026-09-13 老师积极策略专项：主文件 `TeacherActiveBuildOrder` 用老师位/M1失效极值＋0.15 M5 ATR生成初始SL；服务器Stops/Freeze要求扩大距离后重算手数。按OrderCalcProfit测算风险，默认顺势0.35%/逆势0.175%，最小量不足跳过，不再使用旧固定手数；净RR默认>=1.5，计输入每手往返费用和一份点差滑点预算。目标取最近老师/日线障碍前缓冲，最远3R。`ManageTeacherActivePosition` 在真实R后1.5R减半（无法合法分批则全平），1R以后仅已收M5结构支持时推进价格保本，首段后跟随两根已收M5结构，保留原TP上限与紧急风险退出。`TeacherActiveRefreshRisk` 日内首次观察账户净值为基准，默认下降1.5%或老师完整生命周期连续3次亏损SL后只禁新单；净值包含其他品种及入出金影响，不是保证损失上限。以上未做券商实盘/收益回测。

证据核对：2026-09-04；正式源码 `EA_交易托管系统_v1.56.mq5`，以及 `Include/Market/SupportResistance.mqh`、`Include/Market/ShortBox.mqh`。数值输入都属于现有交易语义，维护时不能擅自调参；行号仅为辅助锚点。

## 风险候选到服务器确认

普通管理入口是 `ManagePosition`（主文件 8436，搜索 `ManagePosition(`），它读取服务器仓位、已冻结模板、ATR/结构上下文并计算候选 SL/TP/退出意图，最后才调用统一请求函数。核心判断：

- `MoreProtective`（5245）对 BUY 只接受更高 SL、对 SELL 只接受更低 SL；当前 SL 为空时允许建立保护。
- `SLTPValid`（5254）按 Bid/Ask、方向以及 `SYMBOL_TRADE_STOPS_LEVEL`/`SYMBOL_TRADE_FREEZE_LEVEL` 做距离与方向检查。
- `NormalizePrice`（5118）当前实现只是 `NormalizeDouble(price, _Digits)`，不是显式 Tick Size 对齐；老师点位另有 `ShortTeacherTickSize`/`NormalizeShortTeacherPrice` 路径。这是 TASK-004 记录的边界，不能在无专项授权时顺手改动。
- `NormalizeVolumeDown`（5283）读取 `SYMBOL_VOLUME_MIN/MAX/STEP` 并向下按 step 取整；调用方还必须检查关闭后剩余量是否满足最小手数。
- 请求后不能把候选写成“已保护”，必须经过 `SubmitManagedPositionModify`（3504）和 `ReconcilePendingTradeAction`（3409）读取实际 `POSITION_SL/TP`。

## 短线与趋势初始 R

### 短线

`ShortEnsureInitialRiskReady`（3973）按以下顺序工作：重读已有服务器 SL；若已经在风险侧，调用 `ShortConfirmInitialSL`（3807）冻结实际距离；否则根据 ATR/近期波动、短线箱体/视觉箱体和当前模板生成初始 SL 候选并通过统一修改链请求。`ShortLineGetRisk`（3771）在 `shortRiskReady=false` 时返回 0，不用 ATR 或后续推进的 SL 猜 R。

已实现的保护闸门：`shortRiskReady=false` 时，R 分批、R 保本、浮盈回撤退出和结构追踪不能运行；灾难 SL、初始 SL 补全和绝对最大亏损保护仍要运行。真实初始 SL 读回后才写 `shortInitialRisk`、`shortActualInitialSL`、`shortInitialSLConfirmed`。

### 趋势

`TrendFreezeInitialRiskFromServer`（3378）只接受开仓价风险侧的服务器 `POSITION_SL`，写入 `trendRiskReady`、`trendInitialRisk`、`trendInitialSL`；重启恢复时也要以保存的开仓价/方向/风险侧 SL 组合校验。未 Ready 时，趋势 R 阶梯、保本、结构/ATR 保护不得假定初始风险。`ApplyTrendLongProtection`（4990）负责趋势方向的保护候选，仍须经 `MoreProtective`、`SLTPValid` 和统一修改确认。

## SL/TP 层次

`ManagePosition` 的候选顺序由模板和已有状态共同决定，不能从面板文字反推：

1. 通用/短线初始 SL：固定距离或 ATR 距离；短线还可能使用有效箱体边界/视觉箱体，且“保留已有初始 SLTP”会限制主动收紧/放远。
2. 初始/主 TP：固定或 ATR；短线 `ShortLineEffectiveMainTPDistance`（4222）结合趋势、动能、箱体和老师点位计划；老师 TP 和箱体 TP 要通过方向、空间、最低 R/R、Bid/Ask 和 broker 距离过滤。
3. 保本与快保：普通 `启用保本`、短线动态保本、`ShortFastProtectionCandidate`（18744）和快速微型箱体保护只产生候选；快保状态在服务器实际 SL 达到后才置为已激活。
4. 分批后保护：真实首段成交后，按 `分批后立即保护剩余仓位` 或阶段锁利推进剩余仓位 SL；不得以请求受理代替首段成交。
5. 结构/ATR/阶梯追踪：`CalculateM1PreviousBarsStructureSL`（5208）、`GetAdaptiveTrailConfig`（5138）、`ApplyTrendLongProtection` 和阶段保护均只能单向推进；推进门槛还受最小步长、新 M1 K 线和已收盘结构控制。
6. 浮盈回撤、超时保本和短线回本快收：`GetShortLineDynamicDrawdownProtection`（5485）及 `ManagePosition` 约 8980-9025 只在对应风险/模板闸门满足时提交全平或保护候选。

`fixedTPRemoved` 是服务器 TP 撤销/恢复的状态，不是“代码决定了没有 TP”。只有实际 `POSITION_TP` 达到 0 才确认撤销；尾仓交结构追踪时可能请求撤固定 TP，强趋势或箱体条件改变后也可能请求恢复有效 TP。

## 分批和尾仓

- 一般分批入口：`ExecutePartialTakeProfit`（5939）和 `SubmitManagedPartialClose`（3539）。
- 短线多段入口：`ExecuteShortLineMultiStagePartial`（5787）、`GetShortLineNextPartialStage`（5437）、`GetShortLineStagePartialCloseVolume`（5464）。当前输入保留第三段兼容字段，但实际逻辑当前最多两段；不要据此新增第三段行为。
- 分批触发由 R/S 距离、M1 节奏、动能、利润、目标比例、最小间隔和手数合法性组合决定；`ShortLineEffectivePartialTrigger`（4265）及上下文函数是候选计算，不是成交确认。
- `partialRequestPending`、`pendingPartialStage`、请求/起始/已填量和每阶段累计字段覆盖部分成交；真实退出 Deal 由 `ShortRecordDeal` 累计。第二段可能对剩余仓位使用全平请求，仍要等真实 Deal 和仓位消失。
- `runnerMode`、`fixedTPRemoved`、`partialTPDone` 只在相应服务器事实确认后使用；重启由 `StateStore` 恢复，不要仅凭面板显示重建。

## 箱体、支撑压力、模板和结构

- 支撑压力由 `Include/Market/SupportResistance.mqh` 的 `UpdateSupportResistance`（1255）聚合 M1/M5/M15 等结构，`DetectTrendRegimeM5`（857）提供短线趋势参考；主文件 `RefreshMarketStructureCaches`（10645）按模板缓存并可选择是否更新图表对象。
- `Include/Market/ShortBox.mqh` 的 `ShortLineBoxLevelQualified`、`GetShortLineBoxEdge`、`ShortLineBoxTPPrice`、`ShortLineBoxSLPrice`（4、33、98、128）只从合格的支撑压力/箱体边缘生成短线候选；箱体空间不足、评分/触碰/宽度不合格时回退到动态 ATR/其他候选。
- `配置_黄金超短快保` 是短线快速保本、分批和结构保护模板；`配置_黄金稳健托管` 是趋势保护模板；`配置_黄金支压止盈` 只显示 R/S 和提示，不自动止盈止损、分批或改 SL/TP；`配置_黄金消息对冲` 由独立消息状态机接管。正式 enum/注释在主文件 83-90。
- M1 结构普通路径从已收柱（`GetCachedM1Structure` 使用 shift 1）取得；`M1结构只在新K线更新` 用于减少来回微调。突破、箱体确认和老师反转的 K 线过滤也必须坚持已收柱。
- 微型箱体在 `Include/Market/ShortBox.mqh:227` 明确是最近 5-10 根 M1 的盈利后保护结构，不参与首次 SL 和主 TP；正常尾仓调用 `ShortLineMicroBoxStructureSL(..., false, ...)`（主文件约 8908），只读已收柱。唯一明确例外是灾难保护 `ShortFastProtectionCandidate` 约 18770 传 `includeCurrentBar=true`；不得把这个紧急路径扩成信号确认。

## 外部组合变化

`ShortReconcilePositionShape`（3830）比较当前 volume、开仓均价和方向与 `lastKnownVolume/lastKnownOpenPrice/positionDirection`。外部加仓、减仓、均价改变或 Netting 方向反转会重置/标记风险未知、分批和恢复资格，并记录新的生命周期段；不能把外部减仓冒充 EA 分批，也不能把净额 `INOUT` 当旧仓简单完整退出。

## 状态结论

- 已实现：候选、请求、服务器 `POSITION_*` 确认分层；短线/趋势初始 R 的“服务器风险侧 SL 后冻结”；单向 SL 保护；Hedging/Netting 分批入口；结构/箱体/ATR/回撤/时间保护及持久化字段。
- 部分实现/需专项：通用 `NormalizePrice` 未显式按 Tick Size 网格对齐；消息 runner、消息直接 SL 路径不完全复用统一 pending；实际 broker Stops/Freeze、部分成交、滑点和 Netting 反转尚未实测。
- 未授权待办：任何阈值、默认值、初始 SL/TP、分批、保本、追踪语义的改变都必须形成单独高风险任务并得到用户确认。
