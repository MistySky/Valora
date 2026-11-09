# 桌面鼠标移动 CPU：保守范围快速排除

执行：原 OpenCode 会话、原模型、分支 `codex/idle-cpu-optimization`。按 `docs/opencode-tasks/desktop-pointer-hit-test-prefilter.md` 处理。未启动/替换当前 App、未控制鼠标或音乐、未打包提交；歌词实验工作保持原样。

## 一、改动范围

只改 `Sources/Valora/WindowCoordinator.swift` 的命中外层：在既有 `NotchHoverMetrics.localPoint` 变换之后，先用完全覆盖 `NotchShape.path(in:)` 的保守范围做快速排除；范围内、边界点仍走原始 `NotchShape(...).path(...).contains(local)`。未改 `trackMouse`、hover delay、展开/收起、拖动、激活、`topInset`、`hoverScale`、多屏坐标变换或任何 UI。

两个 `containsMouse` 重载共用同一预判：

- `containsMouse(point:panelFrame:size:contour:scale:)`：保持原有 localPoint 变换；`scale` 非有限/非正时跳过预判，直接走原精确路径。
- `containsMouse(localPoint:size:contour:)`：先预判，再走原精确路径。

调试计数 `NotchHitTestDiagnostics` 只在 `VALORA_DEVELOPMENT`（debug）编译并递增，用来证明“远离时未构造 path、靠近/边界时构造了 path”；Release 无该类型、无计数开销。

## 二、保守范围推导（不调用 `path.boundingRect`）

`NotchShape.path(in: r)` 使用 `r = CGRect(origin: .zero, size: size)`：

- **`.pill`**：`RoundedRectangle(cornerRadius: min(bottomRadius, r.height/2), style: .continuous)`，整条路径必在自身 rect 内。范围为 `[0,width] × [0,height]`。
- **`.notch`**：
  - 主体 `UnevenRoundedRectangle` 在 `[0,width] × [0,height]` 内；
  - 上肩左右矩形各为 `x ∈ [-2t, 0]` / `[width, width+2t]`，`y ∈ [0, 2t]`，并在其中减去圆角。因此整体并集必在：
    - 横向 `[-2t, width+2t]`
    - 纵向 `[0, max(height, 2t)]`
  - `b = max(0, min(bottomRadius, min(width/2, height)))`、`t = max(0, min(topRadius, min(24, height-b)))`，与 `NotchShape` 自身夹取完全一致。

只以严格 `<` / `>` 判定“确定在范围外”；等于范围边界的点仍执行原 path。尺寸/半径非有限、宽高非正或超出合理上限（`10^6`）、半径为负时，`conservativeHoverBounds` 返回 `nil`，直接走原逻辑；点非有限时严格比较不成立，也会走原逻辑。全程未构造 `NotchShape`/`Path`，未调用 `path.boundingRect`。

## 三、验证

### 1. 行为一致（以原始 path 为独立参考）

新增 `Tests/ValoraTests/NotchHitTestPrefilterTests.swift`：每个点同时调用新的 `containsMouse` 和原始 `NotchShape(...).path(...).contains(...)`，逐项要求相等。

- 10 组几何：物理刘海 idle/active/低高度/expanded、模拟刘海 active/窄/高、pill idle/加高/expanded；每组 28 个代表点（内部、四角、上下左右、上肩内部、肩部外沿、范围边界、刚好越界、远处），共 **280 次**对照。
- 点重载：负坐标面板 `x=-1920`、`topInset`（pill 2.5 / notch 0）、`scale` 1.0 与 1.075/1.15，内部/下方/远处/屏幕边缘共 6 点 × 2 面板 × 2 缩放。
- 异常输入：零尺寸、`scale` 为 0/负/NaN、非有限点，均与原逻辑结果一致并走精确路径。
- 每组都断言至少一次“走 path”和至少一次“被预判排除”，证明用例不是只覆盖单侧。

### 2. 快速排除确实跳过 path 构造

调试计数验证：

- 远点：`prefilterExclusions = 1`、`pathConstructions = 0`；
- 中心/精确边界（`x=-2t`、`x=width+2t`、`y=max(height,2t)`）：`pathConstructions` 增加，说明边界仍走原判断；
- 刚越界 0.01pt：只增加排除计数；
- 点重载的远处点同样 0 次 path 构造；
- 零尺寸/异常 scale：path 构造计数 +1，排除计数不变（回退生效）。

### 3. 相邻回归

| 项 | 结果 |
|---|---|
| 新增 `NotchHitTestPrefilterTests` | **5/5 通过** |
| 多屏/交互/音乐/锁屏相邻组合（`MultiDisplayCoordinatorTests`、`IndependentInteractionTests`、`MusicDisplayPolicyTests`、`LockMusicCoordinatorTests`、`LockActivationOwnerTests`、`IndependentLockActivationLifetimeTests`、`MusicSourceActivationTests`、`FeatureSwitchTests`、`NotchDiagnosticPolicyTests`） | **执行 88，通过 88，失败 0** |
| 普通 debug 构建 | 成功 |
| 普通 Release 构建 | 成功；`NotchHitTestDiagnostics` 符号 **0** |

已有断言未删除、未放宽；没有压力测试、批量闪窗或真实鼠标/音乐操作。

## 四、未验 / 风险

- **优化后的真实 CPU 未测**：现场 17%–22% 是改动前的用户抖动数据；本轮没有真实移动鼠标或重新采样 CPU，不能据此宣称 CPU 已下降。
- 真实悬停手感、真实物理/模拟刘海、1x 与多显示器现场未重新人工确认；仅验证几何结果一致与相邻逻辑回归。
- 视频/锁屏/音乐播放路径未改；其相邻测试通过不代表真实设备组合已覆盖。
- 保守范围只排除严格在外的点；边缘附近仍有 path 构造，符合“近边缘保留精确路径”的要求。

## 五、回退

改动集中在 `WindowCoordinator.containsMouse` 及一个私有范围函数；回退即恢复为直接调用 `NotchShape(...).path(...).contains(...)`，删除 `NotchHitTestDiagnostics` 与新增测试即可。没有数据模型、设置项或 UI 依赖。

## 六、边界

未安装、未启动/替换 App、未操作鼠标/媒体、未打包提交；未改歌词、播放、音频、锁屏、设备、菜单栏或窗口扫描；未改事件频率、hover delay、展开/拖动/激活逻辑。
