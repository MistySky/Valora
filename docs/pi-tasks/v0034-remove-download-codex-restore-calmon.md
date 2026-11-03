# V0034：删除下载/Codex，恢复Calmon独立菜单栏与简洁设置

用户最终明确：“整个下载和codex功能都删除，菜单栏展示按照现有calmon那样，设置还是保持简洁”，随后明确“交给pi吧”。这覆盖上一轮不交pi/继续组合环与统一大面板/Codex刘海通知的讨论。当前工作树含Codex直接修复与用户预览成果，先保留其有效部分，不git reset或还原全部；从当前文件串行执行，不开新会话。回退提交de7a225已远程，当前不再Git提交/推送。

## 产品范围
1 完整移除下载功能（不是只隐藏/off）：菜单栏入口、设置页面/开关、任务模型/引擎适配/下载UI、NativeHost/ChromeBridgeKit/桥接服务、扩展资源和安装引导、本地Convoy SwiftPM依赖及其专用源码补丁/脚本。生产不初始化下载manager、不轮询/监听桥接socket、不加载插件或后台helper。移除Package.swift产品target依赖、无用Package.resolved与打包/build脚本相关复制/manifest/参数，最终.app不带NativeHost/ChromeExtension/Convoy专有资源。
2 完整移除Codex/AI用量：采集/子进程/transport/模型/缓存/刷新/LiveProbe/菜单栏指标/设置页面与开关/UI。不改成刘海通知、不留“准备中”。不读真实账号、auth/token、会话或额度。
3 移除本轮组合环和一体主/侧面板的生产及专用代码：CompositeMenuBarController/CompositeStatusIcon/CompositeMenuPanelView/MonitorCodexCombinedView和无用接线。Status Trio不再运行引用；其专用许可资源在实际相关代码全删后同步从包资源移除，保留历史报告/任务中来源记录。不能删仍有用途的其他依赖声明。
4 恢复现有Calmon日历和系统监控两个独立菜单栏入口/点击各自原生popover：监控CPU/MEM双行文字，日期沿现有Calmon“10月27日 周二”格式、系统template黑白。直接复用当前保留的MenuBarModuleController/MonitoringView/CalmonCalendarView以及只读/private/tmp/calmon-v0027固定72235116...成熟实现，不另设计新图标/仪表/大面板。删除controller内codex混合逻辑和旧兼容别名，保留有效的开关重建/观察epoch/取消/睡眠唤醒/面板开后读日程等边界。日期和监控宽度维持用户确认400pt（这是用户覆盖原版360的决定），日期网格368、原节假日/休班/农历/去重/事项和授权流程原样保留。勿因恢复旧Calmon引回已修复的生命周期缺陷。
5 日历和监控功能总开关沿现有语义：off移除所属status item/关闭popup并停止所属后台，初始off不偷偷采集/读日程，on重连有效观察且不重复入口；两模块独立。软件Outline-v7入口及其显隐开关/音乐菜单、刘海/音乐歌词/设备/锁屏均不改。监控原有网络/内存等现有成熟面板内容保持，不新加功能。日历基本月历与EventKit日程授权保持原有正确区分（不要错用未授权作为不能看月历理由）。
6 设置移除AI用量/下载整个页和相应多余文案/图标/分组项，最终通用；刘海屏[音乐,锁定屏幕,设备连接]；菜单栏[日历,系统监控]；Valora下关于。原Alcove控件样式/标题13pt间隔/简洁授权开关保持，不加新说明大段/新设置/新占坑。关于不留虚假“功能准备中”替代已完成功能说明；只做必要简洁事实信息，不新增产品介绍模块。

## 删除边界
- 只删被移除功能的源码/专属测试fixtures/专属原型和打包资源/依赖；可删除已失去被测功能的专属测试并列清单，混合文件保留日历/监控/音乐/权限断言并更新新产品结构，不能直接删整个混合回归文件逃避编译。
- 历史docs/pi-tasks、reports、verification证据/原用户应用图标文件/基线和非下载依赖不删，不全局架构拆包。
- 不接触用户既有下载文件/任务记录缓存/UserDefaults（旧key可留惰性不用，不为清理写真实偏好）、Downloads/Trash、真实Chrome配置/NativeMessagingHosts/插件安装或权限；如果用户先前安装桥接需卸载，只在交付中列具体残留与用户操作，不擅自删其真实注册。不读Chrome个人目录。不得把移除App内功能称真实Chrome扩展已卸载。
- 不覆盖当前运行包和dist，不退出重启用户App。不得动只读归档或pi模型历史，不安装/发布/Git。

## 验证和交付
- 禁止任何--verify-*、自动菜单栏打开关闭/批量截图/循环压力/内存CPU帧率测试；不跑已禁止QA，也不改名绕过。只静态源码/依赖引用和受影响无弹窗功能测试；恢复后的日历/监控off-on、原失败边界/菜单路由、设置分组/授权、日期渲染尺寸足够，不机械全量。Codex负责独立集成验收。不得运行真实媒体/额度/日程查询/设备/系统权限写/浏览器下载。
- 一次必要release构建+打包签名；验证产物无下载/Codex/Chrome专用payload及活跃依赖（保留媒体adapter/设备/日历SolarTerms），日历entitlement与音乐资源完整。
- 候选/private/tmp/valora-v0034-calmon-clean-candidate，报告docs/reports/v0034.md。报告列删除文件/依赖/设置/运行路径清单、保留项、静态引用与定向测试结果、真实Chrome遗留操作边界与尚待用户查看的视觉。
- 完成后停等Codex独立验收，不自动后续任务、不恢复定时器、不启动候选。
