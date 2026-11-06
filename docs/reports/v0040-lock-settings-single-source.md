# V0040 锁屏设置精简：各模块总开关为唯一来源

2026-11-03，现有 OpenCode 会话执行（任务 `docs/opencode-tasks/v0040-lock-settings-single-source.md`）。
前置回退点 `9b2953e` 已由用户确认完成，未推送。本批在其成果上继续，**不触碰上轮已修好的锁屏独占 Space / 锁解动画**。

## 源码变更

### 1) 锁屏页只保留 3 项（`Sources/Valora/SettingsView.swift`）

```swift
SettingsCard {
    toggle("Enable Lock Screen", "enableLockScreen", true); SettingsRule()
    toggle("Play sound on lock", "playSoundOnLock", false); SettingsRule()
    toggle("Play sound on unlock", "playSoundOnUnlock", true)
}
```

删除了「模拟锁屏」「Now Playing」「Connectivity」三行。卡片、字体、顶距、图标与排序未改；锁定/解锁提示音默认仍为 off/on，已有偏好不动。

### 2) 删除「模拟锁屏」专用实现

- 删除 `Sources/Valora/LockPreviewController.swift`（207 行）与 `Tests/ValoraTests/LockPreviewControllerTests.swift`（239 行）。
- `Models.swift`：删除 `previewLockScreenEnabled`、`previewLockPresentationActive`、`previewLockIndicator`、`lockDisplayIndicator`、`isLockPreviewActive`；`showsLockActivity` / `isLockTransitioning` / `isLockNeutralGeometry` / `isLockStage` 直接读 `lockIndicator`；`showsMusicActivity`、`showsCompactLyrics` 去掉预览分支。
- `WindowCoordinator.swift`：`MergeMany` 去掉两个预览 publisher，四处 `|| model.isLockPreviewActive` 守卫去掉。
- `NotchView.swift`：两处点击/展开守卫去掉预览条件。
- `AppDelegate.swift`：删除 `lockPreview` 属性、创建、`start()` 与终止时 `stop()`。

真实锁动画、几何、阶段状态（`LockIndicatorState`）、overlay/独占归属、解锁→neutral→最新音乐链路全部保留未改。

### 3) 音乐卡只跟随 `enableNowPlaying`

- `Sources/ReferenceCore/LockMusicState.swift`：`LockMusicPreferences.init` 不再读取 `allowNowPlayingWidgetWhenLocked`，`musicEnabled` 固定为真；删除不再使用的 `connectivityEnabled` 字段及其读取。
- `Sources/Valora/LockMusicCoordinator.swift`：`musicPreferences.musicEnabled = model.settings.nowPlayingEnabled`（原来是 `preferences.musicEnabled && nowPlayingEnabled`）。

即：音乐模块 on → 锁屏音乐卡按既有 `hasTrack` / 10 分钟 idle 策略显示；off → 立即 `visible=false` 并停止所属刷新，退出沿用原有 0.85s 收起动画。旧的 `allowNowPlayingWidgetWhenLocked=false` 不再能否决模块开关。

### 4) 设备卡只跟随蓝牙模块开关

- `refreshInformation()` 的资格判断改为 `model.settings.bluetoothEnabled`（原 `preferences.connectivityEnabled`）；关闭时**根本不读取** `model.displayDevices`，因此缓存的 `devices` 不会再撑出设备卡。
- `bindModel` 的 `MergeMany` 增加 `model.settings.$bluetoothEnabled`，开关切换即时刷新：关 → `informationAirPods = nil` 且 `orderOut` + detach；再开 → 重新显示。
- 蓝牙授权入口、`ConnectivityController`、真实设备采集未改，未触发任何新授权。

### 5) 锁屏总开关

仍由 `enableLockScreen` → `AppDelegate` 订阅 → `lockMusic.setEnabled` 控制整个锁屏体验（顶部锁/解动画、声音、锁屏卡）。关闭不影响未锁屏的音乐/设备模块；没有把音乐/设备全局开关反向改写，也没有新增设置项。

旧锁屏专用偏好只停止使用，`UserDefaults` 里的历史键值未清理、未改写。

## 定向验证

全部为无 UI、无真实 NSWindow/Space/锁通知的功能回归。

- `swift build` / `swift build -c release` 通过。
- `LockMusicCoordinatorTests` 31 项通过（28 → 31）：
  - 新增 `testArchivedLockOnlyPreferencesNoLongerGateTheCards`：defaults 预置 `allowNowPlayingWidgetWhenLocked=false`、`allowConnectivityWidgetWhenLocked=false`，卡片仍按模块开关显示。
  - 新增 `testTurningOffNowPlayingHidesOnlyTheLockMusicCard`：关音乐只隐藏音乐卡，设备卡保持（跟随自己的模块）。
  - 新增 `testMasterSwitchToggledWhileLockedHidesAndRestores`：锁中关总开关 → 卡片隐藏、overlay released（detached 724）、`lockOverlayReady`/`lockNotchMounted` 均 false；再开恢复可见。
  - 改写 `testInformationPublishesNilDeviceBatteryAndOffTransitions`：设备模块 off → `informationAirPods` 立即 nil；再开恢复。
  - 改写 `testInformationDeviceToNilAndGlobalOff` 的旧锁屏偏好用法为 `enableLockScreen=false`。
  - 保留上轮三项独占 Space 回归（独占优先/被拒回退/overlay 走独占并报真实分支）。
- `LockMusicStateTests` 13 项通过：默认策略、归档锁屏专用偏好不再否决模块开关、音乐/总开关独立、idle deadline、睡眠/唤醒、阶段顺序与过期 token。
- `IndependentInteractionTests` 3 项、`MultiDisplayCoordinatorTests` 3 项、`PresentationControllerTests` 14 项通过（共 20）：确认删除预览状态未影响多屏/呈现路径。
- 无引用残留：`grep -rn "previewLock|LockPreview|模拟锁屏" Sources Tests scripts` 为空。

## 候选

- 目录：`/private/tmp/valora-v0040-lock-settings-candidate`（新目录，未覆盖 `dist`、未覆盖 `/private/tmp/valora-v0039-r2-exclusive-space-candidate`）。
- binary SHA-256：`0b1c675d05768a8168e84ef8128c439286b7fb3479e1640ca1d05fa676cba729`
- `codesign --verify --strict --deep` 通过。

## 未覆盖 / 待独立验收

- **未启动候选**（任务禁止启动/退出用户软件）：实际设置页 3 行渲染、真实锁屏下的动画与卡片显隐未在本轮做视觉核对。检查时机器上没有 Valora 进程在运行，本轮也未启动或退出任何实例。
- 「关闭音乐后立即隐藏」指状态立即为隐藏并停止刷新；面板沿用原有的 0.85s 收起动画退出，不是瞬间消失。
- `stop()` 会把 `model.isSessionLocked` 置 false（既有行为，本批未改）；若用户在实际锁屏中关闭锁屏总开关，锁屏专属链路停止，未锁屏的音乐/设备模块不受影响。
- 未做真实锁解、媒体、设备连接、权限、系统设置、个人日程操作；未 Git 提交/推送；定时器保持关闭。
