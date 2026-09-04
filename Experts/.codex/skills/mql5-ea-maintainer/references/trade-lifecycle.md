# 交易生命周期标准

`POSITION_ADOPTED → INITIAL_RISK_REQUESTED → INITIAL_RISK_CONFIRMED → NORMAL_MANAGEMENT → PARTIAL_CLOSE_REQUESTED → PARTIAL_CLOSE_FILLED → PROTECTION_STAGE_CHANGED → FULL_CLOSE_REQUESTED → FULL_CLOSE_FILLED → POSITION_CLOSE_DETECTED → TRADE_FINALIZED`

- 请求成功不等于成交；`PositionModify`、`PositionClosePartial`、`PositionClose` 的 bool 不是确认。
- 用服务器实际 SL/TP/剩余手数和真实 Deal 确认；pending 必须超时对账。
- Deal 按 `DEAL_POSITION_ID` 去重关联；关闭后先最终结算，再删除状态。
- 重启时立即对账 pending，Summary 必须防重复写入。
