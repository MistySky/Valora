# 鼠标接收状态去重：独立验收

2026-11-09。GLM-5.3-Flash 在 `WindowCoordinator.trackMouse(at:)` 的普通/锁屏分支加入 `setIgnoresMouseEvents`，先读 NSPanel 实际值，只有目标值不同才调用 setter。其余改变 panel 属性的路径未被影子缓存覆盖；鼠标事件接收、命中计算、进入/退出及悬停时序没有改动。

Codex 新增 `IndependentPointerDedupAcceptanceTests`，使用不显示的单个 NSPanel 验证原生 setter 的实际调用：同值不写、变化即时写、外部先改后下一次调用正确纠偏。独立运行 `swift test --filter 'IndependentPointerDedupAcceptanceTests|IndependentNotchPrefilterTests|NotchHitTestPrefilterTests'`：7 项通过、0 失败，日志 `/private/tmp/valora-pointer-dedup-independent.log`。OC 报告的双屏/交互/锁屏 90 项及普通/实验 Release 构建结果另见 `desktop-pointer-window-state-dedup.md`；本次未独立重复其整组窗口测试或 Release 构建。

结论：接受本批逻辑变更。真实用户鼠标悬停、多屏和优化后 CPU 未验。先前暂停播放下用户移动鼠标均值 14.4%、静止 0.4% 是旧运行版结果；本批只消除同值状态赋值，系统全局事件接收与其他成本仍在，不承诺降幅。用户现有运行版未替换，当前结果不能代表优化后 CPU。
