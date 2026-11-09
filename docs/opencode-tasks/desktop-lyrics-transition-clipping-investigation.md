# 歌词换句：针对裁剪层差异的定向验证

用户反馈 build32 换句效果不如原版。上批已给出音符居中修复，但 SwiftUI 过渡实验未能证明正确而撤下；不要重复盲目调动画参数。保留当前源码、实验隔离与上一批音符修复；不替换运行实例。

## Codex 指定的候选根因

原版 `CompactLyricsView` 把包含 17pt 歌词内容的 `LyricsLineContent` **整体**执行 ±26pt transition，最外层以 `rowHeight`（常见 32pt，内嵌可不同）裁剪；长句内部有 17pt 水平裁剪，但随该歌词视图一起移动。

原生实验 `NativeLyricsRowView.layoutLine` 的 `clipLayer.masksToBounds=true` 且高度 `snapshot.rowHeight`（宿主传 17pt），`animateSwitch` 则移动其内部 `lineContainer`/outgoing 层，导致文字在固定的 17pt 区域内进出，与原版移动整行内容、由外层行框裁切的结构不相同。具体 SwiftUI/AppKit 父层是否还额外裁切须验证，以上是结构性原因假设，不得未经对照称已证实。

## 实施决策

0. 先修**已独立复现的空行卡死**：`IndependentLyricsEmptyTransitionTests/testEmptyLineStillAdvancesToNextLyricWithoutAnotherHostSample` 失败（日志 `/private/tmp/valora-lyrics-empty-independent.log`）。`contentWidth == 0` 时宿主移除 `NativeLyricsRowHost`，因此失去静态行边界定时器，下一句无法自行出现。必须在空歌词期间保持同一个 renderer 和边界唤醒（可用零可见宽度，但不能卸载、隐藏导致不调度或变成全速空转），音符仍按原版预期居中；下一句到点恢复文本、布局和滚动。保留测试断言，再补普通句→空行→普通句、seek 到空行、隐藏恢复和失败回退用例。不得靠提高全局采样或自动跳过空行掩盖问题。
1. 先设计可复现的单视图几何验证：分别在生产/实验行以相同 17pt 内容及 32pt（另覆盖内嵌实际行高）容器，人工设置中间偏移（如 ±5pt/±10pt），观察并断言文字可见范围、父层裁剪、横向长句裁剪，保存原始 PNG/位置数据。测试只改变隔离 fixture，不操控用户真实播放，不需要依赖离屏 CA 自动推进。
2. 若证实差异，令实验的**每个行视口（含 17pt 内部水平裁剪和 mask）随换句整体移动**；外层由实际 rowHeight 裁剪。旧行与新行各自视口移动/淡出淡入，旧行持有静态缓存、无第二个活跃 30Hz 时钟；逐字高亮和滚动仍在行视口内部。不得单纯取消水平长句裁剪导致溢出、不得改变 ±26pt/0.2s/曲线、字体/字距/歌词时间或降低帧率。短句小音符居中修复必须保留。
3. 对新旧行在固定可控进度的 0/25/50/75/100% 位置及 alpha，比较生产和实验的**裁剪和可见像素**；要同场景同尺寸、位置/时钟注入并记录测量，不可只断言动画参数或计数。真实 SwiftUI 参考动画不能可靠暂停时，报告此限制，不能声称全帧等价；先做静态几何关键帧直接对照。快速连续换句、seek、隐藏、失败回退确保旧视口释放、仅一条活动时钟。
4. 若父级 NSView/SwiftUI 桥接裁剪无法保持一致，或无法证明修改比当前更接近原版，保留证据并停止，不自行另换方向。新修改仅在实验渲染路径；普通 Release、锁屏沿用原路径。
5. 用一套可复用隔离窗口，不批量闪窗；跑音符坐标、原型生命周期、播放锚、失败回退等定向测试，保留并检查既有断言。输出 `docs/reports/desktop-lyrics-transition-clipping-investigation.md`，注明 CPU 本轮未实测、真实用户体感仍须用户确认。

不得启动/替换 App、控制真实播放、打包提交。完成后停止等 Codex 独立验收。
