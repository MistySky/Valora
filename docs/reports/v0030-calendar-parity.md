# V0030 同轮补充 — 日历 Calmon 节日/休班/去重恢复

任务：`docs/pi-tasks/v0030-supplement-calendar-calmon-parity.md`
SHA256：`f9e401781c58444b384b66ead1e83cfb460095a5a0fccf472625ba9e883db60b`

状态：**限定修复与 fixture/native 证据已交付；等待 Codex 独立验收。**
未重做 V0030 主体/下载引擎，未进入 V0031，未读取真实个人日历。

## 1. 恢复内容

### 1.1 启用 Calmon 节日/休班链路

- `CalmonCalendarModel.showChineseHolidays` 恢复为 `true`。
- `HolidayProvider` 不再是空壳：
  - 恢复公开日历元数据源发现，只选择只读且标题符合中国节假日来源的日历；
  - 只加载当前可见网格 + 选中日所在范围；
  - 保留“正常节日行”和“（休）/（班）安排行”的不同语义；
  - 恢复 `systemFestivals`、`detailFestivals`、`marker`；
  - 恢复日格 `festivalShort`、`secondLine`、`badge`、`showsDot`；
  - 恢复详情 `休息/补班` 标签及来源标题。
- 没有硬编码 2026 国庆/重阳，也不从周末猜休班。所有节日与休班标记只来自选中的系统节假日源；源不存在或未授权时保持基础公历/农历，不伪造。

### 1.2 来源筛选与去重

- `HolidayProvider` 只读取选中的节假日源，不把所有订阅来源混入节日详情。
- `CalendarEvent` 增加只读 `calendarIdentifier/calendarTitle` 元数据；`EventKitCalendarEventProvider` 映射事件来源。
- `CalmonCalendarModel` 从个人日程结果中排除选中的节假日源；同一个 `eventIdentifier` 只保留一次。
- 不在个人日程中按标题去重：两个同名个人事件保留两条。
- 节日详情用 title+marker 做精确去重：
  - 同名普通节日只出现一次；
  - 同名休/班安排只出现一次；
  - normal + arrangement 可同时出现；
  - 不把同名个人事件当作节日删除。

### 1.3 授权/生命周期

- 仍使用既有 Valora 单一 `enableCalendar` + full access 门控。
- `HolidayProvider` 不请求权限、不做系统写。
- 关闭门控时：
  - 停止/丢弃节日源显示；
  - 清空缓存的节日 badge/festival；
  - 清空个人日程，不再发起读取；
  - 旧请求由 generation/selected source 检查丢弃。
- 面板关闭、停止、跨月、撤权、旧回调、并发读取仍沿用既有 CalmonCalendarModel/EventKit 边界。
- 日历无节假日源时保持原基础月份、农历和节气。

## 2. 定向验证

按最新分工只跑相关定向测试，没有重复全量。

- **48/48 定向通过**
  - `CalendarHolidayParityTests` 7/7
  - `CalmonCalendarTests` 5/5
  - `IndependentCalendarLifecycleTests` 7/7
  - `FeatureSwitchTests` 5/5
  - `DownloadEngineIsolationTests` 7/7
  - `DownloadMenuModelTests` 6/6
  - `SettingsReductionTests` 9/9
- 新增日历 fixture 推导：
  - 10/1 国庆节 + 休
  - 10/10 补班
  - 10/18 重阳节
  - normal + arrangement 各一次
  - 同名精确重复只保留一次
  - 同名个人事件保留两条
  - 门控 off 清除节日 badge 并停止读取
- 原生 parity（授权 fixture，非真实个人日历）：
  - `calendar-2026-10-01-national-day.png`：国庆节、休角标、点、详情 `国庆节` + `国庆节（休）` + 休息标签
  - `calendar-2026-10-10-makeup-workday.png`：班角标、点、详情 `国庆节（班）` + 补班标签
  - `calendar-2026-10-18-double-ninth.png`：重阳节、点、详情重阳
  - `verification.json` 明确 `fixtureOnly=true`、`productionEventKitRead=false`、`realUserCalendar=false`
- 设置页 40 个实际页面截图仍通过；功能开关/图标补齐成果保留。
- 菜单栏模块回归 11 checks / 13 rendered。
- 未重跑全量、未重跑下载 popover 内存审计；本次日历修复不改变下载 popover。

## 3. 候选

- 目录：`/private/tmp/valora-calendar-parity-candidate`
- binary SHA256：`c421f6a63e35fc7e5c477fd51cae965db0d3148b7960d38c396266c2e272f8a0`
- `codesign --verify --deep --strict` 通过
- 日历 entitlement 保留
- 无 Sparkle 链接
- 用户 `dist` 未覆盖，仍为：
  `19ba9a0f0cae669dcc32eb8f282750f9fd46a71a603d1bb2d01b9f872b0ffd9f`

## 4. 来源/许可

- Calmon 固定 `72235116e1420fa081e8f694991a32809f81498d`。
- `source/calmon/` 保存参考 `HolidayProvider/CalendarModel/CalendarView/CalendarComponents`；
  `source/local/` 保存 Valora 适配文件；`source/source-manifest.json` 保存 SHA256。
- 该 commit **没有 LICENSE 文件**（事实记录，不发明 MIT/GPL）；来源注释和既有
  V0027 source provenance 保留。
- 未修改参考 checkout、归档或 Git 状态。

## 5. 未验证/边界

- 未读取真实 EventKit/个人日历，未请求或修改系统权限；只使用 fixture。
- 真实系统节假日源是否存在、来源匹配与真实事件标题格式尚未验证；不存在时保持空/基础日历。
- 未用真实鼠标/物理多屏/真实授权验收；native 视图是候选 app 内的实际 Calmon view，但 fixture 数据。
- 未验证真实个人同名日程的 EventKit 返回顺序/来源 ID 组合，仅通过注入 fixture 验证过滤/去重规则。
- 未安装、发布、Git 提交/推送，未改模型历史、归档、用户 dist 或当前运行应用。

报告证据：`docs/verification/v0030-calendar-parity/`
