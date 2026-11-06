# V0104 独立核查与用户范围覆盖

2026-11-06。独立日历相关37项通过；两个可信来源过滤及同名个人事件保留的自动子集成立。build14 Info/JSON一致，strict/deep签名通过，binarycbc2d66fe17c53a55b1073f3f710b60748f7afc427cbdebb477074d438e0dc97匹配，ps唯一PID63480对应/private/tmp/valora-v0104-calendar-holiday-dedup-candidate/Valora.app。日志/private/tmp/valora-independent-v0104-calendar.log。

报告“用户机器上恰好两个可信来源”不是已验证事实：本轮没有读取真实日历来源，只能说fixture复现多来源导致相同现象；应纠正口径，不宣称实际来源根因已证。替换时曾按名字误启动dist导致短暂双实例，最终独立确认单实例；未来应明确PID/完整路径定位当前实例，避免按名称解析启动另一份。

独立另测跨日旧事件缓存发现1失败（IndependentCalendarSelectionIsolationTests，日志/private/tmp/valora-independent-v0104-date-isolation.log）：选新日期加载中仍有前一天personal events。这一新增测试针对即将被用户明确删除的个人日程链路，转为删除该功能的回归依据，不继续修补个人日程缓存。

用户最新明确：不需要个人日程，只要节假日；“正在获取/读取日程”提示也不需要。这覆盖此前Codex按保留个人事件理解的V0104目标。因此不把V0104保留个人事件方案作为最终产品需求接受，进入V0105删除整条个人事件查询/显示链路，保留真正节假日读取与授权及原UI。测试失败记录不删；废弃功能专用测试在移除模块时可按引用证据删除/替换，不能维持无用生产类型只为过旧测试。
