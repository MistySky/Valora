# V0030 主体/开关/日历补充独立验收：整体暂不接受

## 已确认子集
最新候选c421f6a63e35fc7e5c477fd51cae965db0d3148b7960d38c396266c2e272f8a0的deep/strict签名通过；原dist仍19ba9a0f0cae669dcc32eb8f282750f9fd46a71a603d1bb2d01b9f872b0ffd9f，未覆盖/退出。独立运行--verify-calendar-parity，实际原生fixture视图恢复国庆/重阳、休班角标和点、国庆及国庆(休)各一行及休息标签；注入视图不冒称真实用户日程验证。日历360pt、监控400pt源码与Calmon原值一致。三个占位页已换开关，通用图标开关接线存在。

## 阻断：关闭下载后排队resume复活
新增testIndependentQueuedResumeCannotRestartAfterFeatureOff独立本地Range回归失败：同main actor中enqueue→pause→service.resume（内部排Task）→pauseAllAndSave→600ms，仍downloading且activeCount=1（期望paused/0）。两有效断言失败，见late-resume-failed.log。原因DownloadEngineService.resume创建未跟踪Task，off路径只暂停当前任务，没有作废排队动作。必须实现所属service动作generation/任务跟踪或等效屏障，所有start/resume/retry/resolve/enqueue及旧UI动作迟到都不能在off完成后联网。保留partial，不改算法/UI。

## 阻断：日历测试/关闭资源隔离未闭环
HolidayProvider在属性初始化直接EKEventStore()且init observeStore，即使authorizationCheck=false/fixture-only。fixture provider在loadedRange无效或源未选择时ensureEvents/refreshSource可直接调用真实store.calendars。完整集成运行出现系统Calendar/Contacts存储连接诊断，已中止（exit130），不能称全量通过或仅fixture访问。不得读取或打印用户真实事件验证。应懒创建且注入真实/fixture传输，测试和QA完全不建立真实store；真实读取还须started/面板可见/功能开关/授权门控。StoreChanged监听当前只核授权、不核面板/started，stop/隐藏后已排回调须拒绝，监听注销需生命周期闭环。原日历显示数据映射通过子集保留，不为此重写UI。

## 验证范围
全量已尝试一次并因隔离问题中止，非全量测试失败结论，也非通过；不立即重复。下一轮pi仅针对新增失败/日历传输隔离与既有相邻回归；Codex在修复后完成一次必要集成。用户正在运行版本未替换，定时器关闭，不进入V0031。
