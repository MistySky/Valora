# 桌面静置 CPU 第一批：独立验收

日期：2026-11-06。分支：codex/idle-cpu-optimization。

结论：代码及定向回归通过，允许进入桌面实机对照阶段；不代表CPU目标或全部真实体验已经验收。锁屏专项仍不开展。

## 独立审查

- 生产代码只改 Controllers.swift 与 ConnectivityController.swift，共20行新增、4行删除。没有改变0.25秒媒体、3秒设备轮询、歌词时间轴、窗口或音频刷新周期。
- 暂停同值仅跳过tick内setElapsed；applySystem仍更新权威媒体快照和时间锚。播放中即使进度被duration钳制也继续更新锚。媒体流失效重连仍由原tick节奏触发。
- 核对了乐观播放/暂停命令路径与SystemMediaSnapshot的速率归一化：已暂停快照rate为0；未收到播放快照时，不会仅因model.playing变true而从旧暂停锚按非零速率推进歌词。新快照仍同时更新速率与时间锚。
- 设备数组和输出名等值时跳过赋值，但未提前退出applySnapshot；连接事件、低电量边沿、提示更新/断开清理继续执行。AudioDevice的Equatable覆盖展示字段。
- 未发现需要阻止本批进入实机对照的代码问题。

## 本次实际运行

swift test --filter 'DesktopIdleMediaPublishTests|DesktopIdleConnectivityPublishTests|MediaScheduleTests|MediaResponsivenessTests|MediaControllerRecoveryTests|IndependentMediaScheduleLifecycleTests|IndependentDeviceMediaReviewTests|ConnectivityControllerTests|IndependentConnectivityLifecycleTests|IndependentLyricsDeadlineTests|LockLyricsTrackChangeTests|DeviceBatteryRowTests|DeviceBatterySelectionTests|DeviceBatteryProductIDTests|DeviceBatteryMetadataCacheTests'

79项通过，0失败；包含本批13项发布去重测试及相关媒体、设备、歌词回归。日志：/tmp/valora-desktop-independent-tests.log。git diff --check通过。首次沙箱执行因Swift缓存不可写失败，获得工具授权后重跑成功。

## 尚未验收

- 未打包、替换或启动新App；现有安装版不会自动使用源码优化。
- 未测改后真实CPU，不能宣称达到1%–2%。暂停/已有曲目与相同设备快照是直接受益场景；正在播放的4Hz发布和无曲目定时器不变。
- 单测不等于真实歌词人声同步、设备响应或所有交互体验通过。
- 下一阶段先保持同一媒体状态做桌面旧版/候选对照，分别记录暂停、播放和无曲目。需要测试实例时先正常退出现有实例，确认0进程再启动唯一实例。锁屏专项按用户要求留后。
