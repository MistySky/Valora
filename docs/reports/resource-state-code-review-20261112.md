# 资源开销按状态审查：Codex直接负责

## 本轮约束

用户明确本任务由Codex直接分析/执行，不派给Pi。当前仅代码分析，不实施生产变更。首要约束：使用感受、交互响应、动画曲线/时长/触发/衔接/流畅度与刘海外轮廓保持当前认可行为。不得靠降帧、停止可见效果、延迟响应或删功能降低资源数字。本地由Brew管理，不自动替换/重启。

## 状态划分

- A 音乐总开关关闭，界面无操作：媒体服务停止；已开启的菜单栏监控、设备、锁屏功能仍有各自职责。
- B 音乐功能开启但无播放源，界面无操作：需要保留发现播放的能力，与A不同。
- C 有歌曲但暂停，不点击：保留封面/歌词和立即恢复能力，不需要持续逐字高亮。
- D 播放且不点击：歌词短句无逐字、逐字高亮、长句滚动三种子状态应分开测；不能把1%多、3%多与8%混作同条件结果。
- E 切歌、换句、展开/收起、设置/日历点击：允许短峰值，但动画/请求结束后应回到对应A/B/C/D稳态；记录结束后5/15/30秒，仅用于评估回落而不是增加任何功能延迟。

## 当前代码实际行为

### 已有正确边界，优先保留

Controllers.swift:128：总开关关闭stopTick + invalidate + clearMedia；invalidate停止SystemMediaSource并清systemSnapshot/previousSystemArtwork。
Controllers.swift:142：音乐开启时0.25秒tick；暂停只在进度变化时发布；播放收起态1Hz发布进度锚、展开/锁屏进度可见态4Hz。不能直接降低该频率，需保留seek、播放恢复与进度条语义。
NativeLyricsRow.swift:978：逐字或超宽长句播放用共享30Hz；其余用边界唤醒，暂停不需要连续帧。
CompactPlaybackControl.swift:289：律动只有窗口可见、播放、未挂起且非Reduce Motion才注册；不可见后下个tick也能退出。
WindowCoordinator.swift：鼠标退出兜底仅pointerInside时注册，移出撤销；不恢复常驻桌面鼠标高频处理。
SystemMonitor.swift:110：3秒采样由模块开关控制，面板关闭不等于模块关闭（菜单栏CPU/MEM仍要显示）。
ConnectivityController.swift：开启时3秒轮询和系统事件；关闭停止。
MenuBarModuleController.swift：日历按menuBarText变化去重绘图，非逐帧日期绘制；1.0.6的显式可见性恢复没有新增周期任务。

### A/B/C静置仍存在的工作

ScreenStateMonitor.swift:70/87：每0.75秒枚举可见窗口并查询Space；Models.swift:72/73的全屏/Mission Control隐藏默认true。不能简单按未播放就停止检测，否则破坏隐藏行为。workspace通知当前部分注册在NotificationCenter.default，而非NSWorkspace.shared.notificationCenter；后续事件驱动方案必须核实通知来源，不能直接删轮询兜底。
AudioOutputController.swift:75：启动后每0.5秒读取完整ARAudioOutputSnapshot，即使音乐总开关关闭。是否能只读变化/按需求运行，需要覆盖锁屏音量、输出切换、音量HUD与首次展开；不是简单暂停就停。
Controllers.swift：B/C中0.25秒tick仍在运行，虽然暂停进度已去重，但tick计算/1Hz refresh检查仍发生。媒体事件发现/重连和seek期限须保留，优先级低于已采到的渲染开销。

## 优先CPU候选：内部去重，保留画面与时序

1. NativeLyricsRowView.draw（NativeLyricsRow.swift:476）：mask/offset赋值有去重，但CATransaction.begin/commit每次无条件执行。先求出完整目标状态；只有fill、position、opacity等全部相等才跳过事务。参数变化保持同一tick更新，不改变30Hz与过渡。
2. layoutLine（约797）/layout（约823）：每次布局写入多层frame/bounds/position，然后update再次draw。应核查并合并相同目标状态的写入，但不能用不完整尺寸key忽略换句、scale、文字尺寸、mask/offset、重新挂载等失效情况。
3. update（约426）：每帧查询下一句边界并重新注册同一个共享clock。lineEnd可随timeline/当前行/duration变化失效缓存；时钟注册可在注册状态变化时才写。此项主要减重复CPU/小对象分配，不预先承诺明显百分比。
4. 换句：LyricsRowExperiment.keyedRow以presentationID创建新视图；makeNSView apply后NativeLyricsTextPreparer.prepare测量并生成灰色/高亮两张图。高负载sample确实走此路径。保留keyed转场；只有证明同一完整输入被重复prepare时才考虑复用。缓存必须有条目/字节上限与owner生命周期，不能为CPU创建无界内存缓存。
5. 屏幕/音频轮询另立批次，在保持功能时效的前提下研究事件触发和重复数据去重。其变更影响范围比歌词内部空事务大，排后。

注意：空CATransaction也可能被Core Animation自身合并，所以源码冗余不等于确定的大幅CPU收益。需要真实A/B结果决定是否保留改动。

## 内存：已知与待证实

已有：SystemMediaSource每次读流包在autoreleasepool中，缓冲有上限；此前积压已单独修复。LyricsCache上限50条、5MiB原始payload、50MiB磁盘；5MiB不等于含Swift对象开销的总RSS。封面解码有尺寸限制，ArtworkTransitionController只保留current/target/queued并在过渡完成prune。歌词owner invalidate会关闭离屏准备窗口；旧行retire停止时钟，冻结过渡图在过渡流程清理。

待查的有限驻留：NativeLyricsRowView.stop清layer.contents但没有同时nil preparedBaseImage/preparedAccentImage；若视图仍被持有，会留住最后图片。必须先确认真实持有链和后续恢复是否依赖这些引用，不能直接叫泄漏。MenuBarModuleController.popoverDidClose停面板采样需求，但保留contentViewController；settingsWindow也有意复用。这些可解释用后内存高于冷启动，却不证明增长无界。释放可能换来下次打开重建/卡顿，优先级低。

不以强迫回到冷启动30MiB为目标；看同状态稳定平台、交互后的回落和多轮有限交互后是否累积。内存用physical footprint为主，RSS只作辅助，不能混用两个口径宣称改善。

## 验收顺序（未来实现时）

1. 在同一版本/歌曲/歌词段、显示器scale、模块设置、界面状态记录各稳态；CPU以累计进程CPU时间差/墙钟时间计算，调用栈另采，避免把sample重叠段当无探针基线。
2. 每批只做一类内部去重，现有动画常量、keyed身份、层级、边界唤醒与真实进度锚都保持。
3. 定向回归：短/长/空行、逐字、暂停恢复、seek、切歌、隐藏返回、换屏scale、展开收起；同输入图像与关键时刻mask/offset/frame一致，并用真实体验确认衔接。
4. 交互峰值允许；结束后连续帧/任务数必须恢复原状态，内存不持续累积。只接受实际CPU下降且内存/首次响应/动画没有变差的结果。
5. 用户仅要求先分析，本轮未跑新功能测试、未修改生产源码、未启动Pi、未构建或替换。

## 现有数据的限度

1.0.6近期播放采样24.11秒累计CPU0.97秒，约4.02%；之前高段更多换句视图/文字图片布局栈。未做同一首歌同片段的旧版A/B，不能宣称已证明版本退化或给出可靠优化后目标。各A/B/C状态当前没有受控新实测，代码预期不能冒称实测结论。
