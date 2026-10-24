# 权限手形映射与 API 依据（V0015-R1 补充）

## 沿用 Alcove

`Sources/Valora/SettingsControls.swift` 的 `SettingsToggleRow` 保留归档组件的：

- `hand.raised.slash.fill` 手形；
- `hand.raised.slash.fill` 仅作为 Image 状态，不作为 Button；
- 开关不再 `disabled(blocked)`，由开关 Binding 发起权限意图；
- pending 开关状态使用 `@Published` 可观察布尔值；取消后立即回到 off；
- loginRegister 回调绑定 intent generation，旧回调不能完成新意图；首次注册转为 requiresApproval 时所有权保留，取消会调用注入的 `LoginItem.set(false)` 撤销本次注册；原有 requiresApproval 注册不撤销；
- `accessibilityLabel("需要授权")`；
- 原行高、间距、图标顺序。

没有另画手、权限中心或新的设置风格。

## 当前接入项

| 功能 | 权限/系统状态依据 | 手点击行为 | 未决定/拒绝/受限 |
|---|---|---|---|
| 设备连接 | `CBManager.authorization`（CoreBluetooth 类属性，不会分配 manager） | 点击开关：未授权显示 pending；`.notDetermined`/unknown 使用一次现有 IOBluetooth 只读探针；`.denied`/`.restricted` 打开蓝牙隐私页 | 手形只是状态；开关仍可操作；真实状态/应用激活 resolve pending；不假定 `pairedDevices` 必然弹窗 |
| 实时波形 | 没有可靠公开的 process-tap 系统音频预读 API，初始 `unknown` | 点击开关调用现有 `LiveAudioTap.startAsync`；denied 打开设置，返回激活时仅对有效 pending 再尝试一次 | 返回激活发起异步 attempt 后保留 pending，不立即用旧 denied 清除；实际 callback 成功才完成；重复激活不并发；取消/迟到/失败不启用；不猜 denied、不混用屏幕录制；无超时猜结果 |
| 登录时启动 | `SMAppService.mainApp.status` | 点击开关：`notRegistered` 先注册并保留 pending；`.requiresApproval` 打开登录项设置 | 不当作蓝牙/TCC；首次注册转为 requiresApproval 后仍保留 pending，批准返回 refresh 才完成；取消清 pending |

普通歌词、外观、悬停等无需权限的项目保持普通开关，没有手形。

## 明确未做

- 未读取/写入 TCC，未改系统设置或登录项。
- 未启动 CoreBluetooth manager、扫描、配对、连接或断开设备。
- 未真实播放/采集音频；音频权限只通过注入回调验证。
- 未触发/接受真实权限弹窗。真实状态、真实拒绝/受限、系统设置返回和真实设备能力待实机。

## 依据

- Apple `CBManager.authorization` / `CBManagerAuthorization`（SDK 27 `CoreBluetooth/CBManager.h`；可在分配 manager 前检查）。
- Apple `SMAppService.Status.requiresApproval` / `openSystemSettingsLoginItems`（SDK 27 `ServiceManagement/SMAppService.h`）。
- 现有 `LiveAudioTap` 路径及 `NSAudioCaptureUsageDescription`（项目资源/实现）。
- 蓝牙用途键：`docs/research/connectivity-bluetooth-permission.md`。
