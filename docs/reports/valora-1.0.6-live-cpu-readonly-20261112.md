# 1.0.6 CPU只读排查

用户反馈恢复日历入口后CPU约8%。运行进程28780，/Applications/Valora.app，1.0.6/build65。未重启、未改偏好、未控制媒体、未改生产源码。

16:42:54–16:43:08短窗ps %cpu读数：14.7,16.6,9.7,21.5,4.5,8.9,3.7,6.8；存在波动，不能把单次读数当固定稳态。累计CPU时间从32.25秒到34.45秒，14秒内消耗约2.20CPU秒；采样与ps窗口并不完全重合，不能将该值冒称无探针基线。

十秒sample：/private/tmp/valora-1.0.6-cpu-20261112.sample.txt。物理footprint约70.5MiB。

调用栈里有NativeLyricsRowClock.fire/update/switchLine/buildTextLayers及SwiftUI/AppKit布局/提交，另有ScreenStateMonitor、AudioOutputController轮询。MenuBarModuleController.updateMonitorImage少量出现。未采到ensureStatusItemVisible、setCalendarVisible、updateCalendarImage、applyFeatureSettings、queuePointerUpdate或SLSSetWindowEventMask。SystemMediaSource.readStream大量采样处于阻塞等待读取，不能算成CPU热点。采样栈是墙钟统计，不直接等价CPU归因百分比。

1.0.6相对1.0.5仅新增status item命名/显式可见性恢复，没有新Timer。该恢复由启动/设置更新触发，非持续轮询；日历观察只追踪menuBarText，图片按文本变化去重。这些证据不支持“日历可见性修复在持续循环”的结论；但未做同条件有/无日历A/B，不能据此断言日历贡献为零，亦未锁定本次高CPU唯一根因。

已向用户询问当时暂停/播放歌词/鼠标交互状态，待答复后决定是否需要暂停或关闭歌词的受控对照。本次未派发修复或构建新包。
