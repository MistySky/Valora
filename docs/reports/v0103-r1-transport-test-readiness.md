# V0103-R1：传输测试就绪竞态与回归口径

执行：现有会话，分支 `codex/final-cleanup`。**只改测试与报告**：未改产品源码、未构建 Release、未消耗构建号（仍 13）、未重启/替换运行包、未 Git 提交。当前仍运行 `/private/tmp/valora-v0101-r1-dev-isolation-candidate`（PID 37215）。

## 一、失败口径更正（保留历史）

V0103 run 1 的唯一失败 `IndependentCodexTransportTests/testRestartKillsPreviousTerIgnoringChild` 报 `XCTAssertNotNil(pid, "engine did not start")`。

**已确认的测试缺陷**（与首败现象一致，但不能据此断言唯一根因）：

```swift
var pidText: String?
for _ in 0..<50 where pidText == nil {
    pidText = try? String(contentsOf: pidFile, encoding: .utf8)
}
```

`echo $$ > file` 的“创建文件”和“写入内容”不是原子操作，读侧可能先看到**空文件**：`""` 不是 nil，循环立即结束，随后 `pid_t("")` 为 nil → 断言失败。即“空文件被当作就绪”的竞态。

**撤回** V0103 报告中“瞬时系统负载导致”的推断：`contactsd`/AddressBook 日志只是同一时间窗口的系统噪声，不能证明因果。首败仍标注 **未确诊**；本次只确定并修复了测试就绪漏洞，不声称首败唯一根因已找到。

V0103 原报告已追加更正段，原失败记录与日志索引保留未删。

## 二、最小修复（仅测试）

`Tests/ValoraTests/IndependentCodexTransportTests.swift`：

1. 新增 `TransportEngineReadiness`：
   - `readyPID(from:)`：trim 后必须为非空、可解析、**正数** PID；`nil`/空串/空白/`0`/负数/非数字一律“未就绪”。
   - `waitForPID(deadline:read:)`：有界轮询（默认 3s setup deadline），只有有效 PID 才返回；超时返回 nil，绝不无限等待。
2. 真实进程用例改为：
   - fixture 用 `printf … > pid.tmp && mv` **原子发布** PID，避免读侧看到半写文件；
   - 用 `waitForPID` 等**有效 PID** 再取消；
   - 等待失败时保留诊断：文件内容（或 missing）、子任务是否结束、子任务错误，`XCTFail` 输出后再取消收尾，而不是只报一个 nil。
3. 未改动任何产品 deadline/取消语义，也未放宽以下核心断言：
   - 取消读 < 0.6s 停止真实子进程；
   - 静默 stdout 不绕过 2s 产品 deadline（< 2.7s 返回）；
   - 第二次读必须终止忽略 TERM 的旧 child（`kill(pid, 0) == -1`）。

## 三、新增确定性覆盖

| 用例 | 覆盖 |
|---|---|
| `testReadyPIDRejectsEmptyPartialAndPlaceholderValues` | nil/空/空白/非数字/0/负数都不算就绪；`" 4242\n"` 正常解析 |
| `testTransientEmptyFileBecomesReadyWhenAValidPIDArrives` | 读取序列 `["", "  \n", "not-a-pid", "0", "-12", "4242"]`：空文件不会结束等待，最终拿到 4242 |
| `testNoValidPIDEverFailsWithinTheBoundedDeadline` | 序列始终无效时，0.15s 内有界失败（<1s），且轮询次数 >1，不会无限等待 |
| `testRestartKillsPreviousTerIgnoringChild`（既有） | 无效 PID 不再判就绪；正常 TERM 忽略 child 的重启与终止断言保持 |

## 四、实际运行与结果

只跑传输类，**未重跑 398 项/原生/Release**：

| 运行 | 结果 |
|---|---|
| 修复后首次 `swift test --filter IndependentCodexTransportTests` | 7 项 / 0 失败（4.37s） |
| 连续复跑 3 次 | 7 项 / 0 失败（分别 3.50s / 3.50s / 3.51s） |
| 合计 | **28 次用例执行，0 失败** |

日志未单独落盘（输出即本报告数据）；此前 V0103 的失败日志仍在 `/private/tmp/valora-v0103-regression-logs/swift-test.log`，未覆盖。

这不能替代整批回归：V0103 的 398 项安全自动、23 原生场景与两脚本的独立结果仍以原报告为准；本批没有重跑。

## 五、47 项 UI/实机类功能覆盖对照

未运行的类均有真实窗口/状态项副作用；下表把它们对应的用户可见功能标注出来，能由一次实际观察覆盖的写“可观察覆盖”。

| 类（未运行项数） | 覆盖功能 | 可否单次观察 |
|---|---|---|
| `MultiDisplayCoordinatorTests`（17） | 多屏各自面板、活动屏切换、最多一屏展开、次屏 peek、拖拽归属、选主屏收敛、暂停空闲 deadline、歌词留在活动屏、负坐标命中 | 合盖/双屏一次操作可覆盖主要子集 |
| `SettingsReductionTests`（8） | 悬停展开/取消/指针移出、侧栏分组、显示图标、设置窗口复用 | 设置页 + 一次悬停可覆盖 |
| `FeatureSwitchTests`（4） | 三个模块开关建/删状态项、软件图标开关、持久化 | 菜单栏开关一次可覆盖 |
| `IndependentMenuBarMigrationTests`（4） | 日历/监控隐藏再显示恢复、授权刷新后开读 | 菜单栏开关 + 日历授权一次 |
| `MenuBarModuleControllerTests`（5） | 两入口独立、切面板关另一个、关闭停 provider、stop/start 重建 | 菜单栏点击一次 |
| `IndependentInteractionTests`（3） | 设备提示 × 换屏 × 歌词 × 展开音量 × 暂停/低电过期 | 需专门组合，建议实机清单第 3/6 项 |
| `RealMusicTitleDoubleClickTests`（1） | 标题双击打开当前来源（真实宿主） | 播放中双击标题一次 |
| `RealArtworkViewStageTests`（2） | 真实宿主封面翻转、晚到封面不跳过 | 切歌一次观察封面 |
| `IndependentPersistedPermissionTests`（2 个建窗方法） | 登录项设置页归一化不写系统 | 设置通用页一次 |
| `IndependentCalendarLifecycleTests`（1 个状态项方法） | 原生日期文本跨日即时更新 | 菜单栏日期一次 |

## 六、最短用户实机清单（按当前 build 13，一次功能观察）

不需要重做已明确反馈通过的完全相同条件；下列各做一次即可：

1. **锁屏/解锁**：锁一次、解一次，看顶部收起/展开顺序、解锁后焦点恢复、登录界面仍可输入。
2. **合盖外接屏**：合盖用外接屏看锁屏音乐卡位置是否仍遮挡头像（21% 是参考线，不保证）。
3. **耳机**：戴上/摘下 AirPods，看提示出现与消失；看一眼电量。
4. **音乐**：播放→切歌→双击标题；看封面翻转、歌词（紧凑/展开）与音量展开。
5. **菜单栏**：点日历、系统监控、Codex 用量；开关一次模块与软件图标，看显示/隐藏。
6. （可选，组合）设备提示与换屏/歌词同时出现时是否互不干扰。

不自动锁屏、不控制音乐、不触发权限；只做观察。

## 七、状态

- V0103 安全自动范围已独立接受；47 项 UI/实机与真实功能仍未验收，**不进入性能专项**。
- 本批仅测试/报告变化；无候选、无构建号、无替换。
- 停等独立复验。
