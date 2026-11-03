# V0036-R4：收起阶段可呈现的Space所有权＋实际动画completion

先读 `docs/verification/independent-v0036-r3/decision.md`。R3原31项通过，上轮2失败已修，不重做那些成果。Codex新加2测试3断言失败，生产未改，保留有效断言。

## 1 窗口拥有权必须覆盖真实收起

当前syncLockIndicator以showsBadge决定挂载，导致.locking/.neutralizing/.restoring没有Space拥有权。基础刘海目标尺寸存在不等于登录界面可见。原版历史Space挂载证据明确普通用户Space窗口会被登录界面盖住，不要忽略这一实际迁移前提。
局部区分“呈现窗口仍需挂载/可见”和“是否画锁glyph”：锁定收起阶段在真实锁屏呈现前提下可见，neutral不显示glyph但形状要连续；解锁开锁→neutral动画完成之前保留需要的窗口拥有权，再移交普通内容。原音乐卡/设备信息仍在unlock开始立即orderOut/detach，不能为保留notch又保留登录专用音乐卡。off/sleep/stop/failclosed/currentnotch换屏的所有权成对清理。
新增testIndependentLockNeutralAttachesBeforeShowingBadge与testIndependentNeutralGeometryRetainsNotchSpaceOwnership必须通过。既有旧断言若要求open glyph一结束立即detachnotch，需要按用户新的完整neutral阶段调整到neutral真实completion后detach；保留“音乐卡立即detach、notch最终必detach”的有效所有权要求，报告原因，不能简单删断言。

## 2 真正用收起动画完成推进阶段，禁止固定0.12秒替代

当前.withAnimation(badgeAnimation .45/.2)改geometry后scheduler .12就开始locked/hidden，可能回收插值尚未到基础刘海就反向展开。用户动画是核心，不要把.12改成另一个猜测值。
生产应复用SwiftUI logical animation completion或已有呈现完成机制，完成收起才展开锁/音乐；以最小局部适配表达提交geometry及其完成回调，test seam只替换动画commit完成信号，不替换被验证的几何/阶段逻辑。测试手动保留completion后应能证明：未complete不进入下一阶段；complete一次后仅推进一次；旧callback在快速反转/stop/off/sleep/restart后无效；合法currentcallback可收尾；同步completion（ReduceMotion/无动画）也不造成阶段引用/任务句柄污染。
不能再仅fireDelay(.12)证明“动画收完”，fake目标geometry不等于真实插值到达。保留无界面fake隔离，不能创建NSWindow/Space或真实锁屏测动画，别通过加大delay碰运气。

## 3 保留边界与交付

R3基面几何、锁中交互禁用、latest音乐数据不冻结、notification/lyrics/output/hover抑制、R1lifecycle/epoch/Published/当前窗口provider、解锁music detach等全保留。只修改相关呈现链，不改已确认大小/图标/材料/普通播放器行为，不恢复废弃功能。
用户运行 `/private/tmp/valora-independent-v0036-r1-candidate/Valora.app`不退出不覆盖；来源归档只读。定时器保持关。禁止真实锁屏/通知伪造/NSPanel/Space呈现/声音媒体控制/设备权限系统写/个人数据读取、--verify、批量截图、反复UI循环、CPU内存帧率压力、Git提交推送或安装发布。
只定向无界面功能回归与一次必要release签名，候选 `/private/tmp/valora-v0036-r4-completion-candidate`，不自动启动。报告 `docs/reports/v0036-r4-space-animation-completion.md`，列原失败及真实生产completion接线、逐段窗口所有权与cancel、测试fake边界、sourcehash/签名/原版证据未知。动画duration/原版壁纸材质未取到证据仍待实机，不自称1:1。完成停等独立验收，不自行下一功能。
