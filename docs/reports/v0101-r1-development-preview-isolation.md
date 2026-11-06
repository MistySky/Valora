# V0101-R1：两个开发辅助入口的隔离

执行：现有会话，分支 `codex/final-cleanup`。仅修 `--lock-card-preview` / `--expand-media`（含同类 `--preview-long-title`）的启动契约；保留 V0101 的 Release 门控、11 个文件的编译隔离与 build12 的 `重置卡 N 张` 间距修复。未开 QA UI、未启动真实服务、未 Git 提交。只跑相关纯参数/无窗口定向，未跑含窗口的整套 `SettingsReductionTests`。

## 一、失败点（独立验收 2 用例 4 断言）

`--lock-card-preview`、`--expand-media` 都不在 `AppRuntimeDefaults.qaArguments`，`startupMode` 仍为 `.production`、`resolve` 选 `standard`；AppDelegate 走完整生产启动（media/audio/Bluetooth/EventKit 订阅、状态栏、菜单）后才处理这两个 flag。既不是隔离配置，也不是明确拒绝。

## 二、选定契约

| 入口 | 契约 |
|---|---|
| `--lock-card-preview` | **有效开发预览**：QA 隔离 suite + 明确 `.lockCardPreview` 非 production 路径；共享 controller 只构造、**不 start**，不建状态栏/菜单/日历授权订阅，显示真实锁屏音乐卡（fixture 曲目，无真实播放）；在 `model.media.start()` 之前 `return`。 |
| `--expand-media` 单独 | **早拒绝**：它只为真实媒体会话设计；进入 `.invalidDevelopmentCombination("--expand-media")`，在 AppDelegate 构造 controller 之前 `exit(2)`，明确提示“只能作为 `--preview-music` 的修饰符”。不静默回落 production，不恢复真实探针。 |
| `--preview-long-title` 单独 | **早拒绝**（同上，提示需 `--preview-music`）；与 `--preview-music` 同时出现时仍是 `.previewMusic`，行为不变。 |
| `--expand-media` + `--preview-music` | 仍是 `.previewMusic`（synthetic 预览本身已展开），不拒绝；`--preview-music` 优先。 |
| Release | `main.swift` 门控不变，仍先于 `NSApplication.shared` 拒绝这三个 flag（未从名单删除）。 |

实现位置：

- `AppRuntimeDefaults`：`qaArguments` 加入三个 flag；`StartupMode` 新增 `lockCardPreview` 与 `invalidDevelopmentCombination(String)`；`startupMode(arguments:)` 在 `--preview-settings` / `--preview-music` 之后判定三者（明确优先级）。
- `LaunchPolicy.developmentStartupRejection(_:)`：把“无效组合”转成可测的纯函数返回值。
- `AppDelegate`：dev 区第一句即拒绝无效组合（`fputs` + `exit(2)`）；共享 controller 构造之后新增 `.lockCardPreview` 分支（fixture + `LockCardPreviewController` + `return`）；共享构造后加 `assert(model.media/audio/bluetooth != nil, …)` 守卫，防止再把共享初始化误条件化；删除原先“服务启动后才处理 `--lock-card-preview` / `--expand-media`”的不可达代码块。

`.lockCardPreview` 分支不调用 `setupMenu()`，因此不建状态栏/菜单模块、不触发监控采样或日历读事件；预览为卡片窗口本身（`VALORA_LOCK_PREVIEW_CLICKABLE` / `VALORA_LOCK_PREVIEW_ORIGIN` 环境变量仍有效）。退出用 `osascript -e 'tell application "Valora" to quit'`。

## 三、验证（纯参数/无窗口）

| 套件 | 数量 | 结果 |
|---|---|---|
| `IndependentDevelopmentIsolationTests`（原失败，未改动断言） | 2（4 断言） | 通过 |
| `LaunchPolicyTests`（含新增 4 项：lock preview 隔离、expand 单独拒绝、修饰符需 parent、拒绝/预览源码顺序） | 14 | 通过 |
| `LockActivationOwnerTests`（预览复用共享激活生命周期） | 14 | 通过 |
| `CodexUsageSummaryTests`（保留 build12 单位间距） | 14 | 通过 |
| `MonitorSummaryAccessibilityTests`（朗读随 formatter） | 4 | 通过 |
| 合计 | **48** | 0 失败 |

真实 debug 二进制（不显示窗口、不启动服务）实测：

```
.build/out/Products/Debug/Valora --expand-media
→ exit=2 "Valora: --expand-media cannot run standalone; it only modifies --preview-music … No media, audio, Bluetooth or calendar service was started."
--preview-long-title 同
```

未运行 `--lock-card-preview` 本身（属于 QA UI，按本轮要求不打开）；其契约由纯参数与源码顺序断言覆盖（预览分支索引 < `model.media.start()`，拒绝调用索引 < `model.media = MediaController(model)`）。

## 四、Release 交付

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0101-r1-dev-isolation-candidate/Valora.app` |
| 版本 / 构建号 | `0.2.0` / **13**（`Info.plist` 与 `build-verification.json` 一致） |
| binary SHA-256 | `cae680e5c4d51d748ccef6134025e2c2f9172f542094a18f621bb3f0634b34db` |
| 签名 | `codesign --verify --strict --deep` 通过 |
| 替换 | AppleScript `quit` 正常退出 build 12 → 复查 0 实例 → `open -n` 新候选 → 复查仅 1 个进程（PID 37215，稳定运行，无新崩溃报告） |

Release 侧复核：打包后的二进制带 `--lock-card-preview` / `--expand-media` / `--preview-long-title` 均 `exit=2` 且提示 development-only；`nm` 中验证/审计实现符号 **0**。未用 pkill、未覆盖运行中的 `.app` 或 `dist`、未安装发布。

## 五、未做与保留

- 未跑 `SettingsReductionTests`（含真实窗口）；其中 `testSidebarGroupsFollowTheUserApprovedStructure` 的旧期望漏 `Codex 用量` 页仍保留给后续文档/契约核对批次，不删实际页面。
- 未全量、未资源/性能审计、未真实媒体/权限/锁屏操作。
- V0101 主体仍待 Codex 独立复验；build12 的数字单位间距修复（`重置卡 N 张`）在本候选保留，相关 18 项断言仍通过。
