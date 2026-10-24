# V0009-R2：限定补齐悬停暂停后屏幕重置空闲计时

先读AGENTS.md与docs/verification/independent-v0009-r1/decision.md。R1原95测试与构建已独立通过，但新增独立回归 testPausedHoveredActivityExpiresAfterDisplaySelectionClearsPointer 失败，日志pointer-test.log。

复现：fake歌曲暂停，pointerEntered(true) -> visible=true/pending=false；All displays改Main display触发place/resetForScreenChange，指针清false但mediaIdle.input.pointerInside仍true，且没有pending可重建，3.6秒后活动仍visible。修复屏幕重置后媒体输入重新求值/计时生命周期，保证悬停退出归属后启动正常3秒期限；若原来已有pending，保留剩余期限；同值metadata不延后。检查屏幕拔插/隐藏/禁用再启用同路径。保留独立失败回归，不删弱断言；不大改协调器/动画。

用户再次明确：功能UI、控件图标、布局、动画与Alcove一致，可参考来源复刻代码直接迁移；保持现有已确认精简。Valora应用彩色图标与Outline-v7菜单栏标识是用户确认例外，不改回原版品牌，不改图标资源及打包接线。

只修该空闲状态缺陷，歌词暂不实现。正常媒体控制、两页设置和多屏规则保留。禁止真实播放/切歌/seek/音量、蓝牙连接和系统设置/权限/登录项写操作，不安装发布/Git提交，不改来源。不要创建自己的定时器或下一任务，Codex单独接续。

交付docs/reports/v0009-r2.md、docs/verification/v0009-r2/、dist/Valora.app，独立失败回归及原95测试通过，构建签名通过；附最小变化与实机限制，完成待Codex复核。
