# V0036-R1：独立验收限定返修，不重做UI

V0036未接受。先读 `docs/verification/independent-v0036/decision.md`，其中来源哈希/候选签名/安全42项子集已确认，不重复全量或改布局。

## 先停止错误测试路径

你报告“无界面”的LockMusicCoordinatorTests实际usePresentationSpace:false仍创建真实NSPanel、注册系统事件，setLocked(true)直接orderFrontRegardless。Codex没有重跑。**禁止继续运行该测试类的旧实际窗口版本**，禁止其他--verify/闪窗/循环/压力。先以最小局部protocol/factory注入presentation、系统锁状态事件、调度时钟等，让fake用例不创建NSWindow/NSHostingView、不注册真实DistributedNotificationCenter/NSWorkspace，不生成真实Space或播放NSSound；不要用preview bool掩盖真实native操作。保留生产原UI和既有迁移结构，不全局架构重构。测试清单说明哪些适配器是fake。

## 限定修复

1. stop/start彻底清理LockMusicState（已有hide可用）和sleeping等session状态，取消原deadline后再开启必须按当前真实状态重新建立，不能same input短路丢600秒计时或继承过期隐藏。AppDelegate复用coordinator的真实路径要覆盖。时钟/调度注入，不能等10分钟。
2. 给通知/Combine异步交付增加session epoch及started检查，在执行写状态之前拒绝旧周期回调。注销观察者不等于取消已queued Task；睡眠handler不能先写再guard。覆盖捕获旧lock/unlock/sleep callback→stop→start→交付旧callback，声音和model均不被污染；合法新回调仍生效。不能直接在非主actor原生入口触发Swift断言。
3. informationAirPods输出必须明确可观察（发布/等价可靠依赖），与LockInformationView真实绑定一致。覆盖nil→device、同ID新电量/型号、device→nil及子开关/全局设备off，不能把model.devices读到变化当成coordinator发布正确，也不靠orderFront强迫重绘。
4. 当前锁屏notchPanel固定启动引用会在显示选择/active panel/重建后失效。以最小provider/变更通知绑定当前有效窗口，老挂载detach，新窗口attach，stop释放；不改多屏既有策略。fake display/presentation identity测试证明重绑，无真实换屏/窗口循环。
5. bindModel须观察正常音乐总开关nowPlayingEnabled并立即收起/恢复对应锁屏音乐（不要求媒体快照额外变化），不影响锁标志/耳机tile；不得因无关设置变化反复重置600秒隐藏期限。
6. 修正NotchView“Original -24度”及SettingsView旧placeholder注释，区分原版证据与复刻参数，不顺手改动画/视觉。

每个缺陷尽量补用真实生产状态机/adapter seam的修前失败回归，先证明原路径问题再修，保留既有声音edge、baseline、oldgeneration、fixed600和原设备媒体回归。不删有效断言只为通过。fake spy观察声音/挂载/窗口可见意图/定时任务即可，绝不操作用户锁屏或桌面真实窗口。

## 保留/交付

V0036用户取舍、Glass材质、音乐/耳机UI、声音资源和设置五条不改；不加不要的后端。当前R3用户运行包/dist不退出不覆盖；不真实锁屏/播放声音/媒体音量/蓝牙/权限/系统设置/个人数据，不改只读归档或Git提交推送，不恢复定时器。候选另打 `/private/tmp/valora-v0036-r1-lock-screen-candidate`，不自动运行。只定向隔离功能回归和一次必要release构建签名，报告 `docs/reports/v0036-r1-lock-screen-lifecycle.md`，完整列修复、fake测试边界及剩余实机待验，结束停等独立验收。
