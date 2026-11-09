# 鼠标移动 CPU：热路径收窄与透明宿主点透

2026-11-09。用户要求解决当前鼠标移动导致 CPU 升高的问题。本轮只改 `Sources/Valora/WindowCoordinator.swift` 的鼠标热路径和对应定向测试；未改 UI、动画、媒体、音频、锁屏、歌词实验、窗口层级或多屏职责。按 2026-11-09 自动替换约定，构建并替换唯一运行实例。

## 一、根因

现有版本已经做了两项前置优化：远离轮廓时的保守范围排除，以及 `ignoresMouseEvents` 同值去重。但每次全局/本地鼠标移动仍然会：

1. 对每个面板查询 `model.visibleSize`、`model.contour`、`hoverScale`，然后做坐标变换；这些是 SwiftUI 几何链，不是纯 C 坐标运算。
2. 指针靠近轮廓时重复构造 `NotchShape.path(in:)`，并执行 `Path.contains`。
3. 每次事件读取 `NSPanel.ignoresMouseEvents`；更重要的是，`updateVisibility()` 在每次可见性更新时把 `ignoresMouseEvents` 重新设为 `false`，会把刚在鼠标离开时设回的 `true` 撤销，使 624×320 透明宿主重新接收桌面鼠标事件。

用户采样栈中已经出现 `trackMouse → containsMouse → NotchShape.path` 和 `setIgnoresMouseEvents`，与上述链路一致。采样计数不能直接换算 CPU 百分点，但本轮针对的是确定存在的重复工作量。

## 二、修改

### 1. 先做屏幕坐标粗筛

`WindowCoordinator.containsMouse` 在查询模型/SwiftUI 几何之前，先以 `panel.frame.insetBy(dx: -96, dy: -96)` 做屏幕空间排除。96pt 覆盖刘海两侧肩部与 hover scale；粗筛只排除确定在外的点，范围内仍走原来的精确几何和路径判断。

鼠标在桌面其他区域移动时，不再读取 `visibleSize/contour`，不再做路径构造。

### 2. 缓存精确路径

`ScreenPanel` 新增 `hoverPathKey`/`hoverPath`，以宽高、上下圆角、样式为 key。几何不变时复用同一 `Path`，只在形状变化时重新构造；`Path.contains` 的精确语义不变。debug 诊断新增 `coarseExclusions`，Release 不带该类型。

### 3. 缓存窗口接收状态，停止可见性反复重新武装

`ScreenPanel` 缓存 `lastIgnoresMouseEvents`。普通鼠标事件通过缓存状态写入，只有目标变化才调用 setter；外部路径写入时通过 `ignoresMouseEventsDirty` 在下一次事件读取一次真实属性并纠正。

`updateVisibility()` 不再在每次可见性更新时强制把 `ignoresMouseEvents` 设为 `false`。面板默认点透，只有指针真正进入轮廓时 `trackMouse` 才把该面板切换为接收事件；离开时恢复点透。这样透明宿主不会因为一次可见性刷新重新接收整片 624×320 的鼠标流量。

## 三、验证

定向测试：

```
swift test --filter "IndependentPointerWindowStateTests|IndependentPointerDedupAcceptanceTests|NotchHitTestPrefilterTests|IndependentNotchPrefilterTests|MultiDisplayCoordinatorTests|IndependentInteractionTests"
```

结果：**37 项通过，0 失败**。新增/更新的断言覆盖：

- 远离面板的指针由粗筛排除，`pathConstructions == 0`；
- 同一几何的连续精确查询只构造一次路径；
- 外部事件重复时不再触碰窗口 setter；
- 外部直接写入后下一次事件只纠正一次；
- 面板初始点透，指针进入后才接收事件；
- 多屏激活/悬停/拖动/锁定相邻行为未回退。

未做 CPU/内存压力、鼠标抖动循环、批量闪窗或完整全量；真实鼠标 CPU 降幅、悬停延迟和手势体感仍需用户实测。

## 四、候选与替换

- 候选：`/private/tmp/valora-user-test-36/Valora.app`
- 版本/构建：`1.0.3 (36)`
- binary SHA-256：`8c505fb2c1ff2352ca1161f66c145c8a14412a41dd0f53d6524b2f13fc6cdde4`
- `codesign --verify --strict --deep`：通过；构建号由打包脚本自动分配。
- 已正常退出 build35（原 PID 99506），确认零实例后启动唯一 build36（PID 4665）；当前仅一个 Valora 实例，路径对应本候选。
- build35 保留在 `/private/tmp/valora-user-test-35/Valora.app` 以便需要时回退。

## 五、未验

- 真实鼠标抖动下的 CPU 是否明显下降，需同一实例、同一暂停/悬停条件下的用户实测；本轮没有用人工抖动或压力循环冒充降幅。
- 悬停进入/离开延迟、右键/点击在极短移动下的命中、物理双屏与锁屏真实交互未重新人工确认。
- 歌词实验构建仍存在；本轮没有改实验渲染器，也没有把实验代码变成普通 Release 内容。

## 六、build37：鼠标事件合并与窗口属性缓存

用户实测 build36 移动鼠标仍可到 15%–20%，说明仅裁剪命中几何不够。build37 在同一热路径继续做两项收窄：

1. **鼠标事件按约 120Hz 合并**：全局/本地监听回调只置一次待处理标记；实际 `NSEvent.mouseLocation` 读取和 `trackMouse` 每次刷新最多执行一次，移动停止后的最后一次位置仍会被处理。悬停逻辑、hover delay、离开/进入语义不变。
2. **窗口 frame/visible 热路径缓存**：`ScreenPanel` 维护 `surfaceFrame`/`surfaceVisible`，在创建、place、anchor、orderFront/orderOut 时同步；鼠标移动不再逐事件读取 `NSPanel.frame`/`isVisible`。隐藏时直接跳过 tracking 循环。

定向测试仍为 **37 项通过，0 失败**。真实 CPU 降幅仍需用户移动鼠标实测；本轮没有跑 CPU/内存压力、没有操作真实鼠标。

build37 候选：

- `/private/tmp/valora-user-test-37/Valora.app`
- `1.0.3 (37)`
- binary SHA-256：`3630a3ff8ff7521d9d9ae20ad119ed9552e7a9845e34d7da13878db7b506a3fa`
- strict/deep 签名校验通过
- build36 已正常退出，当前唯一 build37 实例 PID `6372`
- build36 保留在 `/private/tmp/valora-user-test-36/Valora.app`

## 七、build38：区域化 hover sensor，移除全屏鼠标监听

build37 仍被用户实测为鼠标移动可到 15%–20%。这说明全局 `NSEvent` 监听本身在普通桌面移动时仍会进入 Valora，继续优化命中函数无法满足“未到刘海区域不应升高”。

build38 改为区域事件源：

- 移除全屏 `NSEvent.addGlobalMonitorForEvents`；不再接收普通桌面鼠标移动。
- 每个刘海面板下方增加一个小尺寸透明 `NotchHoverSensorView` 子窗口（约 240–360 × 40pt，覆盖紧凑刘海及边缘余量），只在该区域接收 `mouseMoved/mouseEntered/mouseExited`。
- sensor 事件仍走现有 120Hz 合并与 `trackMouse`；进入刘海后主面板接受事件，`EdgeHostingView` 的 tracking area 负责主面板的鼠标退出。
- 主面板仍默认点透，只有指针实际进入轮廓才接受事件；透明 624×320 宿主不会因普通桌面移动接收事件。
- 传感器是面板子窗口，随面板移动/隐藏；锁屏/隐藏时父面板 orderOut，传感器随之不可见。点击穿透范围从整屏缩小到刘海附近的小传感器区域。

定向测试仍为 **37 项通过，0 失败**。该改动改变了事件来源，真实 hover 进入/离开、刘海右键/点击、菜单栏中心区域点击穿透和多屏 sensor 位置必须由用户实机确认；本轮没有用真实鼠标操作或压力采样。

build38 候选：

- `/private/tmp/valora-user-test-38/Valora.app`
- `1.0.3 (38)`
- binary SHA-256：`2efcca5f68df81de60f95f93d900be64e05d1bcf57a2e06912ae0a20991ce71e`
- strict/deep 签名校验通过
- build37 已正常退出，当前唯一 build38 实例 PID `8471`
- build37 保留在 `/private/tmp/valora-user-test-37/Valora.app`

## 八、build39：撤回遮挡点击的 sensor，保留非遮挡优化

用户明确否定了 build38 的区域 sensor：顶部小窗口仍可能挡住菜单栏/桌面点击，收益不值得。build39 撤回 sensor 与子窗口事件源，恢复全屏全局监听；保留不改变点击区域的优化：

- 120Hz 鼠标事件合并；
- 面板 frame/visible 热路径缓存；
- 屏幕空间 96pt 粗筛；
- SwiftUI `Path` 改为缓存 `CGPath`，命中改用 CoreGraphics `CGPath.contains(.winding)`，不再每次走 SwiftUI/RenderBox 的 `Path.contains`；
- 面板默认点透、只在指针进入轮廓后接收事件的语义保留。

因此 build39 **不新增任何会挡住点击的窗口**，也没有缩小可点击区域；代价是普通桌面移动仍会进入全局监听，CPU 是否下降取决于 CGPath/合并/缓存是否覆盖主要成本，必须实测。

定向测试 **37 项通过，0 失败**。

build39 候选：

- `/private/tmp/valora-user-test-39/Valora.app`
- `1.0.3 (39)`
- binary SHA-256：`dab8210d538a183941c7af9bed3610cd6d8ccefaa6ccb220ce4fb6bd851d9cda`
- strict/deep 签名校验通过
- build38 已正常退出，当前唯一 build39 实例 PID `10132`
- build38/37 保留在 `/private/tmp` 以便回退
