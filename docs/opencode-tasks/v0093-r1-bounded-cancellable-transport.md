# V0093-R1 独立验收限定返修：真实取消与超时

继续现有会话ses_e5f5da1c5ffesaPdioiEijQ5HM，先读docs/verification/independent-v0093/decision.md及Tests/ValoraTests/IndependentCodexTransportTests.swift。用户仍要求由OpenCode开发，Codex验收；保留用户seq5413已确认的5H日期/两行监控同卡。用户在本聊天新提出“监控放日历事件区”仅讨论，未授权实施，不移动当前布局。

两个独立假进程用例已经实际失败（4断言），不得删断言、缩短fixture静默时长或只取消provider状态来冒充修复：
1. Task.cancel后应及时结束实际子进程，清理管道/后台读取，向调用者抛CancellationError；应处理启动前取消/启动后取消竞态，不误杀其它进程。
2. 当前while内availableData会阻塞，2s deadline在3.2s静默子进程退出前无法触发。用独立超时/非阻塞或异步管道机制保证绝对deadline，无输出或仅半行时也有效，deadline正确返回timeout。
3. 同一传输需要及时排空stderr（不输出其敏感内容）及有界stdout/行buffer；有界SIGTERM→SIGKILL与关闭handler，保证成功、错误、取消、超时均回收进程/管道，输出超限不能无限攒内存。避免主线程阻塞、continuation双resume或文件句柄write导致SIGPIPE崩溃。
4. 保留仅initialize/initialized/account/rateLimits/read白名单；不要读真实auth/账号会话/模型请求/重置操作。本轮只用自产临时脚本/协议fixture，不再跑真实额度握手。
5. stop后无后台进程，并保持现有单在途/重启不并发/缓存节流/旧代次结果拒绝。增加必要少量无窗口真实子进程测试，禁止全量、闪窗、性能/截图循环。原13用例+这两原失败回归及相关有限fixture必须通过。
6. 修报告数量错误：13+32+13+4=62不是49。如其它套件未真正执行，不冒称62通过；报告各套件实际数量。
7. 不改当前UI/菜单入口/内存格式/图标/音乐/锁屏/已确认日期展示，不Git提交push、归档只读、不真实播放器/设备/锁屏/权限动作。
8. 新候选独立/private/tmp/valora-v0093-r1-bounded-transport-candidate（存在则新目录），不要覆写当前运行包。定向验证/构建签名通过后按AGENTS单实例替换（正常退出旧版→确认0→启动→唯一PID路径核验），锁屏不绕过。报告docs/reports/v0093-r1-bounded-cancellable-transport.md及原失败回归结果、签名/hash/单实例记录，完成停止交Codex复验。
