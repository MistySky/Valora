# V0102 独立验收接受（文档口径已纠正）

2026-11-05。本批文档/测试契约接受，产品源代码、Release构建和运行包未因本批改变，仍build13。

独立校验四份归档hash与报告相同。README/REQUIREMENTS/CONTINUATION旧件逐字节等于HEAD原文；AGENTS归档保留HEAD完整前缀，并有22行后续批次追加，全文527行。无法用当前改写后的文档反证当时未提交尾部，但归档内容/长度/hash与交付记录一致，未删除历史证据。

独立核对当前约定/源码，发现AGENTS“节假日/休班不需授权”不准确：AppDelegate注入HolidayProvider和CalendarModel的gate均要求enableCalendar+fullAccess。已仅文档改为基础日期/农历/节气不需授权，EventKit节假日/休班和系统日程都受gate；媒体adapter“只读”改为读取及用户主动控制，验收仍不擅自控制；锁屏选屏独立/形态跟随措辞也澄清。历史原件不改，产品功能不改。

Sidebar测试两处期望只补已确认Codex用量，保留其它断言。旧SettingsReductionTests类setUp会启动WindowCoordinator，不应称其方法为完全无窗口验证；独立新增IndependentSidebarContractTests只读静态catalog/13pt约定、不构造AppModel/coordinator，1项通过。日志/private/tmp/valora-independent-v0102-pure-sidebar.log（注意单数“1 test”，不是零用例）。旧方法也已定向运行，但不作为无窗口安全证据。后续全面回归须先筛查测试setUp/tearDown，不能仅看方法体。

git diff --check通过。本批无新Release，无构建号增加/运行包替换，无Git提交。代码层面尚存不值得为减行数重构的AppMemoryReader类型与部分默认关闭诊断/fixture，分类已记录，不能宣称所有历史代码全删除。它们并非本轮阻断功能缺陷。

当前已确认收尾批次自动范围完成，可以进入完整功能/全局联动的回归阶段；先审核测试副作用、全量覆盖安全自动范围，真实系统/人声/多屏/耳机由用户协助一次功能验证。禁止把有窗口/真实系统写或读取用户账号的测试混入“纯单测”；资源/动画压力专项留回归缺陷解决后。
