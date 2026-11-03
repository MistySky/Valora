# V0039 真实锁屏独立顶部承载与锁解音乐交接

日期：2026-10-30
状态：实现与定向 fake 验证完成，等待 Codex 独立验收；**候选未启动，未替换当前运行应用，真实锁屏/Space 未在本轮操作**。
候选：`/private/tmp/valora-v0039-isolated-lock-candidate/Valora.app`
候选二进制 SHA-256：`8146e25f3122c0e46ede3464d573a2739a5eb1114a1dd70d579094cd4d1a7543`

## 1. 已有真实证据

`docs/verification/direct-lock-capture-v2/live-result/decision.md` 已记录：

- 同一个 window 2442，AppKit frame 长时间保持 `[552,797,624,320]`，host `624×320`，`contentTopScreen=1117`；
- 解锁阶段 Quartz 呈现 bounds 变为约 `580×298 @ x574/y40`，随后恢复 `624×320 @ x552/y0`；第二轮再次出现类似缩小/下移；
- 锁中 `windowSpaces=[1,145]`，桌面 `[1]`；两种成员保留是实测事实，但不能单独证明唯一因果；
- 因此本轮不是本地 glyph/y 偏移或动画 duration 修复，而是真实锁屏承载隔离和中性几何交棒。

用户视频 `3a4155c3...` 与已有原版对照仍表明：软件锁屏区域整体受系统窗口合成影响，不是硬件刘海/本地 glyph 单独移动。

## 2. 实现

### 2.1 独立真实锁屏 overlay

`Sources/Valora/LockMusicCoordinator.swift` 增加真实锁屏专用 overlay：

- 仅在真实 `model.isSessionLocked` 且 lock 阶段进入 `.neutralizing/.locked` 后创建；
- 复用现有 `NotchView`、`LockIndicatorState`、`PresentationMetrics` 几何和 compact activity 动画；
- overlay frame 固定 `screen.frame.maxY`，显式 `host` 内容由现有 `LockPresentationWindowFactory` 创建；
- 不新建下方黑条，不另设计锁 glyph，不更换音乐 UI。
- overlay level 使用 `CGShieldingWindowLevel()+1`，尺寸仍 624×320，内容顶部锚定。
- overlay 只在活动屏动态锁态使用；普通多屏策略未重改。

### 2.2 Space 所有权与失败降级

`Sources/NativeBridge/NativeBridge.m`：

- 普通 primary 仍保留原 `CGSAddWindowsToSpaces/CGSRemoveWindowsFromSpaces` 已知可显示路径，不恢复 R8 的全局迁移 gate。
- 新增 **只给独立 overlay 使用** 的迁移方法：
  - 动态加载固定外部源码同类的 `SLSSpaceAddWindowsAndRemoveFromSpaces(..., 7)`；
  - 只操作本进程自己的 overlay window；
  - 迁移后查询 `CGSCopySpacesForWindows`，要求结果恰好只有目标 owned Space；
  - 符号缺失、返回失败、查询 unknown 或多空间成员都返回 false，不假称成功。

`LockMusicCoordinator.ensureOverlay()`：

1. 创建 overlay 并设置固定顶部 frame；
2. 迁移到 owned Space；
3. 只有查询验证为恰好目标 Space 才设置 `lockOverlayReady=true`；
4. 只有 ready 后 `WindowCoordinator` 才隐藏普通 primary；
5. 任何失败都关闭 overlay，保留 primary 作为已知可见 fallback，并记录失败原因；
6. 不采用 R8 的“unknown 就全局隐藏 UI”行为。

### 2.3 所有权表

| 对象 | 所有者 | 锁定期 | 解锁/收尾 |
|---|---|---|---|
| 普通 primary notch | WindowCoordinator | 真实锁 overlay ready 前短暂保留；ready 后 orderOut，不进入锁屏 Space | overlay neutral completion/隐藏后恢复普通音乐 |
| lock notch overlay | LockMusicCoordinator | 独立 window，迁移到仅目标 owned Space，固定 top | 保持 open glyph→neutral；完成后 detach/close，primary 接回 |
| 锁屏音乐卡 | LockMusicCoordinator 独立 panel | 原行为保留 | unlock 立即 orderOut/detach |
| 设备信息卡 | LockMusicCoordinator 独立 panel | 原行为保留 | unlock 隐藏/detach |
| 模拟预览 | LockPreviewController + primary | 不创建 Space/overlay | 关闭恢复普通音乐，不触发真实 session |

- overlay 失败：`lockOverlayReady=false`，primary 继续显示；不会出现“锁屏完全消失”。
- sleep/wake/stop/masteroff：取消 task、释放 overlay、清理 Space；真实 primary 按已知路径恢复。
- 活动屏变化通过现有 `notchWindowUpdates` 更新 overlay 顶部位置；不增加常驻 orderFront timer。

## 3. 锁/解动画交接

### 锁定

- primary 先保留已有音乐/扩展内容，执行现有 `presenter.collapse`；`.locking` 阶段不提前新建 overlay。
- 到达 neutral 边界后创建并验证 overlay；overlay 使用同一 hardened `NotchView` 显示 neutral → lock 两翼扩展。
- 不加窗口 origin/scale 入场动画；overlay 固定屏幕顶，形状仍来自实体 hardware geometry。
- 无音乐时 neutral 基础刘海直接展开锁；有 compact 音乐时先回基础；完整播放器先完成既有 collapse。

### 解锁

- overlay 保持 locked 宽度和同一 `LockActivityGlyph`，进入 `.unlocking` 显示 open glyph；不先隐藏再出现独立符号。
- 0.8 现有 open-glyph 停留保留；之后 overlay 进入 `.restoring` neutral。
- neutral geometry animator completion 前，音乐不恢复；completion 后才释放 overlay，显示 primary，并用现有 compact music `withAnimation` 展开当前最新媒体。
- 无音乐停在基础刘海。
- 旧 **V0038-R1** 的预览恢复 `withAnimation` 保持；本次只改变真实锁屏承载/交接，不改用户已认可的模拟 UI。

## 4. 诊断

默认关闭；普通构建不启用诊断。R0039 候选通过 `Info.plist` `LSEnvironment` 固定：

```text
VALORA_NOTCH_DIAGNOSTIC=/private/tmp/valora-v0039-lock-handoff.jsonl
```

记录：

- primary/overlay 各自 `role`、windowNumber、frame、Quartz own-window bounds；
- overlay handoff ready/failure/release；
- Space `before/after` 自有窗口成员和 query unknown；
- phase 使用真实/预览来源，避免无角色合并；
- 现有 120 总限额与 phase/kind 分车道、去重、锁阶段保留。

不枚举其他 App，不读取媒体标题/日程/账号，不截屏。候选未启动，诊断也未运行。

## 5. 定向验证

命令：

```text
swift test --filter 'LockMusicCoordinatorTests|LockPreviewControllerTests'
```

结果：**33 项通过，0 失败**（24 lock coordinator + 9 preview）。

新增/保留覆盖：

- 真实锁 primary/overlay 互斥：overlay ready 后 primary 不挂锁屏 Space；overlay 使用目标窗口；
- overlay 迁移失败时 primary fallback 保持可见；
- open glyph 宽度不变 → `.restoring` neutral → geometry completion 后音乐 `.playing` 宽度恢复；
- 无音乐最终 neutral；
- 快速 lock/unlock、旧 completion/geometry token 拒绝；
- sleep/wake/stop/masteroff 清理；
- 当前 notch provider/旧窗口解绑；
- 已正常 preview 不产生 Space/声音/额外窗口副作用；
- 原有锁屏 state/epoch/information/deadline 回归。

没有真实 NSPanel/NSPopover/Space、锁通知、声音/媒体/设备/权限、全量、`--verify-*`、点击/截图循环/压力测试。

## 6. 构建、候选与诊断

- 一次 Release：`/private/tmp/valora-v0039-isolated-lock-candidate`。
- arm64，macOS 27.0，ad-hoc hardened runtime；`codesign --verify --deep --strict` 通过。
- 候选二进制：`8146e25f3122c0e46ede3464d573a2739a5eb1114a1dd70d579094cd4d1a7543`
- 锁解声音资源哈希不变。
- 候选 `Info.plist` 已配置诊断 LSEnvironment 路径；候选未启动。
- 用户当前运行应用和 `dist` 未退出/覆盖/替换；未改偏好/授权/归档；未 Git；未恢复定时器。

## 7. 必须由用户实机确认

- overlay 在本机 macOS 27 的 Space 迁移能否通过“恰好目标 Space”验证；若失败，当前预期是 primary fallback 保留而不是消失。
- 真实锁屏/解锁时 overlay 是否固定在硬件刘海顶部，不再随系统锁屏缩放/位移。
- 解锁 open glyph→neutral→音乐的连续体感、是否还有跳变/停顿。
- 真实底部 Glass 音乐卡/设备卡、真实双屏、声音和耳机链路仍需用户实机。
- 不能以本轮 fake/签名或模拟动画宣称真实锁屏已修复。

正式交付后停止等待 Codex 验收。
