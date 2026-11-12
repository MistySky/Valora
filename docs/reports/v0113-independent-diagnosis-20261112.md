# V0113 日历入口隐藏独立定位

用户反馈：brew安装1.0.5/build64，顶部日期入口整个消失。保持本地安装与PID21278实例，不修改真实偏好、不重启。

源码核对：MenuBarModuleController.swift / CalmonMenuBarStyle.swift从main 6c98d2b到c1009dc没有差异；setupMenu仍调用setCalendarVisible(true)，不存在本轮删除日历显示逻辑。App V图标创建时没有固定autosaveName，隐藏仅isVisible=false；V开关关闭后下次启动不创建V图标，Calendar成为首个状态栏项目。日历创建后只设置专属名称，没有显式恢复可见性。

当前用户偏好（只读）：showApplicationMenuBarIcon=false；enableCalendar=true；enableSystemMonitor=true；NSStatusItem VisibleCC Item-0=false。

独立隔离复现：编译临时Probe.app，独立Bundle ID com.wangqing.valora.diagnostic.calendar-visibility-20261112，只在自身defaults临时设置同名系统键false，创建一个NSStatusItem，设置autosaveName前后输出：

```
before-name Item-0 false
after-name Valora.Calendar false
```

之后移除临时item，并恢复探针自己写过的偏好；未修改com.wangqing.valora偏好。证明通用首项隐藏记录可被新建日历继承，赋专属名称本身不会恢复实际isVisible。结合生产创建顺序与当前用户配置，构成该消失路径的具体证据。

探针源码：/private/tmp/valora-calendar-visibility-probe-20261112.swift

修复要求：V/Calendar/SystemMonitor分别稳定命名；按各自功能可见性意图显式恢复isVisible，不能只检查对象非nil；不删除用户defaults或重置菜单栏布局。动画与歌词不在范围。

真实安装尚未应用新修复；本报告不声称用户当前入口已恢复。

## 源码验收结果

Pi完成最小修复：V有独立Valora.Application名称；Calendar/SystemMonitor创建或再次启用时按模块意图显式恢复isVisible。Codex补充FeatureSwitchTests检查V开关关闭启动与运行时关闭后，日历/监控的实际isVisible，而不是只判断非nil。FeatureSwitchTests、MenuBarModuleControllerTests、IndependentMenuBarMigrationTests共16项通过，0失败。日志：/private/tmp/valora-v0113-independent-tests.log。git diff --check通过。

本次源码可接受，尚未提交或构建新版本；已公开1.0.5不包含此修复。本地Brew安装和当前运行实例未替换、未重启。
