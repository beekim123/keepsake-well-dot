# 唯一外部资源：Fusion Pixel 12px 字体

本项目禁止引入外部美术、声音。字体是设计说明明确允许的唯一例外。

- 作者 / 官方上游：<https://github.com/TakWolf/fusion-pixel-font>
- 发布版：`2026.09.25`，`fusion-pixel-font-12px-proportional-otf.woff2-v2026.09.25.zip`。
- 按设计说明，从同作者项目 [rpg2d-dot](https://github.com/beekim123/rpg2d-dot/tree/84830b12d3d8fada811dd7bba401eb04d062f7af/third_party/fonts/fusion-pixel-12px) 的固定提交 `84830b12d3d8fada811dd7bba401eb04d062f7af` 原样取得字体和四份完整许可证；未取用该游戏任何角色、美术或声音。
- 字体：`fonts/fusion-pixel-12px/fusion-pixel-12px-proportional-zh_hans.otf.woff2`。
- 大小：666,264 bytes；SHA-256：`0ebd99e6f1e9b650a793a3f759c1c3dfa99f0c5b6502e78569b48ddb43767e40`。
- 使用上游压缩 WOFF2 格式而非拆分 / 子集化；原有字形全部保留，单文件低于 2 MB。Godot 4 可直接导入此格式，不需要运行时网络请求。
- 保留 `UPSTREAM-README.md` 记录发布包及哈希；`OFL.txt`、`LICENSES/ark-pixel/OFL.txt`、`LICENSES/cubic-11/OFL.txt`、`LICENSES/galmuri/LICENSE.txt` 全部随字体及游戏分发。

运行时用 12 / 24 px，关闭抗锯齿、hinting、子像素定位、mipmap 与 MSDF。`npm run sync` 将此完整目录复制至 `godot/resources/fonts/fusion-pixel-12px/`。实际 D0 内容的字形覆盖由 Godot 无界面测试校验。
