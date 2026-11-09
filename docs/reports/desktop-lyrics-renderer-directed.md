# 歌词渲染定向任务：缓存修正 + 原生歌词行原型

执行：现有 OpenCode 会话，分支 `codex/idle-cpu-optimization`。未安装/替换运行版、未提交推送；未进入锁屏专项。运行实例仍是 build30（PID 48188）。保留第一批改动、第二批节奏/可见性改动以及 seek 乐观锚修复。

## A. 缓存失效修正（已完成）

独立验收指出的两个失败用例现在都通过：

```
swift test --filter "IndependentLyricsFrameReplacementTests|LyricsLineFrameCacheTests"
→ 8 通过，0 失败（其中 IndependentLyricsFrameReplacementTests 2/2）
```

### 原因与修正

- 原实现用 `nextIndex/nextStart/lineCount` 推断时间轴边界是否仍有效；行数与旧后继槽位相同并不能证明新时间轴里该位置仍是当前行的**第一个**后继。
- 修正（`Sources/Valora/CompactLyricsView.swift`）：每次取帧都先按当前时间轴求出**真实后继起点**（严格大于当前行 `start` 的第一个 `start`，二分查找），把它纳入缓存比较；度量/标签仍按行缓存。
  - 时间轴替换、插入更早的后继、末行变成有后继等情况都会使缓存失效。
  - 不再依赖行数或旧索引；没有每帧全时间轴字符串/hash 或全表扫描。
  - 度量在所有行未变化的重建中复用（新增 `metricsRebuilds` 语义：只在行/身份变化时重新测量）。
- 新增测试：重复时间戳（同一 `start` 不算自己的后继）、空时间轴、±infinity、行尾回退。

### 相邻回归

`LyricsLineFrameCacheTests|IndependentLyricsFrameReplacementTests|LyricsTimelineTests` 全绿；时间轴 `line(at:)` 语义未改。

## B. 原生歌词行原型（未接入生产）

新增 `Sources/Valora/NativeLyricsRow.swift`，整文件包在 `#if VALORA_DEVELOPMENT`：Release 二进制不含任何 `NativeLyricsRow` 符号（`nm`/`strings` 计数为 0），生产路径 `CompactLyricsView` 未改。

### B1. 输入快照（不订阅模型）

`NativeLyricsRowSnapshot`（不可变值）：歌词身份/时间轴、播放锚 `elapsed + sampledAt`、`rate`、`playing`、`duration`、可用宽度、行高、强调色、字距、垂直校准、reduce motion。渲染器不持有 `AppModel`、不查询系统媒体；宿主（未来接入点）负责传入与生产一致的锚，包括 seek 乐观位置。

### B2. 渲染结构

- NSView + CALayer：固定裁剪层 `clipLayer`；内容层 `lineContainer`（只改 `position.x` 做长句滚动）；`baseLayer`（灰色整句）、`accentLayer`（强调色整句）+ `maskLayer`（只改 `bounds.width` 做逐字高亮）。
- 文字在换行/文本/字距/尺寸/scale 变化时准备一次（`textBuilds`）；30Hz 帧只改 mask 宽度与滚动位置，均用 `CATransaction.setDisableActions(true)`，不会引入隐式动画。
- 复用 `LyricsLineMetrics`、`LyricsLineLayout`（填充、跟随偏移、LRC 滑动）、`LyricsPlaybackClock`（锚 + 倍速 + 暂停）与 `LyricsLineFrameCache.nextStart`。业务/解析/网络未改。
- 换句：0.2s easeInOut、±26pt 位移 + 交叉淡出，出栈图层用同一已备字符串重建（`CALayer.copy()` 对 CATextLayer 不可用），动画结束移除并恢复逐帧更新。
- 时钟：共享 30Hz（`NativeLyricsRowClock`，与生产时间轴同分辨率）；仅 `active && playing && rate>0 && 需要连续变化` 时注册；暂停/隐藏/`stop`/`deinit` 注销。静态内容（前奏、空白句、短 LRC 句）不常驻 30Hz，改为在**下一句起点**安排一次性唤醒；唤醒时重新选行、重建并恢复（不漏句切换）。
- 可见性由宿主显式 `setActive`，不用 `window != nil` 推断。
- 无障碍：预览包装设置 `compact.lyrics.native-preview` 标识与行文本标签；行内容本身不重复声明。

### B3. 等价性验证（同一注入时间、同一歌词/尺寸/scale）

数值（与现有公式逐项比较，12 个时间点：前奏、行起点、词中点、跨词、句内后段、换行前、长句起点/滑动、末行前、重复时间戳、最后一行）：**行选择、行尾、填充宽度、滚动偏移全部精确相等（±0.0001）**；另覆盖向后/向前 seek、倍速、暂停。

生命周期/计数（7 项测试，除像素探针外全部常跑）：

| 检查 | 结果 |
|---|---|
| 30 帧连续更新中的文本重建 | 0 次（`textBuilds` 不变） |
| 30 帧中的布局次数 | 0 次（`layoutPasses` 不变） |
| 逐帧 mask 更新 | 递增（>5 次/30 帧，随词推进） |
| 换句 | 文本重建恰好 1 次，换句动画计数 1 |
| 暂停 / 隐藏 | 时钟立即注销；恢复立即重注册 |
| 静态短句 | 不常驻 30Hz，但有下一句唤醒定时器；`stop()` 清理 |

像素（opt-in：`VALORA_ROW_PIXEL_PROBE=1`，离屏窗口、不闪窗；2x）：

| 场景 | 差异像素 | 平均通道差 | 说明 |
|---|---|---|---|
| 前奏短句（居中、无滚动） | 724/14960（4.8%） | 1.39 | 墨迹框 46×23 vs 45×23（1px），字形抗锯齿差异 |
| 逐字词中点 | 1430（9.6%）/1376（9.2%） | 3.62/3.63 | 墨迹框完全一致；填充边缘与 AA 差异 |
| 长句滚动（kern 0） | 5570（37.2%） | 11.35 | 墨迹框 440×25 vs 440×24；无水平错位 |
| 长句滚动（kern 0.05） | 6275（41.9%） | **24.15** | 画字带 0.05 字距后明显变差 |
| 重复时间戳句 / 末句 | 1573（10.5%）/540（3.6%） | 4.68/1.01 | 1px 级墨迹差 |

结论（作为差异记录，不当“等价”）：
1. **布局几何等价**：行、行尾、填充、滚动公式逐项精确一致。
2. **栅格化不等价**：CATextLayer 与 SwiftUI `Text` 的字形抗锯齿不同；静态字词差异约 4.8%（平均 1.4），属渲染栈差异而非布局差异。
3. **基线需要校准**：未校准前原生墨迹整体低 4px（2pt）；校准 `verticalOffset = -2pt`（默认值，注释标明）后墨迹顶/高与首行一致（6..30 vs 6..29）。1x 未验证。
4. **字距不一致（现有实现的既有问题）**：`LyricsLineMetrics` 按 kern 0.05 测量，而 SwiftUI `Text` 实际基本不额外加字距；画面用 0.05 画字时差异从 mean 11.35 升到 24.15。可见现有填充/滚动边界是按 0.05 算、按 0 画的。接入时必须二选一：要么测量与绘制都用同一字距（推荐 kern 0 实测），要么显式给 `Text` 加同样字距。

**按任务要求：存在排版/基线/字距差异，原型不接入生产。** 这些差异已在上面量化，未用“肉眼差不多”声明等价。

### B4. 性能证据边界

- 已测：原型每帧只做一次 mask/位置赋值，文本重建与布局在连续 30 帧内为 0；静态内容不常驻 30Hz。
- 未测：CPU。没有可比环境（不控制真实播放、不启第二个 App）；此前离屏 `TimelineView` 实验在 XCTest 中不节流（~110%），已判定无效、未用作基线；`sample` 等待栈也不用于估算百分点。
- 因此本批**不宣称**任何 CPU 降幅，也不称已找到根因；只提供“每帧更新独立于 SwiftUI 视图构建”的原型与等价性证据。

## C. 测试命令与结果

| 命令 | 结果 |
|---|---|
| `swift build` / `swift build --build-tests` | 成功 |
| `swift build -c release` | `Build complete! (19.72秒)`；二进制无原型符号 |
| `swift test --filter "IndependentLyricsFrameReplacementTests\|LyricsLineFrameCacheTests\|LyricsAnchorInterpolationTests\|NativeLyricsRowPrototypeTests\|SeekProgressTests\|DesktopPlayingCadenceTests\|DesktopIdleMediaPublishTests\|DesktopIdleConnectivityPublishTests\|MediaScheduleTests\|MediaResponsivenessTests\|MediaControllerRecoveryTests\|IndependentMediaScheduleLifecycleTests\|LyricsTimelineTests\|IndependentLyricsDeadlineTests\|LockLyricsTrackChangeTests\|LyricsServiceTests\|LyricsCacheTests"` | **96 通过，1 跳过（像素探针），0 失败**；ReferenceCore 歌词 6 项通过 |
| `VALORA_ROW_PIXEL_PROBE=1 swift test --filter NativeLyricsRowPrototypeTests/testPrototypePixelsAgainstTheShippedRow` | 10 组像素对照全部采集成功（上表） |

## D. 未验项 / 风险

- 像素对照只在 2x；1x、中文标点、日文/emoji、锁屏卡（同一组件未来会复用）未覆盖。
- 换句动画只用计数与曲线参数验证，未逐帧比对过渡过程。
- 静态句“下一句唤醒”只在测试中验证了调度存在，未做真实时间流逝的端到端验证。
- 原型未接入，`CompactLyricsView` 生产路径与之前一致；未打包/替换/提交。
- 若接入，建议顺序：先统一字距口径（测量与绘制一致），再在真实播放上做歌词开/关对照与逐帧录屏比对，最后才切换。

## E. 边界

未安装、未替换运行版、未提交/推送/发布；未改锁屏、波形、音频、设备、菜单栏、窗口扫描；未跟踪文件保留。
