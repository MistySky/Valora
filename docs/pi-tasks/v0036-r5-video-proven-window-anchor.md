# V0036-R5：用户双录屏证明R4仍有下浮，查真实窗口顶锚与Space过渡

R4已交付，Codex独立34定向fake/签名后依用户要求启动供录屏。用户现提供原版＋当前Valora R4的真实手持录屏，视觉仍失败，不能继续用模型geometry正确宣称完成。
先读 `docs/verification/independent-v0036-r4/user-video-comparison.md` 与 `docs/research/original-lock-unlock-user-video.md`。当前用户运行 `/private/tmp/valora-v0036-r4-completion-candidate/Valora.app`，不是旧R1；不能回退其completion、阶段拥有权、生命周期等成果。

## 新的真实证据（必须看，不猜）

临时抽帧：
- `/private/tmp/valora-lock-video-comparison/valora-full-5.5.png`：硬件刘海下方出现独立黑色锁条，间隔可见壁纸。
- `valora-lock1.jpg`：相对源视频4.7s起10fps；约5.3–5.8s下浮后回顶部。
- `valora-unlock1.jpg`：10.3s起10fps；约10.6s同样短暂下浮，再open glyph和收回。
- `valora-lock2.jpg`：15.3s起10fps；约15.8–16.3s再次重复。
- 原版 `/private/tmp/valora-lock-video-review/lock-sequence.jpg`（12.3s起）和 `unlock-sequence.jpg`（16.2s起）：始终贴顶部，锁定左右展开，开锁后左右收回，未见相同独立条下浮。
可读取上述用户授权视频派生证据/metadata，但只分析顶部刘海，不读取/复制视频中无关工作内容。不把手持像素当UI point或假装精确duration。
原视频路径通过用户消息可知；原版filename b0f89d...，Valora e3f0b...。原版视频现已有，报告不能再说完全没有可读原版动态证据。两段未清晰覆盖音乐恢复与完整控制卡底色，相关部分仍明确待验。

## 必须定位的范围

用户核心是原版动态体验。此次可见的是锁glyph所在顶部notch黑条与硬件刘海**物理分离再回去**，不是抽象尺寸变化。先查出影响真实屏幕位置/transform的路径，再修：
1. 当前WindowCoordinator.NotchPanel、EdgeHostingView、panel.frame/content layout/safeArea、本地topInset与原版/复刻窗口类差异；系统是否在登录/菜单栏/Space切换时约束或移动了窗口（包括constrainFrameRect:toScreen:等可证路径）。这只是核查候选，不预设根因，不盲加override。
2. owned Space add/remove/show时序、NSWindow level/collectionBehavior/canBecomeVisibleWithoutLogin及系统锁屏过渡之间的配合；原版原始Space/LockPanel的实际调用链和坐标来源。普通frame写对不代表WindowServer呈现坐标正确，不用重复orderFront timer补洞。
3. 主机SwiftUI内容的父容器顶锚、屏幕safeArea/菜单高度在锁切换的变化、NSPanel自动layout/窗口约束、geometry provider刷新是否引入垂直位移。不得给定一个视频看出来的y值硬补偿；必须正确坐标/挂载/窗口行为。
4. R4阶段completion/旧task/跨Space挂载期间是否产生两份window内容或重挂载跳位；用owner identity和生命周期核对，不以“动画spring问题”泛化。

可以在候选中准备默认关闭、单次短时硬上限的**仅本进程窗口**诊断：阶段时间戳、屏幕frame/safeArea、NSWindow.frame、content bounds/safeArea/转换后可见顶点、Space membership等，不读取别的App窗口标题/内容或账号。若必须实机数据才能唯一确诊，交具体最小候选诊断方案，让Codex协调用户，不在用户当前运行实例注入/重签/改设置，不自己锁屏。不能继续凭猜测改偏移再让用户无证据重复测。

## 修复/测试边界

保留R4真实withAnimation.logicalComplete推进、neutral阶段拥有权、音乐卡unlock立即detach、旧epoch/token拒绝、信息发布/设备音乐门控及所有用户取舍，除非有证据需要最小调整并说明。不改普通音乐歌词耳机/Calmon/品牌，不全局架构重写，不恢复下载Codex或定时器。
fake回归只验证真实根因相关adapter/geometry/挂载决策，不再写“静态frame==目标”就证明屏幕锚定的无效测试。只定向，无NSWindow/NSHostingView/真实Space呈现、真实锁屏通知/睡眠/声音/媒体设备权限系统写、个人数据、所有--verify/批量截图/循环闪窗/压力性能。分析已有用户视频不是运行真实UI测试，允许离线抽帧但不自称测试了本机动作。
候选 `/private/tmp/valora-v0036-r5-window-anchor-candidate`，一次必要release构建签名，不启动、不退出/覆盖当前R4或dist，不Git提交推送，不改只读归档。报告 `docs/reports/v0036-r5-video-window-anchor.md`：逐段视频证据→实际代码根因→最小修复/原版源位置→定向验证→缺少实机的边界。如果不能确诊就交已排除路径和一次有界取证，不伪称修好。底色证据不足单列，优先修顶部连续位置。
