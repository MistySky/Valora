# V0034 独立验收

结论：源码/功能回归/独立构建与签名范围接受。真实菜单栏视觉、鼠标点击及物理多屏未测，不冒称实机视觉通过。未替换或退出用户当前软件。

## 独立核对
- 生产Package只Valora/NativeBridge/ReferenceCore，无Convoy外部包、ChromeBridgeKit、NativeHost。下载/Codex/组合图标、设置页、UI/引擎/扩展专用资源已移除；历史证据保留。
- AppDelegate恢复MenuBarModuleController；两个独立status item及MonitoringView/CalmonCalendarView原生popover，CPU/MEM双行template/完整日期文字。右键仍基础菜单，软件Outline音乐菜单保留。
- 用户数据/Downloads/旧任务缓存/真实Chrome注册或扩展未读写，不宣称用户已卸载旧扩展。
- 54项定向回归通过（明确--skip testPanelsAreIndependentAndSwitchingClosesTheOther），含独立日历生命周期/授权/日期重建、监控开关、系统监控模型、设置减项与节假日。
- 另16项Calmon/QQ QRC/音乐偏好和标题格式回归通过，其中Calmon5项与前轮重复，是清理嵌入分支后的复核，不称70个独立case。
- 独立清理CalmonCalendarView唯一无调用的embedsScroll组合面板分支，恢复单一原滚动键盘路由；未改月历内容/样式/数据。SettingsView去末尾空白。
- 模型/歌词/WindowCoordinator/音乐内容/CalmonCalendarModel/HolidayProvider与已推送checkpoint相比无变更。
- 独立release、package、codesign --verify --deep --strict通过；包内MacOS只有Valora，无下载/Codex/Chrome/Convoy payload及相关链接；MediaRemote/AirPods/SolarTerms与日历权限资源保留。详见package-checks.json。
- 候选/private/tmp/valora-independent-v0034-candidate/Valora.app，binary SHA256 9f387005f531889cc16a9311d243d1d86b33f04530d2263a127be00197d6bdc7。
- dist原SHA19ba9a0f0cae669dcc32eb8f282750f9fd46a71a603d1bb2d01b9f872b0ffd9f未动。未Git提交推送/安装/真实播放/日程读取/系统设置操作。

## 测试证据边界
pi所报55项包含一个直接showCalendarPanel/showMonitorPanel的原生弹窗测试，不能归类为全无弹窗。本轮独立明确跳过；以后任何此类测试仍按用户禁测要求跳过或只提取纯逻辑断言，不重跑。未跑--verify-*、循环菜单开关/截图/资源压力。

下一步仅待用户单次看新候选；本轮不自动新增功能，定时器关闭。
