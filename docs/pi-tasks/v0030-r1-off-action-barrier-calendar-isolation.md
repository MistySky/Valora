# V0030-R1 限定返修：off动作屏障与日历真实传输隔离

先读AGENTS及docs/verification/independent-v0030/decision.md。已完成主体/功能开关/日历UI保留，整体未接受，当前仅修以下边界，不进入浏览器V0031、不改日历360pt/监控400pt，不重做下载行/图标/成熟UI。

1. 必修独立失败testIndependentQueuedResumeCannotRestartAfterFeatureOff（Tests/ValoraTests/DownloadEngineIsolationTests.swift）：本地Range上service.resume排队后立刻pauseAllAndSave，off结束600ms后仍downloading/activeCount1。原两断言保持。追踪所属异步动作/代际与服务启停；所有enqueue/start/resume/retry/resolve及旧视图在途操作要在off屏障作废/等待取消收尾，不能仅当前active task pause。快速off-on不能复活旧操作/重复owner；重新on允许新用户动作但不自动恢复网络。若接口需显式activate/suspend以表达功能生命周期，可本模块最小补齐，调整真实调用者并测试，不全局重构。不删partial/用户文件。

2. HolidayProvider必须懒初始化真实EventKit传输并可注入fixture传输；当前无条件EKEventStore()+observeStore不符合QA隔离和关闭功能无资源。测试及--verify-* / --preview-*不得建立真实store/contacts连接或回退真实来源。ensureEvents/refreshSource/StoreChanged及后台执行前核真正started、面板可见、功能门控和授权，停止/隐藏后排队回调不可新读；既有在途结果代际拒绝，监听随生命周期注销，正常重新开启可恢复。不要仅关闭日志或跳过有效用例。给spy factory/read counters证明fixture/未授权/stop后0真实创建与读取，快速换月合并、取消和晚结果仍正确，保留已有节日映射/去重及同名个人事件规则，不真实读取个人日历/改权限复现。

验证只跑上述定向+必要开关/下载/日历相邻回归，保留已成功原生节日视图结果；生产改动完成才必要重打签名。不要每次全量，Codex后续集中一次集成收尾。报告docs/reports/v0030-r1.md，候选新目录/private/tmp/valora-v0030-r1-candidate，禁止覆盖正在运行候选或dist/退出用户软件。真实测试仅自产temp/localRange/独立defaults/Trash替身。禁止系统权限/日程账户媒体设备真实写、浏览器/helper/cookie、安装发布、Git提交推送、修改归档或pi历史模型，不恢复定时器。交付停等Codex独立验收。
