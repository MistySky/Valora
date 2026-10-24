# V0009-R1：限定返修暂停期间换屏使空闲计时失效

先读AGENTS.md及docs/verification/independent-v0009/decision.md。本任务是已授权V0009验收返修，不新增功能，不恢复定时派工。

Codex独立构建/签名与原91测试通过，但新增真实WindowCoordinator回归 testPausedIdleDeadlineSurvivesDisplaySelectionChange 已失败：fake暂停歌曲pending=true时，将All displays切Main display，3.6秒后活动依旧visible=true且pending=true。完整日志docs/verification/independent-v0009/idle-test.log，测试在Tests/ValoraTests/MultiDisplayCoordinatorTests.swift，不删除或削弱断言。

原因已定位：WindowCoordinator.place -> PresentationController.resetForScreenChange取消idleTask而保留mediaIdle.input/pending；相同输入mediaStateChanged的update返回false，不会重建deadline。按最小范围修复：纯显示/几何变化不能永久中断共享媒体暂停空闲周期；明确保持剩余期限或建立合理有效计时，不使同值metadata轮询不断延后。核对屏幕拔插/隐藏/禁用再启用同类取消路径；不要大幅重写协调器/成熟动画。

保持V0008设置精简、V0009各屏可交互且唯一活动屏、基础右键菜单、基础音乐功能及Codex Outline-v7图标不变。歌词仅待办，不实现、不加依赖；不修改来源、不操作真实播放器/系统权限/登录项、不安装发布/Git提交，不恢复任何自动派工。

交付docs/reports/v0009-r1.md、docs/verification/v0009-r1/与重新构建签名的dist/Valora.app。运行失败回归并覆盖必要同类路径，原91测试回归；不得把fake/注入多屏当实屏体验。完成停止等独立复核。
