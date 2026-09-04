# MQL5 交易安全检查

价格：tick size、digits、NormalizeDouble、Bid/Ask、stops/freeze level、SL/TP 方向。

手数：min/max/step、部分平仓后的剩余手数、请求量与实际 Deal 量、多个 Deal 累计。

结果：`ResultRetcode`、`ResultComment`、`ResultOrder`、`ResultDeal` 与服务器实际 SL/TP/volume。

账户与性能：Hedging/Netting、ticket 与 positionIdentifier、`DEAL_POSITION_ID`；避免在 OnTick/OnTradeTransaction 重历史扫描、文件 IO、网络和重复对象创建。
