# 1.0.6 播放歌词CPU再次定位（只读）

PID28780，用户已确认正在播放并显示歌词。当前采样约24.11秒，累计CPU时间增加0.97秒，区间平均4.02%单核；ps平滑读数2.5–5.0%。数据/private/tmp/valora-cpu-current-20261112.json；15秒调用栈/private/tmp/valora-cpu-current-20261112.sample.txt。未控制真实媒体、修改偏好、重启或替换实例。

## 证据

- 对比此前高占用的10秒sample，旧栈更明显包含NativeLyricsRowHost.makeNSView → apply/switchLine → buildTextImages → SwiftUI测量/截图与布局。当前低占用15秒栈中同路径采中更少。这些是采样权重，不是调用次数或独占CPU占比，不能据此量化精确贡献。
- 当前持续活跃路径包括NativeLyricsRowClock.fire/update/draw、ScreenStateMonitor.refresh和AudioOutputController.refresh。SystemMediaSource的高采样权重主要是阻塞等待读取，不能误判CPU热点。
- 两次都未采到ensureStatusItemVisible、setCalendarVisible、updateCalendarImage、applyFeatureSettings持续执行，也未采到鼠标queuePointerUpdate/trackMouse热路径；监控图标updateMonitorImage少量出现。不能证明日历贡献绝对为零，但没有证据支持1.0.6可见性恢复陷入循环。
- c1009dc→f6666aa的歌词renderer、host、屏幕检测与音频轮询文件无变化。

## 已确认实现机制与可优化位置

1. NativeLyricsRow.swift needsContinuousFrames：播放且逐字数据非空、或长句超宽时注册共享30Hz时钟；短句无逐字时走边界唤醒。不同歌词/段落的播放CPU不能混作同一基线。
2. LyricsRowExperiment.swift keyedRow使用presentationID创建新的歌词视图以保留原翻转；NativeLyricsRowHost.makeNSView立即apply；NativeLyricsTextPreparer.prepare每次执行测量和两张文字图片生成，没有结果缓存。实际高负载栈经过这里。应保留动画身份与时序，若继续优化优先查重复准备同内容/尺寸/颜色/scale的情况，缓存需要严格有界；不能直接删除keyed过渡。
3. NativeLyricsRowView.draw已对mask/offset赋值去重，但CATransaction.begin/commit仍无条件每帧执行。layoutLine也无条件写多层几何；layout回调先layoutLine再update，可能重复布局/提交。可考虑在全部视觉参数不变时跳过事务，并保留参数变化的真实更新，需针对换句/seek/跨屏/布局验证，不能承诺具体CPU降幅。
4. update每帧重新查询lineEnd并注册共享时钟，虽然不是最明显热点，也有稳定输入下的重复工作。屏幕每0.75秒、音频每0.5秒轮询构成另一些开销；应单独测量，不能把所有CPU都算给歌词或日历。

当前数据能解释负载随歌词渲染/换句波动，尚不能证明与历史1%多的同条件版本回归，也不能宣布8%是必须接受的成本。本次只完成定位，未改代码、未派发实现、未构建发布。
