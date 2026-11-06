# V0102：现行约定文档与过期测试契约

执行：现有会话，分支 `codex/final-cleanup`。本批只做文档收尾、完整历史归档、一个过期纯测试期望与只读残留分类。**未改产品源码/布局/动画，未构建 Release，未消耗构建号，未替换或重启 App（仍是 build 13，PID 37215），未 Git 提交。**

## 一、历史归档（原样，哈希核对）

| 内容 | 归档位置 | 行数 | SHA-256 |
|---|---|---|---|
| 旧 `AGENTS.md` 全文 | `docs/history/AGENTS-2026-11-05-pre-v0102.md` | 527 | `108b952e18a39ae1c478eed9f4eaa049483581489b9c2967737624295b5b2aa9` |
| 旧 `docs/CONTINUATION-PLAN.md` | `docs/history/CONTINUATION-PLAN-2026-11-05-pre-v0102.md` | 305 | `98fb618e9c6b18f6e4899311163a54a513965cfb9dc5cb4639e047fa1a773c06` |
| 旧 `README.md` | `docs/history/README-2026-11-05-pre-v0102.md` | 53 | `f2e2e7ed48f8496fc5058ebcecce639fe683adf278597eb4ad398f0382bc781b` |
| 旧 `REQUIREMENTS.md` | `docs/history/REQUIREMENTS-2026-11-05-pre-v0102.md` | 33 | `2289c876f53457ea9077b6cc3228a143f4a9e1e85b0312d541c54ba8631e681b` |

- AGENTS 与计划在本批开始时逐字节复制，复制前后 `shasum -a 256` 一致（上表即归档件与原件相同哈希）。
- README/REQUIREMENTS 的旧版取自 `git show HEAD:`（批前工作区未修改这两文件），保留原文。
- 旧历史不删除；归档不构成现行指令，现行契约只在新的 `AGENTS.md` / `REQUIREMENTS.md` / `README.md` / `docs/CONTINUATION-PLAN.md`。

## 二、新 `AGENTS.md`（527 → 103 行）

按“当前有效约定 + 边界 + 索引”重组，不含旧批次流水账：

1. 项目与基线（Alcove 基准、Swift6/macOS27 迁移、歌词为个人新增、UI 不动的内部优化边界）
2. 当前功能与设置页（按实际源码：通用 / 音乐 / 锁定屏幕 / 设备连接 / 日历 / 系统监控 / Codex 用量 / 关于；含内嵌歌词规则、锁屏选屏与 21% 参考线、设备单开关、Codex 两行三列与 `重置卡 N 张`、下载已删除）
3. 品牌资源（彩色应用图标；v11 菜单栏 22×18 画布 / 20×13.64 可见）
4. 工程基线（tools 6.4 / language 6 / macOS 27；三个 target；OC 与 Perl 的实际用途；仅系统媒体源）
5. 开发验证边界（V0101：debug-only `VALORA_DEVELOPMENT`、Release 早拒绝、隔离预览契约、构建号只能由打包入口分配）
6. 测试与验收分工（定向 vs 独立；当前禁止压力/闪窗；真实写操作需当次授权；fake ≠ 实机）
7. 交付与替换（新 `/private/tmp` 候选、构建号 +1、正常退出→0→唯一启动、禁止 pkill、不覆盖 dist、报告停验）
8. 当前状态（0.2.0 / build 13、分支 `codex/final-cleanup`、最近提交 `9869890`、未发布；已接受批次与 decision 索引）
9. 顺序与待办（收尾→全局回归→性能专项；待实机清单）
10. 协作（现有 OpenCode 会话、Codex 验收、定时器关闭）
11. 历史归档索引

## 三、REQUIREMENTS / README / 接续计划

- `REQUIREMENTS.md`（33 → 31 行）：保留“语言与最低系统迁移、非重做、Alcove 为基准”的核心要求，写明当前真实范围（音乐+歌词、锁屏、设备、日历/监控、Codex 面板、已删除下载等）与验证边界。
- `README.md`（53 → 70 行）：更新为当前 scope、品牌、构建（`--output-dir`、自动构建号、禁止 `--build` 覆盖）、运行、**开发验证参数只在 debug 可用且 Release 早拒绝**、文档索引。移除了“首个歌词候选基线、尚未接受”的过期描述。
- `docs/CONTINUATION-PLAN.md`（305 → 44 行）：只保留当前阶段、已接受收尾批次表、待做（全局回归→性能专项→可选小批）、待用户实机、交付规则摘要。旧计划已完整归档。

文档未承诺私有 API 不可替代，也未承诺系统 Perl 一定移除；下载功能标注为已删除且不恢复。

## 四、唯一测试修改

`Tests/ValoraTests/SettingsReductionTests.swift` 的 `testSidebarGroupsFollowTheUserApprovedStructure` 两处旧期望补上已确认的 `Codex 用量`（V0093 新增页面后一直过期）：

- 分组页列表：`["日历", "系统监控"]` → `["日历", "系统监控", "Codex 用量"]`
- 全页面标题：`[… "日历", "系统监控", "关于"]` → `[… "日历", "系统监控", "Codex 用量", "关于"]`

保留：组标题/顺序、去重断言、13pt 顶距、音乐图标等全部其余断言；未改 `SettingsPage`/`SettingsSidebar`/实际 UI。git diff 为 **2 行插入、2 行删除**。

只运行该纯方法（不跑含真实窗口的整套）：

```
Test Case '-[ValoraTests.SettingsReductionTests testSidebarGroupsFollowTheUserApprovedStructure]' passed (0.153 seconds).
```

## 五、V0101 未隔离共享项只读分类

证据均为当前源码行号；本批未改这些产品代码。

| 项 | 引用证据 | 分类 | 结论 |
|---|---|---|---|
| `NotchWindowDiagnostic` | `LockMusicCoordinator.swift:624`、`:709` 用 `isWindowComposited(...) == false` 做 overlay 回落判定；`isEnabled` 守卫的日志写入：`LockMusicCoordinator:261/577/599/633–648/722–744`、`WindowCoordinator:323/337`、`NotchView:107`（`NotchLayoutProbe`） | **生产必需**（合成判定）+ 默认关闭的有界日志/自绘探针 | 不能整类隔离，也不能用空实现替代判定；日志部分与调用点交织（~8 处） |
| `AppMemoryReader` / `SystemMonitor.applications` | 定义 `AppMemoryReader.swift`；`SystemMonitor.swift:73/101/104/202/229/279` 的采样 API 与 `AppUsage`；生产 `AppDelegate.swift:623` 用 `SystemMonitor()`（无 reader）→ `wantApps = panelVisible && reader != nil` 恒 false；仅 `MenuBarMemoryAudit.swift:45` 注入 fake reader | **debug/测试专用能力仍编译**（类型与分支留在生产 monitor） | 生产不会枚举进程；要与成熟 monitor 解耦需改其 API，收益低 |
| `PreviewCalendarEvents` | 定义 `CalendarEvents.swift:68`；`AppDelegate.swift:604` 在 `previewData || startupMode != .production` 分支（Release 不可达但编译）；审计 `CalendarFixedWindowAudit:22`、`CalendarPopoverAudit:49`、`MenuBarMemoryAudit:49` | **debug/测试专用但仍编译** | 可选小批：把所依赖的 preview 分支整体条件化 |
| `StaticLyricsProvider` | `LyricsService.swift:202`；仅 `LyricsServiceTests:211/254` 与 debug 歌词验证使用 | **测试专用仍编译** | 低价值，可随 LyricsService 收口时再议 |
| `NoLyricsProvider` | `LyricsService.swift:207`；`AppDelegate.swift:408` 的生产三元降级（Release 中 `startupMode` 恒 production，不可达） | **debug/测试专用但仍编译** | 同上 |
| `NotchLayoutProbe`（`NotchWindowDiagnostic.swift:304`，`NotchView:108`） | 仅环境变量开启时叠加的 SwiftUI 坐标探针 | debug/取证用途仍编译（运行时默认不显示） | 与 `NotchWindowDiagnostic` 一并考虑 |
| `applicationStatusMenuForVerification`（`AppDelegate.swift:687`） | 全仓无调用 | **完全无引用**（已在 V0101 移入开发区，Release 不含） | 可在后续小批删除；本批未动 |

建议：**不值得**为减少行数拆 `SystemMonitor`/`AppMemoryReader`；若要再做一小批，优先 `PreviewCalendarEvents` + 两个 lyrics provider 的条件化，以及 `applicationStatusMenuForVerification` 的删除，`NotchWindowDiagnostic` 只拆日志、保留 `isWindowComposited`。均需单独立项，不在本批执行。

## 六、边界与未做

- 未构建 Release、未消耗构建号（仍是 build 13）、未重启/替换运行包、未跑全量、未跑含真实窗口的整套 `SettingsReductionTests`、未做资源/性能审计、未触真实媒体/权限/锁屏。
- 未 Git 提交/推送。
- 文档中的私有 API/系统行为措辞保持“实现观察 + 待实机”边界，未把未验证组合写成通过。

## 七、待独立验收

本批交付：归档哈希与位置、三份现行文档、一个过期纯测试期望通过、残留分类与建议。请独立核验后决定是否进入完整功能与全局联动回归阶段。
