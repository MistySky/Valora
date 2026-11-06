# V0015-R1补充：外观固定自动选择、核验蓝牙权限声明

用户明确同意去掉3D模型/符号设置。设备连接页只留功能总开关；默认自动用已识别型号的3D资产，缺少型号/资产则用现有AudioDevice.symbol回退（已知AirPods但型号不明airpods，其他headphones；已知型号缺动画用其型号符号）。Reduce Motion仍回退符号。删除外观tile入口，旧connectivityModel不得覆盖固定自动策略，不删除必要回退图标/资源或自创设计。

用户同时询问设备是否需要授权。当前NativeConnectedAudioSource使用IOBluetoothDevice.pairedDevices读取已连接设备与电量；scripts/package.py目前无NSBluetoothAlwaysUsageDescription。请核查当前macOS27/IOBluetooth实际权限要求，补齐必要用途声明与隔离回归，说明“3D本地资源不需蓝牙权限；设备检测涉及蓝牙访问许可”，不要声称本机已弹窗或已授权。

官方依据：
- https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription （使用蓝牙接口的用途说明键）。
- https://support.apple.com/en-gb/guide/mac-help/mchl211c911f/27/mac/27 （macOS27 Privacy & Security的Bluetooth访问控制）。

权限要求：默认总开关关闭，不启动检测或预先触发授权；仅用户主动开启后才按系统机制处理。不为了“强行弹窗”改成扫描/配对/连接，不引入无必要的CoreBluetooth manager或额外权限，不授予权限、不改TCC/系统设置，不真实触发权限弹窗作自动测试。拒绝/受限/不可用时平稳处理，不伪造设备、不无限重试或卡UI；如缺实机证据如实待验，保留成熟只读检测路径。

本补充与当前R1及Alcove基线补充同轮收尾，报告补更新范围、权限声明/实际待验，不扩大其他模块、不Git提交推送/安装发布、不恢复定时器。完成由Codex独立验收。
