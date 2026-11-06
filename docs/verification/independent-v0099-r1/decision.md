# V0099-R1 独立验收接受

2026-11-05。独立源检stop guard/isActive、停表、清subscriptions与源callbacks，start只注册新周期；独立原失败start-stop-start一次关闭仅1次stop通过，断言保留。

实际独立11项通过：MediaScheduleTests5（非报告所写6）+IndependentMediaScheduleLifecycleTests1+RevivalSettingsReloadTests5。日志/private/tmp/valora-independent-v0099-r1-tests.log。游戏链路及全屏/MissionControl差异沿上一轮已接受源检和显示策略7，不重复未改动全套。报告数量笔误应更正，不是功能阻断。

候选/private/tmp/valora-v0099-r1-media-subscriptions-candidate/Valora.app，0.2.0/build8与JSON一致；strict/deep签名通过；binary203363338181fbcf3d41b9f3363c8abc34cc82c11d30b472badfd5fe7bacd024匹配；只读ps确认唯一PID15445路径对应。git diff --check通过。无需重新启动同包。

仅fake调度/源与测试偏好，不真实媒体/锁屏/权限、不全量/资源审计/闪窗，不Git提交推送。功能关闭不再有此专用tick，不宣称整App无后台采样。V0099及R1自动范围接受，可推进限定无引用/无障碍收尾。
