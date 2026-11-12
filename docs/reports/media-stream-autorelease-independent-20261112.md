# 媒体读取临时对象释放：独立验收与替换

结论：限定修复技术验收通过，1.0.3/build61已替换为唯一运行实例。未改动画、交互或其它内存策略。长期内存曲线仍待日常使用观察。

## 范围与代码核对

派工前保存全Sources及Package.swift哈希，验收后比较：仅 `Sources/Valora/SystemMediaSource.swift` 变化，无新增生产文件。固定外轮廓、歌词/封面动画、hover、进度、seek、锁屏生产代码均未变。

真实生产循环调用内部readStream。每轮autoreleasepool覆盖读取、追加、JSON解析及snapshot构造；跨chunk的buffer在池外保留。主线程闭包强持有snapshot，池排空不使待交付数据失效。未改事件过滤、nil事件、行顺序、epoch取消、EOF、严格大于16000000的缓冲上限、terminate/waitUntilExit和退出错误通知，也未改适配器参数。

## 独立验证

- 首轮定向34项通过（Valora29、ReferenceCore5），日志 `/private/tmp/valora-media-pool-independent-20261112.log`，范围含媒体流解析、媒体控制恢复/seek、progress隔离、交互和固定外框。
- 审阅发现开发probe使用自建pool/Swift ARC，不具备生产pool反证能力。删除该probe，改为缓冲恰好等于上限仍应解析的边界测试。
- 新增 `IndependentMediaStreamPoolTests`：用一个真实NSObject marker经原始C ABI的objc_autorelease入池。旧永久循环负对照在下一次read仍持有marker；真实生产readStream在下一次read前marker已释放。外层测试pool只用于安全清理负对照，不在注入读取中另建pool。
- 另将含Unicode、换行与512字节封面的snapshot及中间nil事件强捕获进回调，真实生产pool全部排空后实际main队列交付，内容与顺序完整。
- 改正probe后，对两组媒体流/池测试定向复验7项通过（含上述2项独立测试及5项解析/边界），日志 `/private/tmp/valora-media-pool-boundary-independent-20261112.log`。两轮有重叠，不相加宣称41项独立用例。
- `git diff --check`通过。测试未启动真实媒体适配器、未控制用户播放。

## 构建、签名与替换

- 显式 `VALORA_LYRICS_EXPERIMENT=1`，正式打包一次，自动分配build61；日志 `/private/tmp/valora-media-stream-pool-build-20261112.log`。
- 候选 `/private/tmp/valora-media-stream-pool-candidate-20261112/Valora.app`，固定Valora Self-Signed签名；codesign strict/deep、Info.plist与build-verification.json核对通过。
- binary SHA256：`37231fbf28e96b77a4c5909cc32e504d00e12c7746f99883e4e6d0396018f2aa`。
- 正常quit旧build60/PID41471，确认0个Valora，再启动新候选，确认唯一PID66987及正确路径。记录 `/private/tmp/valora-media-stream-pool-running-20261112.json`。
- 未覆盖Applications、未改真实媒体/音量/锁屏/用户偏好、未提交推送。

## 一次运行后核查及限制

新候选启动约34秒后，一次只读采样footprint为28132360字节（26.83MiB），峰值28410888字节（27.09MiB）。autoreleasePools报告中 `valora.system-media.stream` 的池为Empty；所有池仅独占持有的直接/间接对象均0，池页等约24K。命令返回1但产生完整池报告且无错误信息；本次只使用其池归属读数，不称完整leak检测通过。

证据：`/private/tmp/valora-media-stream-pool-after-20261112-footprint.txt`、`/private/tmp/valora-media-stream-pool-after-20261112-autorelease.txt`；采集使用noContent，不输出对象内容。

旧版运行2h22m与新版启动34秒不可直接比较为总内存降幅，不能声称永久省100MiB或长期零增长。本批直接有效性依据是：原进程池持有约37.8M的实证、真实循环释放边界及带负对照的生命周期测试；新版一次池快照是有限补充。没有压力/长时间循环或真实音乐操作，日常长期增量与用户体感仍待观察。
