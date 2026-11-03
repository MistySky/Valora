# V0038后续限定只读核查：系统锁屏过渡是否带动notch window

用户实测桌面模拟加锁与解锁都正常，真实锁屏仍异常，并提出是否跟随系统锁屏的缩放动画。该实测显著缩小范围，但preview和real是不同controller，必须先核时序差异，不能把window归因视为已确诊。

当前V0038-R1解锁补充如尚在执行，先按用户新证据避免无关重做已经正常动画；该补充单独只读研究，不修改生产、不构建/换版/调用真实SkyLight或锁屏，不恢复失败R8迁移。

核查正常notch与真正锁屏路径新增的Space membership、window collectionBehavior(.canJoinAllSpaces/.stationary/.fullScreenAuxiliary)、level、orderFront时机、系统activeSpace切换/屏幕参数/ScreenStateMonitor隐藏条件；这些是否可能让普通notch window参与桌面锁屏系统缩放/位移。必须区分AppKit model frame、SwiftUI实际layout与WindowServer最终合成变换。不能仅NSWindow.frame==顶部就排除最后一种。若只是推断明确标注。

对照外部已读固定源码BoringNotch/SkyLightWindow与DynamicNotch的持续Space归属、普通primary挂起/锁screen overlay独立承载和切换时机，查其为何不随普通桌面合成过渡（若源码不能证明则写未知）。不得因源码不同就盲改接口/猜y/加延迟。

输出简短差异和下一步最小可观测方案docs/research/desktop-preview-vs-system-lock-transition.md。保留已正常模拟动画/设置，当前用户运行V0038 f6d039...不退出不覆盖，不发真实锁通知，不真实媒体/设备/权限写、截图循环/压力/全量，不Git或定时器。报告后停止，Codex决定实际修复。
