# V0015 独立验收：部分接受，限定R1

Codex独立swift test原185项通过（Valora71+Core114），独立构建/private/tmp/valora-independent-v0015/Valora.app及codesign --verify --deep --strict通过。日志/private/tmp/valora-independent-v0015-{test,build}.log。独立设备隔离QA29/29通过，设置真实SwiftUI快照仅总开关/外观，已人工查看Connectivity.png；默认值证据正确区分现场和未证实注册默认。不读取/连接真实设备，不播放真实声音。

未整体接受，新增独立Tests/ValoraTests/IndependentConnectivityLifecycleTests.swift两项失败，日志/private/tmp/valora-independent-v0015-lifecycle.log：

1. 总开关false→true后150ms source调用0，预期初始基线查询1。settings.$bluetoothEnabled在willSet阶段同步执行setEnabled(true)，refresh又读旧false而退出，直到3秒timer才查询；归档原实现专门异步延后以避免此问题。
2. stop()后refresh()仍发起查询（调用1而非0），且stop不重置started/取消订阅，后续设置通知仍可能启动timer。需要真正停止生命周期并允许明确start重开，保持原单in-flight上限与晚结果拒绝。
3. 声音源码缺口：LowBatterySoundPlaying只有play，没有stop；生产每次临时构造NSSound.play，未保存播放实例，setEnabled(false)/stop无法停掉已播放声音，不满足任务总开关关闭声音全部停止。此项源码确认，未实播制造声音。
4. AppDelegate.applicationWillTerminate未调用新设备controller.stop，收尾需补一致。

这些限定docs/pi-tasks/v0015-r1-controller-lifecycle-sound.md返修，不新增设备/其他模块。3D电影真实呈现、真实设备连接/重连/电量权限和物理双屏仍明确待用户实机；cacheDisplay的空电影图层不能冒称已验证。原资源/许可证记录保留，不安装发布或Git提交。
