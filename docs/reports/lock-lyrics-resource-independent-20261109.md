# build44 锁屏歌词独立验收

2026-11-09，用户自行锁屏/解锁，Codex 仅监控，未控制播放、音量或系统锁定。当前唯一实际应用进程 PID36796，候选 `/private/tmp/valora-lock-lyrics-resource-20261109/Valora.app`，build44；strict/deep 签名通过，二进制 SHA256 与 Pi 报告一致（a41f9f674da147570caa14bd9eb6f1647674505ec31a713e4427d4ec1a6ae9ea）。

## 代码与测试

锁屏通过显式 active 接入现有 native 实验歌词底层，不再以桌面 notchSurfaceOnScreen 决定锁屏时钟。正常 Release 仍为旧路径。本次独立运行 `VALORA_LYRICS_EXPERIMENT=1 swift test --filter 'LockMusicCoordinatorTests|IndependentLyricsTransitionClockTests|IndependentLyricsEmptyTransitionTests'`：43 项通过，0 失败。日志 `/private/tmp/valora-lock-lyrics-independent-20261109.log`。不能据此认定动画完全一致或锁屏性能通过。

注意：lyricsActive 的清理并未覆盖所有直接 orderOut 分支（例如 beginUnlock）。视图移除的 onDisappear 另有清理，因此不能仅由此断言时钟泄漏；后续应把状态含义与实际窗口生命周期统一并补对应覆盖。

## 实机采样

原始 `/private/tmp/valora-lock44-monitor-20261109.jsonl`，每2秒由进程累计 CPU 时间差计算 CPU 百分比（100%为一核心），RSS 内存；IORegistry 标记系统锁定状态。未记录实际歌词行、播放状态与卡片是否显示，不能据该日志单独证明歌词是开销根因。

- 全段20:23:28—20:27:28（北京时间），121个采样点。
- 未锁屏20:23:28—20:25:16：54个有效CPU区间，均值2.04%，中位1.50%，峰值23.91%（临近锁屏）；RSS71.48—88.03MiB。此阶段音乐/鼠标状态不完全一致，不能作为严格对照。
- 锁屏20:25:18—20:27:28：66个有效CPU区间，均值10.83%，中位10.47%，范围7.49—21.99%；去掉初始10秒后均值10.72%；RSS93.09—103.84MiB。
- 采样结束时仍锁屏，因此原始四分钟监控未覆盖解锁瞬间。用户通知结束后20:29:08起补采12秒，系统已解锁，CPU约1—2.5%，RSS约107MiB；并非刚解锁峰值。

## 判断

构建身份和定向测试通过，但当前锁屏持续约10—11% CPU，资源优化效果不能验收通过。缺少同条件旧版基线，不能断言完全无收益；未抓取锁屏期间调用栈，不能认定剩余开销全部来自歌词。内存没有长期证据证明泄漏。下一步应在同曲播放、锁屏卡可见条件下抓取调用栈并比较歌词开/关，先确认 native 实际运行还是 fallback，以及主线程渲染、布局、媒体或其他定时器占比，再定向修复。用户尚未反馈本轮真实动画观感。


## 用户关闭歌词后的对照采样

用户报告先关闭歌词，再自行锁屏；Codex 未操作开关或媒体。本轮原始记录 `/private/tmp/valora-lock44-no-lyrics-20261109.jsonl`。锁屏段20:30:40—20:33:43（北京时间），92个2秒区间：CPU均值10.54%，中位10.47%，范围6.50—25.93%，去掉初始10秒均值10.42%。RSS145.91—146.84MiB，本轮锁屏段基本稳定。解锁后前14秒包含26.43%的过渡峰值，随后降至约1.5—3.5%。

与歌词开启轮均值10.83%/稳定10.72%对照，关闭歌词后仅低0.29/0.30个百分点，中位数相同。该短时顺序对照没有证明严格等效（未记录两轮曲目/播放进度，开关状态依据用户操作），但明显不支持“歌词是目前约10%锁屏CPU的主要来源”。下一步应先抓锁屏主进程调用栈，确认播放器/波形/玻璃/布局更新与实际定时器热路径，再决定实现；不能继续只改歌词动画。两轮RSS起点不同，不能把差值当歌词内存成本或泄漏证据。


## 关闭歌词锁屏调用栈

用户再次锁屏，歌词保持关闭。20:35:36（北京时间）对 build44/PID36796 单次 sample 8秒、10ms间隔成功。原始目录 `/private/tmp/valora-lock44-stack-no-lyrics-20261109/`。监控仍显示锁屏CPU约10%；采样工具自身会扰动性能，不把抓栈期间数字当精确基线。

栈中主线程的工作包含 NSWindow layoutIfNeeded → NSHostingView.layout → SwiftUI/AttributeGraph 渲染/布局；MusicMarqueePair/MarqueeLabel.measure 多处文字测量；NotchView、MediaProgressView、SettingsToggleRow/SettingsChoices 视图更新；MediaController 的 TimerMediaTickScheduler → setElapsed；ScreenStateMonitor.refresh 窗口/应用状态检测。SystemMediaSource.start 的625个样本落在阻塞 read，不是625个CPU热点，不能据总样本数把媒体读取误判成CPU主因。当前记录未显示歌词渲染主导，也不足以证明波形或玻璃是主因。

源码印证 MusicMarqueePair.longestWidth 在 body 中被两次访问，每次测量标题与歌手；MarqueeLabel.sizeThatFits/intrinsicContentSize 还各自测量。可用按文本、字号、字重等完整输入缓存减少重复测量，保持字体、宽度及滚动周期。AppModel elapsedSampleDate/elapsed 发布及屏幕监测需进一步检查传播范围；栈出现桌面与设置页不等于已证明窗口不可见，需先核实窗口实际可见性和订阅来源，再针对隐藏视图隔离更新。禁止直接降低可见进度/动画帧率、删除功能或归咎歌词。
