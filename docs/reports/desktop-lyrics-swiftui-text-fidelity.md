# 歌词文字保真：SwiftUI 静态文字图像后端（首批）

执行：原会话、原模型、分支 `codex/idle-cpu-optimization`。按 Codex 指定方案实现“SwiftUI 按现版样式准备静态文字图像、原生图层逐帧只改遮罩和位移”的隔离后端。未改生产 `CompactLyricsView`、未改字体字距、未启动/替换 App、未打包提交；运行实例仍为 build30（PID 48188）。

## 一、实现

### 1. 后端选择（debug-only，默认仍为原后端）

- `NativeLyricsRowSnapshot.textBackend: NativeLyricsTextBackend`：`.coreText`（默认）与 `.swiftUI`。
- 两个后端共用同一套 R4 选行/播放锚/生命周期/边界时钟/动画所有权；没有第二套时间状态机。
- 全部代码仍在 `#if VALORA_DEVELOPMENT`；Release 二进制中 `NativeLyricsRow`/`StaticLyricText` 符号数为 0。

### 2. 静态文字图像

- `StaticLyricText`：严格使用生产样式——`.font(.system(size: 12, weight: .semibold))`、`.lineLimit(1)`、`.fixedSize(horizontal: true, vertical: false)`，底字 `.gray`，强调字 `Color(nsColor: accent)`；不加 kern/描边/阴影。
- **离屏缓存限制与处理（实测）**：只用“游离”的 `NSHostingView` 抓图时，AppKit 以 1x 渲染再被放大：墨迹比生产多 27%、位置低 4px，属于不可靠输出。改为**一个持久复用的 `NSHostingView` + 单个离屏窗口**（每个原型行一份，窗口不随句子创建），抓图即与生产同 scale、同字形覆盖。
- 文字尺寸由 SwiftUI 实际布局（`fittingSize`）得到；图像按 `行高 17pt × 文字宽度` 渲染，**把生产的 17pt 行容器一起画进图像**，因此纵向位置直接来自生产容器，不使用 CATextLayer 的 −2pt 补偿，也没有新的缩放/取整策略。
- 填充宽度、滚动 offset 仍用既有 `LyricsLineMetrics` / `LyricsLineLayout`，未改测量口径。
- 准备时机：文字/强调色/倍率/后端变化时准备一次；30Hz 帧只改 mask 宽度与 `lineContainer.position`。换句只准备一次。
- 缓存只保留当前行与出栈动画行的图像（出栈层共享同一 `CGImage`，mask 单独复制）；动画结束与 `stop()` 释放；`stop()` 同时清空准备状态，后续宿主更新可重新准备。
- 无障碍沿用 R4 的 `onLineChange` 当前行回调，不把位图当标签。

## 二、保真证据（2x，单窗口复用，不批量开窗）

生产参考（`CompactLyricsView`）与新后端在同一时间/颜色/尺寸/scale 下截图，PNG 保存在 `/private/tmp/valora-row-swiftui-fidelity/`。三张生产参考与对应新后端图的 **SHA-256** 对比：

| 场景 | 新后端差异像素 | 平均通道差 | 墨迹像素（新/生产） | 结论 |
|---|---|---|---|---|
| 中文短句（前奏，居中） | **0/14960（0.0%）** | **0.00** | 709 / 709 | **PNG 字节级相同**（同 SHA-256） |
| 逐字半词填充（0.9s） | **0/14960（0.0%）** | **0.00** | 1973 / 1973，填充边缘 217=217 | **PNG 字节级相同** |
| 长句真实滚动（0→8s 后继，4s 比较，offset>0） | 2582/14960（17.3%） | 1.96 | 5791 / 5506 | 位置/墨迹框一致（0,6,440×25），仍有亚像素相位/AA 差异，**未达字节相同** |

对照旧 CATextLayer 后端（同场景）：4.8%/1.39、11.5%/4.19、38.5%/11.85——即字形偏细/差异在新后端的前两个场景被完全消除；长句滚动的残差从 38.5%/11.85 降到 17.3%/1.96，但仍未归零。

结论（有证据）：**SwiftUI 静态文字图像后端解决了已观察到的字形偏细**（短句、逐字填充与生产逐字节相同）；长句滚动仍有亚像素级差异，未宣称完全等价。1x、emoji、换句过渡帧未做，保留未验。

## 三、准备成本与内存

同一句连续 30 帧（`SwiftUITextFidelityTests`）：

- 文本准备、图像生成、hosting 布局、rootView 更新增量均为 **0**；仅 mask/offset 更新（>5 次）。
- 换句：文本准备 +1、图像 +2（底字+强调字一对），出栈层持有同一图像。
- `stop()`：时钟注销、出栈层释放、图像内容清空（`debugImagePointSize == .zero`），再次投递可重新准备。
- 估算内存（2 张图，4 B/px）：短句 48×34 → 约 13 KB；逐字句 144×34 → 约 39 KB；长句 1169×34 → 约 318 KB。只保留当前行/出栈行，不做每行永久缓存。

计数只是工作量证据，不是 CPU 降幅；本批未测 CPU（无有效对照）。

## 四、测试

| 命令 | 结果 |
|---|---|
| `swift test --filter SwiftUITextFidelityTests` | **9 通过 + 1 跳过**（视觉探针），0 失败 |
| `swift test --filter IndependentNativeLyricsRowTests` | 11 通过 |
| 定向组合：`IndependentNativeLyricsRowTests\|IndependentLyricsFrameReplacementTests\|LyricsLineFrameCacheTests\|NativeLyricsRowPrototypeTests\|SeekProgressTests\|DesktopPlayingCadenceTests\|DesktopIdleMediaPublishTests\|DesktopIdleConnectivityPublishTests\|LyricsAnchorInterpolationTests\|MediaScheduleTests\|MediaResponsivenessTests\|MediaControllerRecoveryTests\|IndependentMediaScheduleLifecycleTests\|LyricsTimelineTests\|IndependentLyricsDeadlineTests\|LockLyricsTrackChangeTests\|LyricsServiceTests\|LyricsCacheTests\|PlayingWaveformVisibilityTests\|SwiftUITextFidelityTests` | **136 通过，2 跳过（两个 opt-in 探针），0 失败** |
| `swift build -c release` | 成功（21.49 秒）；Release 无原型符号 |
| 视觉探针（`VALORA_ROW_SWIFTUI_FIDELITY=1`） | 三场景 × 两后端共 6 张新图 + 3 张生产参考，写入成功；捕获/空图/写盘失败都会使测试失败 |

新后端的 R4 逻辑等价覆盖（均为 `.swiftUI` 后端）：连续换句、暂停 seek、宿主重绘不回跳、隐藏恢复跨边界、61 秒有效锚、停止释放；另有 30 帧零准备与后端切换只准备一次。

## 五、未验项

- 1x、emoji、换句过渡逐帧像素未做。
- 长句滚动的亚像素差异未完全归零（位置/墨迹框一致，均值 1.96），未定位到具体原因。
- CPU 无可比对照，未验；此原型未接入，当前运行版不受影响。
- 无障碍生产接线、锁屏复用未覆盖。

## 六、边界

未安装、未启动/替换 App、未操作真实播放、未打包提交；未改锁屏/波形/音频/设备/菜单栏/窗口扫描；旧证据（`/private/tmp/valora-row-r2/`）保留。
