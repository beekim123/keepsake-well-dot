# 素材来源与许可说明

## 字体

Fusion Pixel 12px，作者及上游：[TakWolf / fusion-pixel-font](https://github.com/TakWolf/fusion-pixel-font)，版本 `2026.09.25`。字体文件保持原样，未做子集化。

完整许可随文件保留在 `resources/fonts/fusion-pixel-12px/`：

- `OFL.txt`
- `LICENSES/ark-pixel/OFL.txt`
- `LICENSES/cubic-11/OFL.txt`
- `LICENSES/galmuri/LICENSE.txt`
- `UPSTREAM-README.md`：版本、官方来源与原始哈希。

分发字体时应同时保留这些许可及通知。

## 美术

运行资源清单位于 `resources/art/manifest.json`，其中含语义 ID、文件位置、尺寸及 SHA-256。当前低细节 AI 美术、V2 卡牌及此前已接入的生成素材来自 2026-10-26 的 OpenAI 内置 `image_gen.imagegen`；工具未返回具体模型名。项目助手负责提示词及裁切、最近邻适配、色板映射等技术整理。必要的兼容性资源仍包含早期项目原创代码绘图，不把全部历史纹理说成 AI 生成。

素材源记录引用 [OpenAI Terms of Use](https://openai.com/policies/terms-of-use/) 和 [Service Terms](https://openai.com/policies/service-terms/)；适用条款与第三方权利仍须遵守。本说明不保证输出具有版权、独占性或不存在第三方权利。没有加入购买的或未知授权的第三方图包。

制作原图、提示词、未使用候选、旧方案及完整历史来源记录仍保存在原工作仓库，本干净工程只保留运行需要的资源，不重复装入这些制作资料。

## 音频

`resources/audio/manifest.json` 列出本项目原创程序合成的音乐、音效与短提示音；本包保留原 WAV 字节、采样率和音质。未加入第三方录音、现成旋律或语音服务输出。运行所需音频已包含，不需要另行生成。

本文件是来源通知，不授予项目代码或原创素材额外的开源许可证；字体许可仅适用于对应字体。
