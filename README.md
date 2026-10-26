# 拾遗井（暂定名）

> 每一趟下井，都知道自己是为谁下去的。

低难度的短途卡牌远征，2D 像素风，用 Godot 4 制作。你是枣花镇老井的新任守绳人，顺着会说话的老麻绳「麻爷」下到井底，替镇上的人找回他们最惦记的东西。找到的信物这一趟可以借来用，回到井口必须物归原主，换回一段故事和一张永久新牌。

当前阶段：**核心玩法 demo**（第 1 层「袜沼」，3 个委托，约 45–70 分钟）。

## 当前状态

尚未开工，只有设计文档。从 [docs/README.md](docs/README.md) 开始读；开发规则见 [AGENTS.md](AGENTS.md)。

## 目录

| 目录 | 职责 |
|---|---|
| [`docs/`](docs/README.md) | 设计文档、计划、进度 |
| `resources/art/` | 美术制作源（代码绘制的像素图）与导出的 PNG |
| `resources/audio/` | 声音制作源（代码合成）与导出的 WAV |
| `content/` | 游戏内容数据（卡牌、敌人、事件、剧情、台词） |
| `godot/` | Godot 工程（游戏源码）；其中 `resources/`、`data/` 是自动同步副本 |
| `tools/`、`tests/` | 构建、校验、同步工具与测试 |
| `third_party/fonts/` | OFL 字体及许可证 |
| `artifacts/screenshots/` | 已检查的截图 |

详细规则见 [docs/tech/repository-layout.md](docs/tech/repository-layout.md)。

## 运行（开发开始后补全）

需要 Node.js 22.13+ 和 Godot 4.7.2。

```sh
npm ci
npm run sync
npm run dev
```
