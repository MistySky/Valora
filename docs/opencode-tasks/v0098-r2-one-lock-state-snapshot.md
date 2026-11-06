# V0098-R2 只修一次锁态快照守卫

现有会话继续，见docs/verification/independent-v0098-r1/decision.md。R1共享所有权接受，68项相关独立通过；不改registry引用计数/玻璃/激活动作/UI布局动画。

productionHooks.sessionLockIsKnown与sessionLocked分别调用productionSessionLocked；第一次查false已知，第二次查nil，第二closure“==true”返回false，release仍激活previous。新IndependentLockActivationLifetimeTests.testUnknownSecondSessionReadMustNotBeInterpretedAsUnlocked模拟生产两次query，独立1断言失败。未真实锁屏复现，不要扩大描述。

最小改法合并两个bool hooks为一个() -> Bool?锁态读取：release只读一次局部值，nil未知与true锁定均不激活，明确false才继续frontmost/running守卫。无需添加定时器或重新查询直到成功；不增加其他焦点功能。

相关fake测试随接口合并：旧“两hook镜像第二次未知”测试可改为验证单一reader只调用一次、不拼接两次结果；分别nil禁止、true禁止、false允许（其他守卫成立），说明这是消除旧接口而非删回归。保留原跨surface逆序退出全部独立断言。只相关owner/独立测试，布局等无新改动不必重复全套。

一次正式候选build6或真实下一号，新/private/tmp目录签名/hash/版本一致，正常退出旧版→0→唯一新包，不强退/不覆盖dist、不实际锁解媒体权限、不Git提交。报告docs/reports/v0098-r2-one-lock-state-snapshot.md。完成停等验收，不扩下一批。
