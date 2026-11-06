# V0098 独立验收：暂不接受

2026-11-05。独立源检、焦点fake定向回归和候选签名核验；未实际操作锁解/其他应用焦点。

原LockActivationOwnerTests8通过；新增IndependentLockActivationLifetimeTests1有2条断言失败：两个owner先后acquire，先进入的card先release而preview仍持有时，策略已经恢复accessory，并激活previous app。原测试只测后进入者先release，未覆盖相反退出顺序。当前每个surface各有独立owner/depth，不能保证跨owner最后一个退出才恢复。日志/private/tmp/valora-independent-v0098-focus-tests.log。新增测试源码保留，不允许删断言以通过。

另production hooks sessionLocked在CGSessionCopyCurrentDictionary缺失或CGSSessionScreenIsLocked不可判时返回false，把未知当已解锁，可能允许恢复旧应用。按任务应缺少解锁证据就不激活旧应用。此项静态证据，未进行真实系统复现。

候选/private/tmp/valora-v0098-focus-lifecycle-candidate/Valora.app版本0.2.0/build4，Info.plist和build-verification一致；严格deep签名通过；binary de71eb0b8dcb21a2516a63a5b356c8e2daa6db9fa483a1c4ca63d3fbf13ba39b与报告一致。只读ps唯一PID2823，路径匹配。包交付核验不等于功能接受。

现有部分注释仍宣称只有key窗口才有玻璃（LockCardPreview/LockGlassSurface/协调器present附近），与报告“已改为观察取舍”不完全一致，后续同轮修正但不得改变当前材质实现。

限定R1：共享策略生命周期覆盖任意退出顺序；未知锁态不恢复旧应用。保留用户已确认UI/动画/位置/媒体链路，测试仍只无窗口fake，不全量/资源审计。
