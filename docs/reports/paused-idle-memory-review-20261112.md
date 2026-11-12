# 暂停且不操作界面的内存优化空间（只读）

用户确认“静态”为暂停播放、不操作界面。本次只读检查唯一build61/PID66987，未操控播放/偏好、未测试构建或改生产代码。

## 当前快照

2026-11-12 14:10采集，进程已运行约1h28m。footprint59819112字节（57.05MiB），峰值106316904字节（101.39MiB）；随后池报告约57.3M。RSS132432KiB（129.33MiB），不将共享/可回收等RSS项直接等同应用独占footprint。

heap活跃malloc29359555字节（28MiB），其中non-object约14.2MiB未细归属，不擅自命名为歌词/缓存。vmmap随后总活跃malloc约28.3M、分配器dirty+swap碎片约9399K，不能假设这些页能由释放一个对象或强制整理立刻归还。

图形相关分类：IOSurface约3.98MiB，CoreAnimation约2.44MiB，owned unmapped graphics约1.19MiB，IOAccelerator dirty约0.69MiB，另有可回收图形页。不能把可回收数字直接加到footprint。

autoreleasePools：仅由池持有的直接/间接对象均0，池页等约20K；媒体stream队列存在，无旧版37.8M积压。堆内CFString Storage仅13296字节，旧大字符串不是当前大头。

## 可查的有限空间

- 仍有歌词文字准备NSHostingView、NativeLyricsTextPreparer，以及CalendarMonitorSharedView宿主。对象本体大小不等于其整棵图形/SwiftUI依赖大小，也不能仅凭数量判断泄漏。
- NativeLyricsTextPreparer的NSHostingView在构造时创建，close仅移除/关闭窗口，仍保留host；可以评估未用到时延迟创建、完全不可见且不再需要时释放宿主，而不是直接暂停就卸载显示中的歌词。其边际收益尚未量化。
- 设置窗口构造后由AppDelegate长期保留，日历popover也有复用宿主；可评估彻底关闭后的资源生命周期。当前堆未发现SettingsView宿主，不把它列为本次57MiB的实测来源。销毁后下次重建可能影响打开速度，必须先量化才能立项。
- NativeLyricsRow的needsContinuousFrames及边界定时器计算都检查playing/rate；暂停设计上停止逐字/滚动时钟并保留静态画面。本次未读取内部diagnostics，不能把源码条件当作真实时钟观测。
- LyricsCache上限是序列化payload的5MiB预算，非实际堆上限；当前堆未见大量LyricLine/LyricWord存储，不能把缩小缓存预算当作确定收益。保留显示中封面/歌词纹理及热缓存有助于恢复流畅，不建议为数字盲清。

## 判断

相比上次媒体池问题，本次没有同等级明确异常大块。可以继续量化完全不可见界面与未使用歌词准备宿主的边际占用，预期只作为有限优化候选，不承诺MB节省量或回到启动30MiB。以不影响恢复播放、歌词衔接和打开界面速度为门槛，先测后改；不为了回收分配器空页引入常驻清理timer或重建显示中的动画树。

证据均保存在 `/private/tmp/valora-idle-memory-inspect-20261112/`。本次未向Pi下发修改任务。
