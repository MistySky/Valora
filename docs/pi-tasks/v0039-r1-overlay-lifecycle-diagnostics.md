# V0039-R1 独立验收限定返修

先读docs/verification/independent-v0039/decision.md、targeted-tests.log、budget-regression.log。用户要的真实锁解连续体验优先，当前候选不能换给用户。保留原有效overlay/动画/预览/失败fallback，不改其他模块。

必须修：
1. ensureOverlay失败不随普通media refresh重复make/migrate/close；为同锁定周期/显示screen epoch记录失败/尝试，明确换屏/重锁/wake可有限重试，stop清空；不能永久锁死后续重锁，也不要计时无限重试。保留新增testIndependentOverlayFailureDoesNotRecreateOnOrdinaryRefresh断言使其通过。
2. 原生迁移成功登记自己overlay window所有权（否则detach因_windows无记录跳过），处理部分迁移/query失败的清理，检查自己window身份。可保留失败close后清理但需登记/清理可核验，别套R8未知就关全UI。至少用fake native API callbacks或等效生产注入验证成功detach、partialfailure、unknown、缺符号和普通primary仍可用；不要只改fake返回使测试绿。
3. 诊断重新分配overlay加入后的120硬额度，保留新增testIndependentOverlayTrafficStillLeavesFinalHandoffRecords，确保完整模拟/锁/解/归位在有限事件重放中保留关键记录。overlay在unlock/restoring/屏幕变化等真实事件采样own-window Quartz/host frame/可见状态/Space role，不只是ready/release；主窗口已隐藏时它才是关键。事件驱动+限流不加常驻timer；缺查询unknown不伪造，释放前实际状态别硬写false。
4. notch overlay专用hosting配置与成熟普通notch对齐：screen.frame.maxY锚定、明确host.frame/sizing/安全区策略，不能直接generic music card hosting潜在引入safeArea位移；复用视图/几何不重做UI。overlay独立窗口是否已脱离普通desktop需source/diagnostic证据，不只boolready。

另检查并保留：open glyph保持同宽→neutral收起actualcompletion→音乐withAnimation的原顺序；primary/overlayneutral交棒互斥、真实锁事实/呈现阶段、快速重锁/stop/wake/换屏取消；不为了流畅删除动作或加猜测delay。新role日志与native内存生命周期不阻塞主线程不断重复。

只定向无UI fake/native隔离与必要构建签名；禁全量/--verify/真实NSPanel或Space测试/锁通知/真实媒体设备权限/日程/自动点击截图循环/性能压力。候选新路径/private/tmp/valora-v0039-r1-isolated-lock-candidate，日志/private/tmp/valora-v0039-r1-lock-handoff.jsonl由LSEnvironment显式配置后签名；不得覆盖/退出/启动当前用户capture-v2或旧候选/dist、归档只读、不Git或定时器。报告docs/reports/v0039-r1-overlay-lifecycle-diagnostics.md，交付后停止待Codex，不扩新功能。
