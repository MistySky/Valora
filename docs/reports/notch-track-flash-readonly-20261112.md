# 切歌时整块刘海闪烁：只读定位报告（2026-11-12）

## 范围与当前状态

- 只做源码核对、事件顺序分析和有限隔离复现设计；**未修改生产代码、未构建、未替换候选、未操作真实媒体/音量/锁屏/偏好**。
- 核对时 build59 实例仍为：
  - PID `17091`
  - `/private/tmp/valora-artwork-memory-bounded-r1-20261110/Valora.app`
- build57 保留：
  - `/private/tmp/valora-lyrics-transition-parity-r3e-20261110/Valora.app`
- `/Applications/Valora.app` 是 build26，只读，未启动第二个实例。

## 已核对的源码事实

### 1. 封面翻转本身没有源码 diff

`git diff 6c98d2b -- Sources/Valora/TransitioningArtwork.swift` 为空。`TransitioningArtwork` 的 ±26pt/0.2s/曲线/亮度/模糊参数没有被本批修改。但不能因此排除数据或外层事务导致的整块闪烁。

### 2. 切歌事件顺序

`MediaController.applySystem(_:)` 当前顺序（`Sources/Valora/Controllers.swift`）：

1. `model.artwork = ArtworkImage.prepare(data)` / missing 时清空；
2. 写 `title`、`artist`、`album`、`playing`、`duration`；
3. 写 source/bundle/revision；
4. 最后调用 `model.lyricsController?.mediaMetadataChanged()`。

`LyricsController.update()`（`Sources/Valora/LyricsController.swift:148`）对新 identity 立即：

```swift
model.lyrics = LyricsDisplayState(status: .loading, identity: identity)
```

因此切歌瞬间 `model.showsCompactLyrics` 会从 true 变为 false，直到歌词 ready。

### 3. 可见行和整个 compact 尺寸的连锁

`Sources/Valora/NotchView.swift:118-121`：

```swift
if allowsDynamic, !expanded, !model.isLockStage, model.showsMusicActivity,
   model.showsCompactLyrics
    || (!settings.musicPreferences.showLyrics && model.songPeek.visible) {
    if model.showsCompactLyrics, model.notchSurfaceOnScreen, !lockSurface {
        DesktopLyricsRow(...)
    } else { title/note HStack }
}
```

`Models.swift` 的 `presentationSize` 在没有 `showsCompactLyrics`、且开歌词时 `quickPeek` 为 `.none`，compact 高度会少掉 32pt 行。`NotchShape` 的 `visibleHeight`/形状随之改变。即使窗口 frame 固定为 624×320，SwiftUI 内的黑色 notch shape 仍会重新布局。

这是**源码级几何事件**；仅凭源码不能证明用户看到的“闪”一定是它，但它是目前最直接的时间线候选。

### 4. 新桌面歌词 owner 的卸载链（build59 特有）

同一时间线还会触发：

- `DesktopLyricsRow` 卸载；
- `ExperimentalDesktopLyricsView.onDisappear`（`LyricsRowExperiment.swift:526-531`）调用 `host.invalidate()`；
- `LyricsRowExperimentHost.invalidate()` 把 `isActiveOwner=false`，并 `textPreparer.close()`（`LyricsRowExperiment.swift:165-172`）；
- 重新 ready 后重新挂载，`NativeLyricsTextPreparer` 再次 `prepareWindow()`，在 `NativeLyricsRow.swift:124-133` 创建一个离屏 `NSWindow` 并调用 `orderFrontRegardless()`。

build26 的 `CompactLyricsView` 没有这个离屏 owner window。当前 build59 在切歌的 loading→ready 周期里会关闭再创建准备窗口；这属于新增的窗口 ordering/visibility 链，和“整块闪”值得优先隔离。

### 5. artwork 与身份发布

`AppModel.artwork` 的 `didSet` 先写 `artworkIdentity/artworkColors`（`Models.swift:181-185`）。`TransitioningArtwork` 只监听 `identity`，其 `synchronize()` 只在 identity 变化时调用。当前没有观察到同一次快照触发多次 flip 的源码路径，但 `artwork`/identity/colors 是三次独立 `@Published` 写入；如果外层视图在同一 runloop 多次重建，仍可能在隔离测试中被放大。

`ArtworkImage.prepare` 与 `ArtworkPalette.extract` 目前都在主线程准备/哈希 256px 有界图；这不直接改变 notch 的 opacity，但可能是同一 runloop 的时间预算问题。无真实媒体日志时不能把它定为闪烁根因。

## 已复现 / 未复现

- **已确认的源码事件链**：切歌 → lyrics loading → `showsCompactLyrics=false` → compact 行移除/compact 高度变化 → 歌词 owner 关闭；ready 后重新挂载和重新创建离屏准备窗口。
- **未复现真实可见闪烁**：本次没有真实媒体事件，也没有构建/替换真实 App；不能声称已在真实播放中复现，也没有把源码推断冒充为用户可见证据。
- 没有执行压力、批量闪窗或真实锁屏/媒体操作。

## 最小修复建议（不改变动画）

由 Codex 决定，不在本批代码中执行。建议按风险从低到高：

1. **先消除新准备窗口的 ordering 链**：让`NativeLyricsTextPreparer` 的离屏窗口不参与前台 ordering（`canBecomeKey=false`、`canBecomeMain=false`，用后置/隐藏 ordering），且不要在 loading→ready 的 row 重建时关闭再创建；owner 生命周期内复用，只在真正退出宿主时关闭。这不改 `TransitioningArtwork` 的时长/曲线/位移/opacity。
2. **保持 compact 行逻辑高度**：歌词 loading 时不要让 `showsCompactLyrics` 驱动的整块 compact 尺寸/行在视觉上塌缩，至少保持行占位或让旧行内容以无动画占位挂载；具体呈现由 Codex 决定，不能擅自把 loading 当无歌词。
3. **合并同一快照的画像发布**：若隔离测试证明 artwork/identity/colors 的同 runloop 更新触发多次 `TransitioningArtwork.synchronize`，只在完整快照提交一次；不改变 flip 参数。
4. 不建议用关闭动画、降低帧率、切回 `CompactLyricsView` 或加固定延迟掩盖。

## 未验限制

- 未读取真实播放会话，未在 build26 与 build59 之间真实 A/B。
- 没有真实用户可见帧率/截图证据；上述“整块闪”候选仍是源码级时间线，不是已确认根因。
- 未测真实 3x 屏、外接屏、物理/模拟刘海组合。
- 本报告不修改任何原动画参数，不提交 Git。

## 建议的下一步（仅建议）

由 Codex 先决定是否授权“准备窗口 ordering/复用”与“loading 期间保持 compact 行”的最小差异；再补一个隔离 `NotchView` fake 事件回归，按 ready→loading→ready 采样黑色 notch bbox/高度与快照，比较 build26 外壳。该回归应只使用 fake 事件，不操作真实播放或锁屏。
