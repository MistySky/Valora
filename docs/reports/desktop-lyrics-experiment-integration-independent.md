# 桌面歌词实验接入：独立验收未通过

2026-11-09。普通与实验 Release 的隔离由 OC 构建证据支持；独立复跑实验条件下 `LyricsRowExperimentIntegrationTests|IndependentNativeLyricsRowTests|IndependentSwiftUITextLifecycleTests`：16 通过、1 跳过、0 失败，日志 `/private/tmp/valora-experiment-independent.log`。这些主要验证选择状态和原型逻辑，不能证明真实宿主布局或回退视图正确。

## 必须返修

1. **回退嵌套宽度错误**：`Sources/Valora/LyricsRowExperiment.swift` 的实验外层 HStack 已包含音符和可用文字区，失败时又在其中嵌入一个 `width: width` 的完整 CompactLyricsView，外层总宽因此大于原行，还将原行的 showsNote 设为 false。该组合不能保证原宽度/对齐/裁剪。修复为在实验行最外层整体替换成与正常生产调用参数完全一致的 `CompactLyricsView`（包括 note、宽度、padding、auditRole），不套第二层 HStack/frame/padding；先卸载实验宿主，避免双时钟。添加真实宿主布局/图片对照与注入抓图失败回归，覆盖有/无音符、长短句和内嵌行。
2. **长行整体对齐不一致**：生产行按 `frame.isLong ? .leading : .center` 设置外框对齐，实验行无条件 `.center`。文字容器宽度在不同硬件与 padding 场景会影响音符/行内容相对于外框的位置，必须直接复用现有规则并比较图像和测得坐标，不能靠“都有同一文字宽”推断相等。逐字短句与长句、带音符/无音符都需要覆盖。
3. **回调与状态竞争**：`onLineChange` 可从 `makeNSView/updateNSView → apply → switchLine` 同步回写 SwiftUI `@State`；需要延后到安全时机并带视图/歌曲代次校验，避免旧行或旧失败回调在切歌后覆盖新状态。`onFailure` 当前异步闭包没有捕获并校验歌曲代次，可能把新歌错误锁定到回退。添加旧回调在切歌后到达、卸载后到达的验证；回调重复不应触发多条 30Hz 链。

长句/emoji 像素差异、动画逐帧、1x 和真实 CPU 仍未验；仅靠 state struct 的 5 个测试不能替代真实宿主场景。未打包/替换运行版。
