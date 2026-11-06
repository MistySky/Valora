# V0105：日历只保留节假日，删除个人日程

执行：现有会话，分支 `codex/final-cleanup`。用户明确“个人日程不需要，就节假日这个就行了”，并指出点击后短暂出现“正在获取日程”不应存在。本批按“删除功能”处理，删除整条个人日程读取与蓝色显示；保留 Calmon 基本日历、节假日/休班、授权与监控/Codex 同卡。未读真实用户日历、未改权限、未 Git 提交。

## 一、删除的真实链路与引用证据

| 位置 | 删除内容 | 原引用 |
|---|---|---|
| `Sources/Valora/CalendarEvents.swift`（整文件删除） | `CalendarEvent`、`CalendarEventProviding`、`EventKitCalendarEventProvider`（`calendars: nil` 的普通日事件查询）、`PreviewCalendarEvents`（个人事件样例） | 模型 `eventProvider`、AppDelegate、3 个审计、预览、测试 |
| `CalmonCalendarModel` | `events`、`eventState`、`loadedEvents`、`eventProvider`、`eventGeneration`、`requestedGeneration`、`requestedDay`、`eventTask`、`eventInFlight`、`eventReadStartCount/CompletionCount/DiscardCount`、`EventState`、`startEventRead`、`applyEventFilter`；`refreshEvents()` 改为 `refreshCalendarHolidays()`（只刷新节假日范围） | 原个人日程读取/代次/过滤链 |
| `CalmonCalendarView` | `systemEventsSection`、`CalendarSystemEventRow`、“正在读取日程…”、“开启日历授权后显示系统日程”、预览样例脚注（随该区删除） | 蓝色个人事件区与加载文案 |
| `AppDelegate` | 两处 `eventProvider:`：预览分支 `PreviewCalendarEvents()`、生产分支 `EventKitCalendarEventProvider()`；`refreshCalendarEventsAfterSettings` → `refreshCalendarHolidaysAfterSettings` | 生产构造个人事件查询 |
| `MenuBarModuleController` | `refreshCalendarEvents()` → `refreshCalendarHolidays()` | 设置变化后的刷新入口 |
| `CalendarFixedWindowAudit` / `CalendarPopoverAudit` / `MenuBarMemoryAudit` | `eventProvider:` 参数；`calendarEventStarts/Completions/Discards/Events` 字段与 JSON | 仅服务个人事件读的统计 |
| `CalendarParityVerification` | `EmptyParityEvents` 及其注入 | 仅服务个人事件读 |
| `HolidayProvider` | `holidaySourceIDs`、`applyFixture(sourceIDs:)`、`refreshSource` 的额外通知 | V0104 仅为“过滤个人事件”引入；已删除个人链后不再需要 |
| 保留 | `finishFetch` 的“刚完成范围不再重复请求”去重；`detailFestivals` 的绿色标题/标记去重；`HolidayProvider` 只读来源发现、EventKit 节假日查询、授权 gate | 节假日真正使用的稳定逻辑 |

`HolidayProvider` 仍只发现“只读 + 中国 + 节假日”来源，查询范围仍限当前可见网格；`CalmonCalendarModel` 仍要求本页开关 + fullAccess 才允许节假日读取；手形/授权路由未改。

## 二、设置与用途说明

- 日历设置说明：`允许后续在日历中显示系统日程；基础月份和日期不需要此授权。` → `允许读取日历中的节假日与休班；基础日期、农历和节气不需要此授权。`
- `scripts/package.py` 的 `NSCalendarsFullAccessUsageDescription`：`用于在日历中显示你的日程。` → `用于读取日历中的节假日与休班信息。`（候选 `Info.plist` 已核）
- 未新增设置、说明卡或授权弹窗；未触发真实权限。

## 三、测试：删除与剩余覆盖

随功能删除的测试（共 12 个函数，均为个人事件链；原失败/证据保留在报告中）：

| 文件 | 删除 |
|---|---|
| `IndependentCalendarHolidayDedupTests`（整文件，V0104 新增 6） | 个人事件缓存/晚到元数据过滤 |
| `IndependentCalendarSelectionIsolationTests`（1） | 选中日个人事件隔离 |
| `IndependentCalendarLifecycleTests`（4） | stop 后事件读、快速选择、撤 gate 前读、隐藏不读（均为个人事件 provider） |
| `CalendarHolidayParityTests`（1） | “个人日程同名保留”用例 |

未删除的节假日/权限/生命周期断言保留，并把“授权后读取”改为对 **HolidayProvider 的 fixture transport** 计数（`IndependentMenuBarMigrationTests` 两个授权测试），不再依赖个人事件。

当前声明测试 **443** 个。本次定向运行（无窗口，fake/fixture）：

| 套件 | 数量 |
|---|---|
| `CalendarHolidayParityTests` | 10 |
| `CalmonCalendarTests` | 5 |
| `CalendarMonitorSharedTests` | 4 |
| `IndependentCalendarLifecycleTests`（跳过真实状态项方法） | 4 |
| `IndependentCalendarPermissionTests` | 2 |
| `IndependentHolidayDispatchTests` | 1 |
| `AppPermissionsTests` | 7 |
| `IndependentSidebarContractTests` | 1 |
| `LaunchPolicyTests` | 14 |
| **合计** | **48，0 失败** |

日志：`/private/tmp/valora-v0105-calendar-tests.log`。覆盖：无个人事件 provider 构造/调用（源码已无符号）、无蓝色区/日程 loading 文案；节假日 fixture 普通/休班各一次；未授权/关闭/隐藏/stop 无节假日读、迟到结果不回写（既有 holiday generation/fixture 测试）；日期/月导航、相对日期、农历/节气、休班标记保留。

Debug `swift build --build-tests` 与 Release `swift build -c release` 均通过；未跑全量、未开 QA UI、未闪窗/压力/性能。

## 四、候选与替换

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0105-calendar-holidays-only-candidate/Valora.app` |
| 版本 / 构建号 | `0.2.0` / **15**（`Info.plist` 与 `build-verification.json` 一致） |
| binary SHA-256 | `3b0284706ccdb881f19aaaf8cedce0d4013fee7535f7617dff01128affdd381f` |
| 签名 | `codesign --verify --strict --deep` 通过 |
| 用途声明 | `用于读取日历中的节假日与休班信息。` |
| 替换 | 退出前明确记录当前 PID 63480 / `/private/tmp/valora-v0104-…`；用 `tell application id "com.wangqing.valora" to quit` 正常退出 → 0 个实例 → 打开新候选 → 仅 1 个进程 PID 69159，路径为新候选 |

本次未出现 LaunchServices 启动 `dist` 的情况（按 id 定向退出，未按名称）；未用 pkill/强退，未覆盖 `dist`/运行包，未安装发布或 Git 提交。

## 五、V0104 口径更正

V0104 报告曾写“用户机器上恰好有两个可信节假日来源”。该说法**未经真实读取验证**，已在原报告追加更正：可复现的因果是“存在多个匹配来源时只过滤了选中一个”，fixture 可复现；用户机器实际来源数量未读取、不作为结论。V0104 原失败日志与证据保留，V0104 的独立接受结论不变。

## 六、历史测试退役说明

`docs/verification/independent-v0104/decision.md` 中 personal events 相关失败事实保留；对应测试函数已随功能删除，不再修复该缓存。原 `IndependentCalendarSelectionIsolationTests` 的断言语义由节假日权限/生命周期剩余断言替代，未清空全部日历测试。

## 七、边界与复验

- 未用真实日历/真实节假日源验证；修复与删除依据是源码引用与 fixture。
- 日历 UI 字体/宽度 400/网格 368/两行摘要/卡片颜色未改；音乐/锁屏/耳机/图标/`重置卡 N 张` 未动。
- 用户只需重看日历：10 月 1 日绿色节假日/休班在，蓝色个人事件区与“正在获取日程”不再出现；不需要重做已通过的音乐/锁屏组。
- 停等 Codex 独立验收；不进入性能专项。
