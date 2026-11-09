# 原生歌词行原型 R3：显示时刻与播放锚语义统一

执行：原会话、原模型、分支 `codex/idle-cpu-optimization`。按 `docs/opencode-tasks/desktop-lyrics-renderer-directed-r3.md` 与 R2 独立报告修复。仅改时间语义；未改字体/字距/视觉、未接入生产、未启动/替换 App、未打包、未提交。运行实例仍为 build30（PID 48188）。

## 一、两个新增失败：先复现后修复

`swift test --filter IndependentNativeLyricsRowTests` 修复前：**10 用例、2 失败**（断言未删改）：

1. `testReapplyingSameAnchorAfterAutonomousSwitchDoesNotRewind`：Timer 自主切到乙后，宿主用同一锚重绘，`apply` 按 `sampledAt` 显示又回到甲。
2. `testReactivatingStaticLineCatchesUpAcrossMissedBoundary`：隐藏期间跨过乙的边界，恢复后仍显示甲（边界已过，计算出的截止时间为 nil）。

修复后 10/10 通过。

## 二、改动

### 1. `apply` 的显示时刻 = 当前时间，`sampledAt` 只作播放锚

- 新增可注入时钟 `debugNow`（生产默认 `Date()`）。
- `apply` 不再用 `sampledAt` 作为显示时刻，而是用“当前显示时刻”插值；因此：
  - 宿主用同一锚重绘不会回跳（不是 seek）；
  - **首次锚延迟到达**时显示当前进度而不是旧采样点；
  - 真正的 seek 通过新锚生效（不使用 `max(previous, now)`，不阻止真实回退）。
- 防止“非真实时钟”的锚被外推成几十年：只有 `|now - sampledAt| ≤ 60s` 才把 now 当作显示时刻，否则退回 `sampledAt`。生产锚通常在 1–2 秒内，不受影响；这条规则在两份使用 1970 合成锚的旧用例里生效，未修改它们的断言。（明确披露：这是对“非当前锚”的保护，不是让生产默认读采样时间。）

### 2. 恢复可见先追进度，再决定时钟

- `setActive(false→true)`：先用同一“当前显示时刻”执行一次 `update(at:)`（选行、高亮、滚动、行尾全部刷新），再决定注册 30Hz 还是安排边界唤醒；隐藏期间错过的边界会被补上。
- 重复 `true` 幂等：不做强制重建，也不重置动画。
- 动画清理回调：**总是**释放本轮拥有的出栈层，但只有 `active && !stopped` 时才重绘；隐藏后不会被清理回调重新激活渲染。

### 3. 时间语义一致 + 可注入时钟

- `apply`、30Hz tick、边界唤醒、布局回调、清理重绘都走 `update(at:)`；自动入口统一用当前显示时刻（或注入时钟）。
- 显式 `render(at:)` 保留，供确定性验证。
- 固定 1970 锚的几何用例继续按锚显示（受上面的 60s 保护规则），未改断言、未弱化测试。

### 4. 新增隔离用例（5 项）

| 用例 | 覆盖 |
|---|---|
| 首次锚延迟 0.2s 且已跨静态边界 | 直接显示乙，且高亮 > 0 |
| 隐藏跨边界后恢复 | 显示乙且高亮刷新 |
| 宿主回调重入（onLineChange → apply 同一锚） | 只通知 1 次、不多切换、不回跳 |
| 暂停 | 等 0.2s 后再次 apply，进度保持暂停值 |
| 真实前后 seek | 甲→丙→乙 正确切换 |

真实的“Timer 在无宿主更新时换句”用例（独立测试）继续通过。

## 三、视觉

- 本批**不改**字体、字距、绘制或生产路径，**未重跑**批量像素探针。
- R2 独立观察到的“原型字形偏细”仍作为**未验门槛**保留：数学等价不等于视觉等价，本轮不宣称满足体验要求，也不宣称 CPU 改善。视觉方案由 Codex 单独决策。

## 四、测试

| 命令 | 结果 |
|---|---|
| `swift test --filter IndependentNativeLyricsRowTests` | **10 通过**（修复前 2 失败） |
| `swift test --filter NativeLyricsRowPrototypeTests` | **23 通过 + 1 跳过**（像素探针），0 失败 |
| 定向组合：`IndependentNativeLyricsRowTests\|IndependentLyricsFrameReplacementTests\|LyricsLineFrameCacheTests\|NativeLyricsRowPrototypeTests\|SeekProgressTests\|DesktopPlayingCadenceTests\|DesktopIdleMediaPublishTests\|DesktopIdleConnectivityPublishTests\|LyricsAnchorInterpolationTests\|MediaScheduleTests\|MediaResponsivenessTests\|MediaControllerRecoveryTests\|IndependentMediaScheduleLifecycleTests\|LyricsTimelineTests\|IndependentLyricsDeadlineTests\|LockLyricsTrackChangeTests\|LyricsServiceTests\|LyricsCacheTests\|PlayingWaveformVisibilityTests` | **125 通过，1 跳过，0 失败** |
| `swift build -c release` | 成功（21.23 秒）；`nm` 中 `NativeLyricsRow` 计数 0（仍 debug-only） |

## 五、未验项 / 风险

- 视觉保真（字形粗细/覆盖）仍未验；本轮刻意不改视觉。
- 60s 保护规则只由合成锚用例间接覆盖，未单独做边界值测试（如 59s/61s）；生产锚远小于该范围。
- 边界唤醒的真实长等待仍未端到端执行（用注入时间验证调度与截止计算）。
- 无障碍标签链路只在调试预览验证。
- 锁屏复用未覆盖；CPU 无有效对照，未验。

## 六、边界

未启动或替换 App、未打包安装、未提交推送；未改锁屏/波形/音频/设备/菜单栏/窗口扫描；既有未跟踪文件保留。
