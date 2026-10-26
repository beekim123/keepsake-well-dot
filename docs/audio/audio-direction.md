# 音乐与音效

## 1 原则【定】

- **所有声音都由仓库里的代码合成。** 源数据是文字（音符、音色参数、包络）；不用录音、不用外部采样、不用任何 AI 音乐/语音服务、不用现成旋律。
- **确定性**：同一份源数据，每次合成的结果逐样本一致。噪声只用带固定种子的伪随机数。
- 做法沿用 <https://github.com/beekim123/rpg2d-dot> 的 `resources/audio/synth.ts`：一个纯 TypeScript 合成器，用音符数组和命名音色渲染出 `Float32Array`；Node 端离线导出 WAV 并做数值检查；游戏只播放导出的 WAV。可以参考或改写它的代码，但**旋律必须为本作重新创作**。

## 2 管线【建议】

```text
resources/audio/cues/*.ts（音符与参数）
  → resources/audio/synth.ts（纯函数 renderCue(id, sampleRate) → Float32Array）
  → tools/resources/audio-pack.ts（量化为 PCM16 WAV + manifest.json）
  → resources/audio/export/（提交）
  → npm run sync → godot/resources/audio/（副本）
  → AudioService（Godot 端只负责播放）
```

| 项 | 规定 |
|---|---|
| 格式 | 单声道 PCM16 WAV |
| 采样率 | 音乐 22050 Hz（控制体积），音效 44100 Hz |
| 单文件 | 小于 2 MB（音乐按完整小节写，约 25–40 秒一轮循环） |
| 响度 | 音乐 RMS −20 ±2 dBFS（整轮），音效 −18 ±3 dBFS（去掉首尾静音后），峰值 ≤ −1 dBFS |
| 循环 | 音乐首尾样本归零，接缝处幅度和斜率检查通过 |
| Godot 导入 | 关闭有损压缩（`compress/mode=0`）；音乐设前向循环，音效不循环 |

`npm run audio:check`：合成两次逐样本比较，报告 SHA-256、峰值、RMS、接缝，任何一项不合格就非零退出。**数值通过不等于好听**，每首曲子都要在游戏里实际听过，在 progress 里写一句听感。

### AudioService（Godot 端）【建议】

- 第一次用户点击后才启声。
- 最多 6 个音效同时播放、2 个音乐播放器交叉淡化（0.6 秒）。
- 主音量、音乐、音效三条总线；总线末端加限幅器（−1 dB）。
- 窗口失焦时静音，回来后恢复正在放的音乐。

## 3 音色【建议】

温暖的芯片音乐，加一点民谣感（拨弦、笛子），井底场景加回声。

| 音色 | 做法 | 用途 |
|---|---|---|
| 拨弦 | Karplus-Strong（固定种子噪声激励） | 主旋律、伴奏，像鲁特琴或吉他 |
| 笛子 | 正弦基音 + 少量二、三次谐波 + 轻微颤音 | 标题、归还 |
| 柔和方波 | 25% / 50% 占空比 + 低通 | 战斗旋律 |
| 三角波 | — | 低音 |
| 八音盒 | 双算子 FM，快起慢衰 | 归还故事、心愿完成 |
| 噪声鼓 | 固定种子噪声 + 滤波 + 包络 | 鼓、泡泡、泥水声 |
| 回声 | 多抽头延迟 | 下井、井底 |

## 4 主题动机「井绳谣」【建议】

全游戏共用一个 4 小节动机，所有曲子都是它的变奏。意象：**先往下走，最后回到上面**——前两小节下行（下井），末小节往上收（收绳回家）。

下面是一个原创的示例动机（4/4 拍，数字为八分音符个数，每小节合计 8），开发者可以改写，但要保留"下行—回升"的轮廓，并在 `resources/audio/README.md` 里写清最终版本：

```text
A1 | A4×2 G4×1 E4×1 D4×4          |  往下
A2 | E4×2 G4×1 A4×1 C5×2 A4×2     |
A3 | G4×2 E4×1 D4×1 C4×2 D4×2     |  到底
A4 | E4×1 G4×1 A4×2 D5×4          |  一下子回到上面
```

## 5 曲目表（Demo）

| id | 曲名 | 用在哪 | 情绪 | BPM | 主题处理 |
|---|---|---|---|---|---|
| `music.title` | 井绳谣 | 标题、守绳手账 | 怀旧、期待 | 76 | 笛子完整演奏动机，拨弦分解和弦 |
| `music.hut` | 守绳屋 | 据点 | 温暖、闲适 | 96 | 拨弦领奏，轻八音盒点缀 |
| `music.descent` | 下井 | 路牌画面、事件、篝火 | 好奇、空旷 | 84 | 动机只用前两小节，大量回声，偶尔水滴 |
| `music.battle` | 袜沼一战 | 普通战、精英 | 轻快、滑稽 | 132 | 方波切分节奏化，低音蹦跳，轻鼓 |
| `music.boss` | 九百九十九 | 千袜蛇 | 紧张、执拗 | 144 | 动机改小调，持续的八分音符重复（像在数数） |
| `music.return` | 物归原主 | 归还插画页 | 温柔、释然 | 72 | 八音盒演奏动机，末句完整落回主音 |
| `music.ending` | 回头结 | Demo 结尾（可选，可先用 `music.return`） | 思念、决心 | 80 | 笛子独奏，最后一小节停在不完整的音上 |

### 短乐句

| id | 用途 | 长度 |
|---|---|---|
| `sting.victory` | 战斗胜利 | ~1.5 秒 |
| `sting.defeat` | 战败 | ~1.5 秒 |
| `sting.reward` | 三选一出现 | ~0.8 秒 |
| `sting.keepsake` | 拿到信物 | ~2 秒 |
| `sting.wish` | 心愿完成 | ~1.2 秒 |
| `sting.stamp` | 复刻牌盖章 | ~0.6 秒 |
| `sting.boss_warn` | 首领大招预告 | ~1 秒 |

## 6 音效表（Demo）

| 分组 | id |
|---|---|
| 界面 | `sfx.ui_hover`、`sfx.ui_click`、`sfx.ui_cancel`、`sfx.ui_deny`、`sfx.page_turn`、`sfx.panel_open` |
| 卡牌 | `sfx.card_hover`、`sfx.card_pick`、`sfx.card_play_attack`、`sfx.card_play_guard`、`sfx.card_play_special`、`sfx.draw`、`sfx.shuffle`、`sfx.discard` |
| 战斗 | `sfx.hit_small`、`sfx.hit_big`、`sfx.guard_gain`、`sfx.guard_break`、`sfx.heal`、`sfx.intent_reveal`、`sfx.enemy_poof`、`sfx.end_turn`、`sfx.relic_proc` |
| 路线 | `sfx.path_flip`、`sfx.rope_creak`（下降一格）、`sfx.rope_pull`（收绳） |
| 牌桌彩蛋 | `sfx.frog`、`sfx.bubble_pop`、`sfx.clothesline`、`sfx.reed`、`sfx.sock_avalanche`、`sfx.yarn_roll` |

### 说话音（逐字音）

不做配音。每个说话人一种短音，文字逐字出现时每 2 个字响一次，音高在一个小范围内按字的顺序确定性起伏。

| 说话人 | 音色与音高 |
|---|---|
| 阿穗 | 明亮短脉冲，中高音 |
| 麻爷 | 低沉三角波，带一点颤，像老人咳嗽前的嗓子 |
| 麦婶 | 温暖方波，中音，节奏快 |
| 豆丁 | 高音正弦，短促 |
| 信伯 | 柔和拨弦，中低音，节奏慢 |
| 棉棉 | 很高的 FM 吱吱声 |
| 千袜蛇 | 低音脉冲 + 一点嘶嘶噪声 |
| 饿抽屉 | 木头敲击声（只在"嚼"的时候） |
| 旁白 | 不出声 |
