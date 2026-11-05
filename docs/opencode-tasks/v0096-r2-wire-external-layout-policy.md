# V0096-R2：外接上移分支根本未接入生产（限定修复）

用户追问“替换了吗？看起来仍不够？移动多少”，Codex已确认包确替换但上移未生效。先读docs/verification/independent-v0096-r1/decision.md和Tests/ValoraTests/LockMusicCoordinatorTests.swift新增实际Y断言。

硬证据：Sources/Valora/LockMusicCoordinator.place()构造LockCardLayout时没有传reserveFullExpansion，默认false。整个Valora生产目标没有任何reserveFullExpansion调用。R1修改0.30只在纯模型测试生效，实际窗仍走内置0.21公式。

独立用例testLockTargetOwnsOverlayMusicAndDeviceFramesAcrossClamshellChange已经实际失败：注入外接frame.minY300/H1080，panel.frame.minY实际482.8，预期624；内置190.57通过。这次不增加任意Y补偿或比例，不削弱断言、不继续仅测试LockCardLayout常量。

## 最小修复
- 将实际选定的targetDisplay.isBuiltIn映射到reserveFullExpansion（无物理刘海≠外接，内置无刘海不能被误判），传入真实place调用；相关预览若也使用该模型同样核对，但不添加新预览设置。注入overlayFrameProvider的QA seam须有明确target或默认策略，不能在未知目标时默默错误选内置。
- 保持外接比例0.30/内置0.21不再改值，保留最大卡片240、正常歌词208、顶锚及所有UI/动画。
- 当前实际1080外接相对屏幕底top422.8/全开bottom182.8；接通后top564/全开324/正常歌词356，实际整卡应上移141.2pt，不是此前报告97.2。更正R1错误报告，不将“替换了包”与“真实定位生效”混同。
- 开盖/合盖/拔插以真实目标的logical frame和自身原点重算；内置位置完全不动。不读账号/登录控件、不截图或自动锁屏，不改用户分辨率。
- 保留forceSimulatedNotch形态跟随、歌词恢复、玻璃/音量/Space/两行监控对齐和用户图标。不上升到整体重构或新增设置，不Git提交push。

## 验证与交付
先修原新增生产协调器失败回归，再跑必要协调器/布局少量无窗口测试。验证实际panel.frame.Y随目标变化、内置不变、负原点/四态同top；禁止全量/闪窗/性能/真实锁屏媒体动作。

新独立候选/private/tmp/valora-v0096-r2-layout-wired-candidate（存在换新），不得覆写运行包/dist；构建签名及资源哈希后正常退出旧版→确认0实例→启动新包→核唯一PID与路径。报告docs/reports/v0096-r2-wire-external-layout-policy.md含实际Y回归、源调用与模型一致性、旧新数值、hash签名及实机待验。完成停等Codex验收，不能凭测试写“永不遮头像”。
