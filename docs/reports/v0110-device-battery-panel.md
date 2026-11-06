# V0110：监控卡内设备电量行（最终规格）

执行：现有会话，分支 `codex/device-battery-panel`。按用户最终确认实现；**未替换/启动生产 App、未读真实设备/媒体/日历、未提交/推送、未发版**。当前构建号仍为 22（上次正式），本候选第一次使用 23。

## 最终规格落地

- 位置：`MonitorSummaryCard` 的同一 Grid 内，监控摘要/Codex 之后的**完整一行**（`gridCellColumns(3)`），纯文字、无图标；有前列时上方保留 1pt 分隔线。
- 格式：
  - 普通 AirPods：`AirPods 3  左85%  右85%  盒-`；左右同值也分别显示，不合并。
  - AirPods Max：`AirPods Max  左85%  右85%  盒-`，左右共用 `batteryPercentSingle` 的整机读数；辅助功能说明“左右为整机共享读数”。
  - 缺失项逐个显示 `-`；真实 0% 显示 `0%`；越界/`nil` 均为 `-`。
  - 盒电量当前始终 `盒-`：NativeBridge 只读 left/right/single，没有可证明新鲜的盒读数，不伪造、不显示无效数据。
- 控制：仅受设置里的**设备连接总开关** `bluetoothEnabled` 控制；关闭整行立即隐藏；开启且有已连接耳机才显示，断开隐藏。没有新增独立开关。
- 识别：只认可靠 AirPods（`isAirPods` 或 `AirPodsModel.identify(modelUID:)`）。不再用“任意有效电量”推断耳机，MX Master/键盘/鼠标等即使有电量也不会显示。
- 选择：优先 `active` 的已识别 AirPods，其次第一个已连接 AirPods；只显示一行。
- 路由：监控/Codex 关闭时不新增菜单栏入口；共享面板仍可由现有日历入口打开。只要有设备行，卡片仍渲染该行；监控/Codex/设备都无内容时卡片不出现，保持原语义。
- 未改：刘海紧凑/展开/连接动画/圆环/歌词/设备弹窗；未改 400pt 面板宽度、字号、间距。

## 文件与实现

| 文件 | 改动 |
|---|---|
| `Sources/Valora/DeviceBatteryRow.swift`（新增） | `DeviceBatteryRowData` + 纯 `DeviceBatteryRow`：识别 AirPods、选择、`左/右/盒` 文本、0/`-` 规则、辅助功能文本 |
| `Sources/Valora/CalendarMonitorSharedView.swift` | 新增 `MonitorSummarySection`（观察 `AppModel.devices` 与 `bluetoothEnabled`）；`MonitorSummaryCard` 增加设备行并跨 3 列；摘要无障碍追加设备行 |
| `Sources/Valora/MenuBarModuleController.swift` | 可选传入 `appModel/settings`，共享面板构建时传给视图 |
| `Sources/Valora/AppDelegate.swift` | `setupMenu` 传 `model/settings`；`--preview-menu-modules` 增加仅本地的 AirPods Pro fixture（85/78）供隔离预览 |
| `Tests/ValoraTests/DeviceBatteryRowTests.swift`（新增） | 最终格式、Max 共享 single、0/缺失/越界、仅 AirPods、active 优先、开关/空列表/迟到快照、无障碍、400pt 排版与开关关闭高度 |

## 验证

- 定向测试：`DeviceBatteryRowTests` 9 + `DeviceBatteryRowLayoutTests` 2 = **11 通过**；连同 `MonitorSummaryAccessibilityTests` 4、`CodexUsageSummaryTests` 14、`CalendarMonitorSharedTests` 4，共 **33 通过**。
- `swift build -c release` 通过。
- 隔离排版：`NSHostingView` 实际布局（非离屏图片）验证设备行不撑宽 400pt、长型号可截断、设备行增加高度；开关关闭高度与无设备一致。
- `--preview-menu-modules` 已带 AirPods fixture。曾启动一次调试预览，但 AX 点击未能打开共享 popover（未取得视觉截图），**不以离屏图片冒称窗口预览通过**；可视排版仍请 Codex 在验收时查看。

## 候选

| 项 | 值 |
|---|---|
| 路径 | `/private/tmp/valora-v0110-device-battery-candidate/Valora.app` |
| 版本 / 构建 | `1.0.3` / **23**（自动分配一次） |
| 签名 | `Valora Self-Signed`，DR `identifier "com.wangqing.valora" and certificate leaf = H"3a3b4d8f03d177e1664081c4cc2bb76ee2166a52"` |
| 签名核验 | strict/deep 通过；非 ad-hoc |
| 嵌套框架 | `MediaRemoteAdapter` 同证书 DR；adapter `test` exit 0 |
| App binary SHA-256 | `df3e1c67c994002e777ea14043a947fe73a03d973741882564de99b70239bdf7` |
| Bundle ID | `com.wangqing.valora` |
| 运行 | **候选未启动**：按要求不替换/不提前启动生产；当前无 Valora 实例。调试预览进程已在本次查看后正常结束 |

## 限制

- 盒电量无可靠数据，本版固定 `盒-`；未读真实设备，不能验证实际盒读数。
- 仅识别 AirPods；普通非 AirPods 耳机暂不显示（避免把任意蓝牙设备/鼠标当耳机）。
- 未触发真实蓝牙/日历授权；真实设备断开/重连、系统权限和长期渲染仍待用户实机与 Codex 验收。
- 未提交/推送/发布；`dist` 与 `/Applications` 未替换。

## 交付

候选与报告完成，交 Codex 独立验收。验收通过后由 Codex 正常退出旧实例、确认 0 实例，再替换并确认唯一路径；本会话不提前替换。
