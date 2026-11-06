# V0036：按原版与成熟复刻迁入用户取舍后的锁屏功能

用户已明确授权开始并交给当前pi。最新要求：“看源码，看复刻品很多东西都有实现了，不要猜”。先完整读AGENTS最新覆盖及本任务；这是现有复刻的Swift6/macOS27迁移，不是重做锁屏设计。

## 0 当前阶段与前提

用户实测R3耳机“这版看上去像了”，随后明确开始锁屏取舍并授权落地，覆盖此前“耳机完整验收前不进入锁屏”的阶段阻塞；这不等于R3物理佩戴传感器或全机型全部验收通过。保留R3已用active-route行为、权限/电量/native回调修复，不借本轮回退或扩改耳机逻辑。
当前运行 `/private/tmp/valora-v0035-r3-wear-candidate/Valora.app`，不得退出/覆盖/重签或并开另一生产实例，不覆盖dist；候选单独打包。定时器保持关闭。

## 1 先读已有实现再改，逐项列迁移来源

归档 `/Users/wangqing/code/alcove-revival-archive` 严格只读。必须实际读取：
- `Sources/AlcoveRevival/LockMusicCoordinator.swift`：锁屏/解锁、睡眠唤醒、窗口、声音、信息源与取消清理，注意其混入电池/专注/keepAwake等本轮不要的功能。
- `LockFrostedBackground.swift`：已有NSVisualEffectView .hudWindow/.behindWindow/.active/emphasized/continuous clipping，不要改成自创渐变或笼统ultraThinMaterial。
- `LockInformationView.swift`、`MusicPlayerContent.swift`、`OutputVolumeView.swift`：选择性保留本轮音乐与耳机纵向链路及原UI。
- `Sources/ReferenceCore/LockMusicState.swift`、`LockIndicatorState.swift`。
- `NotchView.swift`中的LockActivityGlyph、`WindowCoordinator.swift`及模型接线。
- `Sources/NativeBridge/NativeBridge.m`/include中的ARLockPresentationSpace完整实现与所有权清理。
- `Sources/AlcoveRevival/Resources/lock.caf`、`unlock.caf`及来源/许可记录。
- 原版`reverse-engineering/lock-screen-music/`、`lock-appearance-0.6.5/`的函数、依据与边界、Space挂载链；`docs/alcove-1.7.9-detail-audit/lock-screen-original-defaults.json`和对应initializer证据。

重要纠错：复刻当前代码**已有**LockIndicatorState hidden/locked/unlocking和LockActivityGlyph锁片旋转(-24度)/上移(x2,y-2)、spring .45 bounce .2；不能照抄旧审计“只有静态锁图标未实现动画”的过期描述。已有实现不等于这些常数已证明原版精确值。先按当前成熟源码保留结构，核原版差异，不把猜测改成证据。
源文件/旧报告冲突以读过的当前源码及具体原版函数区分；报告附“来源路径→Valora迁入文件→必要Swift6适配→已知边界”表。禁止先自创简版后再声称复刻。

## 2 用户确认的产品范围

保留实际功能及简洁设置：
1. 锁屏总开关，默认on。其off必须停止所属监听/任务/声音、移除挂载和窗口，拒绝迟到回调，不能只是视觉隐藏。不得停止正常音乐/耳机/日历/监控。
2. 刘海顶部锁定/解锁状态及动画，随真实session状态变化；锁定时按来源让位锁标志/限制交互，解锁动画后恢复现有正常内容。由总开关控制，不另加动画开关。快速锁解、睡眠/关闭、旧animation completion都需generation安全。
3. 锁定提示音、解锁提示音，两个简洁设置开关，原资源；暂沿原版注册默认锁定off/解锁on（用户确认保留功能，未要求两者默认都开）。仅真实状态边沿按设置播放一次，启动读取当前已锁状态不能误响，off/退出/取消正确停音。测试注入sound spy，禁止实际播放提示音。
4. 锁屏音乐功能开关默认on。复用当前成熟MusicPlayerContent/真实同源媒体控制，不恢复已删除模式或波形设置，不重复启动MediaRemote/歌词源。锁屏玻璃卡UI/布局/材质/动画沿来源。
5. 锁屏设备/耳机信息开关默认on，复用现有设备快照，不新建另一套Bluetooth查询或触发权限；未知电量不伪造，保留同设备型号稳定性。小组件与瞬时通知是原版不同能力：本轮现有设备通知在锁屏按原版/已实现链路允许、受锁屏总开关及设备总开关约束，不额外添加一堆Allowed Notifications设置。若来源存在冲突，报告具体行为，不凭想象叠两份通知。

固定策略（不放设置）：
- keepAwake=0：不接入非零保持唤醒功能，不创建IOPM防睡眠assertion；不携带KeepAwakeController无用依赖。
- 屏保时显示=false：只在真实锁定状态显示，不在单纯屏保状态显示，不接屏保检测后台。
- 音乐固定Glass；不接Clear透明选择/专用分支。macOS27不等于自动用NSGlassEffectView，按已取证frosted分支迁NSVisualEffectView。
- 空闲隐藏固定10分钟，单位分钟，不和刘海3秒混用，沿源音乐状态机，0偏移固定，不放滑块。
- 音量条默认收起，保留播放器现有点击输出图标展开/收起与真实可控性门控，不加“显示音量控制”设置。本设置false不能误解释为禁用点击调音量。真实锁屏控制是否有效列待用户实测，禁止主动调音量。

用户明确不要的是**整个功能不要**：锁屏电脑电池、专注、日历、天气及其通知/采样/provider/资源/设置。不能把整套旧信息面板迁进来只隐藏开关；但勿删除Valora现有菜单栏日历/系统监控（它们不属于锁屏）。不迁入亮度/声音键HUD等旧全量功能。
不借本轮新增锁屏歌词样式或设计，既有刘海歌词不变。

## 3 锁屏真实显示与系统边界

迁入成熟owned presentation Space路径及销毁闭环，原版Space类型1/absolutelevel400证据见Space挂载链；不要只orderFront/提高NSWindow.level就称锁屏可见，不增加重复置顶timer。只管理本进程所建Space和窗口，缺私有符号时安全收起并报告，不改别的进程/桌面/认证/系统保护。
保持非激活面板、避让时钟头像及来源布局；不同屏幕/模拟刘海/无实体刘海沿当前几何与用户显示选择，不破坏多屏单活动屏原则。原版账户/头像位置分支未完整恢复需明确限制，不读用户账户资料补猜布局。
Swift6只改确有需要的actor隔离/可发送快照/回调/所有权/取消；系统ObjC通知不能再次直接落@MainActor入口造成native coordinatorQueue崩溃。不全局放宽并发检查。关闭→重开不重复窗口/订阅或恢复旧请求。

## 4 验证约束

只做受影响模块/必要相邻接口的定向无界面测试，不机械全量。按源码迁来的状态机补锁→解锁→完成、快速反转、off/sleep/stop晚回调、音乐暂停10分钟deadline、耳机信息开关与缺失数据、无电池等不要模块源、音量默认收起可点击路由、声音边沿spy等有意义回归；时间注入，不真实等待10分钟。
必须注入系统锁状态/声音/窗口或Space适配等测试替身，不创建真实锁屏Space/真实锁屏界面来跑fake测试，不用桌面普通窗口截图冒充登录窗口通过。
禁止真实锁屏/解锁、发送锁屏命令/真实通知来模拟、播放控制/音量写、蓝牙操作/新授权/系统设置登录项写/个人日历账号读取；实际锁屏最后由用户选择时机操作，远程期间不替用户锁电脑。
继续禁止所有--verify-*、反复菜单/窗口开关、批量截图、CPU/RSS/帧率/压力测试。不要以“功能测试”名义恢复闪窗。只一次必要release构建/签名/资源闭环核验，候选 `/private/tmp/valora-v0036-lock-screen-candidate`；不自动运行它。
不改归档/模型历史，不Git提交推送，不安装发布，不恢复下载/Codex/定时器，不全局重构拆包。

## 5 交付

`docs/reports/v0036-lock-screen-selected-migration.md`，迁移映射表、原版证据/复刻实现/剩余未知分别列明，说明每项用户取舍真实生效及未迁入无用后端。提供源码/资源哈希、定向测试日志与清单、build/签名、候选目录、必要实机待验。原版动画尚不能精确证实的参数标为复刻既有值，不猜常数或宣称1:1。用户后续看候选不等于验收通过，完成后停等Codex独立验收，不自动下一任务。
