# V0103：功能与全局联动回归

执行：现有会话，分支 `codex/final-cleanup`。本批只做测试预审与安全自动回归；**未改产品源码、未构建 Release、未消耗构建号（仍 13）、未重启/替换运行包、未 Git 提交**。当前运行仍是 `/private/tmp/valora-v0101-r1-dev-isolation-candidate`（PID 37215，`0.2.0` build 13，签名通过，binary `cae680e5…34db`）。

## 一、测试预审（A）

方法：对 `Tests/ReferenceCoreTests`（23 文件）与 `Tests/ValoraTests`（50 文件）逐个 grep `setUp/tearDown`、`NSWindow/NSApp/NSPanel/NSStatusBar`、`AppDelegate`、`WindowCoordinator/MenuBarModuleController`、`UserDefaults.standard`、`NSWorkspace/IOBluetooth/EventKit/LoginItem`、`Process/NSTask`、`URLSession/http`、`Task.sleep/RunLoop`，并阅读可疑类的 setUp 与方法体。

判定规则：

- **可集中运行**：纯逻辑、fake 注入、隔离 `UserDefaults(suiteName:)`、不创建 AppKit 窗口/状态项、不做真实媒体/权限/登录项/网络/设备写操作；`SystemMonitorTests` 的实时读数属只读公开本机指标，保留。
- **不混入批量运行**：会创建 `NSWindow`/`NSPanel` 并 `orderFront`、真实 `WindowCoordinator` 面板、真实 `NSStatusItem`、`AppDelegate` 构造，或需要真实 UI 布局的类。

### 未纳入批量运行的类（共 44 项 + 3 个单独跳过的方法）

| 类 | 声明测试 | 未运行原因（源码证据） |
|---|---|---|
| `SettingsReductionTests` | 8 | `setUp` 即 `WindowCoordinator(model)` + `start()` → 真实 NSPanel；含 `showSettings` 窗口复用方法 |
| `MultiDisplayCoordinatorTests` | 17 | 真实 `WindowCoordinator` + 多块 NSPanel |
| `IndependentInteractionTests` | 3 | 真实 `WindowCoordinator` 双屏面板 |
| `FeatureSwitchTests` | 4 | 构造 `AppDelegate`，创建真实 `NSStatusItem` |
| `IndependentMenuBarMigrationTests` | 4 | `MenuBarModuleController.start` 真实状态项 |
| `MenuBarModuleControllerTests` | 5 | 同上（`startSampling:false` 仍建状态项） |
| `RealMusicTitleDoubleClickTests` | 1 | `NotchPanel` + `orderFrontRegardless` |
| `RealArtworkViewStageTests` | 2 | `NSWindow` + `orderFrontRegardless` |
| `IndependentPersistedPermissionTests`（2 个方法） | 2 | `NSWindow` + `NSHostingView` + `orderFront`（其余 5 项已运行） |
| `IndependentCalendarLifecycleTests`（1 个方法） | 1 | `testNativeCalendarStatusItemUpdatesOnTheFirstDayChange` 建真实状态项（其余 8 项已运行） |

合计未执行 **47** 项；声明测试总数 **445**，实际执行 **398**（445 − 47，数量吻合）。未以 skip 冒充全部通过。

已运行的 Valora 类均确认无上述副作用；其中 `LockMusicCoordinatorTests` 使用伪造 `LockPresentationWindowFactory`/Space（类注释与源码均无 NSWindow），`LockActivationOwnerTests`/`IndependentLockActivationLifetimeTests` 使用注入的 policy 闭包（不写真实 NSApp），`NativeTitleDoubleClickTests` 只有离屏 NSView 无窗口。

## 二、集中自动回归（B）

### 1. Swift 测试（XCTest）

命令（安全子集；未跑 QA/审计 UI）：

```sh
swift test \
 --skip '(SettingsReductionTests|MultiDisplayCoordinatorTests|IndependentInteractionTests|FeatureSwitchTests|IndependentMenuBarMigrationTests|MenuBarModuleControllerTests|RealMusicTitleDoubleClickTests|RealArtworkViewStageTests|IndependentCalendarLifecycleTests/testNativeCalendarStatusItemUpdatesOnTheFirstDayChange|IndependentPersistedPermissionTests/testSettingsViewNormal)'
```

| 运行 | ValoraTests | ReferenceCoreTests | 合计 | 失败 |
|---|---|---|---|---|
| run 1 | 261 | 137 | 398 | **1**（见下） |
| run 2 | 261 | 137 | 398 | 0 |
| run 3 | 261 | 137 | 398 | 0 |

原始日志：`/private/tmp/valora-v0103-regression-logs/swift-test.log`、`swift-test-run2.log`、`swift-test-run3.log`。

### 2. 唯一失败（未复现，保留证据）

- 用例：`IndependentCodexTransportTests/testRestartKillsPreviousTerIgnoringChild`（run 1）
- 断言：`XCTAssertNotNil(pid, "engine did not start")` — 真实小脚本引擎在约 1s 内未写出 pid 文件
- 同 run 其余 3 个 transport 用例（预取消、取消杀真实子进程、静默 stdout 不绕过 deadline）全部通过
- 复现尝试：单用例 1/1 通过；整类 4/4 连续 3 次通过；整批 run 2/run 3 通过（3 次整批仅 1 次失败）
- 失败窗口日志伴随系统级 `com.apple.contactsd`/AddressBook CoreData 报错；当时曾据此推测“瞬时系统负载”，**该归因已撤回**（见 V0103-R1 更正）
- 首败结论：**未确诊**。V0103-R1 已确认测试存在就绪竞态漏洞（空文件被当作就绪），但不能把首败确定归因于它，也不能归因于 contactsd 日志；保留原始证据待进一步诊断。

> **V0103-R1 更正**：上文“指向瞬时系统负载”的推断不成立，仅为同窗口日志，不能作为因果证据。已确认的测试缺陷是：`pidText != nil` 即停止轮询，而 `echo $$ > file` 期间文件可短暂为空 → 空字符串非 nil，循环结束、转换 nil，报 “engine did not start”。修复只改测试（见 `docs/reports/v0103-r1-transport-test-readiness.md`），未改产品 deadline/取消/旧 child 断言，也未确认首败的唯一根因。

### 3. 原生生产 fake callbacks（Space 迁移/恢复/失败）

clang 编译 `Tests/NativeBridgeTests/*.m`（引入生产 `NativeBridge.m`，注入 fake Space 回调，无真实窗口/Space）：

| 用例文件 | 场景 | 结果 |
|---|---|---|
| `ExclusiveSpaceMigrationTests` | 6 | 通过 |
| `LockSpaceMigrationTests` | 6 | 通过 |
| `RepeatedExclusiveMountTests` | 5 | 通过 |
| `IsolatedOverlaySpaceTests` | 6 | 通过 |
| 合计 | **23** | 全部 exit 0 |

日志：`…/v0103-regression-logs/<Name>.build.log` / `<Name>.run.log`。

### 4. 构建号与打包入口脚本

| 脚本 | 结果 |
|---|---|
| `python3 scripts/test_build_number.py` | 通过（连续 +1、peek、并发唯一、写失败不报成功、一次交付 +1） |
| `python3 scripts/test_package_entry.py` | 通过（自动分配一次、`--build` 拒绝且不写状态、连续 +1、元数据一致、损坏状态拒绝） |
| `python3 scripts/package_args.py --build 99` | exit 2，明确 `--build is not supported` |

日志：`…/test_build_number.py.log`、`…/test_package_entry.py.log`。

### 5. 工程/编译边界

- `swift-tools-version: 6.4`、`swiftLanguageModes: [.v6]`、`platforms: [.macOS("27.0")]`；三个 target（`ReferenceCore`/`NativeBridge`/`Valora`）；`VALORA_DEVELOPMENT` 仅 debug 定义（源码核对）。
- 当前 build 13 候选：`codesign --verify --strict --deep` 通过；binary SHA-256 与 `build-verification.json` 一致（`cae680e5…34db`）。
- Release 参数门控（直接执行候选二进制，未启动 App）：`--verify-music` → exit 2 + development-only 提示。
- 本批测试通过 debug 构建，证明开发 QA 入口仍在；未新增 Release 构建。

## 三、模块覆盖（398 项自动）

| 模块 | 套件 | 执行数 |
|---|---|---|
| 媒体/播放/封面/标题/调度 | 19 | 66 |
| 歌词（逐行/逐字/缓存/锁屏切换/几何） | 12 | 75 |
| 刘海几何/锁屏状态机/卡片布局/诊断策略 | 14 | 108 |
| 设备连接/电量/旧回调 | 6 | 31 |
| 日历/系统监控/菜单栏布局 | 10 | 52 |
| Codex 传输/额度格式/摘要无障碍 | 3 | 22 |
| 设置/权限/登录项归一化/侧栏契约 | 6 | 28 |
| 开发边界（Release 拒绝/预览隔离） | 2 | 16 |
| **合计** | **72** | **398** |

逐项对应（用户要求的功能点）：

- 音乐开关/源身份/命令过期：`MediaControllerRecoveryTests`(11)、`MediaResponsivenessTests`(1)、`MusicSourceActivationTests`(2)、`IndependentDeviceMediaReviewTests`(8) 中旧 toggle/stop 后回调；
- 播放锚/暂停/seek/切歌/封面过渡纯状态：`MediaIdle`(6)、`MediaProgress`(4)、`ArtworkTransition`(5)、`ArtworkGapTransition`(6)、`SystemMedia`(4)、`SystemMediaSnapshot`(1)、`MediaSchedule`(5)、`IndependentMediaScheduleLifecycle`(1)；
- 歌词 3 秒/取消/缓存/匹配/锁屏切歌/内嵌与底部：`LyricsService`(17)、`LyricsCache`(4)、`IndependentLyricsDeadline`(2)、`LockLyricsTrackChange`(8)、`LyricsTimeline`(6)、`LyricMetricsCache`(2)、`LyricsContinuousOffset`(1)、`LyricsPlaybackClock`(3)、`LineOnlyReading`(2)、`NonNotchLyricsGeometry`(3)、`QQMusicLyrics`(24)、`QQMusicQRC`(3)；
- 锁屏锁解状态机/独立选屏/外接预留/焦点共享：`LockMusicCoordinator`(32)、`LockMusicState`(13)、`LockActivationOwner`(14)、`IndependentLockActivationLifetime`(3)、`LockCardLayout`(13)；
- 设备开关/旧 callback/佩戴/电量未知回退/低电去重：`ConnectivityController`(11)、`DeviceBatterySelection`(1)、`DeviceBatteryAlert`(4)、`ConnectionAppearance`(5)、`IndependentConnectivityLifecycle`(2)；
- 日历权限/数据 gate/节假日/选择日期/共享面板/Codex 关闭/剩余日期与摘要对齐/无障碍：`CalmonCalendar`(5)、`CalendarHolidayParity`(11)、`IndependentHolidayDispatch`(1)、`IndependentCalendarLifecycle`(8)、`IndependentCalendarPermission`(2)、`CalendarPermission`(6)、`CalendarMonitorShared`(4)、`SystemMonitor`(9)、`CodexUsageSummary`(14)、`MonitorSummaryAccessibility`(4)、`IndependentCodexTransport`(4)；
- 设置分组/授权路由/登录项归一化零系统写：`IndependentSidebarContract`(1)、`RevivalSettingsReload`(5)、`AppPermissions`(7)、`IndependentPermissionFlow`(3)、`IndependentPersistedPermission`(5)；
- build/Release 参数拒绝：`LaunchPolicy`(14)、`IndependentDevelopmentIsolation`(2)。

## 四、未执行原因与用户实机清单

**未执行（自动批次外）**：上表 10 个类/方法共 47 项，原因均为会创建真实窗口/状态项或构造 `AppDelegate`（含登录项写入归一化窗口路径）。不是失败，也不能算通过。

**必须用户协助/后续专门验证**（本批未冒充）：

1. 真实锁屏/解锁动画、解锁后焦点恢复与登录界面可操作性；
2. 合盖外接屏的音乐卡位置与头像避让（21% 为产品参考线）；
3. 真实 QQ 人声逐字歌词同步，以及无逐字时间源时的整行回退；
4. 物理双屏的活动屏/被动屏与跨屏切换；
5. 真实蓝牙/日历授权弹窗、拒绝与返回路径；
6. 耳机佩戴到达/摘下提示、AirPods 电量、低电量声音；
7. 菜单栏三个模块真实点击/材质/弹窗与软件图标显隐；
8. 被排除 UI 类覆盖的渲染级断言（标题双击命中、封面翻转宿主视图、登录项设置页归一化窗口）；
9. 长期运行与后续性能专项。

## 五、缺陷汇总与建议

- 自动范围 **0 个已确认产品缺陷**；1 次整批失败首败未确诊（V0103-R1 已确认并修复测试就绪竞态，修复与复跑见该报告）。
- 无测试契约过期失败（上一批已修侧栏期望；其余 398 项本次全绿）。
- 建议下一批：先由 Codex 独立核查本报告与日志；若同意，再对 flaky transport 用例做**仅测试**的等待机制加固，同时把 10 个 UI 类按“单次最小真实窗口”安排到用户可接受的时间窗口，或继续以静态/fake 契约替代；不为此改产品交互。

## 六、日志索引

目录 `/private/tmp/valora-v0103-regression-logs/`：

- `swift-test.log`（run1，398 执行 / 1 失败）
- `swift-test-run2.log`、`swift-test-run3.log`（398 / 0）
- `ExclusiveSpaceMigrationTests.build.log` / `.run.log`
- `LockSpaceMigrationTests.build.log` / `.run.log`
- `RepeatedExclusiveMountTests.build.log` / `.run.log`
- `IsolatedOverlaySpaceTests.build.log` / `.run.log`
- `test_build_number.py.log`、`test_package_entry.py.log`
