# 《拾遗井》设计文档目录

> 暂定名。低难度短途卡牌远征：下井找回镇上人惦记的东西，借来用一趟，回来物归原主，换一段故事和一张永久新牌。

本目录是给开发者（GPT）的需求与方向。内容分四种强度：

| 标记 | 含义 | 开发者能做什么 |
|---|---|---|
| 【定】 | 核心支柱，决定这是不是"这个游戏" | 不改。确实做不下去时写进 `plan/questions.md`，说明原因和替代方案，按最接近的方案继续 |
| 【建议】 | 推荐的方向、数值、做法 | 可以改。改了更新对应文档，并在 `plan/progress.md` 写一句为什么 |
| 【留白】 | 有意没写细 | 自己设计，补进文档 |
| 【待验证】 | 需要原型或试玩确认 | 按当前写法做，试玩后再定 |

没有标记的内容默认按【建议】处理。**所有数值都是初稿，待原型验证。**

## 阅读顺序

| # | 文档 | 内容 |
|---|---|---|
| 0 | [00-vision.md](00-vision.md) | 一句话、相对原方案的调整、设计支柱、目标体验、**Demo 范围**、**刻意不做**、术语 |
| 1 | [design/01-world-story.md](design/01-world-story.md) | 世界、人物、Demo 逐场剧本、写作风格 |
| 2 | [design/02-rules.md](design/02-rules.md) | 规则细则：流程、路牌、信物与心愿、回合顺序、伤害、奖励、失败、边界情况 |
| 3 | [design/03-content.md](design/03-content.md) | Demo 内容表：牌、奇物、信物、敌人、遭遇、事件、路牌提示语 |
| 4 | [design/04-storytelling.md](design/04-storytelling.md) | 炉石冒险式叙事：插画页、对手登场、牌桌台词、彩蛋、演出 |
| 5 | [design/05-ui-flow.md](design/05-ui-flow.md) | 画面流程、布局、操作、反馈、调试功能 |
| A1 | [art/art-direction.md](art/art-direction.md) | 美术风格、调色板、规格、素材清单、自查清单 |
| A2 | [art/art-pipeline.md](art/art-pipeline.md) | 用代码画像素、导出 PNG 的管线 |
| S1 | [audio/audio-direction.md](audio/audio-direction.md) | 代码合成声音的管线、主题动机、曲目、音效 |
| T1 | [tech/architecture.md](tech/architecture.md) | Godot 架构、规则接口、数据驱动效果、存档、测试与模拟 |
| T2 | [tech/repository-layout.md](tech/repository-layout.md) | **目录规则**、单向依赖、修改入口、抽离规则 |
| P1 | [plan/roadmap.md](plan/roadmap.md) | 里程碑 D0–D3 与验收标准 |
| P2 | [plan/backlog.md](plan/backlog.md) | 任务池 |
| P3 | [plan/playtest.md](plan/playtest.md) | 试玩验证计划、模拟目标、问卷 |
| P4 | [plan/progress.md](plan/progress.md) | 进度日志 |
| P5 | [plan/questions.md](plan/questions.md) | 待用户拍板的问题 |
| — | [prompts/gpt-kickoff.md](prompts/gpt-kickoff.md) | 给 GPT 的启动 / 续跑 / 自查 / 反馈提示词 |

仓库根目录的 [`AGENTS.md`](../AGENTS.md) 是开发者每次开工必须遵守的工作规则。

## 外部参考

- 目录规则、美术与声音的制作方法：<https://github.com/beekim123/rpg2d-dot>（同一作者的项目）。可以参考或改写它的工具代码；它的角色和美术素材属于另一个游戏，不能用。
- 叙事表现：《炉石传说》冒险模式（旁白人物、插画分镜、对手登场、对局台词、可点的牌桌）。只学手法，不复刻。
- 竞品：杀戮尖塔、Monster Train、雪居之地（路线—战斗—奖励循环）；Lost and Found Co.（题材相近，需拉开距离）。
