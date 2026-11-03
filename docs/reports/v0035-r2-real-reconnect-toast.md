# V0035-R2 — 实际重连无提示定位与限定修复

状态：**已定位一个可检查的权限链路断点，并保留既有事件修复；仍需新候选实机验证。**
未覆盖/退出当前运行包，未操作真实蓝牙/媒体/系统权限。

## 1. 用户实际结果与本轮核查

用户已在 `/private/tmp/valora-v0035-reconnect-candidate` 启动后尝试授权、断开并重连；原版 Alcove 出现提示，Valora 没有。系统原生 AirPods 弹窗同时出现是正常现象，本轮不抑制系统通知。

只读检查当前运行候选的公开本地偏好：

```text
com.wangqing.valora bluetoothEnabled = 0
```

这是一个观察快照，不等于用户后续操作或完整 TCC 状态；但它与“授权后总开关仍未真正进入 on/采集”的路径一致，不能继续只归因于连接事件漏采。

## 2. 找到的权限链路断点

现有链路：

```text
Connectivity 开关
  -> AppPermissions.beginBluetoothEnable
  -> bluetoothRequest closure
  -> ConnectivityController.requestAccessProbe()
  -> NativeConnectedAudioSource.snapshot()
  -> IOBluetoothDevice.pairedDevices / battery selectors
```

`AppPermissions` 的 pending intent 只在 `CBManager.authorization == .authorized`
（通过 `permissions.refresh()`）完成；但 `bluetoothRequest` 实际只做 IOBluetooth
读取，没有创建 `CBCentralManager`，因此无法保证 CoreBluetooth 的公开授权状态
从 `.notDetermined` 进入 `.authorized`。如果 IOBluetooth 侧没有同时改变
`CBManager.authorization`，开关会保持 off，控制器不会进入：

```text
settings.bluetoothEnabled == true
  -> authorizationGate()
  -> ConnectivityController.refresh()
  -> ConnectivitySystemEvents.start()
  -> IOBluetooth connect notification
```

这与当前候选偏好 `bluetoothEnabled = 0` 的观察一致；但不能把它伪称已取得真实 native 事件日志。

## 3. 最小修复

新增 `Sources/Valora/BluetoothAuthorizationRequester.swift`：

- 仅在用户点击 Connectivity 开关、且 `AppPermissions` 判定需要授权时调用；
- 创建并短期持有公共 `CBCentralManager(delegate:queue:options:)`；
- **不扫描、不连接、不读取设备、不改变输出**；
- 等待 `CBManager.authorization` 离开 `.notDetermined`；
- 完成后回调 `AppPermissions.refresh()`，由现有 pending intent 决定：
  - authorized -> 完成开关开启；
  - denied/restricted -> 保持 off 并显示既有权限提示；
  - 用户取消/未决定 -> 不伪造开启；
- AppDelegate 的 `bluetoothRequest` 从 IOBluetooth probe 改为该公开授权入口。

这修复的是**权限成为真实 on 的链路**，不是用高频 poll 填事件洞。

## 4. 保留的 R2 设备事件修复

未回退：

- `ConnectivitySystemEvents.bluetoothConnected` 仍为 `nonisolated`，只在后台复制
  Sendable 地址/registration identity，再回 MainActor 验证注册身份；
- 明确连接 intent 以 stable normalized id 保存 10 秒；
- 连接早于首次 baseline 可越过 baseline；
- 型号晚到的 generic snapshot 不消费 fresh intent；
- `eventRevision`/single pending、one-in-flight、off/stop generation、过期丢弃；
- 纯输出变化不冒充蓝牙连接；
- 不提高 3 秒 poll 频率。

## 5. 真实事件/UI 仍未证明

- 当前没有真实 IOBluetooth 回调日志、CoreAudio 事件计数或候选内 UI
  window 证据；不把 fake 通过当实际重连成功。
- 若修权限后仍失败，下一次可审查候选只启用**默认关闭、短会话、无 MAC/名称**
  诊断：记录 authorization/CBManager 状态、register 成功失败、callback 次数、
  stable id 是否匹配、pending 是否消费、toast 是否设置、WindowCoordinator
  active screen 是否可见；硬上限一次、结束停止，不写常驻日志/定时器。
- 本候选未启用该诊断，避免再次给当前运行包加代码/实例。

## 6. 验证

**44/44 定向无界面测试通过**

- ConnectivityController 11
- IndependentConnectivityLifecycle 2
- IndependentDeviceMediaReview 7
- DeviceBatterySelection 1
- MediaControllerRecovery 11
- MediaResponsiveness 1
- AppPermissions 7
- IndependentPermissionFlow 3
- RevivalSettingsReload 1

未运行含 `showCalendarPanel/showMonitorPanel` 的 Panels 测试；未运行 `--verify-*`、菜单/蓝牙循环、截图、性能/内存/CPU/帧率，也未控制真实耳机/媒体。

## 7. 候选

- `/private/tmp/valora-v0035-r2-real-reconnect-candidate`
- App SHA256：
  `425421f92a9d8655295502c56585cc573b494dd12e7eb5c3697afb75877bba88`
- `codesign --verify --deep --strict` 通过；Bluetooth usage description 保留；
  日历 entitlement 保留；无下载/Codex/Chrome payload。
- 当前用户运行包未覆盖；`dist` 未覆盖：
  `19ba9a0f0cae669dcc32eb8f282750f9fd46a71a603d1bb2d01b9f872b0ffd9f`

## 8. 用户一次短验证步骤

由 Codex 协调退出旧候选后：

1. 启动新候选，打开设置 → 设备连接；
2. 点击开关，完成系统 Bluetooth 授权/返回；确认手形消失、开关保持 on；
3. AirPods 断开至少 5 秒后重连；
4. 预计系统原生弹窗仍出现；Valora 刘海应出现 AirPods 3 到达提示与绿色电量环；
5. 若仍未出现，不反复重连；将本次诊断结果交 Codex，下一次候选再启用短诊断。

## 9. 未验证

- 真实授权链路、真实 IOBluetooth 回调、真实 UI toast、物理多屏、低电/Pro3
  仍待实机。
- 系统原生提示不抑制；无 TCC/defaults/AX/登录项修改。
- 未 Git 提交/推送，未改归档/模型历史，未启动新候选替换当前运行包；定时器关闭。

报告证据：`docs/verification/v0035-r2/`
