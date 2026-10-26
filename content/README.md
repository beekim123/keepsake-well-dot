# 内容源：D1 完整数据，灰盒表现

这里是唯一编辑入口。`godot/data/` 是 `npm run sync` 生成的只读运行副本，不手改。

**数据已齐不等于完整游戏已经实现或验收。** 本目录提供设计说明 01–05 的 D1 规则/文字数据；实际战斗、路线、存档、界面、自动试玩要各自通过运行测试。D2 的正式像素插画、人物、卡面、配乐和叙事演出尚未完成。

## 注册表与规模

`registry.json` 保留 D0 的 `format: content/1`、`files[{id,file,target}]`，增加 `stage: D1` 以启用完整校验。每个源文件顶层都是数组；每条记录有稳定 `id`。`ContentCatalog.definitions()` 用 **registry 的 id** 映射原数组，不能从文件名推断业务表。

| registry id | 源 | 运行 target | 规模 |
|---|---|---|---|
| cards | data/cards.json | cards.json | 24：4 种起始、14 种奖励、3 普通复刻、3 心愿＋版 |
| relics | data/relics.json | relics.json | 15 |
| keepsakes | data/keepsakes.json | keepsakes.json | 3 |
| enemies | data/enemies.json | enemies.json | 9（含精英、首领、小袜子） |
| encounters | data/encounters.json | encounters.json | 10 普通遭遇 |
| events | data/events.json | events.json | 6 |
| path | data/path.json | path.json | 1 条七段规则 |
| meta | data/meta.json | meta.json | 1 组永久进度与结尾规则 |
| balance | data/balance.json | balance.json | 1 组可调数值 |
| pages | story/pages.json | story/pages.json | 10 序列、25 页：原主流程 22 页，加首胜线索/婆婆消息/芦苇记号各 1 页 |
| banter | story/banter.json | story/banter.json | 44 条触发记录，包含教学、信物、敌人和主线短台词 |
| ui | data/ui.json | ui.json | UI 模板、说话人名册和 6 个纯表现牌桌彩蛋 |

`card.vow_plus` / `card.whisper_plus` / `card.deliver_plus` 是新增＋版稳定 id；普通版的 `plus_card_id` 与＋版的 `replica_of` 互指。复刻解锁引用信物上的 `replica_card_id` / `replica_plus_card_id`，不可把普通、＋版同时无条件加入奖励池。

## 规则消费者约定

- **牌**：`pool` 为 `starter/reward/replica/replica_plus`；起始牌数量仍使用 D0 的 `starterCount`。`meta.starter_deck` 是同一数量的展开列表，校验器保证两者一致。`uses_per_battle` 约束晃绳子，不是消耗/永久删牌系统。
- **操作**：战斗使用架构文档的基础操作。`damage.times` 是多段；`return_from_discard.amount` 表示选择数量，不是抽牌。`damage_equal_guard`、`free_play_other`、`double_guard_this_turn` 等动态/选择操作不伪造固定 `amount`。
- **奇物/信物**：普通效果用 `trigger/when/ops`。少数规则改写用 `hook`（稳定 id 的末段）和数值 `params`；有 hook 时允许空 `ops`。口琴 `gain_guard` 的 `multiplier: remaining_energy` 乘当前剩余能量。毛球/按钮等派生效果不重复算作出牌。
- **敌人**：`intents` 为公开循环，`type` 为 attack/guard/guard_all/consume_minion。攻击可带 `times/draw_penalty/guard`，精英守护带 `growth`，吞袜带 `enemy_id/heal/fallback_damage`。首领数值全部在 `mechanics`，包括两回合预告。
- **遭遇**：普通遭遇 `enemies` 为敌人 id 数组，重复 id 表示多个实例。`path.elite_encounter_id` 与 `boss_encounter_id` 特意直接使用 `elite.hungry_drawer` / `boss.sock_snake`（定义位于 enemies）；规则入口将其正规化为单敌人遭遇，不额外虚构两条普通遭遇。
- **节点**：选项 `ops` 顺序执行。`next_battle` 源键是 `guard/enemy_id/bonus_relics/first_attack_immune`；Nodes 正规化到运行状态的 `start_guard/extra_enemies/extra_relic_rewards/cancel_first_attack`。无效果选项明确写“不发生变化”。条件心愿选项用 `when.keepsake_id`，和 `complete_wish.keepsake_id` 必须相同。
- **心愿/归还**：`wish.type` 为 `campfire_rest/event_choice`；事件型另带 `event_id/choice_id`。返回故事的 `end.stamp/stamp_plus/keepsake_id` 与信物映射一致。每段归还故事恰有三页普通页和一页 `when.wish` 条件页，未完成心愿仍正常归还。
- **路径/永久进度**：`path.segments/types/choices/tiers/hints/placement` 是路线生成输入；双事件心愿用 2→3 与 4→5 的不同段安排。`meta.services` 根据累计归还开放；结尾要求所有信物归还且首领胜利。没有可接委托但尚未胜首领时仍允许出发，避免死局。
- **文字**：UI 数值模板用 `{token}`；表现层替换状态或 preview 的值，不自行算伤害。`ui.d1.*` 是 D1 灰盒界面词条。说话人记录 `kind: speaker`，以 `speaker` 声明稳定身份；敌人和信物直接以自身 id 为说话人。`caption` 是故事画面叙述的 D1 文字替代，需和正文一起显示，不能只读对白而丢掉故事细节。
- **故事演出**：全部 `layers: []` 是明确的 D1 纯文字页，不是假装已完成正式插画。`intro.when.intro_seen=false`；结尾的 `when` 同时要求归还和首领条件。归还强制发奖/一次性标记归规则状态负责，跳过故事不能跳过发奖，也不能重复发奖。

## D1 占位与 D2 替换表

当前只引用已存在的真实资源 id，没有伪造缺失素材：

| 语义用途 | D1 真实资源 | D2 要替换的范围 |
|---|---|---|
| 三类牌卡面 | `cardart.attack_stub` / `cardart.guard_stub` / `cardart.special_stub` | 各张牌独立正式卡面；现有为类型共用灰盒 |
| 奇物/信物图标 | `ui.panel.default` | 各个 relic/keepsake 的正式第一方像素图 |
| 9 种敌人 | 对应敌人同名 id（含 `elite.hungry_drawer` / `boss.sock_snake`） | 当前为独立程序灰盒，D2 替换为正式精灵与动画 |
| 麻爷头像 | `char.ma_ye` | 当前程序灰盒，D2 正式绳头与表情 |
| 委托人头像 | `ui.panel.default` | 各委托人独立像素头像/立绘/表情 |
| 阿穗说话人头像 | `char.asui` | 角色正式头像与表情；现有待机精灵仍可复用 |
| 6 个事件插画、6 个牌桌装饰 | `ui.panel.default` | 独立事件图与装饰小动画 |
| 25 页故事插画 | 空 `layers`，正文及 caption 完整 | 背景/人物/道具/前景图层及回忆换色 |
| 牌桌装饰反馈声音 | `sfx.ui_click` | 独立晃绳/蛙声/泡泡/芦苇/袜子/线团音效 |
| 牌桌、卡框、意图图标 | `board.sock_swamp` / `board.sock_lair`、`card.frame_s/l.*`、`intent.*` 已由第一方灰盒批次提供，界面直接使用 | D2 正式场景、组件和演出 |
| 标题已有美术/音乐 | 由已有标题场景引用；本内容未虚构新 id | 完整主题曲与各场景第一方合成音乐 |

这些灰盒占位不能进入 D2 验收。所有替代素材仍须遵守仓库红线：代码绘制、代码合成，无生成模型、无外部图音素材、无现成作品角色或台词。

## 校验

- `npm run content:check`：严格检查顶层表、id/重复、数值类型、操作字段、触发器、卡池数量、文字与效果、所有内容/资源引用、意图、心愿选项、首趟/结尾条件、条件故事页与复刻盖章链接。
- `node --test tests/content.test.mjs`：完整内容正例与畸形 JSON、漏引用、错误数值/文本、未知操作、隐藏选项效果、错误心愿/结尾条件等负例。
- D0 冻结 fixture 仍可不带 `stage`；检查报告明确区分 D0 最小基础与 D1 完整源数据，不把 D0 的四牌数量硬编码成所有阶段的要求。
- manifest 不存在时明确警告未检查资源；存在时必须逐项命中且哈希有效。本次 D1 检查使用实际已构建 manifest，不以忽略引用冒充通过。
