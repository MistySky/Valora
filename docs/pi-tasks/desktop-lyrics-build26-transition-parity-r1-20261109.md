# build50 独立验收返修：策略隔离与真实中间帧

原任务 desktop-lyrics-build26-transition-parity-20261109.md 继续有效。Codex正在独立验收，暂不进入内存优化。不要提交推送，不改模型/会话，不回滚已有成果。

## 1. 锁屏策略实际被一起改了

报告称锁屏沿用旧策略，但 LockLyricsRow 仍直接使用 ExperimentalDesktopLyricsView；host.beginTransition 没有role/strategy分支，新SwiftUI+16ms路径和新layoutWidth都作用于锁屏。因此“锁屏未改”目前不成立，违反原任务桌面范围。

明确提供桌面/锁屏过渡策略，桌面启用本轮build26对齐，锁屏保留build49原先的timer/旧宽度策略。不要用debug开关充当生产锁屏策略，不按任意字符串role猜功能；用类型化配置。默认调用兼容性清楚，分别测试生产桌面/锁屏走哪条路径。另一选择是拆桌面外壳，底层共用；只需最小实现，不全局重构。

## 2. 现有证据没有证明生产中段对齐

testRuntimeViewportTransitionSteppedShortAndLong 的中段PNG来自 debugManualTransition/debugSetTransitionProgress，并非生产新SwiftUI驱动；不能拿它当实际平滑证据。testSwitchKeyFrames虽然读生产路径，但以每个delay累积等待（0+.05+.10+.15+.20）而非同一时间原点采样，名义t=.10实际已约.15，t=.20实际约.50；目前断言主要sawOutgoing/settled而未核对中段。

修正实际采样时间基准，在一个有限隔离窗口/fixture内，以真实生产驱动，收集短→短、短→长、长→短起始/中段/结束后帧。baseline用已注明的发布源码外壳，不只是当前生产CompactLyricsView终点。对音符x位置、当前/旧行x/y、容器宽度连续变化和结束后无二次跳动给出中段证据。接受渲染采样有时差并报告实际时间；不要伪造精确同帧或用手工步进代替生产路径。无需批量/长时测试。

## 3. 固定16ms人工停顿

当前主队列固定延迟16ms再启动0.2s动画，且横向syncOuterLayout从lineKey onChange立即启动，两个方向并非同一时刻开始。用户主诉就是衔接不流畅，不能未经验证把这个新空挡称为与build26完全对齐。

先证明生产路径不存在一帧新行闪现/有意停顿、横向先动而竖向晚启动。如果实测存在错拍，优先用真正的SwiftUI transition/同一动画事务协调外层状态，而不是增加固定延迟。若仍必须handoff，说明为何需要、实际延迟与baseline的差异并用真实中段证据验证。不要拉长时长或削弱效果。

## 交付

修正报告中未证实的“锁屏不改/中段对齐”措辞；保留原测试与新生产策略回归。更新原report或追加R1，必要验证通过后按AGENTS一次候选自动替换、唯一实例、默认无诊断、保留build50回退。完成即停，Codex5分钟内检查进度。内存优化等此轮技术验收通过后再派。
