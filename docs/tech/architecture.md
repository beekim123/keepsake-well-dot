# 技术架构

目录与模块边界见 [repository-layout.md](repository-layout.md)。本文的【定】：

- 引擎 **Godot 4.7.x（与 rpg2d-dot 相同的 4.7.2）+ GDScript**，渲染器选 Compatibility（保留以后导出 Web 的可能）。
- **规则与表现分离**，规则是确定性的（同一种子 + 同一串指令 = 同一结果）。
- 美术、声音、内容各走自己的管线，Godot 只读同步副本。
- 有**自动试玩模拟**，能证明默认配置可以打通，并给出平衡数据。
- 运行时不访问网络。

## 1 工具链

| 项 | 选择 |
|---|---|
| 游戏 | Godot 4.7.2，GDScript（静态类型标注尽量写全） |
| 资源工具 | Node.js 22.13+，`.mjs`，以及用 `node --experimental-strip-types` 运行的 `.ts` |
| Godot 位置 | 环境变量 `GODOT_BIN`，或仓库根目录的本机 `Godot.app`（不提交），或 PATH 里的 `godot` |
| 测试 | Godot 无界面运行自写的小测试框架（不引第三方插件）；Node 端用 `node --test` |

### npm 脚本【建议】

| 命令 | 作用 |
|---|---|
| `npm run art:build` / `art:verify` / `art:sheet` | 美术构建、校验、对照表 |
| `npm run audio:build` / `audio:check` | 声音导出、确定性与数值检查 |
| `npm run content:check` | 内容引用、数值范围、美术/声音 id 是否存在 |
| `npm run sync` / `sync:verify` | 把资源和内容同步进 `godot/`；只读校验 |
| `npm run dev` | 打开游戏（调试版） |
| `npm run godot:test` | 无界面跑全部规则测试与回放测试 |
| `npm run sim` | 自动试玩模拟，输出平衡报告 |
| `npm run shots` | 带窗口运行，按脚本走一遍主要画面并截图到 `artifacts/screenshots/` |
| `npm run check` | 依次跑 art:verify、audio:check、content:check、sync:verify、godot:test、sim（快速档） |
| `npm run export:mac`（可选）/ `export:web`（可选） | 导出 |

## 2 Godot 工程设置【建议】

- 视口 640×360；拉伸模式 `viewport`，比例 `keep`，缩放模式 `integer`。
- 默认纹理过滤 `Nearest`；开启 2D 变换和顶点吸附到像素。
- 字体：关闭抗锯齿、关闭 hinting、关闭亚像素定位。
- 物理和动画不依赖帧率：演出用 Tween 和计时器，规则不依赖时间。

## 3 模块

```text
godot/scripts/
├─ core/                    纯规则（继承 RefCounted，不碰 Node、资源）
│  ├─ rng.gd                可序列化状态的随机数（显式 seed/state，禁用全局 randi）
│  ├─ meta_state.gd         永久进度：累计归还、已开放服务、复刻牌、"整个存档一次"的标记
│  ├─ run_state.gd          一趟的状态：种子、生命、牌组、奇物、信物、心愿、当前段、路牌
│  ├─ path_gen.gd           生成 7 段路牌、✦ 与 ♥ 的位置
│  ├─ battle_state.gd       一场战斗：阿穗、敌人、牌库/手牌/弃牌、能量、回合
│  ├─ battle_rules.gd       start / play_card / end_turn / legal_actions → 事件列表
│  ├─ effects.gd            数据驱动的效果操作（见第 4 节）
│  ├─ hooks.gd              奇物与信物的触发钩子
│  ├─ enemy_ai.gd           意图循环、阶段、召唤
│  ├─ nodes.gd              事件 / 篝火 / 交换摊的选项结算
│  └─ policy_bot.gd         自动试玩策略（测试与模拟用）
├─ content/                 读取 godot/data/*.json，校验并构造规则对象
├─ view/                    牌桌、手牌、敌人、路牌、奖励、事件等界面；EventPlayer 逐条播放事件
├─ story/                   插画页播放器 StoryPlayer、台词调度 BanterDirector
├─ services/                AssetCatalog、AudioService、SaveService（autoload）
└─ debug/                   调试面板（只在调试版加载）
```

### 3.1 规则接口【建议】

```gdscript
# 每个改变状态的调用都返回事件数组，表现层按顺序播放
var result := BattleRules.start(encounter_def, run_state, seed)       # -> {state, events}
var events := BattleRules.play_card(state, hand_index, target_index)  # -> Array[Dictionary]
var events := BattleRules.end_turn(state)                             # 包含敌人回合与新意图
var actions := BattleRules.legal_actions(state)                       # 机器人和界面共用
var preview := BattleRules.preview(state, hand_index, target_index)   # 不改状态，给界面显示预测数字
```

事件示例：`{type="damage", source="player", target=1, amount=6, blocked=4}`、`{type="intent", enemy=0, intent={...}}`、`{type="relic_proc", id="relic.lone_glove"}`、`{type="spawn", enemy_id="enemy.sock_kid", slot=2}`、`{type="victory"}`。

**界面上的任何数字都从状态或 preview 读，表现层不自己算规则。**

### 3.2 表现层

- `EventPlayer` 把事件队列逐条播成动画（命中、数字弹出、意图刷新），每类事件有默认时长，可按"快速模式"压缩。
- `BanterDirector` 订阅同一份事件流，查 `banter.json` 决定要不要冒气泡；它不影响规则。
- 所有素材通过 `AssetCatalog.texture(id)`、`AssetCatalog.frames(id, anim)`、`AudioService.play(id)` 获取。

## 4 数据驱动的效果【建议】

牌、奇物、信物、事件选项的效果用操作列表描述，大部分不需要写代码：

```json
{ "id": "card.yank", "type": "attack", "cost": 1, "target": "enemy",
  "ops": [ { "op": "damage", "amount": 5 }, { "op": "draw", "amount": 1 } ],
  "text": "造成 5 点伤害，抽 1 张牌", "art": "cardart.yank" }
```

基础操作：

- 战斗内：`damage`、`damage_all`、`damage_random`、`damage_equal_guard`、`gain_guard`、`heal`、`draw`、`gain_energy`、`next_turn_energy`、`weaken_next_attack`、`set_intent_idle`、`return_from_discard`、`double_guard_this_turn`、`free_play_other`、`retaliate`（到你下回合开始前，每被攻击一次反击 N 点）
- 节点与事件：`lose_hp`、`max_hp`、`gain_relic`、`gain_card`（可指定类型、随机）、`next_battle`（给下一场战斗加修正：开局守护、多一个敌人、每个敌人第一次攻击无效）、`complete_wish`、`story`（播放剧情台词或插画页）

奇物和信物用 `trigger` + `ops`：

```json
{ "id": "relic.lost_kite", "trigger": "card_played", "when": { "card_type": "guard" },
  "ops": [ { "op": "damage_random", "amount": 2 } ] }
```

触发点：`battle_start`、`turn_start`、`card_played`、`turn_end`、`guard_broken`、`enemy_defeated`、`battle_won`、`incoming_attack`。少数改写规则本身的奇物（手套"打两次"、气球"守护减半"、书签"保留手牌"、生日蜡烛"效果翻倍"）用 `hooks.gd` 里按 id 注册的小函数实现，不要为了它们把操作语言做得很复杂。

**`text` 字段必须和 `ops` 一致**：`content:check` 对常见操作做模板比对（例如 `damage 5` 的牌，文字里必须出现"5 点伤害"）。

## 5 存档

- 一个文件 `user://save.json`，带 `version`。
- 内容：`meta`（永久进度）+ `run`（当前一趟的快照，可为空）+ 设置。
- 只在安全点保存：进入守绳屋、每个路牌画面、每场战斗开始前。战斗中途退出，下次从这场战斗开始时继续（战斗用同一种子重建，结果一致）。
- 读取失败：把坏文件改名备份，提示"存档损坏，已备份"，回到标题，不崩溃。

## 6 测试与验证

| 层 | 内容 | 命令 |
|---|---|---|
| 规则单元测试 | 每张牌、每件奇物、每个敌人意图、回合顺序、[02-rules.md](../design/02-rules.md) 第 8 节的每条边界情况 | `npm run godot:test` |
| 回放测试 | 固定种子 + 指令序列 → 期望的最终状态哈希，放在 `godot/tests/fixtures/` | 同上 |
| 自动试玩模拟 | `policy_bot` 打 N 趟完整流程（默认 300 趟，快速档 50 趟），输出报告 | `npm run sim` |
| 内容检查 | 引用完整、数值范围、文字与效果一致、美术/声音 id 存在、台词说话人存在 | `npm run content:check` |
| 资源校验 | 美术逐字节、调色板；声音确定性、响度 | `art:verify`、`audio:check` |
| 画面 | 截图走查：标题、手账、守绳屋、路牌、战斗（含 4 个敌人）、三选一、事件、归还插画、战败 | `npm run shots` |

### 模拟报告应包含

- 每场遭遇的胜率、平均回合数、平均掉血；
- 首领战胜率（分"默认牌组 + 随机奖励"和"按倾向选奖励"两种策略）；
- 一趟的平均战斗数、估算时长（回合数 × 每回合 8 秒 + 每个节点 15 秒）；
- 各奇物被选后的首领胜率变化（找出过强或没用的奇物）。

目标区间写在 [plan/playtest.md](../plan/playtest.md)。

## 7 调试版

- 命令行参数：`--seed=12345`、`--jump=boss`、`--give=relic.lone_glove`、`--meta=returned_2`（直接把永久进度设到某一状态）、`--shots`。
- F1 调试面板，F2 台词立即显示（检查溢出）。
- 发布版不加载 `scripts/debug/`。
