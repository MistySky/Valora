# V0040 设置精简独立验收

2026-11-03：本批代码和设置展示范围接受。独立无窗口LockMusicCoordinatorTests31 + LockMusicStateTests13共44项通过。源码确认模拟锁屏的controller/状态/订阅/专用测试无引用，锁屏仅三行，音乐独立nowPlayingEnabled、设备bluetoothEnabled并订阅实时更新；旧锁屏专用偏好不再读取。NativeBridge相对9b2953e无差异，锁解接管代码仅模块gate/deinit取消补齐，未改已有锁解动作链。

候选/private/tmp/valora-v0040-lock-settings-candidate/Valora.app，binary0b1c675d05768a8168e84ef8128c439286b7fb3479e1640ca1d05fa676cba729，strict/deep签名独立验证通过；未另行独立Release重编译。当前进程清单无旧Valora后按用户启动要求CUA启动本包。

真实设置AX核验：锁屏页只有启用锁定屏幕on、锁定提示音off、解锁提示音off。后者是保留的当前用户偏好，未擅改为注册默认on。通用仍有强制模拟刘海off。真实候选音乐刘海及歌词存在。只导航通用→锁定屏幕各一次，未点任何开关、媒体控制或授权，也未执行真实锁屏。

本轮初次选择回归误含会构造窗口的IndependentInteraction/MultiDisplay测试，已明确告知用户并Ctrl-C中止（exit130），不把整个中止运行计通过。随后确认xctest进程已退出，仅重跑44项真fake无窗口用例。未继续UI循环/性能测试；原中止日志留/private/tmp/valora-v0040-independent-tests.log。

实际锁屏中音乐/设备开关视觉、声音、物理多屏仍待用户；此前已认可的下移修复本轮没有实际重锁验证，不能以本轮44项代替实机动画。未推送/提交本批、未覆盖dist或归档、未新派工或恢复定时器。当前设置停锁定屏幕供用户查看。
