# V0038 桌面模拟锁屏动画开关报告

日期：2026-10-30
状态：实现与定向 fake 验证完成，等待 Codex 独立验收；**候选未启动，当前用户应用未替换，实机用户点击尚未执行**。
候选：`/private/tmp/valora-v0038-desktop-lock-preview-candidate/Valora.app`
候选二进制 SHA-256：`f6d0390566f188e33d90632e4cebb7c721bedff87fde0ca8ee7ce87a5938d387`

## 1. 结果

锁屏设置页在现有五项设置之后新增普通开关：

```text
模拟锁屏
```

- 默认 off；仅保存在 `AppModel` 进程内，不写 `UserDefaults`，重启不会恢复 on。
- 只有锁屏总开关开启时可用；总开关 off 时入口 disabled，且会取消已有模拟。
- 真正锁屏总开关值、真实 session、真实锁屏 coordinator 均不被修改。
- 模拟不创建/挂载 Space、不改变窗口 level、不创建额外 panel、不播放声音、不显示锁屏底部音乐卡/设备卡。
- 模拟只驱动顶部 notch 的预览阶段和普通 `PresentationController` 的收起/completion；没有另写一套视频或不同动画。

## 2. 动画状态机

新增 `Sources/Valora/LockPreviewController.swift`：

### 打开

1. 使用独立 `AppModel.previewLockIndicator`，不覆盖真实 `lockIndicator`。
2. 若有展开播放器，先复用 `model.presenter.collapse(completion:)` 完整收起。
3. `.locking` 保留 compact 音乐活动；随后 `.neutralizing` 收回基础刘海；再进入 `.locked` 展开锁 glyph。
4. 无音乐也走基础刘海 → 锁展开；不伪造底部卡。
5. 锁展开/收起的 geometry 使用可注入 `LockGeometryAnimating`，生产为实际问题 `withAnimation` completion；不是固定计时器。

### 关闭

1. `.locked → .unlocking`，保持锁宽度显示 open glyph。
2. 0.8s 复用现有 unlock 阶段后进入 `.restoring` neutral 基础刘海。
3. geometry completion 后清理 `previewLockPresentationActive`，恢复当前最新媒体 compact 活动；无音乐回基础刘海。
4. 不改变真实 `model.isSessionLocked`，不调用真实 session 锁/解锁、声音、Space、媒体控制。

### 真实锁/总开关/快速反转

- `model.isSessionLocked` 变为 true：取消模拟任务、关闭模拟开关、清除预览 presentation；真实 lock indicator/session 保持真实 coordinator 所有。
- 锁屏总开关关闭或 controller stop：取消 completion/任务，恢复普通音乐，清理预览状态；不自动启动真实服务。
- 快速 on/off/on：generation 取消旧 geometry/unlock task，旧 completion 不能重开锁。
- 模拟关闭时不触发真实 unlock，也不会把真实 `isSessionLocked` 改为 false。

## 3. 显示接线

- `AppModel` 增加独立的：
  - `previewLockScreenEnabled`
  - `previewLockPresentationActive`
  - `previewLockIndicator`
  - `lockDisplayIndicator`：真实锁优先，否则选择 preview；真实 indicator 不被覆盖。
- `NotchView` 使用 `lockDisplayIndicator` 绘制锁/开锁 glyph；预览期间阻止普通展开/点击。
- `WindowCoordinator` 订阅 preview indicator/active，使同一当前 notch panel 在预览阶段正确显隐；不创建额外窗口/Space。
- `NotchView` 的交互门控在预览锁展开期间禁用普通刘海交互；不改变普通音乐正常路径。
- SettingsView 增加一行 `模拟锁屏`，无图标、无长解释、无新设置页。

## 4. 定向测试

命令：

```text
swift test --filter 'LockPreviewControllerTests'
```

结果：**7 项通过，0 失败**：

- 预览使用 locking→neutralizing→locked，不改变真实 session/真实 indicator；
- 关闭预览 locked→unlocking→restoring→hidden，恢复最新音乐；
- 无音乐时基础刘海 → 锁展开；
- 有展开内容时先走既有 collapse completion；
- 真实锁接管自动关闭模拟，不修改真实 lock state；
- 快速 on/off/on 旧 geometry completion 被拒绝；
- 锁屏总开关 off 取消模拟且不改变真实 session。

所有测试使用 fake scheduler/geometry completion、AppModel/presenter 状态；没有真实 NSPanel/NSPopover/Space/锁通知/声音/媒体控制/截图/循环或压力测试。

## 5. 构建与候选

- 一次 `scripts/build.sh --output-dir /private/tmp/valora-v0038-desktop-lock-preview-candidate` Release；arm64、macOS 27、ad-hoc hardened runtime。
- `codesign --verify --deep --strict` 通过。
- 候选二进制 `f6d0390566f188e33d90632e4cebb7c721bedff87fde0ca8ee7ce87a5938d387`
- 锁解声音资源未变；未启动候选、未替换当前 V0037-R1 运行应用、未改 `dist`、偏好或权限。
- 没有实际用户点击/视觉验收；需要用户在当前或新候选设置页打开“模拟锁屏”观察顶部动画。

## 6. 保留与边界

- R7 默认关闭诊断、V0037 日历监控、音乐/歌词/设备/品牌、真实锁屏既有代码均保留。
- R8 Space 迁移撤销状态保持，不恢复 `SLSSpaceAddWindowsAndRemoveFromSpaces`、不修复原下浮、不改材质。
- 没有 Git 提交/推送、没有新增依赖、没有恢复定时器。
