# V0009-R1 独立验收（2026-10-24）

结论：原缺陷修复通过，但整体验收未通过；鼠标悬停后重置屏幕的同类空闲路径仍遗漏，限定R2返修。

独立swift test原95项通过（Valora33/Core62），包括此前失败的暂停pending期间换屏回归；独立构建产物/private/tmp/valora-independent-v0009-r1/Valora.app并完成打包签名。未安装或控制真实播放器。

新增独立回归testPausedHoveredActivityExpiresAfterDisplaySelectionClearsPointer实际失败（pointer-test.log）：暂停，pointerEntered(true)，此时visible=true/pending=false；切All displays到Main display，resetForScreenChange把model.isPointerInside清为false，但没让mediaIdle.input.pointerInside同步，也没有pending任务可重建。等待3.6秒后仍visible=true。

R1只处理已有pending计时；还须在屏幕重置移除旧指针归属后对真实媒体输入重新求值，使此前因指针停留而不计时的暂停活动开始有界计时。保留已有计时剩余期限及同值轮询不延后策略，不删弱测试。

真实双屏体感仍未验。功能UI/图标按原版Alcove，归档复刻仅作迁移代码参考；Valora已确认品牌图标保持。歌词、清理、设备按用户顺序待现有功能验收后推进。
