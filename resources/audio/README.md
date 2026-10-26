# 《拾遗井》声音制作源 · D0

这里只有 **3 个 D0 管线验收声音**，不是 D2 完整配乐。全部由本目录原创文字曲谱、音色参数和纯 TypeScript 代码生成；没有录音、外部采样、现成旋律、音乐/语音生成模型或第三方 DSP 依赖。

## 构建与验证

需要 Node.js 22.13+（本次实测 24.22.1）。从仓库根运行：

```sh
node --experimental-strip-types tools/resources/audio-pack.ts build
node --experimental-strip-types tools/resources/audio-pack.ts check
node --experimental-strip-types --test tests/audio*.mjs
# package.json 集成后也可运行 npm run audio:build / npm run audio:check
```

`build|check` 都支持 `--out <目录>`，可在隔离临时目录做测试。`build` 写入 3 个 WAV 和 `manifest.json`；`check` **只读**，不会重建、修复或掩盖损坏文件。校验比较源合成结果、实际 WAV 字节、SHA-256、规范化清单及已登记 WAV 集合；旧输出、额外 WAV、缺失文件与篡改都非零退出。

抽离本管线只需复制 `resources/audio/`、`tools/resources/audio-pack.ts`，保留相对目录结构。测试另在 `tests/audio-pipeline.mjs`。不依赖美术、内容或 Godot 状态。

## 纯合成 API

```ts
import { cueIds, cueSpec, renderCue } from './synth.ts';
const pcm: Float32Array = renderCue('music.title', 22050);
```

- `renderCue(id, sampleRate)` 每次返回独立缓冲区。未知 id、非整数或不在 8000–96000 Hz 的采样率抛错。
- 音乐默认导出 22050 Hz；音效默认导出 44100 Hz。采样数由时长 × 采样率四舍五入得到。
- 噪声为每次调用重新初始化的 xorshift32 固定种子；不使用 `Math.random()`、日期、外部服务或全局可变振荡器状态。
- `cues/` 是音符和参数的唯一源；`synth.ts` 不做文件读写。Node 工具只负责检验、PCM16 量化、RIFF/WAV 和清单。
- 导出全部为小端单声道 PCM16；`hash` 是完整 WAV 的 SHA-256，`sampleHash` 是量化前逐样本 Float32 LE 字节的 SHA-256。

## 原创动机「井绳谣」D0 试奏

**4/4，120 BPM，4 小节共 8 秒；数字表示八分音符个数，每小节合计 8。** 这是为 D0 八秒测试而写的短版；设计中的正式标题曲仍计划 76 BPM，后续 D2 发展成完整循环，不宣称已完成正式曲目。

```text
T1 | A4×2 G4×1 F4×1 E4×2 D4×2  |  顺着井绳下行
T2 | G4×2 E4×2 D4×1 C4×1 A3×2  |  再向深处，抵达低点
T3 | C4×2 D4×1 E4×1 G4×2 E4×2  |  看见回家的方向
T4 | E4×1 G4×1 A4×2 D5×4       |  收绳，向上回来
```

最后的 D5 比开头 A4 高，保留「下行—回升」轮廓。主旋律为带轻微延迟颤音的正弦笛子，少量二、三次谐波；每小节短低音支撑。四组分解和声：Dm(add9)、C、Am7、Dsus2，四分音符拨弦分别为：

```text
D3 A3 E4 F4 | C3 G3 E4 G3 | A2 E3 G3 C4 | D3 A3 E4 A3
```

拨弦采用固定种子噪声激励的分数延迟 Karplus–Strong；种子基值 `0x57454c4c`，按小节与音符序号派生。音符均有软起、软收，尾音不跨过八秒边界。首尾预留毫秒级呼吸并应用余弦包络，避免机械截断；不以无限延长或丢掉样本伪造循环。

力度由每小节重音、声部增益和包络主动设计。`title.gain = 0.82` 是一次固定编配选择，不依赖测得 RMS；构建器**不做自动归一化、压限或削波修补**，改坏的源会直接校验失败。

## 音效设计

| id | 文件 | 长度 | 设计与固定种子 |
|---|---|---:|---|
| `sfx.ui_click` | `sfx_ui_click.wav` | 0.100 s | 1480→1020 Hz 的短木质点音，加轻次谐波与极少噪声；种子 `0x434c4943`，固定增益 0.53 |
| `sfx.card_play_attack` | `sfx_card_play_attack.wav` | 0.280 s | 250→80 Hz 软冲击 + 低通噪声扫过，像纸牌落桌而非武器/血肉；种子 `0x43415244`，固定增益 0.57 |
| `music.title` | `music_title.wav` | 8.000 s | 上述原创笛子、拨弦、低音动机；仅此项循环 |

## 验证定义与实测

每次构建/校验对每个 cue 独立合成两次，逐样本 `Object.is` 比较，再比较 Float32 哈希和 PCM16 WAV 字节。以下质量门分别检查量化前源和量化后实际播放样本；清单记录后者，避免只检测一个未导出的理想波形。

- 所有样本有限、无越界；峰值 ≤ −1 dBFS；每个文件严格小于 2,000,000 字节。
- 音乐整轮 RMS −20 ±2 dBFS；音效 active RMS −18 ±3 dBFS。
- active 区间以绝对幅度 ≥0.001（−60 dBFS）的首、末样本界定；只去除外部静音，**不删除内部停顿**。
- 音乐首尾样本必须精确为零；首尾各 2 ms 最大幅度 ≤0.01，窗口内最大相邻样本差 ≤0.001，首尾一阶斜率差 ≤0.001。音效不是循环，不套用音乐接缝限制。
- 测试包含清单路径/id/指标/哈希篡改、WAV 样本篡改、坏头、截断、额外 WAV、缺失文件、非法 cue/采样率、超大文件和不合格响度/接缝。失败 check 不修复文件。

Node 24.22.1 本次 PCM16 实测（dBFS，四舍五入显示）：

| cue | 采样率 | 样本数 | 字节数 | 峰值 | 整轮 RMS | active RMS |
|---|---:|---:|---:|---:|---:|---:|
| `music.title` | 22050 | 176400 | 352844 | −11.061 | −20.056 | −20.035 |
| `sfx.ui_click` | 44100 | 4410 | 8864 | −6.428 | −17.523 | −17.461 |
| `sfx.card_play_attack` | 44100 | 12348 | 24740 | −7.596 | −18.558 | −18.445 |

音乐首尾样本、2 ms 边缘幅度、边缘斜率和跨缝斜率差均为 **0**。精确指标与完整哈希见 `export/manifest.json`，构建/校验命令同时打印。

**听感状态：未试听。** 当前执行器未提供可确认听觉播放的工具；数值通过不能替代游戏内试听，也不能证明循环节奏和音色已经好听。后续须在游戏里实际听过后记录：短动机是否温暖、反复循环是否突兀、两种音效是否清楚且不刺耳。

## Godot 接口（运行侧负责）

`npm run sync` 将清单和 WAV 单向复制到 `godot/resources/audio/`，此处不直接修改副本。运行侧用语义 id 查清单，设置无损导入 `compress/mode=0`，仅 `music.title` 前向循环。首次点击启声、主/音乐/音效总线、音效并发上限与淡入淡出属于 AudioService，不放在源合成器里。
