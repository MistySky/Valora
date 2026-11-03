# V0036-R1 锁屏生命周期与隔离测试返修报告

日期：2026-10-28
状态：限定返修完成，等待 Codex 独立验收；**真实登录界面、真实锁屏、真实声音、真实设备及物理多屏仍未实机验证**。
候选：`/private/tmp/valora-v0036-r1-lock-screen-candidate/Valora.app`
候选二进制 SHA-256：`e3260f649d32088521a38684793b0b754acd511a876f2094123a0cb005951744`

## 1. 本次范围

依据 `docs/verification/independent-v0036/decision.md`，只修生命周期、异步交付、发布、当前 notch 窗口绑定、正常音乐总开关门控及过期注释；不重做 V0036 的锁屏 UI、Glass 材质、音乐/耳机 UI、声音资源或五条设置。没有新增电池/专注/日历/天气/keep-awake/screensaver 后端，没有改动用户当前 R3 运行包或 `dist`，没有 Git 操作、真实锁屏/声音/音量/蓝牙/权限/系统设置/个人数据操作，也没有运行旧的真实窗口测试、`--verify-*`、闪窗循环或压力测试。

## 2. 已修缺陷

### 2.1 stop/start 彻底重置会话状态和 600 秒计时

`Sources/Valora/LockMusicCoordinator.swift`：

- `startIfNeeded()` 每次 start 都重新创建 `LockMusicState`；`stop()` 调用 `state.hide()`，清空 input/deadline/generation，并重置 `sleeping`、`lastLocked`、信息缓存、挂载记录和 elapsed deadline task。
- 新周期不会因“相同 track/lock/paused 输入”被 `LockMusicState.update` 短路；暂停且锁定时会重新排 600 秒 deadline。
- 旧 deadline/hide/appearance/unlock task 在 stop 时取消；task 回调另带 session epoch，停止后的旧 task 不写状态。
- `AppDelegate` 的复用路径仍是 `setEnabled(settings.lockPreferences.enabled)`，测试直接覆盖同一 `setEnabled(false) → setEnabled(true)` 路径。

### 2.2 通知/Combine 交付的 session epoch

- `LockMusicCoordinator` 增加 `sessionEpoch`；start 和 stop 都递增。
- `LockSystemEventSource`（生产为 `LockAppKitEventSource`）的 lock/unlock/sleep/wake/screen-change 回调在 coordinator 内先执行 `isCurrent(epoch)`；睡眠 handler 不会先写 `sleeping=true`。
- `LockAppKitEventSource` 自身也维护 start/stop generation。通知观察闭包先 hop 到 `@MainActor`，再用 source generation 拒绝 stop 前已入队的旧 Task；不会把非主 actor 的 ObjC 入口直接当作 Swift actor 执行。
- `bindModel` 的媒体、设备、`nowPlayingEnabled`、锁设置和 `notchWindowUpdates` Combine 回调均捕获 epoch，先 `refresh(epoch:)` guard；`hideFromScreenCapture` 也带 epoch guard。
- 旧事件测试捕获旧 `onLocked`/`onSleep` 闭包，执行 `stop → start` 后投递旧闭包，验证声音和 model 不被污染；新事件仍可正常 unlock/lock。

### 2.3 `informationAirPods` 真正可观察

- `informationAirPods` 改为 `@Published private(set)`；`LockInformationView` 的 `@ObservedObject coordinator` 因此能在 nil→device、同 ID 新电量/型号、device→nil、设备子开关 off、全局开关 off 时收到更新。
- 视图不再依赖 `model.devices` 的间接重绘；`orderFront` 仅用于窗口可见意图，不作为发布/重绘替代。
- 设备仍只从现有 `model.displayDevices` 读取，没有新增 Bluetooth 查询或权限。

### 2.4 当前 notch 窗口绑定

- 新增 `LockNotchWindow` provider 和 `WindowCoordinator.activeNotchWindowNumber` publisher。
- `WindowCoordinator` 在 `place`、`renderPanels`、`activate` 及 panels 清空时发布当前有效窗口号。
- `LockMusicCoordinator` 每次同步使用当前 provider 的窗口号：旧挂载先 `detach`，新窗口再 `attach`；stop 释放最后挂载。生产仍沿用当前多屏单活动屏策略。
- 测试注入 provider 和 `CurrentValueSubject`，只验证窗口号从 11 重绑到 22、旧 detach/新 attach 和 stop 释放，没有真实换屏或窗口循环。

### 2.5 正常音乐总开关门控

- `bindModel` 增加 `model.settings.$nowPlayingEnabled` 订阅。
- 音乐总开关 off 立即让锁屏音乐卡隐藏；不改变锁标志或设备 tile；重新开启恢复锁屏音乐，不要求额外媒体快照变化。
- `LockMusicState` 的输入不包含设备/无关设置，因此无关设置不会重置 600 秒 deadline。测试验证 `hoverDelay` 等无关改动不增加新的 deadline task。

### 2.6 注释来源修正

- `NotchView.LockActivityGlyph` 注释改为“复刻当前参数”，明确 -24°、x+2/y-2 尚未由原版证据证明为精确值；未改动画或视觉。
- `SettingsView` 删除过期 placeholder 注释和无用 placeholder helper；锁屏页仍是现有五条设置与原生样式，未改布局。

## 3. 隔离测试 seam

`Tests/ValoraTests/LockMusicCoordinatorTests.swift` 已完全替换旧的 `usePresentationSpace:false` 实际 NSPanel 测试。新测试使用：

- `LockPresentationWindow` / `LockPresentationWindowFactory` → `FakeWindow` / `FakeWindowFactory`：不构造 `NSPanel`、`NSHostingView`，只记录根视图、frame、可见性、close 和 sharing type。
- `LockPresentationSpace` → `FakeSpace`：只记录 attach/detach，不创建真实 SkyLight Space。
- `LockSystemEventSource` → `FakeEventSource`：手动投递 lock/unlock/sleep/wake，不注册 `DistributedNotificationCenter` 或 `NSWorkspace`。
- `LockScheduling` → `FakeScheduler` / `FakeTask`：手动触发 600 秒 deadline、32ms 入场、850ms 收起和 800ms 解锁，不真实等待。
- `LockNotchWindow` / `CurrentValueSubject` → `FakeNotch`：验证当前活动窗口重绑。
- `LockSoundPlaying` → `SoundSpy`：只计数，不播放 `NSSound`。
- `clock` 与 `sessionLocked` 为测试闭包；不读取真实锁屏/不真实睡眠。

测试文件没有 `NSPanel`、`NSHostingView`、`NSSound`、真实 Space 或真实通知中心路径；`swift test --filter 'LockMusicStateTests|LockMusicCoordinatorTests'` 只执行 fake 用例。

## 4. 定向验证

命令：

```text
swift test --filter 'LockMusicStateTests|LockMusicCoordinatorTests'
```

结果：**20 项通过，0 失败**。

- `LockMusicCoordinatorTests` **12 项**：
  1. 注入工厂的 385×325 音乐面板与 360×94 信息面板边界；
  2. 声音边沿 spy、启动已锁定不误响、重复状态不重放；
  3. 默认锁声 off、解锁声 on；
  4. stop 清理面板并恢复 normal music state；
  5. stop/start 重新建立暂停 600 秒 deadline、清空过期隐藏和 sleeping；
  6. 旧 lock/unlock/sleep callback 跨 stop/start 被拒绝，新 callback 生效；
  7. information nil→device、同 ID 电量/型号变化、device→nil、设备子开关 off；
  8. device→nil 及全局设备 off；
  9. `nowPlayingEnabled` off/on 的锁屏音乐隐藏/恢复；
  10. notch window 11→22 重绑，旧 detach/新 attach/stop 释放；
  11. Space attach 失败 fail-closed；
  12. 无关设置改变不重置 deadline。
- `LockMusicStateTests` **8 项**：既有固定 policy、默认值、快速反转、sleep/wake、600 秒、旧 idle/offset 不能覆盖、总/音乐开关独立、stale unlock generation。

日志/清单：

- `docs/verification/v0036-r1/targeted-tests.log`
- `docs/verification/v0036-r1/test-inventory.json`
- `docs/verification/v0036-r1/source-manifest.json`
- `docs/verification/v0036-r1/build-verification.json`
- `docs/verification/v0036-r1/resource-check.json`
- `docs/verification/v0036-r1/codesign-display.txt`

没有运行旧的实际窗口测试类，没有运行 `SettingsReductionTests`、`--verify-*` 或压力/循环测试，以遵守本轮禁测。

## 5. 构建、签名和候选

- 一次 `scripts/build.sh --output-dir /private/tmp/valora-v0036-r1-lock-screen-candidate` Release 构建/打包。
- arm64；`LSMinimumSystemVersion=27.0`；ad-hoc hardened runtime；`codesign --verify --deep --strict` 通过。
- 候选二进制 SHA-256：`e3260f649d32088521a38684793b0b754acd511a876f2094123a0cb005951744`。
- `lock.caf`：`bae768098424a94a5d8fb096e71b128dec61b22a4bcff7490b81e2784e255306`
- `unlock.caf`：`01c26c9afa276e9cf104b12586ad88d59fc8833f3b228f488bdda38694a36251`
- 候选未启动；用户当前 V0035-R3 运行包和 `dist` 未替换。

## 6. 仍未验证

- 真实登录窗口上的锁屏 Space 可见性、点击命中、时钟/头像避让。
- 真实 `com.apple.screenIsLocked/Unlocked`、真实睡眠/唤醒和关闭时 WindowServer 行为。
- 真实 `lock.caf`/`unlock.caf` 播放、停止与音量。
- 真实 AirPods 快照、未知电量和设备 tile 更新。
- 物理双屏/分辨率/显示选择变化下的实际面板重绑。
- 私有 SkyLight 符号在目标环境的可用性及真实登录 Space 销毁。
- 动画参数仍为复刻既有值，不是原版逐帧 1:1 证据。

本报告不把 fake 测试、候选签名或源码审查等同于上述实机验收。
