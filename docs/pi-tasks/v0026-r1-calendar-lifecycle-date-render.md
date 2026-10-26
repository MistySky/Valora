# V0026-R1：日历读取生命周期/跨日/原生容器限定返修

当前整体不接受，见docs/verification/independent-v0026/decision.md。旧相关39项通过但新增IndependentCalendarLifecycleTests五项全失败，六断言，日志boundary-failures.log。保持已确认布局/下载改名/单入口/刘海正常，禁止重复主体或扩新模块。

## 必须修复并保留独立回归

1 stop后不得接受refresh/queued通知重启读取；日期条观察和面板日程查询生命周期分开。模型构造/正常隐藏状态只算本地日期，不因rebuild/其他设置变化读个人事件。开面板且calendar模块可见、开关on且fullAccess才允许查询；关闭面板/模块/退出/失权立即失效并清可见事件，旧结果不复活。重开按最新选日再读。
2 不合作provider/真实同步EventKit读取不会随Task.cancel停止，必须最多一个实际在途并合并成最新请求，不无限新建Task/入串行队列。老工作完成后只按最新有效状态决定下一次；停止/失权后队列不能继续读。不能只是结果丢弃却继续查询。
3 调度任务真正调用provider前再次校验gate/代际/可见性；从授权发布sink读取旧willSet属性的路径要修，不可用最终commit guard代替读取前拦截。真实provider创建store/query前也应有明确许可边界，不请求新权限。
4 今天自动跨月/跨年且原本跟随今天时，selectedDate和visibleMonth及网格一起更新；手动浏览其他月份不强拉回。系统时区变化要更新使用的Calendar/日界/日期条，不只是用旧Calendar再算一次；测试通过注入时间/时区，不改系统设置。
5 菜单栏原生日期按钮应在首次跨日立即更新，解决$menuBarText willSet读旧值；用发出的新值/安全提交时序，不靠再发一次刷新掩盖。
6 正确拆除default center及NSWorkspace center的block observer token，回调排队后也有有效性检查，stop/重复start不残留/复活。Controller.stop后也不应被旧事件复活popover，subscriptions/事件monitor清理完整。

新增五个独立case保留，不弱化断言。若加入显式面板可见API，相关读测试须明确模拟打开，断言确实发生授权读并验证上限，不能通过永不读让用例假通过。用可控held continuation provider验证未取消真实工作时的积压与gateoff，不依赖sleep猜取消。

## 实际面板与UI可读性收尾

统一view宽360+padding20但popover.contentSize仍300，核真实popover而非完整NSHosting截图，修尺寸契约/动态高度/屏幕最大高度与必要滚动，所有7列、农历/事件可见。日程很多也不能超屏裁断无滚动。今天农历副行目前浅色图白字在红底外，需可读且样式仍参考Calmon，不重设计。

用户正在讨论UI：希望Calmon日历布局＋原生macOS材质，当前灰实底/实线边欠缺透明感。此R1先修功能与真实容器裁切/可读性，不擅自把整套设置/刘海改玻璃；可在报告提出局部原生popover材质方案，用户确认后再专门落地。不下载新图标/主题依赖、不恢复HTML/多风格设置。

## 验证与保护

候选只/private/tmp/valora-v0026-r1-candidate，禁止覆盖用户dist(19ba9a0f...)、退出/重启当前应用。隔离fake provider/权限，禁止读取个人事件/媒体命令/设备连接/系统权限登录项写/账号读取。真实三区左右键/日期按钮/翻月/日格/关闭和正常刘海并存需要可定位的原生预览及清楚运行方式；不能用只有菜单栏的隔离模式称刘海删除，也不能以performClick替代实机。Codex上次CUA定位preview超时，须说明独立preview可见窗口/状态项标识，避免与当前生产同bundle混淆，但不改用户应用身份/权限。

相关39项＋五独立回归及必要新增时区/隐藏/通知/面板尺寸验证、构建签名、项目外候选隔离视图。报告docs/reports/v0026-r1.md，证据docs/verification/v0026-r1/，完成停止Codex独立验收，不Git提交推送/安装发布/改归档/模型历史或恢复定时器。
