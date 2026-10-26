# 仓库目录与模块边界

本仓库按"制作职责"分目录，参考 <https://github.com/beekim123/rpg2d-dot> 的做法（同一作者的另一个项目）：**美术、声音、内容数据、游戏源码、设计文档各自独立**，任何一块都可以整个目录拷走，单独使用或交给别人维护。

## 1 目录总览【定】

```text
<仓库根>/
├─ AGENTS.md                 开发者（GPT）工作规则
├─ README.md                 项目简介、运行方式、目录说明
├─ package.json              只放 Node 工具脚本（美术/声音构建、内容检查、同步）
├─ .gitignore
│
├─ docs/                     设计文档（本目录）
│
├─ resources/                第一方美术与声音的唯一制作源
│  ├─ art/
│  │  ├─ README.md           素材索引：id、尺寸、锚点、帧、用途
│  │  ├─ palette.json        主调色板（字符 → 颜色）
│  │  ├─ lib/                绘图库：png.mjs（PNG 编解码）、pixel.mjs（整数像素画布）
│  │  ├─ source/<分类>/      字符画 *.json、程序绘图 *.mjs
│  │  └─ export/             构建产物：PNG、manifest.json、sheets/ 审图对照表（提交）
│  └─ audio/
│     ├─ README.md           曲谱说明（音名、和声、编配）与音效设计表
│     ├─ synth.ts            纯确定性合成器（不依赖浏览器、Godot、游戏状态）
│     ├─ cues/               每首曲子/每个音效的音符与参数数据
│     └─ export/             构建产物：WAV（PCM16）+ manifest.json（提交，单文件 < 2 MB）
│
├─ content/                  游戏内容数据的唯一制作源（与引擎无关的 JSON）
│  ├─ registry.json          所有内容文件的登记表
│  ├─ data/                  规则数据：卡牌、敌人、奇物、地点、事件……
│  └─ story/                 叙事数据：插画页、台词、触发表
│
├─ godot/                    Godot 4 工程（游戏源码）
│  ├─ project.godot
│  ├─ scenes/                场景与界面
│  ├─ scripts/
│  │  ├─ core/               纯规则：状态、结算、随机数；不依赖节点、图片、声音
│  │  ├─ content/            读取 data/ 并转成规则对象
│  │  ├─ view/               表现层：把规则产出的事件播成动画
│  │  ├─ story/              插画页播放器、台词调度
│  │  ├─ services/           AssetCatalog（语义 id → 资源）、AudioService、SaveService
│  │  └─ debug/              调试面板、作弊指令（只在调试版启用）
│  ├─ tests/                 Godot 无界面测试与自动试玩
│  ├─ resources/             【自动同步副本】美术、声音、字体，禁止手改
│  ├─ data/                  【自动同步副本】content/ 的拷贝，禁止手改
│  └─ resource-pack.json     【自动生成】受管理文件清单与哈希
│
├─ tools/
│  ├─ resources/             art.mjs（build/verify/sheet）、audio-pack.ts、sync-godot.mjs
│  ├─ qa/                    content-check（引用、数值范围、可达性）、内容统计
│  ├─ godot/                 cli.mjs：找到 Godot、运行、无界面测试、导出
│  └─ lib/                   工具共用的路径定义
├─ tests/                    Node 端测试：资源管线、内容检查
├─ third_party/fonts/        OFL 字体（Fusion Pixel）及完整许可证——唯一允许的外部资源
├─ artifacts/screenshots/    已检查过的截图、录屏（提交，可分享）
├─ workbench/                （可选，D3 之后）独立 HTML 素材展示器
└─ build/                    导出产物（忽略，不提交）
```

本机文件不提交：`Godot.app`（或其它平台的编辑器）、`godot/.godot/` 缓存、`build/`、`.cache/`、`.local/`。

## 2 单向依赖【定】

```text
resources/art/source ─build→ resources/art/export ─┐
resources/audio/cues ─build→ resources/audio/export ┼─ sync → godot/resources + godot/data → AssetCatalog → view
content/                                           ─┘
                                                       godot/scripts/core（只读 data，不碰资源）
```

- **规则不依赖表现**：`scripts/core/` 只依赖内容数据和自己的状态；不 `load()` 图片、不播放声音、不引用场景节点。规则函数输入状态和玩家指令，输出新状态和**事件列表**，表现层再把事件播成动画。这样规则能在无界面测试里跑成千上万局。
- **表现用语义 id 取资源**：界面代码写 `AssetCatalog.texture("enemy.sock_snake")`，不写 PNG 路径。只有 AssetCatalog 知道文件在哪。
- **Godot 里的资源和数据都是副本**：改美术去 `resources/art/source/`，改声音去 `resources/audio/`，改数值和剧情去 `content/`，然后 `npm run sync`。直接改 `godot/resources/` 或 `godot/data/` 会在下一次同步时被覆盖，校验也会报错。
- **美术和声音不依赖游戏**：`resources/` 里的代码不 import `godot/` 或 `content/` 的任何东西。

## 3 修改入口速查

| 想改什么 | 去哪里改 | 之后运行 |
|---|---|---|
| 一张图、一套动画 | `resources/art/source/` | `npm run art:build && npm run art:verify && npm run art:sheet`，看对照表，再 `npm run sync` |
| 调色板 | `resources/art/palette.json` | 同上，全部素材重建 |
| 一首曲子、一个音效 | `resources/audio/cues/` | `npm run audio:build && npm run audio:check`，再 `npm run sync` |
| 数值、卡牌、敌人、事件 | `content/data/` | `npm run content:check`，再 `npm run sync` |
| 台词、插画页、旁白 | `content/story/` | 同上 |
| 玩法规则 | `godot/scripts/core/` | `npm run godot:test` |
| 界面、动画、演出 | `godot/scenes/`、`godot/scripts/view/` | `npm run dev` 实际看 |

## 4 同步器

`tools/resources/sync-godot.mjs`：
1. 读取 `resources/art/export/manifest.json`、`resources/audio/export/manifest.json`、`content/registry.json`。
2. 只复制清单里登记的文件到 `godot/resources/`、`godot/data/`，字体连同许可证复制到 `godot/resources/fonts/`。
3. 写 `godot/resource-pack.json`：每个文件的语义 id、相对路径、SHA-256。
4. 清理只删除上一版 `resource-pack.json` 里登记过、这一版不再需要的文件，不碰其它文件。
5. `--verify` 只读校验：副本和源逐字节一致，否则非零退出。

## 5 抽离规则

- 拷走 `resources/art/`：带走 `palette.json`、`lib/`、`source/`、`export/` 和 `tools/resources/art.mjs`，即可独立构建与审图。
- 拷走 `resources/audio/`：带走 `synth.ts`、`cues/`、`export/` 和 `tools/resources/audio-pack.ts`，即可独立合成与检查。
- 拷走 `content/`：纯 JSON，加上 `tools/qa/content-check` 即可独立检查。
- 拷走 `godot/`：自带同步副本，可以直接用 Godot 打开运行。
- 拷走 `docs/`：纯 Markdown。

## 6 文件规范

- 单个文件不超过 2 MB。
- 文本统一 UTF-8、LF 换行。
- 内容 id 用小写英文加点或下划线：`card.knock`、`enemy.wet_sock`、`story.return.ring`。
- 不提交密钥、本机绝对路径、第三方截图。
