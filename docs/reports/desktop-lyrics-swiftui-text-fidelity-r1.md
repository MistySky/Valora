# SwiftUI 文字缓存 R1：生命周期修复与滚动相位实验

执行：原会话、原模型、分支 `codex/idle-cpu-optimization`。按 `docs/opencode-tasks/desktop-lyrics-swiftui-text-fidelity-r1.md` 返修。未接入生产、未改字体字距、未启动/替换 App、未打包提交；运行实例仍为 build30（PID 48188）。首批短句/逐字 PNG 同 SHA-256 的证据保留。

## 一、三个失败断言：复现与修复

`swift test --filter IndependentSwiftUITextLifecycleTests` 修复前 1 用例 3 断言失败（日志 `/private/tmp/valora-fidelity-review-2026-11-09.log`）：

1. 清空 `timeline` 后旧位图仍然可见。
2. `stop()` 后 capture 窗口仍被 hosting 内容持有。
3. 停止后的行仍留下一个 ordered 的 capture 窗口。

修复后 1/1 通过。

### 修复内容（`NativeLyricsRow.swift`）

- **空 timeline / 空文本是正常状态**：`buildTextLayers` 先判空文本，执行 `clearTextVisuals()`——清空底字/强调字的图层内容与图像、隐藏两个图像层、mask 归零、`textSize/imagePointSize/imagePixelSize` 归零、清掉残余动画与位移；**不请求零宽度抓图**，不沿用上句图片，不重复 `NSLog`。清空后 `preparedText=""`，后续帧不会再次准备。
- **捕获窗口归渲染器所有**：`stop()` 与 `isolated deinit` 调用 `releaseCaptureWindow()`——把复用的 hosting view 从容器移除、`contentView=nil`、`close()`、引用置空；恢复时按需重建一份，正常换句复用同一份窗口。只关闭渲染器自己创建的离屏窗口，不动任何用户窗口。
- 新增证据计数：`captureWindowCreations` / `captureWindowCloses`。
- 恢复路径仍按需重建；`stop()` 清空准备状态，后续宿主投递会重新准备。

### 新增隔离覆盖（`SwiftUITextFidelityTests`，3 项）

| 用例 | 断言 |
|---|---|
| 空文本行 | 图像清除、`imagePointSize == .zero`、**图像生成次数不增**、文本准备 +1 |
| stop → 再投递 | 创建 1 → 关闭 1 → 重建 1（总 2）、hosting 不在窗口内 |
| 正常换句 | 两次 apply 只创建 1 个 capture 窗口 |

独立用例自身也会在 `defer` 里关闭本轮新建窗口，测试之间不泄漏 capture 窗口。

## 二、长句滚动相位实验（不改文字外观）

同一生产参考 / 新后端、同一实际 2x、同一 offset，分别比较 **原始小数位移** 与 **按真实像素网格（1/2pt）落点** 的位移；截图按原样比较，未做任何预平移/重采样。长句 0→8s 有真实后继，取 1.5s（hold 之后）、4.0s、6.5s 三个点（后两者为非整数落点）：

| 时间 | 原始 offset（px） | 原始差异 / 均值 | 网格 offset（px） | 网格差异 / 均值 |
|---|---|---|---|---|
| 1.5s | 16.1667pt（32.33px） | 23.4% / 10.93 | 16.0000pt（32.00px） | 23.9% / 14.50 |
| 4.0s | 150.8896pt（301.78px） | 33.6% / 17.74 | 151.0000pt（302.00px） | 27.0% / 16.19 |
| 6.5s | 285.6124pt（571.22px） | 25.2% / 13.23 | 285.5000pt（571.00px） | 25.3% / 15.05 |

- **没有一致的像素对齐规则**：网格落点在一个点略好、另外两个点更差，且差异远未归零。按任务要求**不引入新规则、不改 `LyricsLineLayout`**，保持原始位移；报告后停止，不继续调参。
- 两次重复运行数值完全一致（确定性）。
- **与首批数字的差异（如实记录）**：首批报告长句滚动为 17.3% / 均值 1.96，本轮同名义时间点为 33.6% / 17.74。两套 harness 的设置不同（首批在同一条行上连续换行后 0.02s 抓图，本轮为独立行、干净状态），说明**首批长句滚动数字不可复现，不能作为保真依据**。短句与逐字填充的字节级相同仍成立（首批独立确认，本轮未重跑该两点）。

## 三、测试

| 命令 | 结果 |
|---|---|
| `swift test --filter IndependentSwiftUITextLifecycleTests` | **1 通过**（修复前 3 断言失败） |
| `swift test --filter SwiftUITextFidelityTests` | 13 通过 + 2 跳过（两个 opt-in 视觉探针），0 失败 |
| 定向组合（R4 同组 + 新后端 + 生命周期）：`IndependentNativeLyricsRowTests\|IndependentSwiftUITextLifecycleTests\|IndependentLyricsFrameReplacementTests\|LyricsLineFrameCacheTests\|NativeLyricsRowPrototypeTests\|SeekProgressTests\|DesktopPlayingCadenceTests\|DesktopIdleMediaPublishTests\|DesktopIdleConnectivityPublishTests\|LyricsAnchorInterpolationTests\|MediaScheduleTests\|MediaResponsivenessTests\|MediaControllerRecoveryTests\|IndependentMediaScheduleLifecycleTests\|LyricsTimelineTests\|IndependentLyricsDeadlineTests\|LockLyricsTrackChangeTests\|LyricsServiceTests\|LyricsCacheTests\|PlayingWaveformVisibilityTests\|SwiftUITextFidelityTests` | 执行 **141**，跳过 **3**，**通过 138**，失败 **0**；ReferenceCore 另 6 通过 |
| `swift build -c release` | 成功（23.05 秒）；Release 中 `NativeLyricsRow`/`StaticLyricText` 符号数为 0 |

跳过项均为 opt-in 视觉探针（两个新后端探针 + 旧原型像素探针），不计入通过。

## 四、图像与证据路径

- 本批：`/private/tmp/valora-row-swiftui-fidelity-r1/`（三个时间点 × 原始/网格落点 + 生产参考，共 12 张 PNG）。
- 首批证据保留：`/private/tmp/valora-row-swiftui-fidelity/`。

## 五、未验 / 限制

- 长句滚动保真：原始与网格落点都未达到像素级一致，且首批 17.3% 数字不可复现，**长句滚动仍列为未验**。
- 1x、emoji、换句过渡逐帧像素未覆盖。
- CPU 无有效对照，未验；原型未接入，运行版不受影响。
- 无障碍标签的生产接线、锁屏复用未覆盖。
- 生命周期验证只覆盖独立测试的窗口清理；未做批量开窗/压力测试。

## 六、边界

未安装、未启动/替换 App、未操作真实播放、未打包提交；未改锁屏/波形/音频/设备/菜单栏/窗口扫描；旧证据保留。
