# V0015-R4 权限异步完成与注册取消限定返修

先读AGENTS、docs/verification/independent-v0015-r3/decision.md。Codex独立201项、构建签名通过，原两失败已修；但新增登录旧回调回归失败，生产音频返回异步和首次注册取消仍不闭环。只修本范围，不改Alcove UI/手形Image/开关入口，不加菜单栏模块，不恢复定时。

1. loginRegister回调绑定本次intent generation，取消后旧回调不能完成新意图。保留IndependentPermissionFlowTests新增失败回归，不删断言。
2. refresh音频设置返回发起异步attempt后，不得立刻用旧denied状态清pending；保持有效意图直到实际回调确认。取消仍立即off、迟到不启用、重复激活不并发重复请求；无可靠preflight保留unknown，不轮询提示。提供可注入真实状态读取/激活入口，测试走生产refresh路径：denied→点击开→打开设置→激活→异步延迟成功→完成一次；取消、失败、重复激活、迟到均覆盖。不要只verificationSet后resolve冒充异步成功。
3. 首次注册requiresApproval时用户关闭，不能仅清UI pending而留下本次注册。记录本次注册所有权，以现有LoginItem.set(false)最小注入撤销动作接线；仅撤销本次创建的注册，保护原有系统状态。用注册/撤销spy验证真实Binding取消，偏好原先false也必须撤销，不能依赖draft onChange。撤销失败如实反馈/刷新，不假装系统已关；QA绝不真实改SMAppService。

保持已接受设备检测/声音停止、音乐歌词多屏/图标。完整测试、独立新增回归、构建签名、隔离设置设备及必要回归，报告docs/reports/v0015-r4.md，区分fake和实机权限。禁止真实媒体操作、设备连接、系统设置权限登录项写、安装发布、Git提交推送或改归档。交付后停止等Codex验收。
