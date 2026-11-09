# 换句单调时钟独立验收

2026-11-09。新 OC 会话 GLM-5.3-Flash 完成 `desktop-lyrics-transition-monotonic`。审查 `LyricsRowExperimentHost`：换句开始记录 `systemUptime`，每次 Timer 依据经过时间除以 0.2 秒更新；迟到回调在首次执行时到终点并注销计时器和旧句。曲线与偏移数值未改，正常路径未引入实时逐帧抓图。

独立运行：`VALORA_LYRICS_EXPERIMENT=1 swift test --scratch-path /private/tmp/valora-experiment-tests --filter 'IndependentLyricsTransitionClockTests|IndependentLyricsTransitionClockHostingTests|IndependentLyricsEmptyTransitionTests|IndependentNotchPrefilterTests|NotchHitTestPrefilterTests|SeekProgressTests'`。24 项通过，0 跳过，0 失败，日志 `/private/tmp/valora-monotonic-independent-review.log`。

接受范围：实验版按经过时间推进的计时逻辑及上述定向回归，包括延迟回调、空歌词、鼠标预筛选和 seek。OC 报告的构建隔离及其他测试记录见 `desktop-lyrics-transition-monotonic.md`；本次未重建 Release 或独立复跑完整宿主截图组。

仍未验：新候选在真实 App 的换句体感、CPU/内存、真实播放、1x 与多显示器。用户当前运行的 build33 不含本次后续代码，本次没有替换它；不能由计时测试断言原版视觉完全一致或 CPU 达标。
