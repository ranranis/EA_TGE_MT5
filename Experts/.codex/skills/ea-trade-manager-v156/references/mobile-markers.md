# 手机标记与老师点位

2026-09-15 撤挂确认修复：新增 `Include/Trading/MobileMarkerSafety.mqh`；所有现有标记撤单入口经`RequestMobileMarkerDelete`先持久化意图再发请求，5秒重试节流，`ReconcileMobileMarkerDeletes`一秒核对。撤单受理不解锁；旧单消失后要求历史最终状态，无成交撤销/到期/拒绝可释放，撤单竞态成交则要求该position完整退出。自动R/S及老师标记的创建入口均等待全部已跟踪撤单，重启从GV恢复。保持原异常标记持仓关闭及Magic/危险距离规则；未实现对所有新建请求结果不明的通用事务系统，不宣称覆盖所有重复订单场景。

2026-09-15 用户授权默认值修订：主文件 `启用老师点位自动反转短线=true`，17B积极模式仍true。实现原位移入 `Include/Trading/TeacherAuto.mqh`，策略逻辑未变；源码默认不覆盖旧set/保存的实例参数、不代替MT5权限，空老师文本仍不产生老师信号。下文默认false为历史描述。

2026-09-15 性能修订：`ApplyPanelConfigTemplate` 改置 `手机标记环境Dirty=true`，配置按钮不再等待 `ManageMobileMarkerOrders(true)` 的交易请求；后续Tick/Timer按原入口、原强制刷新dirty判定同步。缺少报价或事件繁忙时可能晚于下一秒，面板本地配置切换不等于手机订单已经同步。标记开关按钮、危险距离检查、异常成交处理、撤挂请求及确认逻辑未改；新增 `PERF_MOBILE_MARKERS` 计时。

2026-09-13 第二次授权修订（以下首版描述仅为历史）：积极模式改为17组固定手数（默认0.01），不限制每日次数；每根新M1最多一个请求，当前品种老师多空合计最多5笔，pending/服务器余单期间不发新请求，只在Hedging启用。`TeacherActiveRange` 以此前12根已收M5的范围/路径效率识别震荡，老师线在上下四分之一区域分别做多/空，不机械同时双开。`TeacherActiveFindCandidate` 接近/追价默认0.35/0.50 M5 ATR，允许再次回踩，按AT记录点位方向的上次请求信号并要求重新离开后收回。旧每日次数参数仅保留set兼容、无作用，止损冷却默认60秒。

2026-09-13 专项更新（用户授权提高老师自动交易频率）：正式主文件 `TeacherActiveFindCandidate`、`TeacherActiveBuildOrder`、`ManageTeacherAutoReversal` 新增17B积极策略，原总开关仍默认false。积极模式默认true，D1 EMA20偏向＋M5 ATR14，顺势M1回踩/已收M5突破后首次M1回踩/关键极值逆势拒绝三路；旧17/17A距离、影线、五日过滤只服务旧策略。沿用单仓、独立Magic、pending与真实成交确认，不修改手机挂单。数值点位不理解老师自然语言条件，用户须先整理点位；默认首次接收后24小时失效，可指定服务器生效/失效时间。已实现源码与离线边界验证，不代表频率/收益已回测。

证据核对：2026-09-04；正式源码 `EA_交易托管系统_v1.56.mq5` 约 10986-11943、老师自动反转约 11945-12492。手机标记不是图形对象，而是服务器真实 pending order；老师自动反转还具有真实市价开仓能力，必须分别隔离。

## 两类 Magic 和来源

- `markerTrade` 只处理手机标记；订单必须是当前 `_Symbol`、`手机标记挂单Magic`（输入约 655）和 `SMA_MARK_` comment。自动 R/S 标签为 `SMA_MARK_R1/R2`、`SMA_MARK_S1/S2`；老师文本标签为 `SMA_MARK_K01...`。筛选函数：`IsMobileMarkerOrderSelected`、`IsTeacherMobileMarkerTag`、`IsAutomaticMobileMarkerTag`（11213-11247）。
- `teacherAutoTrade` 只处理老师点位自动反转，使用独立 `TEACHER_AUTO_SHORT_MAGIC`；不能让标记订单进入 `PositionInScope`、普通 `manageTrade` 或统计的真实管理范围。
- `MobileMarkerSourceMode` 有自动结构、老师文本、老师文本无效三种来源；输入 `老师点位文本` 非空时先解析/缓存，关闭短线老师辅助时只影响手机标记，不改变已有短线管理。

## 自动 R/S 同步

`ManageMobileMarkerOrders`（11773）按刷新秒数/`手机标记环境Dirty`运行：

1. 要求 Hedging 账户；非 Hedging 删除/禁用标记，避免标记成交与 Netting 真实仓位合并。
2. 若任何非标记真实交易存在且 `任意交易时撤手机标记` 开启，撤掉全部标记；短线持仓也可按兼容输入撤掉。
3. 通过 `MobileMarkerLevelBroken` 检测大突破；只有 M1 收线确认和缓冲满足时才刷新结构，轻微刺破保留旧点位。
4. R 用 `Buy Limit` 的 TP 线显示压力，S 用 `Sell Stop` 的 SL 线显示支撑；`SyncOneMobileMarker`（11645）先核对旧订单、危险距离、方向价格规则、手数和 Stops/Freeze，再请求撤旧/挂新。

`手机标记固定价格` 是远离当前价的可见挂单价，`手机标记每侧点位数` 当前限制为最多 2。价格/目标的显示线和真实订单规则不同：不能把 marker price 当实际支撑压力成交价，也不能把 pending 存在当同步完成。

## 老师文本同步

`ParseTeacherMarkerLevels`/`RefreshTeacherMarkerCache`（约 11026、11143）解析文本，保存规范化签名和错误状态。`SyncTeacherMobileMarkers`（11530）按目标集合匹配现有订单：

- 不匹配旧订单先发 `markerTrade.OrderDelete`；再为未匹配点位调用 `SubmitTeacherMobileMarker`（11473）创建 `BuyLimit`，目标写到 TP 线。
- 该函数对手数低于 `SYMBOL_VOLUME_MIN` 直接跳过，不自动放大；按 `SYMBOL_VOLUME_MAX/STEP` 校验。
- 默认 `ORDER_TIME_GTC`，指定到期时间被服务器拒绝时退回 GTC；老师输入无效、危险距离、价规不合法时请求撤销。
- 代码在撤旧后立即重新收集订单并显示“撤销中/失败/已同步”；这只能说明本地枚举时的状态，不能替代 `TRADE_TRANSACTION_ORDER_*` 或下一次服务器读回。

## 真实订单风险和清理

`SubmitTeacherMobileMarker`/`SyncOneMobileMarker`（11473、11645）用 `markerTrade` 设置独立 Magic 后发真实订单；`CloseMobileMarkerPositions`（11334）在极端成交时尽量用同一个独立对象关闭标记 Magic 仓位。标记订单是 GTC 时，EA 停止、断线或崩溃后可能继续存在。

当前实现状态：

- 已实现：独立 `CTrade`/Magic/comment；Hedging 限制；手数、方向、危险距离、Stops/Freeze 检查；R/S 和老师文本两种来源；刷新、突破、大部分旧订单匹配；OnDeinit 调用 `DeleteMobileMarkerOrders`。
- 部分实现/已知风险：`DeleteMobileMarkerOrders`（11323）及来源删除函数主要发撤单请求，没有统一持久化撤单 pending、超时、重启核对和“旧单仍存在则绝不创建替代单”的强制状态闸门；GTC 残单需用户在 MT5 订单列表确认。`CloseMobileMarkerPositions` 也没有统一的成交确认状态机。
- 未验证：实际服务器对指定到期时间/GTC、极端行情成交、手机端线显示、撤挂顺序和断线重连行为。

## 老师点位自动反转（不能误启用）

`ManageTeacherAutoReversal`（12454）是现有主动开仓入口，当前输入 `启用老师点位自动反转短线=false`。它的代码路径包括：

- `TeacherAutoFindReversalCandidate`（12276）结合老师价位、最近 5 根已收 D1 外侧边缘、M5 已收拒绝/收回和 M1 反转；只在 `TeacherAutoRearmReady`（12085）且没有 live/pending 单时找下一次。
- `TeacherAutoBuildInitialSLTP`（12132）先生成并校验现有短线初始 SL/TP，使用 tick size/方向/Stops/Freeze；不应绕过现有 `TicketState`。
- `SubmitTeacherAutoReversal`（12397）请求前写独立 pending；`TeacherAutoConfirmEntryDeal`（12380）和 `TeacherAutoConfirmLivePosition`（11993）只在真实 Deal/持仓存在后结束 pending、进入短线管理。
- `TeacherAutoReconcilePending`（12036）对 pending 订单超时但服务器订单仍在时继续等待，禁止重复开仓；无订单/持仓后才允许清理。

这一能力是既有而非本项目默认定位。任何开启、扩大信号、改手数/阈值、增加重试或改变老师过滤都要单独进行高风险确认；手机标记任务不得触碰它。
