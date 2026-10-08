---
name: mql5-ea-maintainer
description: "维护、审查或重构本项目大型 MT5 MQL5 EA 时使用，适用于 mq5、CTrade、OnTick、OnTimer、OnTradeTransaction、SL/TP、分批、保本、箱体、结构追踪、持久化、交易日志和图表对象任务。"
---

# MQL5 EA 维护流程

1. 复述允许修改模块、保持不变功能和主要回归风险。
2. 搜索参数、状态、初始化、保存/恢复/删除、事件入口、请求、确认、清理和日志，先给出调用链。
3. 先读 [architecture-checklist.md](references/architecture-checklist.md)。涉及请求、Deal、pending 或重启时，以项目专用 Skill 的 [trade-lifecycle.md](../ea-trade-manager-v156/references/trade-lifecycle.md) 为唯一详细依据；本目录的同名文件只作入口说明。涉及价格/手数时读 [mql5-safety-checklist.md](references/mql5-safety-checklist.md)。
4. 将候选计算、请求发送、服务器确认分开；复用现有系统，不建立第二套箱体、持仓或状态系统。
5. 最小范围实施。新增 `TicketState` 字段同步初始化、保存、恢复、删除、超时和重启对账。
6. 完成后调用 `$mql5-compile-reviewer`；优先通过 MetaEditor MCP 的 `syntax_check`/`compile_file` 编译，MCP 不可用时才使用备用脚本，并审查 diff，说明未完成的实盘验证。

## 强制规则

- 不自行调参，不增加主动开仓、补仓或挂单，不作无关格式化/重命名。
- `CTrade` bool 不是最终确认；以 `POSITION_*` 和真实 Deal 为准。
- Deal 优先 `DEAL_POSITION_ID` 对应 `positionIdentifier`，并去重。
- 只用已收盘 K 线确认结构；可视化不得改变交易结果。
- 网络/重历史扫描不放 OnTick；图表对象优先 `ObjectMove`。
