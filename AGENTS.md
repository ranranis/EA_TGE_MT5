# 项目说明

这是一个用于 MetaTrader 5 的大型 MQL5 手动持仓托管 EA。它覆盖 XAUUSD 超短线、手动单、趋势单、箱体与支撑压力、动态 SL/TP、分批、保本、快速保护、M1 结构与微型箱体尾仓、消息对冲、手机标记、交易生命周期、持久化和 CSV 复盘。

# Codex 项目提示词入口

当前 `Experts` 项目的 Codex 工作顺序和交付格式集中写在
`Experts/.codex/PROJECT_PROMPT.md`。本文件负责项目底线；项目提示词负责任务执行顺序，二者同时适用。

# 项目底线

- 未经明确要求，不得新增主动开仓、补仓、挂单或交易方向。
- 不得擅自更改现有输入参数、默认值、SL/TP、分批、保本和追踪阈值；不得删除中文输入参数。
- 仅修改用户明确指定的范围；无关问题只报告，不顺手重构。
- 图表对象和面板修改不得暗中改变交易逻辑。
- 内部状态不得领先服务器：`CTrade` 返回 `true` 不等于成交或修改已真实生效。
- “已分批、已平仓、已快保、已撤 TP”等状态只能由实际 `POSITION_*` 或真实 Deal 确认。
- Deal 归属优先 `DEAL_POSITION_ID` 与 `positionIdentifier`；不得假定 ticket 等于 positionIdentifier，或仅依赖退出 Deal 的 Magic。
- 不得让手机标记 Magic 污染真实持仓管理的 `CTrade` 对象。
- 突破、箱体确认和结构反转只使用已收盘 K 线，不能用第 0 根。

# 修改前必须定位

先搜索并梳理：相关 input、全局变量、enum、`TicketState`、初始化、保存/恢复/删除、`OnInit`、`OnDeinit`、`OnTick`、`OnTimer`、`OnTradeTransaction`、管理入口、请求发送、确认、清理、CSV 日志和图表对象函数。先给出调用链，再开始最小改动。

# 交易动作四阶段

1. 策略产生候选；2. 发送请求；3. 服务器接受；4. 真实持仓或 Deal 确认。计算函数只能产生候选值，不能提前写完成状态。pending 必须有超时、对账和重启恢复路径。

# MQL5 安全与性能

涉及价格、手数和请求时检查 digits、tick size、point、volume min/max/step、stops/freeze level、Bid/Ask 方向、SL/TP 合法性、retcode/comment/order/deal 与服务器实际值。

禁止每 Tick 扫全历史、写 CSV、保存全部 Global Variables、删除重建全部图表对象或调用网络。优先新 K 更新结构、OnTimer 处理低频任务、`ObjectMove` 更新对象、Deal 去重、按 positionIdentifier 查询历史、事件日志配合定时快照。

# 完成前检查

编译并检查新增错误/警告、文件 diff、交易参数和主动开仓能力是否被意外改动。新增状态必须覆盖初始化、保存、恢复、删除、pending 超时、失败和 EA 重启对账；新增对象必须可清理。无法实际编译时必须明确说明。
