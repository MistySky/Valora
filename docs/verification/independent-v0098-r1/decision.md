# V0098-R1 独立验收

2026-11-05。跨surface所有权子集接受，整体仍需锁态单次读取限定返修。

独立源检生产两处owner已共享registry；原独立逆序退出断言保留并通过。独立相关68项通过（owner14+独立1+协调器32+布局13+歌词8），日志/private/tmp/valora-independent-v0098-r1-tests.log。

新增独立边界失败：production sessionLockIsKnown与sessionLocked分别调用productionSessionLocked，前次false已知、后次nil时第二closure的“==true”给false，release仍激活previous。IndependentLockActivationLifetimeTests新增testUnknownSecondSessionReadMustNotBeInterpretedAsUnlocked用fake镜像真实两次查询，1失败；不是实际登录复现。日志/private/tmp/valora-independent-v0098-r1-query-transition.log。

最小修复将查询收敛到一次Bool?状态读取，一份快照只允许==false恢复，nil或true不激活。接口合并后原两hook镜像测试可改为验证一次读取、不混合快照，并覆盖nil/true/false；保留原跨surface独立断言。

build5 Info.plist/JSON一致；签名strict/deep通过；binary10b90acfc65fe93d6cfba26fc18c886d7c5807be4104d6bf7b0105ff897a8ed9匹配；只读ps唯一PID6584为/private/tmp/valora-v0098-r1-shared-lifetime-candidate/Valora.app。不重复启动。不全量/闪窗/资源测试，未触真实焦点/锁屏。
