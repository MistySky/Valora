# Pi 切歌因果核查独立验收

结论：接受为只读排查材料，不接受为根因定位完成或修复交付。未运行测试、未构建、未替换、未修改生产代码。

## 已复核

- `TransitioningArtwork.swift` 与 `ReferenceCore/ArtworkTransitionState.swift` 相对 main 无差异；这只能排除这些文件的直接参数修改，不能证明实际触发和视觉效果等价。
- 当前 `ExperimentalDesktopLyricsView.onDisappear` 调用 `host.invalidate()`；后者关闭 `textPreparer`。再次准备文字会创建离屏 NSWindow 并 `orderFrontRegardless()`。这是新增生命周期链路，尚无可见闪烁的因果证据。
- `Models.presentationSize` 的 quickPeek 仍依赖 `showsCompactLyrics`，后者依赖 `lyrics.hasTimedLyrics`；加载态和可用态可能改变外层高度。此几何分支相对 main 未改，不能归罪于本批新增。
- `NotchView` 的黑色 shape 与外层裁切使用该尺寸。因此，“main 本来如此”不能替代用户最新的固定外轮廓要求。

## 不通过项

1. 主报告没有补齐用户随后明确的外轮廓约束；对应补充任务仍在 request.json，未发现 receipt，不能声称 Pi 已执行。
2. 缺少同一交互状态下短短、短长、长短、空行及整曲 loading→ready 的外轮廓 bounds/path/scale/整体透明度证据。歌词内部文字或音符的像素测试不能替代此项。
3. 新离屏窗口链、主线程封面准备与整块闪动之间仍是假设。报告的恢复建议只能作为待验证方案，不能直接称为已确认根因。
4. 没有 main/build26 与候选的单实例同条件可见回归；报告中的运行进程状态仅代表报告采集时刻，不代表验收时刻。

## 后续边界

先将歌词内容状态与外部呈现几何的依赖区分清楚，补充有限的外轮廓回归证据；明确整曲加载的旧行为与用户新要求之间的冲突及最小方案，再决定生产修复。不冻结主动悬停、展开/收起，不改封面翻转，不靠停动画或降帧率掩盖。内存优化继续暂停。
