# V0106-R1：基线测量有效性限定补齐

执行：现有会话，分支 `codex/final-cleanup`。只改开发测量工具/报告并做一轮有界短测；未改产品行为/UI/动画节奏，未打包、未加构建号、未替换或退出 build 15（PID 69159 仍为唯一正式实例）。未 Git 提交。

## 一、工具与口径修正

| 缺口 | 修正 |
|---|---|
| 17.87% 被写成“峰值” | 明确为**阶段平均**；新增按原始样本差分的 1 秒峰值 `cpuPeakSingleCore`（只取墙钟 ≥0.8s 的完整区间，避免阶段末零头样本制造假尖峰；分辨率约 1s） |
| display-link 只有 `sender.timestamp` 间隔 | `BaselineGapStats` 分开记录 **timestamp gap**（视频刷新时钟）与 **wall-clock arrival gap**（回调体执行时的 `systemUptime`，含主线程调度）；两者都不是呈现帧 |
| 落屏靠 Hz 猜 | 每个阶段记录**实际 `panel.screen`** 的 name/frame/maxFPS/scale；`NSScreen.main` 不再作为证据 |
| silent fake 无 snapshot | 新增 `AuditTickingMediaSource`：本地生成带 `elapsedTimeMicros`/`timestampEpochMicros`/`playbackRate`/`artworkData` 的 `SystemMediaSnapshot`，经现有 `MediaController` 时间锚推进；fake seek/换歌仅本地 fixture |
| 暂停 CPU 归因 | 撤回“120Hz 合成/进度渲染”的推断，只列可能因素（采样器、协调器/屏幕观察、隐藏面板残余、过渡帧），无消融/栈证据 |
| Debug 成本 | 新增 **release 优化 QA** 独立 scratch 宿主（`-c release` + `-DVALORA_DEVELOPMENT`），只用于仪器，**不是正式 Release 产物**；正式 Release 仍无开发实现并拒绝 flag |
| 短测 | 只跑一轮 ~105s：紧凑播放 30s（fake 真锚）、同状态去 display-link 30s、单次交互 15s、暂停 30s；未重跑 6 分钟/全量 |

新增/修改均为 debug-only（`ResourceBaselineAudit.swift` 及 `--audit-resources-short`）；`AppRuntimeDefaults`/`LaunchPolicy` 只增加该开发标志（Release 拒绝）。Release 复核：`nm` 中 `ResourceBaselineAudit`/`AuditTickingMediaSource` 符号 **0**；`--audit-resources-short` → **exit 2**。

## 二、优化 QA 宿主

| 项 | 值 |
|---|---|
| 构建 | `swift build -c release --scratch-path /private/tmp/valora-v0106-r1-scratch -Xswiftc -DVALORA_DEVELOPMENT` |
| 二进制 | `/private/tmp/valora-v0106-r1-scratch/out/Products/Release/Valora` |
| SHA-256 | `dc421489b65e3e1aad967efeee6c7c1dafc9914e48e5838a0b5d3ddf23e6c031` |
| 标识 | release 优化 + 仅开发定义，未打包、未进入 dist/.build Release 产物 |
| 运行 | `--audit-resources-short docs/verification/v0106-r1` → exit 0，`SHORT BASELINE PASSED` |

## 三、短测结果（优化 QA，单核 100% 口径）

| 阶段 | 时长 | CPU 平均 | CPU 1s 峰值 | RSS 首/末 (MB) | Footprint 首/末 (MB) | Timeline ticks | 换行/换词 | display 回调 | arrival p95/max | timestamp p95/max |
|---|---|---|---|---|---|---|---|---|---|---|
| 紧凑播放（link on） | 30s | 11.20% | 16.53% | 76.8 / 78.5 | 23.74 / 24.22 | 1076 | 3 / 8 | 3586 (119.5Hz) | 9.2 / 20.4 ms | 8.3 / 20.8 ms |
| 同状态（link off） | 30s | 10.95% | 15.72% | 78.5 / 81.3 | 24.25 / 24.80 | 1069 | 3 / 2 | — | — | — |
| 单次交互 | 15s | 14.35% | 32.38% | 83.3 / 86.8 | 29.86 / 27.69 | 597 | 7 / 8 | 1795 (119.8Hz) | 8.9 / **17.1** ms | 8.3 / **17.6** ms |
| 暂停 | 30s | 4.48% | 6.21% | 87.0 / 87.0 | 27.64 / 27.36 | **0** | 0 / 0 | 3590 (119.5Hz) | 8.6 / 25.1 ms | 8.3 / 20.6 ms |

- 面板实际落屏：`Built-in Retina Display`，1728×1117 逻辑点（3456×2234 Retina），**120Hz**；外接 U2701B 60Hz 未承载该窗口。`panel.screen` 与 `NSScreen` 列表见 `docs/verification/v0106-r1/panel-screen.txt`。
- 真实 fake 锚：30s 播放内 `elapsed` 由约 2.0 推进到 32.0（最终行 `第二句短句`），`lineChanges=3`、`wordChanges=8`；link-off 期间继续推进到 62.0（行 `末尾短句`）。这证明不是静止 elapsed 的回调空转。
- 交互 8 步（同一次，不循环）：展开 → 音量开 → 音量关 → 收起 → fixture seek 到 6s（长句）→ seek 到 21s（第二短句）→ fixture 换歌 B（新封面）→ 换回 A；步骤及当时 `elapsed` 见 JSON。
- **display-link 采样开销对照**：同状态 on/off 为 11.20% vs 10.95% 平均、16.53% vs 15.72% 峰值；差值约 0.25/0.81 个百分点，属同一运行内的短对照，不是干净消融。
- **71.5ms 定向复核**：本次 15s 交互最大 timestamp gap 17.6ms、arrival 17.1ms，**未复现**；只说明这一次短测没出现，不能称已消除或不存在卡顿。

## 四、对 V0106 原报告的更正

原报告已追加“V0106-R1 更正”章节，历史数字保留不删：

- 17.87% 为阶段平均；1 秒峰值 35.60%（交互）；其他阶段峰值：全关 0.49、紧凑播放 17.00、暂停 8.33、歌词关闭 11.04、3 分钟保持 16.03、保持后暂停 2.44（均为原始样本差分，≥0.8s 区间）。
- 撤回暂停 CPU 的“120Hz 合成/进度渲染”归因，改为未消融的可能因素。
- “全关 0.23%”仅 QA 子集，不含 audio/Codex/系统监控等生产服务。
- 原 display 统计仅为 timestamp gap，无 arrival，也不是呈现帧；落屏未证明。

## 五、针对性逻辑测试

| 套件 | 说明 | 结果 |
|---|---|---|
| `AuditTickingMediaSourceTests` | 注入时钟下 elapsed/timestamp 推进、暂停冻结、seek/换歌；经真实 `MediaController` 锚推进并选中后一行；gap stats 区分 timestamp/arrival、空值不为 NaN | 4 通过 |
| `LaunchPolicyTests` | 新 flag 映射与 Release 拒绝（含 `--audit-resources-short`） | 14 通过 |
| 合计 | 只跑相关逻辑，未全量 | **18 通过** |

Release 启动门控另以实际二进制复核：`--audit-resources-short` exit 2；正式 Release 无开发实现符号。

## 六、仍未验证（不得冒充）

- 生产音频 0.5 秒轮询成本、真实媒体读取/切歌/seek、真实锁屏/解锁动画、物理双屏、真实 QQ 人声逐字、真实设备/权限弹窗。
- 正式打包 Release 的资源成本；本次是 release 优化 QA 宿主，非 shipping bundle。
- 唤醒次数不可得；display-link 不是呈现帧，无 GPU/WindowServer 帧计数，不宣称 60fps/与 Alcove 同流畅。
- 暂停 4.48% 未做消融，不能归因到单一子系统。
- V0103 的 47 项窗口/状态项自动测试仍未执行。

## 七、证据与清理

`docs/verification/v0106-r1/`：`short-baseline.json`、`samples.csv`（112 行）、`optimized-qa-binary.txt`、`command.txt`、`panel-screen.txt`、`isolation-cleanup.txt`、stdout/stderr。

- QA 宿主正常退出（`SHORT BASELINE PASSED`，无遗留 `audit-resources` 进程）；未动 build 15（PID 69159 仍为唯一正式实例）。
- 未打包、未加构建号、未覆盖 dist、未安装、未 Git 提交。
- 说明：R1 的第一次短跑因暂停后 3 个 teardown 帧触发检查失败（工具等待不足），延长到 5.5s 后复跑通过；该中间 JSON 被覆盖，未保留（V0106 的首败证据仍保留在 `docs/verification/v0106/baseline-run1-failed-onepause-tick.json`）。
- 停等 Codex 独立验收；不继续功能开发或性能修复。
