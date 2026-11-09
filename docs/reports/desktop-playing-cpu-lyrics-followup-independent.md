# 歌词补充批独立验收：不通过

2026-11-06。当前进程PID44468运行 /private/tmp/valora-lyrics-followup-r3-candidate/Valora.app，build29，二进制SHA256 fd158980f80e15e3041a3415cd8c176171e1e636f1994c00905cec90384b2822，与报告候选一致。用户反馈表现仍基本一样，不能再解释为未替换新包。

## 已复现问题

P2：CompactLyricsView.swift 的 LyricsLineFrameCache.lineEndStillValid 仅比较行数与旧nextIndex处的起点；不能证明新时间轴中该位置仍是当前行的第一个后继。

- 当前行10秒；旧时间轴0/10/20，新时间轴10/15/20。行数和旧index2的20不变，却应选择15；实际缓存返回20。
- 当前行10秒；旧时间轴0/10（最后一行，fallback100），新时间轴10/15。行数不变且旧nextIndex为nil，直接认为有效；实际返回100而非15。

同一歌词身份的时间轴替换/补全可能使LRC长句滚动仍按旧边界计算，违反体验不退化要求。应基于可靠的时间轴版本/身份失效或正确重新求后继，不能仅凭这些局部特征推断整个边界未变。修复时保留换行、seek、同时间戳语义，并避免用每帧全量比较抵消缓存收益。

新增独立复现：Tests/ValoraTests/IndependentLyricsFrameReplacementTests.swift，两项均失败。未修改生产代码。

## 实际执行

swift test --filter 'IndependentLyricsFrameReplacementTests|LyricsLineFrameCacheTests|LyricsAnchorInterpolationTests|DesktopPlayingCadenceTests|DesktopIdleMediaPublishTests'

24项，22通过、2失败。日志 /tmp/valora-r3-independent.log。git diff --check通过。未启动第二App、未操作媒体或改用户设置。

## 性能结论边界

新增缓存减少部分每帧准备工作，但可见歌词的TimelineView/SwiftUI文本遮罩路径保留。用户开歌词10%以上/关约2%的反馈及本轮“基本一样”说明核心体验目标尚未满足，不能宣布播放性能优化完成。

报告中的“每个tick重建整块面板display list”“每帧15–30次分配”“borderless窗口收不到occlusion通知”均超过现有证据强度：根render调用不证明所有子树或像素均重建，具体分配次数没有计数证据，透明/离屏窗口通知实验不能泛化所有在屏窗口。应改成观察或假设，不据此直接决定大范围原生重写。

后续先修缓存正确性；针对可见歌词的文本/遮罩/布局做隔离归因并验证改前后CPU。如果考虑原生图层，先小范围原型及视觉等价验证，保持高亮、滚动、行切换和时间同步；不盲目降帧或扩大锁屏范围。
