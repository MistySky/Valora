# 桌面鼠标移动 CPU：保守范围快速排除

用户确认 CPU 偶尔升高时没有悬停在刘海上，但鼠标在移动。2026-11-09 现场抖动鼠标 30 秒，Valora 采样多次约 17%–22%；同时采集的 `/private/tmp/valora-mouse-move-20261109.txt` 再次出现全局鼠标事件 → `WindowCoordinator.trackMouse` → `containsMouse` → SwiftUI `Path.contains` / RenderBox 复杂路径计算。静止对照阶段不能确认用户是否完全静止，不能声称已证明唯一原因。按用户要求优先处理，不影响交互。

## Codex 指定最小方案

1. 仅优化 `WindowCoordinator.containsMouse` 的精确形状判断前置条件。完成已有 `NotchHoverMetrics.localPoint` 变换后，先用完全覆盖 `NotchShape.path(in:)` 的保守范围作快速排除；**范围内与边界点一律保留原始 `NotchShape.path(...).contains(local)` 精确逻辑**。不降频、不合并事件、不改变 hover delay/展开/拖动/激活逻辑。
2. 形状来源 `NotchView.swift`：`.pill` 无外伸，可用自身 rect 的保守包围；`.notch` 的上肩通过 left/right rect 各外伸 `2*t`，其中 `b = max(0,min(bottomRadius,min(width/2,height)))`、`t = max(0,min(topRadius,min(24,height-b)))`；左右外包至少 `[-2*t, width+2*t]`，纵向须覆盖主体 `[0,height]` 与肩部 `[0,2*t]`。只以严格 `<`/`>` 判定确定在范围外，边界交给原 path 判断。若尺寸/坐标/半径/scale 非有限、非正或几何异常，直接走原逻辑，不能引入错误排除。计算不要调用 path.boundingRect，否则无法避开昂贵路径构造。
3. 两个 `containsMouse` 重载保持一致；多屏每个 record 的坐标变换、`topInset` 和 hoverScale 必须照旧。鼠标从内部移出时仍执行既有 `trackMouse` 的状态清理；快速排除不能跳过上层状态逻辑。屏幕负坐标、物理/模拟、pill、展开、悬停缩放、通知和连接状态的形状全部保持相同。
4. 添加有意义的隔离回归：以原始 `NotchShape.path(...).contains` 为独立参考，对代表性内部/外部/精确边界/上肩附近的点逐项比较，覆盖物理/模拟、pill、长宽和缩放变化、负坐标多屏以及异常输入回退。增加测试 seam/计数证明远离时确实跳过 path 构造、靠近时执行原判断；不能以计数代替行为一致性。禁止大量循环/压力/批量闪窗。
5. 跑多屏、悬停、交互、音乐和锁屏相邻定向逻辑测试，保留已有断言。报告 `docs/reports/desktop-pointer-hit-test-prefilter.md` 写明精确范围推导、测试、未验项；不要把用户抖动期间的原始数据说成已验证优化后的 CPU。

保留当前歌词动画实验工作；这批不要改歌词、播放、音频或锁屏实现。不得启动/替换当前 App、控制鼠标或音乐、打包提交推送。完成后停止，等 Codex 独立验收，再由用户对照体验和 CPU。
