# V0015-R3 权限意图取消/返回完成限定返修

先读AGENTS、docs/verification/independent-v0015-r2/decision.md。R2正式交付已复核，198原测试、独立构建签名/设备QA31通过，但新增IndependentPermissionFlowTests两项失败。只修权限意图闭环，保持手形Image、开关唯一入口及原Alcove布局，不新增模块/权限中心，不改品牌或归档来源。

1. 等待权限时明确关闭必须让真实设置视图立即回到off。pending状态变化需可观察；不仅修改内部闭包，不靠其他Published事件碰巧刷新。蓝牙、音频、登录都核；取消后迟到回调不再开启，重复开启不重复请求。
2. 音频从设置返回授权后完成仍有效开启意图一次并清pending。当前resolvePendingIntents完全无音频分支，refresh无确认路径。保留新增失败回归并修；生产应基于可证实的系统音频尝试结果/回调（必要时返回激活后仅对有效pending重试），无可靠preflight就保持unknown，不造denied，不轮询提示/超时猜结果。已取消不重试、不启用。
3. 核首次登录项注册从notRegistered得到requiresApproval的路径：现SettingsView.onChange回退draft但未建立pendingLogin，系统批准返回不会完成首次意图。用注入注册结果/设置spy复现实际路由，最小接线修复；不能只测试初始已requiresApproval。等待时关闭需清意图并正确停止用户授权的注册行为，避免UI关闭但稍后系统又启用；不真实改登录项。

测试需覆盖真实Binding路由及视图可观察状态：pending开→关立即off、授权后仅一次完成、拒绝失败off、关闭后迟到拒绝、重复请求、系统设置返回和首次登录注册requiresApproval。保持IndependentPermissionFlowTests有意义，不删断言或绕开生产路径。完整swift test、构建签名、隔离设置/设备QA和必要音乐歌词多屏回归，报告docs/reports/v0015-r3.md（不要继续覆盖R1报告）。真实OS弹窗未验明确记录。禁止真实播放/切歌/seek/音量、设备连接、系统权限/登录项写、安装发布、Git提交推送；不恢复定时器。完成停止等Codex验收。
