# V0113 日历状态栏入口消失：已定位最小修复

当前唯一任务，原Pi会话与模型。用户反馈brew新装1.0.5 build64后顶部日期入口整个消失。用户本地用brew管理，禁止本次启动/退出/替换任何真实实例，禁止改真实偏好。仅源码修复、定向测试与报告，不构建、不改版本、不提交推送发布，交Codex验收。

## Codex已独立确认
- AppDelegate及MenuBarModuleController日历逻辑相较main未变化，并非本次删日历代码。setupMenu始终setCalendarVisible(true)。
- 真机偏好 com.wangqing.valora：showApplicationMenuBarIcon=false；enableCalendar=true；enableSystemMonitor=true；`NSStatusItem VisibleCC Item-0`=false。
- V图标installApplicationStatusItemIfNeeded创建时没有autosaveName，隐藏时isVisible=false，后续启动V关闭则不创建，日历成为首个item。
- 独立编译并运行临时应用（Bundle ID com.wangqing.valora.diagnostic.calendar-visibility-20261112），仅其独立defaults先seed相同系统键false，创建item后打印：before-name Item-0 false；随后item.autosaveName="Valora.Calendar"，after-name Valora.Calendar false。
  这证明状态栏项目创建时可继承通用Item-0隐藏状态，后赋autosaveName不会重置实际isVisible。未改Valora用户设置。probe源/tmp/valora-calendar-visibility-probe-20261112.swift。
- 当前测试只assertNotNil模块对象，没有验证isVisible，漏掉重启恢复。

## Codex决定的最小方案
1. App V图标创建后设置稳定独立autosaveName（如Valora.Application），按产品显示请求显式isVisible=true；已存在的恢复分支保留true。V关闭时仍隐藏它自己，不影响日历/监控。
2. Calendar/SystemMonitor创建完成并设置各自autosaveName后，按该模块当前启用意图明确isVisible=true；模块再次setVisible(true)时也确保已有item实际可见（不能只判断非nil）。关闭仍按现有移除/停止逻辑，不改采样、定时器、面板样式、日期文字、排列布局或权限。
3. 不删除用户defaults，不清所有状态栏布局，不通过始终创建隐藏V来占序号，不新增Timer，不改变动画/歌词/锁屏。
4. 小而有效回归：实际NSStatusItem对象预置isVisible=false后，执行对应生产恢复分支必须变true；V关闭后日历/监控仍可见；V具备稳定独立autosaveName。用项目QA隔离默认域（验证不得读写真实用户prefs）。如需生产helper或测试入口，保持最小。不要用纯assertNotNil冒充可见性。
5. 跑FeatureSwitchTests、MenuBarModuleControllerTests及必要新增用例，有限定向，不全量/不压力/不操作真实媒体。

写docs/reports/v0113-calendar-status-visibility.md，注明根因证据、实际改动、测试数、未真实启动新包；不要声称用户当前安装已修复。
