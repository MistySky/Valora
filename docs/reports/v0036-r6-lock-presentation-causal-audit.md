# V0036-R6 锁屏下浮原因核查与诊断完善

日期：2026-10-30
状态：仅完成因果审计与默认关闭诊断完善；**未宣称锁屏问题已修复，未启动候选、未改用户当前 V0037 应用或偏好**。
候选：`/private/tmp/valora-v0036-r6-diagnostic-candidate/Valora.app`
候选二进制 SHA-256：`edb4446c8cc5ba632c8689804bc46981954e348b0aaaf29874b69809b2078181`

## 1. 已确认事实

### 1.1 正常 `.playing` 与 `.locked` 的模型链

已逐段核查当前生产代码：

- `AppModel.visibleSize` 使用同一 `PresentationMetrics.stationarySize`：
  - 普通 compact 音乐：`liveActivity: .playing`；
  - 锁定：`liveActivity: .locked`；
  - 物理刘海分支两者均增加 74pt 宽度，高度为 `safeAreaTop`。
- `NotchView.topStrip` 是同一个 HStack，左翼从 `TransitioningArtwork` 切换为 `LockActivityGlyph`。
- `NotchShape.fill(.black)` 对普通音乐和锁定共用；这是刘海自身的形状绘制，不是“另画一个模拟硬件”的证据。
- `NotchGeometry.calculate` 先检测 `safeAreaTop > 0` 和 auxiliary left/right，再判断 `simulated`。当前实体 MacBook 屏幕下 `hasPhysicalNotch=true`，`forceSimulatedNotch` 不是自动跳过实体分支的条件。
- `WindowCoordinator` 当前 notch panel 始终为 624×320，顶边为 `display.frame.maxY`；R5 的屏幕大小 LockPanel frame 已撤销，锁定没有单独全屏 frame。

因此，“模型宽度/高度不同”与“shape.fill 是完整形状”目前**不能证明**下浮根因是模型另走模拟刘海。

### 1.2 尚未证实的差异

- 普通音乐不经过 `ARLockPresentationSpace` 的挂载；锁定经过 `LockMusicCoordinator` 的 Space 挂载/解锁 detach。相同视图和目标尺寸不等于 WindowServer 最终呈现相同。
- 可能是 panel `frame` 被系统重定位、`NSHostingView` 内容/安全区实际下移，或 Space 交接带来呈现变换。当前没有锁态真实窗口数据来区分。
- 旧 `/private/tmp/valora-notch-diagnostic.jsonl` 的 120 条记录已核对：
  - 全部 `phase=hidden`；
  - 全部 `sessionLocked=false`；
  - 约同一 panel `[552,797,624,320]`；
  - 普通状态耗尽限额，没有任何锁定阶段记录。
  
因此旧日志不能用于锁定根因，也不能证明或否定窗口/Space 假设。此前把 `forceSimulatedNotch=1` 当作唯一根因不成立；它是设置状态，实体检测分支本身优先。

## 2. 诊断修正

`Sources/Valora/NotchWindowDiagnostic.swift`：

- 新增纯 `NotchDiagnosticPolicy`：
  - 连续相同事件 key 去重；
  - 普通状态最多 24 条；
  - 锁/解阶段保留最多 96 条；
  - 总硬上限仍 120；
  - 不同阶段/几何/窗口状态 key 不同。
- 新增实际日志入口和字段：
  - `reason`、`phase`、display frame、safeAreaTop、menuBarHeight；
  - auxiliary 左右宽、`forceSimulated`、`hasPhysicalNotch`、compact、visibleSize、contour topInset；
  - anchor 前/后的 panel frame；
  - host frame/bounds/safeArea；
  - host 左上/内容顶部转换后的 screen point；
  - visible/sessionLocked/notchMounted/windowNumber。
- `WindowCoordinator.anchorPanelTop` 现在记录 **before/after**；`updateVisibility` 实际调用记录入口。
- `LockMusicCoordinator.updateNotchMount/detachNotchIfNeeded` 直接记录 `ARLockPresentationSpace` 的 before/after membership；只读本进程窗口的 Space 诊断。
- 诊断关闭时不调用 layout/geometry/Space 诊断路径，不增加常驻 timer、不枚举其他 App、不写媒体/日程/账号内容。

这是诊断完善，不是位置补偿；未添加任何 y 偏移或新锁定窗口。

## 3. 定向验证

命令：

```text
swift test --filter 'NotchDiagnosticPolicyTests|CalendarMonitorSharedTests'
```

结果：**8 项通过，0 失败**：

- 去重；
- 普通额度耗尽后仍保留锁阶段额度；
- 总硬上限；
- 锁定/解锁阶段边界 key；
- V0037 共享日历/面板可见性和路由回归未受影响。

未运行真实 NSWindow/NSStatusItem/Space、锁屏/睡眠/媒体/权限、`--verify-*`、截图/点击/循环/压力或全量。

## 4. 现有证据能否定位

不能唯一定位。当前能确认的是：

- 普通音乐与锁定使用同一模型几何/视图；
- 旧诊断全被普通 hidden 状态耗尽，不包含锁态；
- 锁定比普通音乐多一条 Space 挂载/所有权路径，但仅凭代码和手持视频不能确认是 window frame、hosting content 还是 WindowServer 变换。

不能据此继续加位置偏移或更换材质；也不能把 V0036-R5/R6 的静态/fake 测试当成实机通过。

## 5. 一次用户协助的最小取证方案

不启动/不替换用户当前 V0037 应用，不修改偏好。由用户或 Codex 在合适时用独立 R6 候选执行：

```text
VALORA_NOTCH_DIAGNOSTIC=/private/tmp/valora-r6-lock-diagnostic.jsonl \
  /private/tmp/valora-v0036-r6-diagnostic-candidate/Valora.app/Contents/MacOS/Valora
```

然后只做一次真实锁屏/解锁，完成后退出候选，读取日志。重点比较：

1. `.locking/.neutralizing/.locked` 的 `panelBefore/panelAfter` 与 `hostFrame/hostBounds/hostSafeArea`；
2. `contentTopScreen` 是否相对 `screen.maxY` 下移；
3. `hasPhysicalNotch/auxLeft/auxRight/compact/visibleSize/topInset` 是否在阶段间变化；
4. `recordSpace` 的 `before/after` membership 与 `windowNumber`；
5. `windowNumber` 是否在阶段中变化或重建。

如果 `panelBefore/After` 保持顶边而 `contentTopScreen` 下移，根因在 hosting/content；如果 panel frame 下移，根因在 NSWindow/WindowServer；如果只在 Space membership 变化附近出现，根因在 Space 挂载时序。该一次日志足以决定下一步最小修复，不需要反复录屏。

## 6. 构建与保留

- 一次 Release：`/private/tmp/valora-v0036-r6-diagnostic-candidate`。
- arm64，macOS 27.0，ad-hoc hardened runtime；`codesign --verify --deep --strict` 通过。
- 候选二进制 SHA-256：`edb4446c8cc5ba632c8689804bc46981954e348b0aaaf29874b69809b2078181`
- 锁解资源哈希不变。
- 未启动 R6 候选；当前 V0037-R1 运行应用、`dist`、用户偏好和 V0037 成果未改。
- 不处理材质、下载、Codex 或新模块；不 Git 提交/推送。

正式交付后停止等待 Codex 验收。
