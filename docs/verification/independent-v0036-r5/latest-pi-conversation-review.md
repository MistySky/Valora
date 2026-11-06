# 2026-10-29 最新 pi 对话与实际代码复核

用户要求核查，并未在本轮要求再次启动或改偏好。本轮只读生产代码/pi对话/已有自有窗口日志，未运行UI或测试。

- 旧独立decision对应89269c候选；pi此后在用户直接对话中多次修改并启动，最新报告binary29a2518。旧验收不能套用于新候选。用户对最新版本仍明确反馈不行，动画验收失败/未接受。
- 当前Models.visibleSize在同一PresentationMetrics链选择.playing/.locked；NotchView.topStrip在同一左翼切换封面/锁；WindowCoordinator.panelFrame在普通/锁屏均624x320、顶边screen.maxY，已无全屏锁态frame分支。
- shape.fill(.black)绘制完整形状是音乐和锁共用实现，不等于启用了模拟硬件几何；硬件遮住中心，视觉应只见左右延展。
- NotchGeometry.calculate先检测safeAreaTop与auxiliary左右区，再判断simulated；检测到实体时forceSimulatedNotch=true也不选140pt模拟基础宽度。pi以该偏好为唯一根因的说法不成立。仍需记录锁切换时实际hasPhysicalNotch/auxiliary宽/compact/contour/视图坐标，不能假定始终检测成功。
- 锁态仍额外经过LockMusicCoordinator阶段与ARLockPresentationSpace挂载，普通音乐没有相同Space交接；同一视图/相同尺寸不证明最终屏幕呈现相同。
- /private/tmp/valora-notch-diagnostic.jsonl共120条，全部phase=hidden/sessionLocked=false，均相同panel[552,797,624,320]，限额已耗尽；没有一条锁屏阶段，不能定位锁态下浮或排除窗口问题。记录仅anchor校正后，亦缺内容screen转换坐标及实际几何分支。

结论：实机未修好，但现有证据不能断言原因是另外模拟了完整刘海。应先修正诊断采集生命周期/去重及保留锁阶段额度，记录校正前后、当前真实几何和转换后内容位置，再决定改实际失败路径。不要重复归因模拟开关、猜偏移、重启用户软件或让用户无证据多次录制。当前不投递新任务、不改生产、不触发锁屏。
