# V0093 Codex 用量单行与剩余内存格式

执行：现有 OpenCode 会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，分支 `codex/music-display-lock-policy` 工作区（未 reset/checkout，未覆盖 Codex 已完成的内嵌歌词/锁屏选屏/用户 V 图标）。
未 Git 提交/推送、未安装发布、归档只读；未控制真实播放、音量、耳机、系统锁屏/登录/权限，未读个人日程或账户身份。

## 一、来源与恢复范围

| 复用件 | 来源（只读证据） | 处理 |
|---|---|---|
| 额度模型/解析（含还剩余额派生、多桶、畸形字段、重置卡） | `docs/verification/v0030-r4/source/CodexUsageModels.swift`（V0028 独立接受版本） | 原样恢复为 `Sources/Valora/CodexUsageModels.swift`，补 `CodexUsageError` |
| 刷新调度 | `docs/verification/v0030-r4/source/CodexRefreshScheduling.swift` | 原样恢复 |
| Provider（单在途、代次、节流、冷却、旧回调拒绝） | `docs/verification/v0030-r5-r1/source/CodexUsageProvider.swift` | 原样恢复 |
| 传输 | V0028 用的是第三方 `CodexAppServerClient`，**该源码不在本仓库**（仅有任务/验收文档） | 自写最小只读客户端 `CodexAppServerClient.swift` |

传输只允许三个方法（常量 `allowedMethods`）：`initialize`、`initialized`、`account/rateLimits/read`。
不读 `auth.json`、令牌、会话/对话、账户 email，不发模型请求，不执行重置；引擎只在本机固定路径查找（`/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`、`/opt/homebrew/bin/codex`、`/usr/local/bin/codex`、`~/.local/bin/codex`、`~/.codex/bin/codex`），找不到就报 `missingEngine` 且不启动任何进程。
子进程有 8s 超时、SIGTERM→SIGKILL 收尾；关闭开关会停止计时器/任务，旧回调按代次丢弃。

**真实只读握手已在 shell 有界验证一次**（本机 `codex-cli 0.166.0-alpha.6`）：

```
initialize → {"userAgent":"valora/0.166.0-alpha.6 ..."}
account/rateLimits/read → {"ordinaryUsageAllowed":true,"rateLimits":{"limitId":"codex",
   "primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":...}}}
```

本次**没有**在 App 内主动发起真实额度读取（开关默认关闭）；上面只证明协议与解析路径可用，真实账号额度/重置时间仍以用户开启后的实机结果为准。

## 二、UI

- **设置**：侧栏「菜单栏」组里、**系统监控正下方**新增独立页「Codex 用量」，卡内只有**一个总开关**（键 `enableCodexUsage`，默认关闭），沿用现有 Alcove 行式/开关样式，无品牌素材、无说明段、无其它选项。
- **展开面板**：只在现有「监控 + 日历」共享面板里增加一行，位置在监控摘要之下、日历之上：

  ```
  5H 79% 19:00    WEEK 97% 11/12 14:00    重置卡 2张
  ```

  - 11pt regular、secondary、左右内容 16pt、卡片内边距 12pt、HStack spacing 12，与 `MonitorSummaryCard` 完全一致；无标题/图标/进度条/悬停/二级面板/缩字；
  - 百分比一律是**剩余额度**（`100 − usedPercent`），与 Codex 自身显示一致；
  - 5H 同日显示 `HH:mm`，跨日显示 `MM/dd HH:mm`；WEEK 固定 `MM/dd HH:mm`（本地时区）；
  - 无数据显示 `—`（不是 0%/0 张）；重置卡只显示数量，不执行重置。
- **菜单栏**：**没有**新增图标/百分比/5H、WEEK 入口；软件 V 图标与左右键行为未改。
- 该行由自己的开关控制，与系统监控开关独立（关监控、日历入口仍开时也能显示）；开关关闭时整行移除并停止后台刷新，不只是隐藏。

## 三、内存格式

- 「剩余内存」固定一位小数：`UIStyle.memoryRemainingString` → `9.0 GB / 9.2 GB / 10.0 GB`；
- 「内存总量」仍走原 `memoryCapacityString` → `32 GB`（不会变成 32.0 GB），两者用不同函数，避免总量被全局改动；
- 磁盘、运行时长的格式未动。

## 四、定向验证（无窗口）

```
swift test --filter "CodexUsageSummaryTests"
swift test --filter "CodexUsageSummaryTests|LockMusicCoordinatorTests|LockMusicStateTests|LockCardAppearanceTests"
```

| 用例 | 覆盖 |
|---|---|
| `testRemainingPercentIsDerivedFromUsed` | 21→79%、3→97% |
| `testParserKeepsUsedAndRemainingApart` | 协议 fixture（primary 21 / secondary 3 / 可用卡 2） |
| `testParserDoesNotTreatMissingCreditsAsZero` | 重置卡缺失 → `重置卡 —` |
| `testUnknownValuesNeverRenderAsZero` | 5H/WEEK/重置卡缺失全部 `—` |
| `testZeroUsedRendersFullRemaining` | 0 不做假、100% 用尽 |
| `testFiveHourUsesClockWhenResettingTodayAndDateWhenCrossingDays` | 同日 `HH:mm`、跨日带日期 |
| `testWeekAlwaysCarriesDateAndTime` | WEEK 必须带日期 |
| `testLongestCommonLineFitsTheContentWidth` | 用真实 11pt 字体量「5H 100% 23:59 / WEEK 100% 12/31 23:59 / 重置卡 99张」≤ 344pt |
| `testMemoryRemainingAlwaysKeepsOneDecimal` / `testMemoryTotalStaysWhole` | 9.0/9.2/10.0 GB 与 32 GB |
| `testCodexUsagePageSitsRightBelowSystemMonitorInTheMenuBarGroup` | 侧栏位置紧跟系统监控 |
| `testStopCancelsTheScheduledRefreshAndIgnoresTheOldCallback` | 关闭后计时器取消、旧回调不再读取、状态非运行 |
| `testDisablingRemovesTheRowWithoutTouchingMonitorOrCalendar` | 行移除不影响监控/日历可见性 |

结果：新增 13 项 + 协调器 32 + 状态 13 + 外观 4 = **49 项通过**（未跑全量、未跑建窗/闪窗/性能类）。

## 五、构建 / 单实例替换

- 候选：`/private/tmp/valora-v0093-codex-usage-candidate/Valora.app`
- binary SHA-256：`84c254fbf300b18bd7575c640ae616476b0131c64625beb9d304fcbadd798d8b`
- `codesign --verify --strict --deep` 通过；`dist/Valora.app` 未动
- 替换：`pkill -f "MacOS/Valora"` → 复查 0 实例 → `open -n` 候选 → 复查**仅 1 个进程**，路径 `/private/tmp/valora-v0093-codex-usage-candidate/Valora.app/Contents/MacOS/Valora`（PID 32770）

## 六、仍未验/边界

1. App 内真实额度读取未主动触发（开关默认 off）；真实账号下的 5H/WEEK 数值、重置时间、重置卡数量以用户开启后为准，失败会显示明确状态（未找到引擎/未登录/超时/协议不兼容），不会把旧缓存当实时成功。
2. 跨日/极远重置时间的短日期格式以本机 locale/时区渲染，未在其它时区实测。
3. 共享面板高度只增加这一行，滚动沿用现有策略；面板日历部分未改动。

## 七、V0094 用户反馈修正

1. **5H 也带日期**：`5H 79% 11/12 19:00`（`MM/dd HH:mm` 本地时区），不再同日只给 `HH:mm`；面板空间足够，且跨午夜无歧义。
2. **两行监控挨在一起**：Codex 用量行不再单独一张卡片，改为**同一张卡片内**、与内存/磁盘/运行时长之间用 1pt 分隔线 + 8pt 间距；日历与卡片之间的间距保持不变（用户明确"日历隔得远没问题"）。
3. 若系统监控开关关闭但 Codex 开关打开，同一张卡片只显示 Codex 行。

验证：`CodexUsageSummaryTests` 13 项更新后通过（其中 5H 断言改为"必须带日期"，最宽行按 `5H 100% 12/31 23:59 / WEEK 100% 12/31 23:59 / 重置卡 99张` 用真实 11pt 字体仍 ≤344pt）。

候选：`/private/tmp/valora-v0094-codex-row-tight-candidate`，binary SHA-256 `7914f53cbdb49adc6a43ededc455d8c30354af7e38a0c61b23b9b3b75e031543`，签名通过；已单实例替换（pkill 至 0 → 启动 → 仅 1 进程 PID 36813）。
