# V0029-R1：用户已同意本地最小兼容补丁，完成隔离引擎接入

用户已明确回答“采用本地兼容补丁（推荐）”。此项覆盖V0029“不应用补丁/等待方案选择”的限制。只允许目录/配置/所属manager注入及必要生命周期最小适配，不改下载算法、既有Convoy操作/UI、不创建或推送GitHub fork、不Git提交推送、不偷改.build/checkouts。前批编译/纯映射范围已独立接受，见docs/verification/independent-v0029/decision.md；接着做真实安全隔离，不再重复问同一方案。

## 本地依赖可维护交付
- 固定上游007a20973923fcd69c42a3571fc299f5b8582dc6，建立显式项目内可审查的本地兼容包（例如Vendor/Convoy），Valora仍通过SwiftPM引用DownloadEngine产品，禁止把引擎业务散进Valora。只纳入必要引擎源/正确LICENSE/NOTICE；本地Package清楚标注与原manifest差异（不引入主App/Sparkle/浏览器host运行或UI）。不要夹带嵌套.git/用户数据/构建产物。上游原始固定源码/内容哈希和本地修改patch/manifest分别保存，可重建、可比对。
- 记录UPSTREAM revision、每个修改源路径/原因/边界、可复核patch和升级校验脚本：干净基线验证→应用小补丁→编译/接口与隔离回归；版本不匹配明确失败，禁止静默全量替换/模糊应用。仍保留未来引擎/插件/NativeMessagingHost/IPC同源版本清单，不承诺纯SPM升级自动覆盖补丁和扩展。

## 必须真正隔离的范围
1 提供明确DownloadEnvironment/configuration和manager工厂/可注入初始化，Valora实例显式配置自己的Application Support/Valora/...任务文件/锁、Caches/Valora或下载专用scratch、独立named UserDefaults suite；QA全部指向唯一临时根+唯一suite。不能通过全局HOME、UserDefaults.standard重定向或任意进程沙箱假装生产隔离；不要把UserDefaults塞Sendable struct后unchecked全局放行，可用隔离配置或suite标识等真实所有权。
2 Manager持久化/锁/损坏列表备份/保存/恢复/启动临时测量全走环境。初始化副作用明确、有界、只在自己的根，临时测量延迟或显式开启，应用普通启动不实例化manager或自动恢复下载。兼容.shared可保留仅上游默认用法，但Valora绝不走原Convoy.shared。
3 Settings注入自己的defaults，默认下载目录仍系统Downloads（QA必须覆盖到临时目录）；restoreDefaults不碰standard/其他App偏好。DownloadTask/DownloadSegment/TaskScratchDirectory/TemporaryStorage/report/remove/合并/取消/失败/恢复/清理都传播同一环境，避免测自己的列表却扫原Convoy残留。
4 任务回调所属manager尤其不能遗漏：上游DownloadTask.swift约1488/1509/1788/1995的DownloadManager.shared（迟到文件名冲突/去重/丢弃待处理冲突）必须改为所属实例/回调，不再逃回全局Convoy单例。manager与task之间不形成永久retain cycle。任务内AppSettings.shared/YouTube helper等路径需明确环境归属；本批HTTP(S)验证不要触发Cookie读取、helper更新/安装、真实浏览器或外部工具。其他未验证路径如实列边界，不能悄悄用默认共享路径fallback。
5 原成熟下载算法/分段、状态、暂停继续、重试、重名确认、删除确认语义不改；DownloadService薄适配实现真实状态流及动作，snapshot尽量保留未来分段所需layout/filled/active与速度/剩余时间/完成文件等字段，不把引擎对象泄露进音乐日历监控或未来View。必要新增只为已确认功能；不全局架构重构或提前修改UI。

## 真实引擎隔离验证（限开发自产临时数据）
- 本地Range HTTP服务+临时小文件，验证多分段SegmentMap确实变化、完成字节hash一致、暂停/继续无重复写/进度一致、取消/失败不残留活跃任务、停止并重建实例恢复进度/记录、重名不覆盖并走原冲突处理、完成只移记录vs明确移Trash动作区别。Trash用可注入测试替身/自产隔离文件，不动真实用户Trash或文件。
- A/B两个不同环境与sentinel文件/suite证明互不读写，临时测量/清理不能扫另一环境；并发锁/不可读记录备份只在自己根，未合作异步迟到结果不复活旧任务。禁止查看/散列用户真实Convoy目录或Downloads内容来证明隔离，使用测试根模拟上游/其他应用记录即可。
- 全面静态rg所有shared/default路径/自动installer/browse/cookie调用，给出Valora可达路径与测试证据；测试没覆盖的不可写“全隔离完成”。检查设置订阅/Task/Timer/缓存随生命周期释放，避免重演面板开窗内存叠加。
- 不实际下载外部资源/安装helper，不请求新权限、不真实媒体/设备/账户/个人日程操作。真实引擎QA与FakeDownloadService严格区分，真实Range验证不能用fake代替。

## 交付
Swift6/macOS27保持；最小隔离/真实下载及必要已接受Codex/日历监控回归、release构建签名、包内来源许可检查。候选仅/private/tmp/valora-v0029-r1-candidate，禁止覆盖dist/退出当前软件、不Git/改归档/模型历史/自行修改定时器。报告docs/reports/v0029-r1.md，证据docs/verification/v0029-r1，含上游与patch/hash/升级校验说明/真实测试与未完成项。完成停等Codex独立验收，再派V0030菜单栏下载列表，之后V0031浏览器接入。
