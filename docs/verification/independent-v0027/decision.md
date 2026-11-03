# V0027 独立验收：整体暂不接受，限定R1

## 已独立通过的子集
- 现有263项：Valora149 + ReferenceCore114，0失败，existing-tests.log。
- 当前源码独立release构建/临时打包/签名通过。独立binary 4f6398b8e8734d04e2995c22a206da1275f8fcd05f319a23b9f954b1306c04c8。用户dist仍19ba9a0f0cae669dcc32eb8f282750f9fd46a71a603d1bb2d01b9f872b0ffd9f，未替换/退出/重启。
- Calmon固定72235116e1420fa081e8f694991a32809f81498d本地来源checkout干净；13份源/资源与source-manifest哈希均匹配，当前迁入文件哈希均匹配。MonitoringView仅增加QA标签，UIStyle只有Swift6 NSFont隔离适配，月历保留布局并接现有授权事件行。
- 独立原生verify-menu-modules：3独立状态项、2独立popover，日历360x541、监控400x482；模块基础菜单无音乐/显示器；均关闭成功。生产软件图标音乐菜单仅源码接线核查，验证器手工简化菜单不能证明实际该菜单交互已通过。
- CUA只读查看隔离候选实际日历/监控popover，七列、选日、农历、概览和应用列表可见；未点真实媒体/权限/个人事件，未验证真实鼠标左右键或系统重排。此次不称完整屏幕/物理多屏材质体验通过。

## 新增独立回归：3项中2项失败
Tests/ValoraTests/IndependentMenuBarMigrationTests.swift，日志boundaries.log。
1 隐藏再显示日历，新statusitem沿用lastCalendarText导致update跳过，accessibility日期为空（模型日期正常）。需新按钮立即重画，不等后续日期变化。监控同类立即重绘case本次通过。
2 生产AppDelegate.$calendar.sink同步调用refresh，但readGate读取Published旧willSet状态，已开面板授权denied→fullAccess后provider读次数0，应1。测试复现同一生产接线；返修时提取共享生产接线或真正注入入口测试，不能只改复制测试而生产仍旧。

## 内存专项独立复跑
运行pi正式候选ec5e18b...的隔离memory audit，454.6秒/144点；日历及监控各30轮开关，两阶段长开，假事件与假应用列表，真实公共CPU/MEM及本进程RSS/footprint。stop后controller/calendar/monitor/reader全部释放。原始memory-audit.json及memory-summary.json。
监控连续37/37样本isShown=true，预热30秒后footprint44.99→44.99MiB，拟合-0.013MiB/min；RSS89.88→89.89MiB，拟合-0.008MiB/min。本观察窗口未见持续阶梯增长，不是长期无泄漏保证。真实全量图标缓存未作长期实测。
日历长开阶段10/37样本可见；独立验收期间启动另一个原生QA进程打断焦点而关闭，故该段不能算日历完整3分钟长开通过，负斜率也不能用于此宣称。这是本次QA干扰限制，不据此认定产品自行关闭。pi原提交日历37/37可见记录已核，但不能以其报告代替本次独立实测。原60轮及对象释放证据仍有效。

## 决定
主体迁入/自动回归/构建签名及内存部分子集接受，整体暂不接受。仅派docs/pi-tasks/v0027-r1-status-recreation-calendar-grant.md修复两复现逻辑、完善实际接线测试与有效隔离验证，UI不动。物理双屏/真实日程授权等如实待验，不要求本轮执行真实权限动作。
