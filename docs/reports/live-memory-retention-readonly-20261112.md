# build60 当前高内存只读核查

2026-11-12 12:31–12:32，本次仅采集当前进程摘要、堆类型汇总与自动释放池归属；未重启、未改代码、未测试/构建、未控制真实音乐或用户设置。

## 实测

- 唯一PID41471，1.0.3/build60，运行路径为本轮固定外框候选；采集时已运行约2小时22分。
- 初次footprint：151438488字节（144.42MiB），峰值170214552字节（162.33MiB）。RSS约143.86MiB。
- 初次分类：Malloc Small 98484224字节（93.92MiB），IOSurface dirty 14434304字节，owned unmapped graphics 10944512字节，IOAccelerator graphics 3588096字节。分类中的reclaimable不可简单再加到footprint。
- 随后heap采样：footprint119.9M，峰值163.3M；瞬时值有变化，不将初次与后续数值差当作修复效果。活跃malloc总计84432146字节，224080节点。主要类型：NSConcreteData字节存储24395776字节；CFString存储23544768字节。
- `leaks --autoreleasePools --groupByType --noContent --nostacks`：仅自动释放池持有的对象及其间接分配合计约37.8M；其中间接对象约37.7M。主线程只有少量普通条目；大量NSConcreteData、JSON reader、字典、CFString条目位于 `valora.system-media.stream` 线程池。此命令检查池归属，不是完整泄漏检测，不能称为已确认不可达泄漏。

## 原因与边界

`SystemMediaSource.swift:71-94` 将整个媒体读取while循环放在单个长期dispatch任务中。每轮availableData读取、JSONSerialization解析产生Foundation临时对象，循环内没有autoreleasepool。GCD任务长期不结束，这些已无业务用途但仅由自动释放池持有的临时对象不能及时释放。实际池归属与源码吻合，是当前内存偏高的一条直接证据；不再将其笼统归罪于歌词位图。

`SystemMediaSnapshot` 会把JSON中artworkData字符串解码为Data；这说明媒体JSON临时字符串与数据块有较大的可能体积。本次未读取对象内容，未逐个确认大字符串业务字段，不把所有CFString都断言为封面base64。

不能由一次快照解释所有内存或宣称37.8M立刻等量反映为footprint下降。SwiftUI/AppKit图形资源、正常活跃对象、分配器碎片与压缩均有贡献。当前没有证据证明歌词owner大量泄漏，也未证明仅此一项解释全部增长。

## 最小建议（未实施）

在媒体流读取每轮设置局部autoreleasepool，覆盖availableData读取及解析，而非包裹整个永久while；按流退出/解析失败路径维持原语义。跨到主线程的snapshot需由闭包正确强持有，不改变事件顺序、媒体时钟、动画、读取缓冲上限与退出策略。先用有限注入输入验证生命周期/内容与时序，再单实例实测同条件内存，不能用强制重启或关闭歌词替代修复。

## 证据文件

- `/private/tmp/valora-memory-inspect-20261112-footprint.txt`
- `/private/tmp/valora-memory-inspect-20261112-vmmap.txt`
- `/private/tmp/valora-memory-inspect-20261112-heap.txt`
- `/private/tmp/valora-memory-inspect-20261112-autorelease.txt`

所有对象采集均未输出对象内容。本次未派实施任务。
