# 媒体通知与窗口更新去重

## 范围与约束

用户授权 Codex 在 codex/resource-idle-render-dedup 直接实施并实测，不交 Pi。基线为上一轮 build66；其 NativeLyricsRow 空事务优化保留，本笔未追加歌词渲染改动。用户同意保持播放歌词、不操作，并启动独立候选测量。没有覆盖 Brew/Applications、提交、推送或发布。

## 生产改动

- Controllers.applySystem：13个显示/能力/来源字段仅在值改变时写入 @Published。比较当前 model，而非只比较上一份系统快照，确保乐观播放/暂停反馈仍会被系统权威状态纠正。完整时间锚、seek确认、封面处理、同步歌词更新、song peek/多屏路由保持原顺序，不整包丢弃进度事件。
- WindowCoordinator：刘海窗口frame、hover sensor frame与sharingType相等时不重复设置。EdgeHostingView保留几何相同且仍实际注册的tracking area；尺寸变化、外部移除或重新挂载后仍能重建；无有效尺寸时移除并清空引用。
- LockMusicCoordinator.place：几何相同不再发布lockNotchGeometry；卡片实际位置与目标相同时不重复setFrameOrigin。以实时窗口frame判断，外部/Space移动后的偏移仍会修正，无永久目标位置缓存。

保留：窗口orderFront/orderOut、ignoresMouseEvents及其退出兜底、Space迁移、调度顺序、所有动画/转场/帧率/歌词图像准备。没有合并或延迟真实状态变更事件，没有新增常驻计时器或图像缓存。

## 测试证据

新增6个针对性用例（新MediaNotificationDedupTests 4个，现有LockMusicCoordinatorTests追加2个）。先对旧生产代码运行：6项、4条预期失败，分别捕获一次纯进度事件的13次不变字段发布、重复锁屏几何发布、重复卡位置写入、重复tracking area替换。权威状态纠正、真变化/seek位置与外部位置漂移用例原本即可通过。

改后定向回归：ValoraTests 84项、ReferenceCoreTests 6项，总计90项通过、0失败。覆盖媒体生命周期/重连/乐观播放反馈、seek、暂停与进度锚、锁屏生命周期/选屏、点击穿透/退出兜底、固定外轮廓。测试没有自动控制真实播放；窗口事件测试不等于真实WindowServer鼠标送达或用户流畅度验收。

日志：

- /private/tmp/valora-media-dedup-before-tests.log
- /private/tmp/valora-media-dedup-after-tests.log

git diff --check通过。本次新增测试通过后未扩大到全量/压力测试。

## 候选

- 1.0.6 / build67，仅本地测试候选。
- /private/tmp/valora-media-window-dedup-20261112/Valora.app
- 显式VALORA_LYRICS_EXPERIMENT=1，与build66一致；沿用Valora Self-Signed。
- binary SHA256：2876d27ee08a8c7a582fa3edbbf00d1d4cf87849fcd72ddb94706b9106bff919。
- 打包元数据摘要与实际二进制一致；主机环境codesign --verify --strict --deep成功。沙箱内首次独立验证出现CSSMERR_TP_NOT_TRUSTED，移到可读取本机信任链的主机环境复核通过；没有修改证书/信任配置。
- 正常退出已核对路径的build66/PID41443，确认0实例后启动build67/PID47652；确认仅1实例且路径对应本笔候选。
- 构建日志/private/tmp/valora-media-window-dedup-build.log；完整元数据同产物目录build-verification.json。

## 实测方法与基线

CPU以进程累计CPU时间差/墙钟时间计算，40秒窗口每2秒读一次ps。不并行构建、测试或采样调用栈。RSS仅辅助，不将其冒称physical footprint。只读媒体get在CPU窗口前后执行，记录曲目身份hash，不能用相同曲目身份冒称相同歌词片段。

build66：用户确认播放歌词、不操作后的40.28秒窗口平均CPU6.75%；构建完成后、替换前另40.25秒窗口5.47%，后者前后曲目身份相同且playing=true。说明现状本身有波动，不能用一次高值与新版本低值直接宣称固定降幅。先前用户确认前的30秒4.97%只保留观察，不充当受控基线。

原始数据：/private/tmp/valora-media-dedup-before-confirmed.json、/private/tmp/valora-media-dedup-before-final.json。一次独立vmmap记录build66 physical footprint35.6M、peak36.8M（与RSS不同口径，且不是相同使用历史的内存A/B）。

候选播放首段：启动后留出稳定时间，40.28秒平均CPU4.82%，RSS89.05–92.27MiB。窗口前后playing=true，但完整媒体身份hash发生变化，且与旧版窗口hash不同，因此不能将5.47%→4.82%宣称受控降幅，亦不能据此保证播放达到1%。原始数据/private/tmp/valora-media-dedup-after-playing.json。

CPU采样后单独vmmap：候选physical footprint33.4M，peak34.4M。旧版35.6M与之不是相同运行时长/使用历史，不能据此宣称内存优化了2.2M。本笔没有改缓存策略。

用户随后明确回复“已暂停，动画和交互正常”，确认候选日常歌词衔接与鼠标进出体验。暂停后40.26秒平均CPU1.12%，RSS97.94–98.27MiB；采样前后playing=false、同一媒体身份，确认停止播放后回落。数据/private/tmp/valora-media-dedup-after-paused.json。

用户随后自行关闭音乐总开关，defaults read com.wangqing.valora enableNowPlaying返回0。关闭态测量不再调用媒体get，不自动恢复用户设置。本次未要求真实锁屏，隔离锁屏回归不能冒称实机锁屏通过。

关闭音乐后40.27秒平均CPU1.14%，RSS125.81–126.06MiB。随后独立vmmap physical footprint44.8M、peak45.4M；期间用户打开过设置，不能与刚启动后的33.4M直接对比为泄漏或优化退化。进程检查仅PID47652，未发现其媒体适配子进程，确认总开关并非只隐藏画面。原始数据/private/tmp/valora-media-dedup-after-disabled.json、/private/tmp/valora-media-dedup-final-memory.txt。

## 本轮结论

重复字段发布与相同几何写入已用先失败后通过的回归证实消除；所有90项定向测试通过，用户确认动画和鼠标交互正常。实际播放首段4.82%，暂停与总开关关闭均约1.1%，回落正常。播放比旧版两段5.47%/6.75%读数低，但歌词片段/媒体身份不一致，不宣称固定CPU降幅或已经达到播放1%的目标。

保留本笔有限去重，不扩大到歌词布局、时钟、轮询或缓存改造。候选build67保持唯一运行实例；音乐总开关保持用户最后选择的关闭状态。本轮未提交、推送、合并或发布，Brew安装未覆盖。

## 后续异常：音乐关闭仍出现高段

用户随后报告空界面CPU升至16%。现场ps实读17.0%，PID47652/build67，enableNowPlaying=0；未重启或改代码。随后30.18秒记录均值5.67%，前段回落，后10秒累计CPU差分约10–14%，ps最高20.6%，说明并非只可忽略的单点显示。该观察邻近8秒sample探针，不能当干净基线。

首次sample主线程大部分等待，业务栈中有屏幕/音频轮询，无歌词或queuePointerUpdate/trackMouse热点；另一个AppKit NSEventThread显著出现WindowServer事件接收、解码路径。采样权重不是CPU百分比，且尚未与用户主动鼠标动作同步，不能直接断定鼠标或某个监听为根因。第二次sample启动时CPU已1.0%，事件线程基本等待；后续约30秒观察ps0.3–1.9%，未触发>=8%的额外抓栈。

核对Git：当前HEAD=f6666aa9db12cf90d9e5e0ea643b2b7c78a8b684，分支codex/resource-idle-render-dedup从1.0.6发布点创建，包含3b4dc91鼠标轮询移除与c1009dc点击穿透修复，并非从旧main重建。c1009dc为修复退出丢失事件增加了悬浮期间启用的local/global mouse monitor，退出调用removeMonitor；本笔没有新增这组monitor，但更改了tracking area相同几何复用，需要一并核验。监听移除后事件层是否仍有接收开销是待验证假设，不是已证实的系统行为。

前述约1.1%仅代表已采的静止窗口，不能扩展为鼠标活动路径也已通过。已请求用户保持音乐关闭、远离刘海晃鼠标以同步抓取，尚未收到该次动作确认。相关文件：/private/tmp/valora-build67-idle-spike.sample.txt、/private/tmp/valora-build67-idle-spike.json、/private/tmp/valora-build67-idle-spike-second.sample.txt、/private/tmp/valora-build67-event-spike-watch.json。

### 用户配合鼠标动作后的证据

用户随后明确“可以，现在开始晃动”。同一PID47652/build67、音乐总开关关闭，启动读取即ps17.7%。连续20.16秒累计CPU均值18.45%，ps12.1–21.1%；其中前15秒包含sample探针，因此18.45%不是无探针基准值。

sample中AppKit NSEventThread明显集中于MessageHandler → PullEventsFromWindowServerOnConnection → CGSDecodeEventRecord/事件解码。queuePointerUpdate、NativeLyricsRow、updateTrackingAreas、updateVisibility、SLSSetWindowEventMask均未采到；trackMouse仅1个采样权重，通过tracking-area退出事件进入。权重不是调用次数，也不能由零采样断言回调绝对未执行。

提示用户停止晃动后，另采20.14秒（不带sample）平均CPU1.19%。该次动作关联以及此前无探针现场17%支持鼠标活动触发高开销；剩余工作应定位事件订阅/窗口事件接收生命周期，不能继续把问题归因于歌词渲染。尚未证明global monitor移除后残留是唯一根因，也未证明本笔tracking area复用造成或未造成该问题。

本次仅只读采样与代码核对，没有生产修改、重启或替换。证据：/private/tmp/valora-build67-mouse-confirmed.json、/private/tmp/valora-build67-mouse-confirmed.sample.txt、/private/tmp/valora-build67-mouse-stop.json。

### 无窗口监听对照：结果无效

用户再次同意晃鼠标后，执行三个独立无窗口AppKit诊断进程：none从不注册，removed启动后0.5秒移除global monitor，active保持global monitor。均30秒自动退出，测量窗口20.36秒；三者累计CPU差分均为0.00秒、回调数均0，连active正对照也未收到事件。

因此本次实验无效，不能证明removeMonitor消除了或残留了事件接收开销；也不能据此归因于具体权限或AppKit行为。诊断环境没有确认与真实应用具有同样的事件交付条件，用户动作与实际采集起止也存在工具启动延迟。未向系统注入鼠标事件、未更改权限、未改生产代码或重启Valora。

工具源码/private/tmp/valora-hover-monitor-probe.swift，结果/private/tmp/valora-hover-monitor-comparison/result.json。下一次应以能实际接收鼠标事件的应用运行环境作对照，同时记录Valora作为阳性参照，不能继续拿零回调结果支持监听残留假设。此前悬浮期间位置检查替代全局监听仍只是待验证方案，须通过真实候选的资源与点击穿透/拖动/动画验收。
