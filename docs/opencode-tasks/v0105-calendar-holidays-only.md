# V0105 用户最新覆盖：日历只要节假日，不要个人日程

现有会话继续。用户明确“点击后会短暂出现正在获取日程是啥？？个人日程不需要，就节假日这个就行了”。这覆盖此前按“保留个人日程去重”理解的V0104目标，不再继续打补丁完善个人事件缓存。本批属于用户明确删功能，保留Calmon基本UI。

## 目标
保留日期/农历/节气/节假日/休班、原“今天/距今天”相对日期、休息/补班标记、日历导航/日期菜单栏，以及现有监控/Codex同卡。绿色节假日与休班每项一次，下面不再出现蓝色个人事件区、正在读取/获取日程、开启授权显示系统日程、个人日程空态。
删除整条个人日程读取与显示，不只是隐藏蓝色View/加载文字。不得额外扫描个人事件、读取用户真实日历/来源去诊断、删除系统事件或改订阅。上批报告“用户机器上恰好两个可信来源”未经真实读取证明，改为fixture复现的可行原因，保留原日志不变造。

## 实现边界
- 移除EventKitCalendarEventProvider对calendars:nil的一般日事件查询及其生产构造/订阅；CalmonCalendarModel的eventProvider/events/eventState/loadedEvents/个人任务与代次等专用链路无用后移除。
- CalendarSystemEventRow/systemEventsSection、个人事件fixture/仅供个人链路的协议模型等若无剩余真实引用一并清理。不要保留死生产模块只为了通过旧测试。debug审计/预览调用点同步适配，保持Release门控和debug编译，不恢复个人事件功能。
- 保留HolidayProvider对可信只读中国节假日来源的可见范围查询和去重，不把节假日读取也删掉；授权gate仍需总开关与真实fullAccess，不篡改为“无需授权”。日历入口/总开关/手形及正常授权路由沿既有语义，基础日历不依赖读取个人事件。
- 更新设置简洁说明与NSCalendarsFullAccessUsageDescription，从“你的日程/系统日程”改为实际节假日/休班用途；不新增说明卡片/设置/授权弹窗，不触发真实权限操作。
- V0104 source集合/元数据重过滤如仅供被删个人链路需评估移除，保留绿色节假日真正使用的稳定逻辑，不顺带重构provider。可保留已必要的同范围请求去重。
- 其它UI字体/宽400/网格368/两行摘要/卡片颜色/音乐锁屏耳机一律不改。“重置卡 N 张”和当前用户图标保留。

## 功能验证
仅fake/fixtures无窗口。验证没有个人事件provider构造或调用、无蓝色区/日程loading文案；授权后真实节假日路径仍有对应fake读（普通节日+休班并存各一次）；未授权/关闭/隐藏/stop无节假日读、迟到结果不回写；日期/月份导航和相对日期/农历节气/休班标记保留。
相关历史personal-event测试随功能删除按证据退役或改为节假日权限/生命周期有效断言，不盲目清空所有日历测试。新IndependentCalendarSelectionIsolationTests针对即将删除的personal events可退役，保留decision里原失败事实，不再修该缓存。列清删除测试与剩余覆盖数量，debug与Release都要正常编译，不全量/闪窗/性能。
更新现行AGENTS/REQUIREMENTS/README/CONTINUATION范围（历史归档不改），本轮用户实机音乐/锁屏已通过不重做。

## 候选
当前build14；新正式候选自动build15或实际下一号，新/private/tmp目录，签名/hash/Info/JSON一致。正常退出时明确定位当前运行PID/完整路径，避免LaunchServices按名称启动dist导致多实例；工具不支持就交Codex接续，禁pkill/强退。退出到0再唯一启动，核唯一PID路径。禁覆盖dist/运行包、安装/Git提交push。
报告docs/reports/v0105-calendar-holidays-only.md列真实删除链路/引用证据/测试和剩余边界，完成停等Codex独立验收，用户随后只重看日历，不进入性能专项。
