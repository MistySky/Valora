# V0035-R1：独立验收三失败限定返修

V0035未接受。先读docs/verification/independent-v0035/decision.md及Tests/ValoraTests/IndependentDeviceMediaReviewTests.swift，本聊天Codex新增三个隔离case全部失败（5断言），原26相关case通过，签名通过。当前用户运行的是V0034独立候选，不得覆盖/退出/重启，耳机正戴着，不再要求用户反复连接、不控制真实音乐。

## 必修1 设备事件遇在途读取
onConnect当前known.remove后refresh，若queryTask/queryInFlight存在就丢刷新；独立held source测期望calls3实2。事件到达应合并一个pending fresh query，在当前read结束后立即进行，不等3秒poll；同时间多个事件保持有界/去抖。不让事件前已开始的陈旧快照消费新连接标记并伪造到达，需事件revision或待处理ID生命周期，至少最新read才用于判定新连接。off/stop/授权撤销取消pending与事件标记，旧generation不能清除新session pending；首次baseline、不重复arrival动画、one-in-flight及纯输出变化不冒充蓝牙连接保持。
独立测试仅通过Mirror拿到现有ConnectivitySystemEvents.onConnect闭包，未真实注册事件/读取硬件，不得删断言或以这个是fake为由忽略生产同路径。

## 必修2、3 音乐旧命令回调污染
commandGeneration仅在下一次command递增，invalidate/stop/clearMedia/源切换未失效，故旧失败可覆盖新歌曲snapshot或停止后的model。新增testFailedOldToggleCannotOverwriteNewTrackSnapshot和testFailedToggleAfterStopCannotMutateModel须通过。需要控制会话与权威快照revision校验，不能简单移除失败处理/错误消息或忽略所有失败。播放即时反馈仅是pending反馈，真实来源/播放状态/歌词与播放时间锚应保持可校正，不能用假playing状态造成歌曲实际仍播但歌词错误停住；同源新权威快照到达后旧失败不得再回滚（不仅换track）。快速多次点击/成功失败交错、stop/restart、source清空之后旧completion不能污染新状态。保留能力/source校验、真实命令仍一次派发、后台I/O，不因修复改音乐UI/封面/歌词/seek语义，不删可回滚反馈测试。

## 电量与报告边界
C返回类型检查/左右电量优先保留；没有真实字段值则明确电量仍待实机，不能只凭ABI类型不一致就断言原错误根因已证实。0保留真实可能值，未知隐藏，不能把所有0当未知或填100。用户授权的当前耳机只读最多3样本/10秒范围可用，但不得向运行进程注入/新权限/外部TCCprobe/启动多生产实例，也不为取值破坏正在听歌。若仍无法不打扰地拿真字段，诚实列待用户新候选一次确认。
系统AirPods原生提示没有证据的抑制不实现，不改系统通知。

## 交付
仅修上述生命周期与回归，保留V0034无下载/Codex与Calmon/简洁设置；定向无弹窗测试（包括新增独立三case及必要同源新snapshot/旧回调），禁止--verify-*或包含showCalendarPanel/showMonitorPanel的测试。旧V0035测试清单误含MenuBarModuleControllerTests.testPanelsAreIndependentAndSwitchingClosesTheOther，后续明确跳过，不称全无界面。无循环菜单/批量截图/压力资源性能测试，不机械全量。
一次必要build/signature，候选/private/tmp/valora-v0035-r1-device-response-candidate，报告docs/reports/v0035-r1.md，逐项根因/修复/结果/实际未测写清楚。不得Git提交推送/改只读归档模型历史/安装发布/真实媒体设备操作/覆盖当前用户App和dist，定时器关闭；完成停等Codex独立复验。
