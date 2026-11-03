# V0036 独立验收：暂不接受，限定R1

## 已确认子集
- 来源清单13份归档、19份Valora源文件哈希均匹配当前文件。确实从复刻迁移了锁屏音乐/状态/材质/owned Space/声音链路，而非完全另起简版。
- 五条设置与固定Glass/600秒/偏移0/不迁入keepAwake电池专注天气日历的产品取舍基本吻合。菜单日历监控未被删除。
- 独立安全定向42项通过：Valora设备/媒体34 + ReferenceCore锁屏状态8；日志safe-targeted-tests.log。没有跑LockMusicCoordinatorTests或SettingsReductionTests，避免其真实面板路径。
- 候选二进制dcb88b3a9528002f1fd128982920afc096e7b4b0e4a5cdc17b28b4fe9c987721，锁解caf哈希与报告一致，codesign strict/deep独立通过。未启动候选/未锁屏/未放声音/未替换运行R3版。

## 代码缺陷与验证缺口

1. **stop/start没有重置音乐state/睡眠状态**。LockMusicCoordinator.stop(374–411)取消task却不调用已有state.hide或重建state，也不重置sleeping；AppDelegate385–388复用同一coordinator的setEnabled。若锁定且暂停时关闭再开启、曲目/锁状态输入相同，state.update短路而generation不变，不重建600秒deadline任务；若旧state已expire，可能保持隐藏。旧sleeping也会跨次保留。此为确定代码路径问题，尚未用真实窗口复现。
2. **旧通知Task跨启用周期**。observe198–205先移入Task MainActor，只在setLocked里检查started；stop移除token不能取消已排队Task，stop→start后started再次true，旧锁定/解锁/睡眠handler可污染新session并触发声音。Combine排队refresh同样应有生命周期校验，且睡眠handler先写sleeping无started检查。需要epoch和注入队列测试，不能仅注销观察者就称拒绝旧callback。
3. **耳机信息更新没有发布**。informationAirPods为普通private(set)属性，LockInformationView从coordinator读取它；model.$devices会排队refresh，refreshInformation301更新后不会发布objectWillChange，view之前因model刷新读取到旧值时没有后续可靠重绘通知。电量/型号更新及nil→有设备必须有明确可观察输出，不靠orderFront触发布局。
4. **锁屏持有启动时notchPanel**。AppDelegate385只传coordinator.panel一次，LockMusicCoordinator weak引用不再重绑定；WindowCoordinator后续activate/reconcile可以换主panel/重建。锁定时可能仍挂载旧屏或已关闭窗口，违背当前显示选择。需当前panel provider/变更接线与old detach/new attach，无界面替身验证，不真实多屏循环。
5. **所谓无界面coordinator测试会显示真实窗口**。LockMusicCoordinatorTests使用usePresentationSpace:false，但createPanels仍创建NSPanel/NSHostingView并注册真实系统观察者，setLocked(true)会执行present/orderFrontRegardless及信息panel置前。false只绕过Space，不隔离窗口。Codex没有执行这8项，不采信其全无界面声明。R1需真正fake窗口/Space/事件源与clock/scheduler，禁止再次运行这些原测试到真实桌面，不能改名绕过禁测。
6. **普通音乐总开关门控未订阅**：refresh计算nowPlayingEnabled，但bindModel未订阅它。若音乐全局off不造成其他媒体字段变动，锁屏音乐不会及时收起；需要对应独立回归。其他无关pref更改不应重置空闲deadline。

补充文档准确性：NotchView注释称-24度等为Original而报告承认复刻值，应修正来源表述；SettingsView旧placeholder注释也已过期。不要为了修注释更改动画。

## 边界
这些缺陷来自实际源码数据流审查；本轮未运行会开真实窗口的复现，不谎报新增失败测试。需pi用真正隔离的接线补修前失败/修后通过。真实登录窗口可见性、按钮命中、玻璃与锁解动画/声音仍待用户选择时机实测。总体不接受，当前运行版不动，限定返修后复核。
