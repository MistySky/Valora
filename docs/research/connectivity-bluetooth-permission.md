# 设备连接与蓝牙权限（V0015-R1 补充）

## 当前实现

- `NativeConnectedAudioSource` 只读调用 `IOBluetoothDevice.pairedDevices` / `isConnected`，并读取 CoreAudio 的默认输出名称与已知音频设备型号；不扫描、不配对、不连接、不断开设备。
- 查询位于独立 utility 队列，由 `ConnectivityController` 单 in-flight 限流；总开关默认关闭，关闭时 `Timer`/`Subscription`/查询均停止。
- 只有用户主动打开设备连接总开关后才启动检测；应用启动不会预先查询或请求许可。
- 失败/受限/空结果会保持无 toast 的正常状态；不伪造设备，不无限重试，不阻塞主线程。

## Info.plist 声明

`scripts/package.py` 现在写入：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Valora 需要访问蓝牙以检测已连接的 AirPods 并显示连接和电量提示。</string>
```

构建校验 `dist/build-verification.json` 记录
`bluetooth_usage_description_key` 与 `bluetooth_usage_description_present=true`；
设备 QA 还读取实际 `Bundle.main` Info.plist 检查键存在且非空。

## 官方依据（本次只读核对）

- Apple, Information Property List: `NSBluetoothAlwaysUsageDescription`
  https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription
- Apple Support, macOS 27 Privacy & Security — Bluetooth access control
  https://support.apple.com/en-gb/guide/mac-help/mchl211c911f/27/mac/27

结论：蓝牙接口访问属于需要用途说明的隐私能力；3D 本地 mp4 资源本身不需要蓝牙权限，只有设备检测/读取会触发系统蓝牙访问控制。本文不声称本机已弹窗、已授权或已在真实设备上验证。

## 未做

- 未修改 TCC、系统设置、权限数据库。
- 未启动 CoreBluetooth manager、扫描、配对、连接或断开设备。
- 未真实触发/接受权限提示，未读取个人设备信息用于伪造测试。
- 真实授权弹窗、拒绝/受限设备状态和物理设备通知仍待用户实机验证。
