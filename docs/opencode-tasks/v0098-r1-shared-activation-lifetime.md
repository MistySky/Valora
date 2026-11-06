# V0098-R1 焦点所有权限定返修

现有会话继续。独立验收见docs/verification/independent-v0098/decision.md。本批整体未接受，不进入下一项调度清理。

## 已复现失败
新增Tests/ValoraTests/IndependentLockActivationLifetimeTests.swift：两surface各有owner，card.acquire→preview.acquire→card.release，preview仍持有，policy却已accessory且activatedApps非空，2断言失败。原8只测preview先release，不能证明跨owner引用计数。生产正是各自makeProduction，私有depth不共享。

最小修复：同一NSApplication的临时策略应有共同生命周期，任何退出顺序均须最后surface退出才恢复首次原策略/考虑恢复旧应用。每个surface仍防重复进入与未持有release；注入共享状态/小型scope即可，不扩为全局焦点框架。保持首次原状态不被覆盖、最后退出清除，再次进入重新捕获；原already-regular情形不擅自降策略。不能通过删除预览、删失败断言或取消所有焦点守卫来通过。
独立测试可为必要共享scope注入调整初始化方式，但必须保留“先进入者先退出仍regular/不得激活旧应用、最后退出仅恢复一次”的原断言。补两种退出顺序、重复release、每owner嵌套和新周期；不构造真实NSApp激活。

## 未知锁态
production sessionLocked现在缺session或key时返回false，不能代表已解锁。改为缺少明确解锁证据就不激活previous app（Bool hook可保守true或明确tri-state）。有纯函数/注入fixture覆盖nil、缺key、异常类型、true/false；不真实锁解，不读取个人账号字段、不申请权限。

## 同轮文案
LockCardPreview、LockGlassSurface与coordinator present附近仍残留“Liquid Glass only/key/reference same constraint”绝对说明。只改为本实现观察与当前取舍/真实锁态待验，材质和激活动作不借文案修改。不能声称本批消除了实际密码焦点问题。

只改这两处生命周期及相关注释/定向测试；Objective-C/Perl保留，不改已接受UI/动画/位置/歌词/音量/设备。只相关fake回归，不全量/闪窗/性能。完成一次Release候选自动build5或当前下一号，新/private/tmp目录签名/hash/版本一致。正常退出旧版→0→单实例启动；不pkill强退、不覆盖dist/运行包、不真实媒体/权限/锁解、不Git提交推送。若工具无正常退出能力，交Codex接续，不擅自强退。报告docs/reports/v0098-r1-shared-activation-lifetime.md，完成停等复验。
