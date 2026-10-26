# 第一方像素美术 · D0

所有图像均由本仓库字符画或程序绘制；没有外部图像、模型调用或运行时图片输入。`source/` 与 `palette.json` 是唯一真相。`export/` PNG 和清单是需要提交的构建产物，`export/sheets/` 是不进入游戏资源包的审图表。

## 素材索引

| id | 单帧 | 锚点 | 帧 | 用途 |
|---|---|---|---|---|
| `char.asui` | 48×64 | 24,60（脚底） | 4 | 阿穗：麦黄草帽、短辫、深蓝工作服、暖灯。待机含肩部呼吸、手肘/灯笼摆位、眨眼和看灯；脚底保持不动，不是整图上下移动。 |
| `ui.panel.default` | 16×16 | 0,0 | 1 | 深井色面板、麻绳色边框；九宫格边距 `[4,4,4,4]`。 |
| `board.title` | 640×360 | 0,0 | 1 | 原创守绳屋、井口与绞盘的侧视标题背景。左侧留给引擎排字，右侧窗口和提灯为暖色焦点。 |

`char.asui` 的 `idle` 为 4 fps，帧序列 `[0,0,0,1,1,0,0,2,0,0,3,3]`，有停顿。PNG 为 192×64 横排帧；引擎应读清单，不写死这些参数。D0 不包含 play / hurt / win 或 D1 内容美术。

## 命令

在仓库根目录：

```sh
node tools/resources/art.mjs build
node tools/resources/art.mjs verify
node tools/resources/art.mjs sheet
node --test tests/art-pipeline.test.mjs
```

同名 npm 脚本为 `art:build`、`art:verify`、`art:sheet`。Node 工具无第三方依赖；PNG 编解码只用 `node:zlib`，CRC32 为仓库代码。编码不写时间、主机或随机元数据。

- `build` 从 JSON 字符画与 `.mjs` 程序源生成 PNG 和 `art-manifest/1` 清单；旧资源清理仅限上一版清单管理的路径。
- `verify` **只读**：重新绘制两次并逐字节比较、校验 PNG CRC / SHA-256、44 色调色板、0/255 alpha、尺寸、锚点、动画引用、九宫格和内容引用；拒绝未登记 PNG。
- 内容 JSON 的美术字段约定为 `art`、`artId`、`assetId`、`texture`、`textureId`、`backgroundArt`、`portraitArt`。未被内容引用的素材给出警告，可能由表现层直接使用；不把该警告冒充漏图。
- `sheet` 每个 id 生成一张带标签的 **3×最近邻** 审图表。标签是仓库自绘的微型 3×5 字母，只用于审图，不进入游戏图片。游戏文本由引擎和 Fusion Pixel 字体渲染。

## 编辑入口

- `palette.json`：精确的 44 个命名颜色；`.` 为透明，其余字符经 `characters` 映射到命名颜色。
- `source/char/asui.json`：`art/1` 字符画，每帧 64 行、每行 48 字符。直接修改字符源再重建。
- `source/ui/panel.mjs`、`source/board/title.mjs`：程序绘图；使用整数坐标和命名颜色，不调用随机函数。
- `lib/pixel.mjs`：D0 基础绘图、Bresenham 直线、椭圆、多边形、整数盖章、外轮廓、镜像、换色；内部 selout 和左上光源色阶由作者明确绘制，避免噪点与枕头式阴影。
- `lib/png.mjs`：RGBA8 编码、非交错 RGBA8 解码（支持全部五种 PNG 扫描行过滤器）。不是通用第三方图片导入器。

## 清单合同

```json
{
  "format": "art-manifest/1",
  "assets": [{
    "id": "ui.panel.default",
    "file": "ui/panel-default.png",
    "size": [16, 16],
    "frames": 1,
    "anchor": [0, 0],
    "animations": {},
    "nineSlice": [4, 4, 4, 4],
    "hash": "PNG bytes SHA-256"
  }]
}
```

`file` 相对 `export/`；同步器映射到 `godot/resources/art/`。只有面板有 `nineSlice`。帧在 PNG 中横向等宽排列；所有画布锚点和九宫格边距都是整数。

## D0 审图记录

已生成并实际打开 `export/sheets/char.asui.png`、`board.title.png`、`ui.panel.default.png`。检查了草帽/短辫/提灯剪影、稳定的脚部、冷暖焦点、色块和完整轮廓；修补了守绳屋山墙，让屋顶下没有穿透背景的空洞。每张审图表和游戏 PNG 均小于 2 MB。

实际游戏组合、中文排字和按钮反馈仍须由 Godot 标题截图验收；单独审图不替代游戏截图，也不表示 D1 玩法已完成。
