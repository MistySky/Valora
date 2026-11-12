# 固定刘海外轮廓：歌词空间与内容可用性分离（2026-11-12）

## 结论先行

本批只改了普通桌面 compact/inline 歌词的**外框几何输入**：歌词空间由稳定的歌词显示模式决定，不再由 `lyrics.hasTimedLyrics`、loading/ready/失败、当前行文本或空行决定。歌词内容仍由原 `showsCompactLyrics`/`showsInlineLyrics` 门控。

这是本批唯一认可的体验差异：

> 歌词加载/无歌词期间不再收缩歌词空间；即使没有可用歌词，固定 slot 仍保留现有 32pt compact 高度（或 inline 16pt 宽度）。内部可以为空，不显示上一首旧歌词，也不捏造歌词。

未改封面翻转、逐句歌词动画、时长、曲线、位移、透明度、音符对齐、hover/展开收起、锁屏位置或真实媒体路径。

## 精确源码改动

### `Sources/Valora/Models.swift`

1. `presentationSize` 的 compact `quickPeek`：
   - 由 `showsCompactLyrics` 改为 `reservesCompactLyricsSlot`。
2. `presentationSize` 的 inline 宽度分支：
   - 由 `showsInlineLyrics` 改为 `reservesInlineLyricsSlot`。
3. 新增稳定几何判定：

```swift
private var compactLyricsSlotVisible: Bool {
    settings.nowPlayingEnabled && settings.musicPreferences.showLyrics
        && showsMusicActivity
        && (!isSessionLocked || isLockTransitioning)
        && !expanded
        && settings.showNotch && !screenHidden && connectionToast == nil
}
var reservesCompactLyricsSlot: Bool { compactLyricsSlotVisible && !usesInlineLyrics }
var reservesInlineLyricsSlot: Bool { compactLyricsSlotVisible && usesInlineLyrics }
```

4. `inlineLyricsWidthAddition` 改为由 `reservesInlineLyricsSlot` 决定；`NotchView.nativeNotchSize` 原本就读取该值，因此内嵌宽度和外框使用同一稳定口径。
5. `showsCompactLyrics` / `showsInlineLyrics` 保持为内容可用性，仍依赖 `lyrics.hasTimedLyrics`；不因保留 slot 而启动无意义歌词时钟或显示旧歌词。

未改 `NotchView` 的逐句行内容、内部 keyed transition、row 内部宽度、外层 `frame`/`clipShape`/`scaleEffect` 或任何动画参数。

## main 对比

main `6c98d2b` 的 compact quickPeek/indent 几何依赖 `showsCompactLyrics`/`showsInlineLyrics`，`showsCompactLyrics` 依赖 `lyrics.hasTimedLyrics`，所以整首切歌 loading 期间外框会少 32pt/16pt。当前保留后将不再随加载/可用性伸缩；这是明确批准的差异，不是“动画参数改成不同”。

逐句路径没有改变：当前行文本/长度从来没有进入 `presentationSize`；`NotchShape` 的尺寸/路径只读 `visibleSize`。本批保留 content gating，不改变逐句内部动画。

## 验证

新增 `Tests/ValoraTests/NotchFixedContourTests.swift`，4 项通过：

1. compact slot：loading、ready、短句、长句、空行、unavailable 的 `visibleSize` 和 `NotchShape.boundingRect` 全部相同；
2. inline slot：loading/ready/unavailable 宽度/路径相同，且相对关闭歌词时仅增加既有 16pt；
3. 显式关歌词、screenHidden 仍会改变几何；暂停/活动规则沿用现有；
4. 实际 `NSHostingView<NotchView>` 离屏采样：
   - ready 短句 / ready 长句 / ready 空行 / loading 的黑色外框 bbox 完全一致；
   - 采样值：`(398, 0, 452, 110)`（同一 host/geometry）；
   - `model.visibleSize = (214.0, 55.0)`（外部模拟刘海 fixture）。

相邻定向回归共 82 项通过：

- `MusicDisplayPolicyTests` 8
- `LyricsServiceTests` 17
- `RevivalSettingsReloadTests` 5
- `IndependentInteractionTests` 3
- `LockLyricsTrackChangeTests` 9
- `LockMusicCoordinatorTests` 36
- `NotchFixedContourTests` 4
- `NotchSurfaceVisibilityTests` 2

`LockCardLayoutTests` 2 项也通过。

## 未验证项

- 没有正式打包/Release 候选，没有替换运行实例，没有操作真实音乐、音量、锁屏或用户偏好。
- 没有真实硬件/真实桌面窗口的可见采样；`NSHostingView` 离屏结果不等同 WindowServer 真帧。
- 没有 build26/build59 同条件真实 A/B；当前唯一运行实例仍是 `/Applications/Valora.app` build26（PID 23755）。
- 没有验证所有物理/模拟刘海、外接屏、多屏边界；没有验证歌词失败/迟到的真实网络路径。
- 没有提交 Git。

## 文件

- 改动：`Sources/Valora/Models.swift`
- 新增测试：`Tests/ValoraTests/NotchFixedContourTests.swift`
- 本报告：`docs/reports/notch-fixed-contour-fix-20261112.md`
