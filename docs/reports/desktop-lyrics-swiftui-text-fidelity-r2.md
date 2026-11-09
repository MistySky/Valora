# 歌词文字缓存 R2：失败处理与保真验证

执行：原会话、原模型、分支 `codex/idle-cpu-optimization`。按 `docs/opencode-tasks/desktop-lyrics-swiftui-text-fidelity-r2.md` 与 R1 独立报告返修。仍为 debug-only 隔离原型；未接入生产、未改字体字距、未启动/替换 App、未打包提交。

## 一、抓图失败处理（原子提交 + 显式状态）

`buildTextImages` 现在：

- 先 `prepareTextHostWindow()`，再测量、再抓图（见第三节的顺序修正）。
- 底字与强调字两张图**一起成功才提交**；任一失败调用 `failTextImages`：
  - 清除当前旧图像、mask、几何与出栈图层（代次递增，旧清理回调失效）；
  - 记录 `imageRenderFailed = true`、`imageRenderFailures += 1`；
  - 标记已准备输入（避免 30Hz 每帧重试），但**不视为成功缓存**，也不静默切换后端。
- **空行/空时间轴**在进入图像路径前处理，清除视觉状态并标记完成，**不算失败**、不抓零宽图。
- 失败后的重试只发生在**宿主更新**（`apply`）时一次；连续帧不重试。恢复成功后 `imageRenderFailed = false`。
- `stop()`/deinit 关闭并释放自有 capture 窗口与 hosting 引用，失败状态与像素一并清理。

### 可注入失败 seam 与测试（5 项，全通过）

`debugFailImageRender: Set<Int>`（1 = 第一张失败，2 = 第二张失败，可注入多个）。

| 用例 | 覆盖 |
|---|---|
| 第一张失败 | 失败状态、旧图清除、失败计数 +1、无回退 |
| 第二张失败 | 同样的原子性（强调图失败不留下底图） |
| 失败后宿主更新 | 清除 seam 后同一文本的宿主更新可重试并恢复 |
| 失败后 stop | capture 窗口关闭计数 +1、无像素、无出栈层 |
| 空行 | `imageRenderFailed == false`、失败计数 0 |

## 二、统一参考 harness 与上一批 1.96 / 17.739 的解释

新的 `testLongLineUnifiedReferenceHarness` 在**同一窗口、同一 2x、同一颜色/尺寸/锚/时间轴**下，等待切行动画结束（断言 `outgoing == 0`、无活动动画）后再截图；逐点记录：行选择、行尾、逻辑 offset、容器实际 position、contentsScale、位图尺寸、是否有活动动画，并保存原图。

| 时间 | 行尾 | 逻辑 offset | 容器 position | 位图 | 差异 / 均值 | bestShift | 墨迹（新/生产） |
|---|---|---|---|---|---|---|---|
| 1.5s | 8.0 | 16.1667 | (−16.1667, 0) | 440×34 | 19.4% / 3.570 | 0 | 5638 / 5179 |
| 4.0s | 8.0 | 150.8896 | (−150.8896, 0) | 440×34 | **17.3% / 1.957** | 0 | 5791 / 5506 |
| 6.5s | 8.0 | 285.6124 | (−285.6124, 0) | 440×34 | 16.0% / 1.820 | 0 | 5634 / 5339 |

**上一批 1.96 与 17.739 之差已定位并消除**：

- 两份旧抓图（首批 17.3% 与 R1 33.6%）在**平移 1 个设备像素后完全相同**（`differing=0`），说明差异是 1px 相位，而非渲染后端。
- 根因是**测量时机**：同一段文字，`NSHostingView` 在**未挂窗口**时 `fittingSize.width = 585.0`，挂到离屏 capture 窗口后为 **584.5**（0.5pt = 1 设备像素）。首批 harness 在挂窗口后测量（584.5，均值 1.96），R1 harness 在窗口创建前测量（585.0，均值 17.739）。
- 修复：`buildTextImages` 先建立 capture 窗口再测量，测量与渲染处于同一环境；统一 harness 的三个点现在稳定在 **16–19%、均值 1.82–3.57，bestShift=0**，不再出现 1px 整体相位差。

长句仍有 **16–19% 的差异像素（均值 1.8–3.6）**：宽高、位置、墨迹框一致且无整数相位差，剩余为分数位移下的亚像素采样/抗锯齿差异。没有证据支持某个最小像素取整修正；按任务要求**记录并停止**，未改 `LyricsLineLayout`、未做像素量化、未降帧、未换架构。

## 三、补受限视觉验证（同一复用画布，2x）

- **Emoji**（`你好 🎵 世界`）：差异 **7.6%，均值 2.22，bestShift=0**；墨迹非空，图为 `emoji-*.png`。
- **换句关键帧**：切换后 50ms / 150ms 各截一帧。两帧都记录到 `anim=1`、`outgoing=1`（出栈层在场）、合成墨迹 3006、bbox 稳定（89,6,261×24），图像为 `switch-050ms.png` / `switch-150ms.png`。**未做逐帧像素等价断言**：SwiftUI 与 CA 的动画时序在本离屏 harness 中不同步，只证明能采到过渡帧并记录位置/在场状态，过渡像素等价仍未验。
- **1x**：当前环境没有真实 1x 显示，未以 2x 重采样冒充，**未验**。

## 四、其它要求

- 同一句连续 30 帧：文本准备、图像生成、hosting 布局、rootView 更新增量仍为 0（既有用例继续通过）；换句只准备一对图像；缓存只保留当前/出栈行；`stop()` 释放窗口与图像。
- 生产路径未改；所有新代码仍在 `#if VALORA_DEVELOPMENT`；Release 中 `NativeLyricsRow`/`StaticLyricText` 符号数为 0。

## 五、测试

| 命令 | 结果 |
|---|---|
| 定向组合（R1 同组 + 新后端 + 生命周期）：`IndependentNativeLyricsRowTests\|IndependentSwiftUITextLifecycleTests\|IndependentLyricsFrameReplacementTests\|LyricsLineFrameCacheTests\|NativeLyricsRowPrototypeTests\|SeekProgressTests\|DesktopPlayingCadenceTests\|DesktopIdleMediaPublishTests\|DesktopIdleConnectivityPublishTests\|LyricsAnchorInterpolationTests\|MediaScheduleTests\|MediaResponsivenessTests\|MediaControllerRecoveryTests\|IndependentMediaScheduleLifecycleTests\|LyricsTimelineTests\|IndependentLyricsDeadlineTests\|LockLyricsTrackChangeTests\|LyricsServiceTests\|LyricsCacheTests\|PlayingWaveformVisibilityTests\|SwiftUITextFidelityTests` | 执行 **149**，跳过 **6**（opt-in 视觉探针），**通过 143**，失败 **0**；ReferenceCore 另 6 通过 |
| 视觉探针（`VALORA_ROW_SWIFTUI_FIDELITY=1`） | 统一 harness 3 点、emoji、换句 2 帧全部采集并写盘；抓图失败/空图/写盘失败都会使测试失败 |

## 六、未验 / 风险

- 长句滚动仍是 16–19% 差异像素（mean 1.8–3.6），未达像素等价；未找到可证明的最小修正，保留现状。
- 换句过渡只验证了可采集与位置/在场，未做逐帧像素等价。
- 1x 未验；CPU 无有效对照，未验。
- 无障碍生产接线、锁屏复用未覆盖。

## 七、边界

未安装、未启动/替换 App、未操作真实播放、未打包提交；未改锁屏/波形/音频/设备/菜单栏/窗口扫描。新图：`/private/tmp/valora-row-swiftui-fidelity-r2/`；旧证据保留。
