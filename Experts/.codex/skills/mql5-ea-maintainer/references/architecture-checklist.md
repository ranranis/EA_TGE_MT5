# 大型 MQL5 EA 架构检查清单

检查：输入参数、全局/CTrade 对象、enum、struct/TicketState、持久化、OnInit/OnDeinit/OnTick/OnTimer/OnTradeTransaction、持仓管理、交易请求与确认、分批、SL/TP、箱体、支撑压力、消息行情、手机标记、日志、图表对象和清理流程。

每个模块回答：谁调用它、它调用谁、是否改变交易状态、是否发送服务器请求、是否依赖第 0 根 K、是否可重启恢复、失败路径、重复执行风险与性能风险。
