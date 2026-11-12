# 媒体读取循环临时对象及时释放（最小修复）

用户授权：“可以，交给pi修这个，别动动画和交互，完成后你验收替换下”。继续当前原Pi会话/模型/checkout；禁止另开会话、提交推送、覆盖Applications或控制真实音乐/音量/锁屏/设置。

## 已有真实证据

先读 AGENTS、`docs/reports/live-memory-retention-readonly-20261112.md`。build60运行约2h22m后，媒体读取队列 `valora.system-media.stream` 的autorelease池保留大量Data/JSON/CFString对象，全部池约37.8M仅由池直接/间接持有。原始证据 `/private/tmp/valora-memory-inspect-20261112-autorelease.txt`，禁止打印对象内容。本任务是临时对象生命周期修复，不宣称不可达泄漏，不把新启动内存较低当作长期收益证明。

## Codex指定实现

只修 `Sources/Valora/SystemMediaSource.swift` 的reader永久循环释放边界：每一次读取迭代的局部autoreleasepool必须覆盖 `availableData`、chunk追加、逐行JSON解析及snapshot构造。buffer在pool外保留跨chunk未完整行；当轮解析临时对象在下一次阻塞读取前能释放。不得仅给整个永久dispatch任务包一个pool或仅改queue的autoreleaseFrequency来冒充修复。

- EOF、16_000_000缓冲上限及terminate、畸形行continue、type/diff过滤、snapshot=nil回调、同一epoch主线程投递顺序、stop取消和退出错误路径保持原样。
- 正在跨main.async的snapshot须由闭包拥有正确生命周期；不能提前释放、丢弃、合并、排序或延迟事件。读取频率/--debounce/--no-diff参数保持不变。
- 允许最小内部测试接缝将这一个真实读取循环提取为内部helper，使用注入readChunk/emit/超限回调；生产必须调用同一helper，避免只测复制实现或只断言源码出现autoreleasepool。不得重构媒体控制器或整个数据管道。
- 所有动画、交互、歌词外框固定修复、原曲线时长、逐句切换、封面、hover、progress、seek、锁屏全部不改。不得改封面质量、缓存策略或加入新timer/诊断常驻任务。

## 有限验证

1. 分片JSON跨多chunk、同chunk多行、畸形/非data/diff行、EOF、buffer超限；正确snapshot与nil事件内容和顺序保持原行为。使用fake输入，不启动真实媒体适配器。
2. 检验pool生命周期：在真实读取迭代中注入可观察的自动释放临时对象，在下一次读取开始前已释放；跨main派发的snapshot数据在pool排空后仍完整。禁止靠长循环/大批量内存压力模拟或仅测终点footprint。
3. 跑相关SystemMediaSnapshot/SystemMedia纯逻辑、MediaControllerRecovery/交互/seek及固定外框的定向必要回归。不全量压力、不开关真实音乐/锁屏。
4. 保存准确测试数量/日志和失败处理；遇到权限限制如实报告。

## 交付停止点

报告 `docs/reports/media-stream-autorelease-fix-20261112.md`：精确diff、池与异步数据所有权说明、有限测试证据、未验项。**先不正式打包、不替换、不操作用户真实状态**；完成即停，由Codex独立验收、构建签名、正常退出旧实例、确认0后启动唯一候选。不要进入其它内存优化。
