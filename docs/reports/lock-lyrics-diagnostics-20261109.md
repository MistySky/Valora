# 锁屏歌词有界诊断（2026-11-09）

分支：`codex/lock-screen-idle-cpu`。本批只准备诊断，不改歌词动画/渲染算法/内存策略，不提交或推送 Git。

## 一、证据边界

- 无歌词锁屏约 **3.16%**，有歌词约 **7–8%** 的用户采样来自 Codex 报告；现有调用栈能证明 `NativeLyricsRowClock → update/draw → mask/CA`，但不能用包含式样本算 CPU 占比。
- 因此本轮不把歌词宣称为已确认根因，只增加一个默认关闭、显式环境变量才启用的有界观测工具；普通启动不产生诊断文件或诊断 timer。

## 二、诊断实现

新增 `Sources/Valora/LyricsDiagnostics.swift`，整文件在 `#if VALORA_LYRICS_EXPERIMENT` 内：

- 只有 `VALORA_LYRICS_DIAGNOSTICS_DIR` 指向 `/private/tmp/...` 新子目录时启用；否则无 timer、无文件、无 I/O。
- 每 2 秒写一条 JSONL；最多 12 分钟或 512 KiB，超限停止 timer 并关闭文件；不常驻。
- 注册表只持 `NativeLyricsRowView` 弱引用；不延长 view/window/image/AppModel 生命周期。
- 计数只在现有 native 渲染路径加整数计数：`apply`、`clockTick`、`frameTicks`、`maskUpdates`、`offsetChanges`、draw CA begin/commit、text/image build、layout/hosting/rootView、switch/stop/resume、captureWindow；不改事务、不新增每帧对象/日志。
- JSON 不写标题、歌手、歌词文本/词、来源凭据或原始 timeline；只写角色、布尔、尺寸/计数/时间。

角色由实际调用点标记：

- `desktop-active` / `desktop-passive`
- `desktop-inline`
- `desktop-expanded`
- `lock`

fallback 通过 `ExperimentalDesktopLyricsView` 的 `host.failed` 状态按角色计数；native 实例单独统计。

## 三、启动方式（仅诊断轮使用）

普通启动不要带环境变量。Codex 需要诊断时，用同一候选显式启动：

```bash
VALORA_LYRICS_DIAGNOSTICS_DIR=/private/tmp/valora-lock-lyrics-diag-20261109 \
  open /private/tmp/valora-lock-lyrics-diagnostics-20261109/Valora.app
```

输出：

```text
/private/tmp/valora-lock-lyrics-diag-20261109/lyrics-diagnostics.jsonl
```

字段包括：

- `utc`, `monotonic`
- `systemLocked`, `modelSessionLocked`, `lyricsSwitch`
- `nativeLive`, `nativeActive`, `clockRegistered`
- `fallback`, `fallbackCount`
- 每实例：`id`, `role`, `hasWindow`, `windowVisible`, `active`, `stopped`, `playing`, `rate`, `backend`, `imageFailed`, `clockRegistered`, `boundaryWake`, `boundaryDelay`
- 计数：`apply`, `clockTick`, `frameTicks`, `maskUpdates`, `offsetChanges`, `caBriefs`, `caCommits`, `textBuilds`, `imageBuilds`, `layoutPasses`, `hostingLayouts`, `rootViewUpdates`, `switches`, `stops`, `resumes`, `captureWindows`, `captureCloses`

`draw` 计数不是屏幕实际呈现帧数；`clockTick` 是共享时钟回调计数；`caBriefs/commits` 仅统计 draw 路径。

## 四、验证

- `LyricsDiagnosticsTests` 3 项通过：关闭时无 timer/output；弱注册、fallback、JSONL 字段与无歌词文本；弱引用不延长 view。
- 相关定向回归 71 项通过：waveform 自动恢复、进度隔离、实验歌词 hosting、锁屏 active、pointer 包装。
- 普通无实验 Release 构建成功，二进制中诊断环境变量字符串 **不存在**。
- 未启动带诊断环境的实际锁屏轮次，未操作真实开关/媒体；真实锁屏采样仍待 Codex 与用户。

## 五、候选

- `/private/tmp/valora-lock-lyrics-diagnostics-20261109/Valora.app`
- `1.0.3 (47)`
- binary SHA-256：`65a5272e5c1f189c53c402933390d06af9a368154b40e29b8f23b5eb9d0fdfa9`
- strict/deep 签名通过
- build46 已正常退出，当前唯一 build47 实例 PID `75861`（普通启动，未带诊断环境）
- build46 保留在 `/private/tmp/valora-waveform-return-20261109/Valora.app`

## 六、未验

- 真实锁屏开/关歌词各约 1 分钟的 CPU、内存、栈对照尚未执行；本轮不宣称定位或降幅。
- 诊断 JSONL 的真实窗口/锁屏字段需在 Codex 启动诊断环境后核对；不能用当前无诊断的运行实例冒充。
- 未做压力/批量锁解/反复开关/截图。
