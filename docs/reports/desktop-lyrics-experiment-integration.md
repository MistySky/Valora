# 桌面歌词可回退实验版：接入实现与验证

执行：原会话、原模型、分支 `codex/idle-cpu-optimization`。按 Codex 指定方案实现构建期隔离与仅桌面接线。未打包、未安装、未启动/替换 App、未提交推送；运行实例检查时为未运行。

## 一、构建期隔离（`VALORA_LYRICS_EXPERIMENT`）

- `Package.swift`：仅当构建环境设置 `VALORA_LYRICS_EXPERIMENT=1` 时才给 `Valora` target 添加 `.define("VALORA_LYRICS_EXPERIMENT")`；不会放开 `VALORA_DEVELOPMENT` 到正式构建。
- `NativeLyricsRow.swift`：文件级条件改为 `#if VALORA_DEVELOPMENT || VALORA_LYRICS_EXPERIMENT`；其中 **debug 预览**（`NativeLyricsRowPreview` 及 representable）仍包在 `#if VALORA_DEVELOPMENT`，实验构建不含预览。
- 新增 `LyricsRowExperiment.swift`：
  - `LyricsRowBackend`（编译期常量，报告当前构建选择）与 `LyricsRowFallbackState`（纯状态，无渲染、无开关）始终编译，体量极小；
  - 实验视图 `ExperimentalDesktopLyricsView` 与 `NativeLyricsRowHost` 仅在 `VALORA_LYRICS_EXPERIMENT` 下编译；
  - `DesktopLyricsRow` 在两种构建下都存在：普通构建体内就是 `CompactLyricsView`，实验构建体内切换到实验视图。
- 核验（Release，分开构建）：

| 构建 | 命令 | 符号/字符串证据 |
|---|---|---|
| 普通 Release | `swift build -c release` | `nm`/`strings` 中 `NativeLyricsRow`、`ExperimentalDesktopLyricsView` 计数 **0**；5.42 MB |
| 实验 Release | `VALORA_LYRICS_EXPERIMENT=1 swift build -c release --scratch-path /private/tmp/valora-experiment-build` | 全符号计数 **321**，字符串含 `NativeLyricsRow.swift`、失败日志、`ExperimentalDesktopLyricsView`、`NativeLyricsRowHost`；5.57 MB |

普通包不含实验实现或实验开关；实验产物仅用于本机评估。

## 二、仅桌面接线

`NotchView.swift` 三处桌面歌词调用改为 `DesktopLyricsRow`，并保留原有外层结构（音符、宽度、内边距、裁剪、空白、无障碍、布局）：

- 浮动/紧凑歌词行（`showsCompactLyrics`）：`!lockSurface` 时使用桌面行。
- 刘海内嵌歌词（`showsInlineLyrics`）：原本已是 `!lockSurface`，改为桌面行。
- 展开歌词（`showsLyricsInExpanded`）：`lockSurface` 继续 `CompactLyricsView`，桌面用桌面行。

锁屏 `LockMusicView` 仍直接调用 `CompactLyricsView`，未改动；没有把 `CompactLyricsView` 改成全局开关。

## 三、权威输入与生命周期

实验宿主构造的不可变快照直接来自现有权威状态：

- `model.elapsed` + `model.elapsedSampleDate`（沿用乐观 seek 锚）、`model.playbackRate`、`model.playing`、`model.duration`、`model.lyrics.timeline/identity`、`model.lyricsAccentColor`。
- 宿主**不创建** SwiftUI `TimelineView`；30Hz 由渲染器自己的时钟驱动。
- 可见性使用 `model.notchSurfaceOnScreen` 显式传给 renderer（不以 `window != nil` 判断）；`dismantleNSView` 调用 `stop()`，释放时钟与自有 capture 窗口。
- 多显示器：每个 `NotchView` 实例各自持有实验视图与 renderer 实例，回退状态独立（测试覆盖状态独立）；未改多屏布局。
- 开关、歌词加载/空行、切歌、暂停、seek、倍速、滚动、换句、Reduce Motion 走现有模型与渲染器逻辑（R4 回归保留）。

## 四、失败回退

- 渲染器抓图失败通过 `onRenderFailure` 上报；宿主在**当前视图**上置 `failed`，立即改为渲染生产 `CompactLyricsView`，同时移除原生宿主（`dismantle` → stop → 释放时钟/窗口），**不会同时运行两条 30Hz 链**。
- 回退状态只属于当前视图与当前歌词身份：`LyricsRowFallbackState.updateIdentity` 在曲目身份变化时清除失败，允许重新尝试；同一曲目内保持回退，避免无限重试。
- 不新增用户设置、不注册后台任务；失败不丢字、不保留旧图（渲染器失败时已清空像素与 mask，测试覆盖）。
- 普通构建完全不受影响。

## 五、测试

| 命令 | 结果 |
|---|---|
| 定向组合：`IndependentNativeLyricsRowTests\|IndependentSwiftUITextLifecycleTests\|IndependentLyricsFrameReplacementTests\|LyricsLineFrameCacheTests\|NativeLyricsRowPrototypeTests\|SeekProgressTests\|DesktopPlayingCadenceTests\|DesktopIdleMediaPublishTests\|DesktopIdleConnectivityPublishTests\|LyricsAnchorInterpolationTests\|MediaScheduleTests\|MediaResponsivenessTests\|MediaControllerRecoveryTests\|IndependentMediaScheduleLifecycleTests\|LyricsTimelineTests\|IndependentLyricsDeadlineTests\|LockLyricsTrackChangeTests\|LyricsServiceTests\|LyricsCacheTests\|PlayingWaveformVisibilityTests\|SwiftUITextFidelityTests\|LyricsRowExperimentIntegrationTests` | 执行 **154**，跳过 **7**（opt-in 视觉探针 + 实验构建专属选择用例），**通过 147**，失败 **0**；ReferenceCore 另 6 通过 |
| 实验构建测试：`VALORA_LYRICS_EXPERIMENT=1 swift test --scratch-path /private/tmp/valora-experiment-tests --filter LyricsRowExperimentIntegrationTests` | 4 通过 + 1 跳过（普通构建选择用例），实验选择用例通过 |
| 普通 Release / 实验 Release | 均构建成功，符号核验见上表 |

新增 `LyricsRowExperimentIntegrationTests`（5 项）：普通构建选择生产行、实验构建选择实验行（各自按构建跳过其一）、回退在曲目身份变化前保持、多行回退状态独立、`reset()` 清除失败。

既有原型/缓存/seek/节奏/生命周期/文字保真回归全部保留未改动。

## 六、体验风险与未验项（实验不等于接受）

- 长句滚动仍有 **16–19% 差异像素、平均通道差 1.8–3.6**（统一 harness，bestShift=0）；emoji 7.6%/2.22；换句过渡只验证可采集与位置/在场，**逐帧像素等价未验**。
- 1x、真实多显示器、真实播放、CPU/内存收益均**未验**；本轮帧内零准备只是局部工作量证据。
- 未改字体、字距、歌词时间、帧率或生产渲染来掩盖差异。
- 无障碍标签由 `onLineChange` 维护当前行文本；生产接线尚未在真实 App 中复核。

## 七、可回退方法与下一步

- 回退：不设置 `VALORA_LYRICS_EXPERIMENT` 重新构建即可，普通构建从源码层面不包含实验实现；没有持久化开关或后台状态。
- 本批**未打包、未安装、未启动/替换 App**。是否生成实验候选、如何与 build31 对照，由 Codex 验收后安排；不得以本报告宣称体验或 CPU 已通过。

## 八、边界

未安装、未启动/替换 App、未操作真实播放、未打包提交；未改锁屏/波形/音频/设备/菜单栏/窗口扫描；旧证据与未跟踪文件保留。
