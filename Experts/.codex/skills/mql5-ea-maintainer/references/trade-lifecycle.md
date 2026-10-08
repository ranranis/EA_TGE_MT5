# 交易生命周期标准入口

当前项目的交易生命周期详细规则统一维护在
[`ea-trade-manager-v156/references/trade-lifecycle.md`](../../ea-trade-manager-v156/references/trade-lifecycle.md)。

本文件不再复制第二套规则。审查请求、确认、持仓和 Deal 状态链时，必须以项目专用文件为准，重点包括：

- `POSITION_IDENTIFIER` 与 ticket 的关系
- `DEAL_POSITION_ID` 归属
- pending 超时、重试和重启恢复
- 部分成交、重复事件和完整平仓
- 请求值与服务器实际值的差异
