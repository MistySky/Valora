# V0016 独立验收：授权子集通过，图标限定返修

独立完整215测试（101+114）通过；新增IndependentCalendarPermissionTests两项通过，验证实际开关路由取消→重开→旧callback拒绝，以及denied系统设置返回仅完成有效intent一次。独立构建/private/tmp/valora-independent-v0016/Valora.app及codesign深度严格验证通过。设置视图生成/窗口几何通过，设备32项通过（含日历用途声明）。原日志/private/tmp/valora-independent-v0016-{test,extra,build,settings,connectivity}.log。

代码仅增加公开EventKit授权，无事件读取/写入调用。dist binary SHA256已独立核对5fab5cd372b564501f58b0e05efa7a4521cc1eda60fbf9807a6eff62be1c05c1，签名通过。实际Valora已运行并查看日历设置页AX/截图，单卡单开关、hand为Image且Toggle可操作；未点击真实授权，不读取个人日程。

用户指出日历图标不符，重新对照来源确认：归档SettingsControls.swift的SettingsIcon有page==.calendar专用分支（上色页眉、浅色纸面、日期数字），当前Valora仅通用粉底白SF calendar，迁入遗漏。原版reference-ui/Calendar.png侧栏和标题均为纸质日历日期图标，开关行calendar.badge.clock则已一致。不能因授权测试通过宣布UI整体接受。

限V0016-R1恢复原专用日历图标分支，不自行重画，不改已接受授权交互/其他图标布局；需明暗/活动与非活动态、标题与侧栏对照。真实EventKit弹窗及系统设置返回仍待实机，本批无月历/日程展示，未改真实授权或系统设置。

用户实机反馈追加：正式dist开关无法弹授权已由Codex复现，TCC日志明确缺少Hardened Runtime日历entitlement。不是用户拒绝。见runtime-calendar-entitlement-failure.md，整体授权入口亦不通过，V0016-R2修签名资源声明；原fake子集通过不能冒称真实授权通过。
