# 绳与对规则验证

测试从 `b1eb91e:godot/tests/` 恢复，适配当前根目录工程。

- `Godot.app/Contents/MacOS/Godot --headless --path . --script tests/test_runner.gd`：战斗、远征规则。
- `Godot.app/Contents/MacOS/Godot --headless --path . --script tests/sim_runner.gd -- --count=300`：确定性七节点模拟。
- `tests/battle/run_pure.sh`：不加载表现资源的独立战斗测试，需设置 `GODOT_BIN`。

旧根测试入口依赖 D1 专用 audio/view 断言；当前入口仅聚合恢复的两套纯规则测试，不把旧 D1 界面假设当新版验收。
日志/截图写入 `.local/rope-and-pair/`，禁止提交；任何启动完整游戏的 QA 都必须带调试参数且使用 `user://d2-debug.json`，不得读写正式存档。

阶段 0 基线（2026-10-27）：5,142 条规则断言全过；300 趟、1,101 场、5,251 回合，错误为 0；实际窗口首趟控制器 34 项全过。基线 JSON 和五张截图保存在上述本机目录。
