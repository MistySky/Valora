# V0035 三方对照：原版 Alcove、成熟复刻、当前 Valora

范围：设备连接/电量/到达提示；以及本轮已定位的音乐点击链路。
本文只读审计，不修改源码、测试、构建或当前运行候选。

## 0. 证据边界

### 原版反编译

来自 `/Users/wangqing/code/alcove-revival-archive/reverse-engineering/connection-appearance/`：

- `1002b45f8.c`：Connectivity 外观分支（3D models / symbols）
- `1002b5cf4.c`、`1001f4c48.c`、`1002b1594.c`、`1002b16fc.c`、
  `1002b5fec.c`、`1002b6390.c`、`1001e1ce8.c`：电量/环/电影/符号的尺寸、
  缺失状态和布局
- `1002ba4a8.c`：电量颜色分支
- `10031fbe8.asm`：AirPods 代际到 symbol/内部标识的映射
- `1000f0660.c`：音乐输出设备图标分支（不是耳机到达电量）
- 汇总只作索引，本文引用具体函数/地址范围；反编译是 Ghidra 近似，不是原始
  Swift 源码。

### 成熟复刻与历史实机

- `docs/alcove-1.7.9-detail-audit/evidence/fixed-0.6.35/airpods3-real-notes.txt`
  （不复制 MAC、地址或用户名称）：
  - 真实 AirPods 3，productID `0x2013`；
  - 同一连接实测 `batteryPercentLeft=100`、`Right=99`、`Single=0`；
  - 当时确认 `single=0` 被纳入 `min` 会显示 0% 红环，修复后稳定帧与
    `original-airpods3-arrival.png` 同设备对照；
  - 这是历史实际 AirPods 3 实机，不是“先前未实测”；
  - 原版/复刻只确认稳定 arrival 帧，逐帧 scale/offset/spring 未定量。
- `Sources/AlcoveRevival/Models.swift`：`battery` 使用 `>0` 过滤后取 min。
- `Sources/AlcoveRevival/Controllers.swift`：`BluetoothController` 的
  `valid` 使用 `1...100`；3 秒 poll；native 查询 off-main；2.5 秒超时，
  token/generation 丢弃迟到结果。
- `Sources/AlcoveRevival/NotchView.swift`：只有连接 toast；没有系统通知
  拦截。

### 当前 Valora / V0035-R1

- `Sources/Valora/Models.swift`：`AudioDevice.battery`。
- `Sources/Valora/ConnectivitySource.swift`：native snapshot 解析。
- `Sources/Valora/ConnectivityController.swift`：poll、off/on、toast、
  query generation、event pending/revision。
- `Sources/Valora/ConnectivitySystemEvents.swift`：IOBluetooth connect +
  CoreAudio output/devices notification。
- `Sources/NativeBridge/NativeBridge.m`：selector 读取、字段、modelUID。
- `Sources/Valora/NotchView.swift`：到达画面、电量环、3D/symbol。
- `Sources/Valora/Controllers.swift` + `SystemMediaSource.swift`：音乐命令、
  来源校验、显式 play/pause 映射和即时反馈。

## 1. 逐项三方对照

| 项目 | 原版反编译/证据 | 成熟复刻/历史实机 | 当前 Valora / R1 | 迁移判断 |
|---|---|---|---|---|
| battery 可选/缺失 | `1002b5cf4` 读取 optional `_batteryLevel`；缺失时走零值分支；`1002b5cf4`/`1002ba4a8` 的可见环分支 | 历史 0.6.35 修复为忽略 0、valid 1...100；实际 100/99/Single0 | `battery` 左右优先，single 仅左右都缺失时使用；0 保留；nil 不画环 | 保留真实 0，避免 single 占位压左右；不等同原版 >0 过滤，需实机确认未知 0 |
| 左右/Single 合成 | 反编译未直接证明 AirPods earbuds 三字段合成规则；UI 只消费一个 batteryLevel | 历史实机明确 Single=0 不适用，左右 100/99；旧 min 错误 | 左右有效取 min；single fallback | 已知历史缺陷不再复现；Single 是否可靠仍待设备字段 |
| 原生 selector 类型 | 反编译不包含 IOBluetooth private selector ABI | 旧复刻没有类型验证，使用 unsigned int 读取 | `method_copyReturnType == C`，`unsigned char`；不支持返回 -1 | 当前修正独立于历史记录，不能倒推为历史错误唯一根因 |
| 型号映射 | `10031fbe8.asm` 有 AirPods/Gen3/Gen4/Pro/Max；Pro3 内部标识仅部分覆盖 | 复刻支持 AirPods3 `2013 4c`；Pro3 回退 `airpods.pro` | `AirPodsModel` 同映射；`2013 4c` 为 AirPods3 | AirPods3 保持；Pro3/未知型号仍限制 |
| 型号获取 | `1002b45f8` 3D/symbol 分支；modelUID 是外观选择输入 | 旧缺口：只有当前输出设备填 modelUID；后改为 CoreAudio 全部已注册设备按地址匹配 | `NativeBridge` 遍历 CoreAudio devices 匹配 modelUID；仍只把真实默认输出标 active | 改进已保留；未成为默认输出的连接仍可能暂时无 movie，需实机 |
| 缺失电量显示 | `1002b5cf4` optional 缺失分支；环不填；没有百分比文字 | 修复后 99/100 显示绿环；低电/Pro3 仍限制 | `NotchView` `if let battery` 才画环，nil 为空白 | 与“缺失不可伪造”一致 |
| 环尺寸/线宽 | `1002b5cf4`（14），`1001f4c48`（14/12），`1002b6390` 符号，`1001e1ce8` 无刘海 -2；反编译未直接给出所有线宽 | 证据汇总：环14/12、线2.5/2；电影32/28 | `ConnectionBatteryRing` 14/12、线2.5/2；movie32/28、symbol15/13 | 当前常量与证据一致；真实 1x 视觉未单独验收 |
| 3D/symbol 分支 | `1002b45f8` 根据 connectivityModel；`1002b5fec`/`1002b1594`/`1002b16fc` 电影尺寸与 y 偏移 | 复刻有 3D/symbol 分支；历史 AirPods3 稳定帧已对照 | `ConnectionArtworkPolicy` + `ConnectionArtwork`；fixed automatic 3D，Reduce Motion/资源缺失回退 symbol | 结构保留；Reduce Motion 和真实电影渲染仍需实机 |
| 连接检测 | 反编译未证明通知来源；原版 UI 有到达提示 | 旧复刻 3s poll、off-main、2.5s stale timeout；没有 IOBluetooth/CoreAudio 事件接入 | 3s poll 兜底 + IOBluetooth connect + CoreAudio output/devices；120ms debounce；one-in-flight；pending/revision | 当前减少快速连接漏采；真实断开/CoreAudio 时序仍需实机 |
| 首次启动/重播 | 原版稳定 arrival 帧证据；首次不重播策略在复刻实现 | 首次 baseline；didRead 后 fresh 才 toast | 首次 baseline、不重复到达；事件 target pending | 保留；真实首次启动仍需用户验证 |
| 低电量 | 反编译颜色分支；低电阈值/提示音未形成完整原版常数证据 | 历史低电量/阈值/声音为合成 QA；历史实机电量 99–100 未触发 | 固定阈值 20、提示音开；未知/0 不伪造 | 不能把 99/100 的历史样本冒充低电验证 |
| 音乐命令映射 | 本轮未独立还原原版命令派发；`SystemMediaSource` 是复刻 Swift 适配器，不能冒称原版反编译 | 复刻同映射；后台 command queue | 当前保留同 source/get/send 映射 | 不把 UI 即时反馈当成真实 toggle |
| 点击反馈/回调 | 原版命令由后台 source 完成后刷新；没有当前新生命周期 | 复刻没有 command generation 失效；旧失败可污染 | 即时可回滚 playing；applySystem/stop/invalidate/clear 失效 generation | R1 修复旧 completion；真实点击体感仍待实机 |
| 系统 AirPods 通知 | 反编译未见系统通知拦截；原版证据未确认 | 复刻有自己的 `connectionToast`；没有 UN/NSUserNotification 抑制 | 当前同样没有系统通知抑制代码 | 只能确认“自己显示 toast”；不能承诺原版/Valora 接管系统提示 |
| 权限/查询 | 原版权限行为无完整证据 | 旧查询 off-main；授权 gate 存在于当前 | 当前 gate + 事件注册只在 native/auth/on；off/stop 注销 | 无新 TCC/外部 probe；真实 TCC 仍未验证 |

## 2. 关键缺口与改进

### 已确认的历史事实

1. AirPods 3 曾实际测到左右 100/99、Single 0；旧 min 导致红色 0 环。
2. 成熟复刻通过“忽略 0、1...100”解决当时的 earbuds 显示，但这不是
   对“真实 0 永远不可能”的证明。
3. AirPods3 原版/复刻 arrival 稳定帧有过同设备视觉对照；逐帧动画未定量。

### 当前 Valora 的改进

- 不再 min 三字段；保留左右优先、single fallback，避免同一已知占位错误。
- 0 保留为真实可能值，不用 `>0` 全过滤；未知/越界由解析层转 nil。
- native selector 类型检查与 `unsigned char`，避免旧 ABI 读法。
- 事件与 3s poll 合并，事件 pending/revision 防止旧快照消费新连接。
- 音乐 command 的权威状态/stop/invalidate 使旧失败 completion 失效；即时
  feedback 可回滚，source/get/send 校验未删。
- 3D/symbol、环尺寸、缺失空白、首次 baseline 结构保留。

### 仍未知/未验证

- 当前 Valora 候选没有取得 AirPods3 原始 `left/right/single` 字段值；
  ABI 类型证据不等于“用户此前的错误电量已唯一确诊”。
- 真实 0 和 unknown 0 在 IOBluetooth 返回中的区分未证实；不能把所有 0
  当未知或真实低电。
- 断开/快速重连的 IOBluetooth/CoreAudio 真实时序、首次启动、事件重复、
  active 输出与已注册设备的关系仍需实机。
- Pro3、未知/重命名设备、低电量阈值/提示音的原版证据仍不完整；历史
  AirPods3 99–100 不能拿来证明低电。
- 原版是否/如何抑制系统 AirPods 通知没有确认；当前没有系统通知修改。
- 3D 电影真实渲染、Reduce Motion、系统浅/深/刘海/无刘海稳定帧未在本轮
  单独视觉验收。

## 3. 后续只读实机方案（不在本文实现）

在用户已经授权的 **Valora 候选进程内**，由用户显式触发一次诊断，而不是
启动新实例或外部 CLI：

1. 仅在蓝牙总开关开启、当前授权可用、当前存在默认音频设备时触发；
2. 在既有 native source 的 utility queue 上最多读取 3 次，总预算 10 秒；
   一次 in-flight，超时后停止等待，不堆线程；
3. 只读取当前活动音频设备（不遍历/持久化其他配对设备）：
   - product/model UID（例如 AirPods3 的 `2013 4c`）
   - left/right/single 的原始值与有效/缺失状态
   - 合成后的 battery
   - 每次读取耗时
   - 授权状态与设备是否 active
4. 不记录 MAC、地址、用户起的设备名、其他配对列表或账户；
5. 不操作播放/切歌/seek/音量、不选择输出、不连接/断开/配对/扫描 BLE，
   不触发新 TCC，不向当前运行进程注入代码；
6. 结果只作为一次候选审查证据；结束后恢复普通 3 秒 poll 生命周期。若
   用户当前未运行候选，只能如实列“待用户新候选一次确认”，不能假装读数。

## 4. 结论

- 历史 AirPods3 实机验证是真实存在的；旧复刻已知 `single=0` 占位导致
  红环的问题，当前 Valora 不应回退到三字段 min。
- 当前 R1 已保留真实 0 语义、左右优先、ABI 类型检查和事件/音乐生命周期
  修复；但不能仅凭源码/类型证据宣布用户电量与系统提示已全部正确。
- 锁屏属于下一步，但本补充不进入锁屏开发；先等设备实机与 R1 复验收尾。

