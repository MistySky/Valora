# V0101：开发验证代码编译边界

执行：现有会话，分支 `codex/final-cleanup`。本批只收尾开发 QA 的编译边界：正式 Release 不再编入验证/审计/预览实现与可执行入口，开发构建仍保留既有隔离 suite 与测试 seam。未拆 target、未删验证能力/历史/fixture/用户资源/许可证、未改产品 UI/材质/动画/布局/功能；Objective-C/Perl 与原生桥未动。未 Git 提交/推送。

## 一、编译条件（源码级证据）

`Package.swift` 的 `Valora` 可执行目标新增：

```swift
swiftSettings: [
    .define("VALORA_DEVELOPMENT", .when(configuration: .debug))
]
```

因此 `VALORA_DEVELOPMENT` 只在 debug 配置定义，Release 配置不存在；下方文件与分支使用 `#if VALORA_DEVELOPMENT` 编译条件，而不是运行时 `if`。

## 二、整文件隔离（11 个）

以下文件整体包在 `#if VALORA_DEVELOPMENT … #endif` 中，Release 编译产物内没有任何实现：

| 文件 | 内容 |
|---|---|
| `Verification.swift` | `MusicPresentationVerification` / `SettingsVerification` / `SystemMediaVerification` / `MenuBarIconVerification` |
| `CalendarParityVerification.swift` | 日历节假日/休班一致性验证 |
| `ConnectivityVerification.swift` | 设备连接验证 + `EmptyConnectivitySource` / `ConnectivitySoundSpy` |
| `LyricsVerification.swift` | 歌词 QA |
| `MultiDisplayVerification.swift` | 多屏 QA |
| `FluidityAudit.swift` | 流畅度审计、`AuditDisplayLink`、`AuditLyricsProvider`、`FluidityFixtures`、`LyricsFrameProbe` |
| `MenuBarMemoryAudit.swift` | 菜单栏内存审计 + `AuditAppMemoryReader` |
| `CalendarFixedWindowAudit.swift` | 固定窗口日历审计 |
| `CalendarPopoverAudit.swift` | 日历弹窗审计 |
| `LockCardPreview.swift` | `LockCardPreviewController`（桌面预览锁屏卡） |
| `MenuBarAuditValidity.swift` | `ContinuousVisibilityTracker`（仅被上述审计与测试使用） |

调用点同步条件化：

- `AppDelegate.swift`
  - 审计/验证分支（`verifyCalendarParity`、`previewMenuBarModules`、`audit*`、`verifyMenuBar`…`verifyConnectivity`）→ 开发区；
  - `verifyMusic`、`previewMusic` 分支 → 开发区；
  - `lockCardPreview` 属性、`--lock-card-preview` / `--expand-media` 启动块、`applicationWillTerminate` 中的预览清理 → 开发区；
  - 测试 seam（`setupMenuForVerification`、`applyFeatureSettingsForVerification`、`applicationStatusItemForVerification`、`menuBarModulesForVerification`、`removeApplicationStatusItemForVerification`、`applicationStatusMenuForVerification`、`previewMusic()`）→ 开发区；debug 测试仍可访问。
- `CompactLyricsView.swift`：仅 `LyricsFrameProbe.record(...)` 调用条件化；歌词渲染/时间轴/动画未动，`auditRole` 参数保留为开发 seam。

`--diagnostic` 的只读诊断（`writeLiveDiagnostic`）不属于验证套件，保持生产可用，未改。

## 三、Release 启动参数拒绝（在 AppKit 之前）

新增纯函数入口 `Sources/Valora/LaunchPolicy.swift`：

```swift
static let developmentFlags: Set<String>   // --verify* / --audit* / --preview* / --expand-media / --lock-card-preview
static var isDevelopmentBuild: Bool        // #if VALORA_DEVELOPMENT
static func rejection(arguments:developmentBuild:) -> String?
```

`main.swift` 在 **`NSApplication.shared` 之前**调用：

```swift
if let flag = LaunchPolicy.rejection(arguments: CommandLine.arguments,
                                     developmentBuild: LaunchPolicy.isDevelopmentBuild) {
    fputs("Valora: \(flag) is a development-only verification flag …", stderr)
    exit(2)
}
```

行为边界：

- Release 收到任一开发参数 → 明确报错、`exit(2)`，**不进入** AppKit、媒体源、音频、蓝牙/EventKit 权限入口，也不会“悄悄回落到 production”；
- 普通参数（无参数、`--settings`、`--no-settings`、`-psn_…`、`--settings-page`）不拒绝；
- Dev（debug）构建照旧接受全部参数，继续使用隔离 suite `com.wangqing.valora.qa`；
- `AppDelegate.applicationDidFinishLaunching` 另有 `#if !VALORA_DEVELOPMENT` 兜底：若未来入口绕过 `main.swift`，非 production 启动模式直接 `exit(2)`。

`AppRuntimeDefaults` 的 QA 参数表、`StartupMode` 与 `resolve` 保持原样（解析、测试与 gate 列表共用同一事实，debug 行为不变）。

## 四、保留为共享、未隔离的实现（如实记录）

| 项 | 未隔离原因 |
|---|---|
| `NotchWindowDiagnostic` | 生产 `LockMusicCoordinator` 用 `isWindowComposited(windowNumber) == false` 做**真实回落决策**（未合成即释放 overlay、回到用户会话表面）；日志记录本身由 `VALORA_NOTCH_DIAGNOSTIC` 默认关闭、有界、只读自身窗口。不能以空实现替代该判定，故整类保留；其 `record*` 写入仍默认关闭。 |
| `AppMemoryReader` / `SystemMonitor.applications` | `SystemMonitor`（生产监控卡）的采样 API 直接使用该类型；生产构造 `SystemMonitor()` 时**未注入 reader**，所以生产不会枚举进程或读进程内存。类型与采样分支与成熟 monitor 交织，本批不重构，留给后续决定。 |
| `StaticLyricsProvider` / `NoLyricsProvider` | 位于生产 `LyricsService.swift`，被测试与降级路径使用，不属于本批验证实现。 |
| `PreviewCalendarEvents` | 位于生产 `CalendarEvents.swift`，生产 `setupMenu` 在非 production 分支与测试中使用；本批不动。 |

Release 产物补充核验（非唯一证据，仅佐证）：`nm` 中 `MusicPresentationVerification`/`LockCardPreviewController`/`MenuBarMemoryAudit`/`FluidityAudit` 符号数 **0**（debug 为 487），`strings` 中开发日志文案数 **0**（debug 为 21）。

## 五、首批候选启动崩溃与修复（如实记录）

首次候选（build 10）在 `applicationDidFinishLaunching` 崩溃：`Unexpectedly found nil`。原因是第一版把“为所有模式构造 controller”的共享块（`model.media/audio/bluetooth`）一并包进开发区，Release 里 `model.media` 保持 nil，随后 `model.media.start()` 触发隐式解包。

修复：只隔离验证分支，共享块（controller 构造、`lyricsProvider`、`coordinator`、`lockMusic`、生产启动）全部移回无条件编译；新增回归 `testSharedLaunchPathIsNotInsideTheDevelopmentRegion`（解析 `AppDelegate.swift` 的 `#if` 深度，断言共享行不在开发区）。修复后重新打包为 build 11 并实际启动验证（见下）。

## 六、定向验证（无窗口/无 QA UI）

| 套件 | 数量 | 结果 |
|---|---|---|
| `LaunchPolicyTests`（新增：参数拒绝/放行、模式与 gate 全覆盖、隔离 suite、源码编译条件、共享启动路径回归、debug 入口存在） | 10 | 通过 |
| `FeatureSwitchTests`（AppDelegate QA seam 仍可用） | 4 | 通过 |
| `NotchDiagnosticPolicyTests`（生产保留的诊断预算策略） | 6 | 通过 |
| `NotchDiagnosticCaptureTests` | 3 | 通过 |
| `MenuBarAuditValidityTests`（已隔离类型在 debug 仍编译可用） | 5 | 通过 |
| `LockLyricsTrackChangeTests`（`CompactLyricsView` 改动相邻回归） | 8 | 通过 |
| 合计 | **36** | 0 失败 |

Release 产物行为验证（直接执行打包后的二进制，未启动 App）：

```
--verify-music / --audit-fluidity / --preview-settings / --expand-media / --lock-card-preview
→ exit=2，stderr 明确提示“development-only verification flag”
```

`LaunchPolicyTests.testReleaseGateRunsBeforeAppKitStarts` 另断言 `main.swift` 中 gate 出现在 `NSApplication.shared` 之前；`testVerificationImplementationIsBehindACompileCondition` 断言 11 个文件与 AppDelegate 的编译条件、以及 `Package.swift` 的 debug-only define。

未跑全量、未运行任何 QA/审计 UI、未做闪窗循环或性能/资源审计、未触真实媒体/权限/锁屏。

## 七、既有失败（非本批引入）

`SettingsReductionTests.testSidebarGroupsFollowTheUserApprovedStructure` 目前有 2 条断言失败：期望的页面列表缺少 `Codex 用量`（V0093 新增页面后未同步更新断言）。该测试文件自 checkpoint `9b2953e` 起未被修改（`git status` 干净），本批也未触碰 `SettingsPage`/`SettingsSidebar`，故为本批之前就存在的过期断言；按要求未在编译边界批次里改动它，如实记录待后续处理。

## 八、Release 交付

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0101-dev-boundary-candidate/Valora.app` |
| 版本 / 构建号 | `0.2.0` / **11**（`Info.plist` 与 `build-verification.json` 一致） |
| binary SHA-256 | `82210e711ac0d917340efba222219550b7ad90b84da198842a0030224c32862e` |
| 签名 | `codesign --verify --strict --deep` 通过 |
| 替换 | AppleScript `quit` 正常退出 build 9 → 复查 0 实例 → `open -n` 新候选 → 复查仅 1 个进程（PID 32158，稳定运行 > 70s，无新崩溃报告） |

构建号说明：build 10 是首次候选（崩溃版），修复后重新走正式打包入口分配到 **11**；未手动指定/重置构建号，`scripts/build_number.py` 记录 last=11。未用 pkill、未覆盖运行中的 `.app` 或 `dist`、未安装发布。

## 九、未做

- 完整功能全局回归、CPU/内存/后台唤醒与 Alcove 动画流畅度专项（按用户顺序在收尾后）；
- 验证代码目录/文档迁移、`AGENTS.md` 历史归档（下一批）；
- 删除用户资源、图标旧候选、历史报告、许可证；
- 全局无引用自动删除、`AppMemoryReader`/`NotchWindowDiagnostic` 的进一步拆分（记录在第四节）。
