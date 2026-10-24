# V0015-R2 独立验收：限定返修

Codex独立运行198项原有测试通过，独立构建及codesign --verify --deep --strict通过；隔离设置视图生成成功，设备QA31项通过。无真实蓝牙连接、声音播放、系统权限或登录项写入。权限图中手形已是非交互Image，Toggle未因未授权禁用；此子集接受。

新增Tests/ValoraTests/IndependentPermissionFlowTests.swift两项回归均失败（4个断言）。原始日志/private/tmp/valora-independent-v0015-r2-permission-flow.log：

1. 取消等待蓝牙授权的意图，没有objectWillChange通知。pending闭包非Published且取消不改实际偏好，因此开关UI可能保持pending开启直到其他事件刷新。同类音频/登录取消也须核。
2. 音频denied引导设置后，注入授权成功再resolve，completion仍0且pending不清。resolvePendingIntents未处理音频；生产refresh也没有音频重新确认路径。需要可证实的授权尝试结果，不能伪造preflight或把unknown当denied。
3. 源码另发现首次登录项注册：loginBinding将notRegistered直接写true，onChange注册若requiresApproval会回退draft，但没有记录pendingLogin；与“已requiresApproval再点开关”不同，返回系统批准后不能完成原意图。此项为源码风险，需注入实际注册结果的路由回归验证并最小修复。

整体不接受，限V0015-R3权限意图收尾，保留Alcove布局与已接受设备/音乐/歌词行为。真实OS授权弹窗、AirPods与物理多屏仍待实机，不以fake视图证明。
