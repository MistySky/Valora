# V0015-R1 独立验收：修复子集接受，权限交互限定R2

Codex独立swift test194项通过（80+114），包括此前新增设备开启即时基线/stop拒绝刷新两项；独立构建/private/tmp/valora-independent-v0015-r1/Valora.app及codesign --verify --deep --strict通过。日志/private/tmp/valora-independent-v0015-r1-{test,build}.log。

源码检查：开关Published延后读取已恢复，started/subscriptions/stop和单in-flight旧结果保护已补；生产NSSound保留并有stop，退出有lazy-safe设备收尾；设备页仅总开关、3D固定自动回退、蓝牙用途声明及原版来源对应记录已补。接受上述修复子集，未宣称真实蓝牙授权或3D实机已验证。

用户最新澄清权限交互，当前不符合：SettingsToggleRow仍为可点击手形Button+Toggle.disabled(blocked)，SettingsView授权动作绑onAccessory，开关无法点；授权成功后也无有效pending开启联动。手形应仅状态标志，点击功能开关处理授权并在成功后完成这次开启，失败保持off，旧指令被用户最新覆盖。

另核查requestBluetoothAccess的0.8秒固定延迟未决定时就弹未授权notice，不能把等待用户决定当拒绝；受限/unknown状态下仍需可关闭已开功能。按docs/pi-tasks/v0015-r2-toggle-authorization-flow.md限定修复与实际开关路由fake验证，不引入新权限中心或模块。

独立隔离设备/设置视图验证输出connectivity/、settings/，不是用户实际授权。真实权限弹窗、真实耳机连接/声音/3D视频图层、物理双屏仍待用户安排，QA不触发真实权限/设备写。

独立设备QA已完成31/31通过，设置权限/关态等实际SwiftUI视图已生成；模型旧权限入口检查通过不等于符合用户最新开关交互，仍限定R2。
