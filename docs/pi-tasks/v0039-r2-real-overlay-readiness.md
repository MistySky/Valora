# V0039-R2 真实overlay接管失败限定返修

先完整读AGENTS.md、CONTINUATION-PLAN及docs/verification/independent-v0039-r1/live-2026-11-03/decision.md和own-window-diagnostic.jsonl。用户刚实测本轮仍下移。不是动画数值问题：seq14 overlay561迁移失败，回退primary526，[1,36]，locked QuartzY55/unlockingY37；AppKit顶边不变。R1代码/fake接受不等于实际接管，真实体验拒绝。

本批仅修真实overlay创建/WindowServer注册/Space接管生命周期，不改已正常桌面preview、glyph/open→neutral→最新音乐完成顺序或其他功能。

1. 定位生产调用顺序与native所有返回分支。当前隐藏make→windowNumber→原Space必须非空→迁移→orderFront。新窗口可能尚无Space，但目前证据不足称唯一原因。优先只读核已有固定外部源码研究与原版证据，明确他们创建/显示/加入迁移/主窗口挂起的先后；不直接运行他人软件或恢复普通primary迁移R8。
2. native给出可注入、每次尝试有界的结果详情：自己overlay window、符号可用、目标Space、原成员nil或已知空、系统返回status、迁移后实际成员、清理结果。不要在Swift failure日志硬写unknown，保留真实nil/[]差异。默认关闭、仅自己窗口、主线程无循环/阻塞/常驻timer。
3. 以已证明生命周期实施最小修复。未知query仍安全失败，已知空若可合法直接进入所属Space需证据及失败清理；如需要让窗口先被WindowServer注册，选择无可见闪动/无旧desktop缩放污染的准备方式，明确alpha/collectionBehavior/Space关系，不先显示黑条再抢移。不要简单删guard、盲目delay/补偿Y/宽松返回true。primary仅在自己overlay实际接管后挂起；失败仍保留可见fallback且明确诊断，不全消失。不允许普通媒体refresh无限重建。
4. 用真实生产native代码fake回调和Swift注入重现原Space为[]、nil、系统错误、success未移动、成功注册后detach、取消/stop/重锁以及所有权恢复；不要只用预先设定成功的FakeSpace冒充覆盖。定向测试即可，不重跑无关全量。若静态/隔离尚无法证实修复，只如实报告待证并交足分支诊断，不能宣称已实机修好。

候选新路径/private/tmp/valora-v0039-r2-overlay-readiness-candidate，日志/private/tmp/valora-v0039-r2-overlay-readiness.jsonl，以package.py --lock-diagnostic-path配置并签名核验，报告docs/reports/v0039-r2-real-overlay-readiness.md。用户当前运行包不退出/不覆盖/不启动新包；交付等待Codex独立验收。

只无UI功能回归和必要构建签名；禁止真实NSWindow/Space探针、真实锁通知/锁屏、媒体/设备/权限/个人日程操作、UI循环/批量截图/性能压力、dist覆盖、Git、定时器。归档只读。不能为记录更多信息再次要求用户重复测试；先修当前已证实接管未成立和诊断不足。
