# 原生歌词行原型 R1 返修

执行：现有 OpenCode 会话，分支 `codex/idle-cpu-optimization`。按 `docs/opencode-tasks/desktop-lyrics-renderer-directed-r1.md` 与独立验收报告返修。未接入生产、未启动/替换 App、未打包安装、未提交；运行实例与上一轮一致（build30，PID 48188）。保留 seek 乐观锚与已通过的生产缓存修正。

## 一、四个失败用例复现与修复

先复现：`swift test --filter IndependentNativeLyricsRowTests` → **4 用例、5 个断言失败**，未删除或弱化任何断言。修复后 4/4 通过。

### 1. 持续播放不自行切句（已修）

- 原因：`render` 只推进已有行内的词，不按插值时间重新选行；`clockTick` 直接调用它，连续模式又跳过边界定时器。
- 修复：所有入口（宿主 `apply`、30Hz `clockTick`、静态边界唤醒、布局回调）都走**同一个 `update(at:)`**：先用同一个插值时间 `line(at:)` 选行，跨行才 `switchLine`（准备文字 + 一次换句动画），随后重算行尾、几何、填充/滚动，并重新决定“连续刷新 or 静态下一边界唤醒”。宿主采样频率未提高。
- 新增隔离用例：滚动长 LRC → 短行（切句后自动释放 30Hz 时钟）、静态行 → 逐字行（边界唤醒后注册时钟）、暂停/恢复、向前/向后 seek。

### 2. 当前行不变时沿用过期行尾（已修）

- 修复：行尾失效与文字重建**分离**。每帧按当前时间轴调用生产同款 `LyricsLineFrameCache.nextStart` 求真实后继，并为末行按时长回退；不再依赖 `prepare`。纯行尾变化不重建文字、不重播动画。
- 通过独立用例：后继 20s→10s（行数/Slot 不变）立即生效；末行 duration 100→120 立即生效。
- 新增用例：行尾更新后 `textBuilds` 不变、`lineSwitchAnimations == 0`。

### 3. 绘制属性变更未重建文字（已修）

- 失效条件拆开：
  - 文本或字距变化 → 重建 attributed string、重新测量、重排；
  - 强调色变化 → 只替换强调层字符串，不重新测量、不换句；
  - `verticalOffset`/宽高变化 → 只重排；
  - backing scale 变化 → 更新 `contentsScale`（新增隔离注入 `debugSetBackingScale`）。
- 绘制口径保持生产原样：原型按生产 `Text` 的实际绘制（默认字距 0）画字，测量仍沿用生产 `LyricsLineMetrics`；没有通过统一生产字距或改样式来迁就原型。
- 独立用例：kern 0→2 后测量宽度显著变宽；新增用例覆盖颜色、倍率、`verticalOffset` 各自只做自己的失效。
- 每帧的 `lastLineKey` 字符串已移到真正的换句路径，`draw` 不再构造。

### 4. 换句动画不等价（已修）

- 保留 0.2s `easeInOut`、±26pt 位移，并补上**双向淡入淡出**（生产 `.combined(with: .opacity)` 对应）。
- 出栈层模型终态直接设为 `opacity=0`、`ty=-26`，移除动画后不会闪回。
- 代次/所有权：每次换句递增 `switchGeneration`，清理回调只有在代次仍匹配且出栈层属于本轮时才执行；快速连续换句不会误删新动画；`stop()` 递增代次并禁止清理回调重新激活渲染。
- 动画结束按 `max(当前时间, 最近渲染时间)` 重绘，不回退到旧 `sampledAt`。
- 新增用例：甲→乙→丙快速连切（2 次动画、最多 1 个出栈层、结束后出栈层为 0、最终仍为丙）；动画结束重绘时间前进且高亮不回退。
- reduce motion 沿用原参数（0.12s），未新增策略。

## 二、测试

| 命令 | 结果 |
|---|---|
| `swift test --filter IndependentNativeLyricsRowTests` | 4/4 通过（修复前 4 用例、5 断言失败） |
| `swift test --filter NativeLyricsRowPrototypeTests` | 15 通过 + 1 跳过（像素探针），0 失败 |
| 定向组合：`IndependentNativeLyricsRowTests\|IndependentLyricsFrameReplacementTests\|LyricsLineFrameCacheTests\|NativeLyricsRowPrototypeTests\|SeekProgressTests\|DesktopPlayingCadenceTests\|DesktopIdleMediaPublishTests\|DesktopIdleConnectivityPublishTests\|LyricsAnchorInterpolationTests\|MediaScheduleTests\|MediaResponsivenessTests\|MediaControllerRecoveryTests\|IndependentMediaScheduleLifecycleTests\|LyricsTimelineTests\|IndependentLyricsDeadlineTests\|LockLyricsTrackChangeTests\|LyricsServiceTests\|LyricsCacheTests\|PlayingWaveformVisibilityTests` | **111 通过，1 跳过，0 失败** |
| `swift build -c release` | 成功（20.86 秒）；`nm`/`strings` 中 `NativeLyricsRow` 计数为 0，原型仍为 debug-only |

新增隔离用例 10 项：长 LRC→短行、静态→逐字、暂停/恢复、前后 seek、强调色/倍率、字距与垂直校准、纯行尾更新、快速连续换句、动画结束状态与重绘时间。

## 三、视觉证据（opt-in 像素探针：`VALORA_ROW_PIXEL_PROBE=1`）

同一注入时间、同一歌词/宽度，原型 vs 生产 SwiftUI 行；1x 与 2x 分别按目标像素尺寸重绘后比较（差异像素阈值：单像素 RGB 和 > 12）：

| 场景 | 1x 差异 / 平均通道差 | 2x 差异 / 平均通道差 | 墨迹框（生产/原型） |
|---|---|---|---|
| 中文短句 | 5.7% / 1.33 | 4.8% / 1.39 | 23×12 / 23×12；46×23 / 45×23 |
| 英文短句 | 11.5% / 3.39 | 9.0% / 3.47 | 65×9 / 66×9；131×20 / 131×19 |
| 中英+emoji | 14.4% / 3.18 | 10.4% / 2.87 | 70×16 / 71×15；141×30 / 141×29 |
| 逐字填充（词中点后） | 16.7% / 6.51 | 14.1% / 7.11 | 墨迹框一致；填充边缘不同 |
| 中文长句滚动 | 45.2% / 9.96 | 35.1% / 10.18 | 墨迹框一致（整行满宽） |

结论：
- **布局一致**：所有场景墨迹框相同或 ±1px（行选择、填充基准、滚动量由同一公式）。
- **栅格化不同**：静态短句差异 4.8%–14.4%、均值 1.3–3.5，来自 CATextLayer 与 SwiftUI `Text` 的抗锯齿/字形栅格差异，不是排版差异。
- **动画态差异更大**（均值 6.5–10.2）：生产用 kern 0.05 算填充/滚动边界、却用默认字距画字；原型按生产实际绘制（字距 0）画，因此填充边缘与滚动相位天然差几像素。**这是生产既有的度量/绘制口径不一致**，接入前必须先统一（建议实测 kern 0），不能靠改生产样式来迁就原型。
- 未声称“体感等价”；以上只说明公式与墨迹框层面的一致性及剩余差异来源。

## 四、性能

- 计数证据：连续 30 帧文本重建 0、布局 0、仅 mask/位置更新；换句文本重建恰好 1；静态句不常驻 30Hz。
- CPU：**未验**。无真实播放的可比环境；此前离屏 `TimelineView` 实验无效，未用作基线；不根据 `sample` 等待栈推算。原型未接入，当前运行版不会因此降 CPU。

## 五、未验项 / 风险

- 换句过渡只做了计数/终态/快速连切验证，未逐帧比对过渡动画的像素。
- 1x 比较使用同一套离屏重绘（非真实 1x 显示器）；emoji 覆盖为中英混排，未覆盖复杂 ZWJ 组合。
- 下一句唤醒的真实时间流逝（等待定时器实际触发）只用注入时间验证了选择路径与延迟计算，未做长等待端到端。
- 锁屏卡复用同一组件仍未覆盖（锁屏专项未开）。
- 原型未接入生产；`CompactLyricsView` 未改。

## 六、边界

未启动或替换 App、未打包安装、未提交推送；未改锁屏/波形/音频/设备/菜单栏/窗口扫描；既有未跟踪文件保留。
