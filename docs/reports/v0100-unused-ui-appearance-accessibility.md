# V0100：无引用残留、失效外观实验、摘要无障碍与过时注释

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，分支 `codex/final-cleanup`。
可见 UI/材质/布局未改；Objective-C/Perl 保留；未 Git 提交。

## 一、删除无引用残留

| 项 | 引用证据 | 处理 |
|---|---|---|
| `CodexUsageSummaryRow` 独立卡片 View | 全仓搜索除定义文件外 **0 处**引用（当前实际使用是 `MonitorSummaryCard` 内的同卡 Grid） | 删除该 View；文件改名 `CodexUsageSummaryFormatter.swift` 只保留仍被 `CalendarMonitorSharedView` 与测试使用的 `CodexUsageSummaryFormatter` |
| `PreviewCodexUsage`（样例额度注入） | 全仓 **0 处**调用 | 删除 |
| `LockCardAppearance`（`glassOverride` / `glassScheme` / `contentScheme` / `VALORA_LOCK_CARD_GLASS` / `wallpaperIsNearlyWhite` / 浅色 palette） | 生产 **0 处**读取（只有测试）；`LockGlassSurface` 实际固定 `.darkAqua` + variant 5，播放器只用 `palette` | 删除实验外观结构，文件改名 `LockCardPalette.swift`，只留实际使用的白色墨色 palette（`primary/secondary/waveform/track` 数值不变） |

配套测试调整（不是保留已删功能）：
- `LockCardAppearanceTests` → `LockCardPaletteTests`（2 项）：只断言当前生产读取的白色墨色与派生透明度；
- 原"浅色玻璃 / 近白壁纸翻转墨色 / 背景前景独立"三类断言随已删除的接口一并移除，因为这些行为在 Valora 里从来没有输入来源。

未动：额度后台生命周期、日期/剩余百分比格式、两行同卡 Grid/字体/对齐、`CodexUsageSummaryFormatter` 的公开行为。

## 二、摘要卡无障碍按真实显示内容

新增纯函数 `MonitorSummaryAccessibility.label(showsStats:codex:stats:now:)`，`MonitorSummaryCard` 用它作为 `accessibilityLabel`：

- 只监控 → 内存总量/剩余、磁盘总量/剩余、运行时长；
- 只 Codex → `5H …`、`WEEK …`、`重置卡 …`；
- 两者都有 → 全部；
- 都没有 → 空字符串（不输出虚假监控或额度）。

可见文本、布局、开关与数据取值均未改。新增 `MonitorSummaryAccessibilityTests` 4 项覆盖这四种组合。

## 三、过时注释

`ReferenceCore.LockMusicState` 中 `reserveFullExpansion` 的 "so opening the volume and the lyric row can never cover the avatar" 改为：
> 外接/合盖目标在同一**产品参考线**（屏高 21%，macOS 不提供登录头像边界）之上为完整展开预留；这只让布局可预期，**不保证**不遮挡头像；内置屏维持已认可锚点。

数值（21% / 240 / 164+32）与真实外接接线未动。

## 四、验证（无窗口）

| 套件 | 数量 | 结果 |
|---|---|---|
| `MonitorSummaryAccessibilityTests`（新增） | 4 | 通过 |
| `LockCardPaletteTests` | 2 | 通过 |
| `CodexUsageSummaryTests`（formatter 行为不变） | 14 | 通过 |
| 合计 | 20 | 0 失败 |

未跑全量、未做资源/性能审计、无真实媒体/权限/锁屏操作。

## 五、构建 / 单实例替换

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0100-residue-cleanup-candidate/Valora.app` |
| 版本 / 构建号 | `0.2.0` / **9**（`build-verification.json` 同为 9） |
| binary SHA-256 | `cf046ac2c97c54fdb451715f52b2877f73f0d67066ca1e1add2d27e09e4386eb` |
| 签名 | `codesign --verify --strict --deep` 通过 |

替换：AppleScript `quit` 正常退出 build 8 → 复查 0 实例 → `open -n` 新候选 → 复查**仅 1 个进程**（PID 17859）；未用 pkill；`dist` 未覆盖。

## 六、数量更正

`docs/reports/v0099-r1-cancel-media-subscriptions.md` 里 `MediaScheduleTests` 写的 6 实际是 **5** 项（独立验收记录 11 项相关测试），已在原报告加更正说明。

## 七、未做

验证代码编译边界与 `AGENTS.md` 历史归档（下一批）；未删用户资源/图标旧候选/历史报告/许可证；未做全局无引用自动删除。
