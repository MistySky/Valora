# 锁屏刷新范围收窄（2026-11-09）

分支：`codex/lock-screen-idle-cpu`，沿用 build44 的未提交锁屏歌词改动；未提交/推送 Git，未合并 main。

## 一、读取的证据

- `docs/reports/lock-lyrics-resource-independent-20261109.md`：build44 锁屏稳定约 10.7%/10.4%，歌词开关只差约 0.3 个百分点，不能把歌词当主因。
- `/private/tmp/valora-lock44-stack-no-lyrics-20261109/locked.sample.txt`：主线程有 SwiftUI/NSHostingView 布局、`MusicMarqueePair/MarqueeLabel.measure`、NotchView/Settings 视图、`MediaController` tick→`setElapsed`、`ScreenStateMonitor.refresh`；阻塞 read 样本不是 CPU 热点。
- 未获得真实锁屏同条件基线；本批目标只是删除可证明的重复工作和错误广播，不宣称已降低实机 CPU。

## 二、文字度量缓存

`Sources/Valora/MarqueeLabel.swift`：

- 新增 `MarqueeMeasurementCache`，键包含原始文本、字号、`NSFont.Weight.rawValue`，沿用完全相同的 `NSString.size(withAttributes:)`、system font 和 0.05 kern；
- 固定容量 128，按插入顺序淘汰；共享缓存有锁保护，`MarqueeLabel.measure` 保持 nonisolated 以兼容现有歌词 metrics 调用；
- `sizeThatFits`、`MarqueeLabelView.intrinsicContentSize`、`layout`、`rebuild`、`MusicMarqueePair.longestWidth` 均走同一缓存；
- `MusicMarqueePair.body` 先取一次 `longestWidth`，避免 body 内重复测量标题/歌手。

字体、字号、字距、4.5 余量、滚动起点/周期、颜色/点击和原生 marquee 动画未改。

## 三、进度与 AppModel 解耦

新增 `Sources/Valora/PlaybackProgress.swift`：独立 `@MainActor ObservableObject`，单个 `Snapshot(elapsed, sampledAt)` 原子发布，避免两次广播错配。

`AppModel`：

- 移除 `@Published var elapsed` 及 `elapsedSampleDate` 内部 didSet；
- 保留 `model.elapsed` 读写、`elapsedSampleDate`、`setElapsed(_:sampledAt:)`、`lyricsElapsed(at:)` 兼容入口，全部代理 `model.progress`；
- 纯进度 tick 不再触发 AppModel 的 `objectWillChange`。

迁移实际进度订阅：

- `MediaProgressView` 增加 `@ObservedObject playback`，进度文本/轨道只由 progress 刷新；播放器媒体/样式仍观察 model/settings。
- `CompactLyricsView` 增加内部 `@ObservedObject playback`，保证暂停/seek/切歌即使 Timeline 暂停也能收到新快照。
- `ExperimentalDesktopLyricsView` 增加同一 progress 订阅，snapshot 的 elapsed/sampledAt 来自同一 `Snapshot`。
- `MusicPlayerContent` 传入 `model.progress`；现有测试中的 `model.$elapsed` 已迁移到 `model.progress.$snapshot.map(\.elapsed)`。

未降低 4Hz 供给、30Hz 逐字/滚动频率、换句时长，也未引入全局计时器或强制整树重建。

## 四、锁屏 active 清理修正

`LockMusicCoordinator.beginUnlock` 的 `.locking`、`.neutralizing`、`.locked` 三个直接 `panel.orderOut()` 分支补 `lyricsActive = false`，使锁屏歌词时钟与实际窗口移除一致；不改变锁解动画。

## 五、验证

- `PlaybackProgressScopeTests`：progress 快照一致、AppModel 不因纯进度失效、同值不重发；度量缓存命中/完整键/容量淘汰。
- 既有媒体节奏/歌词缓存/锚点/锁屏协调器/实验歌词 hosting/transition 测试通过；本批定向总执行约 100+ 项，0 失败（实验构建 109 项中 1 个按构建条件跳过）。
- 普通（无实验）与 `VALORA_LYRICS_EXPERIMENT=1` 均完成编译/定向测试。
- 未做真实锁屏 CPU、压力、批量闪窗或真实播放操作；缓存命中计数不等于 CPU 降幅。

## 六、候选

- `/private/tmp/valora-lock-refresh-scope-20261109/Valora.app`
- `1.0.3 (45)`
- binary SHA-256：`d71642b4c80fbfac4ebe69f2a2fe33d72914d9a8d1157f0a7e45544b67487971`
- strict/deep 签名通过
- build44 已正常退出，当前唯一 build45 实例 PID `53834`
- build44 保留在 `/private/tmp/valora-lock-lyrics-resource-20261109/Valora.app`

## 七、未验 / 风险

- 真实锁屏 CPU 是否下降、锁屏歌词逐字/换句/暂停/解锁视觉是否完全一致，需用户实际锁屏并由 Codex 采样。
- 进度隔离改变了 `AppModel.$elapsed` 的发布形态；已迁移生产读取和现有测试，但外部代码若直接依赖该 Combine 发布者会编译失败，属于有意边界变更。
- 调用栈中的 ScreenStateMonitor/Settings/NotchView 隐藏视图刷新本批未改；需要下一批同条件采样再判断。
