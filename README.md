# 拾遗井（暂定名）

> 每一趟下井，都知道自己是为谁下去的。

低难度的短途卡牌远征，2D 像素风，用 Godot 4 制作。你是枣花镇老井的新任守绳人，顺着会说话的老麻绳「麻爷」下到井底，替镇上的人找回他们最惦记的东西。找到的信物这一趟可以借来用，回到井口必须物归原主，换回一段故事和一张永久新牌。

当前阶段：**核心玩法 demo**（第 1 层「袜沼」，3 个委托，约 45–70 分钟）。

## 当前状态

D0 地基已完成：可运行标题与守绳手账预览，资源管线与基础测试通过。**完整战斗、远征与归还尚未接通，不能作为可玩 Demo 验收。** 当前证据见 [D0 验证](docs/plan/d0-verification.md)，继续从 [设计文档](docs/README.md) 与 [任务池](docs/plan/backlog.md) 查看 D1 工作。

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

## 运行与检查（D0）

需要 Node.js 22.13+ 和 Godot 4.7.2。

```sh
npm ci
npm run sync
npm run dev
```

Node 工具不依赖第三方包。若 PATH 不是 Godot 4.7.2，请设置 `GODOT_BIN` 指向正确可执行文件，或把 macOS `Godot.app` 放在仓库根目录（不提交）。工具会验证真实版本，不静默使用旧版。也可以用 Godot 4.7.2 直接打开 `godot/project.godot`，资源副本已经生成。

```sh
npm run check
npm run art:sheet
```

D0 的 `npm run sim` 只报告基础烟测，不含完整远征或胜率。首次点击才解锁音频；云端无音频设备的截图不代表实际听感通过。
