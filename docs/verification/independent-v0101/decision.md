# V0101 开发编译边界独立验收：限定返修

2026-11-05，基于已含数字单位空格补充的build12和当前源码。Release门控/主要实现隔离子集接受，debug入口隔离未完整，不整体通过。

源检Package.swift仅debug定义VALORA_DEVELOPMENT，11个开发文件与AppDelegate对应分支条件化，shared controller构造已回到条件外。正式main在NSApplication.shared之前拒绝。直接执行当前build12二进制带--verify-music/--audit-fluidity/--preview-settings/--expand-media/--lock-card-preview，均退出2并明确development-only，未创建UI或启动真实服务，不是开关弹窗测试。

独立LaunchPolicyTests10通过。新增IndependentDevelopmentIsolationTests2共4条断言失败：standalone --lock-card-preview和--expand-media都不在AppRuntimeDefaults.qaArguments中，startupMode仍.production，resolve选standard。AppDelegate走完整正常服务启动后才到辅助flag。这不符合任务“开发预览隔离配置、不能fake变真”。未真正运行这些debug模式，均纯参数判断。日志/private/tmp/valora-independent-v0101-launch-tests.log。

修复可为有效组合设隔离非production路径，或拒绝不支持的standalone辅助参数并在启动前明确错误（若改为拒绝，独立测试可按真实契约验证早拒绝，不能只从开发gate名单删flag来掩盖）。保留可用debug QA能力、Release条件和正常运行功能。

主体报告已记录SettingsReductionTests.testSidebarGroupsFollowTheUserApprovedStructure旧期望漏Codex用量。独立读源码确认期望仍[日历,系统监控]，实际用户已确认[日历,系统监控,Codex用量]。此为后续测试契约更新，不能为绿测试删实际页面；本轮不跑含真实窗口的整套SettingsReductionTests。

当前运行build12的签名/hash/单实例证据见independent-reset-card-unit-spacing/decision.md；V0101不能用间距补充通过替代。未全量/资源审计/真实媒体权限锁屏操作，未Git提交push。下一步R1两个入口→文档现行契约/过期断言→完整功能与全局联动回归→修完缺陷后资源和动画流畅度专项。
