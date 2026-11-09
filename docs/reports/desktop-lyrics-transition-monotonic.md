# 换句计时器：按真实时间推进（单调时钟）

2026-11-09。执行：新 OpenCode 会话（GLM-5.3-Flash，用户覆盖旧会话/模型条款）、分支 `codex/idle-cpu-optimization`。按 `docs/opencode-tasks/desktop-lyrics-transition-monotonic.md` 处理。改动仅限 `Sources/Valora/LyricsRowExperiment.swift` 的 `LyricsRowExperimentHost` 驱动段与新增测试文件，全部位于 `VALORA_LYRICS_EXPERIMENT` 条件编译；普通构建生产代码零改动。未启动/替换 App、未打包、未安装、未提交推送、未控制真实播放；锁屏未改。运行中的用户 build33 实例未触碰。

## 一、Codex 审查结论与修法

`LyricsRowExperimentHost.startTransition` 原驱动在每次 60Hz Timer 回调累加固定 `1/60/0.2`：主线程卡顿、回调合并或丢帧时回调次数变少，0.2s 动画按回调次数而非时间补齐，会被拉长。修法按方案执行：

- **单调起点**：`startTransition` 记录 `transitionStartedAt = currentMonotonicSeconds()`。生产时钟读 `ProcessInfo.processInfo.systemUptime`——与渲染器 `NativeLyricsRowView` 边界唤醒（`boundaryDeadlineUptime`）同一单调源，不受用户改墙钟影响；不用 `Date`。
- **时间进度**：每次回调 `progress = clamp((now − start) / 0.2, 0…1)` 后直接应用并夹取；`progress ≥ 1` 第一次回调立即到达终点、`stopTransition()` 停止计时器并释放旧句。不再逐帧累加固定份额；迟到的第一次回调即刻终态。计时器仍 60Hz、`tolerance 0.002`、`.common`，合并帧无影响。
- **不变项**：`cubic-bezier(0.42, 0, 0.58, 1)`、±26pt 双向位移、双向透明度、`debugManualTransition`/`debugSetTransitionProgress` 确定性步进、歌词 30Hz/字体/配色/滚动、代次与身份回调防护全部保持。
- **测试 seam**：`debugMonotonicClock: (() -> Double)?`（nil = 生产 `systemUptime`）；`debugFireTransitionTick()` 执行恰好一次驱动回调（无视图/无手动 stepping 依赖即停在无窗口场景）；`debugTransitionTimerActive`（= `transitionTimer != nil`）使驱动生命周期可验证。

## 二、独立行为回归（新增 9 项，`Tests/ValoraTests/IndependentLyricsTransitionClockTests.swift`）

宿主级 8 项（注入时钟 + 单次/多次 seam tick，不依赖睡眠准时、不跑真实 runloop）：

1. `testSingleLateTickReachesTheEndPointAndReleasesTheOldLine`：开始后时钟已过 0.25s 只触发一次回调 → 立即 settled、旧句释放、驱动停止；其后再两次过期回调为 no-op（不重启动画）。
2. `testProgressMatchesTheElapsedMonotonicTime`：0.1s 时四状态等于 ease(0.5) 预测（容差 0.2pt / 0.01）；同刻重复回调幂等；0.199s 仍中途；0.2s 整到达终点。
3. `testUnevenIntervalsFollowTimeNotCallbackCount`：0.03/0.06/0.09/0.12s 间隔不均回调各时段状态全部等于按时间预测，并反而断言与「第 i/12 回调」预测差 > 0.2pt（排除按帧数累加）；0.21s 回调按期收束——时长不被回调次数拉长。
4. `testRapidSwitchesRestartTheWindowAndEndOnTheLastLine`：A→B 中途切 C 重置时钟窗（0.25s 时未终、0.31s 终）；终态 C、冻结 `1.0-` 行。
5. `testPauseKeepsTheDisplayedLineAndSettlesOnIt`：中途进度推进不改行、终态停在原行。
6. `testHideStopsTheDriverAndStaleTicksDoNothing`：`endPresentation` 立即释放并停驱动；过期 tick 不复活。
7. `testFailureStopsTheDriverAndIgnoresLateLineCallbacks`：失败停驱动；同代次迟到行回调不得重启动画。
8. `testInvalidateCancelsTheLiveDriverAndLateCallbacks`：代次令牌使已排定定时器与迟到回调失效，旧呈现失败不锁定新状态。

真实宿主 1 项（`IndependentLyricsTransitionClockHostingTests`）：经渲染器触发、真实 60Hz runloop 定时器（无 debug fire、无 manual 模式）、仅注入时钟；时钟读 0.25 后频率上第一次 runloop 回调即到达终点：settled、旧句/冻结视图移除、单 renderer、`lineSwitchAnimations == 0`、驱动停止。生产时钟路径（不注入）的自然自终由既有用例覆盖（下节）。

## 三、核对与本轮全量结果

既有防线未删改：端点帧一致性、音符/文字居中（含空行仅音符、双宽度）、空行→下一句唤醒、单 renderer / 单活动时钟、静态冻结视口仅换句期间存在、逐帧无文字/位图重建（`textBuilds` 增量断言）、隐藏/失败/卸载/暂停 seek/快速换句、渲染器 CA 换句保持关闭（`lineSwitchAnimations == 0`）、普通构建无实验实现。

| 组 | 结果 |
|---|---|
| 实验构建（新时钟 9 + 空行 1 + 宿主 3 + 真实宿主 22 + 集成 5 + 静态帧 3 + 渲染器 11 + 生命周期 1） | **执行 55，跳过 1，通过 54，失败 0**；日志 `/private/tmp/valora-transition-monotonic-exp.log` |
| 普通构建定向组合（歌词/渲染器/桌面发布/锁屏歌词 14 套件；实验专属文件编译为空无匹配） | ValoraTests **执行 63，跳过 1，通过 62，失败 0**；日志 `/private/tmp/valora-transition-monotonic-normal.log` |
| ReferenceCore（含歌词时间轴等） | **137 通过，0 失败** |
| 普通 Release | 成功；`nm`/`strings` 实验实现计数 **0**（`/private/tmp/valora-monotonic-normal-release/`，binary 5,417,064 B） |
| 实验 Release | 成功；`nm` 实验实现符号 **172**（`grep -c -e LyricsRowExperiment -e ExperimentalDesktopLyricsView -e StaticLyricsLineNSView`，含新 `debugMonotonicClock`/`debugTransitionTimerActive`），`strings` 含 `ExperimentalDesktopLyricsView`/`LyricsRowExperimentHost`；nm 总行 19400（普通 18547）。`/private/tmp/valora-monotonic-exp-release/`（5,416,776 B） |

跳过 1 为既有 opt-in 探针（`LyricsRowExperimentIntegrationTests` 普通构建选择用例），两轮各计一次。构建命令：普通 `swift build -c release --product Valora`；实验前置 `VALORA_LYRICS_EXPERIMENT=1`（实验 Release 首跑曾漏环境变量，已重建并以符号计数核验为准）。

## 四、未验 / 风险

- **真实 App 体感未验**：本轮证明的是驱动语义与端点行为（自由真实宿主自然终态、注入时钟下时间进度正确）；未在真实 App 逐帧对照 0.2s 过程，不以计数推导完整体感。既有端点/静态帧证据（见 `desktop-lyrics-transition-runtime.md`）语义未变并复跑通过。
- **真实丢帧场景未复现**：注入时钟模拟「回调少而时间已过」，真实 runloop 卡顿/合并由单调时间数学保证按期收敛，但未在真实卡顿环境实测。
- CPU/内存本版未测；用户对 build32/33 的 CPU 观察仍是实测前参照，不代表本改版。
- `systemUptime` 单调源复用渲染器既有约定，未做跨机器/休眠后行为实测（休眠属毫秒级暂停场景，进度夹取保证终态正确，未验体感）。
- 1x、真实物理多显示器/刘海、真实播放与音量未增验；锁屏与普通构建未改动。
- 既有宿主路径存在「view 更新期内发布」告警（`host.begin` 由 `wire()` 在 `makeNSView` 中同步调用所致，非本轮引入、非产物路径），如实记录待后续处理。

## 五、回退

实现全部位于 `VALORA_LYRICS_EXPERIMENT` 条件编译；不设该环境变量时普通 Release 实验符号 0。回退只需不启用该构建标志；生产 `CompactLyricsView` 与锁屏路径不受影响。

## 六、边界

未安装、未启动/替换 App、未操作真实媒体/权限/设备/登录项、未打包提交；未改鼠标命中预筛选（`NotchShape` 预筛选保持已接受版本）、音频、设备、菜单栏、窗口扫描、锁屏；未改歌词时间轴、30Hz 帧率、字体/字距/配色、滚动。停等 Codex 独立验收。
