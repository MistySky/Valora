# V0113 日历状态栏入口消失（最小修复）

## 根因证据

Codex 独立真机/临时诊断已确认：

- 用户偏好：`showApplicationMenuBarIcon=false`、`enableCalendar=true`、`enableSystemMonitor=true`；
- 系统状态栏布局键 `NSStatusItem VisibleCC Item-0=false`；
- V 图标创建时没有独立 `autosaveName`，隐藏后 `isVisible=false`；后续启动 V 关闭时不创建；
- 日历成为首个 status item，创建时继承了通用 `Item-0` 的 hidden 状态；
- 后赋 `autosaveName` 不会自动重置实际 `isVisible`；
- 现有测试只检查模块对象非 nil，没检查真实 `isVisible`。

这解释了“日历入口整个消失”，不是设置导航或日历渲染消失。

## 实际改动

### 1. 应用 V 图标

`AppDelegate.installApplicationStatusItemIfNeeded()`：

- 新建 item 设置稳定 `autosaveName = "Valora.Application"`；
- 创建和已存在恢复分支都显式 `isVisible = true`；
- V 关闭仍只隐藏 V 自己，不影响日历/监控。

### 2. 日历 / 系统监控

`MenuBarModuleController`：

- `makeStatusItem(autosaveName:)` 统一设置稳定名称后显式 `isVisible=true`；
- 新增 `ensureStatusItemVisible(_:autosaveName:)`，已有 item 再次启用时也修复可见性，而不是只判断非 nil；
- 日历继续 `Valora.Calendar`，监控继续 `Valora.SystemMonitor`；
- 关闭仍按原有移除/停止逻辑，不改采样、定时器、面板、日期文字、排列、权限或设置。

没有删除用户 defaults、清空状态栏布局、常驻隐藏 V、增加 Timer，也没有改动画/歌词/锁屏。

## 测试

新增/加强：

- `MenuBarModuleControllerTests.testHiddenInheritedStatusItemIsRepairedWithStableAutosaveName`
- `MenuBarModuleControllerTests.testReenablingCalendarRepairsAnExistingHiddenItem`
- `MenuBarModuleControllerTests.testVApplicationItemUsesStableAutosaveNameAndIsVisible`
- 原有独立 status item 测试增加实际 `isVisible == true` 和 autosaveName 断言。

定向结果：

- `FeatureSwitchTests` 4 项通过；
- `MenuBarModuleControllerTests` 8 项通过；
- `IndependentMenuBarMigrationTests` 4 项通过；
- 合计 16 项，0 失败。

测试只使用 QA/临时 status item 与项目默认域隔离；未读取或修改真实用户偏好，未启动新包。

## 未验项

- 未构建/安装/替换真实 Valora，未实际重启验证用户当前安装是否恢复；
- 未在真实 `NSStatusBar` 系统布局（真实用户 Item-0 状态）中执行新包；
- 没有验证用户原有菜单栏位置/顺序在真实重启后的最终排列；
- 没有删除或迁移用户当前 defaults；Codex 构建验收时需确认真实启动后的日历可见性；
- 未提交 Git、未改版本。

## 交付

源码与定向测试已完成，未正式构建、未替换、未提交；等待 Codex 独立验收后构建候选。
