---
name: ea-trade-manager-v156
description: "维护、审查或解释本项目正式 EA_交易托管系统_v1.56.mq5 及其直接 Include 时使用；提供源码证据化的架构、交易生命周期、风险、消息对冲、手机标记、持久化与 Canvas 维护地图。不要用于旧版、备份、release 副本或泛化 MQL5 任务。"
metadata:
  short-description: "EA v1.56 maintenance map"
---

# EA 交易托管系统 v1.56 项目 Skill

本 Skill 只服务于当前项目的正式维护对象：项目根下的 `EA_交易托管系统_v1.56.mq5` 及它直接引用的项目 Include。它是维护前的机制地图，不是对旧版 EA、`.bak`、`Backups/`、`_backups/` 或 `_release/` 副本的认可。源码和服务器状态优先于本 Skill、旧架构文档、面板文字和任何推测。

## 何时加载

当任务涉及这个 EA 的持仓接管、模板、`CTrade`、`OnTick`、`OnTimer`、`OnTradeTransaction`、SL/TP、初始 R、保本、分批、回撤、结构追踪、箱体、支撑压力、消息对冲、手机标记挂单、Global Variables、CSV、统计、Canvas 或图表对象时加载。仅讨论通用 MQL5 语法或其他 EA 时不要套用本 Skill。

## 维护前固定入口

1. 先完整阅读项目根 `AGENTS.md`，再按任务需要读取本目录的 references。实现或审查交易生命周期时同时遵循 `mql5-ea-maintainer` 与 `mql5-trade-lifecycle-auditor`；它们是流程约束，本 Skill 是 v1.56 的事实地图。
2. 以 `EA_交易托管系统_v1.56.mq5` 为唯一正式主文件，搜索实际符号和 `Include/...` 引用；不要从旧版、备份或 release 文件复制机制。
3. 推荐读取顺序：
   - 总体调用链、文件职责和模板边界：[`references/architecture.md`](references/architecture.md)
   - 请求、Deal、pending、账户模式、重启和结算：[`references/trade-lifecycle.md`](references/trade-lifecycle.md)
   - 价格、风险 R、SL/TP、分批、箱体和结构：[`references/risk-management.md`](references/risk-management.md)
   - 消息模板/状态机：[`references/news-hedge.md`](references/news-hedge.md)
   - 手机真实挂单及老师点位：[`references/mobile-markers.md`](references/mobile-markers.md)
   - Global Variables、旧版本恢复和日志：[`references/persistence.md`](references/persistence.md)
   - Canvas、统计、CSV、图表对象和性能：[`references/ui-observability.md`](references/ui-observability.md)
   - 修改路由、任务文档和更新/交付检查：[`references/maintenance-map.md`](references/maintenance-map.md)
4. 修改前给出“允许改什么、保持什么、回归风险是什么”的调用链摘要。平仓、分批、SL/TP、保本、回撤、结构追踪、消息拆锁/runner、手机真实挂单、Netting 反转、Deal 归属、重启恢复或新增真实订单属于高风险；按 `AGENTS.md` 先展示最小方案并等待一次明确确认。

## 不可破坏的项目边界

- 默认系统只管理当前品种、管理范围内已经存在的手动单或指定 Magic 仓位；不得新增信号、自动开仓、补仓、马丁、网格、亏损加仓、自动提前建立消息双向仓位或第二套状态机。
- `markerTrade` 产生的手机标记是唯一既有真实挂单例外，必须作为高风险交易模块审查；`teacherAutoTrade` 对应的老师点位自动反转也是现有主动开仓能力，默认关闭，不得被维护任务意外启用。
- `manageTrade`、`markerTrade`、`teacherAutoTrade` 的 Magic 和职责不能混用。面板/对象/状态文字不能替代服务器的 `POSITION_*`、订单、Deal 或实际挂单。
- 四阶段始终分开：候选计算 → 请求发送 → 服务器受理 → 真实 Position/Deal 确认。`CTrade`/`OrderSend` 返回 `true` 或受理 retcode 不是成交、修改、平仓或撤单完成。
- 生命周期以 `POSITION_IDENTIFIER` 为锚；当前 ticket 只是访问句柄。Deal 归属优先 `DEAL_POSITION_ID`，并处理 `IN`、`OUT`、`OUT_BY`、`INOUT`、ticket 切换、外部加减仓、反转、延迟和重复事件。
- 保护性 SL 只能更保护。请求前重读服务器 SL/TP，检查方向、Bid/Ask、Digits、Tick Size、Stops/Freeze、Volume Min/Max/Step；状态只有在服务器实际值或真实 Deal 达标后才推进。
- 突破、箱体确认、结构反转和普通结构追踪使用已收盘 K 线；`GetShortLineMicroBoxRange(includeCurrentBar=true)` 仅是已有灾难保护路径的明确例外，不能扩展到策略确认。
- 不在每 Tick 扫全历史、写 CSV、保存全部 Global Variables、重建全部对象或调用网络；使用已有缓存、事件、定时器、按 position 的历史查询和 dirty flags。

## 证据与更新规则

references 中的行号以文档核对日期所对应的正式源码为辅助定位，不能单独作为定位依据。任何结论至少同时写出“相对路径 + 符号名/搜索词 + 当前辅助行号”，并标注为“已实现、部分实现、已知风险/缺陷、待办或未验证推测”。不要把旧架构文档中的旧版本字段覆盖当前源码事实。

机制变化时，按领域同步更新对应 reference，并检查 `architecture.md` 的调用链和 `maintenance-map.md` 的文件/任务索引；状态字段变化还必须同步 `trade-lifecycle.md` 与 `persistence.md`，UI 入口变化还要同步 `ui-observability.md`。只修正实际变化，不建立冗长 changelog；在各 reference 的证据栏更新核对日期/版本即可。

代码任务完成后由唯一执行者做范围、自主动开仓、状态生命周期、服务器确认和 diff 自检，并按项目流程决定是否调用编译 Skill。当前 Skill 创建任务本身不编译、不启动 MT5、不加载 EA、不点击、不模拟或制造订单；最终报告必须明确实际验证边界。
