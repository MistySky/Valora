# 锁屏 CPU：缓存测量与隔离进度更新

用户已授权开始。沿用现有 Pi 会话/模型/分支，保留所有未提交改动。build44 已运行；锁屏歌词沿用桌面 native 渲染方式，用户接受当前桌面体感。本批不改歌词动画。

## 证据与目标

先读 `docs/reports/lock-lyrics-resource-independent-20261109.md`、前批报告与 AGENTS.md。用户实测歌词开启锁屏稳定CPU10.72%，关闭10.42%，同轮中位均10.47%；不能再把歌词当主因。

调用栈 `/private/tmp/valora-lock44-stack-no-lyrics-20261109/locked.sample.txt`，2026-11-09 20:35:36，build44/PID36796，锁屏且用户关闭歌词，单次8秒/10ms。主线程工作出现 NSWindow/NSHostingView/SwiftUI 布局、MusicMarqueePair/MarqueeLabel.measure、NotchView/Settings 视图、媒体tick→AppModel.setElapsed、ScreenStateMonitor.refresh。阻塞read/等待样本不是CPU热点；不能按包含式样本总数相加分摊CPU。本批目标为去掉可证明的重复工作，最终降幅由Codex与用户实机验收。

## Codex 决定的实现范围

### 1. 完整输入、有上限的文字度量缓存

MarqueeLabel.measure、sizeThatFits、intrinsicContentSize 与 MusicMarqueePair.longestWidth 当前会对同一标题/歌手多次测量。让其共用 @MainActor 度量缓存，键至少包含原始文本、字号、NSFont.Weight（及实际参与测量的字距/字体环境）；结果保持现有 NSString/font/kern 测量完全一致。缓存有固定容量/淘汰，不无限增长。每次 body 内 longestWidth 只求一次。保持13.5/13号字、0.05字距、4.5余量、滚动起点/周期、长短标题对齐、颜色与点击行为；不动原生滚动动画。

### 2. 高频进度从 AppModel 整体观察中隔离

目前 @Published elapsed 每次媒体4Hz tick 都向 AppModel 全部观察者广播。采用一个独立、稳定持有的可观察播放进度对象，把 elapsed 和 sampledAt 作为同一份一致快照交付；由 MediaProgressView、CompactLyricsView、ExperimentalDesktopLyricsView 等真正读取进度的叶子订阅，普通 AppModel 观察者不再因纯进度tick刷新。保留 AppModel.elapsed / elapsedSampleDate / setElapsed / lyricsElapsed 的调用兼容入口（可代理该对象），迁移所有实际依赖，搜索生产、开发与测试用例，不能只修锁屏路径。

要求：不降低现有4Hz进度供给、不动30Hz逐字高亮/滚动及换句时长，非实验 CompactLyricsView 路径同样正确；暂停/恢复/切歌/seek/播放速率变化/歌词内容替换立即正确，不依赖下一轮tick补救。snapshot 的 elapsed 与 sampledAt 不能由两次广播产生错配。保留现有乐观seek、时间锚点及迟到回调隔离，不引入全局计时器、不每帧全局广播，不用强制整棵树重建掩盖订阅缺失。

如代码检查证明需要超出此边界的大规模改造，停下报告具体依赖，不自行换架构。不要仅把 @Published 去掉而没有替代订阅，或用随意 objectWillChange.send 让问题回到原处。

### 3. 本批只核实隐藏视图，不叠加未经证实的窗口修改

调用栈出现 NotchView/Settings 不等于已证明不可见窗口在工作。先读实际窗口可见性/订阅，报告进度隔离后哪些路径停止无效刷新；禁止直接清空窗口root、破坏设置草稿/焦点、裁剪窗口或改变Space。ScreenStateMonitor 按需调度留到这批效果验收后，本批不改。顺便修正前批 lyricsActive 在 beginUnlock 的直接 orderOut 分支漏清理，使其与实际窗口移除一致，覆盖对应生命周期即可，不改变锁解动画。

## 不可改变的体验

保留 build44 的桌面鼠标路径、刘海/歌词翻转、逐字高亮、标题滚动、播放器进度流畅度、音符/空行居中、暂停行、锁屏卡片几何/位置/玻璃/配色、点击拖动、解锁恢复。native 实验边界和 fallback 不变，不改歌词过渡容器/时长，不控制真实播放、音量、锁屏或设备，不提交推送Git。

## 验证与交付

按 AGENTS.md 跑必要定向测试，禁止压力/批量闪窗/反复锁解。新增有意义覆盖：相同度量复用/输入变化/缓存上限；纯进度更新不触发全局AppModel广播且进度订阅收到一致快照；暂停/seek/切歌及时刷新；实验和普通歌词进度订阅正确；原乐观seek/锁屏生命周期/桌面换句回归。测试不能冒称实机CPU或动画完全一致。

报告 `docs/reports/lock-refresh-scope-20261109.md`，说明修改原位置、实际效果、测试数/日志、未验项。必要验证通过后以当前实验配置交付一次 Release 候选，自动build号+1，签名/hash/清单验证，按长期授权正常退出旧版、确认零实例后启动唯一新包；无法正常退出就保留候选，不强退，不覆盖Applications。当前build44保留可回退。

完成即停并回报，Codex独立验收后安排用户真实锁屏监控，不自行继续下一批。
