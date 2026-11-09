# 桌面静置 CPU 优化：第一批（解锁桌面）

执行会话：现有 OpenCode 会话；分支 `codex/idle-cpu-optimization`；依据 `docs/opencode-tasks/desktop-idle-cpu-first-pass.md`。只做本批两项内部改动，**未打包、未安装、未替换运行版、未提交推送**；锁屏专项未触碰。

## 一、改动（2 个文件，+20/-4）

### 1. 暂停时不再重复发布同值进度

- 原位置：`Sources/Valora/Controllers.swift:114-128`（`MediaController.startTickIfNeeded()` 的 0.25s tick），原实现只要有媒体快照就每 tick 调 `model.setElapsed(...)`。
- 原行为：`elapsed` 是 `@Published`（`Sources/Valora/Models.swift:186`），赋值不比较旧值；暂停时 `SystemMediaSnapshot.rate` 被规范为 0（`Sources/ReferenceCore/SystemMediaSnapshot.swift:37`），时间轴位置恒定，但同一数值仍以 4Hz 触发 `objectWillChange`，被 `NotchView`（`NotchView.swift:40`）、`LockMusicView`、`LockInformationView` 等整模型观察者接收。
- 最小修改：tick 内先算出位置，仅当 **正在播放** 或 **位置确实变化** 时才 `setElapsed`。
  ```swift
  if self.model.playing || position != self.model.elapsed {
      self.model.setElapsed(position, sampledAt: now)
  }
  ```
- 为什么不在 `AppModel.setElapsed` 全局加 guard：该函数同时维护 `elapsedSampleDate`（歌词锚点）。播放中即使值被钳制在 `duration` 而不再变化，也必须刷新采样时间，否则 `LyricsPlaybackClock` 会从旧锚点继续外推。因此只对「暂停且值未变」这一确定无视觉变化的情形停发，播放路径保持每次发布（4Hz 与歌词 30Hz 插值语义不变）。
- 体验影响：暂停/未播放时进度、歌词行、时间文本取值与原来完全一致（值本来就未变），只是不再触发重算。恢复播放、seek、切歌、倍速、流失效重连、命令失败回滚路径均未改。

### 2. 设备展示数据未变时不重复发布

- 原位置：`Sources/Valora/ConnectivityController.swift:342-343`（`applySnapshot`），原实现 3s 轮询每次都无条件 `model.devices = devices`、`model.audioOutput = snapshot.output`。
- 最小修改：两处赋值改为等值判断后赋值；`applySnapshot` 的其余业务顺序完全不变（无提前返回）：待连接过期清理、`transitionAirPods` 判定、`batteryAlerts` 低电量边沿、toast 元数据更新/断开清理、`known`/`didRead` 更新仍按原顺序在赋值之后执行。
- 影响面：`$devices` 与 `$audioOutput` 的订阅者包括共享摘要行（`CalendarMonitorSharedView.swift:82`）、锁屏协调器（`LockMusicCoordinator.swift:229` 每次发射都 `refresh(epoch:)`）。等值快照不再触发这些重算。
- 体验影响：设备行、输出名、到达提示、低电量提醒、断开隐藏的行为与刷新时机不变；轮询频率保持 3s 未改。

## 二、验证

### 构建

`swift build` → `Build complete! (3.75 秒)`，无错误。

### 新增定向测试：`Tests/ValoraTests/DesktopIdlePublishTests.swift`（13 项）

媒体（6）：
1. 暂停 tick ×8 不再发布 `elapsed`，且 `objectWillChange` 计数为 0；tick 仍存活。
2. 播放时每 tick 仍发布（4Hz），歌词锚点与 `elapsed` 一致（±0.25s）。
3. 暂停→恢复：恢复后下一 tick 立即发布且位置不倒退。
4. 暂停态 seek：新位置立即生效，随后 tick 保持静默。
5. 暂停态切歌：新 revision 生效，tick 仍静默。
6. 流失败：清空后 tick 无发布；第 4 个 tick 触发既有 1s `refresh()` 重连并恢复发布（重连语义未改）。

设备（7）：
1. 同快照 ×3：`devices`/`audioOutput` 与 `objectWillChange` 均 0 次发布，但模型仍是最新快照。
2. 变化快照：立即发布 1 次，且到达提示仍为 `b`。
3. 仅输出名变化：只发布 `audioOutput`。
4. 同值重复后电量跌破阈值：提醒仍触发 1 次，重复同值不再重复提醒。
5. 重复同快照不重放/不延长到达提示（generation 不变）。
6. 重复快照后断开：`devices` 清空发布 1 次、提示清理、`known` 清空。
7. 迟到元数据（同 id 后到 modelUID）：仍发布并更新为 AirPods 3。

命令与结果：

| 命令 | 结果 |
|---|---|
| `swift test --filter "DesktopIdleMediaPublishTests\|DesktopIdleConnectivityPublishTests"` | **13 通过**，0 失败 |
| `swift test --filter "MediaScheduleTests\|MediaResponsivenessTests\|MediaControllerRecoveryTests\|IndependentMediaScheduleLifecycleTests\|AuditTickingMediaSourceTests\|MusicSourceActivationTests\|ConnectivityControllerTests\|IndependentConnectivityLifecycleTests\|DeviceBatteryRowTests\|DeviceBatterySelectionTests\|DeviceBatteryProductIDTests\|DeviceBatteryMetadataCacheTests\|IndependentDeviceMediaReviewTests\|IndependentLyricsDeadlineTests\|LockLyricsTrackChangeTests\|LyricsServiceTests"` | **89 通过**，0 失败 |
| `swift test --filter "LockMusicCoordinatorTests\|LockLyricsTrackChangeTests\|CalendarMonitorSharedTests\|MonitorSummaryAccessibilityTests\|MusicDisplayPolicyTests\|FeatureSwitchTests\|IndependentInteractionTests\|IndependentSidebarContractTests\|IndependentLockActivationLifetimeTests\|LyricsCacheTests"` | **70 通过**，0 失败 |

未做全量回归（按分工由 Codex 集成时执行）。

### 发布次数证据（隔离、不闪窗）

新测试直接统计 `@Published` 与 `objectWillChange` 的发射次数（即 SwiftUI 实际订阅的信号），不启动 App、不动窗口：
- 暂停静置：每 8 次 tick 由「8 次发布」降为 **0 次**；
- 设备静置：每 3 次同值快照由「3 次 devices 发布 + 3 次 objectWillChange」降为 **0 次**。

这只是发布/失效次数证据，**不等于**真实 App 的 CPU 降幅；本批未做同场景实机 CPU 前后对照，因此**不宣称**已达到 1%–2%。

## 三、未验项与限制

- 未做真实 App 的桌面/锁屏 CPU 前后对照：需要替换运行实例（先正常退出、确认 0 进程、再启动唯一新包），本批按要求不启动 App、不扰动当前使用；对照步骤交 Codex 协调。
- 未验证真实媒体源下的暂停/恢复（不控制真实播放）：暂停判定依赖 `snapshot.rate == 0`，若某些来源在暂停时仍上报非零 rate，位置会继续变化并照常发布（保守行为，不会冻结进度）。
- 未打包候选、未递增构建号；`/Applications` 仍是 1.0.3/build26 唯一实例，未被本批改动。
- 锁屏文件、玻璃材质、锁屏歌词、窗口扫描频率、音频查询频率、菜单栏刷新周期均未修改。
- 现有未跟踪文件未触碰。

## 四、待 Codex 验收要点

1. 真实暂停/播放切换：暂停后进度与歌词不再闪变、恢复后立即继续、seek/切歌正常。
2. 真实设备轮询：设备行与到达提示的刷新时机无延迟（等值不发布不应造成“看起来不刷新”），断开/重连/低电量仍正常。
3. 如需 CPU 结论：按同一媒体状态分别测「暂停且有曲目」「正在播放」「无曲目」三态，改前/改后各 120s，分别报告，不合并。

## 五、候选与替换（用户当次授权）

- 用户授权“打包候选并替换运行版”；版本仍由 `scripts/package_args.py` 默认值 `1.0.3`，构建号由 `scripts/build_number.py` 自动分配一次：**27**（26 → 27）。
- Release 构建：`swift build -c release` → `Build complete! (24.41秒)`；警告仅为既有的 target 未处理文件提示，与本次改动无关。
- 打包：`python3 scripts/package.py --binary .build/out/Products/Release/Valora --output-dir /private/tmp/valora-desktop-idle-cpu-r1-candidate`。

| 项 | 值 |
|---|---|
| 候选路径 | `/private/tmp/valora-desktop-idle-cpu-r1-candidate/Valora.app` |
| 版本 / 构建 | `1.0.3` / **27** |
| 签名 | `Valora Self-Signed`；`codesign --verify --strict --deep` 通过 |
| 嵌套框架 | 同证书；adapter `test` exit 0 |
| App binary SHA-256 | `d4ec6df514045cea1c16e136aa90b64c7324b8caf5e803611b1d842c7e8957e6` |
| build-verification.json | version/build/bundle id/签名身份与上表一致；日历 entitlement 存在 |

替换过程：`osascript -e 'tell application id "com.wangqing.valora" to quit'` 正常退出旧实例（`/Applications` 1.0.3/build26，PID 91976），确认 **0** 个 Valora 进程后启动唯一新包；当前 **1** 个进程，PID 15830，路径即候选路径，刘海面板窗口存在（624×320）。全程未使用 pkill/强退，未安装到 `/Applications`，未提交/推送。

启动约 29s 时的一次只读观测：`top` 0.8%–0.9%、RSS 约 86 MB（含启动阶段，**不作为**优化前后对照，也不宣称 1%–2%）。

