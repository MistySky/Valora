# 桌面歌词实验接入 R2：行切换与外层对齐同步

沿用现有 OC 会话/模型/分支。读 AGENTS.md 与 `docs/reports/desktop-lyrics-experiment-integration-r1.md`。R1 回退和布局宿主测试通过，但 Codex 独立检查发现：`ExperimentalDesktopLyricsView.isLong` 读取 `model.currentLyricLine`，它用 `model.elapsed`，而原生 renderer 按插值时间自行选行。收起状态宿主采样约 1Hz，逐字或边界换句时新文字已显示，外层长短对齐仍可能保持旧行近一个采样周期。生产 SwiftUI 行每帧用同一插值时间决定行和对齐。不得因性能改变显示体验。

## 指定修复

1. 原生行切换回调携带完整 `LyricLine?`，通过已有 generation/identity 保护投递给宿主；宿主以该实际显示行计算 `LyricsLineMetrics` 的 long/short 和无障碍文本。不要从 `model.currentLyricLine` 或旧的 `elapsed` 推断当前显示行。只在真实换行或宽度变化时重新计算/更新状态，不能把 30Hz 状态提升给 SwiftUI。
2. 开始/首次挂载、切歌、失败回退、空行及卸载均清理或更新对应状态；真正逐行变化要与对齐变化在尽量同一显示事务提交，不能引入旧回调竞态。保留 R1 按身份/代次防护与整行回退。若 cannot match timing without extra frame，明确报告并停止，不宣称等价。
3. 新增独立真实宿主测试：恒定的 host anchor、不推送新的 model.elapsed，以可注入时间跨过短→长、长→短边界，验证 native 行和 HStack alignment/音符坐标同时随当前显示行变化；要覆盖带音符和无音符。验证 width 改变、切歌、卸载迟到回调与失败回退；不可只验证一个布尔 helper。
4. 保留锁屏旧路径、普通 release 无实验实现，跑 R1 同组测试和实验构建。真实 1x、动画逐帧、CPU 等未验事实不变。完成报告 `docs/reports/desktop-lyrics-experiment-integration-r2.md` 后停止，不打包启动、替换 App、提交。
