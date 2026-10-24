# V0015：设备连接提示迁移（原版证据＋成熟复刻）

用户最新明确授权开始设备模块，覆盖此前“本轮不自动进入设备”的停止点；不是重开旧全量队列。使用现有pi会话/本Valora目录，先读AGENTS.md及本任务。歌词V0012/R1—R4、清理V0013、流畅度V0014已独立接受，保持其体验与代码，完成本批后停止由Codex独立验收。

## 产品范围

- 只接原版Connectivity/设备连接提示纵向链路，参考原版证据并直接迁入成熟复刻代码，Swift6/macOS27。不是重画简化版本，也不顺带接系统电池、日历、Focus、锁屏等模块。
- 设置新增原有风格的“设备连接”页/导航图标；只保留总开关及外观（3D模型/符号），保持通用、正在播放原UI及歌词设置不变。栏目图标/选项图标/控件间距/动画按原版Alcove和归档，不自行换设计。
- 固定低电量提醒开启、阈值20%，总开关关闭时检测、连接提示、低电量提醒/声音全部停止并取消未完成工作；不提供这些隐藏选项。旧偏好值不得偷偷覆盖固定策略。
- 显示时长固定默认；已有原版现场取证和复刻fallback均5秒，提示音现场/复刻fallback为开。先只读查原版注册/构造证据；若能证实采用原版默认，若无法证实则明确本批固定策略采用5秒、低电量默认音开启，不把现场取值冒称首次安装默认，不因此拖住可实施部分。总开关/外观默认也须区分来源与推断，未证实时保守延用复刻（总开关关闭、3D模型）。
- 支持设备种类/型号以原版与成熟复刻实际已覆盖为准，不宣称支持所有蓝牙耳机/键鼠，不新增配对、连接、音频切换按钮或设备管理功能。

## 可直接复用的来源（只读）

归档/Users/wangqing/code/alcove-revival-archive：

- Sources/AlcoveRevival/Controllers.swift中Bluetooth/连接监测控制器（约190—310行）；Models.swift的AudioDevice、Connectivity偏好及提示状态。
- Sources/NativeBridge/NativeBridge.m及include/NativeBridge.h中ARConnectedAudioDevices/CoreAudio型号映射。Valora现有音量/输出桥保持，不覆盖其已接受实现。
- Sources/ReferenceCore/ConnectivityPreferences.swift、DeviceBatteryAlert.swift、AirPodsModel.swift、AirPodsMaxColor.swift、PresentationMetrics对应connection分支。
- Sources/AlcoveRevival/ConnectionArrivalArtwork.swift、NotchView.swift的ConnectionArtwork/ConnectionBatteryRing和成熟3D电影播放器，所需Resources/airpods*.mp4及low-battery.caf；按需迁入并保留许可来源，不拷整项目资源目录。
- SettingsView.swift约290行Connectivity卡片、SettingsCatalog.swift/SettingsLocalization.swift的成熟行/图标，按用户要求只减条目。
- reference-ui/Connectivity.png；reverse-engineering/connection-appearance/核对结果.txt及同目录函数，docs/alcove-1.7.9-detail-audit/evidence/fixed-0.6.10/和原版对照证据。原版现场、反编译常量、复刻实现三者须区分。
- tests/ReferenceCoreTests/{DeviceBatteryAlertTests,ConnectionAppearanceTests}.swift及PresentationVerification中的连接场景可作回归底稿。

## 必须保留/核验的行为

- 首次快照学习基线，不把已连接设备重复当新连接；真实新连接/重连才入场。设备身份稳定，缺少ID不能每次生成随机ID导致提示风暴。型号/电量晚到只更新当前提示，不重播入场、不延长固定时长。
- 低电量边沿提醒：从阈值上方降至<=20%触发一次，恢复上方后重新武装；首次低电量快照不乱弹/响。缺失/无效电量如实未知，不伪造；核验真实0%与nil的区别，避免把0%当不存在。断连、关闭开关、重新启用的基线与提醒状态明确，不重复提示。
- 3D/符号分支、型号选择、电量环尺寸/颜色和进出动画沿用成熟来源，Reduce Motion/资产缺失有合理符号回退。3D视频图层不一定被cacheDisplay捕获，不能以空截图假称电影播放验证通过。
- 与现有音乐/歌词/展开/音量的优先级按原版提示与归档成熟路径，连接提示不叠字、不引入新横栏，结束后恢复当前音乐/歌词状态。保留用户已确认的活动屏动态归属，其他屏紧凑静态，不重新引入被动屏不可见Timeline/电影刷新。
- IOBluetooth同步调用不可在主线程。归档曾记录服务信号量卡死，不能只把查询搬后台再无限并发超时重试，须有界in-flight/资源与过期token保护；开关关闭/停止后晚结果不重新弹出，不崩溃，不阻塞音乐/歌词。Swift6隔离/Sendable保持，不全局关闭并发检查。
- 不迁入原版身份/授权/更新服务/用户偏好，不改品牌应用图标和Outline-v7菜单栏；必要共享底座最小迁移，不能覆盖已接受的歌词时钟/取消/缓存及多屏行为。

## 验证与交付

先用可注入设备源/时钟/声音spy做隔离QA，不真实配对/连接/断开设备，不改蓝牙开关/音频来源/音量，不触发或接受新权限弹窗，不写权限/登录项/系统设置。QA不真实播放提示音、不读个人设备信息用于伪造测试；生产检测为只读能力并受总开关控制。

针对性回归：首快照/新连/重连/元数据晚到、不延时重播、总开关关闭和迟到回调、20%边沿与0%/nil、声音spy、3D/符号/Reduce Motion、未知型号和资产缺失、活动屏、提示中切歌/暂停/展开/音量/歌词恢复。不要仅测常量和fake布尔值冒充实际UI。

swift test、独立候选构建签名、必要原音乐/歌词/多屏回归及新设置实际SwiftUI截图；资源打包清单和来源。真实设备/3D视频实机/物理双屏缺条件则明确待验，由用户安排，不用fake当实机通过。默认值证据写docs/research/connectivity-defaults-and-source.md；正式报告docs/reports/v0015.md及docs/verification/v0015/。

未经用户另行指示不安装发布、不Git提交推送/重置或换分支、不改原归档、不执行真实媒体/设备/系统写操作。交付后停止，不自动新增模块。定时器先前已删除，本次派工本身不擅自恢复。
