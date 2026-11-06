# V0097 独立验收

2026-11-05；Space子集接受，整体暂不接受，构建号绕过路径限定返修。

- 独立编译生产NativeBridge.m的fake native测试：既有Exclusive6、新Repeated5、原历史失败回归1均通过；原回归first=1 second=1 restoredDesktop=1。没有构造真实窗口/操作真实Space。
- 独立Swift定向53通过：协调器32、布局13、锁屏歌词8；日志/private/tmp/valora-independent-v0097/swift-targeted.log。非全量、无UI循环/资源审计。
- 独立scripts/test_build_number.py通过：自动分配顺序/并发/错误路径子集有效。
- 但package.py显式--build仍直接取值且不推进状态。独立执行真实脚本AST中的参数及编号分配前缀（在binary resolve之前停止、无实际打包/真实计数器写），--build1/2/999分别原样分配1/2/999，输出counter not advanced。可重复旧号或高号之后退回自动低号，不符合构建号递增要求。
- 脚本“单次交付恰好+1”用例只调用分配器，并未经过package.py真实参数路由，未覆盖该遗漏。需增加打包入口路径验证，保持测试仅临时目录、不反复Release构建。
- 当前包/private/tmp/valora-v0097-space-restore-candidate/Valora.app，版本0.2.0/build2，Info.plist与build-verification一致。严格deep签名通过；二进制b72d615cfeb2b68f3128322a5d7d7c6b288215ad5039ca3a968cb03b7ca74387与报告一致。
- 独立只读ps确认唯一PID93857，路径为上述候选。无须再次启动同包。git diff --check通过。

仅返修构建号入口，不改已通过Space/UI/位置/材质/动画。本轮尚不开始全量测试或资源流畅度测试。
