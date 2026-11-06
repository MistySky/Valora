# V0030-R5：共用监控/Codex菜单入口，并补齐缓存冷却

用户确认刚讨论的方案并明确“验收pi给pi派活”。先读AGENTS和independent-v0030-r4/decision.md；保留已接受剩余口径/后台缓存/400pt与下载日历，不开始Chrome-only V0031。

## 缓存限定修复
R4独立19项通过，但testIndependentCachedFailureStillHonorsClickCooldown失败，见日志：旧成功缓存后台失败仍ready，点击绕过lastFailureAt，requestCount2→3。保留有效断言修复，ready/stale不绕失败冷却，冷却内点击只看缓存，过期可重试，成功清错误；不清成功值和observedAt。检查在途点击合并当前有效请求，不每次点击再排无必要读取，pending仅真实代际需求使用。保留单真实在途/取消/后台timer/reset刷新，不重复真实账户probe。

## 用户新确认的合并展示
- 两个status item改成一个共享status item。双方开：CPU/MEM双行一组、5H/WEEK双行一组在菜单栏横向并排，保留字号对齐与适当组间距；整块点击同一面板，不分两处命中，不加页签/横滑。
- 展开400pt，上系统监控、下Codex剩余列表，必要分隔，超屏幕高度单一纵向滚动。复用Calmon MonitoringView成熟内容及Codex列表，不重做CPU卡片/应用列表/重置卡，不缩字体；可最小抽取已有content避免嵌套ScrollView，保持监控搜索/应用列表折叠/Esc等交互。
- 只监控开：入口CPU/MEM、面板仅监控；只AI开：入口5H/WEEK、面板仅Codex；双方关：共享入口消失、面板关闭、双方后台停止。某模块off只移除其section/请求，不留空标题分隔，不停止另一模块。
- 设置仍系统监控/AI用量两个独立页面总开关，不新增联合开关/不改偏好键。off启动不start所属provider，开启哪项只跑哪项；sleep/wake按各开关，无重复provider/任务。关闭共用面板不停止仍启用的正常功能。Codex沿官方剩余、启动即后台取、保留stale/错误缓存/重置卡直接列表，不因共用UI清缓存或每次点击新app-server。
- 共享入口右键仅禁用版本/设置/分隔/退出；日历和下载独立，软件V完整音乐菜单和通用图标显隐、刘海/音乐歌词设备不变。移除旧monitor/codex独立status item防重复，保持合理位置迁移，不改其他App设置。不全局重构拆包。

## 验证与交付
仅无界面功能测试/源码/必要构建签名：四开关状态的共享内容描述与路由、provider相互不启动/不停止、旧回调、缓存冷却、400pt和单滚动结构。严禁连续菜单栏点击、循环开关、批量截图、所有--verify-*或换名绕过禁测、内存CPU压力/驻留/无变化全量。单次人工体验留给用户，不自动操作当前软件。
候选/private/tmp/valora-v0030-r5-candidate，报告docs/reports/v0030-r5.md，正式交付停等Codex。禁覆盖dist/正在运行包或退出App、真实quota身份token聊天日程读取、媒体设备权限登录项写、浏览器配置插件cookie/helper/真实用户文件操作、Git提交推送/改归档模型历史。定时器关闭，Chrome-only V0031在本批独立接受后串行。
