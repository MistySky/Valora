# V0038 用户可操作的桌面模拟锁屏开关

用户最新要求明确交pi完成，覆盖上一轮仅Codex修复范围。先读AGENTS.md/当前源码。用户希望在未真实锁屏的桌面直接验证左右延展，避免系统锁屏/Space干扰。

## UI与行为
保留锁屏现有五项设置/默认不变，在同页加一行“模拟锁屏”普通开关，Alcove同样简洁风格，不加图标/长解释。默认off，临时状态仅进程内，不写UserDefaults、不重启后恢复on。不修改真正锁屏总开关值。
- 用户打开：复用当前真实锁动画状态机/几何/真实withAnimation完成驱动：音乐若已展开先收完整播放器，音乐compact若有两翼先收回基础刘海，再原地左右展开锁标志；无音乐基础刘海直接展开锁。只在当前活动屏使用现有notch window，不能另造浮条/新panel或用假的动画视频。
- 用户关闭：维持锁展开宽度显示开锁glyph，再收回基础刘海，当前有音乐再按正常音乐活动展开，无音乐回基础刘海。恢复最新媒体快照，不恢复缓存旧歌、不真实播放暂停。
- 模拟只验证顶部锁/解动画；不显示锁屏底部音乐卡/设备卡，不播放声音，不触发真实锁通知、CGSession锁定、睡眠、屏保、Space创建/挂载/移除或窗口level更改。
- 实际锁屏事实与模拟呈现状态分开，不能仅setLocked(true)就触发真实Space/声音/底部卡链，也不能另写一套不同动画来假验证；必要最小抽取呈现输入/来源并复用既有阶段状态机，不能全局重构。
- 真正锁屏事件优先：模拟中如用户真正锁屏，应安全取消模拟异步回调并交还真实后端，模拟开关自动off；真锁状态下禁模拟入口，关闭模拟不能将真正sessionLocked改false或触发真解锁。不要用模拟callback覆盖真实锁状态。
- 锁屏总开关关闭/功能stop/退出取消模拟，恢复正常音乐并清理旧completion；总开关off时模拟入口禁用即可，不自动启动真实服务。快速on/off/on保持generation/epoch边界，旧动画完成不能重开锁。

## 当前回退状态
R8迁移实机导致锁屏直接消失，已撤销生产迁移并启动/private/tmp/valora-lock-visible-rollback-candidate（binary54fc0d29...）。保留当前已知可显示add/remove路径，不恢复SLSSpaceAddWindowsAndRemoveFromSpaces、R8严格gate或擅自修原下浮；原下浮仍未验收通过。R7默认关闭诊断保留，V0037日历监控成果保留，归档只读。

## 验证/交付
只本批定向fake功能用例（不能构造真实NSWindow/Space）：模拟on/off完整阶段顺序/同几何；有音乐/无音乐/完整展开；快速反转/旧完成拒绝；真实锁接管/模拟off不真解锁；总开关off/stop清理；sound/space/windowFactory动作spy确保模拟操作不产生额外真实后端副作用或底部卡。不要全量、--verify-*、自动点击/闪窗/截图批量/压力测试。
一次必要Release/签名候选/private/tmp/valora-v0038-desktop-lock-preview-candidate（不要覆盖当前运行包或dist，不自动退出启动换版）。不真实锁屏/媒体设备/权限偏好系统设置写、不Git提交推送、不恢复定时器。报告docs/reports/v0038-desktop-lock-animation-preview.md明确源码/测试/界面待用户点开，交付后停待Codex验收，不向旧队列推进。
