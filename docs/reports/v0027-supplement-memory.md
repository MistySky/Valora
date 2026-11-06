# V0027 补充：菜单栏面板内存增长专项验证

## 范围与结论

- 接续 V0027 Calmon 迁入；不重做 UI，不改设置/刘海/音乐歌词/设备/品牌。
- 用户报告的“旧 Calmon 点击菜单后内存增长”仅作为必验项，不预设为已定位泄漏，也不继承来源自述的优化结论。
- 本补充在该迁移实现上独立做生命周期/内存审计；**没有观察到暖机后持续阶梯增长**。首开存在明显的 SwiftUI/NSHostingView/字体/图标一次性预热峰值，关窗静置回落；30 轮循环后无持续增长，两个模块各自连续 3 分钟保持稳定（物理足迹与 RSS 原始点见证据）。
- 不设 MB 阈值作为“通过”依据；报告只给原始时间序列、观测范围和环境边界。

## 内部修复（不改变可见 UI）

| 位置 | 问题 | 最小修复 | 验证 |
|---|---|---|---|
| `Sources/Valora/AppMemoryReader.swift` | Calmon 进程图标缓存随应用出现增长，没有上限 | 加 `iconCacheLimit = 128`；达到上限时清空后插入；`purge`/`trimCache` 保持清理 | `testApplicationIconCacheIsBoundedAndTrimClearsIt`；审计 cache=0（fake reader） |
| `Sources/Valora/MenuBarModuleController.swift` | stop 时依赖异步 close 回调释放 content view tree | stop 显式把两个 popover 的 `contentViewController` 置 nil，再移除 status item | 内存审计 deallocated 全 true；重复 start 测试 |
| `CalmonCalendarModel` / `SystemMonitor` | 缺少可观测计数，无法区分必要 CPU 采样、事件读取和丢弃 | 加只读内部计数：event starts/completions/discards、sample starts/completions/discards | 审计报告和定向测试 |
| 菜单栏面板生命周期 | 关闭后不应继续应用列表/磁盘/日程读取；CPU/MEM 必要采样保留 | 保持 V0027 的 panel-visible 门；本次只审计和显式释放；不关闭 3s CPU/MEM 基础采样 | 审计连续段；sample 继续、event 停止 |

没有改布局、字体、间距、图标、材质、可见按钮或交互。没有新增状态项、设置项、权限或功能。

## 生命周期审查结论

- **Popover / NSHostingController**：模块只复用两个 `NSPopover`；关闭时 `popoverDidClose` 清空 contentViewController，`stop` 再显式置 nil 并移除 status item。审计 stop 后 controller、monitor、calendar、reader 全部释放；30 轮后 status item identity 仍各 1 个。
- **Observation/Combine**：`MenuBarModuleController` 的 monitor/calendar 观察使用 `withObservationTracking` + weak self，stop 后以 started 拒绝旧回调；AppDelegate 的 permissions/draft Combine 订阅在进程生命周期内持有，未按次点击新建。没有每次点击新增订阅。
- **通知 token**：日历默认/workspace token、controller sleep/wake token 在 stop 时移除；stop 后日期通知测试不再更新。
- **Timer / 采样**：3s CPU/MEM Timer 只由 `SystemMonitor.start/stop` 管理；面板关闭不销毁必要 CPU/MEM 采样，应用列表/磁盘在面板关闭时停止；模块停止时 timer/reader purge 全部停止。审计中 sample 计数在面板关闭后继续是必要行为。
- **Task / 异步事件**：日历 eventTask 取消、generation 校验、单在途 latch；close/失权后的完成结果丢弃。30 轮为 31 次 event start/completion，无每轮叠加；连续 3 分钟事件读取次数不增长。
- **闭包捕获**：timer/queue/notify 回调使用 weak self 或显式 controller stop；stop 后没有复活弹窗或状态项。
- **图标缓存**：真实 `AppMemoryReader` 硬上限 128；溢出清空、panel close/stop purge/trim；GUI 不显示缓存内容。

## 审计方法

命令：

```sh
/private/tmp/valora-v0027-candidate/Valora.app/Contents/MacOS/Valora \
  --audit-menubar-memory docs/verification/v0027/memory-audit
```

- 真实独立 `NSStatusItem` 和两个 `NSPopover`；测试进程自行退出。
- 日历事件使用 `PreviewCalendarEvents` fake；应用内存列表使用 `AuditAppMemoryReader` fake。
- CPU/MEM 使用 `SystemMonitor` 的真实公开调度（3s），应用列表/磁盘只在面板可见时读取；真实公开指标只用于有界本机核对。
- 不查个人 EventKit/日程、不读媒体、不控制播放器、不操作权限/设备。
- 记录同进程 `ri_phys_footprint`、`resident_size`、monitor sampling、sample/event 计数、状态项身份、fake cache。
- 流程：冷启动基线 → 开始 → 首次打开/关闭预热 → 日历 30 轮 → 监控 30 轮 → 各关闭静置 → 日历连续 180s → 监控连续 180s → 关闭 → stop/nil-out。

- 原始点：144 个，时长 **454.2 s**；`memory-audit.json`。
- 分析摘要：`analysis.json`。

## 原始观测

| 阶段 | physical footprint | RSS | 事件 | 说明 |
|---|---:|---:|---|---|
| 冷进程基线 | 12.3 MiB | 47.1 MiB | — | status item/view 未创建 |
| 首次日历打开 | 68.3 MiB | 82.3 MiB | 1/1 | 首开宿主/字体/图标预热峰值 |
| 首次关闭静置 | 46.2 MiB | 83.3 MiB | 0 visible events | 回落；不是回到冷值 |
| 首次监控打开 | 75.9 MiB | 87.9 MiB | — | 首开应用列表/图形预热 |
| 首次监控关闭静置 | 45.8 MiB | 84.6 MiB | — | 回落 |
| 日历 30 轮末 | 81.6 MiB（关后立即） | 85.5 MiB | 31/31 累计 | 事件不再增加；关后长静置约 39.6 MiB |
| 监控 30 轮末 | 65.1 MiB（关后立即） | 85.7 MiB | — | 必要 CPU/MEM 采样继续 |
| 日历连续 180s | 48.0 → 47.5 MiB | 87.1 → 86.4 MiB | 32 starts / 32 completions | 同一事件，无新读取；30s 后拟合约 −0.009 MB/min |
| 监控连续 180s | 44.4 → 44.3 MiB | 85.6 → 85.5 MiB | — | 30s 后拟合约 −0.003 MB/min |
| stop/nil-out | — | — | — | controller/monitor/calendar/reader 全部释放 |

- 状态项身份：启动后 monitor 1 个、calendar 1 个；两个 popover 各 1 个身份。没有每轮新建状态项。
- `calendarEventStarts == calendarEventCompletions`；关闭后没有继续事件查询。`calendarEvents` 在关闭后清空。
- 连续 3 分钟段内事件读取保持 32 次，不随 5 秒采样增长；每个 5 秒样本同时记录对应 popover `isShown=true`（日历 36/36、监控 36/36），没有把焦点被其他 QA 进程打断的样本称为连续开窗。
- 监控 sample 计数在关闭面板后继续增长，这是必要的 CPU/MEM 菜单栏采样；应用列表/磁盘/日程查询没有继续。没有把该必要采样误判为泄漏。
- `staleSamples` 只出现在面板/生命周期切换时；generation 丢弃路径生效。
- fake reader 的 `iconCacheEntries` 为 0（fake 没有图标缓存）；真实 `AppMemoryReader` 的上限/trim 由单独测试覆盖。

## 验证

- 完整 `swift test`：**263/263 通过**（Valora 149 + ReferenceCore 114）。
- 定向：**28/28**（日历 5、独立生命周期 9、系统监控 9、菜单栏控制器 5）。
- `--verify-menu-modules`：独立状态项/弹窗、基础菜单、关闭成功；应用图标菜单改由 `AppDelegate.applicationStatusMenuForVerification()` 的生产 `rebuildStatusMenu` 路径生成，并检查实际音乐/显示器项，不使用手工样例菜单。
- `--verify-settings` 导航、`--verify-music` fake 74/74、`--verify-menubar` 应用图标通过。
- Candidate：`ec5e18b87b632083048394b306809e182757b224c248c55d50e190515e2350a1`。
- 用户 `dist` 仍为 `19ba9a0f...`，本补充未覆盖/退出用户应用。

## 证据

- `docs/verification/v0027/memory-audit/memory-audit.json`：144 点原始数据
- `docs/verification/v0027/memory-audit/analysis.json`
- `docs/verification/v0027/memory-audit/README.md`
- `docs/verification/v0027/logs/full-test.log`、`targeted-tests.log`
- `docs/verification/v0027/native/`、`settings/`、`music-fake/`、`app-icon/`
- `docs/verification/v0027/source-mapping.md`、`source-manifest.json`、`removed.json`

## 边界

- 单机、同进程、同外观的一次 7.5 分钟审计；不能证明所有 macOS 字体缓存、辅助功能、物理多屏或未来系统版本都与本次一致。
- 没有真实个人日程/账号；fake 事件和 fake 应用列表只用于结构验证。
- 未做真实鼠标点击/真实系统菜单排序/屏幕材质截图；native status item/popover 的创建与释放是隔离进程实际对象。
- 不承诺 RSS 必须回到冷启动精确值；只报告原始趋势和预热差异。
