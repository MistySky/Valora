# 原生歌词行原型 R2：边界调度与出栈坐标

执行：原会话、原模型、分支 `codex/idle-cpu-optimization`。按 `docs/opencode-tasks/desktop-lyrics-renderer-directed-r2.md` 与 R1 独立报告返修。不接入生产、不启动/替换 App、不打包、不提交；运行实例仍为 build30（PID 48188）。保留 R1 有效改动与既有生产缓存/seek 修复。

## 一、三个新增失败：先复现后修复

`swift test --filter IndependentNativeLyricsRowTests` 修复前：**7 用例、3 失败**（断言未删改）：

1. 时间轴把下一句 20s→1s 后，`debugBoundaryDelay` 仍 ≈ 19.99998（应 < 1.1）。
2. 速率 1→2 后，唤醒仍 ≈ 20s（应 < 10.1）。
3. 换句后出栈层 `position.x == 0`（短句居中时应为 ≈124.04）。

修复后 7/7 通过。

## 二、改动

### 1. 边界计时器改为“当前快照派生的绝对截止时间”

`NativeLyricsRow.swift`：

- 新增 `boundaryDeadlineUptime`：用**当前墙钟**对当前快照插值出 `elapsedNow`，再由真实后继求得 `deadline = uptime + (boundary - elapsedNow)/rate`。
- 只有**有效截止时间相同（±0.02s）且计时器存在**才复用；时间轴/当前行/播放锚/seek/倍速任一变化都会得到不同截止时间并替换计时器，不会把旧采样点的完整剩余时长从现在重新计时。
- 连续刷新路径：直接注册 30Hz 时钟并清空边界计时器，**不分配**边界计时器；进入静态路径时重新选择截止时间。
- 暂停、隐藏、`stop()`、无下一句（末行）都会取消计时器与截止时间；`boundaryFired` 清空后走同一 `update(at:)` 选行。
- `debugBoundaryDelay` 现在报告“绝对截止时间 − 当前 uptime”，而不是计时器的 `fireDate`。

新增确定性用例（注入时间/真实锚）：

| 用例 | 断言 |
|---|---|
| 旧采样 0.5s | 延迟 ≈ 19.5，不从头重计 20 |
| 向后 seek 到 15s | 延迟 ≈ 5 |
| 向前 seek 到 19.5s | 延迟 ≈ 0.5 |
| 再 seek 回 1s | 延迟 ≈ 19 |
| 静态→逐字（边界唤醒） | 切行后注册 30Hz 时钟 |
| 滚动长句→短句（连续→静态） | 切行后释放时钟且不再常驻 |

独立用例同时覆盖时间轴替换与倍速变化。

### 2. 出栈层保留原横坐标

- 原因：`snapshotOfLine` 先设 `position`，随后 `frame` 以 0 原点覆盖它。
- 修复：用 `bounds` 描述尺寸、单独保留 `position = (contentOriginX - appliedOffset, 0)`。短句居中与长句滚动两种情况下，出栈层 x 与切换前一致；纵向 −26pt、双向淡入淡出与动画所有权逻辑未改。
- 独立用例（居中短句 x≈124）通过；新增用例另覆盖“没有可比较的出栈层时视为失败”（用 `XCTUnwrap`）。

### 3. 其他按任务要求修正

- **reduceMotion**：生产 `CompactLyricsView` 实际固定 0.2s easeInOut；原型原 0.12s 分支来自旧原型、并非生产行为，已删除，统一 0.2s。
- **无障碍标签随自主换句**：新增 `onLineChange` 宿主回调，在真正换句时通知；调试预览 `NativeLyricsRowPreview` 用它维护 `@State currentLine` 作为 `accessibilityLabel`（异步回写，避免在 SwiftUI 更新过程中改状态）。新增用例断言自主切句只通知一次。
  - 未实现部分：生产 `CompactLyricsView` 由视图树自然更新标签，未来接入时必须把该回调接到真实无障碍元素；本轮只验证了调试预览这条链路。
- **像素探针语义**：捕获失败现在直接 `XCTFail`（不再只打印 `capture-failed`）；每次运行把生产/原型图像写到 `/private/tmp/valora-row-r2/` 供审查。

## 三、撤回未经证明的归因（R1 报告更正）

R1 报告把原型与生产的填充/滚动差异归因为“生产按 kern 0.05 测量、按 0 绘制”。**该归因不成立**：两条路径使用同一套 `LyricsLineMetrics` 测量，原型默认也按任务要求用生产实际绘制口径（默认字距）画字。现撤回该结论，不做“接入前必须统一生产字距”的建议。

本轮重新做的定位（单用例、离屏、仅 2x，不跑批量开窗探针）：

| 用例 | 差异像素 | 平均通道差 | 最佳整数位移 | 填充边界（生产/原型） | 墨迹框 |
|---|---|---|---|---|---|
| 逐字填充（词中点后） | 1717/14960（11.5%） | 4.19 | 0（位移无改善） | 217 / 218 px（0.5pt） | 140×23 / 141×23 |
| 中文长句滚动 | 5256/14960（35.1%） | 10.18 | 0（位移无改善） | —（无逐字填充） | 439×25 / 439×24 |

结论（有实际坐标/遮罩/裁剪/栅格化定位）：
- **横向相位一致**：两例最佳整数位移均为 0，说明不是整体滚动/填充坐标偏移。
- **填充边界差 1px**：来自 mask 边缘抗锯齿，不是计算错误（同一公式、同一 metrics）。
- **长句差异来自字形覆盖/栅格化**：墨迹框宽一致（±1px）、行内每行墨迹量不同，属 CATextLayer 与 SwiftUI `Text` 的字形栅格差异；未见裁剪框或坐标差异。
- 仍未定位到单一渲染细节（字体光学尺寸/灰度 AA 权重），因此不宣称视觉等价。

## 四、测试

| 命令 | 结果 |
|---|---|
| `swift test --filter IndependentNativeLyricsRowTests` | 7/7 通过（修复前 3 失败） |
| `swift test --filter NativeLyricsRowPrototypeTests` | 19 通过 + 1 跳过（像素探针），0 失败 |
| 定向组合：`IndependentNativeLyricsRowTests\|IndependentLyricsFrameReplacementTests\|LyricsLineFrameCacheTests\|NativeLyricsRowPrototypeTests\|SeekProgressTests\|DesktopPlayingCadenceTests\|DesktopIdleMediaPublishTests\|DesktopIdleConnectivityPublishTests\|LyricsAnchorInterpolationTests\|MediaScheduleTests\|MediaResponsivenessTests\|MediaControllerRecoveryTests\|IndependentMediaScheduleLifecycleTests\|LyricsTimelineTests\|IndependentLyricsDeadlineTests\|LockLyricsTrackChangeTests\|LyricsServiceTests\|LyricsCacheTests\|PlayingWaveformVisibilityTests` | **117 通过，1 跳过，0 失败** |
| `swift build -c release` | 成功；`nm` 中 `NativeLyricsRow` 计数 0（仍 debug-only） |
| 单用例像素探针（`VALORA_ROW_PIXEL_PROBE=1 VALORA_ROW_PIXEL_CASE=... VALORA_ROW_PIXEL_SCALE=2`） | 2 个用例采集成功，图像在 `/private/tmp/valora-row-r2/` |

## 五、未验项

- 1x、英文、emoji、短句与逐字以外的场景本轮未重跑（避免批量开窗）；R1 的数值仅作历史参考，不作为本轮视觉验收。
- 换句过渡仍只验证计数/终态/快速连切/出栈坐标，未逐帧比对过渡动画像素。
- 自主换句的无障碍标签只在调试预览链路验证，未接入生产视图。
- 边界唤醒的真实长等待端到端（真实 Timer 到点）未做，只用注入时间验证了调度与截止时间计算。
- 锁屏复用未覆盖。
- CPU 无有效对照，**未验**；原型未接入，当前运行版不会因此降 CPU。

## 六、边界

未启动/替换 App、未打包安装、未提交推送；未改锁屏/波形/音频/设备/菜单栏/窗口扫描；既有未跟踪文件保留。
