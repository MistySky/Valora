# V0043-R1 独立验收限定收尾

先读docs/verification/independent-v0043/decision.md。独立44真fake和最终52aa9436...c84c签名/hash通过，不能因此称玻璃实际一致。用户上一张乳白图不能直接等同最终clear，当前本机无Valora，本轮Codex未启动。

必须处理：
1. 查原版modern100187f28.c:1031–1048/1055–1065/1078–1088的玻璃背景与前景分离。当前clear之外仍把标题/artist/progress/controls/output/波形/音量等强制white。请核已有背景/外观信息与系统语义颜色的最小策略，让锁屏音乐在亮/暗背景可读，不把clear当完成；不要改普通黑底刘海播放器、顶部Space与动画、卡片345/圆角30、V0040。对确需新增壁纸读取且现有信息无法提供的路径，先明确给出具体方案/数据范围，不直接读取真实壁纸或截取用户屏幕；可先用注入明暗fixture验证策略。禁止经验黑白纱/壁纸自绘/猜私有variant数值。未知不能假装已匹配原版。
2. 改正报告绝对推论：“公开样式不一样就一定是variant/无法公开实现”未证明；前景/appearance/实际背景合成尚未排除。regular是新LiquidGlass的一种，不是旧HUD组件。保留当前clear候选，不反复换材质试色。
3. 把注释regular→clear、当前实际启动记录和桌面预览操作如实对齐，保留历史失误。对话称已启动16503而报告称从未启动，必须更正。后续新候选只/private/tmp/valora-v0043-r1-lock-contrast-candidate，不能继续覆写旧目录/运行包，不能自动退出启动/替换，交付冻结hash。桌面效果不当锁屏验证，缺实机就如实待验。

仅改动所需无窗口fixture/定向功能回归及构建签名；禁全量、MultiDisplay类/--verify/真实NSPanel/Space/锁通知/媒体设备权限日程/账号/壁纸读取/自动预览/截图循环/性能。不Git提交推送或定时器。报告docs/reports/v0043-r1-contrast-and-delivery-evidence.md；交付后停等Codex。
