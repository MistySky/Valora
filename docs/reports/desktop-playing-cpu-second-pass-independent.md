# 桌面播放态第二批独立验收

2026-11-06，分支 codex/idle-cpu-optimization。

## 结论

有限通过：本次独立定向回归47项通过、0失败，代码差异格式检查通过。但用户核心问题“歌词开启约10%以上、关闭约2%”未解决，不接受第二批作为播放态性能优化完成，不进入锁屏专项。

本次确认正在运行的进程PID22471来自 /private/tmp/valora-desktop-playing-cpu-r2-candidate/Valora.app，而非上一批候选。用户对照仍需区分同曲目/同界面，但它是聚焦歌词路径的重要线索。

## 实际改动和覆盖边界

- 收起态媒体锚点发布降至1Hz，展开或锁屏音乐卡仍4Hz，显示状态切换补发锚点；歌词本地30Hz时间轴保持。
- 普通刘海的部分紧凑内容根据notchSurfaceOnScreen挂载；波形根据NSWindow.isVisible暂停时钟。
- 可见歌词每帧的文本、遮罩、行查找、滚动计算路径未改。不可用发布计数下降证明已解决歌词开启时的CPU。
- 1Hz锚点目前主要以发布次数测试验证，真实歌词同步与曲末钳制等边界仍需补充行为验证，不能仅凭次数断言体验完全等同。

## 验证

实际执行：swift test --filter 'DesktopPlayingCadenceTests|DesktopIdleMediaPublishTests|DesktopIdleConnectivityPublishTests|MediaScheduleTests|MediaResponsivenessTests|MediaControllerRecoveryTests|IndependentMediaScheduleLifecycleTests|IndependentLyricsDeadlineTests|LockLyricsTrackChangeTests'

47项通过，0失败。日志 /tmp/valora-r2-independent.log。未再次运行窗口开关测试，不启动第二App、不改变真实媒体或用户界面。

## 补验项（不是已复现的功能故障）

- PlayingWaveformVisibilityTests在每次orderFront/orderOut后主动configure，不能证明实际occlusion通知能自动停/恢复。补一项不调用configure的生命周期验证，并核查新增block observer的销毁清理。
- notchSurfaceOnScreen是全局visible意图值，写入发生在后续锁屏/多屏orderOut分支之前，不是所有面板真实isVisible的集合；不得把它描述为完整的可见性证明。锁屏专项仍留后。

用户最新判断波形大概率影响较小，结合歌词开关对照，波形补验不应抢占歌词性能归因优先级。

## 后续建议

聚焦可见歌词：区分每帧必要的高亮/滚动和可缓存的文字、度量、行边界/布局准备工作。保留同步、高亮、滚动和流畅度，不直接降低30Hz帧率。补充在同曲目和同布局下歌词开/关的性能样本；根据证据实施，不把等待栈计数转换为CPU百分点。

没有修改生产代码，没有重新派发修复任务。歌词补充任务文件已经准备，但发送动作在用户转为要求验收后被自动审批拒绝，因此并未发到OpenCode。
