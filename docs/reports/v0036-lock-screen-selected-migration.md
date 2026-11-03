# V0036 锁屏选定功能迁移报告

日期：2026-10-28
状态：实现完成，等待 Codex 独立验收；**未经真实锁屏/解锁、真实提示音、真实设备或远程桌面实机验收**。
候选：`/private/tmp/valora-v0036-lock-screen-candidate/Valora.app`
候选二进制 SHA-256：`dcb88b3a9528002f1fd128982920afc096e7b4b0e4a5cdc17b28b4fe9c987721`

## 1. 结论与范围

按用户选定范围，从成熟复刻 `alcove-revival-archive` 迁入锁屏音乐纵向链路，并在现有 Valora 的 Swift 6/macOS 27 代码中接回：

- 锁屏总开关（默认开启）；
- 真实 session 锁定/解锁事件驱动的刘海顶部锁标志；
- 锁定/解锁提示音（原资源；默认锁定关闭、解锁开启）；
- 复用现有 `MusicPlayerContent`/媒体后端的锁屏音乐卡；
- 复用现有设备快照的锁屏设备/耳机信息；
- 固定 Glass 外观、固定 10 分钟空闲隐藏、固定 0 偏移、音量条默认收起。

没有迁入锁屏电池、专注、日历、天气、亮度/声音 HUD、屏保时显示、keep-awake 或相关 provider/资源/设置。没有删除 Valora 既有菜单栏日历、系统监控、正常音乐、耳机或设置功能。

本轮未启动候选，未操作当前运行的 V0035-R3 包，未替换 `dist`，未 Git 提交/推送，未播放真实声音，未真实锁屏，未调音量，未操作蓝牙，未运行 `--verify-*` 或反复窗口/压力测试。

## 2. 来源证据、复刻实现与 Valora 迁入文件

### 2.1 原版证据

- `docs/alcove-1.7.9-detail-audit/lock-screen-original-defaults.json`
  - 原版二进制 SHA-256：`31844809b53e2ac5bd2411a96586183ceb0a20676a93c29fe2ca95714e3bcf20`
  - 已核对注册默认值：`enableLockScreen=true`、`keepAwake=0`、`showOnScreenSaver=false`、`playSoundOnLock=false`、`playSoundOnUnlock=true`、`allowConnectivityWidgetWhenLocked=true`、`allowNowPlayingWidgetWhenLocked=true`、`nowPlayingStyle=glass`、`hideIdleDuration=10`、`showVolumeControl=false`、`nowPlayingWidgetOffset=0`。
  - 原版默认表的 scope 明确说明是 registered defaults，不是当前用户偏好；首次安装 override 未独立验证。
- `reverse-engineering/lock-screen-music/Space挂载链.txt`
  - `1001bf1c0.asm` 的 `0x190`(400) 绝对层级、`10012fcb4` 的 `CGSMainConnectionID/CGSSpaceCreate/CGSSpaceSetAbsoluteLevel/CGSShowSpaces`、`10012fec0` 的窗口集合差量挂载/移除，以及 `1001bf5fc/1001bf770` 的 Space 清理链。
  - 来源自身记录：原版为全屏容器；旧复刻主要验证了 385×245 小面板；真实登录界面显示仍需实测。
- `reverse-engineering/lock-screen-music/依据与边界.txt`
  - 原版 `100186a7c` 的 345pt 音乐卡、旧的 30pt 圆角；`1001866a4` 的入场 spring `.6 / .3 / .075`；`10036f590` 单账户/有头像/无消息为高度 `.21`；原版证据中也明确将 `.95`、blur 16、`.85` 等列为重建策略，不是确认原版常数。
- `Sources/AlcoveRevival/LockMusicCoordinator.swift`
  - 锁屏/解锁临时通知、sleep/wake、非激活 `LockMusicPanel`、space 挂载、解锁 800ms 指示器延迟、850ms 延迟收起、`lastLocked` 边沿、音效、`LockMusicState` 定时器。
  - 同时包含本轮明确排除的电池、焦点、keep-awake 和 3 秒信息刷新 timer；没有直接整文件照搬。
- `Sources/AlcoveRevival/LockFrostedBackground.swift`
  - `.hudWindow` / `.behindWindow` / `.active` / `isEmphasized` / continuous corner clip。
- `Sources/AlcoveRevival/LockInformationView.swift`
  - 设备/耳机 tile 结构；本轮只保留 AirPods tile，去电池/焦点 tile。
- `Sources/AlcoveRevival/MusicPlayerContent.swift`、`OutputVolumeView.swift`
  - 复用现有 Valora 同名/同源组件，没有另起媒体面板。
- `Sources/ReferenceCore/LockMusicState.swift`、`LockIndicatorState.swift`
  - 锁屏可见状态、空闲 deadline、解锁分支和 generation 结构。本轮进一步把固定策略收敛到用户选定范围。
- `Sources/NativeBridge/NativeBridge.m` / `include/NativeBridge.h`
  - 原 `ARLockPresentationSpace` 的 identifier/level/show/hide/add/remove/destroy 路径。
- `Sources/AlcoveRevival/NotchView.swift`
  - `LockActivityGlyph`：`lock.top` 旋转 -24°、偏移 x+2/y-2，spring `.45` / bounce `.2`；这是成熟复刻当前值，不能宣称已证明原版精确值。
- 声音：归档构建产物中的 `Resources/lock.caf`、`Resources/unlock.caf`（当前归档源码树没有独立的资源许可文件；按归档自有资源保留，未引入第三方服务或身份）。

### 2.2 来源 → Valora 文件 → Swift 6 适配

| 来源 | Valora 迁入/接线 | 适配与说明 |
|---|---|---|
| 原版 defaults + 复刻 `LockMusicPreferences` | `Sources/ReferenceCore/LockMusicState.swift` | 只保留选定 policy；强制 `idleSeconds=600`、`offset=0`、`glass=true`、`showVolume=false`；不读取旧 `hideIdleDuration`/offset/电池/焦点键。 |
| 原版/复刻 `LockIndicatorState` | `Sources/ReferenceCore/LockIndicatorState.swift` | 保留 hidden/locked/unlocking 与 generation；完成解锁必须匹配 token。 |
| 复刻 `LockMusicCoordinator` | `Sources/Valora/LockMusicCoordinator.swift` | `@MainActor`；通知 handler 为 `@Sendable` 并在 main 用 `MainActor.assumeIsolated` 回调；任务可取消；去掉 IOPM/KeepAwake、电池、焦点、3 秒 timer；保留 800ms 解锁、850ms 收起、32ms 入场提交和安全 fail-closed。 |
| `LockFrostedBackground` | `Sources/Valora/LockFrostedBackground.swift` | 原 NSVisualEffectView 路径；固定 Glass，不接 NSGlassEffectView。 |
| `LockInformationView` | `Sources/Valora/LockInformationView.swift` | 只保留设备 tile；只读 `coordinator.informationAirPods`，无 Bluetooth 查询、无权限请求；未知电量显示“电量暂不可用”。 |
| `MusicPlayerContent` | `Sources/Valora/LockMusicView.swift` | 复用现有 345pt 音乐卡、`translucent:true`、`showsVolume`、播放器控制和真实媒体门控；Glass 卡圆角使用成熟复刻 28pt（原版证据另见 30pt，未宣称 1:1）。 |
| `NotchView.LockActivityGlyph` | `Sources/Valora/NotchView.swift` | 新增锁标志分支；锁定时隐藏普通音乐内容并限制展开/点击；保留无 `lock.top`/`lock.bottom` 时的整锁 fallback。 |
| 复刻 WindowCoordinator 接线 | `Sources/Valora/WindowCoordinator.swift` | 新增 session lock/indicator/notch mounted 订阅；锁定时保留锁标志面板、禁止普通面板交互，解锁完成后恢复原音乐/胶囊行为。 |
| 复刻 Coordinator 的 Space 生命周期 | `Sources/NativeBridge/NativeBridge.m`、`include/NativeBridge.h` | 仅管理本进程窗口；`CGSSpaceCreate`、absolute level 400、show/hide/add/remove/destroy；统计自持窗口集合；失败返回 nil，调用方 fail closed。 |
| 复刻 Settings 的锁屏页 | `Sources/Valora/SettingsView.swift`、`SettingsCatalog.swift`、`SettingsLocalization.swift` | 用现有 `SettingsToggleRow`/`SettingsCard`，仅增加总开关、两个声音开关、音乐、设备连接五条；不新增页面样式或图标。 |
| 复刻模型接线 | `Sources/Valora/Models.swift`、`Sources/Valora/AppDelegate.swift` | 增加 lock preference、session lock/indicator/notch state；主线程生命周期；关闭时销毁 coordinator；不停止其他模块。 |
| 原资源 | `Resources/Sounds/{lock,unlock}.caf`；`scripts/package.py` | 随包复制；`build-verification.json` 记录来源和哈希。 |

## 3. 用户选定行为如何生效

### 总开关

- `enableLockScreen` 默认 true。
- `AppDelegate` 仅在真锁屏总开关开启时创建/启动 `LockMusicCoordinator`。
- 关闭时调用 `stop()`：取消 state deadline、入场/收起/解锁 Task，移除全部 NotificationCenter/DistributedNotificationCenter 观察者与 Combine 订阅，停止声音，销毁信息面板/音乐面板，解除 notch/panel 的 Space 挂载，并清空锁屏 state。晚到回调没有可投递的观察者或 coordinator 任务。
- 关闭不会调用音乐、耳机、日历或监控的停止/重连；锁屏本地 `model.isSessionLocked` 复位，使正常刘海恢复。重新开启时重新创建一次面板和订阅，不重复保留旧实例。

### 真实锁定/解锁与刘海

- 监听 `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`，初始 session 从 `CGSessionCopyCurrentDictionary` 的 `CGSSessionScreenIsLocked` 读取。
- 锁定时固定 `lastLocked` 边沿，播放提示音仅在该边沿且对应开关开启时一次；启动时已经锁定只建立 baseline，不误响。
- 锁定时将 notch panel 挂入自有 presentation Space；锁定后普通音乐内容让位锁标志，点击/展开被限制；解锁进入 `unlocking` 阶段，800ms 后 `finishUnlock(token:)`，旧 generation 的完成回调被拒绝。
- 睡眠：隐藏锁屏内容；唤醒重新判断。应用停止/退出：取消任务并清理 Space/窗口。
- 没有单独的动画开关；没有定时器；没有重复置顶 loop。
- 锁标志动画参数来自成熟复刻当前 `LockActivityGlyph`（-24°、x+2/y-2、spring .45/bounce .2），不是从原版逐帧证明的 1:1 值。

### 提示音

- `playSoundOnLock` 默认 false，`playSoundOnUnlock` 默认 true，与原版注册默认表一致。
- `setLocked` 只在 `lastLocked` 改变时按各自开关调用注入的 `LockSoundPlaying`；启动 baseline 不响。
- 测试用 `SoundSpy`，没有调用 `NSSound.play()`；真实播放未验证。
- `stop()` 调用声音 stop；面板销毁/关闭路径不再保留旧任务。

### 锁屏音乐

- 固定使用 `LockMusicView` + 现有 `MusicPlayerContent`，走同一 `AppModel`/媒体控制/歌词状态；没有新建 MediaRemote、歌词服务或媒体源。
- 音乐开关 `allowNowPlayingWidgetWhenLocked` 默认 true，且仍受现有 `nowPlayingEnabled` 约束。
- 空闲隐藏仅在有曲目且暂停时启动 10 分钟 deadline；恢复播放取消隐藏；锁屏关闭/睡眠/解锁/停止都取消或失效。
- 音量条 `showsVolume` 初始 false；通过现有输出图标点击展开，复用现有真实可写门控。没有显示音量设置，也没有主动调音量。

### 锁屏设备/耳机

- `allowConnectivityWidgetWhenLocked` 默认 true；仅在已锁定、总开关开启、设备开关开启且 `model.displayDevices` 中存在 AirPods 时显示。
- 仅消费现有快照；没有新建 Bluetooth 查询、权限请求或第二套设备状态。
- 电量 nil 保持 nil，并显示未知文案；不会伪造 0。
- 当前没有锁屏电池、Focus、Calendar、Weather tile 或 provider。

## 4. 固定策略与排除项

- `keepAwake=0`：没有引入 `IOPM`、`KeepAwakeController` 或防睡眠 assertion。
- `showOnScreenSaver=false`：不接屏保检测；只在真实 `screenIsLocked`/session locked 时显示。
- 音乐外观固定 Glass：使用 `LockFrostedBackground` 的 NSVisualEffectView `.hudWindow`/`.behindWindow`/`.active`/emphasized；没有 Clear 选择或渐变替代。
- 空闲隐藏固定 600 秒；即使旧 defaults 中存在其他值也不覆盖固定策略。
- 偏移固定 0；不提供滑块。
- 音量条默认收起；没有“显示音量控制”设置。
- 排除整个锁屏电池/专注/日历/天气及其通知、采样、provider、资源、设置；不删除现有菜单栏日历/系统监控。
- 不新增锁屏歌词样式；既有刘海歌词保持原逻辑。
- 原版账户/头像、时钟避让未恢复；本轮不读账户资料补猜。

## 5. 定向验证

运行：

```text
swift test --filter 'LockMusicStateTests|LockMusicCoordinatorTests|SettingsReductionTests'
```

结果：**24 项通过，0 失败**。

- `ReferenceCoreTests.LockMusicStateTests` 8 项：
  - 原版默认锁定/声音/音乐/设备/Glass/10 分钟；
  - 旧 idle/offset 值不得覆盖固定 policy；
  - 锁定→解锁→再锁定快速反转 generation；
  - 启动已锁定但没有曲目不推断面板；
  - sleep/wake；
  - 暂停 10 分钟 deadline 与 stale token；
  - 音乐/总开关独立；
  - 锁指示器 stale unlock completion。
- `ValoraTests.LockMusicCoordinatorTests` 8 项：
  - 初始已锁定不播放启动声音；
  - 真实边沿 sound spy；相同状态不重放；
  - 默认锁定声音 off、解锁声音 on；
  - 总开关 off 停止并恢复 normal music state；
  - 总开关 off 不创建新的 coordinator 工作；
  - Space attach 失败 fail closed；
  - 385×325 音乐面板与 360×94 信息面板边界；
  - 设备 tile 只消费现有 AirPods 快照，未知电量保持 nil。
- 既有 `SettingsReductionTests` 8 项回归通过（设置分组/悬停/窗口复用等）；没有运行全量、`--verify-*`、反复窗口或压力/内存测试。

日志与清单：

- `docs/verification/v0036/targeted-tests.log`
- `docs/verification/v0036/test-inventory.json`
- `docs/verification/v0036/source-manifest.json`
- `docs/verification/v0036/build-verification.json`
- `docs/verification/v0036/resource-check.json`
- `docs/verification/v0036/codesign-display.txt`

## 6. 构建、签名与候选资源

- 使用 `scripts/build.sh --output-dir /private/tmp/valora-v0036-lock-screen-candidate` 做一次 Release 构建/打包。
- 目标架构：arm64；`LSMinimumSystemVersion=27.0`；bundle `com.wangqing.valora`；ad-hoc hardened runtime。
- `codesign --verify --deep --strict` 通过；现有日历 entitlement 保留。
- 候选二进制 SHA-256：`dcb88b3a9528002f1fd128982920afc096e7b4b0e4a5cdc17b28b4fe9c987721`。
- `lock.caf` SHA-256：`bae768098424a94a5d8fb096e71b128dec61b22a4bcff7490b81e2784e255306`
- `unlock.caf` SHA-256：`01c26c9afa276e9cf104b12586ad88d59fc8833f3b228f488bdda38694a36251`
- 候选未启动，未替换用户当前运行的 V0035-R3 包，未改 `dist`。

## 7. 尚未验证/已知边界

以下均未在真实机器上证明，不能因测试通过而称为体验验收通过：

1. **真实登录窗口可见性/点击**：候选没有启动；私有 SkyLight `ARLockPresentationSpace` 在目标 macOS 27 登录界面的实际挂载仍待用户操作。
2. **真实锁屏/解锁**：没有发送锁屏命令或真实通知；session 初始读取和锁定/解锁事件只做了注入测试。
3. **锁屏提示音**：没有播放真实 `lock.caf`/`unlock.caf`；只有 sound spy。
4. **真实 QQ/MediaRemote 在锁屏下的更新**：只复用现有媒体后端，没有在真实锁屏中验证曲目/进度持续更新。
5. **真实 AirPods/未知电量**：没有连接/佩戴设备；设备 tile 的未知电量和实际快照仍待实机。
6. **多屏/不同分辨率**：面板使用首选屏幕的 `.21` 位置、385×325/360×94 边界；未在物理双屏/缩放屏幕上验证。原版账户/头像/时钟避让没有完整恢复。
7. **动画常数**：-24°、x+2/y-2、`.45/.2`、800ms、850ms、32ms、28pt 圆角均来自成熟复刻或既有重建；原版精确值未能从当前证据逐帧证明。
8. **私有符号缺失**：代码有 fail-closed；目标系统符号可用性未在候选运行中验证。
9. **面板 owner/退出清理**：已写 detach/close/destroy 路径并用 fake Space 验证失败路径，但真实 WindowServer 登录 Space 的退出行为未实测。
10. **音效停止**：总开关 stop、应用退出和显式取消路径已接线；真实 NSSound 的立即停止未用真实播放验证。

## 8. 交接

本批完成实现、定向测试、一次 Release 构建/签名/资源检查及报告。当前在当时用户运行包之外独立打包；不自动运行候选。请 Codex 独立复核源码、测试、签名与候选资源；真实锁屏/声音/设备/多屏由用户后续选择时机操作。
