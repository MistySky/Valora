# V0015-R3 独立验收：仍需限定返修

独立全量201项测试通过（87+114），原两项IndependentPermissionFlowTests回归通过；独立构建与codesign --verify --deep --strict通过。原始日志/private/tmp/valora-independent-v0015-r3-test.log及-build.log。未改系统权限/登录项或连接真实设备。

新增独立回归testCancelledLoginRegistrationCannotCompleteNewIntent失败：取消首次注册、重新开启后，第一次旧回调(.enabled)错误完成第二次意图并清pending。日志/private/tmp/valora-independent-v0015-r3-extra.log，3项中1项失败、2个断言失败。loginRegister仅检查pendingLogin != nil，无代次绑定。

另有两个生产接线问题：

- AppPermissions.refresh在audioNeedsReturnAttempt时发出异步音频确认，随后立即resolvePendingIntents；audioCapture仍是旧denied/restricted，音频分支立刻clearAudio。真实异步成功回来时pending已空，因此无法完成。这不同于QA直接verificationSet(.authorized)再resolve的同步路径。需实际生产激活路径的注入状态源测试，不能另造只供测试走的成功路径。
- 首次登录注册返回requiresApproval后，系统已注册；取消仅clearLogin。draft仍false，Binding不写false，也无unregister回调，SettingsView.onChange不会触发；因此只关闭界面意图，留下注册，稍后系统批准仍可能启用。任务R3已明确禁止这种情况，尚未落实。取消只清理本次创建的注册，不应删除无关既有注册。

保留Published pending和手形Image的已修子集，整体仍不接受。限R4闭环，不扩新模块、不重构UI。真实OS权限与AirPods/物理多屏继续待实机。

补充：Codex隔离设置视图生成/窗口几何验证完成，设备QA31项全部通过；未调用真实蓝牙/声音。此不抵消上述权限流程缺陷。
