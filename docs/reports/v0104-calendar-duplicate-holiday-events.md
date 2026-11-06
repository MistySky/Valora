# V0104：日历节假日重复（蓝色重复行）

执行：现有会话，分支 `codex/final-cleanup`。用户 build 13 实机：锁屏/解锁、音乐开关恢复、歌词、封面翻转、双击均正常；共享日历面板在 10 月 1 日绿色“国庆节”“国庆节（休）”下方又出现蓝色同两名。本批只修节假日来源合并，保留个人日程与原 UI；未读真实用户日历、未改权限、未 Git 提交。

## 一、fixture 复现的真实缺口

`CalmonCalendarModel` 原先只排除**一个**来源：

```swift
let holidayID = provider.selectedCalendarID
events = loaded.filter { event in
    if let id = event.calendarIdentifier, let holidayID, id == holidayID { return false }
    …
}
```

`HolidayProvider.refreshSource()` 实际已经算出全部匹配的只读中国节假日来源（`matched`），但只保留了 `chosen` 一个；其余来源的同日事件因此仍留在蓝色列表。

> **V0105 口径更正**：上句曾写“用户机器上恰好有两个可信节假日来源”，但该结论**未经真实读取用户日历/来源验证**。真实可复现的因果是：只要存在多个匹配来源（fixture 已复现），未选中的来源事件就会留在蓝色列表；用户机器上的实际来源数量没有读取、也不作为结论。原失败日志与证据保留不改。

用 fixture 把旧规则临时放回 `applyCalendarFilter` 等价的单 ID 过滤后，两条来源的事件都留在蓝色列表：

```
实际: ["a-normal", "b-normal", "personal-all-day", "personal-timed"]
期望: ["personal-all-day", "personal-timed"]
```

这不是按颜色/名称的视觉问题；根因是“可信来源 ID 集合”被压成了单个 ID。

## 二、最小修复

`Sources/Valora/CalmonHolidayProvider.swift`

- 新增 `holidaySourceIDs: Set<String>`：由 `refreshSource()` 中全部 `matched`（只读 + 标题/来源含中国 + 节假日）填充，不再只取第一个；无匹配时清空。
- `refreshSource()` 在来源元数据发布后调用 `onHolidayDataChanged`，让已显示事件可重新应用规则（元数据晚到/来源变化）。
- `applyFixture(records:range:title:sourceIDs:)` 支持注入可信来源集合（默认 `["fixture-holiday"]`，既有测试不变）。
- `finishFetch` 在排空 `pendingRange` 前检查刚完成的范围是否已覆盖它，避免“回调触发 rebuild 再排队同一范围”造成重复日历读。

`Sources/Valora/CalmonCalendarModel.swift`

- 新增 `loadedEvents`（当前日原始事件）与 `applyEventFilter()`：只排除 `calendarIdentifier ∈ provider.holidaySourceIDs`；按 `event.id` 去重；**不以标题、颜色或“节”字判断**。
- 读完成：`loadedEvents = loaded` → `applyEventFilter()`。
- `rebuild()` 也调用 `applyEventFilter()`，因此 `onHolidayDataChanged`（晚到元数据、来源变化、fixture 更新）会重新过滤已加载事件，**不发起新的日历读**（测试断言 `readCount == 1`）。
- `stop()`、`setPanelVisibility(false)`、gate 关闭/拒绝、迟到结果丢弃时同时清空 `loadedEvents` 和 `events`，不留下可被重新过滤还原的旧数据。

边界（如实记录）：**没有可信来源证据就保留**。`calendarIdentifier == nil` 或不在可信集合内的事件（哪怕标题同为“国庆节”、同一天、全天）都保留；不按日历标题含“节”泛化过滤；个人日程即使同名同时间也保留。

## 三、定向回归（全部 fake / 隔离日期 2026-10-01，无真实日历读取）

新增 `Tests/ValoraTests/IndependentCalendarHolidayDedupTests.swift` 6 项：

| 用例 | 结果 |
|---|---|
| 两个可信来源：绿色“国庆节/国庆节（休）/休标记”各一次；蓝色只剩个人两条 | 通过 |
| 单来源：绿色各一条，蓝色不重复 | 通过 |
| 元数据晚到：先 4 条（无可信来源），后注入两个来源 → 只剩个人，且事件读次数仍为 1 | 通过 |
| 缺 `calendarIdentifier` 的未知事件保留（不误删） | 通过 |
| 隐藏 / 撤销 gate / stop 清空，重新显示后过滤仍正确 | 通过 |
| 隐藏后迟到的日历结果不回写 | 通过 |

失败复现证据：把模型临时改回“只用 `selectedCalendarID`”后，第 1 项失败并打印 `["a-normal","b-normal",…]`；恢复后文件 SHA-256 与修复版一致（`e730478d…2fc4`）。

相关既有回归（未跑全量）：

| 套件 | 数量 | 结果 |
|---|---|---|
| `CalendarHolidayParityTests` | 11 | 通过 |
| `IndependentCalendarLifecycleTests`（跳过真实状态项方法） | 8 | 通过 |
| `CalmonCalendarTests` | 5 | 通过 |
| `CalendarMonitorSharedTests` | 4 | 通过 |
| `IndependentCalendarPermissionTests` | 2 | 通过 |
| `IndependentHolidayDispatchTests` | 1 | 通过 |
| 合计（含新增 6） | **37** | 0 失败 |

未跑全量/闪窗/压力/性能，未真实媒体/设备/锁解/权限写入，未读个人日历。

## 四、候选与替换

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0104-calendar-holiday-dedup-candidate/Valora.app` |
| 版本 / 构建号 | `0.2.0` / **14**（Info.plist 与 `build-verification.json` 一致） |
| binary SHA-256 | `cbc2d66fe17c53a55b1073f3f710b60748f7afc427cbdebb477074d438e0dc97` |
| 签名 | `codesign --verify --strict --deep` 通过 |
| 当前运行 | **仅 1 个** `Valora` 进程，PID 63480，路径为新候选；dist 未被覆盖 |

替换过程中的事实（不隐去）：

1. 先按应用名 `tell application "Valora" to quit` 时，LaunchServices 解析到已注册的 `dist/Valora.app` 并把它启动（09:10:13），build 13 被退出；
2. 结果短暂出现 dist 与新候选两个实例；
3. 改用 `tell application id "com.wangqing.valora" to quit` 逐个正常退出，确认 **0** 个进程后重新启动候选一次，最终仅 1 个（PID 63480）。

没有 pkill/强退，没有覆盖运行包或 `dist`，没有安装发布或 Git 提交。

## 五、未做与边界

- 未用真实用户日历/真实节假日源验证；修复依据是公开元数据的来源集合，不读取用户日历内容。
- 未改日历面板宽度/字体/布局、未加设置、未动个人日程显示与基本日历。
- 真实机器上“多个节假日来源”的具体来源名称未读取（不查用户数据），但规则只看“可信只读节假日来源 ID 集合”，与来源数量无关。

## 六、复验

用户只需重看 10 月 1 日同一面板：绿色仍各一条，蓝色不再出现这两条；个人日程（含同日/同名）应仍在。已通过的锁屏/音乐组不需要重做。
