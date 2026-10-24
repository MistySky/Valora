# V0011 中断接续（不是重新执行）

你在同一会话处理docs/pi-tasks/v0011-line-lyrics-display-sync.md期间，2026-10-24本地约02:22—02:23发生terminated及连续Request timed out，未提交v0011报告，邮箱现ready。Codex只读核实会话错误后恢复这一次，不新建会话、不重写历史、不重复从头做任务。

先读AGENTS.md及原V0011任务，检查当前工作树已写的LyricsTimeline.swift、LyricsService.swift、LyricsController.swift、Models/QQMusicLyrics/MarqueeLabel等修改，在现有成果上继续未完成的UI/设置接线、QA、回归、构建签名与交付。不要覆盖或重复已完成逻辑，不把上次shell的echo done当编译成功，读取实际构建退出码和错误日志。范围只限原V0011，不开QRC或设备等后续任务。

完成docs/reports/v0011.md及docs/verification/v0011/后停止等独立验收，遵守原任务的UI/图标/媒体写操作/来源只读/不安装发布Git提交等全部边界。若上游再次超时或不可用，保留成果并明确报告失败，不自行切模型或无限重试。
