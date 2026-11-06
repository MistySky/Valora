# V0030-R5-R1 限定返修：共享入口启用后订阅恢复

读AGENTS及independent-v0030-r5/decision.md。独立20定向/缓存冷却/签名通过子集，合并结构保留，不重做UI。新增IndependentCombinedEntryTests启动off再开Codex失败：provider79/97正确但共享status tooltip仍--，原两断言保留。

start只为启用模块注册观察，而setSystemMonitorVisible(true)/setCodexVisible(true)不恢复observe，导致初始off再开（及Codex正常off-on观察消失后再开）背景更新不到菜单栏。最小补齐每个模块启用时的观察连接，snapshot后续变化继续更新共享图/tooltip/无障碍，不只强制画首次图或靠点击刷新。关闭一个不取消另一个的数据更新，双方off无后台工作，不重复provider/observer/计时器；处理stop重启的旧callback不覆盖新session观察标志。sleep/wake仍按各开关。

定向功能用fake quota及注入monitor snapshot验证初始off再开收到背景值、下一次更新继续、off-on重连、关闭另一模块不误停、既有cooldown和剩余缓存保留。不要循环开关/弹出面板；不调用showPopover/togglePopover/performClick，不运行--verify-*、批量截图/压力/全量。允许一次必要状态项功能调用；若可用纯观察描述/spy则优先无界面。原独立用例不得删断言。

新候选/private/tmp/valora-v0030-r5-r1-candidate，报告docs/reports/v0030-r5-r1.md；必要构建签名一次，完成停等Codex独立验收。不覆盖当前运行候选/dist、不退出用户App、不真实额度/账户token会话/日程读取、不系统权限媒体设备或浏览器配置cookie/helper/真实用户文件写删、不Git提交推送/改归档或pi模型历史，不恢复定时器、不开始V0031。
