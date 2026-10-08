# 持久化、Global Variables 与重启恢复

2026-09-15 五项风险修复：实际StateStore升级V7，新增PC保护字段提交标记；`ShortStateWrite`检查GV返回值，写入失败保留dirty，不提交PC。新增TRR/TRU/TIR/TIS/THI/TLO趋势R与极值、RAR/RAT/RAL/RAG恢复武装、TPI/TPV/TPSL/TPSH/TPMD/TPT1/TPT2老师冻结计划（签名拆32位）。保存/恢复/删除同步，`trendRiskUnknown`在创建初始化及INOUT重置。旧V6/缺键/未提交保护字段不猜原始R、不套当前老师文本；离线加仓/均价变化不继承保护。原始R已遗失无法自动补回。`MobileMarkerSafety.mqh`使用S55.MD.<account>.<magic>.<symbol>.<ticket>持久化撤单等待，ticket在键名中不转double；历史最终撤销或成交仓完整退出后清除。

2026-09-13 多仓修订：AUTO V1增加可选PM（pendingMode，缺省0兼容旧请求），保存/恢复/清pending同步；新请求comment为 `TEACHER_ACTIVE_<mode>_<signalTime>`。AC/AB旧键不再用于限额/首次回踩，保留旧键清理；新增AT0..39记录点位方向请求信号，签名变化清理、跨重启保留，真实确认可补录请求返回前崩溃丢失的AT。AX仍只防同M1重复请求，不是日额度。pending结果不明保持占位；订单FILLED还须精确Position确认或完整入出Deal量对账，未读取真实成交时不释放。TAP逐仓管理及日内AH保护键语义不变。

2026-09-13 当前源码专项核对：本次实际 `Include/Persistence/StateStore.mqh::ShortStateSave` 写V6（下文历史V9描述不适用于此工作树）。新增可选 `TAP` 保存/恢复/删除 `teacherActivePlan`，旧状态缺键时保留真实仓位comment识别结果。老师AUTO原V1 pending不变；新增AD日、AE首次日净值、AH停机锁、AS拆分点位签名、AF首次接收时间、AX最后请求信号、AC0..39点位方向日请求计数、AB0..39突破收盘时间。AC每日或点位签名变化清理，AB签名变化清理，AH换日重置；请求前和停机时flush，EA卸载不删除保护状态。历史风险缓存为运行态，重启Init/Timer按完整position id重建，不把请求计数当成交次数。

证据核对：2026-09-04；正式源码 `Include/Persistence/StateStore.mqh`（568 行）、主文件 `TicketState`/`NewsHedgeState`。项目旧架构文档 `docs/architecture/persistence-and-restart.md` 仍写短线 `V=8`；当前源码 `ShortStateSave` 已写 `V=9`（约 231），源码优先。

## 短线 TicketState 键空间

`ShortStateKey`（`Include/Persistence/StateStore.mqh:4`）格式为：

```text
S55.<login>.<symbol>.<positionIdentifier>.<field>
```

它以 `POSITION_IDENTIFIER` 而不是当前 ticket 作为生命周期主键。`ShortStateSave`（121）把 `TicketState` 的风险、初始 SL、模板、老师计划、峰谷、恢复武装、分批、pending、Deal/退出、外部变化、Netting 反转、生命周期和浮盈时长字段写入 Global Variables，并在末尾写 `V=9`。`MarkShortStateDirty`/`FlushShortStateIfNeeded`（237、244）支持 dirty 批量保存；不要为了显示字段在每 Tick 强制完整落盘。

关键保存类别：

- 身份与开仓：`TK`、`ID`/position identifier、`OT`、`DR`、`ATM`、初始 volume/开仓价。
- 短线风险：`IR`、`ISL`、`ASL`、`RR`、`SC`、`RU`。
- 趋势风险：`TRR`、`TIR`、`TIS`；这些字段来自 TASK-004 的服务器 SL 后冻结设计。
- 分批/pending：`PS`、`PD`、`PEN`、`PST`、`PV`、`PF`、`PSV`、`PQT`、`F1/F2/F3`。
- 请求/退出：`LP`、`PG`、`PA`、`PAT`、`PRQ`、`POR`、`PDE`、`PSL`、`PTP`、`PVO`、`PEI`、`PFP`、`PFSL`、`PFR`、`CDT`、`FRC`、`FIN`。
- 生命周期/外部变化：`LRN`、`MLP/MLL`、`LPE`、`EVC/EVT`、`PEF`、`PRC`、`LED`、`RBT`、`NRV`、`LST`。
- 浮盈时间：`FTPS/FTLS/FTFS/FTLL/FTFP/FTOS/FTHD/FTFN`。

字段缩写以源码 `ShortStateSave`/`ShortStateLoad` 为准，不要只复制此摘要；新增字段必须同时进入保存、恢复、删除和版本兼容逻辑。

## 加载、对账和删除

- `ShortStateLoad`（266）读取已保存版本和身份，校验保存的开仓时间、方向、开仓价以及短线/趋势风险组合；不完整或矛盾时不猜测原始 R，保留风险未知并等待服务器实际 SL 对账。
- `ShortStateRestoreAll`（516）扫描 `GlobalVariablesTotal`，按键提取 position identifier，跳过已有 Summary 的生命周期，重新建立当前可见或待最终结算的状态，并写 `STATE_RECONCILED_AFTER_RESTART`。它不是恢复旧 ticket 的盲目重试。
- `OnInit`（主文件 17858）顺序包含 `ShortStateRestoreAll` 和逐状态 `ReconcilePendingTradeAction`；`OnTimer` 继续补 Deal/超时/对账；`OnDeinit`（19513）强制 `FlushAllDirtyShortStates(true)`。
- `ShortStateDelete`（503）只在 `FinalizeTradeLifecycle` 成功后删除 position identifier 下的全部字段；`CleanupStates`（主文件 3654）先等待仓位消失、历史 Summary 完成，再从数组移除。仓位刚消失时不得立刻删状态。
- `TradeSummaryKey`（`Include/Journal/TradeSummary.mqh:4`）使用 `S55.SUMMARY.<login>.<symbol>.<positionIdentifier>` 防止重复写完整汇总。

## 老师自动状态

`TeacherAutoStateKey`（`StateStore.mqh:21`）格式为：

```text
S55.AUTO.<login>.<symbol>.<field>
```

`TeacherAutoStateWriteUlong/ReadUlong`（26、35）把 pending order/deal 等 `ulong` 拆成低/高 32 位写入，避免直接转 double 造成精度损失；自动反转的 pending、重武装和真实入场确认由主文件 `TeacherAutoStateLoad`、`TeacherAutoStateSave`、`TeacherAutoReconcilePending` 管理。不要把这些键混入某个 position 的 `TicketState`。

## 消息状态

消息状态不在 `StateStore.mqh`，而在主文件 `NewsHedgeKey`（6071）：

```text
SMA_NH_<login>_<symbol>_<field>
```

`NewsHedgeSaveState`（6090）当前写 `VER=5`，保存阶段、双腿/runner/loser ticket 和 identifier、箱体/缓冲、拆锁时间、实际/估算成本、runner 风险、微回踩、部分阶段、最近 Deal 和 pending Deal 队列；`NewsHedgeLoadState`（6204）在 `OnInit` 恢复并对旧版本状态做有限兼容，`NewsHedgeDeletePersistence`（6076）负责清除字段。旧版本重建只能以当前服务器仓位和可读取历史为证据，不能凭面板状态推断方向。

## 不能持久化替代的运行态

`TicketState` 末尾明确将浮盈计时当前状态、采样毫秒、缓存和部分 dirty 维护为运行期字段；processed Deal 数组也是运行期集合。重启后依靠持久化字段、`HistorySelectByPosition`、事件和定时补录恢复，不能声称运行期去重集合跨终端存在。

Global Variables 的值本质上是 `double`：老师自动的 ulong 已拆分，但短线状态中 ticket/position id 仍有 double 表示边界；项目交接文档把超出 IEEE-754 精确整数范围列为理论风险。不要新增直接把任意 `ulong` 写 double 的持久化字段，除非先设计兼容编码。

## 状态维护规则

当新增或修改字段，必须逐项核对：定义/默认初始化 → 新仓创建 → 更新/dirty → 保存 → 恢复/旧版本 → 请求失败/pending/超时/部分成交 → 重启对账 → 完整结算 → 删除。同步更新 `trade-lifecycle.md`（状态语义）和本文件（键/版本/清理），必要时更新 `news-hedge.md` 或 `mobile-markers.md`。不要把架构文档的旧版本数字直接作为实现依据。

## 结论

- 已实现：短线状态按 identifier 保存；短线 schema 当前 V9；老师自动独立键和 ulong 拆分；消息 VER5；启动恢复、Timer 对账、dirty flush、Summary 前清理。
- 部分实现/已知风险：运行期 Deal 去重集合不跨重启；消息/手机标记的订单撤销 pending 不是统一的 `TicketState` 链；Global Variables 的 double 约束仍需谨慎；旧文档 V8 已漂移。
- 未验证：重启恰逢部分成交/延迟 Deal/断线、旧键与当前 ticket 切换的全部时序；需要 MT5 日志或专项静态审查，不在普通文档更新中臆补。
