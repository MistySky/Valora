# V0016：Alcove日历设置页与系统日历授权

用户最新授权：“先做日历？设置里面的日历的先拿过来，加上授权就行？”本批只设置页与真实授权状态链路；日历展示后续沿用Calmon，不迁入复刻刘海日历。用户确认一体菜单栏监控→Codex→日历、点击整体展开同一面板，但本批不实现菜单栏/日期月历/监控/Codex，不新增快捷键入口。

先读AGENTS、docs/CONTINUATION-PLAN.md，保持V0015-R4及联动已接受行为。Codex当前Git checkpoint bbb17cd已上传，分支codex/lyrics-word-sync，标签checkpoint-2026-10-24-before-menubar；pi仍禁止Git提交推送或重置，不改来源归档。

## UI来源与最小范围

只读来源/Users/wangqing/code/alcove-revival-archive/Sources/AlcoveRevival/SettingsCatalog.swift日历symbol=calendar、配色与正在播放同粉色；SettingsView.swift约206/339行permissionPage("Calendar", key:"enableCalendar", symbol:"calendar.badge.clock")仅一张卡一行开关、目前blocked占位。迁入现有Valora设置风格，侧栏日历入口放正在播放后，原布局字号卡片/控件图标不自创。不要复制blocked占位/禁用开关。

本页仅一个系统日历授权/日程访问开关，首次默认关闭，不凭已有系统授权自动打开。表达为授权后允许后续显示系统日程，基本月份/日期本身不依赖授权；本批无日历展示，不误称已实现日程读取/展示。必要时用现有说明方式说明用途，不增第二个开关/权限中心。字段语义与未来菜单栏日历模块总开关区分，避免将授权偏好与基础月历显示混为一谈。

## 授权

使用macOS27公开EventKit：EKEventStore.authorizationStatus(for:.event)、requestFullAccessToEvents；读取日程需要.fullAccess，writeOnly不能当可读。保留真实unknown/denied/restricted/notDetermined/fullAccess差异，不套用错误二值状态。声明NSCalendarsFullAccessUsageDescription（如“用于在日历中显示你的日程”）；核对现有签名/沙盒配置所需entitlement，不无故开启沙盒或额外权限。业务范围只读，不调用保存/删除/修改事件，不接提醒事项/联系人权限。

Apple来源：
- https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoevents(completion:)
- https://developer.apple.com/documentation/eventkit/ekeventstore/authorizationstatus(for:)
- https://developer.apple.com/documentation/eventkit/accessing-calendar-using-eventkit-and-eventkitui

沿用已修AppPermissions/PermissionToggleRouting最小扩展与用户明确交互：hand.raised.slash.fill非点击标志，开关始终可操作；仅点开启才请求授权，成功该次意图完成、手形消失；拒绝/取消/失败off。已拒绝可点开关引导系统对应设置，返回刷新真实状态，仅仍有效开启意图才能完成。连续点击不重复请求，pending明确关闭立即off；旧回调不能完成后一次意图。开关关闭不撤销系统授权，不打开系统设置撤销权限，不在启动/切页/QA中请求权限，也不自动查询个人事件。

Swift6隔离明确，EventKit对象不跨actor乱传；只作必要权限适配，不重构其他权限/成熟底座。避免V0015旧bug：非Published pending导致不刷新、异步返回前按旧状态清pending、旧回调无generation。已有设备/系统音频/登录项权限交互不可回退。

## 验证交付

使用注入EventKit授权provider/设置spy，测试实际开关Binding与pending可观察性：未决定点开一次、授予后开启、拒绝/取消off、重复点击不重复、pending关闭与迟到旧回调、拒绝到系统设置再返回、外部已授权但无开启意图不自启、writeOnly不可当可读、撤权回到不可用且不读数据。QA绝不请求/接受真实权限、不读个人日程、不修改系统设置或偏好。运行完整测试/构建签名，隔离设置页明暗及权限/pending/on/off视图，必要设备音乐歌词回归。记录默认值为本项目策略，不冒称原版首次默认。

报告docs/reports/v0016.md，证据docs/verification/v0016/，列出源码来源、最小改动、真实授权弹窗待实机。正式交付后停止等Codex独立验收，不恢复定时器，不继续下一模块。

禁止真实播放切歌seek音量、设备连接、真实权限/登录项/系统设置写、真实日历事件访问或写入、安装发布、Git提交推送、修改来源归档/品牌图标。
