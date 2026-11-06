# V0037 日历与基础监控合并展示

日期：2026-10-29
状态：实现完成，等待 Codex 独立验收；**未启动候选，未做真实菜单栏 popover/视觉点击验收**。
候选：`/private/tmp/valora-v0037-calendar-monitor-candidate/Valora.app`
候选二进制 SHA-256：`d6e3acd5145c5b9a4bdf629bcdcc4c03fd1fd5aa62dafe48faba2071601bda92`

## 1. 结果

- 保留两个状态项：CPU/MEM 监控和日期；图标、文本、右击基础菜单不变。
- 两个入口左击现在打开**同一个共享 `NSPopover`**：
  - 同一入口再点关闭；
  - 另一入口点会先关闭共享 popover，再以新入口为锚打开；
  - 不会并存两个面板。
- 共享内容顶部是一张单行基础监控卡，下方嵌入现有 Calmon 日历。
- 日历宽度仍为 400pt，网格仍为 368pt；导航、农历/节假日、授权日程逻辑未重写。
- 外层只有一个 `ScrollView`；日历通过 `embedsScroll:false` 嵌入，没有外层 + 日历内层双滚动。
- 两个原设置开关仍独立：监控关闭停止采样/观察、移除 CPU/MEM 项和监控卡；日历关闭停止日历后台、移除日期项和日历区。面板显示中切换会立即更新共享视图并关闭已无内容的 popover。
- 删除旧监控专用 `MonitoringView.swift`（圆环、应用内存列表、搜索、进程采集触发）；历史 QA 文档未改，旧 audit 只为编译保留 fake reader。

## 2. 顶部监控卡

用户最新确认只显示一行，与提供的 Calmon 参考样式一致：

```text
<chip>  <macOS version>  <memory total>  <disk total>  <uptime>
```

- 设备/系统分别复用现有 `Snapshot.device.chip`、`osVersion`。
- 内存复用 `Snapshot.memory.total`；磁盘复用 `Snapshot.disk.total`，不合并 APFS 卷。
- uptime 复用 `Snapshot.uptime`。
- 缺失值显示 `--`，不伪造 0；不显示旧三行、圆环、应用列表、搜索、CPU 细分或额外按钮。
- 单行 `HStack` 使用现有 Calmon `caption` 字体、`secondary` 颜色、`cardBackground`、圆角和内容边距；`lineLimit(1)`/缩放避免换行。

## 3. 共享路由与生命周期

代码：`Sources/Valora/MenuBarModuleController.swift`

- `sharedPopover` 是唯一 popover；`monitorPopoverIdentity`/`calendarPopoverIdentity` 诊断别名指向同一个对象。
- `PanelRouteDecision` 纯决策：
  - 未显示 → open；
  - 同一入口 → close；
  - 另一入口 → switchAnchor（先关闭再打开）。
- 状态项仍由 `systemMonitorVisible`/`calendarVisible` 独立创建、移除。
- `CalendarMonitorSharedView` 观察 `MenuBarPanelVisibility`：
  - 监控 off：卡消失、监控入口移除、采样停止；
  - 日历 off：日历区消失、日期入口移除、日历 provider 停止；
  - 两项 off：共享 popover 关闭；
  - 一项 on：仍可打开对应部分。
- 一个入口打开时设置 `monitor.setPanelVisible(true)`（仅监控可见时）和 `calendar.setPanelVisibility(panel:true, calendarModule:true)`（仅日历可见时）；关闭时分别 false。
- 右击仍走 `makeBasicMenu()` 的版本/设置…/分隔线/退出，不加入音乐控制。

## 4. 简化后台

`Sources/Valora/SystemMonitor.swift`：

- 生产 `SystemMonitor()` **不注入 reader**：`reader == nil`。
- `tick` 中应用采集条件为 `panelVisible && reader != nil`；生产恒 false，不调用 `NSWorkspace.shared.runningApplications` 或 `AppMemoryReader.sample`。
- 普通 CPU/MEM 采样、磁盘读取、30 秒磁盘节流、睡眠/wake、generation 取消保留。
- `SystemMonitor(reader:)` 仅为历史 QA/audit 注入 fake reader；`MenuBarMemoryAudit` 仍使用明确 fake reader，不读取用户应用。
- 删除 `Sources/Valora/MonitoringView.swift`；旧的 ring/list/search 生产 UI 和 `AppSearchModel` 不再被编译/引用。

## 5. 定向验证

命令：

```text
swift test --filter 'SystemMonitorTests|CalendarMonitorSharedTests|CalmonCalendarTests|CalendarHolidayParityTests|IndependentCalendarLifecycleTests'
```

结果：**38 项通过，0 失败**：

- `SystemMonitorTests` 9：CPU/内存/磁盘格式、缺失数据、旧注入 reader 的生命周期/缓存；生产默认无 reader。
- `CalendarMonitorSharedTests` 4：
  - 两开关四组合；
  - 共享路由 close/switch/open 决策；
  - 缺失值 `--`；
  - 生产 `SystemMonitor` 无注入应用 reader。
- Calmon 日历核心/节假日/独立生命周期 25 项通过（原回归，未改日历实现）。

日志与清单：`docs/verification/v0037/targeted-tests.log`、`source-manifest.json`、`test-inventory.json`、`build-verification.json`、`resource-check.json`、`codesign-display.txt`。

本轮没有运行真实 `NSStatusItem`/`NSPanel`/`NSPopover` UI 测试、`--verify-*`、自动点击、截图、循环、压力/性能或全量；候选未启动，当前用户运行版和 `dist` 未替换。

## 6. 构建与签名

- 一次 `scripts/build.sh --output-dir /private/tmp/valora-v0037-calendar-monitor-candidate` Release。
- arm64，macOS 27.0，ad-hoc hardened runtime；`codesign --verify --deep --strict` 通过。
- 候选二进制：`d6e3acd5145c5b9a4bdf629bcdcc4c03fd1fd5aa62dafe48faba2071601bda92`
- 锁解声音资源仍保留；未改动品牌/音乐/耳机/Calmon 日历核心。

## 7. 待实机视觉验收

- 两个状态项是否都按预期打开同一个 popover，同一入口关闭/另一入口切换锚。
- 400pt 共享卡片、368pt 日历网格、顶部单行监控卡在明暗主题下的实际间距/对齐。
- 设置开关在 popover 显示中切换时的即时收缩/展开。
- 授权日历日程、真实 APFS 容量显示和真实 popover 高度仍需用户环境确认。

以上未以 fake 测试或源码静态检查冒充通过。
