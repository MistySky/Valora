# V0036-R2：按用户原版实测纠正刘海锁解过渡顺序与音乐卡底色

用户实际启动了Codex独立补修候选 `/private/tmp/valora-independent-v0036-r1-candidate/Valora.app` 并实测，当前重点不再是基础编译/挂载，而是原版过渡细节。本任务限定返修，保持已有功能范围；先读AGENTS最新及本任务，不重做UI、不新创交互。

## 1 用户原版观察（验收依据）

- Alcove锁定：在顶部刘海原位置处理，先收起当前音乐/左右扩展，再展开锁定状态。
- 当前Valora锁定：出现刘海被向下拉出、随后又回到顶部刘海的异常过程，不符合原版。
- Alcove解锁：先显示开锁状态/动画，再收起锁状态，最后重新展开正常音乐；有清晰连续的过渡顺序。
- 当前Valora缺少上述顺序和细节，且锁屏音乐控制卡的底色看起来不对。
- 用户反复强调“看源码、复刻品很多已有、不要猜”。不能仅调spring/delay说完成，不把本轮上一阶段fake测试通过等同原版动态一致。

## 2 已知当前代码切入点（不是已唯一确诊）

- `LockIndicatorState` 仅hidden/locked/unlocking，没有明确“普通内容收起→锁定展开”和“开锁→收起→音乐恢复”阶段；锁/解事件直接更改model.isSessionLocked、调用presenter.collapse，并同步几何/挂载。
- model.visibleSize 同时依赖 expanded、connectionToast、songPeek、showsLockActivity和歌词，而showsLockActivity又依赖异步lockNotchMounted。NotchView retainsExpandedContent及localContour也参与。须检查中间帧是否混入展开/歌词高度/错误圆角、旧notification/hover或Space/window位置切换，不要先认定是哪一项。
- 原版/复刻已有 `PresentationController`、`PresentationMetrics`、`LockIndicatorState`、LockMusicCoordinator、WindowCoordinator与锁标志视图。按实际源码接通/复用，必要最小阶段状态协调，不另起平行全局状态机。
- 当前Glass按迁入NSVisualEffectView `.hudWindow`/`.behindWindow`/active/emphasized、强制darkAqua、连续corner28，音乐卡另加白色stroke。拥有这些常量不等于屏幕材质一致。检查实际frosted路径、appearance继承/强制深色、NSHostingView/NSPanel透明底、overlay/填色叠加、材质容器与Space/壁纸采样，查明原版和复刻可证的差异，不盲换material或加白/黑遮罩。

## 3 工作要求

### A 先查原版与现有复刻调用链

来源只读 `/Users/wangqing/code/alcove-revival-archive`。
必须看当前Sources的状态与过渡实现，并看 `reverse-engineering/lock-screen-music`、`lock-appearance-0.6.5` 的具体函数/asm。特别核原版geometry/展开收起顺序、LockView/LockActivityGlyph、music card材质链。旧边界文档可能过时：复刻当前已有上下锁片运动，不要据旧文档称只有静态图标。
报告列原版确证/用户实际观察/复刻当前实现/尚未知，不能把复刻.8秒或自拟delay说成原版精确时长。

### B 按原版观察落实连续过渡

保持顶边锚定，不因中间expanded/QuickPeek/歌词/音量高度或旧hover而向下拉出多余刘海。先有界完成普通内容收起，再展开锁状态；解锁先开锁，再收起锁内容，最后恢复当前最新音乐，而不是直接用音乐替换glyph。音乐源继续后台更新，呈现缓冲不能冻结/覆盖真实曲目信息。
阶段完成优先复用已有呈现completion机制；若现有源码没有精确completion路径，说明最小方案和证据，不堆多个无所有权asyncAfter；每段有generation/epoch，快速锁→解→锁、期间暂停/切歌/音量展开、off/sleep/stop不会让旧completion展开音乐或残留窗口。Reduce Motion保持可完成的有序路径，不强迫播放全套运动。
复刻原几何与动画，非用户指定不得改宽高/圆角/字体/图标/音乐控制位置或耳机链路；不把“先收起”实现为长期彻底隐藏窗口造成闪烁。保持之前真实owned Space挂载及fail-closed，锁屏不可交互与解锁交互恢复的安全门控。

### C 锁屏控制卡底色对齐

查清源实现后只作有证据的最小材质/容器修复，Glass固定不加设置/新样式。没有同壁纸真实原版对照时明确“待视觉核验”，不要凭离屏fake图宣布颜色相同；如需要用户补原版/Valora同场景证据，交具体一次操作方案，不能反复锁用户电脑或自行改壁纸/系统外观。

## 4 保留上一轮独立补修（必读）

`docs/verification/independent-v0036-r1/decision.md`：Codex新增解锁清理回归在R1失败，已按复刻setLocked(false)直接补回 `lockSpace.detachWindowNumber(panel.windowNumber)`。音乐卡解锁立即隐藏并解除登录Space挂载；顶部notch保留到开锁动画阶段完成再移除。源码和Tests/LockMusicCoordinatorTests中有独立回归，不回退到错误detachNotchIfNeeded位置，不丢新增断言；若新阶段需要调整具体解除时刻，解释兼容原版序列并以同等所有权断言替代，不能保留登录专用音乐窗口到桌面。
上一轮state/sleep复位、epoch、信息Published、当前notchprovider、全局音乐开关、fake窗口/Space/事件/时钟/声音全部保留；功能取舍仍五条设置/Glass/固定600秒/offset0/volume默认收起，排除项不恢复。

## 5 测试与交付边界

只跑本轮修改和相邻接口定向**无界面fake**测试，不机械全量。先补能捕获错误过渡顺序/几何意图/门控/旧completion的回归，再修；可注入phase/completion和窗口frame意图spy验证顶边锚定，不能把fake调度当真实帧或动画一致。更新直接使用生产呈现逻辑的测试，不写只复述常量的测试。
严禁真实锁屏/解锁/睡眠命令、发布真实系统锁通知冒充fake、真实NSPanel/Space呈现测试、播放声音/媒体控制/蓝牙设备/权限系统设置写、个人数据读取、反复闪窗/批量截图/性能压力、所有--verify-*。只一次必要release构建签名，候选另放 `/private/tmp/valora-v0036-r2-transitions-candidate`，不启动、不退出或覆盖用户当前运行版/dist；归档只读，不Git提交推送、不恢复定时器/下载Codex、不扩模块。

报告 `docs/reports/v0036-r2-original-transitions-glass.md`：源调用链/原版证据、用户观察对应修复、各阶段与取消时序、材质差异根因/未知、修前失败修后通过、候选签名/资源/源码哈希、剩余一次实机验证步骤。完成停等Codex独立验收；原版时长/材质效果没证据不自称精确一致。
