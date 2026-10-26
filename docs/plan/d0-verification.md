# D0 地基验收

2026-10-26：D0 通过，进入 D1。这里只验证基础管线与标题，不声称完整游戏可玩。

- `npm ci`：零外部 Node 依赖，锁文件可用。
- `npm run check`：58 个 Node 测试、45 个 Godot 测试通过；美术 3 项、音频 3 项、内容 18 条、同步 17 文件检查通过。
- `sim --quick`：仅 4 个基础规则烟测通过，明确 `full_simulation_implemented=false`；完整远征胜率和时长留待 D1。
- 实际 Godot 为 4.7.2；错误 PATH 版本会被工具拒绝。
- 首次原生运行默认 ALSA 输出设备不可用，保留在本机调试记录；最终截图运行显式指定 Dummy，除 llvmpipe 不支持 VSync 切换的环境警告外无引擎错误。未声称已实际听音。
- 在云端可见窗口手动点标题按钮打开手账，按 Esc 返回标题，正常关闭 exit 0。随后以可见窗口截图模式保存真实视口。
- 自查原始 640×360 与 3 倍最近邻截图：中文无缺字、无溢出，角色/井口/面板边缘清楚，待机有独立帧变化。桌面尺寸不足以容纳 1920×1080 窗口，3 倍图为真实逻辑视口的整数放大，不是 3 倍物理窗口截图或概念稿。

## 证据

- `artifacts/reports/d0-check.log`、`artifacts/reports/d0-summary.json`
- `artifacts/screenshots/d0-capture.json` 与两组原图/3 倍展示图
- `resources/art/export/sheets/` 三张审图表（已实际查看）
- `resources/audio/README.md` 的曲谱、数值检查与未听音范围

## 建议实现决定

- D0 标题背景为额外的原创建立气氛素材，不扩展玩法。
- Fusion Pixel 使用上游完整 WOFF2 文件，保留全部许可，无子集化，低于 2 MB。
- D0 `music.title` 仅为 8 秒测试动机；D2 将提供完整标题曲，不把测试曲当最终音频。
- QA 的 HOME/XDG 固定在忽略的本机测试目录，避免继承不可写用户目录；测试明确捕获 Godot exit0 但输出 ERROR 的情况。

## 未验证

D1 的战斗、七段路线、三委托归还、首领、完整模拟；D2 正式叙事美术和听感；D3 macOS 导出与干净机器试玩。
