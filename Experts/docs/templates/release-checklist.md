# EA 发布与回滚清单

## 发布前

- [ ] `docs/tasks/active/` 只有本次主要任务。
- [ ] 用户已经确认高风险行为方案。
- [ ] `git status` 中没有范围外变化。
- [ ] 正式文件名仍为 `EA_交易托管系统_v1.56.mq5`。
- [ ] input 名称、中文参数和默认值的变化均有明确授权。
- [ ] 没有意外新增主动开仓、补仓、马丁、网格或消息自动挂单。
- [ ] 新状态覆盖初始化、保存、恢复、删除、失败、pending、超时和重启对账。
- [ ] Position/Deal 归属仍以 `POSITION_IDENTIFIER`/`DEAL_POSITION_ID` 为锚。
- [ ] MetaEditor 完整日志为 `0 errors, 0 warnings`。
- [ ] 项目 Skill 对应 reference 已同步。
- [ ] 用户已完成约定的 MT5/模拟盘/界面/手机端验收。

## 发布记录

- Git commit：
- Git tag：
- 源码 SHA-256：
- EX5 SHA-256：
- MetaEditor 路径：
- 编译日志：
- 参数文件及 SHA-256：
- 用户验收日期与结果：

## 回滚

- 回滚目标 tag/commit：
- 回滚前当前源码和 EX5 已留存：
- 回滚范围已经核对：
- 回滚后重新编译：
- 回滚后用户验证：
