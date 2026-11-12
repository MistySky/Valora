# R3 实施设计：桌面行生命周期与原版keyed transition

R2报告已明确三个边界未完成，因此build52不接受为目标完成。用户持续授权夜间工作/5分钟跟进，并反馈当前感官不柔顺。内存优化继续等待，不交叉执行；不要仅重复R1报告后再加无功能变化的build号。

以下是Codex决定的最小表现层设计，请实施而非再次因边界尚未解开就停止。若具体实现有不可安全解决的阻碍，指出对应代码/测试，不能用参数一致取代目标。

## 1. 桌面行呈现owner

新增一个桌面专用、@MainActor的行呈现owner（可扩展现有host），持有当前行呈现ID/lineKey、最新输入与generation，及当前native view弱引用。SwiftUI HStack中的歌词child使用这个行呈现ID做.id，真实使用原版asymmetric offset±26+opacity transition，父层easeInOut0.2s；新旧各自固有/available宽度交给原版布局过渡，不再用incomingOffset/outgoingOffset动画模拟。

lineKey沿用build26的start+text语义；同identity只替换word timing/revision应更新输入，不平白启动换句。若需要避免快速seek回上一行时复用已退役视图，可将呈现代次附于child ID（保持每次真实lineKey变化才增加）。

## 2. 在旧native改变显示前截断handoff

当前NativeLyricsRowView.update检测nextLine后立即switchLine/build新图，再向host回调，太晚了。对**桌面keyed策略**增加一个主actor可选line-change handoff入口，在当前视图已初始化、且下一lineKey改变时，于改写旧行图层之前通知owner并返回handled。

- 此刻把旧行定格在原有图层/图片、当前高亮和横向offset；解除它的连续clock/boundary wake，标记为只读退场行（retired/frozen）。
- retired视图后续任何旧SwiftUI update/apply都不能重新注册clock或选成新行；判断由owner当前呈现代次/retired标志控制，不依赖SwiftUI在退场时一定调用onDisappear。
- 一个主队列handoff发布owner新行ID/模型，让SwiftUI在同一个原版transition中移除旧child、插入新child。不得加固定16ms延迟/拆成两次offset动画。
- 新native child初次apply直接显示所绑定的当前新行，并注册唯一continuous clock；初挂不能再次触发相同handoff。其后锚点/暂停/速率/内容替换仍来自最新snapshot。
- 旧child可作为冻结的native图层视图退场，不必强行换成另一个static view；关键是它不再参与clock/line选择、不再被同曲输入唤醒。退场结束释放；stale completion只影响对应代次。

## 3. 图片准备资源复用

不能每切一行就新建一套离屏NSWindow/NSHostingView导致性能倒退。将现有文字截图准备设施提取为一个可共享、main actor的准备对象，由桌面行owner稳定持有，交给新行用；生成的两张CGImage/metrics是不可变结果，新旧行各自引用相应结果，不复制像素。每真实换句只准备新行一次，退场旧行0次。owner不可强持native view循环引用。

若更小改法是把“prepare images”与“apply images到本行layer”拆开、让owner在handoff前取得新行资源，也可：旧层必须保持旧图直到退场完成，新child复用准备结果，capture宿主不能随每个旧child销毁/重建。锁屏保留现有独立宿主/legacy策略，不借此共享改锁屏行为。

## 4. 所有生命周期

空行/尚无行仍需一个轻量当前行owner/边界唤醒，能自动进入下一句；不能重现必须点击才能恢复。暂停/seek/快速切歌/内容替换/隐藏返回都要使正确当前呈现立即更新，旧view/旧回调不能清新view；restore和失败fallback仍工作。只允许一个实时30Hz消费者，退场0个clock。用有限离屏回归证明；不碰真实播放/锁屏。

保持桌面缓存高亮30Hz/进度隔离、波形恢复；锁屏typed legacy策略、总歌词/锁屏独立开关和44pt位置保持。不要改封面/字体/动画风格或进入内存优化。

## 5. 证据/交付

以发布源码baseline外壳做真实SwiftUI过渡对照，短短/短长/长短有限中间帧，保存图并报告实际时间，不用debug手动推进或只断言终点。补活跃/退场clock、共享准备宿主次数、同输入去重和回调失效回归。若图像有时差/字体误差说明，不承诺与真实build26二进制像素绝对一致，但原版机制和连续性必须真实恢复。

完成实现和必要验证后才生成一次有实质修改的候选，按AGENTS签名/hash/正常退出→零实例→唯一新版，默认无诊断，保留build49/52回退。不做空候选，不强退/覆盖Applications。更新report R3并停止等Codex。Codex在当前任务内每5分钟检查。
