# V0003：独立验收限定返修——媒体断线恢复与seek安全边界

按用户顺序V0001迁移→V0002图标已完成，Codex已统一独立验收，记录docs/verification/independent-v0002/decision.md。图标接入通过，98XCTest、91项真实SwiftUI合成检查、独立重构建相同binary/icon和实际只读媒体读取通过，但完整候选仍有两处具体问题。本任务不是新功能，不动旧布局/动画/默认选项和已确认图标，不重新架构。

1. Controllers.swift MediaController.start中的system.onError只clearMedia；SystemMediaSource退出时已将process=nil，而Controller.systemStarted仍true。refresh永不再次start。以最小改动让错误/退出后控制器可经既有定时refresh恢复；禁用/stop后不得继续重连，不能同时多开adapter；失败重试须有限频率，不能同步递归或紧密循环。测试应在真实Controller使用fake source模拟首次启动失败/运行中流退出→后续成功，确认状态/快照恢复、停用后不重试、并发重复refresh不多开进程。仅加必要测试注入边界，不用重新写一套媒体架构。
2. Controllers.seek中Int64(target*1_000_000)存在有限Double过大/乘法溢出/Int64越界trap；Snapshot秒数只finite不能保证微秒Int64。安全检查/转换后才派发；非法或不可表示目标安全拒绝且不调用runner，正常clamp/舍入语义保持旧实现。补Double极大、接近Int64边界、NaN/infinity、普通seek的回归。全部fake/no real player write。

不要动源alcove-revival-archive，不启用任何新功能/新语言/权限，不重做图标。报告保留V0001/V0002，交付更新dist/Valora.app、docs/reports/v0003.md与docs/verification/v0003/，记录最小diff/新源映射指纹/必要回归/实际只读smoke/包图标不回归。不在既有历史manifest里冒称修改前后相同。真实播放器控制、音量亮度、权限登录项、安装发布、Git提交都不执行。完成停止等Codex复核，通过后交用户试用。
