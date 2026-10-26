# D1 集成约定【建议】

D0 已通过，D1 以完整灰盒循环为目标。该文件只固定协作接口，不更改 design/02-rules.md 的【定】规则。

## 只读定义与可存档状态

内容由 `ContentCatalog` 读取同步 JSON，提供 `definitions()`：一个字典，键为 `cards/relics/keepsakes/enemies/encounters/events/path/meta/balance/pages/banter/ui`，值为对应源文件解析结果。规则类通过构造参数接收此只读字典；纯规则不自行读取文件、不依赖 Node 或图片。

规则状态为仅含 JSON 类型的 Dictionary / Array，适合复制、保存与测试。卡牌定义以稳定 id 查询，手牌中的重复牌必须有实例标识。永久进度与单趟状态分开，不把定义或资源放进存档。

## 战斗接口

`battle_rules.gd` 继承 RefCounted，以 `new(definitions)` 构造：

- `start(encounter_def, run_state, seed) -> {state, events}`
- `play_card(state, hand_index, target_index = -1, choices = {}) -> Array[Dictionary]`
- `end_turn(state, keep_index = -1) -> Array[Dictionary]`
- `legal_actions(state) -> Array[Dictionary]`
- `preview(state, hand_index, target_index = -1, choices = {}) -> Dictionary`：完全不改变输入或随机流。
- `forecast(state) -> Dictionary`：当前/下一意图与实际预计掉血，UI 不另算公式。
- `retry(state, attempt) -> {state, events}`：按文档援助，使用新洗牌种子，不能抹掉本趟已拿信物。

完整状态字段与选牌 choices 参数，由战斗实现者在开始写界面前补充本节或发给整合者。不可通过 UI 偷写 hp、energy 或强行判定胜负。

## 随机流

`rng.gd` 由战斗规则实现者单独维护。提供 seed/state 序列化、next_u32()、range_int(min,max_inclusive)、shuffle(array)、snapshot()。不要使用全局随机数。路线、奖励、洗牌、战斗随机各持有独立 state。

## 远征接口

远征实现者拥有 `meta_state.gd`、`run_state.gd`、`path_gen.gd`、`nodes.gd`（必要时增加 `run_rules.gd`），负责接委托、生成七段、节点、奖励、信物/心愿/强制归还、永久服务与结尾判定。应提前向界面整合者提供状态和 API。

普通 JSON 规则表放 `content/data/`；故事放 `content/story/`，均通过 registry 的 file/target 映射同步。新增内容源与规则消费者应直接协调，不各写一份数值。

## 尚需明确的解释（按建议默认，测试必须覆盖）

- 手套的“打两次”只支付一次费用、只算一次 card_played；重复执行该牌效果。原目标已倒下时不暗中改选新目标。
- 生日蜡烛把首张牌中可计数的效果数量翻倍，不重复消耗费用，也不递归触发自己；布尔/选择类效果不应意外无限重入。与手套叠加需要显示准确预览并有专项测试。
- 首领两回合预告必须让玩家拥有两次可读的应对窗口；具体倒计时由战斗实现者明确记录，不跳过预告直接伤害。
- 若三个信物已归还但首领仍未获胜，允许再次下井挑战，不能因没有可接委托而堵住 Demo 结尾。
- 退出/读档要从合法安全点恢复；不得重复发复刻牌或纪念画框。

这些都是未写清处的实现约定，不作为新增成长系统。重要调整需写入 progress/questions；不增加删牌优化、天赋树、永久死亡、商店货币等禁止项。
