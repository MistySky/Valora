# V0016-R2 修复真实日历开关被系统签名策略直接拦截

用户反馈“点日历不行，点了不能去授权”。Codex实际dist只点一次开关复现：没有系统授权窗口，直接应用alert“日历读取未获授权，功能保持关闭”。未接受授权/读取事件。精确TCC证据见docs/verification/independent-v0016/runtime-calendar-entitlement-failure.md。

已定位：dist flags adhoc,runtime；scripts/package.py codesign --options runtime，却无--entitlements。系统明确报kTCCServiceCalendar requires entitlement com.apple.security.personal-information.calendars but it is missing。此前报告“非沙盒不需entitlement”忽略Hardened Runtime，必须纠正，不继续用fake通过宣称入口可用。

最小修复：将com.apple.security.personal-information.calendars=true加入项目签名entitlements，并在最终app codesign明确应用该文件；保持--options runtime，不关闭保护、不无故开启sandbox，不加联系人/提醒事项/摄像头或其他额外资源，不清TCC/重置用户权限。NSCalendarsFullAccessUsageDescription保留。最终codesign -d --entitlements导出必须包含此项且runtime仍启用；构建签名/打包QA需核真正签名的app，不只检查源XML。

Apple官方参考：https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.personal-information.calendars 。核对SDK/官方能力，最小迁移。

EventKitCalendarAuthorization现requestFullAccessToEvents把Bool/Error全部丢弃再只读status，遇签名/系统服务错误只显示“未授权”。最小保留安全的失败诊断（domain/code或说明，勿日志输出日程/隐私内容），区分真正拒绝与配置/请求失败；不把错误伪造为denied。正常成功/取消generation/pending不回退，不借此重构现有全部权限。

本修复与V0016-R1图标同轮收尾；R1已busy时别从头重跑，不改已发任务哈希，读本新任务继续。报告docs/reports/v0016-r2.md，更新research错误结论与最终entitlement证据，构建/测试与必要回归，交付后Codex独立核签名再由用户实际点授权。pi不要真实触发/接受权限，不读个人事件，不写系统/TCC，不安装发布/Git提交推送，不改原归档/品牌，不开新模块或恢复定时器。
