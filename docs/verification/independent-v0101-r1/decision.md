# V0101/R1 独立验收接受

2026-11-05。主体开发编译隔离及R1两个入口的自动范围接受，不宣称已运行QA UI或全局回归。

独立LaunchPolicyTests14+IndependentDevelopmentIsolationTests2共16通过，原4失败断言保留。有效lock-card-preview属于QA suite/.lockCardPreview，AppDelegate fixture分支只构造controllers、不start、不setupMenu，在服务启动前return；standalone expand-media/preview-long-title属于invalidDevelopmentCombination，dev拒绝发生在controller构造之前。与preview-music同用保持synthetic，不回落production。Release main仍在NSApplication.shared前拒绝。

独立直接运行当前正式binary分别带三个flag，均exit2/development-only，无窗口或真实服务；release编译条件与shared controller顺序沿主体已核。日志/private/tmp/valora-independent-v0101-r1-tests.log。未运行debug卡片UI、未真实媒体/权限/锁解，不全量或资源审计。

包/private/tmp/valora-v0101-r1-dev-isolation-candidate/Valora.app，bundle0.2.0/build13和JSON一致；strict/deep签名通过；binarycae680e5c4d51d748ccef6134025e2c2f9172f542094a18f621bb3f0634b34db匹配；只读ps唯一PID37215路径对应。git diff --check通过。“重置卡 N 张”补充仍在，沿独立18测试记录。

保留项不能算全隔离：NotchWindowDiagnostic含实际compositing回退判定；AppMemoryReader/SystemMonitor类型仍交织，生产不注入reader；其它共享fixture/纯策略需按引用判断。下一步文档明确这些事实，不借隔离重构。主体曾build10崩溃，修复后build11及13正常运行；记录不删除。

可以进入现行文档/历史索引与过期sidebar纯测试契约更新，之后才完整功能/全局联动回归，修完回归缺陷后资源与动画专项。
