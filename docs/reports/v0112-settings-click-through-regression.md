# V0112 设置顶部点击失效 / 刘海悬停不退出（最小修复）

## 范围

只修 `WindowCoordinator` 的 hover 输入所有权和退出清理；未改设置导航、动画、刘海外轮廓、歌词、锁屏、音量、媒体控制、用户偏好或版本。未构建交付包、未替换/quit 用户实例、未提交 Git。

## 根因

真实窗口关系（Codex 证据）：

- 刘海 panel 是 624×320 透明 canvas，初始 `ignoresMouseEvents=true`；
- 小 sensor 负责进入/退出；
- 指针进入后 `trackMouse` 把 panel 改成可接收事件，`record.pointerInside=true`；
- 此时输入所有者变成覆盖 624×320 的 panel，sensor 位于其下，不能再稳定收到自己的退出事件；
- 退出恢复只依赖 `EdgeHostingView` 的 compact tracking area/`mouseExited`。一旦退出事件未到（覆盖/重排/边界交接），`pointerInside` 和 `ignoresMouseEvents=false` 会保留，整块透明 canvas 继续挡住设置顶部的点击，并让 hover 看起来一直存在。

关键位置：

- `EdgeHostingView.updateTrackingAreas` / `mouseExited`（`WindowCoordinator.swift:58-86`）
- sensor（`:88-104`）
- `trackMouse` 的 `record.setIgnoresMouseEvents(!inside)` / `pointerInside`（`:1011-1046`）
- `updateVisibility` 的 panel/sensor ordering（`:714-729`）

这不是设置页导航本身错误；AXPress 能切换设置页也说明导航活着。

## 最小修复

1. 仅在有 panel `pointerInside` 时安装 **hover-only local + global** `mouseMoved`/`leftMouseDragged` 兜底：
   - local monitor 回调必须返回原 `NSEvent`，不吞事件；
   - global monitor 只用于应用失焦/跨窗口移动；
   - 两者都复用已有 `queuePointerUpdate()` 120Hz coalescing，不恢复永久全桌面鼠标流。
2. `syncHoverExitMonitors()` 在 pointerInside 状态变化、`updateVisibility` 和 test seam 中同步：
   - 进入时有 fallback；
   - 全部退出后立即移除 monitor。
3. `clearPointerOwnership()` 在以下路径统一清理：
   - 刘海不可见/隐藏；
   - 锁屏；
   - trackMouse 在 surface 不可见时被调用。
   可见性更新还会同步兜底监听生命周期；不宣称每个重排/交互结束入口都直接调用该清理函数。
   清理所有 panel 的 `pointerInside=false`、`ignoresMouseEvents=true`、pending hover，并移除 monitors。
4. `pointerChanged` 测试入口也同步实际 panel 的 click-through 状态，避免测试只改模型。
5. 保留已有 `setIgnoresMouseEvents` 去重和 `queuePointerUpdate`，未引入常驻 timer、未改 tracking area 的 y/flipped 方向。

## 测试

新增：

`MultiDisplayCoordinatorTests.testHoverOwnershipFallbackInstallsOnlyWhileInsideAndRestoresClickThrough`

验证：

- hover 进入后 local/global fallback 安装，panel 暂时接收事件；
- 鼠标到桌面区域后 fallback 移除，panel 恢复 click-through；
- hidden 后清理 monitor；
- 重新显示/再次进入仍可正常；
- 退出后顶部 canvas 不再接收事件。

定向结果：

- `MultiDisplayCoordinatorTests` 18 项通过（含新增）；
- 关联 `IndependentPointerWindowStateTests`、`IndependentInteractionTests`、`DesktopIdlePublishTests`、`NotchHoverTests` 的合并定向共 26 项通过；
- debug `swift build` 成功；未做 Release/正式包。

## 未验项

- 未在本机 build62 上用真实鼠标点击设置顶部；只做代码级 fake/window state 回归。
- 未启动/关闭用户真实媒体、锁屏、设置或第二实例。
- 未验证 local/global monitor 在极端快速移动、应用失焦、全屏/Mission Control 和多物理屏上的真实事件投递；这些需要 Codex/用户真实 A/B。
- 新增回归没有直接模拟 `NSEvent` 的 local monitor 用户点击路径，只验证安装/移除、click-through 和 pointer ownership 生命周期。
- 未证明该问题只由这一条造成；本次修复针对窗口输入所有权的最小可复现链路，不改设置页或动画。

## 交付状态

源码最小修复和定向测试已完成；**未构建交付包、未替换、未提交**。等待 Codex 独立验收后正式构建/替换。
