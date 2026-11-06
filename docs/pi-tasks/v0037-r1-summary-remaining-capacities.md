# V0037-R1 基础监控内容纠正

用户2026-10-30最新明确：当前系统和芯片不要显示，需要显示剩余内存和剩余磁盘。核对现有CalendarMonitorSharedView.MonitorSummaryCard发现parts仍是chip/osVersion/memory.total/disk.total/uptime，缺剩余。本轮只修内容，保留当前日历/共享popover布局和简洁风格，不借机增加组件。

- 完整移除卡片芯片和系统版本展示。
- 显示内存总量与剩余（memory.total / unusedCapacity）、磁盘总量与剩余（disk.total / available）、已运行时间。总量保留，不能用剩余替代总量而丢数据。
- 标签明确归属，不能一排无标签GB导致无法辨别内存和磁盘。布局按现有简洁卡片适配400pt，必要分成内存/磁盘/运行时间紧凑三行，避免用极小字体挤满；日历保持。
- 使用已有单位格式，缺失--，真实0有效，不硬编码32/494.4等示例。
- 不恢复复杂监控、进程采集/搜索/环形图，开关停止后台及两入口共享popover不变，不改音乐/锁屏/设备。

仅相关无UI格式/数据映射定向回归和必要编译签名，不全量、不创建真实窗口/菜单/截图循环/压力，不读真实日程或改权限/偏好，不退出启动替换用户App，不覆盖dist、不Git提交推送。候选独立路径/private/tmp/valora-v0037-r1-summary-candidate，报告docs/reports/v0037-r1-summary-remaining-capacities.md。不要重跑已通过无关模块。完成等待Codex验收。
