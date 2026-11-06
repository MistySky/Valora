# V0099-R1 controller停止时取消旧订阅

现有会话继续；主路径16独立测试接受，整体未接受。新Tests/ValoraTests/IndependentMediaScheduleLifecycleTests.swift失败：start→stop→start→settings.nowPlayingEnabled=false，一次disable实际source.stop2次预期1。stop没移除subscriptions，start又注册导致重复处理，后续周期会继续增长。

仅修MediaController订阅与生命周期：stop取消并清空本次订阅，必要时start防止旧待派发事件影响新周期，仍一个timer/一个设置订阅。新周期读取当时真实开关，stop后不处理偏好，重复stop/start不叠回调。保留现有媒体epoch/generation与源停止/清理语义，不重写媒体链路或引入全局调度器。不要改独立断言为大于等于或删失败测试。
补/跑fake定向：原独立一次关仅一次stop、多个start-stop周期无增长、stop后偏好不调源/不重启timer，正常开关再次开启保持一表一源。只相关无窗口测试，不重复全套布局/锁屏等未改项，不全量/真实媒体/闪窗资源审计。

正式新候选自动build8或当前下一号，独立/private/tmp目录；签名/hash/Info/JSON一致；正常退出旧版→0→唯一启动（不强退/不覆盖dist）。报告docs/reports/v0099-r1-cancel-media-subscriptions.md。保留游戏移除与已接受UI/玻璃/焦点/动画/位置，Objective-C及Perl保留。不Git提交push。完成停等复验，不提前下一批。
