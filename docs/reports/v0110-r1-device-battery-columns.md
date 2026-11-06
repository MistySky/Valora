# V0110-R1：设备电量的三列真对齐（最终）

执行：现有会话，分支 `codex/device-battery-panel`。按用户最终确认改为 `MonitorSummaryCard` 同一 Grid 内**真正三列**，不覆盖 build23 候选；本候选 build24 独立目录。**未启动/替换生产、未提交/推送、未发版**。

## 布局

- 三列与上方 `内存/5H`、`磁盘/WEEK`、`已运行/重置卡` 共用同一 Grid 列宽：
  1. 名称：`AirPods 3`（`.lineLimit(1).truncationMode(.tail)`）
  2. 耳机电量：左右同值 `85%`；不同 `左85% · 右78%`；单侧 `左85%`/`右78%`；未知 `-`
  3. 盒：`盒-`（无可证明新鲜读数，不伪造）
- AirPods Max：中间列显示 `整机85%`（共用 `batteryPercentSingle`，辅助功能注明“整机共享读数”）；未知 `-`；第三列仍 `盒-`。
- 0% 是有效读数；nil/负数/>100 为 `-`。
- 不再使用 `gridCellColumns(3)` 包一整串文字。
- 保留既有：`bluetoothEnabled` 总开关、断行即隐藏、仅识别 AirPods、active 优先、监控/Codex 开关与共享面板路由；刘海/动画/歌词/圆环未改。

## 测试

- `DeviceBatteryRowTests` 9 + `DeviceBatteryRowLayoutTests` 2 + `DeviceBatteryRowCombinationLayoutTests` 1（stats on/off × Codex 有/无 四种组合，400pt 不溢出且设备行确实增高）= **12**
- 加 `MonitorSummaryAccessibilityTests` 4、`CodexUsageSummaryTests` 14、`CalendarMonitorSharedTests` 4 = **34 通过**
- `IndependentDeviceBatteryPreviewTests` 未覆盖/未删；仅将其 `DeviceBatteryRowData` 旧构造适配为 `ears/caseText` 新字段，可继续由 Codex 验收渲染。
- Release 构建通过；`NSHostingView` 实际布局验证 400pt 宽度与四种开关组合。

## 候选

| 项 | 值 |
|---|---|
| 路径 | `/private/tmp/valora-v0110-r1-device-battery-candidate/Valora.app` |
| 版本 / 构建 | `1.0.3` / **24**（自动分配一次；build23 保留未使用） |
| 签名 | `Valora Self-Signed`，DR `identifier "com.wangqing.valora" and certificate leaf = H"3a3b…"` |
| 签名核验 | strict/deep 通过；非 ad-hoc |
| 嵌套框架 | 同证书；adapter `test` exit 0 |
| App binary SHA-256 | `4fb3b22f5a492e9765678594c45ffe8a25ac08f3cc81cf34aaedc522f181cf6c` |
| 运行 | 未启动；当前无 Valora 实例 |

## 限制

- 盒电量仍无可靠数据；`盒-` 固定。
- 未读真实设备/媒体/日历，未触发蓝牙/日历授权；真实断开/重连与系统授权待 Codex/用户实机。
- build23 候选未使用，不覆盖；本候选与报告交 Codex 验收，通过后由 Codex 正常退出旧实例并替换。
