# V0036-R6 锁屏下浮原因核查，禁止继续猜测修复

用户2026-10-30要求查询：既然采用和音乐同样的两侧延展，为何仍出现完整黑色刘海脱离实体刘海。当前实机仍失败，不把旧fake/签名称通过。本轮在V0037-R1已交付后串行执行，仅定位与完善默认关闭诊断，不自动换版/更改用户设置。

先读docs/verification/independent-v0036-r5/latest-pi-conversation-review.md及两段用户视频对照。读取本pi最新直接用户对话，承认其多次反馈不行；之前将forceSimulatedNotch=1称根因不成立：NotchGeometry先识别实体safeArea/auxiliary，再判断simulated，除非锁定期间实体识别失败。完整shape.fill是普通音乐也使用的绘制方式，不能仅此断言另模拟硬件，更不能把共享尺寸当实际屏幕表现证明。

核查重点：
1. 正常.playing和.locked链逐段对照：NotchView顶锚/hosting layout/实际geometry分支、LockMusicCoordinator阶段/Space attach/detach、WindowCoordinator renderPanels/updateVisibility/屏幕参数更新顺序。区分窗口下移、hosting内容下移/安全区改变和WindowServer呈现变换。
2. 复刻源码与原版已有反编译证据只读核查，Space/LockPanel各自承载内容/坐标类型要区分，不再以原版某LockPanel全屏就让顶部notch也全屏。不用猜出的菜单栏高度作y补偿，不改音乐成熟路径。
3. 已有/private/tmp/valora-notch-diagnostic.jsonl共120条全部hidden/sessionLocked=false，限额耗尽，无法说明锁态。先验证这点，修诊断：连续相同状态去重、普通状态有限额度与锁事件保留额度、锁/解生命周期边界，保持总硬上限；记录anchor前/后、Space成员变更前/后、display/frame/aux左右宽/safeArea/forceSimulated/hasPhysical/compact/visibleSize/contour.topInset、host.frame/bounds/safeArea和convertToScreen内容顶点。必须实际调用的日志入口，而非仅写未接函数。可加默认关闭的轻量布局probe观察实际SwiftUI顶部区域位置，以区别panel正确但内容错，禁止常驻采样timer或枚举其他App窗口内容。
4. 诊断数据只包含自己窗口与数字状态，不含媒体标题/日程/账号/其他窗口。不开诊断不增加布局探针/磁盘写入；fake验证去重/限额保留/触发顺序，不建真实NSWindow/Space、不发真实锁通知。

交付明确哪些已证实、哪些假设、现有证据能否定位。若不能唯一定位，准备一次用户协助的具体取证方案，不擅自启动/重启/改偏好、也不先要求用户反复录屏。不继续试验性位置补丁。保留现有功能和V0037成果，不处理材质/下载Codex/新模块。
只定向无UI测试/必要构建签名，不全量/--verify/UI点击截图循环/压力，不真实锁屏睡眠声音媒体设备权限系统写，不Git提交推送、归档只读、不覆盖dist或当前候选（运行路径不可靠，禁止覆盖R5）。如需候选另放/private/tmp/valora-v0036-r6-diagnostic-candidate，不启动。报告docs/reports/v0036-r6-lock-presentation-causal-audit.md，交付停止等待Codex。
