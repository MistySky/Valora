# build68剩余资源优化复核

用户请求查看CPU与内存还有哪些优化空间。本轮仅只读采样、源码复核和报告，没有修改生产代码、测试、构建或替换。

## 当前测量

- 唯一Valora实例PID71033，1.0.6/build68；音乐总开关读取为1。
- 30.15秒CPU累计差分均值3.98%；窗口前后通过只读媒体get确认playing=true、同一媒体身份。没有要求用户严格不操作，因此称当前播放观察，不冒称受控纯静置或相同歌词片段A/B。
- 独立vmmap：physical footprint47.3M，peak47.9M。ps RSS约128MiB，与footprint不是同一口径；不得将RSS作为用户实际内存开销结论。
- CPU窗口结束后另取8秒sample，未叠加到上述均值。可见歌词clock/update/draw/换句文字准备，ScreenStateMonitor窗口与Space查询、AudioOutputController/CoreAudio读取；未采到checkHoverExit热点。SystemMediaSource.readStream大量栈权重是等待输入，不能当作CPU热点。
- 单次内存快照不能证明没有泄漏或长期增长，但当前没有足够证据支持为缩小数字而清除现有UI/歌词缓存。

## 推荐的下一步

### 1. 同轮音频查询去重，优先于完整事件驱动重构

AudioOutputController.swift:75每0.5秒获取完整ARAudioOutputSnapshot，相等判断在读取后。NativeBridge.m:35的volumeChannels为检查能力读取音量，:56的snapshot再次读取同一组声道音量。可以首先复用同一轮的读取结果，保持轮询间隔、控制响应和设备切换语义不变。后续若缓存UID/name/modelUID/能力等稳定字段，必须对设备切换和相应属性变更失效；不能只按设备ID永久缓存。

### 2. 歌词内部管理与布局去重，保持现有渲染

NativeLyricsRow.swift:425每帧refreshLineEnd并synchronizeClock；换行时switchLine也refreshLineEnd。:1117每帧重写同一个弱引用注册项，fire每tick筛字典并生成数组。可以只在成员/时间轴/行/duration变化时更新管理状态，继续原30Hz、同一时间戳的高亮/滚动，不改变换句身份、翻转或曲线。

layoutLine:802无条件写图层几何；layout及viewDidMoveToWindow存在重复路径。应先有限计数确认实际重复，再按完整几何及图层代际去重；不能只按宽高跳过换句/scale/挂载所需布局。LyricsRowExperiment.updateNSView在完整输入去重前仍wire新闭包，可研究owner/generation稳定时复用，但不可缓存旧回调或改变发布时序。

这些是确定冗余路径，未测出各自独占CPU贡献，不承诺能把播放3.98%降到1%。保留必要的灰色/高亮双图、逐字效果、原帧率和所有转场。

### 3. 屏幕检测做小范围去重，不直接降频

ScreenStateMonitor.swift:87每0.75秒枚举窗口/查询Space；非空时screens()在同一轮调用两次，可改成单次取值。更大收益需要研究窗口/Space查询触发，但全屏与Mission Control隐藏依赖这些结果，不能因没有音乐就停止，也不为CPU数字擅自延迟检测。

## 内存建议

暂不主动压缩缓存或销毁设置/日历界面。现有LyricsCache有50条/5MiB原始payload与磁盘上限，原始payload额度不是实际Swift对象堆大小。设置窗和popover存在复用；强制关闭即销毁会增加首次重开成本。

NativeLyricsRow.stop清了图层contents，但仍保留preparedBaseImage/preparedAccentImage；若视图仍被持有，最后图像可能驻留。这只是应调查的持有链，不是已证实泄漏。先确认结束转场后是否还有旧视图及图片，再考虑仅释放确定不再使用的对象。不要追求使用后强制回到冷启动内存。

## 证据路径

- /private/tmp/valora-build68-resource-review.json
- /private/tmp/valora-build68-resource-review-memory.txt
- /private/tmp/valora-build68-resource-review.sample.txt

建议继续做小批CPU去重，以同状态实测收益决定是否保留；内存先维持现状。不能用不同播放状态的1.29%、5.37%和本次3.98%计算优化降幅。
