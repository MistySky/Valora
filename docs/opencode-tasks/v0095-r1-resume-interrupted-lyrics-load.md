# V0095-R1 限定收尾：恢复被隐藏打断的同曲歌词加载

用户实测V0095“看上去没啥问题”，Codex独立确认原主修复和6用例通过。保留，不重写已认可主链/UI/动画。

读docs/verification/independent-v0095/decision.md与新加LockLyricsTrackChangeTests.testInterruptedLoadingResumesWhenSameLockCardReturns（实际1case2断言失败）。

原因：loading期间surface消失→取消并设unavailable，但currentIdentity仍A；卡片回来仍A，identity==currentIdentity直接return，永久无歌词直到换曲。修复只让“由于真实需求消失而取消的在途load”在需求重新出现时可恢复一次，不要把所有unavailable视为重试条件。

必须保留：已成功同首跨锁/显隐不重复请求；3s超时/接口失败同首不被0.25s/元数据轮询无限重试；快速换曲取消/代次拒绝、全局开关关闭清空/取消、新歌曲识别/共享缓存。若无表面期间换曲，恢复时不能出现旧曲歌词。可清除专门取消中的身份或明确request状态，不新起第二Provider/服务，不改音乐/锁屏玻璃、Space、音量、头像位置、顶部对齐、菜单图标。

只做新增原失败+已有LockLyricsTrackChangeTests/IndependentLyricsDeadlineTests/必要协调器的少量无窗口功能测试；补一个真实超时后重复metadata不重试的负例。不真实切歌/锁屏/网络歌曲/系统权限，不全量/闪窗/性能。

任务完成构建签名，新独立/private/tmp/valora-v0095-r1-interrupted-load-candidate目录（已存在换新），不要覆写运行包/dist；按用户要求正常退出→确认0→启动唯一新实例。报告docs/reports/v0095-r1-resume-interrupted-lyrics-load.md，保留用户认可的主流程，不Git提交push。完成停等Codex验收。
