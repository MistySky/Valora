# 修正采样v2准备与启动（2026-10-30）

Codex直接实现，不改动画、Space实现、用户设置。诊断仍默认关闭，本候选由LSEnvironment单独启用。
- 新CapturePolicy按phase+kind分桶：每阶段shape4/window6/space4/event2，shape最小间隔.12s/window.08s，去重按lane而非单全局key。总硬上限120不扩无界。已观察真实lock后的hidden用returned-to-desktop独立预算，避免启动hidden用掉最终归位记录。真实receiveLocked入口记录lock/unlock edge，独立event桶。
- shape增加phase变化回调，Window记录增加仅自己window ID的CGWindowList bounds，不存其他字段/标题/截图/其他App。命名Quartz bounds与AppKit分开，不能假设它总反映最终compositor transform。读取失败unknown。
- 25定向fake通过（23锁coordinator+2新采样），最后小改后2采样再复验通过。新测试重放用户已保存120条几何日志、确认frameburst后window/space/unlock/returned都可记录；另验证分lane限流去重。无UI/压力/性能测试。
- Release及strict/deep签名通过；候选/private/tmp/valora-lock-capture-v2-candidate/Valora.app，binary01ec79791440c158b76006841d1a9d73d1f8469a481aae109462095ee8641693。
- 用户同意协助测试后，CUA退出此前logging-candidate并启动v2；AX刘海界面可见，未点真实媒体控制。
- 已实际核实/private/tmp/valora-lock-capture-v2.jsonl产生11条初始记录，含shape/window/space。实体hasPhysicalNotch=true，AppKit顶部1117=screen.maxY，Quartz当前windowbounds X552/Y0/W624/H320。首条系统bounds暂unknown，后两条成功有值；不把首条未呈现时未知当作失败或伪造。
尚未真实锁屏，不称根因已确定；请用户保持模拟off、仅真实lock/unlock一次，之后读日志。无新权限/偏好修改、无dist覆盖/Git/定时器。
