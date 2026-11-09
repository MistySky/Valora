# 鼠标命中预筛选独立验收

2026-11-09。用户实测未悬停时抖动鼠标，Valora 多个采样点约 17%–22%；对应短调用栈出现全局鼠标移动 → trackMouse → NotchShape Path.contains。不能以栈计数推算 CPU 百分比或证明它是唯一原因。

代码审查：快速排除在原有屏幕坐标和 hoverScale 变换后进行。pill 使用自身矩形；notch 覆盖主体与两侧各 2t 的外伸肩部，纵向覆盖 max(height,2t)，t 按原形状半径夹取规则计算。严格在外才返回 false，边界及范围内仍走原 Path.contains；鼠标事件频率、进入/退出状态、悬停及拖动调度未改。

首次独立测试发现 ±infinity 和 NaN 与越界坐标组合未按指定走原路径；已交 OC R1 修复为双坐标有限性检查。复跑 `swift test --filter 'IndependentNotchPrefilterTests|NotchHitTestPrefilterTests'`：6 通过、0 失败，日志 `/private/tmp/valora-pointer-r1-independent.log`。OC 报告相邻 88 项通过，普通 Release 无诊断符号。

验收结论：接受本批代码的定向逻辑与保守范围设计；尚未验证用户真实鼠标手感、实际多屏及优化后 CPU。当前用户运行版未替换，用户实测前不能声称资源占用已下降；需用户授权后构建并切换单实例作同条件对照。歌词动画实验是另一个未完成门槛，不把两者混为已全部验收。
