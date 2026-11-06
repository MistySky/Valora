# V0042 锁屏音乐玻璃限定返修：先沿原版调用链和成熟复刻

用户明确让本聊天Codex检查并指挥你，参考原版反编译和归档成熟玻璃实现，透明方案不追。继续现有会话，不新开/改模型。先完整读AGENTS最新覆盖、docs/verification/lock-glass-supervision-2026-11-03/findings.md，再读下列实际源码。

## 必须纠正的证据解读

归档/Users/wangqing/code/alcove-revival-archive只读：
1. reverse-engineering/lock-screen-music/100186a7c.c:443–452（docs/.../ghidra同名副本亦可）：material0xd、blending0、state默认active、+0x38=0x101的后字节frosted=true、corner28。
2. docs/alcove-1.7.9-detail-audit/evidence/ghidra/100131c1c.c：OS26+且frosted=false才Glass；当前音乐调用frosted=true仍NSVisualEffectView。核整个参数→分支，别只读工厂支持某类就猜锁屏走它。外层NSView做continuous圆角裁切，effect四边约束。
3. reverse-engineering/lock-appearance-0.6.5/依据与边界.txt，已有解释不可漏读。
4. Sources/AlcoveRevival/LockFrostedBackground.swift、LockMusicCoordinator.swift:54–85：成熟玻璃体验底稿。用户确认这条比透明实现好，应直接保留迁入而非重造。

## 本批做什么

- 背景回到上述玻璃路线：hudWindow/behindWindow/active/emphasized；复用归档darkAqua、continuous28、white15%@0.5细描边及层级。darkAqua/描边是复刻底稿，不得报告为已证明原版精确值。不要把系统Liquid Glass/自绘壁纸/亮度黑白纱实验继续叠进来。
- 按反编译原生容器形态处理必要外层NSView和effect四边约束；显式防止NSViewRepresentable无intrinsic尺寸撑开卡片。background不参与决定前景尺寸，卡片可见总宽345，panel仍385及现有透明动画边距，展开音量高度按原策略。不要通过缩放整个播放器来凑尺寸。
- 限定音乐卡背景/必要appearance/描边/容器，不全局改colorScheme。保留用户此前已确认的耳机单行16pt/位置、进度未播放段、滑入、V0040三项设置及模块总开关；不要再回滚为整批9b2953e。尤其不能动顶部独占Space、锁解原地开锁→neutral→音乐、显示来源、普通刘海播放器/歌词、权限/日历等。
- 核现有--lock-card-preview作用和生命周期，若保留只复用同一音乐卡，不截图壁纸、不把桌面合成颜色当锁屏通过；禁止启动它或自动循环截图。无需恢复模拟锁屏设置。
- 修正V0041报告“原版锁屏就是LiquidGlass”的不实判断，保留历史实验说明为已否决，不删除历史证据。明确还原了哪些来源行、因Swift6/macOS27作了哪些必要适配；证据未知不猜透明度。

## 验证与交付

仅必要无窗口功能回归（LockMusicCoordinatorTests/LockMusicStateTests）+构建签名。源码及必要纯布局约束核查防345→385，不建真实UI/Space/真实锁通知、不跑多屏测试类或--verify、不批量截图/反复弹窗/性能；不读取壁纸/个人日程/真实媒体，不真实播放seek音量/设备连接/授权。当前用户软件不退出/启动/覆盖，不覆盖dist；候选/private/tmp/valora-v0042-lock-music-glass-candidate，报告docs/reports/v0042-lock-music-glass-source-parity.md，交付后等Codex独立验收及用户一次体验。无Git提交推送或定时器。不要写仅凭枚举/单测/离屏图就“玻璃已实机一致”。
