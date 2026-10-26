# 绳与对规则验证

- `tests/test_runner.gd`：当前正式门槛（规则、内容引用、拾物/信物、教学、存档迁移、奖励、策略回归）。仅测试读写独立工程的 `user://d2-debug.json`，不使用正式存档。
- `tests/sim_runner.gd -- --count=300`：三策略实际七节点远征，各100趟；并执行同种子拾物拥有/未拥有完整远征对照与首领重试探针。
- `tests/rope_pair/sim_runner.gd -- --count=300 --output=<绝对JSON路径>`：相同模拟，可输出完整JSON证据。
- `tests/battle/run_pure.sh`：使用新 `tests/rope_pair/rules_runner.gd`，只测纯战斗规则；需设置 `GODOT_BIN` 为 Godot 4.7.2。

全机计算预算按项目 AGENTS 要求执行；单worker、nice -n 10，启动前检查已有进程。完整门槛推荐创建仅 ContentCatalog autoload 的独立测试工程，将本仓库 scripts/tests/data 以符号链接挂入，设置 `threading/worker_pool/max_threads=1`，避免启动表现资源和用户存档。

`tests/battle/battle_suite.gd`、`tests/expedition/test_suite.gd` 是历史护盾规则归档，旧5142断言不代表新规则门槛，不再被正式入口执行。模拟中止或超回合/动作预算均计未完成/失败，不强制判胜；数值目标在JSON targets中逐项公开，不能用模拟代替真人试玩。
