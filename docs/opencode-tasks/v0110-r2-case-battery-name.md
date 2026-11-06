# V0110-R2 真正接入盒电量、型号名

用户实测build24指出盒电量和名称不对，明确「对啊，肯定接入啊，不然占位干嘛」。继续当前codex/device-battery-panel和现有会话。现在补真实接线，而非写死盒-。不再占位交付，不改三列对齐及同电量合并、刘海等已确认行为。用户已授权修复当前连接耳机名称/电量读取，以及此前测试通过后使用1.0.3，真实只读当前耳机诊断限此范围，不读其他个人数据/媒体或改设备状态，不触发新权限。如需要开盒才能上报再报告。

已知来源：NativeBridge.m connectivityScalar已针对unsigned char返回、respondsToSelector、0...100校验；左/右/single都这样读。系统IOBluetoothDevice存在同类batteryPercentCase接口（本机运行时验证类型，不只凭网文；Hammerspoon官方源码 extensions/battery/libbattery.m也直接读取该字段）。请把case百分比从NativeBridge字典→NativeConnectedAudioSource解析→AudioDevice optional default nil→DeviceBatteryRow真实caseText完整接通。保持不缓存历史battery，不把255等无效值变0；0%有效；Max无充电盒保持-，不要误把单机电量当盒。nil时-，有真实值时盒62%。公开API不提供这些字段，沿用既有隔离私有selector边界，不引入扫描/新轮询。

名称：当前ARConnectedAudioDevices的name会用active outputName覆盖device.name，DeviceBatteryRow只是原样显示。用户期望具体型号如AirPods 3、AirPods Pro 2。用现有AirPodsModel.identify(modelUID:)增加明确产品显示名（airPods/2/3/4, pro/2/3,max/2），设备行优先准确型号，未知型号再用真实蓝牙设备名称；不要通过通用outputName伪造代际。保留其他UI原名字语义，如要换底层名称须评估影响，最好只为新增行独立映射，不回退连接动画/模型识别。

补定向测试：case nil/0/100/越界、字段解析接线、读取selector安全性（若可注入）、不同代际/自定义名/未知名回退，断开/禁用清理及左右合并回归。必要时单次只读当前AirPods诊断证明系统是否上报case（仅输出型号名/电量/支持状态，不落MAC/所有配对设备）。不要把系统缓存读数宣称持续实时、无新鲜度证据就如实说明。

版本保持1.0.3，下一构建号自动分配一次，新候选/private/tmp/valora-v0110-r2-device-battery-candidate。Release只构建一次且检查退出码，不运行--version（会启动生产）。候选、报告完成由Codex验收后正常替换使用；不提交推送/发版。私钥不触碰。
