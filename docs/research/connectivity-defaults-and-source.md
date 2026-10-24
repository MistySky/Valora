# 设备连接默认值与原版证据（V0015）

## 结论

本批不把任何现场取值冒称原版“首次安装注册默认值”。

| 项目 | 原版现场/AX 当前值 | 原版注册默认证据 | 归档复刻 fallback | Valora 本批策略 |
|---|---|---|---|---|
| 设备连接总开关 | 开启 | 未找到 Connectivity 注册默认表 | `bluetoothEnabled = defaults.bool(...)` → 关闭 | **关闭**，首次由用户打开；不声称原版默认 |
| 显示时长 | 5.0 s | 未证实；settings.json 的 `original_default` 为 null | `ConnectivityPreferences` fallback 5 | **固定 5 s** |
| 低电量提醒 | 开启 | 未证实；原版现场仅证明当前值 | fallback `true` | **固定开启，受总开关控制** |
| 低电量阈值 | 20% | 未证实 | fallback 20 | **固定 20%** |
| 低电量提示音 | 开启 | 未证实；原版现场仅证明当前值 | fallback `true` | **固定开启，受总开关控制** |
| 设备外观 | 3D models | 未证实；原版现场为 3D models | fallback `3D models` | **自动**：有型号/资产用 3D，缺失走现有 `AudioDevice.symbol`；不提供外观设置，旧 `connectivityModel` 忽略 |

原版现场证据是当前配置快照，不是默认值：
- `docs/alcove-1.7.9-detail-audit/evidence/original/connectivity-on.ax.txt`：toggle on、Duration 5.0、Warn on low battery on、threshold 20、Play sound on low battery on、3D models。
- `docs/alcove-1.7.9-detail-audit/settings.json`：Connectivity 各项的 `original_default` 均为 `null`；审计说明也明确“current_original 是现场配置，original_default 始终独立”。

归档复刻代码（只读来源）：
- `Sources/AlcoveRevival/Models.swift`：`bluetoothEnabled=d.bool(forKey:"bluetoothEnabled")`，即关闭 fallback。
- `Sources/ReferenceCore/ConnectivityPreferences.swift`：duration fallback 5，warn/threshold/sound fallback true/20/true，appearance fallback 3D。

## 本批取舍

- 显示时长、低电量提醒、20% 阈值和提示音是**产品固定策略**，不提供 UI，也不读取旧的隐藏键值；旧 `referenceSettingsUI` 值不会覆盖它们。
- 外观固定为自动选择：已识别型号且本地动画存在时使用 3D；缺少型号/资产/Reduce Motion 时使用已有 `AudioDevice.symbol`。旧 `connectivityModel` 不参与。
- 原版中 Focus/Lock 的额外允许项、通知声音预览与旧隐藏设置不在本批范围，也不迁入入口。
- 真实设备检测仍只读；未连接或未知型号时只能提供有限的通用回退，不宣称覆盖所有蓝牙耳机/键鼠。

## 复核路径

- 原版当前值：`evidence/original/connectivity-on.ax.txt`
- 默认值缺口：`settings.json`（`original_default: null`）
- 复刻 fallback：`Sources/AlcoveRevival/Models.swift`、`Sources/ReferenceCore/ConnectivityPreferences.swift`
- 本批固定策略：`Sources/ReferenceCore/ConnectivityPreferences.swift`
