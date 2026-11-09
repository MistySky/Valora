# 原生歌词行原型 R4：删除 60 秒回退，统一时钟注入

执行：原会话、原模型、分支 `codex/idle-cpu-optimization`。按 `docs/opencode-tasks/desktop-lyrics-renderer-directed-r4.md` 与 R3 独立报告收尾。只做时间语义；未改视觉、未接入生产、未启动/替换 App、未打包、未提交。运行实例仍为 build30（PID 48188）。

## 一、复现

`swift test --filter IndependentNativeLyricsRowTests` 修复前：**11 用例、1 失败**——`testValidPlaybackAnchorOlderThanOneMinuteStillInterpolates`（真实 61 秒龄锚，歌词甲 0、乙 60，仍显示甲）。断言未删除、未改写。

修复后 11/11 通过。

## 二、改动

### 1. 删除按锚年龄退回采样时间的规则

- 删除 `displayTime(for:)` 中 `abs(now - sampledAt) <= 60` 的阈值回退；**没有**新增阈值、没有按 XCTest/环境识别的分支。
- 显示时刻永远来自时钟，播放锚只参与插值：61 秒、61 分钟还是更久的有效锚都按当前显示时间推进。
- 真正 seek（新锚）与暂停（`playing=false` 时插值固定为锚）语义未改。

### 2. 自动入口统一使用同一时钟

`currentDisplayTime()`（生产默认 `Date()`，测试可注入 `debugNow`）现在用于：

- 宿主 `apply`；
- `setActive(false→true)` 的追赶刷新；
- 静态边界截止时间计算与边界唤醒；
- 30Hz 共享时钟 tick（改为每视图向自己的时钟取时，不再由共享时钟统一传 `Date()`）；
- 布局回调、窗口回调；
- 换句动画结束后的重绘。

显式 `render(at:)` 仍接受外部时刻，供确定性验证。现在源码中唯一的 `Date()` 是 `currentDisplayTime()` 的生产默认值（`debugNow?() ?? Date()`）。

### 3. 固定锚测试改为注入匹配时钟（断言不变）

- 独立测试文件（`IndependentNativeLyricsRowTests.swift`）4 个使用固定 1970 锚的用例，各加一行 `view.debugNow = { anchor }`：连续换句、时间轴替换后的行尾、末行时长、字距重建。**只注入时钟，未改任何断言。**
- 原型测试文件 7 个固定锚用例同样注入：倍速/暂停、30Hz 计数、换句重建、暂停/隐藏/静态、滚动长句→短句、seek 后选行、暂停恢复。
- 真实时间用例（真实 Timer 换句、恢复跨边界、宿主重入、61 秒锚等）保持默认实时钟，未改为合成时间。

## 三、测试

| 命令 | 结果 |
|---|---|
| `swift test --filter IndependentNativeLyricsRowTests` | **11 通过，0 失败**（修复前 1 失败） |
| `swift test --filter NativeLyricsRowPrototypeTests` | **23 通过 + 1 跳过**（像素探针），0 失败 |
| 定向组合：`IndependentNativeLyricsRowTests\|IndependentLyricsFrameReplacementTests\|LyricsLineFrameCacheTests\|NativeLyricsRowPrototypeTests\|SeekProgressTests\|DesktopPlayingCadenceTests\|DesktopIdleMediaPublishTests\|DesktopIdleConnectivityPublishTests\|LyricsAnchorInterpolationTests\|MediaScheduleTests\|MediaResponsivenessTests\|MediaControllerRecoveryTests\|IndependentMediaScheduleLifecycleTests\|LyricsTimelineTests\|IndependentLyricsDeadlineTests\|LockLyricsTrackChangeTests\|LyricsServiceTests\|LyricsCacheTests\|PlayingWaveformVisibilityTests` | **126 通过，1 跳过，0 失败** |
| `swift build -c release` | 成功（18.96 秒）；`nm` 中 `NativeLyricsRow` 计数 0（仍 debug-only） |

## 四、未验项（不变）

- 视觉保真（原型字形偏细）仍是独立门槛，本轮未改字体/字距/绘制，未重跑像素探针。
- 边界唤醒真实长等待、无障碍标签的生产接线、锁屏复用未覆盖。
- CPU 无有效对照，**未验**；原型未接入，运行版不受影响。

## 五、边界

未启动或替换 App、未打包安装、未提交推送；未改锁屏/波形/音频/设备/菜单栏/窗口扫描；既有未跟踪文件保留。
