# V0036-R7 外部源码与内容/空间位置审计

日期：2026-10-30
状态：诊断与根因候选审计完成；**未修改锁屏呈现修复，未启动候选，未替换当前 V0037-R1 应用**。
候选：`/private/tmp/valora-v0036-r7-diagnostic-candidate/Valora.app`
候选二进制 SHA-256：`d2844a4989e85185fbc6de8a94e522706a88e54090950ec8728437ce1e5491b0`

## 1. 结论

本轮不把“相同模型尺寸”当成屏幕锚定已通过。现有证据仍不能唯一定位下浮原因；R7 完成的是可审查的外部源码对照、内容坐标修复、Space 成员实际查询和一次性取证路径。

目前最可信的**候选根因路径**是：

1. 当前 notch window 通过 `CGSAddWindowsToSpaces` 加入 owned presentation Space，但没有把窗口从普通桌面 Space 移除；解锁时再 `CGSRemoveWindowsFromSpaces`。这会让同一自窗口同时保留普通/锁屏空间成员关系。
2. 外部 boring.notch / SkyLightWindow 与 DynamicNotch 均使用 `SLSSpaceAddWindowsAndRemoveFromSpaces(connection, space, [windowNumber], 7)`，其语义是加入锁屏/目标 Space 并移除其它 Space 成员；当前实现只添加。
3. DynamicNotch 进一步隐藏普通 primary window，单独创建顶锚 lock overlay，显式设置 host.frame，并在 activeSpace/screen/wake 时刷新位置。当前 Valora 复用普通 notch window，没有这层独立 ownership/refresh；这可能是空间过渡时出现双重呈现或坐标变换的路径。

这些是**代码候选**，不是已证实的唯一根因。没有真实锁态 frame/Space 数据前，不能直接更换私有 API、照搬外部多窗口架构或增加 y 偏移。

## 2. 外部源码只读核对

外部源码位于 `/private/tmp/valora-lock-open-source`，未执行、未加入依赖：

- boring.notch `23e7705a4ffcb5d97a54fb1d4135e180084a566d`
  - `BoringNotchSkyLightWindow.enableSkyLight` 调用 SkyLightWindow；
  - SkyLightWindow `b7bd99f62a0673a99bed4bfd31098ca1dcdd10eb` 的 `delegateWindow` 使用 `SLSSpaceAddWindowsAndRemoveFromSpaces(connection, space, [windowNumber], 7)`；
  - `undelegateWindow` 另有移除路径。
- DynamicNotch `41ea276e4eaa0c774f2a251af169791a8c44fd81`
  - `SkyLightOperator` 同样使用迁移式 `SLSSpaceAddWindowsAndRemoveFromSpaces`；
  - `AppDelegate+Window.suspendPrimaryWindowForLock` 隐藏普通 primary window；
  - `LockScreenLiveActivityWindowManager` 创建独立顶锚 overlay，host.frame 显式匹配 canvas，委托 `lockScreenNotchOverlay`，并在 activeSpace/screen/wake 时 `refreshPosition`；
  - `OverlayWindowLayout.topAnchoredFrame` 使用 `screen.frame.maxY`，不是 visibleFrame。
- 当前 Valora/复刻：
  - `ARLockPresentationSpace` 创建 level 400 Space，调用 `CGSAddWindowsToSpaces` 和 `CGSRemoveWindowsFromSpaces`；
  - 复用 `WindowCoordinator` 的 624×320 notch panel；
  - 没有隐藏普通 primary niche window / 独立顶锚 overlay。

因此外部实现提示了 **Space 迁移语义和 primary/overlay 分离**两个差异，但不能从源码直接断言哪一个是本机 macOS 27 的实际根因。

## 3. R6 诊断缺口修复

### 3.1 内容坐标

`WindowCoordinator.recordDiagnostic` 现在：

- 由 `NSView.isFlipped` 决定 host 顶部：非 flipped 用 `maxY`，flipped 用 `minY`；
- 字段明确拆分：
  - `hostFrame` / `hostBounds` / `hostSafeArea`；
  - `hostTop`（局部坐标）；
  - `contentTopScreen`（经 `NSView.convert` 和 `NSWindow.convertPoint(toScreen:)` 转换）；
- 不再把 hosting 边界称为 NotchShape 顶点。

新增纯坐标函数 `NotchDiagnosticCoordinate`，无 UI 测试覆盖：

- 非翻转 `maxY` / 翻转 `minY`；
- 负屏幕 origin 的 window→screen 逻辑换算。

### 3.2 实际 SwiftUI notch 区域 probe

默认关闭；只有 `VALORA_NOTCH_DIAGNOSTIC` 启用时：

- `NotchView` 的 `shape.fill(.black)` 上插入 `NotchLayoutProbe`；
- GeometryReader 记录 `source: NotchView.shape` 的 SwiftUI **global logical** rect；
- 字段命名为 `globalRect`，不冒充 WindowServer/屏幕像素坐标；
- 没有常驻 timer；去重/限额沿用 policy。

该 probe 只在诊断模式插入，不改变正常绘制；它不能单独证明最终屏幕呈现。

### 3.3 Space 成员查询

`ARLockPresentationSpace` 增加自有窗口查询：

- `windowSpaceIDs:` 使用 `CGSCopySpacesForWindows`（mask 0xF），只查询当前 `windowNumber`；
- 查询失败/符号不可用返回 nil，诊断写成 `"unknown"`，不伪造 `[space]` 或 true；
- `LockMusicCoordinator` 在 attach/detach 前后记录 `windowSpaces`、Space owned count 和 window number；
- 仍不枚举其他 App 窗口或内容。

注意：Space 查询列表存在不等于真实 WindowServer 最终画面；它是用于判断普通桌面/锁屏 Space 是否同时保留。

### 3.4 限额

- 连续相同 key 去重；
- 普通 24 条 + 锁阶段 96 条，总硬上限 120；
- 锁/解/neutral/anchor/Space 变更优先保留。

## 4. 定向验证

命令：

```text
swift test --filter 'NotchDiagnosticPolicyTests|LockMusicCoordinatorTests'
```

结果：**29 项通过，0 失败**（6 policy/坐标 + 23 fake lock coordinator）。

新增覆盖：

- host flipped / 非 flipped 顶部；
- 负屏幕 origin 逻辑转换；
- 去重、普通/锁额度、总上限、锁阶段 key；
- R4/R5/R6 既有 epoch、Space ownership、geometry、window detach、R6 诊断不变。

未运行真实 NSStatusItem/NSPanel/Space、锁屏/睡眠/声音/媒体/权限、`--verify-*`、截图、循环或压力。

## 5. 最小修复候选（尚未实施）

优先级依据待实机诊断确认，不在本轮直接改：

1. **若日志显示 window 仍同时属于普通和锁屏 Space，且下浮只在 Space 迁移附近出现**：
   - 最小候选是把当前“仅 add + 后 remove”改为外部源码同类的“加入目标 Space 并移除其它成员”语义；
   - 需要先在 macOS 27 验证固定符号/参数/ABI、失败回滚和普通桌面归属恢复；不能盲替换并照搬外部实现。
2. **若 `panelBefore/After` 顶部始终正确而 `contentTopScreen` 或 SwiftUI layout probe 下移**：
   - 根因在 hosting/content layout，不应改 Space/窗口 API；需要检查安全区、host frame、SwiftUI top alignment。
3. **若普通 window 与锁屏 overlay 同时可见**：
   - 才评估 DynamicNotch 式 suspend primary + independent top overlay；这属于更大架构，不作为本轮自动修复。

没有实机日志前，不添加固定 y、全屏 frame、延迟或猜测的私有 API 调用。

## 6. 一次用户协助取证

不启动当前 V0037 应用，不替换偏好。由用户/Codex在适合时机独立启动 R7 诊断候选：

```text
VALORA_NOTCH_DIAGNOSTIC=/private/tmp/valora-r7-lock-diagnostic.jsonl \
  /private/tmp/valora-v0036-r7-diagnostic-candidate/Valora.app/Contents/MacOS/Valora
```

只锁/解一次，退出候选后读取：

- `kind=window` 的 `panelBefore/After`、`hostTop`、`contentTopScreen`；
- `kind=swiftui-layout` 的 `globalRect`；
- `kind=space` 的 `before/after.windowSpaces`；
- `phase=locking/neutralizing/locked/unlocking/restoring`。

但不能承诺“一次日志必定确诊”：若 WindowServer 只改变最终合成而不反映到 NSWindow/NSView/SwiftUI layout，仍需进一步针对真实呈现或外部 Space 迁移做验证。

## 7. 构建/边界

- 一次 Release：`/private/tmp/valora-v0036-r7-diagnostic-candidate`。
- arm64、macOS 27.0、ad-hoc hardened runtime；`codesign --verify --deep --strict` 通过。
- 候选未启动；当前 V0037-R1 运行应用和 `dist` 未替换；未改偏好/权限/系统设置。
- 未 Git 提交/推送；外部源码只读，未新增依赖。
- 材质、下载、Codex、设备及新模块不处理。
