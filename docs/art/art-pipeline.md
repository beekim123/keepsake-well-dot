# 美术管线：用代码画像素，导出 PNG

【定】**所有图片都由本仓库的代码绘制，导出成 PNG 提交进仓库，游戏只读取这些 PNG。** 不调用任何图片生成模型，不使用外部图片素材，不描摹任何现成作品。

做法沿用 <https://github.com/beekim123/rpg2d-dot>（同一作者的仓库）的 `resources/art/` 与 `tools/resources/art.mjs`：源数据用文字保存 → 工具构建 PNG 和清单 → 逐字节校验 → 生成审图对照表。如果能访问那个仓库，可以直接参考或改写它的 `resources/art/lib/png.mjs`（零依赖 PNG 编解码）和 `pixel.mjs`（整数像素画布）。**它的角色、PNG 素材属于另一个游戏，不要拿来用。**

## 1 原则【定】

1. **源数据是唯一真相**。PNG 是构建产物，可以随时重新生成，两次生成逐字节一致。
2. **PNG 和清单提交进仓库**，不先构建美术也能运行游戏。
3. **清单驱动**：游戏只通过 `manifest.json` 找素材，不在代码里写死路径和帧数。
4. **只用调色板颜色**，alpha 只有 0 和 255（不做半透明像素；需要淡入淡出由引擎调整节点透明度）。
5. **不能用 `Math.random()`**，只能用带种子的伪随机数（mulberry32 之类）或坐标哈希。
6. 不读取任何外部图片文件。

## 2 三种源数据

### 2.1 字符画（人物、敌人、头像、图标、卡面小图）

```json
{
  "format": "art/1",
  "id": "enemy.wet_sock",
  "category": "enemy",
  "size": [32, 32],
  "anchor": [16, 32],
  "animations": {
    "idle":   { "fps": 4,  "loop": true,  "frames": [0, 1, 0, 2] },
    "attack": { "fps": 12, "loop": false, "frames": [3, 4, 5, 6] },
    "hurt":   { "fps": 10, "loop": false, "frames": [7, 8] }
  },
  "frames": [
    ["................................", "..........AAAA.................."]
  ]
}
```

每帧是一组等长字符串，每个字符对应 `palette.json` 里的一个颜色，`.` 是透明。**关键角色、首领、头像建议逐像素写字符画**，质量最可控。

### 2.2 程序绘图（背景、牌桌、卡框、界面面板、特效、插画页）

一个 `.mjs` 文件导出若干素材：

```js
export const assets = [{
  meta: { id: 'board.sock_swamp', category: 'board', size: [640, 360], anchor: [0, 0], frames: 1 },
  draw(g, { frame, seed }) {
    g.fill('night1');
    g.speckle({ color: 'moss1', density: 0.06, cluster: 3, seed });
    // ……
  },
}];
```

`g` 是 `lib/pixel.mjs` 的 `PixelCanvas`。

### 2.3 组合与换色（同一底图的多个变体）

- 部件叠加：底图 + 若干部件精灵按图层盖章，再统一描边。
- 换色表：同一张源图通过 `recolor({from: to})` 导出多种配色（敌人变种、受击闪白、冬/春两季等）。换色结果也要逐字节确定。

## 3 绘图库【建议】

`resources/art/lib/pixel.mjs`，所有坐标都是整数，所有颜色都是调色板名字：

- 基础：`px`、`rect`、`line`（Bresenham）、`ellipse`、`polygon`、`stamp`（把另一张精灵画上来）、`text`（只用于审图表标注，不用于游戏内文字）
- 像素风专用：
  - `outline(color)`：沿不透明区域外圈自动描边
  - `selout`：选择性描边（外圈用深色，内部线条用本色暗一阶）
  - `shade(region, ramp, light='top-left')`：按左上光源上两三阶明暗
  - `speckle`：成簇的斑点纹理
  - `dither(pattern)`：Bayer 网点过渡
  - `mirror`：左右镜像
  - `recolor(map)`：换色
  - `dissolve(mask, t, seed)`：确定性溶解（做融化、显影这类逐帧动画）
- 界面：`nineSlice` 面板（导出时记录四边边距）

## 4 构建、校验、审图

```sh
npm run art:build    # source → export/*.png + export/manifest.json
npm run art:verify   # 重新绘制并逐字节比较；检查调色板、alpha、尺寸、锚点、动画帧引用
npm run art:sheet    # 生成 export/sheets/*.png 对照表（3 倍最近邻放大，带 id 标注）
```

`manifest.json` 每项记录：`id`、`file`、`size`（单帧尺寸）、`frames`（帧数，PNG 横向等宽排列）、`anchor`、`animations`、`nineSlice`（界面面板才有）、`hash`（PNG 的 SHA-256）。

`verify` 至少检查：
- PNG 与源重新绘制的结果逐字节一致；
- 没有调色板以外的颜色，没有半透明像素；
- 帧尺寸、锚点合法；动画引用的帧存在；
- `content/` 里引用的每个美术 id 都在清单里（没有缺图）；
- 清单里没被任何地方引用的素材给出警告。

## 5 审图流程【定】

每做完一批美术：
1. `art:build` → `art:verify` → `art:sheet`。
2. **自己打开对照表看图**（运行环境能看图就一定要看），逐条对照 `art-direction.md` 的自查清单。
3. 在游戏里截图（`artifacts/screenshots/`），确认放在牌桌上、和文字放在一起的实际效果。
4. 有问题改源数据重建；在 `docs/plan/progress.md` 记录这批素材和对照表路径。

用户的美术意见优先于 `art-direction.md` 里的【建议】。

## 6 字体

使用 Fusion Pixel 12px（OFL-1.1，支持简体中文）。从 rpg2d-dot 的 `third_party/fonts/fusion-pixel-12px/` 拷贝字体文件和**全部许可证文件**，上游是 <https://github.com/TakWolf/fusion-pixel-font>。Godot 里关闭抗锯齿、关闭 hinting、整数像素对齐；字号只用 12（正文）和 24（12 的整数倍放大，用于大标题）。游戏内文字一律由字体渲染，不画进图片（插画里的招牌之类装饰字除外）。

## 7 动画规范

- 所有运动都画进 PNG 帧里；运行时只选帧、移动节点位置，不做旋转、缩放、扭曲像素（整体弹跳、抖动、位移可以，但位移必须是整数像素）。
- 待机：2–4 个姿势，4 fps，带停留的循环（例如 `[0,0,0,1,1,0,0,2]`），不要不停晃动。
- 攻击/受击：一次性动画，最后一帧回到待机姿势。
- 特效：一次性动画，最后一帧完全透明。
- 多个同类物体的待机按位置错开相位，避免整齐划一地同步摆动。
