# V0015-R1：设备开关、停止生命周期和声音收尾

先读docs/verification/independent-v0015/decision.md及AGENTS。V0015原185项独立测试/构建签名、设备QA29/精简设置视觉通过子集；整体仍待本返修。仅修下列项，不重做UI/动画，不新增功能模块。

1. 修复Codex新增IndependentConnectivityLifecycleTests两项，不删除测试/改期望：false→true时初始baseline应在Published提交后及时发起，不能等3秒timer；保持初快照不弹、无重复查询。stop后不能再从refresh/迟到订阅/旧timer重启查询，明确started/订阅生命周期；显式重新start可恢复。
2. stop/关闭开关时仍有不合作的底层读取，保持真实单in-flight上限，不能仅清标志导致新读取无限排队或并发；晚结果绝不重开toast。补off→on/stop→start/旧source晚返回的回归，确保新一轮基线和token隔离。
3. LowBatterySoundPlaying增加停止/取消能力，生产保留NSSound对象直到完成或主动stop；低电量总开关关闭、controller.stop、必要退出收尾主动停止已播放声音。QA仅sound spy，不实播。声音播放去重/重新武装保持；补spy验证开关关闭/stop会停止且不再播放，避免只验证计数而没有停止接口。
4. AppDelegate.applicationWillTerminate调用设备controller.stop，且不触发lazy初始化造成退出时新查询。保持现有lyrics/media/audio收尾。

报告docs/reports/v0015-r1.md；针对性回归及完整swift test、构建签名，必要设备/设置/音乐歌词多屏隔离QA。保留总开关/外观两项、固定5秒/20%/低电量声音开策略及原版/复刻区分证据；不修改原归档/品牌图标/资源许可，不真实连接/断连/配对设备，不修改蓝牙/音频来源/音量，不触发或接受权限提示，不实播提示音，不Git提交推送/安装发布，不恢复定时器。

正式交付后停止等Codex独立复验，真实设备与3D实机项目如实待验。
