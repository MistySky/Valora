# 整首切歌动画退化因果核查（2026-11-12，只读）

## 0. 当前实际状态与限制

- 任务给出的当前 build59 路径是 `/private/tmp/valora-artwork-memory-bounded-r1-20261110/Valora.app`，但核查时唯一运行的 Valora 是：
  - PID `23755`
  - `/Applications/Valora.app`（main build26，只读）
- build59 当前没有在运行；没有启动第二个实例。因此本报告不能声称已完成 build26/build59 真实 A/B，也没有真实播放/锁屏操作。
- 本批未修改生产代码、未构建、未替换候选、未改动画参数、未提交。
- 已阅读 `AGENTS.md`、`main-interaction-regression-review-20261112.md`、`main-interaction-source-manifest-20261112.json`、前一份 `notch-track-flash-readonly-20261112.md` 以及所有未提交/未跟踪生产文件的 diff。

## 1. main 与当前整首切歌时间线

### main `6c98d2b` / build26

1. `MediaController.applySystem` 收到新 snapshot：
   - `model.artwork = NSImage(data:)`；`AppModel.artwork.didSet` 用 `ArtworkPalette.extract` 生成 TIFF-based identity/colors；
   - 随后写 `title/artist/album/playing/duration/source/revision`；
   - 最后 `model.lyricsController?.mediaMetadataChanged()`。
2. 新 track 的 `LyricsController.update` 同步发布 `lyrics = .loading`；`showsCompactLyrics=false`。
3. `NotchView` 的 `if model.showsCompactLyrics` 分支不成立，compact 歌词行移除；`presentationSize` 的 quickPeek 高度也少 32pt。该 loading→行移除/尺寸变化在 main 已存在。
4. `MediaPlayerContent`/`TransitioningArtwork` 根据新 artwork identity 走原 `ArtworkTransitionController`；`TransitioningArtwork.swift` 与 `ReferenceCore/ArtworkTransitionState.swift` 相对 main 无 diff，封面翻转的 duration/curve/scale/brightness/blur 参数没有被本批改。
5. main compact 歌词是纯 SwiftUI `CompactLyricsView`；没有 `NativeLyricsRowView`、`NativeLyricsTextPreparer` NSWindow、keyed child 或 owner handoff。

### 当前 build59 源码

相同 metadata/lyrics 顺序，但新增：

1. `MediaController.applySystem` 把原 `NSImage(data:)` 改成 `ArtworkImage.prepare(data)`；
   - ImageIO thumbnail 解码/规范化在 main actor 同步执行；
   - `AppModel.artwork.didSet` 的 `ArtworkPalette.extract` 改为 256px 像素 identity 哈希 + 32px palette；仍同步。
2. `showsCompactLyrics=false` 时，`NotchView` 第 118–121 行移除 `DesktopLyricsRow`，而不是纯 SwiftUI `CompactLyricsView`。
3. `DesktopLyricsRow` 是 `ExperimentalDesktopLyricsView`：
   - `onDisappear` 调用 `host.invalidate()`；
   - `LyricsRowExperimentHost.invalidate()` 关闭 `NativeLyricsTextPreparer`；
   - 歌词 ready 后重新挂载，`NativeLyricsTextPreparer.prepareWindow()` 创建离屏 `NSWindow` 并 `orderFrontRegardless()`（`NativeLyricsRow.swift:124-133`）；
   - `NativeLyricsRowHost` 是 `NSViewRepresentable`，并在 keyed handoff 中创建/移除 AppKit row。
4. `NotchView` 新增 `model.notchSurfaceOnScreen` gate（compact/inline/waveform）和 `WindowCoordinator` 的 tracking area/透明 sensor；`WindowCoordinator.updateVisibility()` 在可见时还会 `hoverSensor.orderFrontRegardless()`、更新 tracking size、把 panel 的 `ignoresMouseEvents` 设为 `!pointerInside`。
5. `AppModel.elapsed` 改为 `PlaybackProgress`，4Hz anchor 不再广播整个 AppModel；`MediaProgressView` 单独观察 progress。该变化降低全局失效，但切歌时 metadata/artwork 仍走 `@Published`。

## 2. 每项优化的可见影响判断

| 改动 | 状态 | 判断 |
|---|---|---|
| `TransitioningArtwork`/封面翻转参数 | **已排除直接参数改动** | 文件及 `ArtworkFlipMetrics` 无 diff；只能说明这是同一个翻转实现，不能排除触发次数/时机被新输入链改变。 |
| 封面 ImageIO 有界化 + 新 identity | **仍假设** | metadata 更新前多了同步 thumbnail/identity 工作；可能改变同一 runloop 的触发时刻或让外层事务晚提交。没有真实帧证据，不能称它改了动画曲线。 |
| 新 native 歌词 owner/共享截图窗口 | **最明确的新增链** | main 没有此链。切歌 loading 会卸载 row→`invalidate`→关闭离屏 window；ready 重新挂载→创建 window→`orderFrontRegardless`。这可能影响 WindowServer ordering/提交，且 `NSViewRepresentable` 重建比 main 纯 SwiftUI row 更重。 |
| `NSViewRepresentable` keyed row | **仍假设** | 只要切歌 loading 期间 row 被移除，AppKit 子视图就会离开/重新进入 SwiftUI host；main 只是纯 SwiftUI 行。是否有整块闪烁需实际帧验证。 |
| lyrics loading→移除行/compact 高度 | **不能算新增** | 该主体逻辑 main 已有；当前没有新增这个判断。不能把它单独定为新增回归，也不能直接改占位。 |
| progress isolation | **大概率无关** | compact notch 不画 elapsed；只影响展开进度/锁屏。没有通往黑色 notch opacity/尺寸的源码路径；但改变了 `setElapsed` 的发布节奏，需在整曲切换 A/B 中确认。 |
| tracking area/透明 sensor/click-through | **仍假设（鼠标条件）** | 整曲切换若触发 `updateVisibility`，会重新 order sensor、更新 tracking size；pointerInside 可能被边界事件重算，影响 hoverScale/交互。main 没有 sensor 子窗口。 |
| `notchSurfaceOnScreen` gate | **仍假设** | 正常情况下 track change 不改变 visible；若任何 mediaIdle/visibility 订阅瞬时把 visible 置 false，歌词/waveform 会被移除。当前源码未证明 track change 会触发该 false。 |
| artwork/identity/colors 连续 `@Published` | **仍假设** | `artwork` didSet 内再写 identity/colors，存在同 runloop 多次失效；`TransitioningArtwork` 只在 identity change 同步。没有证据证明同次换曲会触发第二次 flip。 |

## 3. 最小新增异常链（源码可证明，非可见根因已确认）

main 与当前的最小新增差异是以下链：

```text
track change
  -> lyrics = loading
  -> showsCompactLyrics = false
  -> current NotchView removes DesktopLyricsRow
  -> ExperimentalDesktopLyricsView.onDisappear
  -> host.invalidate() / NativeLyricsTextPreparer.close()
  -> lyrics ready
  -> DesktopLyricsRow remount
  -> NativeLyricsTextPreparer.prepareWindow()
  -> offscreen NSWindow + orderFrontRegardless()
```

main 在同一切换点也会移除 compact lyrics row，但没有：

- `NSViewRepresentable` 的 Native row 生命周期；
- owner `invalidate` / 离屏 NSWindow 关闭/创建；
- keyed frozen image / shared preparer；
- tracking sensor 重新 ordering。

因此，**不能把“切歌时歌词行短暂消失”当作新增根因**；需要把证据集中在新 owner/window/NSView 链是否使整块黑 notch 在同一 runloop 被不必要地提交/重建。

## 4. 尚未证明但应优先隔离的量

### A. artwork 触发与多个 Published

用同一 fake snapshot 比较：
- 正常新封面；
- 先缺失后迟到封面；
- 同封面不同曲；
- 连续快速两次切歌。

记录 `ArtworkTransitionController` 的 `update`/`runTransition` 次数、generation/phase、`image` 是否短暂为空、`title/playing` 与 artwork/identity 的提交顺序。当前源码可核对顺序，但没有真实日志证明多次 flip。

### B. owner/window 链

重点是 `NativeLyricsTextPreparer` 的 `NSWindow` 是否在 loading→ready 关闭/创建；是否应在 track identity 内复用，是否必须 `orderFrontRegardless`，以及 `NSViewRepresentable` 插入/移除是否导致父 hosting view 的整块提交。此项是 main 完全没有的链。

### C. WindowCoordinator sensor

若整曲切换会触发 `updateVisibility()`，需要记录 `pointerInside`、`hoverScale`、`hoverSensor.orderFrontRegardless()`、panel `ignoresMouseEvents` 的前后值。当前只能证明源码可达，不能证明用户看到的整块闪由 sensor 引起。

### D. 时间预算

`ArtworkImage.prepare` + 256px identity 在 `applySystem` 的同步主线程完成；需要记录一次真实封面的耗时和切歌开始时刻。没有真实 footprint/timing 数据前，不能把内存优化当作已证明原因。

## 5. 限制与需要的真实证据

- **未复现**真实整曲可见闪烁：build59 未运行，不能启动第二实例，也不能操作真实播放。
- **未做 main/build59 同时 A/B**；唯一运行的是 `/Applications` build26。
- 不能把现有歌词逐句测试的通过，外推为整曲切换已等价；它们没有覆盖 `showsCompactLyrics` 的 loading→ready owner 卸载/重建和离屏窗口 ordering。
- 若需要真正确认，最小真实方案是：用户按同一首歌、同一操作，**分别单实例**运行 build26 与 build59，录制 120fps 屏幕（只保留刘海区域），同时记录 `trackChanged`/`lyrics loading/ready`/`TransitioningArtwork.update`/`updateVisibility`/`hoverSensor` 时间戳；不能同时运行两版。

## 6. 最小恢复建议（不实施，等待 Codex）

优先按“main 已有逻辑不动、只移除新增风险”排序：

1. **准备窗口**：先不要在切歌 loading→ready 时关闭/重建 `NativeLyricsTextPreparer`；owner 生命周期内复用，且离屏窗口不能参与前台 ordering（`canBecomeKey/Main=false`，不要 `orderFrontRegardless`）。这只是去掉新窗口链，不改封面/刘海动画参数。
2. **owner/NSView**：若隔离证明 `DesktopLyricsRow` 的 NSView 重建导致整块提交，评估让 owner 在加载期间保持挂载或复用同一 NSView；不能通过关闭动画或降低帧率掩盖。
3. **sensor**：若隔离证明切歌触发 sensor 边界重算，避免在 `updateVisibility` 的 track-change 路径无关地重复 `orderFrontRegardless`/tracking update；不改变 hover 视觉曲线。
4. **artwork**：仅在实测证明同 runloop 多次 flip/延时时，合并 artwork/identity/colors 为一次完整快照发布；不先改 identity 语义。

## 7. 结论

- 已证明：当前新增了 main 没有的 native lyrics owner / shared preparer NSWindow / NSViewRepresentable 生命周期，且切歌 loading→ready 会关闭再创建离屏窗口。
- 已排除：封面 flip 参数文件本身没有 diff；不能据此说封面效果未变，但可以排除“本批直接改了 ArtworkFlipMetrics”。
- 仍未证明：该新链或 artwork 同步准备就是用户看到的整块闪；需要 build26/build59 单实例真实录制与时间戳。
- 本报告不修改动画、不构建、不替换、不操作真实媒体；等待 Codex 决定下一步。

## 8. 用户硬约束：内部歌词不能带动外轮廓

用户补充原话：“核心点一定是要固定刘海屏不能动，里面的切换歌词不能影响外轮廓”。独立验收 `docs/reports/track-animation-cause-independent-review-20261112.md` 也指出本报告缺少外轮廓证据，不能以歌词内部像素或封面参数无 diff 代替。

### 8.1 外轮廓的源码依赖

当前外轮廓不是由歌词行自己计算的：

- `NotchView.localSize` 的 compact 分支取 `model.visibleSize`（`NotchView.swift:78`）；
- `NotchView.width/height` 直接取 `localSize`（`:80-81`）；
- `shape` 使用 `localContour`（`:92`）；
- 最外层 `ZStack` 使用 `.frame(width:width,height:height)`（`:153`）、`.clipShape(shape)`（`:154`）、`.scaleEffect(x:localHoverScale...)`（`:157`）；
- `model.visibleSize` 的唯一几何来源是 `Models.presentationSize`（`Models.swift:299-323`）；
- `presentationSize` 的 compact `quickPeek` 高度由 `showsCompactLyrics` 决定（`:313-315`），inline 宽度由 `showsInlineLyrics`/`inlineLyricsWidthAddition` 决定（`:320-322`）；
- `showsCompactLyrics`/`showsInlineLyrics` 只依赖 `lyricsAvailable`（`lyrics.hasTimedLyrics`、now playing、show lyrics、surface）和 `usesInlineLyrics`，不依赖当前 `LyricLine` 文本/长度（`Models.swift:349-364`）。

因此，**逐句换行在源码上不应改变 `presentationSize`/`visibleSize`/`NotchShape` 的尺寸或路径**。`TransitioningArtwork` 的 scale/brightness/blur 只作用于 artwork 子树；`NotchView` 的 `scaleEffect` 只由 `localHoverScale` 决定；整体 `.opacity` 只由 `expanded` 决定。源码层面没有把当前行长度或 row 内部宽度传给 `shape`/外层 frame 的路径。

但这条结论仍缺少真实外轮廓证据；`NSViewRepresentable` 插入/更新、`DesktopLyricsRow` 内部 `.animation`/keyed transition 是否通过 AppKit/SwiftUI 排版副作用影响父 hosting view，不能仅由静态值引用排除。

### 8.2 整首 loading→ready 是明确的外轮廓变化路径

整首切歌不是逐句：

1. `LyricsController` 发布 `.loading`；`hasTimedLyrics` 变 false；
2. `showsCompactLyrics`/`showsInlineLyrics` 变 false；
3. `Models.presentationSize`：
   - compact 的 `quickPeek` 从 `.playing` 变 `.none`，少 32pt 高度；
   - inline 模式下 `inlineLyricsWidthAddition` 从 16 变 0，外宽少 16pt；
4. `NotchView` 的 `width/height`、黑色 `NotchShape`、`.frame`、`.clipShape` 随之改变；
5. `WindowCoordinator.trackingSize`/`hoverSensorFrame` 也使用同一 `visibleSize`，所以透明 sensor 的 frame 跟着变。

这条路径在 main 已存在一部分（`showsCompactLyrics` 条件、`presentationSize` quickPeek 逻辑），但用户的**新硬约束**要求同一显示/交互状态下歌词加载不能带动外轮廓。因此这里存在“main 旧逻辑 vs 新约束”的冲突，不能因为 main 也这样就把当前现象排除。

### 8.3 逐句与整首的边界

| 场景 | 外轮廓源码依赖 | 当前判断 |
|---|---|---|
| 同一 track 逐句短短/短长/长短/空行 | 当前行文本/宽度不进入 `presentationSize`；row 内部 `.frame(width: resolvedWidth)` 只在 row 内 | **源码上应固定**；缺乏实际 bounds/path 采样，不能宣称已完成验收 |
| 整首 loading→ready | `showsCompactLyrics`/`showsInlineLyrics` 改变 `quickPeek`/`inlineLyricsWidthAddition` | **明确可能改变外轮廓**，与用户新约束冲突；需 Codex 决定最小解 |
| 歌词开关/内嵌模式显式切换 | `showLyrics`/`inlineLyrics` 改变几何 | 属于用户授权交互，不在此约束禁止范围 |
| 主动展开/收起、hover | `presentation`/`localHoverScale` 改变 frame/scale | 属于已认可交互；不得因本约束全局冻结 |

### 8.4 最小方案候选（不实施）

不改变动画参数、不改变逐句内部行效果的前提下，外轮廓固定需要一个“外层几何不随歌词可用性变化”的边界。最小位置在：

- `Models.presentationSize` 的 `quickPeek`/inline 分支（`Models.swift:313-322`），以及
- `NotchView` 的 compact row 条件（`NotchView.swift:117-121`）。

可选方案（由 Codex 决定，需用户确认视觉行为）：

1. 同一 track/同一显示模式下，compact 行几何由“歌词模式已启用且音乐活动可见”决定，而不是由 `lyrics.hasTimedLyrics` 当前是否 loading 决定；loading 期间保留行占位，内部可显示空/旧内容。这会改变 main 的 loading 视觉，需要用户确认。
2. 将 `quickPeek`/inline 外轮廓与 compact 行可用性分离，使用独立的 music surface 状态；不把行可用性直接映射成外轮廓。需要定义“歌词开启但当前无行”时的产品行为。
3. 仅移除新增的附加几何输入（如新版 `NativeLyricsRow` 自带的父级布局副作用）；这不能解决 main 已有的 loading 收缩，但可以避免新回归。

不建议通过关闭歌词、关闭动画、降低帧率或全局冻结窗口来满足约束。

### 8.5 证据缺口与最小 fixture

独立验收明确指出缺少：

- 同一显示模式/交互状态下，短短、短长、长短、空行的外轮廓 bounds/path/scale/整体 opacity 与内部 row bounds 分开断言；
- 整首 loading→ready 的外轮廓 bounds/path/整体 opacity；
- build26 与当前候选单实例同条件对照。

建议的最小 fixture（不执行，等待授权）：

- 在 offscreen `NSHostingView<NotchView>` 上，固定不悬停、不展开、同一 geometry；
- 记录 `shape.path` 的 boundingRect、`NSHostingView` 实际 subview bounds、`model.visibleSize`、`model.hoverScale`、`expanded`；
- 依次注入同 track 的 `short/short`、`short/long`、`long/short`、`empty` 行变化，断言外部几何四项完全不变；
- 再注入 track loading→ready，单独记录外部四项变化，明确这是产品冲突点而不是逐句回归；
- 不通过歌词像素/note x 坐标代替外轮廓断言。

### 8.6 本补充结论

- **已证明（源码依赖）**：逐句当前行不进入 `presentationSize`/外框计算；整首 loading→ready 通过 `showsCompactLyrics`/`showsInlineLyrics` 明确进入外层高度/宽度计算。
- **未证明**：当前实际可见闪动是否就是该 loading 几何变化；缺少真实外轮廓帧/路径证据，也缺少 main/build59 单实例 A/B。
- **不能接受为已修复**：没有修改生产代码，也没有把外轮廓固定实测通过。
- 未构建、未替换、未操作真实媒体/锁屏、未提交。
