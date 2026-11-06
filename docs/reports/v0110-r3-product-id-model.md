# V0110-R3：蓝牙 PnP 产品 ID 识别型号（未佩戴仍连接）

执行：现有会话，分支 `codex/device-battery-panel`。在 R2 盒电量/型号基础上补真实 PnP 产品标识，解决“只有戴上时才显示 AirPods 3、未佩戴仍连接只显示 AirPods”的问题。**未启动/替换生产、未提交/推送/发版**。当前 `/Applications/Valora.app`（1.0.3/build24）由用户/Codex 运行，未触碰。

## 一、真实运行证据（Codex 单次只读）

- 当前 AirPods：`productID=0x2013`、`PnPProductID=0x2013`、`vendorID=0x004c`、`PnPVendorID=0x004c`，四个 getter 返回类型均为 `unsigned short`（`S`）。
- 当前 CoreAudio 默认输出是 `Speaker`，因此不能只依赖默认输出的 modelUID。
- 本批不再额外探测；以上数据足够。

## 二、原生链路

`Sources/NativeBridge/NativeBridge.m`：

- 新增 `connectivityUShort`：`respondsToSelector` + `method_copyReturnType` 必须为 `S`（unsigned short，uint16 ABI），不重用仅 unsigned char 的电量 helper；非法/缺失返回 -1。
- 读取 `pnpProductID`，缺失再尝试 `PnPProductID`；vendor 同理（`pnpVendorID` / `PnPVendorID`）。
- 输出 `productID` / `vendorID`（NSNumber）；0/越界不在 Swift 解析为有效值。
- 既有电量（left/right/single/case）读取与 0...100 规则不变。

`NativeConnectedAudioSource`：

- `device(from:)` 新增 `validID`（1...0xFFFF）解析 product/vendor，写入 `AudioDevice.productID/vendorID`。
- `isAirPods` 在原有名称/modelUID 基础上，增加“Apple vendor + 可映射 productID”。
- CoreAudio `modelUID` 仍保留作为辅助。

`AudioDevice.airPodsModel`：

- 优先 `productID`（vendor 为 nil 或 `0x004C`）→ `AirPodsModel.identify(productID:)`；
- 否则回退 `AirPodsModel.identify(modelUID:)`。
- 因此具体 `0x2013` 不会被子系统/辅助的通用 `2002` 覆盖；通用 `2002` 作为真实产品时仍显示 AirPods。
- 不修改 `AudioDevice.name` 与既有动画/弹窗名称语义；仅设备行使用 `displayName`。

## 三、未佩戴仍连接

- 行选择：优先 `active` 的已识别 AirPods；没有 active AirPods 时选第一个已识别 AirPods。因此默认输出为 Speaker、AirPods inactive 时仍显示 AirPods 3 行。
- `metadataCache` 扩展为仅缓存 `modelUID/name/isAirPods/productID/vendorID`；同一稳定 id 的瞬时快照缺失 PnP 字段时保留已确认型号。
- **不缓存电量**：缺失的左右/盒显示 `--%`，不会复用旧值；断开（设备从当前快照消失）整行隐藏。

## 四、文案（保持 R2 最终版）

- 不同：`AirPods 3 | 左85% 右78% | 盒62%`
- 相同：`AirPods 3 | 全部85% | 盒62%`
- 缺失：`左--% 右78%` / `左--% 右--%`；盒无值 `盒--%`
- Max：`全部85% | 盒--%`；0% 正常；未知 `--%`。
- 三列仍与内存/磁盘/已运行（及 Codex）列对齐。

## 五、测试

- `DeviceBatteryProductIDTests` 6：0x2013 在 Speaker 输出时识别 AirPods 3；具体 2013 覆盖通用 2002；真实 2002 保持 AirPods；非 Apple vendor 不映射；inactive AirPods + Speaker 选中；未知 product 回退真实蓝牙名。
- `DeviceBatteryMetadataCacheTests` 1：瞬时缺失 productID 保留型号但不保留电量/盒，断开隐藏。
- 既有 `DeviceBatteryRowTests` 9、case/name 5、layout 2、四组合 1；加 `MonitorSummaryAccessibilityTests` 4、`CodexUsageSummaryTests` 14、`CalendarMonitorSharedTests` 4 = **46 通过**。
- `IndependentDeviceBatteryPreviewTests` 未覆盖，仅已适配 R2 数据字段；可继续由 Codex 验收渲染。
- Release 构建、签名、adapter test 通过。

## 六、候选

| 项 | 值 |
|---|---|
| 路径 | `/private/tmp/valora-v0110-r3-device-battery-candidate/Valora.app` |
| 版本 / 构建 | `1.0.3` / **26**（自动分配一次；23/24/25 保留未动） |
| 签名 | `Valora Self-Signed`，strict/deep 通过 |
| 嵌套框架 | 同证书；adapter `test` exit 0 |
| App binary SHA-256 | `c3c82db28a270ef0236fd87af9f436432b5a5b0eb138a10007a39c24a1419fff` |
| 运行 | 未启动；生产 `/Applications` 1.0.3/build24 正在运行，未替换 |

## 七、限制

- 型号依赖当前连接设备的 PnP 字段；若系统在未佩戴时不提供任何 PnP/model 信息，且此前从未确认过该设备，仍只能回退真实蓝牙名（有缓存时才保留已确认型号）。
- 盒/电量读数来自 IOBluetooth 系统缓存，刷新节奏未证明；不宣称持续实时。
- 未读其他设备/媒体/日历/权限；未提交/推送/发布。候选交 Codex 验收后由其正常退出旧实例并替换。
