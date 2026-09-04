---
name: mql5-compile-reviewer
description: "编译 MQL5 mq5/mqh、读取 MetaEditor 日志、检查 warning，并审查本项目代码 diff 与回归风险时使用；适用于任何 MQL5 代码修改完成后的交付验证。"
---

# MQL5 编译与回归审查

1. 确认修改的 mq5 与允许范围。
2. 使用 [scripts/compile-mq5.ps1](scripts/compile-mq5.ps1) 实际调用 MetaEditor，读取完整日志。
3. 修复新增 error/warning 后重编译。
4. 审查 diff：不得意外调整交易参数或增加主动开仓/挂单/补仓；新增状态覆盖初始化、保存、恢复、删除、失败和超时；新增对象可完整清理。
5. 报告 SourceFile、MetaEditor 路径、errors、warnings、ex5、修改范围、无关改动和未完成的实盘验证。

找不到或无法运行 MetaEditor 时，明确写“未实际完成 MetaEditor 编译”，不得按代码阅读宣称成功。
