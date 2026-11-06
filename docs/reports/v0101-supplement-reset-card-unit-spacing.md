# V0101 补充：重置卡单位间距

执行：现有会话，分支 `codex/final-cleanup`。本补充在 V0101 编译隔离交付（build 11）之后单独完成，未并行改生产文件，也未回退任何编译边界成果。未 Git 提交/推送。

## 一、问题与改动

用户实看截图确认：build 11 仍显示 `重置卡 2张`，数字与单位贴得太近。授权落地为 `重置卡 2 张`。

`Sources/Valora/CodexUsageSummaryFormatter.swift`：

```swift
// 之前
return "重置卡 \(count)张"
// 现在
return "重置卡 \(count) 张"
```

- 正整数 `2` → `重置卡 2 张`；`0` → `重置卡 0 张`（同一分支，自然一致）；
- 未知（nil / 负数）仍 → `重置卡 —`，不伪造 0；
- 注释同步说明这个空格是用户阅读要求，避免以后又被“优化”掉。

未动：Grid 三列、左对齐、字号 11pt、边距（16+12）、两行同卡布局、`5H`/`WEEK` 文本与日期格式。没有新增列、没有补齐空格、没有 `minimumScaleFactor`。

摘要朗读使用同一 `resetCredits`，因此 VoiceOver 文本随之变为 `重置卡 2 张`，未另有分支。

## 二、断言与宽度 fixture 同步（未放宽）

| 文件 | 更新 |
|---|---|
| `Tests/ValoraTests/CodexUsageSummaryTests.swift` | `0` 的期望改为 `重置卡 0 张`；两处宽度 fixture 的 `重置卡 99张` 改为 `重置卡 99 张` |
| `Tests/ValoraTests/MonitorSummaryAccessibilityTests.swift` | Codex-only / 两者都显示两处 `重置卡 2张` 断言改为 `重置卡 2 张`；“只监控”仍断言不含 `重置卡` |

宽度要求保持不变且仍用真实字体测量（`NSFont.systemFont(ofSize: 11)`）：

- `testLongestCommonLineFitsTheContentWidth`：单行总宽 ≤ **344pt**（400 面板 − 2×16 内容边距 − 2×12 卡片内边距）；
- `testTwoRowsShareColumnWidthsAndFitTheCard`：三列共享列宽后总宽 ≤ **344pt**。

加一个空格后这两项仍通过，说明单元间距没有被“放宽可读宽度”换掉。

## 三、验证（只相关、无窗口）

| 套件 | 数量 | 结果 |
|---|---|---|
| `CodexUsageSummaryTests` | 14 | 通过 |
| `MonitorSummaryAccessibilityTests` | 4 | 通过 |
| 合计 | **18** | 0 失败 |

未跑全量、未跑 QA/审计 UI、未做闪窗/性能/资源审计、未触真实额度查询或系统权限。

## 四、Release 交付

因 V0101 已打包，按“独立下一构建自动 +1”执行，未并入 build 11。

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0101-supplement-reset-card-candidate/Valora.app` |
| 版本 / 构建号 | `0.2.0` / **12**（`Info.plist` 与 `build-verification.json` 一致） |
| binary SHA-256 | `2573c084b4544e32a2660a62c5ea53a665663fb1eba053c3dd6e207ebea62b86` |
| 签名 | `codesign --verify --strict --deep` 通过 |
| 替换 | AppleScript `quit` 正常退出 build 11 → 复查 0 实例 → `open -n` 新候选 → 复查仅 1 个进程（PID 33728，稳定运行，无新崩溃报告） |

保留的编译边界证据在本候选上复核：`--verify-music` 仍 `exit=2` 并提示 development-only；`nm` 中验证/审计符号 **0**，`strings` 中开发文案 **0**。未用 pkill、未覆盖运行中的 `.app` 或 `dist`、未安装发布。

## 五、状态说明

本补充**已完成**（formatter + 断言 + 宽度 fixture + build 12 单实例替换）。V0101 主体（编译边界）仍待 Codex 独立验收，本补充不自行宣称主体通过，也未改动其他功能。
