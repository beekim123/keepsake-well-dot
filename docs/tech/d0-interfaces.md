# D0 集成约定【建议】

这是实现层接口约定，不改变已定玩法。第一方美术、音频、内容分别生成，再单向同步至 Godot。各条管线独立运行；无外部 Node 依赖。

## 美术

`resources/art/export/manifest.json`：`{"format":"art-manifest/1","assets":[...]}`。
每项：`id`、`file`（相对 export 的 PNG 路径）、`size:[w,h]`（单帧）、`frames`（横排帧数）、`anchor:[x,y]`、`animations:{name:{fps,loop,frames:[]}}`、`hash`（PNG SHA-256）；面板另有 `nineSlice:[left,top,right,bottom]`。
运行副本 `res://resources/art/manifest.json`；PNG 路径是该目录加 `file`。至少提供 `char.asui` 与 `ui.panel.default`。

## 音频

`resources/audio/export/manifest.json`：`{"format":"audio-manifest/1","assets":[...]}`。
每项：`id`、`file`、`sampleRate`、`channels:1`、`frames`（采样数）、`duration`、`loop`、`hash`（WAV SHA-256）和 `metrics`。
运行副本 `res://resources/audio/manifest.json`；WAV 路径是该目录加 `file`。D0 提供 `sfx.ui_click`、`sfx.card_play_attack`、`music.title`（8 秒测试版本，非最终完整曲目）。

## 内容

`content/registry.json`：`{"format":"content/1","files":[{"id":"cards","file":"data/cards.json","target":"cards.json"}]}`。
`file` 相对 content，`target` 相对 godot/data。规则 JSON 文件使用顶层数组；每项都有稳定 id。后续故事 target 可以为 `story/pages.json`。
同步 registry 至 `res://data/registry.json`；最小牌数据至 `res://data/cards.json`。D0 使用四种起始牌定义，不宣称完整 D1 内容已经实现。

## 同步与工具

同步器写 `godot/resource-pack.json`（目标相对路径与 SHA-256）。只清理先前受管理且本次已退出清单的文件，不碰不受管理文件。verify 只读，不构建、不修复文件。
Godot CLI 优先环境变量 `GODOT_BIN`，其次本机 Godot.app / PATH；必须核验实际版本为 4.7.2。不得把云端本机绝对路径写进提交文件。
`npm run godot:test` 使用 `godot/tests/test_runner.gd`；D0 的 sim 只可报告基础烟测，必须明确完整远征模拟尚未进入 D1，不得伪造胜率与试玩时长。
