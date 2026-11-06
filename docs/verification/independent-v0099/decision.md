# V0099 独立验收：限定返修

2026-11-05。主路径停表/无效游戏链路清理子集接受；controller重启订阅累积未修，整体暂不接受。

独立源码检查：音乐开启时保留0.25s与每4tick refresh，关闭stopTick+invalidate+clear；游戏检测及消费已移除，全文Sources无GameMatcher/gameApplication/isGaming。全屏与MissionControl算法未修改，旧游戏偏好仍固定false。
独立MediaSchedule4、RevivalSettingsReload5、MusicDisplayPolicy7共16通过。新增IndependentMediaScheduleLifecycleTests1失败：start→stop→start→关闭音乐，一次关闭触发2次source.stop（预期1）。Controllers.stop不清subscriptions，下一start又订阅一次，长期重启累积重复清理/发布。日志/private/tmp/valora-independent-v0099-tests.log；只fake source/scheduler，不是性能或真实播放测试。

候选/private/tmp/valora-v0099-background-cleanup-candidate/Valora.app，0.2.0/build7，两处元数据一致；strict/deep签名通过；binary97c300d2841ed509b7b75a21e5209b5db7c745da97bcf6479322b23f295c6ca5匹配；只读ps唯一PID13144对应路径。git diff --check通过。无需重启同包。

限定修stop/start订阅生命周期，不删独立失败断言或只放宽次数。不扩UI/源协议/动画及性能审计。单独说明CoreAudio/其它必须存在的监测未因本批全部停止，不宣称所有后台资源归零。
