# 桌面歌词可回退实验版：Codex 指定方案

用户已知 build31 没有接入新渲染器、实测无明显改善，同意准备一个可回退的真实测试版；体验与功能仍是约束。先读 AGENTS.md、`docs/reports/desktop-lyrics-swiftui-text-fidelity-r2.md` 和最新独立报告。沿用原 OpenCode 会话、模型和当前分支。

## 方案与范围

1. **构建期隔离**：新增专用编译条件 `VALORA_LYRICS_EXPERIMENT`，只有显式实验构建会编译和调用新渲染器；普通 debug/release 默认路径保持生产 SwiftUI 行。不要放开 `VALORA_DEVELOPMENT` 给正式构建，也不要把验证入口混入正常 Release。把实验所需 renderer 与纯验证/预览代码拆开条件，普通 Release 不能带实验实现或开关。
2. **仅桌面**：在 `NotchView.swift` 三个桌面歌词调用处显式启用实验行，覆盖浮动/刘海内嵌/展开歌词；锁屏 `LockMusicView` 默认继续现有 `CompactLyricsView`，不更改锁屏行为。保留现有外层音符、宽度、内边距、裁剪、空白、无障碍与布局结构；新 renderer 只替换歌词文字与逐帧遮罩/滚动。不要把整个 `CompactLyricsView` 改成锁屏也会使用的全局开关。
3. **权威输入和生命周期**：以 `model.elapsed` + `model.elapsedSampleDate`、`model.playbackRate`、`model.playing`、`model.duration`、`model.lyrics.timeline/identity`、`model.lyricsAccentColor` 构造快照，沿用现有乐观 seek 锚和时间轴；宿主本身不得创建 30Hz SwiftUI TimelineView。保留当前开关、歌词加载/空行、切歌、pause、seek、倍速、滚动、换句、Reduce Motion 和屏幕显隐；隐藏/卸载必须停止时钟并关闭自有 capture 窗口。多显示器各自显示正常，不能把是否 active 仅凭 window != nil 判断。
4. **明确可回退**：普通构建不受影响；实验 renderer 抓图失败时，宿主立即回退现有 SwiftUI 歌词行，禁止丢字/残留旧字/无限重试。停止新 renderer 时先释放时钟与窗口。回退状态只属于当前视图/有效歌词身份，不新增用户设置或后台开销；重新换曲可重新尝试。不要为了回退同时运行两条 30Hz 渲染链。
5. **体验门槛**：新渲染器已有长句 2x 截图残余差异、emoji 差异及动画逐帧未验。实验不等于正式接受；不得为了掩盖差异改字体、字距、歌词时间、帧率或生产渲染。提供可复现真实参考图/实验图与用户可感知风险说明；如果完整桌面接入需要破坏功能或不能确保失败回退，停止并报告，不硬接。

## 必做验证

- 针对宿主接线增加独立于实现的回归：显式实验与普通路径选择；锁屏始终旧路径；隐藏/恢复；文字变化/空行；失败回退与释放；seek/暂停/切歌；音符和行宽不变；多个显示实例独立。复跑上批原型、缓存、seek、节奏定向测试，不删改既有断言。
- 普通 Release 构建和显式实验 Release 分开构建并核验：普通包不含实验 renderer 与实验开关；实验产物只用于本机评估。测试不操作真实播放、不启动第二个 App、不进行压力或批量闪窗。
- 输出 `docs/reports/desktop-lyrics-experiment-integration.md`，说明选中范围、失败回退、真实测试数、视觉差异、可回退方法、1x/动画/CPU 未验项和独立验收方法。
- 本轮完成实现与验证后停止，等待 Codex 审核。**不得打包安装、启动/替换当前 App、提交或推送**；用户的上一轮替换授权针对 build31，不自动授权本轮替换。Codex 验收后再安排真实对照。
