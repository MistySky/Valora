# OpenCode 锁屏修复独立验收

2026-11-03。实际项目/会话是 /Users/wangqing/code/Valora、session_v2 ses_e60ad9e4bffekz1hsfhtNOnPtJ「锁屏刘海屏扩展问题」。当前聊天cwd为archive，但此次修复未发生在那里。已只读会话用户/assistant正文：用户seq925确认“你这把修复的不错啊”。原报告将作者误写Codex；实际来源为本次OpenCode会话，不以该报告署名为作者证据。

## 核心效果接受

原native非空原Space前置条件挡住新窗口；新实现先透明order、支持已知空成员，add目标并移除其它成员，验证独占后揭示overlay、挂起primary；解锁恢复原成员。不是Y补偿或改glyph。代码、用户反馈和实际日志互相支持。

本次独立读取的日志有4轮overlay ready/release；window1316/1339/1358/1381锁屏成员仅[92]，unlocking/restoring采样均Quartz[552,0,624,320]；释放回[1]，未见fallback。锁定早期Quartz为null，不能称所有锁定帧已测或每帧绝无偏移，但用户实际动画认可，并且旧版Y55/Y37问题的解锁采样已得到反证。

40项Swift定向全部通过（LockMusicCoordinator/LockPreview/NotchDiagnosticCapture）；当前生产native代码两组fake各6场景通过。无真实窗口/Space测试、无UI循环/性能/真实锁通知。候选strict/deep签名通过，binary833de47049f058b530442d433c26f9f20c3a4581ecd68d42f16c486b03b0b323与报告匹配；未另行重新构建Release或退出/改签正在运行实例。

## 收尾缺陷，不回退已修好的主路径

独立新增native场景可复现：从桌面11独占迁移同window7两次，两次均success；detach后desktop11未恢复。原因migrateWindowNumberExclusively每次用captured覆盖_originals，第二次captured=[owned]覆盖第一次[desktop]。输出first=1 second=1 restoredDesktop=0，退出1。最小修复应保留首次成功捕获直到detach，补重复迁移后restore回归；不影响用户已认可动画，不立即改/替换运行包。复现源码保存在本目录，编译时用当前项目的ExclusiveSpaceMigrationTests.m辅助fake，不构造真实窗口。

另：isWindowComposited将缺失onscreen字段当false，与注释的unknown不fallback不完全一致；0.25秒校验使用静态查询，未注入覆盖不可见/unknown分支。仅记审查边界，不把CGWindow缺字段推断为实机故障。

## 后续记录入口

scripts/read_opencode_records.py只读本地opencode.db，优先session_v2/session_message，兼容旧session；按项目目录精确过滤，默认Valora，输出用户/assistant正文，不输出reasoning/tool/认证配置。已实际查到本次会话及用户结果。数据库不修改，不运行OpenCode，不新派工。
