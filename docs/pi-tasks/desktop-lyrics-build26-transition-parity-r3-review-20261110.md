# R3源码复核补充：双旧行与错误资源复用

Codex在R3执行期间只读复核发现以下具体问题；收到此补充后优先修正，不开始封面内存任务。若R3最终代码已处理，对照报告证据即可，不做空构建。

## 1. 两个退场旧句风险

keyedRow当前同时放 FrozenLyricsImageView(outgoing) 并给其removal transition，又对 nativeRow.id(presentationID) 加removal transition。handoffToNextLine调用retireForTransition只停clock/回调，没有隐藏旧native图层；因此SwiftUI可能保留仍绘有旧句的native child退场，同时冻结图又退场，重复画两份旧句。这与中段墨迹过多（R3KEY .10约5166—5477，而原baseline4032）吻合，但具体像素受时差影响，不能仅凭数字下结论。

决定：仅保留一条旧行退场路径。优先旧native child自身作为retired冻结行参与真实transition，不另外叠加FrozenLyricsImageView；它保有当下mask/offset，不再clock，完全符合R3设计第2节。若必须纯图片旧行，就必须确保旧native removal不再可见，且不会为了替换内部view多出默认淡入淡出。有限中段测试同时检查可见旧句份数，不只活跃clock数。

## 2. 新的全局图片缓存不等于共享截图宿主

NativeLyricsImageCache为static全应用64项，保存每句两张CGImage；buildTextImages cache miss仍调用每个新NativeLyricsRowView自己的prepareTextHostWindow，独有新歌词每句仍新建NSWindow/NSHostingView。缓存只对重复文本命中，不能解决R3要求的宿主稳定复用。64项也只限数量，不限图片字节，会把歌词序列的位图长期留全局；用户下一步正要内存优化，不接受以这项增长换动画。

决定：移除此新全局64项图片缓存。按R3设计第3节抽出桌面owner持有的共享image-preparation宿主，整行owner生命期内一个NSHostingView/离屏NSWindow；每句生成两张新图，旧新view各持相应不可变结果；换句不新建截图window。需要缓存仅保当前/退场资源，不长期累积整歌图片。owner退出/stop后关闭准备窗口释放资源。锁屏legacy路径保持，不全局改变截图窗口语义。

## 验收要求

新增有限回归：三句不同文本自然切换后共享preparation window creations仍为1（不只是对相同文本cache hit）；退场只有一份旧句视觉/一个实时clock，结束旧资源可释放；离开owner关截图宿主，反复出现不需要点击恢复。保留现有设置/锁屏门控、进度/seek、幅度和动画参数。

当前任务如果还没交付候选，可直接作为R3收尾；若已交付则只在有实质修复并验证通过后再build+1。报告诚实区分完成/未完，禁止用新增cache限量当共享宿主实现，禁止把手动步进PNG称真实生产帧。默认无诊断，不实际控制用户音乐/锁屏。
