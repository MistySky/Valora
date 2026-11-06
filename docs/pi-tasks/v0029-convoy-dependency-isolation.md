# V0029：Convoy DownloadEngine依赖接入与隔离验证

前置V0028-R1独立接受后投递，接续用户确认顺序，不改下载UI（后批V0030）、不接真实浏览器（V0031）、不全局重构/拆包。用户要求直接SPM复用引擎，未来引擎/插件/host同源版本管理；不是把整个Convoy App迁入或后台启动。

## 已核事实/先处理实际接入边界
来源 https://github.com/TheDynamicPunk/Convoy ，Codex只读核main固定revision 007a20973923fcd69c42a3571fc299f5b8582dc6。Package.swift公开DownloadEngine library，其target直接依赖swift-log（整个包还声明Sparkle，区分依赖解析与实际链接）。不要笼统保证零适配即可完整使用。
重要：该revision DownloadManager是public final单例shared，private init立即loadPersistedTasks并测临时目录；persistenceURL硬编码Application Support/Convoy/downloads.json，存在锁/写入/损坏列表移走/临时文件清理路径。AppSettings.shared也有默认值写入。只读确认在DownloadManager.swift约78/1397行。未经证实隔离之前绝不可实例化.shared或用真实HOME/用户Convoy目录跑引擎；不能以初始化无害假设覆盖用户已有记录。

## 工作范围
1 固定上述revision作为SPM依赖，仅链接DownloadEngine产品，Package.resolved可复现。允许依赖解析及编译产物缓存，不安装/启动Convoy应用，不引入Convoy自更新/主窗口/浏览器host。保留引擎实际许可证与应有第三方声明，记录版本/来源/实际链接资源，不能剥许可或编造所有组件都相同许可。
2 静态逐项核公开API：DownloadManager/DownloadTask/SegmentMap/Settings/temporary paths/persistence与删除；列任务添加/暂停继续/进度/分段/取消/完成文件/持久化/重名/恢复所需接口、可访问性和所有自动副作用。依赖Swift5.9包在Valora Swift6/macOS27下实编译，不因引入依赖降低Valora语言/平台或关闭全局并发检查。
3 建立最小自有DownloadService边界与可注入引擎接口/不可变状态快照（只确实需要的，不铺大架构），产品UI未来只依赖该接口，具体import DownloadEngine留适配处；不得把引擎类型撒到音乐日历监控。可以先完成纯映射/编译适配和fake，不启动实际单例；不得在AppDelegate启动时初始化下载服务或写用户目录。设置下载当前UI占位不动。
4 查明生产Valora独立AppSupport/缓存/任务文件/用户Defaults与QA临时根是否能经公开API完全配置。若上游支持，走其公开配置；若不支持，只写可复核的最小隔离补丁/接入备选方案（不实际发布/fork推送、不偷改.build/checkouts、不大段复制整个引擎），说明哪些阻断完整运行与后续升级。仍完成依赖编译/纯映射/模拟接口验证，报告给Codex决定；不要用改全局HOME/UserDefaults或sandbox外进程绕路径来冒充可维护的生产隔离。未经安全隔离不跑真实DownloadManager，不制造“完整下载已接入”结论。
5 只有证据确认可注入隔离根时，才在临时目录自建Range HTTP fixture实测小文件：分段真实进度/字节校验、暂停继续/取消与临时清理、任务恢复与重名不覆盖、完成只移记录与显式Trash语义。禁止访问/修改个人Downloads或已有Convoy数据、浏览器cookie/配置、外网大文件。未知条件不足列待验，不凭fake冒充真实引擎通过。测试文件和服务器须自产、自清理，无管理员/新系统权限。
6 记录引擎revision与将来Extensions/Chromium、Firefox、NativeMessagingHost/IPC同源对应清单；只读核协议，不安装扩展/写真实host注册，不接真实浏览器，不替换Valora当前运行包。下载UI以后沿Convoy行/分段，顶部无+、图标右键新建下载、无分类、默认Downloads（QA必须隔离）与原删除确认语义见CONTINUATION-PLAN，不借本批改UI。

## 验收与交付
针对性纯映射/适配/隔离路径/禁止隐式启动回归，SPM resolve+release构建签名/必要已接受Codex与日历监控回归，区分真正引擎与fake结果。候选/private/tmp/valora-v0029-candidate；不覆盖dist/退出用户软件，不真实媒体/设备/TCC/登录项/个人日程账号操作，不Git提交推送或改归档/模型历史/定时器。报告docs/reports/v0029.md，证据docs/verification/v0029，给出版本/许可/API/副作用隔离清单、已实现/未实现与必要具体选择。停止等Codex独立验收，不自动推进下载UI或浏览器。
