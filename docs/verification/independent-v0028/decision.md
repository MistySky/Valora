# V0028 独立验收：整体暂不接受，限定R1

已有相关45项独立通过；release独立构建/临时打包签名通过。dist仍19ba9a0f...，未覆盖或退出当前应用。pi已执行唯一一次live只读字段探针，摘要显示字段存在；本次不重复读真实额度。只读RPC源码allowlist initialize/initialized/account/rateLimits/read，未见auth/会话读取或重置动作。最小字段/UI列表已接入，但生命周期不接受。

新增Tests/ValoraTests/IndependentCodexUsageTests.swift三项全部失败：
1 stop→start遇未合作结束的旧read，真实在途达到2（应<=1）。stop立即清task/isRefreshing不能证明旧进程已退出；生产sleep/wake及模块隐藏恢复同样可触发重入。
2 立即反复打开面板10次，3分钟仍新鲜的快照却产生11次read（初始1+打开10），会让真实app-server子进程/网络请求随点击反复启动。原native30开关30请求不是节流通过，应修新鲜缓存/冷却和失败退避，不用每次开窗强刷。
3 authoritative map被错误类型污染时静默回落旧legacy，显示88%旧数据。应明确协议失败/缺失，不把错误数据伪装有效旧数据；null按真实可空协议区别处理，已存在错误字符串/数组绝不能fallback。

另静态边界：integer先比较double<=Double(Int.max)再Int(double)，Double(Int.max)舍入为2^63，边界整数可能触发转换trap；修解析边界并用隔离fixture验证，不在用户主进程触发。transport仅有allowlist静态测试，实际fake child协议/超时/输出/取消/退出清理未覆盖。R1需补最小真实传输替身测试且不再真实账户探针。

保留成熟UI和权限/日历监控，不推进下载直到此批自动验收接受。仅派docs/pi-tasks/v0028-r1-refresh-lifecycle-parser.md。

独立正式候选原生注入QA完成：Codex列表360x272，5H/WEEK54x20，三项显示/基本路由通过；30开关request/completion30/30、假provider子进程0，该30次请求恰为上述缺少新鲜度节流的复现，不能称生产进程节流通过。
