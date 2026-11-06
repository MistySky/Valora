# V0103 独立验收：安全自动范围通过，整体验收未完成

2026-11-05。独立核原始run1/run2/run3：均启动398个不同用例，报告排除的窗口类未混入。首轮1失败，随后两轮零失败的记录属实，不能用重跑抹去首败。

Codex独立集中执行一次相同安全范围：ValoraTests261+ReferenceCore137=398，用例来自72个类、398个唯一测试，0失败。日志/private/tmp/valora-independent-v0103-swift.log。排除47个窗口/状态项测试，故只能称安全自动范围通过，不能称所有功能/全部全量通过。测试setUp/tearDown和缺省依赖属于预审范围。

独立重新编译并运行当前生产native fake callbacks四文件：Exclusive6+Isolated6+LockMigration6+Repeated5=23通过，日志/private/tmp/valora-independent-v0103/。构建号与package入口两脚本独立通过，仅临时目录。没有新Release构建/编号/换包，不操作真实播放、锁解、设备或权限，不性能/闪窗压力测试。

首败IndependentCodexTransportTests.testRestartKillsPreviousTerIgnoringChild还未确诊：源码pidText一旦读到非nil就停止等待，但shell“echo $$ > pid”先创建/截断文件再写，合法的短暂空字符串会让pid转换失败。此为确定存在的测试就绪竞态，不足以断定本次失败必由该竞态或系统负载造成。contactsd/AddressBook日志同期出现不证明因果。建议先仅测试修正就绪判定并保留未启动时的任务错误/超时诊断，保持产品取消和deadline断言，不改产品实现、不无理由反复跑398项。

当前结论：无已确认产品缺陷，已知一个测试时序失败需收尾；47窗口测试与真实锁屏/焦点/合盖、QQ人声、物理双屏、设备/授权、菜单真实渲染仍待功能验证，不算失败也不算通过。资源及动画专项仍不开始。下一步限定测试就绪返修，再整理一次用户实机功能核对清单；不得绕过此前不批量闪窗要求。
