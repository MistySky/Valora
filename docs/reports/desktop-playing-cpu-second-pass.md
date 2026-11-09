# 桌面播放态 CPU 优化：第二批（解锁桌面）

执行会话：现有 OpenCode 会话；分支 `codex/idle-cpu-optimization`；依据 `docs/opencode-tasks/desktop-playing-cpu-second-pass.md`。只做解锁桌面，未进入锁屏专项；未打包、未递增构建号、未安装替换、未提交推送。上一批两个生产文件改动与其测试/报告均保留。

## 一、现场核对与测量局限

- 运行实例：`/private/tmp/valora-desktop-idle-cpu-r1-candidate/Valora.app`，PID 15830，`1.0.3 / build 27`，binary SHA-256 `d4ec6df5…8957e6`，与上一轮候选及 `build-verification.json` 一致。
- 采样时实例处于无播放状态（`top` 0.3%、5 秒 `sample` 无 Timeline/波形栈、无 CA 帧），因此**本批没有拿到播放态真实样本**。按要求未控制真实媒体/播放，未把空闲采样冒充播放场景。
- 用户给出的新版实测（无播放≈1%、播放/浮动≈10%、日历≈10%、切歌≈20%）作为需求输入，本批不重复复测，也不宣称降幅。

## 二、代码定位（确认的执行路径）

### 1. 4Hz 进度样本与观察边界

- `Controllers.swift` 0.25s tick：有快照即 `setElapsed`；`elapsed` 是 `@Published`（`Models.swift`），不比较旧值。
- `MediaProgressView` 只在 `MusicPlayerContent`（展开播放器）与锁屏卡里出现（`grep MediaProgressView(` 仅一处生产调用，锁屏经 `translucent` 复用）。
- 紧凑刘海条不含任何 elapsed 依赖：歌词用 `model.lyricsElapsed(at:)` 本地插值（`CompactLyricsView.swift:77`），进度条仅在展开/锁屏可见。
- `NotchView` 以 `@ObservedObject model` 观察整个模型，因此播放中每个 4Hz 样本都会重算整棵刘海视图（含 `NotchShape.path` 的路径相减、`contextMenu` 构建），而收起态并无对应可见变化。

### 2. 不可见但仍运行的连续动画

- `CompactWaveformView.synchronizeTimer()` 原条件为 `window != nil && playing && !reducedMotion && !suspended`：`orderOut` 后 `window` 仍非 nil，全屏隐藏/菜单栏开关导致的收起仍在跑 0.2s 波形时钟与每次 5 条 CA 弹簧动画。
- `CompactLyricsView` 的 30Hz `TimelineView` 只按 `playing/rate` 暂停，与面板是否真正在屏无关；`NotchView` 在 `orderOut` 后仍挂着该视图。
- 展开内容的“保留挂载”（`retainsExpandedContent = phase != .collapsed`）在完全收起后不再挂载，因此没有隐藏展开树；跑马灯在收起时 `active=false` 已停止。这两项经核实**无需改动**。

### 3. 未改动项（证据不足或越界）

- 30Hz 歌词时间轴帧率、逐字高亮/滚动/行切换：可见时必须保持，未降频。
- 波形在可见时的 0.2s 节奏与 120fps 偏好：未改。
- 音频/设备轮询、日历/菜单栏刷新、锁屏文件与玻璃：未改。

## 三、真正改动（4 文件）

### A. 进度样本按可见的进度面分级（`Sources/Valora/Controllers.swift`）

- 收起播放：每 4 个 tick（1Hz）发布一次锚点；展开播放器或锁屏卡可见：维持每 tick（4Hz）。
- 暂停：仍只在值变化时发布（上一批语义）。
- 展开/锁屏卡出现/消失：由 `$presentation`（`retainsExpandedContent`）与 `$lockMusicCardVisible` 合并订阅**立即补发一次锚点**，不等下一拍。
- 保持的语义：`elapsed` 仍是时间轴插值的锚，`lyricsElapsed(at:)`、seek/切歌/倍速/命令失败/重连都走原有快照事件（`applySystem`）立即发布；30Hz 歌词插值不变。
- 为什么不是“全局降频”：收起时没有任何视图读 `elapsed`，1Hz 只影响不可见的部分；进度条可见时仍是 4Hz。

### B. 收起/离屏时停止紧凑歌词与波形（`Models.swift`、`WindowCoordinator.swift`、`NotchView.swift`）

- 新增 `AppModel.notchSurfaceOnScreen`（`@Published`，仅在值变化时赋值）：`WindowCoordinator.updateVisibility()` 是普通刘海面板唯一的 orderFront/orderOut 决策点，在此同步；面板集合为空时置 false。
- `NotchView` 的内嵌歌词、紧凑歌词行、紧凑波形都增加该条件：面板不在屏上时不再挂载，自然停掉 30Hz 时间轴与波形时钟；重新在屏时立即挂载恢复（歌词按当前时间重新选中行，无滞后）。
- 该标志只描述普通刘海面板；锁屏覆盖层与其他窗口不读它，锁屏路径未改。
- 另加双保险（`CompactPlaybackControl.swift`）：波形时钟在 `window.isVisible` 为假时不注册，`clockTick` 自检离屏即停，并订阅 `NSWindow.didChangeOcclusionStateNotification` 重新核对。

### 体验保持方式

- 可见时：波形节奏、歌词 30Hz 与逐字高亮、行切换、滚动、尺寸全部不变；展开动画期间 `retainsExpandedContent` 为真，进度仍 4Hz。
- 隐藏时：不显示任何内容，停止的只是不可见帧；重新显示由标志/挂载即时恢复。
- 展开/锁屏出现：立即补发锚点，不会出现“进度条先停在旧值再跳”。

## 四、测试

新增 `Tests/ValoraTests/DesktopPlayingCadenceTests.swift`（8 项）：

| 用例 | 断言 |
|---|---|
| 收起播放 8 tick | 仅 2 次 `elapsed` 发布（1Hz） |
| 展开播放 4 tick | 4 次发布（4Hz 不变） |
| 锁屏卡可见 4 tick | 4 次发布 |
| 开始展开 | 立即发布 1 次，值不小于收起时 |
| 展开→收起后 4 tick | 回到 1 次发布 |
| 暂停 + 展开 | 仍 0 次发布（无新内容） |
| 隐藏面板 | 不注册波形时钟 |
| 在屏/离屏/再在屏 | 依次 运行/停止/恢复；暂停、suspended、reduce motion 均不注册 |

上一批测试的同步调整（语义随本批变化，已注明）：
- `testPlayingTickStillPublishesEveryTickAndKeepsTheLyricsAnchorFresh` → `testCollapsedPlayingKeepsAOneHertzAnchorAndFreshLyricsClock`（收起态 1Hz，歌词时钟仍取到当前时间）。
- `testResumeFromPausePublishesImmediatelyWithTheNewAnchor` → 断言语义改为“恢复由快照事件立即发布锚点，之后收起态 1Hz”。

调试审计同步（`Sources/Valora/Verification.swift`，仅 debug）：波形用例改为把离屏窗口真正 `orderFrontRegardless`/`orderOut`，并新增“离屏停止、回屏恢复”两项检查；QA 窗口放在屏幕外，不闪窗。

命令与结果：

| 命令 | 结果 |
|---|---|
| `swift build --build-tests` | 成功，无错误 |
| `swift build -c release` | `Build complete! (23.59秒)` |
| `swift test --filter "DesktopPlayingCadenceTests\|PlayingWaveformVisibilityTests\|DesktopIdleMediaPublishTests\|DesktopIdleConnectivityPublishTests"` | **21 通过**，0 失败 |
| `swift test --filter "MediaScheduleTests\|MediaResponsivenessTests\|MediaControllerRecoveryTests\|IndependentMediaScheduleLifecycleTests\|AuditTickingMediaSourceTests\|MusicSourceActivationTests\|IndependentLyricsDeadlineTests\|LockLyricsTrackChangeTests\|LyricsServiceTests\|LyricsCacheTests\|LockMusicCoordinatorTests\|MusicDisplayPolicyTests\|IndependentInteractionTests\|MultiDisplayCoordinatorTests\|MonitorSummaryAccessibilityTests\|CalendarMonitorSharedTests"` | **122 通过**，0 失败 |
| `swift test --filter "FeatureSwitchTests\|RevivalSettingsReloadTests\|IndependentSidebarContractTests\|IndependentLockActivationLifetimeTests\|MenuBarModuleControllerTests\|IndependentDeviceMediaReviewTests\|DeviceBatteryRowTests\|DeviceBatterySelectionTests\|DesktopIdlePublishTests\|DesktopPlayingCadenceTests\|PlayingWaveformVisibilityTests"` | **44 通过**，0 失败 |

未跑全量（按分工由 Codex 集成时执行）；未运行 `--verify*`（会另起实例，本轮禁止）。

## 五、已测 / 未测性能

- 已测（隔离、不闪窗）：收起播放的 `elapsed` 发布由 4Hz 降为 1Hz；隐藏面板不再注册波形时钟；展开/回屏立即恢复。发布次数与时钟注册数是**行为计数**，不等于真实 CPU 降幅。
- 未测：播放态真实 CPU。当前实例无播放，未拿到播放中 5 秒 `sample`；因此不能给出“约 10% → X%”的结论，也未达到/宣称 1%–2%。
- 明确未改（仍可能是播放态主要成本）：可见时 30Hz 歌词 SwiftUI 重绘、波形 CA 动画、展开态 4Hz 进度重绘。若实机显示播放态仍高，下一批应优先用真实播放样本区分“歌词重绘 vs 波形 vs 4Hz”。

## 六、交 Codex 的实机对照步骤

1. 用同一候选（本轮改动后重新打包）替换运行版：先正常退出旧实例、确认 0 进程，再启动唯一新包（不并行、不强退）。
2. 场景分开、各 120s，记录 `ps -o time` 差 ÷ 墙钟、`top`、RSS、媒体状态与歌词是否显示：
   a) 无播放；b) 暂停且有曲目；c) 播放 + 收起刘海（紧凑歌词可见）；d) 播放 + 展开播放器；e) 播放但刘海被全屏隐藏。
3. 播放中补一次 5 秒 `sample`，只用于看调用路径（不换算份额）。
4. 重点验证：展开瞬间进度无跳变/延迟、收起时歌词与波形仍流畅、全屏隐藏再恢复后动画立即恢复、暂停/恢复/seek/切歌/倍速/歌词行切换正常。
5. 结果按场景分别报告，不把空闲与播放、锁屏与桌面混算。

## 七、限制

- 未在真实播放下验证 1Hz 锚点对歌词逐字插值的影响（数学上与实际时间同源，单测覆盖了时钟取值，但真实播放的 30Hz 观感需实机确认）。
- `notchSurfaceOnScreen` 由 `updateVisibility()` 单点维护；若将来出现绕过它的 orderFront/orderOut，需要同步更新。
- 未触碰锁屏文件；锁屏卡的 4Hz 行为通过 `lockMusicCardVisible` 保持，但锁屏专项仍未验收。

## 八、候选与替换（用户当次授权）

用户明确要求“肯定要替换，不替换怎么测试”，据此打包候选并替换运行版（仍不安装到 `/Applications`、不提交）。

| 项 | 值 |
|---|---|
| 候选路径 | `/private/tmp/valora-desktop-playing-cpu-r2-candidate/Valora.app` |
| 版本 / 构建 | `1.0.3` / **28**（27 → 28，构建号自动分配一次） |
| 签名 | `Valora Self-Signed`；`codesign --verify --strict --deep` 通过 |
| 嵌套框架 | 同证书；adapter `test` exit 0 |
| App binary SHA-256 | `a127531de0957ae5f39a7924bf637d9d93b1d297ca57623ef3c029c7036175ab` |
| build-verification.json | version/build/bundle id/签名身份一致；日历 entitlement 存在 |

替换过程：`osascript -e 'tell application id "com.wangqing.valora" to quit'` 正常退出上批 build27（PID 15830），确认 **0** 个进程后启动唯一新包；当前 **1** 个进程（PID 22471，路径即候选），刘海面板窗口存在。全程未使用 pkill/强退。

替换后的只读观测（条件未受控，**不作前后对照**）：
- 启动后前几分钟出现 13%–16% 的区间（同期用户可能正在操作/播放，`sample` 在该区间外只看到等待栈，无法归因）。
- 静置且无鼠标移动时：5 秒内 `ps TIME` 增量约 0.09–0.10s（≈2%），`top` 1.7%–3.3%。
- 随后一次 61 秒窗口：2.83 CPU 秒 ≈ **4.72%**，RSS 169→179 MB（内存增长原因未查，属未验项）。
以上只说明“新包可运行、无持续高占用”，不构成播放态或 1%–2% 结论。

## 九、补充批（歌词开关对照）结果

独立验收后按 `docs/opencode-tasks/desktop-playing-cpu-lyrics-followup.md` 追加了一轮歌词专项，详见 `docs/reports/desktop-playing-cpu-lyrics-followup.md`。要点：

- 确认（采样调用栈）：每个 30Hz 歌词 tick 都会走 `NSHostingView.layout → ViewGraphRootValueUpdater.render → renderDisplayList`，即整块刘海面板 display list 重建，这是“歌词开≈10%、关≈2%”最可能的结构性来源。
- 已改：`CompactLyricsView` 每行数据（度量/行尾/标签/行 id/transition）只准备一次，逐词进度每帧只算一次；波形删除不可验证的 occlusion 观察者，改由 `clockVisible` 自检 + 挂载路径恢复。
- 补验：1Hz 锚的真实时钟插值（恢复/seek/倍速/暂停/曲末钳制）4 项、波形无 configure 的停止与挂载恢复 2 项、`notchSurfaceOnScreen` 边界 2 项，全部通过；未发现需要回退第二批策略的回归。
- 未解决：可见歌词的根渲染成本仍在。原生 CATextLayer 歌词行是证据支持但本批未做的下一步，需要实机歌词开/关对照与逐帧视觉比对。
- 本批未安装/未替换运行版；运行实例仍为 build28（PID 22471）。
