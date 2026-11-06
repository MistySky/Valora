# V0039-R1 独立验收限定返修：overlay 生命周期与诊断

日期：2026-10-31
状态：限定返修完成，等待 Codex 独立验收；**候选未启动，当前用户运行包/dist 未动，真实锁屏未操作**。
候选：`/private/tmp/valora-v0039-r1-isolated-lock-candidate/Valora.app`
候选二进制 SHA-256：`fb09dbbec464cf8310773a7b0e051b9f9350b26f45855b5c2cf54eb7fb43fbe2`

## 0. 实机日志复核（2026-11-03 live 候选）

读取用户 live 候选的 `/private/tmp/valora-v0039-r1-live-20261103.jsonl`：

- overlay 记录实际出现 `reason=failure:space-migration-failed`，`windowSpaces` 为 unknown；
- primary 仍留在普通桌面，诊断中的 Quartz unlock bounds 仍缩小/下移（约 568×292 @x580/y50），因此用户“还是一样”是由 **overlay 迁移失败后 fallback primary** 造成的；
- 已定位一个具体触发条件：overlay 在首次查询/迁移前尚未 order，`windowSpaceIDs` 没有普通 Space 成员，保守迁移 precheck 返回失败。

这不是新的猜测；此前的独立测试只验证 fake migration，未暴露真实窗口必须先进入普通 Space 才能被查询/迁移的时序。

## 1. 修复项

### 1.1 overlay 失败不在普通 media refresh 反复重建

`LockMusicCoordinator` 增加锁定周期/屏幕失败门控：

- `lockAttemptGeneration` 在真实 lock edge / 初始已锁定 / 重锁时递增；
- `overlayFailureAttempt + overlayFailureFrameKey` 记录当前锁定周期和屏幕 frame；
- 同一 lock attempt/同一屏幕的普通 media/refresh 不再次 `makeWindow/migrate/close`；
- `wake`、`receiveScreensChanged` 和新的 lock cycle 会清空失败门，允许有限重试；
- `stop` 清空门控；没有计时循环或无限重试。

新增回归 `testIndependentOverlayFailureDoesNotRecreateOnOrdinaryRefresh` 通过（window count 保持稳定）。

### 1.2 原 native overlay 所有权登记与失败清理

`Sources/NativeBridge/NativeBridge.m` 的 overlay 专用迁移：

- overlay 创建后先透明（alpha=0）orderFront，使其进入普通桌面 Space；
- 迁移前查询并保存普通 Space 成员；
- 只调用当前自有 overlay window；
- 迁移后要求查询结果**恰好为目标 owned Space**；
- 成功时把窗口 number 登记到 `_windows`，因此 release 的 `detachWindowNumber` 不再是 no-op；
- 失败/部分成功/query unknown：
  - 移除可能加入的目标 Space；
  - 恢复捕获的普通桌面成员；
  - 返回 false，不 pretend ready；
- 未改变 primary 的原 add/remove 路径，不恢复 R8 全局严格 gate；primary fallback 继续可见。

### 1.3 120 诊断额度重新分配

`NotchDiagnosticCapturePolicy` 调低每 phase/kind lane：

- `swiftui-layout 3`、`window 4`、`space 3`、`overlay 4`、`event 2`；
- 完整 `locking→neutralizing→locked→unlocking→restoring` 重放后仍有额度写入 `returned-to-desktop` 和 unlock 事件；
- 保留 phase/kind 分车道、去重、rate limit 和总上限 120；
- 新增 `testIndependentOverlayTrafficStillLeavesFinalHandoffRecords` 通过。

### 1.4 overlay 专用 hosting 配置

`LockRuntimeAdapters.swift` 增加：

- `LockNotchOverlayHostingView`：`NSHostingView<AnyView>`，`safeAreaInsets = zero`；
- `LockNotchOverlayWindowFactory`：`NotchPanel`，透明、非激活、忽略鼠标，`sizingOptions=[]`，显式 624×320 frame 由 coordinator 设置；
- `diagnosticHostFrame` 暴露真实 host frame；
- overlay 不再复用 generic music-card hosting / `NSHostingView` 默认 safe area；
- 固定 `screen.frame.maxY`，无入场 origin/scale 动画。

### 1.5 overlay 生命周期诊断

`LockMusicCoordinator` 新增 `recordOverlayState(reason:)`：

- overlay ready、reposition、每个真实 phase（含 unlocking/restoring）以及 release 前记录；
- 记录 role `lock-overlay`、windowNumber、panel frame、host frame、可见实际值、Quartz own bounds、Space 成员；
- 主动 reposition（screen/active space 更新）也记录；
- release 前使用实际 `isVisible`，不写死 false；
- 现有 primary record 带 `role=primary`；
- 不新增常驻 timer，只事件驱动并受 lane 限流。

## 2. 保留的既有成果

- primary/overlay ready 门控互斥；overlay 失败 primary fallback 可见；
- open glyph 同宽 → `.restoring` neutral → geometry completion 后音乐 withAnimation 恢复；
- 无音乐停在基础 neutral；
- 快速锁解/重锁、旧 completion/token、sleep/wake/stop/masteroff 清理；
- V0038-R1 模拟预览（不 Space/声音/额外窗口）保留；
- 真实锁事实与呈现 stage 分离；
- R8 迁移失败历史不回退，primary 仍走已知 add/remove。

## 3. 定向验证

命令：

```text
swift test --filter 'LockMusicCoordinatorTests|LockPreviewControllerTests|NotchDiagnosticCaptureTests'
```

结果：**37 项通过，0 失败**：

- LockMusicCoordinatorTests 25；
- LockPreviewControllerTests 9；
- NotchDiagnosticCaptureTests 3（含 overlay traffic/final handoff 额度）。

未运行全量、真实 NSWindow/NSPanel/Space、锁通知、声音/媒体/设备/权限、自动点击/截图/循环/压力。

限制：本轮没有创建真实私有 Space 或真实 native callback harness；原生迁移由源码审查覆盖，Swift fake Space/overlay factory 覆盖成功与失败 fallback、detach 和 primary 可见性。缺符号/真实 ABI 行为仍需实机诊断。

## 4. 构建与候选

- Release 一次：`/private/tmp/valora-v0039-r1-isolated-lock-candidate`。
- arm64、macOS 27.0、ad-hoc hardened runtime；`codesign --verify --deep --strict` 通过。
- 候选二进制：`fb09dbbec464cf8310773a7b0e051b9f9350b26f45855b5c2cf54eb7fb43fbe2`
- 候选 Info.plist `LSEnvironment`：
  `VALORA_NOTCH_DIAGNOSTIC=/private/tmp/valora-v0039-r1-lock-handoff.jsonl`
- 锁解声音资源哈希不变。
- 候选未启动；当前 capture-v2/旧候选、用户 App、`dist`、偏好、权限、归档均未动；无 Git/定时器。

## 5. 仍需用户实机

- overlay Space 迁移是否成功且确实只在目标 Space；失败时 primary fallback 是否保留。
- 真实锁屏/解锁顶部是否固定在硬件刘海顶，是否仍跟系统缩放/下移。
- open glyph→neutral→音乐 continuous timing/是否有跳变或停顿。
- 真实底部 Glass/设备卡、物理双屏；不能以 fake 或本轮签名宣称系统下浮已修好。
