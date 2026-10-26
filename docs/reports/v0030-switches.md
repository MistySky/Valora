# V0030 同轮补齐 — 功能总开关与软件图标开关

任务：`docs/pi-tasks/v0030-supplement-feature-switches-and-app-icon.md`
SHA256：`29acd0cfc7acf7ef2a95beac3a94c503f5d69b06291be42f7cf0006a9f9e4613`

状态：**功能和定向验证已交付；等待 Codex 独立验收。**
V0030 主体未重做，V0031 未开始。

## 1. 功能开关

设置页保持原 Alcove 侧栏、13pt 顶部间距和卡片样式，只把三个占位页替换为实际开关，并在通用页增加一行：

| 页面 | 开关 key | 默认 | 行为 |
|---|---|---|---|
| 通用 | `showApplicationMenuBarIcon` | 开 | 只控制 Valora V 软件 status item 是否显示；不影响刘海、音乐或其他模块 |
| 系统监控 | `enableSystemMonitor` | 开 | 开启才创建/继续监控；关闭停止采样、移除入口、关闭 popover |
| AI 用量 | `enableAIUsage` | 开 | 开启才启动 Codex 用量 provider；关闭停止刷新/定时器/在途请求，拒绝迟到响应 |
| 下载 | `enableDownloads` | 开 | 开启才创建下载 controller/service；关闭暂停全部任务、保存记录和 partial，不删除文件，不自动重启网络任务 |

`SettingsView` 使用真实 `SettingsToggleRow` / `SettingsDraft.binding`，不是静态卡片。
设置变更通过既有 `ValoraSettingsDraftChanged` 通知进入 `AppDelegate.applyFeatureSettings()`。
`SettingsDraft` 使用传入的 runtime suite，默认值均为开，用户显式关闭后持久化。

### 系统监控

- 关闭前已启动：`monitor.stop()`，停止 Timer，移除 status item，关闭 popover。
- 启动时关闭：`MenuBarModuleController.start` 不创建 monitor item、不调用 `monitor.start()`，采样计数保持 0。
- 再开启：重新启动同一个 `SystemMonitor`，不创建第二个 provider。

### AI 用量

- 启动时关闭：Codex provider 对象仍由应用持有，但不调用 `start()`；无定时器、无 app-server 请求。
- 关闭时：`CodexUsageProvider.stop()` 取消 timer/Task、`generation` 递增；迟到结果 `finishRequest` 丢弃且不提交。
- 再开启：复用同一个 provider；不创建第二个 provider；先前的 in-flight 仍由原 owner 结束。
- AI 页面保留 Codex 说明，但不再显示“功能准备中”。

### 下载

- `DownloadServicing` 增加 `pauseAllAndSave()`；真实 adapter 使用 `manager.pauseAll()` + `saveBeforeTermination()`，fake 仅更新 paused 状态。
- `DownloadMenuBarController.suspendAndStop()`：关闭 popover → pauseAllAndSave → stop（移除入口、停止 model timer、service shutdown 保存）。
- 关闭不删除任务或 partial；再次开启复用同一 controller/service，任务保持 paused，不自动 resume。
- 正常启动 `enableDownloads=false` 时不构造 `DownloadEngineService`，不读取/创建下载 manager；用户开启后才创建。
- 设置页下载说明明确“再次开启只恢复列表和暂停状态，不自动重新开始网络下载”。

## 2. 软件图标开关

- 通用页新增“显示菜单栏图标”开关，默认开，持久化。
- 关闭：设置 `statusItem.isVisible = false`，保留同一 `NSStatusItem` 和完整音乐管理菜单；不关闭刘海、音乐、模块入口。
- 重新开启：复用原 status item，不创建第二个；隐藏前已创建的完整音乐菜单仍在。
- 如果启动时持久化为关：`setupMenu` 不创建 status item；之后开启才创建一次。
- 所有模块关闭时，软件图标仍由该开关独立决定。
- 刘海右键“设置…”等恢复入口未删除。

## 3. 验证

本次按补充策略只做定向验证，没有重复全量 317 项测试。

- 定向：**50/50**
  - `FeatureSwitchTests` 5/5
  - `DownloadMenuModelTests` 6/6
  - `DownloadEngineIsolationTests` 7/7
  - `MenuBarModuleControllerTests` 6/6
  - `IndependentMenuBarMigrationTests` 4/4
  - `SettingsReductionTests` 9/9
  - `CodexUsageProviderTests` 8/8
  - `CalmonCalendarTests` 5/5
- 新增关键回归：
  - 系统监控 off 启动不采样；开启后采样；再次 off 后等待 3.2 秒采样计数不增加。
  - AI off 启动不请求；开启产生一次请求；off 后迟到响应不提交、不新增请求。
  - 下载功能 off 的真实本地 Range：已有非零 partial 后 pause、保存、停止，bytes 不继续增长，partial 未被删除；重新开启后同任务保持 paused，activeCount 0，不自动重启。
  - 软件图标 off 时模块 status item 保持；重新开启复用同一 status item identity；off 启动不创建 status item；全部模块 off 时软件图标仍可独立开关。
- 原生设置页（候选实际 app）：
  - `--verify-settings` 40 个页面截图
  - `General` 显示“显示菜单栏图标”
  - `System-Monitor`、`Downloads`、`AI-Usage` 均为实际 `SettingsToggleRow` 页面，没有“Feature in preparation”
- 下载菜单回归：`--verify-downloads` 10 checks / 17 rendered
- 菜单栏模块回归：11 checks / 13 rendered
- 构建/签名：候选 `/private/tmp/valora-v0030-switches-candidate`
  - binary SHA256 `1e78eda5a9072f755ae64834f1b698ba8942ee14f716d25683723f46d7a1ab0d`
  - `codesign --verify --deep --strict` 通过
  - 日历 entitlement 保留；无 Sparkle 链接
  - `dist` 未覆盖，仍为 `19ba9a0f0cae669dcc32eb8f282750f9fd46a71a603d1bb2d01b9f872b0ffd9f`

## 4. 未验证/边界

- 未用真实鼠标点击设置开关；原生页面是实际 SwiftUI `SettingsToggleRow`，绑定和持久化由测试覆盖，点击行为需 Codex/实机确认。
- 未运行真实生产下载 manager（只 local Range 自产临时文件）；真实 Downloads/Trash 未操作。
- 未读取真实用户 Codex 用量、EventKit 日程、系统权限；未改真实浏览器/helper/cookie。
- 系统监控采样测试只验证计数/生命周期，不把真实 CPU 数值当 UI 验收。
- 未重做 V0030 成熟行 UI、下载算法或引擎；未重新跑 3 分钟 popover 内存审计，因为下载 popover/引擎未改，功能 off 路径由定向测试和 stop timer 覆盖。
- 未安装、发布、Git 提交/推送，未改归档或模型历史，未退出或覆盖用户当前应用。

报告证据：`docs/verification/v0030-switches/`
主体报告：`docs/reports/v0030.md`
