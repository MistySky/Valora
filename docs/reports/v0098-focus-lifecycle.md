# V0098：锁屏玻璃与预览的焦点生命周期

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，分支 `codex/final-cleanup`。
只处理激活所有权；未改玻璃材质（darkAqua + variant 5）、锁解动画、选屏/位置、歌词/音量、设置与 UI。未 Git 提交；Objective-C/Perl 保持原样。

## 一、先核实的调用链与必要性

| 位置 | 原行为 |
|---|---|
| `LockMusicCoordinator.activateGlassSurface()` | `guard usePresentationSpace, !glassActivated` → `NSApp.setActivationPolicy(.regular)` + `activate(ignoringOtherApps:)` + `panel.makeKey()` |
| `LockMusicCoordinator.deactivateGlassSurface()` | 只 `NSApp.setActivationPolicy(.accessory)`，**不恢复原策略、不恢复先前应用** |
| `LockCardPreview.start()/stop()` | 同一套 `.regular` + activate；`stop()` 无条件 `.accessory` |
| 调用点 | 卡片 `present()` 时激活；隐藏/解锁(`beginUnlock` 各分支)/`stop()`/`suspend` 时释放 |

结论：激活是为了让面板成为 key、材质按"活动态"绘制。**这是本实现的观察与取舍，不是系统保证**；本轮据此保留该动作，只把它变成有所有权的、可逆的、保守的操作（注释也改成这个口径，不再宣称"原版如此/只有 key 才有玻璃"）。

## 二、最小修改

新增 `Sources/Valora/LockActivationOwner.swift`（约 130 行，无全局框架）：

- **记录真实原策略**：只有当前策略不是 `.regular`（即本次确实会改变）时才记录 `savedPolicy` 与进入前的前台 App bundle id；**嵌套/重复 acquire 不会覆盖**；已经是 `.regular` 时什么都不记，release 也不动策略，因此锁屏卡与预览互不干扰；
- **引用计数**：`acquire/release` 成对；未持有就 release → `not-owned`，不改策略；仍持有就 release → 不动；
- **保守恢复**：release 时先恢复策略；是否把先前应用拉回前台，必须同时满足
  1. 会话已解锁（`CGSSessionScreenIsLocked == false`）；
  2. Valora **仍然是**前台（用户没有切走）；
  3. 进入前的前台 App 仍在运行且不是自己；
  否则只恢复策略，并用 `lastReleaseReason` 记录原因（不含窗口标题/账号）。
- 生产 hooks 只读：`NSApplication.shared.activationPolicy()`、`NSWorkspace.shared.frontmostApplication`、`NSRunningApplication.runningApplications(withBundleIdentifier:)`、`CGSessionCopyCurrentDictionary()`；未新增 AX 权限，未读取窗口标题/账号。

接线：
- 协调器 `activateGlassSurface`/`deactivateGlassSurface` 改为 `activationOwner.acquire()/release()`（`glassActivated` 仍在，保证与原有调用点一一对应）；
- `LockCardPreview` 用自己的 owner 实例，`stop()` 不再无条件 `.accessory`。

## 三、定向验证（无窗口，注入 fake 钩子）

`Tests/ValoraTests/LockActivationOwnerTests.swift` 8 项全通过：

| 用例 | 断言 |
|---|---|
| 重复进入/退出 | `.regular` 只写一次、只激活一次；退出到底才恢复 `.accessory`，先前应用激活一次 |
| 未持有就 release | 不改策略，原因 `not-owned` |
| 锁屏卡与预览重叠 | 后进入者没改变策略 → release 不恢复；只有真正改变的那一方恢复 |
| 仍锁屏 | 策略照常恢复，**不**激活先前应用（`...not activated (locked)`） |
| 用户已切走 | 不抢焦点（`...focus moved`） |
| 先前应用已退出 | 不激活（`...gone`） |
| 本来已是 `.regular` | 不记录、不激活、release 不动策略 |
| 快速 5 次进出 | 策略写入 5 次 regular / 5 次 accessory，最终 `.accessory` |

回归：`LockMusicCoordinatorTests 32`（含锁屏/解锁/stop 的激活路径）、`LockCardLayoutTests 13`、`LockLyricsTrackChangeTests 8` 全部通过。

## 四、Release 交付

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0098-focus-lifecycle-candidate/Valora.app` |
| 版本 / 构建号 | `0.2.0` / **4**（计数器自动分配，`build-verification.json` 同为 4） |
| binary SHA-256 | `de71eb0b8dcb21a2516a63a5b356c8e2daa6db9fa483a1c4ca63d3fbf13ba39b` |
| 签名 | `codesign --verify --strict --deep` 通过 |

**替换方式（按要求不再 pkill）**：`osascript -e 'tell application "Valora" to quit'` → 等待后复查 **0 个实例** → `open -n` 新候选 → 复查**仅 1 个进程**，路径 `/private/tmp/valora-v0098-focus-lifecycle-candidate/Valora.app/Contents/MacOS/Valora`（PID 2823）。`dist` 未覆盖。

## 五、边界与待验

1. 真实锁屏下"恢复先前应用"是否如预期（解锁后仍在前台时才激活）**未实机验证**；本轮只证明所有权与守卫条件在注入钩子下正确，不宣称"密码焦点已修"。
2. 若系统在解锁瞬间把前台切给其它应用，`selfIsFrontmost` 会为 false → 只恢复策略，不抢焦点（保守，符合要求）。
3. 未展开后续批次：0.25s 调度、无效游戏检测、无用 View/外观字段、验证代码编译边界、文档整理。
