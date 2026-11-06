# 日历显示限定修复：恢复Calmon已存在节日/休班/去重链路

用户明确提供原版Calmon与Valora同2026年10月日历截图要求检查显示差异。这是已迁入日历的缺失修复，不新设计。当前先完成feature-switches-and-app-icon在途任务，再串行本补充；定时器保持关闭，不重做V0030主体/引擎或展开浏览器。

已独立静态确认：Valora CalmonCalendarModel.showChineseHolidays=false；CalmonHolidayProvider.systemFestivals/detailFestivals始终[]、marker恒nil；CalendarEvents使用calendars:nil全来源原样映射，未复用Calmon选择节假日源与标题去重/安排解析。用户截图Valora缺国庆/重阳、休班角标与相应点标，详情同名国庆/国庆(休)重复、无休息标签。重复根因具体是否多订阅/映射以代码和注入证据判断，不读用户真实日历验证。

参考只读/private/tmp/calmon-v0027/CalMon/Calendar/{HolidayProvider,CalendarModel}.swift与其视图，固定72235116e1420fa081e8f694991a32809f81498d。恢复已有来源筛选/范围查询/normal festival与arrangement映射/日格副标题/marker/点/详情去重和休息补班标签，现有Calmon布局材质字号不动。不能只设showChineseHolidays=true却留下空provider，也不能硬编码2026国庆或从周末猜休班。保留来源许可。

授权仍复用Alcove/Valora已有流程，不让新provider私自请求权限，不系统写。功能开关off/无fullAccess不建立真实读取；开且授权时只读取所需可见网格范围及选中日。保留旧已接受stop/取消/跨月today/撤权/旧callback/无并发叠读边界。选用明确节假日源，避免把全部订阅重复倒进详情；节日已有详情与普通事件合并时防同一记录重复，不能仅凭同名删不同个人事件。源不存在未授权时保持基础公历农历，不伪造节日。公开来源元信息与必要事件字段可由注入fixtures验证，禁止现场读取个人日历或改授权。

定向测试：用户截图10月1国庆+休、10月10补班、10月18重阳等通过fixture推导而非内置猜测；同名节日重复/normal+arrangement正确并存各一次及标签；非重复同名个人事件保留；跨月范围/撤授权/总开关off停止读取及旧响应丢弃。实际native视图用授权fixture还原两张截图同日期同选中日，证明休班角标/点/副标题/详情已恢复；不把用户真实数据当QA素材，不假称系统实机已测。测试按最新分工定向跑，Codex独立验收，不重复无变化全量。

候选新目录/private/tmp/valora-calendar-parity-candidate，不覆盖正在运行V0030或dist、不退出用户App，不真实媒体/权限/日程/文件删除/Git提交推送。报告docs/reports/v0030-calendar-parity.md，交付停止等待Codex验收。保留当前功能开关和通用图标任务成果。
