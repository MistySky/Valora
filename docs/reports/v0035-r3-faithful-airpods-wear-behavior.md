# V0035-R3 — 佩戴触发语义与 AirPods 到达状态

状态：**完成可审查的 active-route 佩戴代理修复，等待新候选实机验证；不宣称已完成物理佩戴传感器复刻。**
未覆盖/退出当前运行包，未操作真实蓝牙/媒体/系统输出。

## 1. 用户真实事实

用户对照：

- Valora：仅在蓝牙 connect 时可能显示；摘下后还会冒出其他耳机图标；再戴上不出现。
- Alcove：戴上时出现；摘下后短暂保留再消失；再戴上应有触发。
- macOS 原生 AirPods 弹窗同时出现是正常现象，本轮不抑制/不接管。

此前 R2 把“显式 connect”作为主要触发，不能满足“戴上 → 摘下 → 再戴上”的体验；不能继续用断开 5 秒后重连替代该验证。

## 2. 原版/复刻证据核查

只读检索 `alcove-revival-archive` 的 Sources、connection-appearance 反编译和 detail-audit：

- 找到的原版函数主要证明：
  - `1002b45f8` 3D/symbol 分支；
  - `1002b5cf4` optional battery 与 14pt 环；
  - `1001f4c48` 14/12、`1002b5fec` 32/28 电影、
    `1002b6390` 15pt symbol、`1001e1ce8` 无刘海减 2；
  - `10031fbe8` 型号映射；
  - `1002ba4a8` 电量颜色；
  - `1000f0660` 音乐输出图标。
- **没有找到明确 in-ear/wear selector、佩戴通知或耳塞状态字段**。
  这是“已查范围未命中”，不等于原版绝无私有 API。
- 成熟复刻 `BluetoothController` 仍是 3 秒 poll + connected device fresh ID，
  没有 wear 状态；不能把复刻能力当原版上限。
- 历史真实 AirPods3 记录证明左右 100/99、Single=0 和电量修复；不是本次
  wear 事件日志。
- 用户观察本身是当前唯一明确的原版行为输入：戴上出现，摘下短暂保留，
  再戴触发。

因此本轮不伪造“已找到佩戴传感器”。采用**当前可观测的 active default
output 转变**作为最小代理，并明确它不是物理佩戴传感器。

## 3. 实际修复

### 3.1 触发由“新 connected ID”改为 active AirPods route

`ConnectivityController.applySnapshot`：

- 首次 active AirPods 只建立 baseline，不重播；
- active AirPods → inactive（摘下/切换到其他输出）：不产生新到达，已有
  toast 仍按配置时长短暂保留；
- inactive → active（再戴上/恢复 AirPods 输出）：产生一次到达；
- 同一 active route 重复 snapshot：不重播；
- 明确 connect event 仍然保留 10 秒 intent，可越过 baseline；
- pending intent 只在 active AirPods 真正出现时消费；
- 纯连接但非 active 输出不显示为“戴上”；
- 不使用播放/暂停状态作为佩戴代理，不控制音乐。

### 3.2 同设备瞬态元数据不换图标

- 以 native stable id 为 key，保留最近 modelUID/name/isAirPods；
- 同一 id 短暂缺失 modelUID 时只用于更新**已有 toast**的展示，不把 raw
  generic snapshot 当成新的 AirPods 触发；
- 不同 stable id 不继承上一个设备的型号；
- 缓存有界，off/stop 清空；真实断开/换设备不会复用另一设备型号。

### 3.3 权限/事件前提

R2 的 `BluetoothAuthorizationRequester` 保留：

- 用户点击 Connectivity 开关时才创建短期 CBCentralManager；
- 不扫描/连接/读取设备；
- 授权完成后经 `AppPermissions.refresh()` 完成既有 pending intent；
- `ConnectivitySystemEvents` nonisolated callback、registration identity、
  连接 intent、单 in-flight/revision/pending 保留；
- 3 秒 poll 保留兜底，不提高频率；
- off/stop 注销监听并清空 pending/event state。

## 4. 验证

**48/48 定向无界面测试通过**

- ConnectivityController 11
- IndependentConnectivityLifecycle 2
- IndependentDeviceMediaReview 8（含新增 active→inactive→active、同 route 不重播、瞬态 model 不换图标）
- DeviceBatterySelection 1
- MediaControllerRecovery 11
- MediaResponsiveness 1
- AppPermissions 7
- IndependentPermissionFlow 3
- IndependentInteraction 3
- RevivalSettingsReload 1

原 R2 非隔离 callback、首次 baseline、明确 connect、late model、过期 intent、
off/stop、旧回调、左右电量优先和媒体旧 completion 回归均保留。

未运行 `--verify-*`、菜单/蓝牙/耳机循环、批量截图、CPU/RSS/帧率压力；未运行
含 `showCalendarPanel/showMonitorPanel` 的 Panels 测试。

## 5. 候选

- `/private/tmp/valora-v0035-r3-wear-candidate`
- App SHA256：
  `736c7cffaf4b6ad030d3f4a59cd1593d852a2fbd8200b2b8b98c608b870935f9`
- `codesign --verify --deep --strict` 通过；Bluetooth usage 保留；日历
  entitlement 保留；无下载/Codex/Chrome payload。
- 当前用户运行包未覆盖；`dist` 未覆盖：
  `19ba9a0f0cae669dcc32eb8f282750f9fd46a71a603d1bb2d01b9f872b0ffd9f`

## 6. 实机验证步骤（由用户操作）

1. Codex 协调退出旧候选后启动新候选；
2. 打开设置 → 设备连接，点击开关完成系统 Bluetooth 授权；确认手形消失、
   开关保持 on；
3. 戴上 AirPods：应出现 Valora 到达提示；系统原生弹窗仍可同时出现；
4. 摘下：已有提示按 5 秒配置短暂保留后消失；不应变成其他耳机图标；
5. 再戴上：应再出现一次到达提示；
6. 不要求“断开 5 秒重连”作为佩戴验证。

## 7. 未知/边界

- **active default output 不是已证实的物理 wear 传感器**；它只是当前没有
  in-ear 证据时的最小可观测代理。若用户/原版实际在未切换输出时也有
  佩戴提示，本代理仍会不触发，需下一轮最小有界诊断。
- 单耳/双耳佩戴、摘下后真实停留时长、音乐暂停/无播放、睡眠唤醒和
  非默认输出的原版证据仍不足；没有自行设计这些分支。
- 真实 Bluetooth callback、真实授权和 UI toast 未在本轮采集；不把 fake
  测试通过当实机通过。
- 系统原生 AirPods 弹窗不抑制；没有 TCC/defaults/AX/登录项或输出操作。
- 未 Git 提交/推送，未改归档/模型历史，未启动候选替换当前运行包；定时器关闭。

报告证据：`docs/verification/v0035-r3/`
