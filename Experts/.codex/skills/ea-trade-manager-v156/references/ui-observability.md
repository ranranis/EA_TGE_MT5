# Canvas、图表对象、CSV、统计与性能

2026-09-15 结构提取：`CanvasDirectionColor`至`RefreshCanvasPanelByDirtyFlags`原文移入 `Include/UI/CanvasPanel.mqh`，主文件原位include，类型及Renderer仍在主文件。`ClassifySRTradingIntent`按需共享本次完整四根M1，部分历史继续重试；不跨调用缓存。

2026-09-15 性能修订：主文件 `OnTick` 不再直接执行周期面板刷新/结构绘图，`OnTimer` 保留原周期刷新，`OnChartEvent` 保留即时点击反馈。`ApplyPanelConfigTemplate` 不清空旧模板缓存、不重复创建参数未变的M1 ATR，不在点击内同步手机订单。`RefreshMarketStructureCaches` 命中有效缓存时不重复复制保存数组。`CPanelRenderer::Ellipsize` 改二分宽度探测并去除调用方重复FontSet。`SupportResistance.mqh::AddDensityLevelsByM1PriceBuckets` 改有界直接索引，保留首次出现/同分顺序，跨度过大或索引分配失败回退原搜索。新增PERF `TemplateSwitch/MobileMarkers/OnChartEvent`；默认仍关闭。离线模型对照不代表MT5实测延迟；未做实盘加载或视觉验收。

证据核对：2026-09-04；正式主文件 Canvas 区约 1861-17857，事件区 18986-19534；直接 Include 的日志/统计实现也属于维护范围。显示信息不是服务器事实；任何能触发交易的按钮按高风险逻辑审查。

## Canvas 视图链

主文件注释从约 1861 开始标为 v1.56 Canvas 架构。主要对象/类型：`PanelViewState`、`PanelTheme`、`PanelMetrics`、`PanelLayout`、`PanelViewModel`、`UIHitRegion`、`CPanelRenderer`；运行期缓存是 `CanvasPanelModel`、`CanvasPanelDirty`、`Canvas*ModelValid` 和复盘/走势缓存。

刷新路径：

```text
业务/交易事件
  -> MarkCanvasPanelDirty / 失效 ViewModel/统计缓存
  -> BuildMiniPanelViewModel / BuildHoldingPanelViewModel / BuildStatsPanelViewModel
  -> Calculate*PanelLayout
  -> RenderHidden/Mini/Holding/StatsCanvasPanel
  -> Build*HitRegions -> CanvasRedraw
```

`BuildHoldingPanelViewModel`（14111）、`BuildStatsPanelViewModel`（14903）只应读取业务状态；`RenderHoldingCanvasPanel`（14566）、`RenderStatsCanvasPanel`（16608）消费 ViewModel；`RefreshCanvasPanelByDirtyFlags`（16655）按 dirty flags 更新而不是每次重建全部内容。Canvas 与旧对象式面板仍有同步函数 `SyncCanvasStateFromLegacy`/`SyncLegacyStateFromCanvas`（2833、2854），修改时不能让两个状态源产生不一致。

`OnTradeTransaction` 收到 `DEAL_ADD` 会 `InvalidateStatsCache` 并标记 Canvas 数据失效；`RefreshPanel`（17803）负责刷新节流、隐藏/迷你/完整模式和 `ChartRedraw`。面板当前显示模板可能与某个仓位的冻结模板不同，持仓页必须按 `TicketState.adoptedTemplate` 展示/管理。

## UI 交易边界

`OnChartEvent`（18986）不只是绘图事件：

- 持仓按钮可能调用全平、分批、保护或模板相关动作。
- 消息按钮在约 19084 起可冻结箱体、开放拆锁或请求消息组合动作。
- 手机标记面板开关会保存开关并调用 `ManageMobileMarkerOrders`，触发真实撤/挂请求。
- 模板切换只应影响下一单/显示；进行中的消息组合和已有 `TicketState` 不能被切换中断。

改 Rect、命中区域、按钮文案或点击去重时，必须检查 `sparam` 对应的真实函数调用，不能把它当纯 CSS/UI 修改。Canvas 渲染不应直接写交易状态；如果按钮要交易，必须走已有请求、pending 和服务器确认链。

## 图表对象

- 支撑压力 `Include/Market/SupportResistance.mqh` 的 `UpdateSupportResistance(force, updateVisuals)`（1255）在需要时更新 `SMA_SR_*` 线；`DrawSupportResistanceLines`（1191）负责显示，`updateVisuals=false` 可在持仓循环避免重复绘制。
- `Include/Market/ShortBox.mqh:204` 的 `DeleteLegacyShortLineBoxChartObjects` 清理 `SMA_SHORT_BOX*`、微型箱体和历史前缀对象；主文件在启动/刷新相关路径调用它。
- Canvas 初始化会清理/销毁旧面板对象；`OnDeinit` 调用 `DeletePanel`、销毁 Canvas、释放 ATR。新增对象必须有明确前缀、更新和清理路径，不能每 Tick 删除再重建全部对象。
- `显示支撑压力线` 默认可关闭，但面板/手机标记仍使用结构缓存；可视化开关不能改变风险候选或交易结果。

## CSV 与完整生命周期统计

`Include/Journal/TradeJournal.mqh`：

- `TradeJournalFileName`（4）生成 `SMA_<kind>_<login>.csv`，当前 kind 包括 `TradeDeals`、`TradeLifecycle`、`TradeSummary`。
- `TradeJournalWriteDeal`（65）写原始 Deal；运行期 `processedJournalDealTickets` 去重。
- `TradeJournalWriteLifecycle`（92）写请求、确认、状态、快照和失败事件；`TradeJournalWriteSnapshots`（158）由 Timer 周期调用。
- `TradeJournalImportAvailableHistory`（177）启动时补录可读经纪商历史，但不能倒推过去的 Tick 级管理轨迹。

`Include/Journal/TradeSummary.mqh:15` 的 `FinalizeTradeLifecycle` 只有在仓位消失后按 `HistorySelectByPosition(positionIdentifier)` 聚合并写 Summary；`Include/Journal/LifecycleStatistics.mqh` 明确以完整 position 生命周期为交易口径，退出 Deal 数量只是执行质量信息。`CalculateLifecycleStatsByBJRange`（752）结合 Summary 元数据，排除仍 live 或未完整退出生命周期，按北京时间/模板/时段计算表现、走势和复盘。

## 性能敏感路径

- `OnTick` 每 tick 计算新 K 标志、扫描当前仓位、执行管理；必须保持结构/ATR缓存，不能加入全历史扫描、网络、全量 CSV 或 Global Variable 写入。
- `Include/Market/ATRCache.mqh:10` 以 `iTime(...,1)` 的已收 M1 柱缓存 ATR；同一收盘柱复用。
- `RefreshMarketStructureCaches`（10645）按当前模板加载/保存缓存，并调用 `UpdateSupportResistance`；持仓循环前后已有缓存设计，避免每笔仓位重复复制同一数组。
- 统计缓存按筛选/日期/服务器范围/Deal generation 失效；复盘/走势数据不是每 tick 重算。
- `Performance.mqh` 的 metric 包括 `OnTick`、`OnTimer`、`ManagePosition`、短线上下文、支撑压力、箱体、面板刷新、状态保存、历史查询、日志和交易事件；`PerformanceScope` 及 `PerfFlushIfNeeded`（约 62、73）只在性能开关开启时统计/输出，不参与交易判断。
- `LogUtils.mqh` 的 `AllowRateLimitedLog`/`PrintRateLimited`（13、55）限制高点差、失败和重试日志；不要用高频打印替代状态。

## 状态结论

- 已实现：Canvas dirty flags/ViewModel/Renderer 分层；旧对象清理；Deal 事件使统计缓存失效；TradeDeals/TradeLifecycle/TradeSummary；完整生命周期统计/复盘；ATR/结构/统计缓存和性能计数器。
- 部分实现：部分 UI 按钮和手机开关能发真实动作；Canvas 视觉状态与服务器确认之间需要逐动作核对。旧对象式面板作为兼容路径存在，不能只测试新版开关。
- 未验证：不同 DPI/窗口尺寸、旧版面板点击、Canvas 视觉布局、长历史 CSV 性能和真实日志文件锁竞争；本 Skill 创建任务不做截图、点击或视觉验收。
