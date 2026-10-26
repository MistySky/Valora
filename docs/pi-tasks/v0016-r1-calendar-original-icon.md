# V0016-R1 恢复原Alcove日历专用图标

用户实际查看后明确指出“日历的图标没使用alcove的”。Codex独立215测试+2新增授权回归、构建签名、设备32、设置几何通过子集，但UI图标不通过。见docs/verification/independent-v0016/decision.md。

根因明确：只读归档/Users/wangqing/code/alcove-revival-archive/Sources/AlcoveRevival/SettingsControls.swift的SettingsIcon.body在page==.calendar时有专用VStack（上色页眉size*.27，纸面背景.controlBackgroundColor，日期Text("12")字体size*.48 medium），并保留统一frame/clip/overlay。Valora迁入首期只有通用SFsymbol分支，新加Calendar页面却遗漏恢复这个原有分支，导致粉底白线calendar像计算器。不要称已按原版图标完成。

直接迁入成熟来源专用分支，不重新设计/找emoji/下载新图标/使用imagegen；侧栏和页标题都应走SettingsIcon，颜色/比例/圆角/活动/非活动/muted行为按原实现。对照原版/Users/wangqing/code/alcove-revival-archive/reference-ui/Calendar.png（侧栏粉色页眉浅底日期，标题非活动muted），来源日期12为取证样本，不新增日期动态刷新需求。核对当前复刻渲染与截图差异，报告区分源码底稿与原版图证。

设置卡内calendar.badge.clock当前和原版一致，保留不要误改为日期块。只修侧栏/页标题专用分支；其他页面图标/卡片/文案/授权交互保持。无其他功能/架构改动，已接受日历授权回归都保留。

构建签名、隔离设置日历页浅深色/活动非活动的图证、必要设置回归。报告docs/reports/v0016-r1.md，交付停止等Codex独立验收。本批低影响视觉修复不要新增镜像实现测试；不真实授权/日程读写/系统设置操作，不Git提交推送/安装发布/改归档或品牌图标，不恢复定时器或进入Calmon展示。
