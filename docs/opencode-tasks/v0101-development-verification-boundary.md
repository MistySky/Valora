# V0101 开发验证代码编译边界

现有会话继续，当前codex/final-cleanup，V0100独立20定向/签名hash/build9单实例接受。本批只收尾开发QA编译边界，不重构三个target架构、不删验证能力/历史证据、不改变产品UI与当前功能。Objective-C/Perl、原生桥/材质/动画均保留。

## 要解决
约3千行Verification/Audit/LockCardPreview及开发启动分支仍在正式App目标。目标是正式Release不编入开发验证实现与可执行入口，开发构建仍可按已有隔离suite用测试/preview。不要只加运行时if把实现继续留正式产物，也不以“nm找不到”代替源码编译条件证据。

优先小型明确编译条件（例如VALORA_DEVELOPMENT仅debug定义），避免新包/大拆目录。系统最低27/Swift6.4和语言6保持。全仓核每个QA类型的真实调用，必要调用点一致条件化；不全局包裹成熟生产控制器。记录本批实际隔离文件/入口及必须保留的共享纯逻辑/测试seam。

- 核Verification.swift、*Verification.swift、*Audit*.swift、LockCardPreview.swift及AppDelegate/AppRuntimeDefaults中对应启动分支。MenuBarAuditValidity等实际共享纯策略依引用决定，不按文件名盲删。
- NotchWindowDiagnostic是用户协助取证开发路径，可将重实现限开发编译，生产callsite条件化或极小无行为门面；不能让生产丢底层锁屏Space必要诊断结果/功能判定，不以空实现替代真实锁屏控制。
- AppMemoryReader进程枚举/旧应用列表如牵涉大量SystemMonitor类型，本批只隔离确属开发实现，不借目标清理重构成熟monitor；未能安全隔离处如实记录供下一步决定，不假称全清零。
- 正式Release收到已移除的--verify/--audit/--preview/--expand-media等开发参数必须在启动真实服务之前明确拒绝并退出，不能悄悄回落production启动真实媒体/权限源。锁屏预览flag此前未列QA suite需同时明确仅开发，不恢复设置入口。普通系统启动参数不误拒。
- 保留debug测试隔离preferences，不能因为预览代码门控让fake变真或访问正常用户配置。测试既有AppRuntimeDefaults期望按debug可用继续成立。生产正常启动/开关/权限路由不变化。
- 不直接删除历史测试、fixture、报告、用户资源、图标候选或许可证；不搬移整个文档/改AGENTS历史（下一批）。不全局格式化。

## 验证
仅相关纯参数/启动模式/隔离suite定向与必要编译验证；不用全量/闪窗循环，不运行QA UI/审计本身、不触真实媒体/权限/锁解。debug编译证明测试入口仍可用，release编译与源码条件证明重实现不进正式产物；用小型CLI纯入口测试验证Release开发参数拒绝发生在AppKit/服务之前，避免为此真正打开多个App。

正式候选一次Release构建自动build10或真实下一号；新/private/tmp目录，严格签名/hash/Info/JSON；正常退出旧版→0→唯一新包，不强退/覆盖dist/运行包、安装或Git提交push。报告docs/reports/v0101-development-verification-boundary.md给文件清单/构建条件/残留及原因/定向测试数量/候选证据，不宣称性能改善已测。完成停等独立验收，不推进完整回归/性能专项。

## 用户随后授权的极小排版补充

本批结束前顺序处理docs/opencode-tasks/v0101-supplement-reset-card-unit-spacing.md：重置卡数字与单位统一空格“重置卡 2 张”，不改布局字体。若已正式交付则作为下一构建处理，不并行启动会话。
