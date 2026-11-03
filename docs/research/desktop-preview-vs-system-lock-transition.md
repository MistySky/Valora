# 桌面模拟 vs 真实系统锁屏：notch window 过渡差异

日期：2026-10-30
范围：只读代码/已有外部源码证据；不修改生产、不构建、不启动、不触发真实锁屏。
用户观察：V0038 桌面模拟加/解锁正常；真实锁屏仍出现顶部锁条与实体刘海分离。

## 1. 两条链的关键差异

| 环节 | 桌面模拟 `LockPreviewController` | 真实锁屏 `LockMusicCoordinator` |
|---|---|---|
| 锁事实 | 只改 `previewLockPresentationActive` / `previewLockIndicator`，`isSessionLocked` 保持 false | 真实 `isSessionLocked=true/false`，真实 `lockIndicator` 由系统锁事件驱动 |
| 窗口 | 复用 `WindowCoordinator` 的同一个 624×320 notch panel | 复用同一个 panel，但额外进入 owned presentation Space |
| Space | **不创建、不挂载、不迁移** | `ARLockPresentationSpace` 创建 level 400 Space，`CGSAddWindowsToSpaces` 加入 notch window；解锁 `CGSRemoveWindowsFromSpaces` |
| 窗口属性 | `level=CGShielding+1`，`.canJoinAllSpaces/.stationary/.ignoresCycle/.fullScreenAuxiliary` | 同一 WindowCoordinator 属性，不因锁态改 level/collectionBehavior |
| 顺序 | 本地状态 → 普通桌面合成 | 系统锁屏登录层/activeSpace 过渡 + 自有 Space 挂载/移除 |
| 锁屏底部内容 | 无 | `LockMusicCoordinator` 可显示独立音乐/设备窗口（非顶部 glyph） |
| 系统隐藏条件 | 不触发真实锁屏/睡眠 | `ScreenStateMonitor` 仍运行，可能响应 activeSpace/全屏/调度中心状态 |

已代码核对：

- `Sources/Valora/LockPreviewController.swift`：模拟只改 model 预览状态，不触碰真实 session、sound、Space、window factory。
- `Sources/Valora/LockMusicCoordinator.swift`：真实锁态在 `syncLockIndicator` 中按非 hidden 阶段调用 `updateNotchMount`；attach/detach 经由 `ARLockPresentationSpace`。
- `Sources/Valora/WindowCoordinator.swift`：普通/真实/模拟共用同一 panelFrame；窗口 collectionBehavior 和 level 不在锁定时改变。
- `Sources/NativeBridge/NativeBridge.m`：当前是 `CGSAddWindowsToSpaces` + 独立的 `CGSRemoveWindowsFromSpaces`，不是外部源码的迁移式 add-and-remove。
- `Sources/Valora/ScreenStateMonitor.swift`：使用 `CGWindowListCopyWindowInfo`/Space type 判断全屏、调度中心、游戏；真实锁屏过渡期间是否触发隐藏仍是未知，不应把隐藏当成已经排除或已确诊。

## 2. 已确认与仍是假设

### 已确认

- 桌面模拟不经过真实 Space/锁屏登录层，因此它不能证明真实锁屏窗口的最终屏幕位置。
- 真实锁屏与模拟共用同一 NotchView、同一模型几何、同一 panel frame；静态 `NSWindow.frame` 相同不能排除 WindowServer 合成变换。
- `.canJoinAllSpaces`、`.stationary`、level 等在模拟与真实路径相同，单凭这些属性不能解释差异。
- 真实路径的唯一显著窗口归属差异是：同一 notch window 被加入 owned lock Space，而模拟没有。

### 未确认的候选根因

1. **Space 成员迁移语义**：当前 add-only 可能让窗口仍属于普通桌面 Space；登录层/activeSpace 过渡可能让同一窗口在普通合成与锁屏合成中产生位置/缩放变换。现有证据不足以证明这是唯一根因。
2. **WindowServer 登录过渡**：系统自身锁屏缩放/位移可能作用于窗口合成，即使 AppKit `NSWindow.frame` 仍是屏幕顶。普通 frame 自报无法排除。
3. **宿主/SwiftUI 内容**：当前 R7 诊断会区分 panel、host、SwiftUI shape 三层，但尚未有真实锁态日志；不能先归因 Space。
4. **普通 primary window 未挂起**：DynamicNotch 在锁屏时隐藏普通窗口并另用锁屏 overlay；当前 Valora 未这样做。这是架构差异，不是已证实的本机根因。
5. **ScreenStateMonitor**：真实锁屏期间是否触发 `screenHidden` 仍未知；模拟不经过这些系统状态。

## 3. 外部源码对照（只读）

先前已读取的固定源码：

- boring.notch / SkyLightWindow：窗口通过 `SLSSpaceAddWindowsAndRemoveFromSpaces(connection, space, [windowNumber], 7)` 委托；这表达“加入目标并移除旧成员”，但不同应用/窗口结构和调用时机，不能直接推导本机根因。
- DynamicNotch：`suspendPrimaryWindowForLock` 隐藏普通 primary window；`LockScreenLiveActivityWindowManager` 创建独立顶锚 lock overlay，显式 `host.frame` 匹配 canvas，并在 activeSpace/screen/wake 时 `refreshPosition`；overlay 使用 `screen.frame.maxY` 锚定。它的正确性来自这套独立 ownership/刷新链，而不是某个单独 Space 函数名。
- 因此“外部用了迁移式 Space API”是一个需要验证的候选，不是可直接替换的修复；不能照抄 ABI、隐藏普通窗口或多窗口架构。

## 4. 最小可观测方案

### 4.1 先完成一次实机日志（不反复录屏）

使用现有 R7 诊断候选（或在下一候选构建后同路径启动一次），保持当前 wallpaper/display：

```text
VALORA_NOTCH_DIAGNOSTIC=/private/tmp/valora-lock-compare.jsonl \
  /private/tmp/valora-v0036-r7-diagnostic-candidate/Valora.app/Contents/MacOS/Valora
```

一次操作：

1. 在桌面模拟开关打开，记录一次 preview on/off（不触发真实锁屏）。
2. 关闭模拟后，真实锁屏一次、解锁一次。
3. 退出候选，读取同一日志。

同屏对照：

- `kind=window`：`panelBefore/After`、`hostTop`、`contentTopScreen`；
- `kind=swiftui-layout`：`globalRect`（SwiftUI 逻辑坐标，不是 WindowServer 像素）；
- `kind=space`：`windowSpaces` 的 old/new 列表；
- phase/sessionLocked 区分 preview/真实边界。

判读规则：

- panel 顶边和 hostTop 都不变，但实际视频仍下浮 → WindowServer 合成变换仍未在日志中体现，需进一步真实合成验证；
- panel 顶边变 → NSWindow/WindowServer 窗口位置；
- panel 顶边不变而 contentTopScreen 或 SwiftUI globalRect 变 → hosting/SwiftUI layout；
- 只有真实锁屏出现 `windowSpaces` 同时保留普通/锁屏成员，且下浮边界与 attach/detach 对齐 → Space 成员迁移候选得到支持，仍不能仅凭此断言唯一根因。

### 4.2 不应做的事

- 不根据该一次日志直接猜 y、加延迟、全屏化 notch 或替换私有 Space API；
- 不把R7诊断一次日志说成必然确诊；
- 不在真实日志中同时修改用户偏好/权限/运行包。

## 5. 当前结论

V0038 模拟正常只证明**模型动画和普通桌面合成路径**正常，不能证明真实锁屏 Space/登录过渡。当前最需要区分的是：

1. 真实锁屏是否改变 notch window 的 Space 成员；
2. 该变化是否伴随 WindowServer 合成位置变化；
3. hosting/SwiftUI 顶部实际布局是否改变。

在生产代码没有真实锁态 frame/SwiftUI layout/Space 对照数据前，不进行新修复。等待取证后再决定最小修复路径。
