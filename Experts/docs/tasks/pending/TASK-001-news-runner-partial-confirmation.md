# TASK-001：消息 runner 分批成交确认

状态：pending

风险等级：高

范围：现有消息对冲状态机，不新增第二套消息系统。

## 已确认问题

`NewsExecuteRunnerPartial()` 当前可能在 `PositionClosePartial()` 返回 `true` 后推进 `firstPartialDone/secondPartialDone`；当 `ResultDeal()` 尚不可读时，还可能先按估算利润记录结果。

`CTrade=true` 只代表请求通过本地检查并被服务器受理处理，不能证明分批 Deal 已真实成交。该状态若提前推进，会在延迟 Deal、部分成交、失败、乱序事件或重启时造成重复/漏记和错误的 runner 阶段。

## 未来实施要求

- 请求阶段只写 pending，不推进完成状态。
- 使用 `DEAL_POSITION_ID` 关联 `positionIdentifier`，累计真实退出 Deal volume 并去重。
- 覆盖失败、超时、部分成交、多 Deal、仓位消失和 EA 重启对账。
- 组合已实现盈亏只采用真实 Deal；估算只能作为显示或灾难保护的明确降级口径。
- 修改前必须展示完整调用链和最小方案，并取得用户明确确认。

本文件只记录已知风险，不授权修改交易代码。
