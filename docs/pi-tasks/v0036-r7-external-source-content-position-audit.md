# R7 外部源码与R6诊断缺口限定返修

用户实测刚启动的archive复刻版也有同样下浮，要求看其他开源软件。Codex独立已读外部实际源码而非README。先读docs/verification/independent-v0036-r6/decision.md及docs/research/lock-screen-external-source-comparison.md。

R6限额4fake/签名接受但未定位修复。修诊断不能再靠host边界冒充实际NotchShape：
1. contentTopScreen记录host边界须根据host.isFlipped选minY/maxY，字段名明确hostTop；单独默认关闭、仅诊断模式插入的实际SwiftUI notch区域布局probe，记录layout rect/位置，解释SwiftUI global与NSWindow/屏幕转换，避免将逻辑frame误称真实呈现frame。不启动真实窗口测试；提取纯坐标函数fake覆盖翻转/负屏幕origin/内部y偏移。
2. 记录自己notch window原/目标空间成员实际查询列表及迁移边界（禁止枚举其他App）；只汇总count/verified不足。Space query失败要标unknown，不能假true。
3. 核读/tmp外部固定源码：boring.notch→SkyLightWindow delegateWindow与DynamicNotch两条均用SLSSpaceAddWindowsAndRemoveFromSpaces，而我们CGSAddWindowsToSpaces只添加；详细查当前锁定添加窗口是否仍属于普通桌面、系统过渡是否可能同时呈现、解锁原归属怎么恢复。DynamicNotch还隐藏普通窗口，使用独立顶锚overlay和显式host.frame+activeSpace刷新；不能只拿其函数名直接换，也不要求强行照搬多窗口架构。
4. 查复刻来源和原版已有反编译，区分继承缺陷和新迁移问题。已有对照录屏可离线分析，但不得把源码候选当唯一根因。
本轮交可审查根因候选与最小修复方案、完善的默认关闭取证路径。没有实机证据前不盲加偏移/全屏/延迟或直接更换私有Space API；不能断言“一次日志一定能确诊”。不要自动启动/退出用户当前软件或archive，不改偏好，不触发锁屏/睡眠/声音/媒体设备权限/日程读取。定向无UI fake、必要构建签名仅新/private/tmp/valora-v0036-r7-diagnostic-candidate，不覆盖已有运行候选/dist、不全量/--verify/自动截图点击/循环压力、归档只读不Git不新增依赖。报告docs/reports/v0036-r7-external-source-content-position-audit.md，交付后停。
