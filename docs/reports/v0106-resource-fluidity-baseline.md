# V0106：资源与流畅度隔离基线（只测量，不改产品）

执行：现有会话，分支 `codex/final-cleanup`。用户 2026-11-06 授权 CPU/内存与动画同轮、分场景记录。本批只做隔离测量、原始证据与开发测量工具适配；**未改产品行为/UI/动画/刷新节奏，未优化，未打包、未加构建号、未替换或退出 build 15**（PID 69159 仍在运行）。

## 一、入口与仪器核查

| 项 | 结论 |
|---|---|
| `FluidityAudit`（既有 `--audit-fluidity`） | 已是 debug-only、fake 媒体/歌词、无权限/网络/状态项；但含 10 个阶段（约 160s）与两注入屏，不完全覆盖“全关/暂停/音乐关 + 3 分钟保持”顺序，且会建两个面板 |
| `LaunchPolicy` | debug 标志、Release 在 AppKit 前 `exit(2)`；本轮新增 `--audit-resources` 也走同一门控 |
| 新增隔离入口 | `ResourceBaselineAudit.swift`（`#if VALORA_DEVELOPMENT`）+ `--audit-resources`：一个 `WindowCoordinator` 面板、静音 fake `MediaController` 源、fake 歌词；无状态项、无 `NSApp.activate`、无权限/登录项/EventKit/设备/锁屏/网络 |
| 仪器成本 | 1s MainActor 资源采样 + 播放阶段一条 `NSWindow.displayLink` + `LyricsFrameProbe`（默认关闭，仅测量时开）；**这些是本进程额外成本**，生产不启用 |
| 生产文件改动 | 仅 `AppRuntimeDefaults` 增加 `--audit-resources`/`.auditResources`、`LaunchPolicy.developmentFlags` 增加该标志；无生产行为变化。Release 已复核：`--audit-resources` → exit 2 |

Debug `swift build` 与 Release `swift build -c release` 均通过；未跑全量。

## 二、环境与方法

- macOS 27.2（26B123），Apple M1 Pro（10 核），32 GB；内置 Retina 120 Hz，外接 U2701B 60 Hz；QA 面板实际落在内置屏（display-link 回调 ~119.9 Hz，与 120 Hz 一致）。
- 采样：`getrusage(RUSAGE_SELF)` 累计 CPU 秒差 ÷ 墙钟 → 单核 100% 口径；`mach_task_basic_info.resident_size`；`task_vm_info.phys_footprint`；每秒 1 次。
- Timeline 指标：`CompactLyricsView` 的 SwiftUI `TimelineView` body 回调（约 30 Hz），不是 GPU 帧。
- 帧指标：`NSWindow.displayLink` 回调间隔（p50/p95/max），**不是合成/呈现帧**，不能写“60 fps”或与 Alcove 同流畅。
- 唤醒：无可用的非特权工具（`powermetrics` 需权限），**未取，不猜**。
- 原始证据：`docs/verification/v0106/baseline.json`、`samples.csv`（349 行）、`environment.txt`、`command.txt`、stdout/stderr。
  - 首次运行 `baseline-run1-failed-onepause-tick.json` 保留：暂停后 30s 采到 1 个 teardown 帧，检查过严；测量工具延长等待后复跑通过，产品未改。

## 三、场景结果（Debug，单核 100%）

| 场景 | 时长 | CPU% | CPU 秒 | RSS 首/末/均值 (MB) | Footprint 首/末/均值 (MB) | 歌词 ticks | display 回调 (Hz) | p50 / p95 / max |
|---|---|---|---|---|---|---|---|---|
| 全关：音乐关 + 刘海隐藏 | 30s | **0.23** | 0.07 | 56.7 / 56.7 / 56.7 | 13.80 / 13.80 / 13.80 | 0 | — | — |
| 紧凑播放（fake） | 30s | **11.97** | 3.59 | 69.1 / 70.5 / 70.2 | 18.06 / 18.47 / 18.32 | 900 | 119.8 | 8.3 / 8.3 / 17.7 ms |
| 暂停（idle 后） | 30s | **2.18** | 0.65 | 70.9 / 70.8 / 70.8 | 18.58 / 18.53 / 18.53 | **0** | 119.8 | 8.3 / 8.3 / 18.9 ms |
| 歌词关闭（仍播放） | 30s | **4.51** | 1.35 | 70.9 / 71.2 / 71.1 | 18.64 / 18.81 / 18.74 | **0** | 119.3 | 8.3 / 8.3 / 26.9 ms |
| 单次交互（8 步） | 15.1s | **17.87** | 2.69 | 71.3 / 76.4 / 75.7 | 18.89 / 22.11 / 21.65 | 500 | 118.3 | 8.3 / 8.3 / **71.5** ms |
| 持续 3 分钟 fake 播放（长句） | 180s | **10.11** | 18.20 | 76.5 / 78.8 / 78.3 | 22.14 / 22.00 / 22.06 | 5401 | 119.9 | 8.3 / 8.3 / 20.8 ms |
| 保持后暂停 | 30s | **1.92** | 0.58 | 79.0 / 79.0 / 79.0 | 22.19 / 22.16 / 22.17 | **0** | 119.9 | 8.3 / 8.3 / 16.7 ms |

交互 8 步（同一次，不循环）：展开 → 音量展开 → 音量收起 → 收起 → 短句→长句 → 回短句 → fake 换歌/封面 → 换回。

## 四、发现与判断

1. **音乐关闭**：歌词 0 tick、无音乐活动，30s CPU 0.23%。结合 `MediaScheduleTests`（关闭即取消 0.25s 调度）可确认无持续音乐 timer 工作；这是整进程空闲值，不宣称“零 CPU”。
2. **暂停**：Timeline 0 tick；2.18% 来自仍在跑的 display-link 采样、协调器/屏幕观察与隐藏面板的残余工作，**不是歌词刷新**。保持 3 分钟后暂停回落到 1.92%。
3. **歌词关闭仍播放**：Timeline 0 tick；4.51% 来自可见紧凑面板 + 120 Hz 合成/进度渲染 + 采样器，非歌词行。
4. **3 分钟保持**：footprint 22.14 → 22.00 MB（均值 22.06，峰 22.42），**无持续增长**；RSS 76.5 → 78.8 MB（+2.3 MB）后进入稳定，符合分配器波动而非确定泄漏。该结论只限此 3 分钟 Debug 运行。
5. **交互**：RSS +5.1 MB、footprint +3.2 MB（展开/音量/换歌首次挂载），随后 3 分钟保持期不再同步增长；CPU 峰值 17.87%。display-link 最大间隔 71.5 ms 仅出现一次，位于展开/换歌窗口，属**待复核的瞬时抖动**，不是已确认产品卡顿。
6. 回调 p95 稳定在 8.3 ms（120 Hz）；偶发 17–27 ms 间隔存在，未做合成呈现验证。

## 五、不确定项与未覆盖

- **Debug ≠ Release**：无优化、带断言；CPU/RSS 不能当作正式资源成本，需后续 Release 复测。
- display-link 回调 ≠ 合成/呈现帧；无 GPU/WindowServer 帧计数，不能声称 60 fps 或 Alcove 同等流畅。
- 唤醒次数不可得（工具限制）。
- 未运行锁屏音乐卡模拟（会再开第二个窗口，本轮只允许一个 QA 宿主）；真实锁屏/解锁动画未操作，待用户体感与系统工具。
- 未验证物理双屏、真实 QQ 人声逐字同步、真实设备/蓝牙/日历授权；V0103 的 47 项窗口/状态项自动测试仍未执行，不能称全量全部通过。
- 采样器和 display-link 本身抬高播放阶段 CPU（全关 0.23% vs 暂停 2.18% 可作上界参考，但不是干净消融）。

## 六、最小后续建议（本批不执行）

1. 待用户批准后，用 **Release** 同场景复测一次，得到可对外的资源基线；Debug 数字只用于相对比较。
2. 若 Release 空闲仍明显偏高，先用 Instruments/`sample` 区分协调器屏幕观察、display-link（生产没有）与 UI 渲染，再决定是否优化；不按 Debug 百分比改刷新节奏。
3. 对交互中一次 71.5 ms 回调间隔，在 Release + Instruments 下定向复核，不先改动画。
4. 3 分钟无增长只说明短期无泄漏；长时/真实使用仍需后续专项。

## 七、清理与状态

- QA 进程正常 `NSApp.terminate` 退出（exit 0，`RESOURCE BASELINE PASSED`），无遗留 `audit-resources` 进程、无 status item、无权限弹窗。
- build 15 未被退出或替换：PID 69159 仍为 `/private/tmp/valora-v0105-calendar-holidays-only-candidate`。
- 未打包、未加构建号、未覆盖 dist、未安装、未 Git 提交。
- 停等 Codex 独立验收；不继续功能开发或性能修复。

## 八、V0106-R1 更正（不修改上述历史数字）

1. **CPU 口径**：上文“CPU 峰值 17.87%”错误——17.87% 是交互阶段 15 秒的**阶段平均**。用原始逐秒样本（仅取墙钟间隔 ≥0.8s 的完整 1 秒区间）重新差分：
   - 全关 0.23%（均值）/ 0.49%（1 秒峰值）
   - 紧凑播放 11.97% / 17.00%
   - 暂停 2.18% / 8.33%
   - 歌词关闭 4.51% / 11.04%
   - 交互 17.87% / **35.60%**
   - 3 分钟保持 10.11% / 16.03%
   - 保持后暂停 1.92% / 2.44%
   口径为进程累计 CPU 秒 ÷ 墙钟（单核 100%，可因多线程短时超过 100%），分辨率约 1 秒。
2. **暂停 CPU 归因撤回**：上文把 2.18% 归因“120Hz 合成/进度渲染”没有消融或栈证据，**不再作为事实**。可能因素包括 display-link 采样器本身、协调器/屏幕观察、隐藏面板残余工作与过渡帧；未做消融。
3. **“全关”范围**：0.23% 只是 QA 子集（该宿主根本没有 audio/Codex/系统监控服务），**不是正式软件全模块关闭基线**。生产音频 0.5 秒轮询成本尚未测量。
4. **display-link 定义**：上文 p50/p95/max 仅为 `sender.timestamp` 间隔（视频刷新时钟），**不是主线程回调到达延迟，也不是呈现帧**；V0106 未记录 arrival 间隔。落屏也未证明：本次 R1 才记录 `panel.screen`（Built-in Retina Display，120Hz）；`NSScreen.main` 不能证明面板所在屏幕。
5. **固定 elapsed 的限制**：上文长句/换句只测了回调开销，`elapsed` 固定、silent source 无 snapshot，不能证明真实演唱锚推进；R1 用本地带时间戳的 fake snapshot 经现有 `MediaController` 锚验证（见 R1 报告）。
6. **71.5ms**：仅是交互窗口的一次 display-link timestamp 间隔，未在 R1 优化编译短测中复现（最大 17.6ms）；不能据此称已消除或仍有卡顿。
7. 首次运行 `baseline-run1-failed-onepause-tick.json` 保留；原始 `baseline.json`/`samples.csv` 未改动。
