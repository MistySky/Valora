# SwiftUI 文字缓存首批独立验收

2026-11-07。方向得到局部支持，不能接入生产。

## 保真证据独立核对

读取 `/private/tmp/valora-row-swiftui-fidelity/` 原始图片，独立核验 SHA-256：中文短句参考/新后端均为 `1c00bdd92f4680dc7ecfb6da36172880d255efcea583ca42c7586161ba4b2bad`；逐字半词参考/新后端均为 `c65b5f86799e519139bf393278b5e8b267815de64b10614648b5a39fdd8d1ca7`。两场景逐字节一致的报告属实。

独立查看长句真实滚动的原始两图，仍有细节差异。OC 统计均值 1.96/差异像素 17.3%，本轮没有重跑视觉探针。当前仅有一个滚动位置，不能推出整段动画体感一致。可能涉及浮点位置合成与栅格化时机，不能仅按墨迹框相同确定原因。

## 独立回归发现两类阻断问题

新增 `IndependentSwiftUITextLifecycleTests/testEmptyTimelineClearsPixelsAndStopReleasesCaptureWindow`，仅创建一个隔离原型及其捕获窗口；测试末尾清理该用例新建的窗口。

1. 非空歌词变 nil 时间轴后，`debugLine` 正确清空，但 `debugUsesImageContents` 仍为 true。`buildTextImages` 在空字符串测量失败时直接返回，旧图像继续可见；日志连续两次 render failed。空内容是正常状态，须明确清空当前可见像素、mask、尺寸和缓存状态，不能视为捕获失败并沿用旧字。
2. `stop()` 清空图层 contents，却未关闭捕获 NSWindow 或移除 hosting 内容。独立断言 `debugHostingViewInWindow == false` 失败，新增窗口仍 `isVisible == true`。不能以图像估算字节称整体资源已释放；窗口/hosting 也占资源。

同组复测共 59 用例：57 通过、1 失败（3 个断言）、1 跳过。日志 `/private/tmp/valora-swiftui-fidelity-independent.log`。既有 R4 同步回归继续通过。

## 规定的下一步

先修空内容与 capture-window 生命周期，捕获失败也应显式状态且不遗留旧画面。停止/销毁关闭自有捕获窗口并移除内容，按需恢复只创建必要的一份；不碰用户 App 窗口。

滚动只做定向相位实验：比较相同非整数 offset 下原样与对齐实际像素网格的候选截图，记录实际 offset 和图层位置，验证原 SwiftUI 的落点规则；如果有证据才把该规则移植到后端。禁止任意 round 来掩盖差异，禁止每帧抓图或新建位图。仍有差异则保留未验，不能自动切换方案。

本轮未改生产实现、未替换 App、未控制真实播放；无 CPU 降幅结论。报告中“136 通过、2 跳过”应按 XCTest 总数修正为 134 通过、2 跳过（另一个 ReferenceCore 测试 target 单列）。
