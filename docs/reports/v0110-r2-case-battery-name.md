# V0110-R2：盒电量真实接入与型号名

执行：现有会话，分支 `codex/device-battery-panel`。补齐 `batteryPercentCase` 与型号显示名；三列布局、同值合并等已确认行为保留。**未启动/替换生产、未提交/推送/发版**。当前 `/Applications/Valora.app`（1.0.3/build24）由用户/Codex 运行，未触碰。

## 一、盒电量接线

- `Sources/NativeBridge/NativeBridge.m`：沿用既有 `connectivityScalar`（`respondsToSelector` + 返回类型 unsigned char + 0...100 校验），新增 `batteryPercentCase`，输出字典键 `case`；255/越界/无 selector 仍为 `-1`，Swift 解析为 nil。
- `NativeConnectedAudioSource`：抽出纯 `device(from row:)` 映射，`case` 经同一 `validBattery` 校验；`AudioDevice` 新增 `caseBattery: Int? = nil`（默认 nil，不影响既有构造）。
- `DeviceBatteryRow`：
  - 普通 AirPods：真实盒值 `盒77%`；nil/越界 `盒--%`；`0` 有效显示 `盒0%`。
  - AirPods Max：无充电盒，固定 `盒--%`，绝不把 single 当盒。
  - 每次只用当前快照，不缓存历史电量。

**系统证据**：本机 `system_profiler SPBluetoothDataType` 对当前连接的 AirPods 显示 Case Battery Level 77%、左右 96%（未记录名称/序列号/MAC）。证明系统确实上报盒电量；未用新进程直接调用 IOBluetooth，以免触发新的蓝牙授权。

## 二、型号名

- `AirPodsModel.displayName` 新增明确产品名：AirPods、2、3、4、Pro、Pro 2、Pro 3、Max、Max 2。
- 设备行名称优先 `AirPodsModel.identify(modelUID:)` 的显示名；未知型号回退真实蓝牙设备名（如自定义名），不用 `outputName` 伪造代际。
- 仅设备行使用；`AudioDevice.name`、连接动画/弹窗等原有名称语义不变。

## 三、最终文案

同卡三列，纯文字：
- 左右不同：`AirPods 3 | 左85% 右78% | 盒--%`
- 左右相同：`AirPods 3 | 全部85% | 盒--%`
- 单侧缺失：`左--% 右78%` / `左85% 右--%`
- 两侧缺失：`左--% 右--%`
- 真实盒值：`盒62%`；无值/越界：`盒--%`
- Max：`全部85%`（single），无盒 `盒--%`
- 0% 正常显示；未知一律 `--%`，不使用单个 `-`。

## 四、测试

- `DeviceBatteryRowTests` 9 + 排版 2 + 四组合 1 + `DeviceBatteryCaseAndNameTests` 5 = 17
- `MonitorSummaryAccessibilityTests` 4 + `CodexUsageSummaryTests` 14 + `CalendarMonitorSharedTests` 4 = **39 通过**
- 覆盖：case nil/0/62/100/101/-1/255、parser `case` 字段接线、9 个代际名与未知型号回退、Max 不把 single 当盒、左右合并/差异/缺失、0 有效、开关/断开/迟到快照、stats×Codex 四组合 400pt 不溢出。
- `IndependentDeviceBatteryPreviewTests` 未覆盖；仅把旧构造适配为 `ears/caseText` 并同步新文案，继续由 Codex 验收渲染。
- Release 编译通过。

## 五、候选

| 项 | 值 |
|---|---|
| 路径 | `/private/tmp/valora-v0110-r2-device-battery-candidate/Valora.app` |
| 版本 / 构建 | `1.0.3` / **25**（自动分配一次；23/24 保留未动） |
| 签名 | `Valora Self-Signed`，strict/deep 通过 |
| 嵌套框架 | 同证书；adapter `test` exit 0 |
| App binary SHA-256 | `bb2ade4da0499c2cdb2036329e3d5fd0bb7a49cc26817d2b5f2d989d2ff40958` |
| 运行 | **未启动**；当前生产 `/Applications` 1.0.3/build24 由用户/Codex 运行，未替换 |

## 六、限制

- 盒读数来自 IOBluetooth 系统缓存；是否持续新鲜未证明，不宣称实时刷新。
- Max 无硬件盒，固定 `盒--%`。
- 真实显示需在已授权蓝牙的 App 内查看；本批未启动候选、未读取其他设备/媒体/日历/权限。
- 未提交/推送/发布；build25 交 Codex 验收后由 Codex 正常退出旧实例并替换。
