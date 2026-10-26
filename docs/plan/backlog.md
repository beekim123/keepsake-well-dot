# 任务池

开发者持续维护：做完打勾，太大的任务拆小，新发现的问题加进来。用户的试玩意见放在最前面，标为最高优先级。

## 用户反馈（最高优先级）

（暂无）

## D0 · 地基

- [ ] 目录骨架、`.gitignore`、`README.md` 补运行方式
- [ ] `package.json` 脚本（见 architecture 第 1 节）
- [ ] 拷贝 Fusion Pixel 12px 字体和全部许可证到 `third_party/fonts/`，写 `third_party/README.md`
- [ ] `resources/art/palette.json`（44 色）
- [ ] `resources/art/lib/png.mjs`、`pixel.mjs`
- [ ] `tools/resources/art.mjs`：build / verify / sheet
- [ ] 素材：`char.asui` 待机（字符画）、`ui.panel.default`（程序）
- [ ] `resources/audio/synth.ts` + `tools/resources/audio-pack.ts` + `audio:check`
- [ ] 音效 `sfx.ui_click`、`sfx.card_play_attack`；8 秒测试旋律
- [ ] `content/registry.json`、最小 `cards.json`、`tools/qa/content-check`
- [ ] `tools/resources/sync-godot.mjs`（含 `--verify`）
- [ ] Godot 工程设置、AssetCatalog、AudioService、SaveService 空壳
- [ ] 标题画面
- [ ] 无界面测试框架 + `tools/godot/cli.mjs`
- [ ] D0 验收

## D1 · 规则可玩

- [ ] `rng.gd`（可序列化）
- [ ] 内容数据：cards、relics、keepsakes、enemies、encounters、events、path、meta、balance
- [ ] `battle_state` / `battle_rules`：回合顺序、出牌、伤害与守护、抽牌与洗牌、胜负
- [ ] `effects.gd` 基础操作 + 文字一致性检查
- [ ] `hooks.gd`：手套、气球、书签、生日蜡烛等特殊奇物
- [ ] `enemy_ai.gd`：意图循环、饿抽屉越嚼越硬、千袜蛇凑对与阶段二
- [ ] 战斗界面（灰盒）：手牌拖拽、目标指示、意图、"将受到 X"、出牌预览、规则牌
- [ ] 战后三选一、牌组满 12 张时的替换
- [ ] 战败：再打一次 / 收绳回家
- [ ] `path_gen.gd`：7 段路牌、✦ 漂移规则、♥ 保证
- [ ] 路牌画面（灰盒）、井道剖面
- [ ] 事件、篝火、交换摊
- [ ] 信物栏、借用效果、心愿判定
- [ ] 守绳屋：委托板、委托卡、出发准备、出发选物、牌册
- [ ] 归还流程（文字页）、复刻牌入池、永久成长
- [ ] 存档与读档、损坏保护
- [ ] 规则单元测试 + 边界情况测试 + 回放测试
- [ ] `policy_bot.gd` + `npm run sim` 报告
- [ ] 第一趟教学流程（固定婚戒、固定手套）
- [ ] D1 验收（含自己完整玩一遍）

## D2 · 叙事与表现

- [ ] StoryPlayer（图层、小循环、平移、翻页、跳过、条件页）
- [ ] 全部插画页素材与 `pages.json`
- [ ] BanterDirector（冷却、优先级、once、chance）+ `banter.json` 全部台词
- [ ] 麻爷绳头说话人（左上角垂下）
- [ ] 对手登场演出 + 规则牌
- [ ] 牌桌彩蛋（袜沼 4 个、蛇巢 2 个）
- [ ] 信物登场、心愿完成、复刻牌盖章演出
- [ ] 正式美术：牌桌 ×2、人物、敌人 ×9、卡框与卡面、奇物/信物图标、界面、特效
- [ ] 回忆换色、虚影换色
- [ ] 音乐 ×6–7、短乐句 ×7、音效全表、说话音
- [ ] 设置菜单
- [ ] `npm run shots` 截图脚本
- [ ] D2 验收

## D3 · 试玩版

- [ ] 按模拟和自玩调数值
- [ ] 阻断性问题清零
- [ ] macOS 导出（Web 可选）
- [ ] 试玩说明 + 问卷
- [ ] D3 验收，打标签 `demo-1`
