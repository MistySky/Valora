# 桌面鼠标移动：窗口鼠标接收状态去重

2026-11-09。执行：新 OpenCode 会话（GLM-5.3-Flash）、分支 `codex/idle-cpu-optimization`。按 `docs/opencode-tasks/desktop-pointer-window-state-dedup.md` 处理。改动仅限 `Sources/Valora/WindowCoordinator.swift` 的鼠标接收状态赋值点与新增测试文件；未改鼠标事件监听频率、命中判断、悬停/进入/退出/激活/拖动/锁屏/多屏语义，未触碰歌词优化与预筛选。未操作真实鼠标/播放、未启动或替换用户 App（build34/33 运行实例未动）、未打包安装、未提交推送。

## 一、实测证据边界（Codex 提供，本批未重测）

build34 暂停播放、远离刘海晃动鼠标约 30s：13 次采样均值 14.4%（8.5–20.2%）；静止约 20s：11 次均值 0.4%（0.1–0.9%）。栈 `/private/tmp/valora-build34-paused-moving-20261109.txt` 含 `WindowCoordinator.trackMouse` → `NSWindow.setIgnoresMouseEvents` → `_setEventMask` → `SLSSetWindowEventMask`，也含系统事件处理与音频输出查询，不能按样本数断言各成分占比。本批目标只是消除其中确定真实的重复赋值成分。

## 二、实现（`WindowCoordinator.swift`）

- 新增静态幂等辅助（生产代码，非 debug 区域）：

  ```swift
  static func setIgnoresMouseEvents(of panel: NSPanel, _ value: Bool) -> Bool
  ```

  **每次调用都读取该 NSWindow 的当前真实 `ignoresMouseEvents`**；仅目标值不同才赋值并返回 true，相同则不触碰 setter。没有自维护缓存，因此可见性/锁屏/预览等其他路径的直接赋值会在下一次鼠标事件自然被读出并按需纠正一次。
- `trackMouse(at:)` 两处调用点替换为该辅助：
  - 常规分支 `record.panel.ignoresMouseEvents = !inside` → `Self.setIgnoresMouseEvents(of: record.panel, !inside)`；
  - 会话锁分支 `= true` 同样幂等化（锁屏语义不变：全部面板忽略事件、pointerInside 清零、hover 取消、presenter.pointerEntered(false)）。
- `updateVisibility` 的直接赋值路径（隐藏/锁屏 orderOut/锁定回退）保留原样：它们继续充当强制纠偏路径，且不在逐事件热路径上。
- debug-only 可观测性（`#if VALORA_DEVELOPMENT`，两条 Release 均无）：`PointerStateDiagnostics`，`assignments` 只在真实赋值处递增，`skippedUnchanged` 记录未达 setter 的事件。
- 验证访问器：`verificationIgnoresMouseEvents(screenID:)` 读取真实属性；`verificationSetIgnoresMouseEvents(screenID:_:)` 绕过辅助直接赋值，用于模拟外部路径修改。

## 三、独立回归（新增 7 项，`Tests/ValoraTests/IndependentPointerWindowStateTests.swift`）

可注入 `NSPanel` 子类（实际 setter 计数）+ 真实协调器双屏面板（计数/断言都在真实辅助赋值点）：

1. `testHelperSkipsTheSetterWhenTheLivePropertyAlreadyMatches`：同值调用不触发真实 setter（外部预先赋值产生的 didSet 计数不增加）；真正变更恰好触及 setter 一次；外部再改后同值调用仍跳过（证明读取的是实时属性而非缓存）。
2. `testRepeatedOutsideMovesAssignOnlyWhenStateDiffers`：静止外部态首个事件把两块面板各翻转一次（2 次赋值）；重复两次相同事件零赋值；外部把其中一块改回接受态后下一事件只纠正该块（第 3 次赋值）。
3. `testEnterAndLeaveAssignTheCorrectTargetExactlyOnce`：进入内建刘海：内建接受(1)、外部屏忽略(2)，presenter 进入；重复进入事件零赋值；离开仅内建翻回(总共 3)。悬停关闭以隔离窗口状态语义（悬停体验由既有悬停用例承担）。
4. `testScreensTrackTheirStateIndependently`：同一事件下仅外部漂移的那块屏被纠正，另一块不动；镜像方向同样成立。
5. `testPointerInteractionStopsTrackingWithoutAssignments`：`pointerInteractionActive` 期间 trackMouse 提前返回，外置漂移零纠正、属性保持；交互结束后首个事件恰纠正一次。
6. `testSessionLockedBranchAssignsIgnoresOncePerScreen`：锁分支逐屏幂等赋 true（漂移屏 1 次赋值、已锁屏跳过），presenter 退出指针。
7. `testHiddenVisibilityBranchKeepsItsDirectAssignment`：`showNotch=false` 隐藏路径保持原有直接赋值（orderOut + ignores，不计入辅助计数）。

无压力循环/无批量闪窗；每用例固定少数几次驱动调用。

## 四、复跑定向回归与构建

| 组 | 结果 |
|---|---|
| 复跑预筛选 + 多屏/悬停/交互 + 锁屏相邻（`IndependentPointerWindowStateTests|IndependentNotchPrefilterTests|NotchHitTestPrefilterTests|MultiDisplayCoordinatorTests|IndependentInteractionTests|LockMusicCoordinatorTests|LockActivationOwnerTests|IndependentLockActivationLifetimeTests|LockLyricsTrackChangeTests`） | **执行 90，跳过 0，通过 90，失败 0**（既有断言未删改；新 7 项全过）；日志 `/private/tmp/valora-pointer-dedup-regression.log` |
| 普通 Release `swift build -c release --product Valora`（scratch `/private/tmp/valora-pointer-dedup-normal-release`，binary 5,417,496 B） | 成功；实验符号 `nm` 计数 **0**；`PointerStateDiagnostics` 字符串 **0**（debug-only 编译边界守住） |
| 实验 Release `VALORA_LYRICS_EXPERIMENT=1 …`（scratch `/private/tmp/valora-pointer-dedup-exp-release`，5,681,752 B） | 成功；实验实现 `nm` 计数 **147**，实验代码与状态去重并存 |

## 五、未验 / 风险

- **真实抖动 CPU 未测**：本次去重消除的是「属性未变仍下发 `SLSSetWindowEventMask`」这一确定重复成分；用户对照采样中的系统事件处理与音频查询成本仍在，且短时对照本身不构成降幅承诺。真实鼠标手感、悬停时延、多屏真实布局需用户在下一候选实测复查。
- 未实现媒体/锁屏/发版集成：改动超出指针状态的验证留待 Codex 全量与真实视图验收。
- NSPanel 属性读取每事件 O(1)，但未做微观基准（按约定禁压力基准）；属性读取本身若有未预期成本，只影响 debug 工具无关的生产路径——生产代码现在是每事件一次普通属性读 + 变化时才一次赋值。
- 1x、真实物理多显示器、锁屏真实交互未改动且未增验；歌词实验与预筛选保持现状无回归（复跑证据见上）。

## 六、回退

最小可回退：把 `trackMouse(at:)` 两处 `Self.setIgnoresMouseEvents(...)` 恢复为原直接赋值（辅助与访问器/诊断可整体删除，行为回到逐事件无条件赋值）；`PointerStateDiagnostics` 仅 debug 存在，无 Release 代码路径。

## 七、边界

未操作真实鼠标/播放/权限/设备、未启动/替换 App、未打包安装、未提交推送；未改事件监听 API/频率、预筛选范围、悬停调度、命中范围、锁屏交互、歌词实现、菜单栏/日历/监控/Codex 用量。完成后停止，等 Codex 独立验收。
