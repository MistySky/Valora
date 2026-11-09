# 第二批补充：可见歌词每帧成本与补验

执行会话：现有 OpenCode 会话；分支 `codex/idle-cpu-optimization`；依据 `docs/opencode-tasks/desktop-playing-cpu-lyrics-followup.md` 与 `docs/reports/desktop-playing-cpu-second-pass-independent.md`。只处理解锁桌面；未进入锁屏专项；未安装、未替换运行版、未提交推送、未发布。

## 一、现场核对

- 当前运行实例：PID **22471**，`/private/tmp/valora-desktop-playing-cpu-r2-candidate/Valora.app`，`1.0.3 / build 28`，binary SHA-256 `a127531d…`（与第二批候选一致）。本轮未替换它。
- 用户对照（歌词开≈10%+、关≈2%）是本轮唯一可用的播放态证据；未受控复测，不能当作精确归因，也不据此宣布第二批代码成败。

## 二、可见歌词每帧工作：定位结论

### 1. 结构性原因（已确认）

在第二批候选上抓到的播放中采样里，一次歌词时间轴回调的栈是：

```
TimelineView<>.UpdateFilter.updateValue
  → closure #1 in CompactLyricsView.body.getter        CompactLyricsView.swift:79
  → CompactLyricsView.lineView(...)                    CompactLyricsView.swift:43
  → NSHostingView.layout()
  → ViewGraphRootValueUpdater.render(interval:)
  → ViewGraph.renderDisplayList(...)
```

也就是说，**30Hz 歌词 tick 走的是整个 hosting view 的根渲染/display list 重建**，不是只刷歌词那一小块。这是“歌词开≈10%、关≈2%”最可能的结构性来源（与差值方向一致），但每帧具体耗时仍未能独立测量（见第六节）。

### 2. 每帧可省的准备工作（已确认，按代码核对）

`CompactLyricsView` 每帧原本都会重复做以下与时间无关的工作：

| 每帧重复项 | 位置 | 说明 |
|---|---|---|
| 指标缓存 key 构造（identity 串 + 每个词插值 + 拼接） | `LyricMetricsCache.metrics(for:identity:)` | 每帧约 15–30 次小字符串分配 |
| `lineEnd` 全表线性扫描 | 原 `lineEnd(for:)` | 每帧 O(行数) |
| 行 id 字符串 | `.id("\(start)-\(text)")` | 每帧 1 次 |
| 无障碍标签字符串 | `.accessibilityLabel(line.map { "歌词，\($0.text)" })` | 每帧 1 次 |
| transition 重新构造 | `.transition(.asymmetric(...))` | 采样里可见 `AnyTransition.combined`、`TransitionBox.visitBase`、泛型元数据查找，每帧都在做 |
| 逐词进度扫描两次 | `lineView` 一次取 index、`LyricsLineContent` 再一次 | 每帧 2 次 |

### 3. 无证据、未做的事

- 未降低 30Hz 帧率、未关闭歌词、未改逐字高亮/滚动/行切换。
- 未做“静态行只在边界唤醒”的调度器（对逐字歌词无收益，且容易漏更新）。
- 未做原生 CATextLayer 歌词行（见第七节：证据方向支持，但属大改，需先有真实播放对照与视觉等价比对）。

## 三、本批改动

### A. 每行数据只准备一次（`Sources/Valora/CompactLyricsView.swift`）

- 新增 `LyricsLineFrameCache`：以（当前行、歌词身份、duration、可用宽度、时间轴行数/下一行起点）为键，缓存 **度量（词宽/前缀/总宽）、是否滚动、行尾时间、无障碍标签、行 id、transition 标识**。
- 30Hz 帧只做：一次 `line(at:)`（O(行数)、无分配）、一次缓存命中比较、一次逐词进度计算，然后构建视图。
- 行尾时间用 `nextIndex/nextStart` 做 O(1) 校验：时间轴被替换（如 LRC→QRC 补全、重新拉取）时不会沿用旧边界。
- `transition` 提升为 `static let`，不再每帧构造；行 id/标签直接复用缓存字符串。
- 逐词进度只算一次，作为参数传给 `LyricsLineContent`（原来算两次）。
- 视觉与时间语义完全保持：字体/字距/颜色/遮罩宽度公式/滚动 offset 公式/行切换动画曲线与时长均未改；`frame.key` 与原来的 `.id` 字符串一致。

### B. 波形可见性：去掉不可验证的通知，保留确定路径（`CompactPlaybackControl.swift`）

- 原实现新增了 `NSWindow.didChangeOcclusionStateNotification` 观察者作为“回屏自动恢复”。隔离实验证明：这类 borderless 面板 **收不到该通知**（on-screen、alpha=0 窗口的 `occlusionState.contains(.visible)` 为 false，`orderFront/orderOut` 期间通知计数为 0）。
- 因此删除该观察者（连带删除 block observer 与其清理需求），只保留两条确定路径：
  1. `window.isVisible == false` 时 `clockTick` 自检停止（无需任何重配置）。
  2. 面板回屏时由 `notchSurfaceOnScreen` 触发 SwiftUI 重新挂载 → `viewDidMoveToWindow` → 时钟立即恢复。
- `Sources/Valora/Verification.swift`（仅 debug）审计同步：离屏检查改为等待一个时钟周期（0.4s）而不主动 configure；回屏恢复显式 configure 并注明生产由挂载/更新路径恢复。

### C. 未改

锁屏文件、玻璃、锁屏歌词、设备/音频/日历/菜单栏刷新周期、第一批与第二批已有策略均保留。

## 四、补验结果

### 1. 1Hz 播放锚的真实时钟插值（补充行为测试，未发现回归）

`Tests/ValoraTests/LyricsFollowupTests.swift → LyricsAnchorInterpolationTests`（4 项，全部通过）：

| 场景 | 断言 |
|---|---|
| 1Hz 窗口内（0.4s 无发布） | `lyricsElapsed` 随墙钟前进 0.4s（±0.08），且 `$elapsed` 发布次数为 0 |
| 倍速 2.0 | 0.3s 后插值前进 0.6s（±0.1） |
| seek 后 | 立即从新锚点插值，不回跳 |
| 暂停 | 歌词时间冻结在锚点（±0.001） |
| 曲末钳制 | 插值可超过 duration（原样），但行选择仍是最后一行、逐字填充仍为 100%，与 4Hz 时显示一致 |

结论：1Hz 锚没有破坏歌词同步；不触发第二批策略回退。

### 2. 波形生命周期（不依赖手动 configure）

`PlayingWaveformLifecycleTests`（2 项，通过）：

- `orderOut` 后**不做任何 configure**：一个时钟周期内自行停止（自检路径）。
- 从窗口移除再挂回：自动停止/自动恢复（真实挂载路径）。
- 观察者已删除，因此不存在“block observer 未销毁”的遗留风险。

### 3. `notchSurfaceOnScreen` 边界

`NotchSurfaceVisibilityTests`（2 项，通过）：`showNotch` 关/开、`screenHidden` 置真/假、`hideWhenIdle` 有/无曲目活动，均能正确翻转。

边界说明（与独立验收意见一致）：它是 `updateVisibility()` 计算出的**全局可见意图**，写在循环内的锁屏/多屏 `orderOut` 分支之前，不等于每个面板的真实 `isVisible`；本批未改锁屏与多屏 UI，因此不把它当作完整可见性证明。

## 五、测试

| 命令 | 结果 |
|---|---|
| `swift build` / `swift build --build-tests` | 成功，无错误 |
| `swift build -c release` | `Build complete! (23.10秒)` |
| `swift test --filter "LyricsLineFrameCacheTests\|LyricsAnchorInterpolationTests\|PlayingWaveformLifecycleTests\|NotchSurfaceVisibilityTests\|DesktopPlayingCadenceTests\|DesktopIdleMediaPublishTests\|DesktopIdleConnectivityPublishTests\|MediaScheduleTests\|MediaResponsivenessTests\|IndependentLyricsDeadlineTests\|LockLyricsTrackChangeTests\|LyricsServiceTests\|LyricsCacheTests\|MusicDisplayPolicyTests"` | **77 通过**，0 失败 |
| `swift test --filter "LockMusicCoordinatorTests\|IndependentLockActivationLifetimeTests\|MultiDisplayCoordinatorTests\|MonitorSummaryAccessibilityTests\|CalendarMonitorSharedTests\|IndependentInteractionTests\|FeatureSwitchTests\|MenuBarModuleControllerTests\|IndependentDeviceMediaReviewTests\|DeviceBatteryRowTests\|LyricsTimelineTests"` | **89 通过**，0 失败（另 ReferenceCore 歌词相关 9 项通过） |

新增 `LyricsFollowupTests.swift` 共 14 项（帧缓存 6、锚点插值 4、波形生命周期 2、可见意图边界 2）。

### 每帧准备工作的量化证据（隔离、非 CPU）

`LyricsLineFrameCacheTests` 直接统计真实构建次数：

- 同一行连续 30 帧：`frameRebuilds == 1`、`metricsRebuilds == 1`（原为每帧 1 次）；行 id/标签/transition 均为复用。
- 换行 / 宽度变化 / 时间轴替换：各重建 1 次且结果正确（行尾、滚动判定、标签）。

这说明“每帧重复准备”已从每帧 N 次降到每行 1 次；**但这不是 CPU 降幅证据**。

## 六、测量局限（重要）

- 本轮仍**没有播放态真实样本**：当前实例无播放，任务也不允许控制真实媒体/歌词开关。用户 10%/2% 的对照未经独立控制。
- 尝试用离屏 `NSHostingView` + `getrusage` 隔离测量 30Hz 歌词行的 CPU：在 XCTest 进程中 `TimelineView(.animation)` 被无节流驱动（播放态恒定 ~110% 单核、暂停态 ~0%），该数据不可用，已删除该探针，避免把伪数据写进报告。
- 每个歌词 tick 触发整棵 hosting view 根渲染的结论来自采样调用栈，不是耗时占比。
- 未验证真实播放下列切换动画与视觉是否与改动前逐像素一致（渲染路径未改，但需实机确认）。

## 七、未解决项与下一步（需决策）

**仍未解决：可见歌词 30Hz 的根渲染成本。** 本批只去掉了每帧可省的准备工作，未改变“每个歌词帧重渲染面板 display list”这一结构。

证据支持但本批未实施的方案（建议下一批单独立项）：

1. 把歌词行改为原生 CATextLayer 行（项目已有同样模式的 `MarqueeLabel`、`CompactWaveform`）：灰度底字 + 强调色字 + mask 宽度 + 滚动 offset 全部在图层上按 30Hz 更新，SwiftUI 只在换行/换曲时更新。
2. 严格对齐现有排版：字体 12 semibold、kerning 0.05、行高 17、可用宽计算、逐字填充公式、LRC 单行滑动公式、0.2s easeInOut 行切换与 ±26pt 位移、无障碍标签。
3. 需要实机验收：同曲目歌词开/关各 120s CPU 对照 + 屏幕录制逐帧比对（换行、逐字高亮、长句滚动、暂停保持行）。
4. 风险：字体基线/裁切可能存在 1px 级差异；必须先出样张比对再替换。

## 八、边界

未安装、未替换运行版、未提交/推送/发布；运行实例仍是第二批 build28（PID 22471）；未改锁屏；未跟踪文件保留。

## 九、候选与替换（用户当次授权）

用户要求“替换下”，据此打包并替换运行版（未安装到 `/Applications`、未提交/推送/发布）。

| 项 | 值 |
|---|---|
| 候选路径 | `/private/tmp/valora-lyrics-followup-r3-candidate/Valora.app` |
| 版本 / 构建 | `1.0.3` / **29**（28 → 29，自动分配一次） |
| 签名 | `Valora Self-Signed`，`codesign --verify --strict --deep` 通过 |
| 嵌套框架 | 同证书；adapter `test` exit 0 |
| App binary SHA-256 | `fd158980f80e15e3041a3415cd8c176171e1e636f1994c00905cec90384b2822` |

替换过程：执行前检查到上一实例（build28）已自行退出、系统无 Valora 崩溃报告（`~/Library/Logs/DiagnosticReports` 最新为 11-05），确认 **0** 进程后直接启动新候选；当前 **1** 个进程（PID 44468，路径即候选），刘海面板窗口存在。未使用 pkill/强退。

### 替换后的一次真实播放采样（未受控，仅作方向证据）

启动约 35s 后 30 秒窗口：4.26 CPU 秒 ≈ **14.2% 单核**；随后 5 秒 `sample`（时间窗 0.70 CPU 秒）：

- 歌词时间轴确实在跑（`TimelineView<>.UpdateFilter` 16 处、`CompactLyricsView.body` 3 处）。
- 主线程约 382 采样点中：260 空闲等待；**约 47 个在 display-cycle（transaction flush/commit、`NSHostingView.layout`、`ViewGraphRootValueUpdater.render`）**，占主线程约 12%。
- 波形时钟未出现在栈中（`WaveformClock` 0 处）。
- 另有 14 个采样落在 HIToolbox 输入源查询（系统侧，与歌词无关）。

这与“歌词开的持续开销主要来自每帧整面板重渲染”的判断一致，也说明本轮“每行只准备一次”并未改变该结构成本。播放状态、界面状态由用户操作决定，未经控制，不作前后对照，也不据此宣称降幅。

## 十、独立验收后的缓存修正

独立验收复现的 `LyricsLineFrameCache` 失效问题（行数/旧后继槽位不能证明后继未变）已按定向任务修正：每帧按当前时间轴用二分查找求真实后继起点并纳入比较，度量/标签仍缓存。两个独立用例与缓存/时间轴相邻测试全部通过。原生歌词行原型与等价性证据见 `docs/reports/desktop-lyrics-renderer-directed.md`（未接入生产）。
