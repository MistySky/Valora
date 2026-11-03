# V0029 独立验收：依赖编译/纯适配接受，真实引擎运行等待隔离方案选择

独立36项相关测试通过（新增adapter3与既有Codex/菜单回归），release独立构建/临时打包签名通过。binary c11af4d74f0e0627c893837faff3ede4ee30506d5b160508c039fe1d05d91df3，与pi正式候选一致。otool无Sparkle链接。Package.resolved固定Convoy 007a209.../swift-log1.16.2/Sparkle2.10.1；checkout HEAD匹配且无diff。源码只有DownloadEngineAdapter import库，无真实manager初始化或启动接线。fixture DownloadTask public init只赋字段，无网络/文件/manager共享初始化。用户dist仍19ba9a0f...未覆盖/退出。

独立复核隔离阻断：DownloadManager.shared、private init，在构造时loadPersistedTasks/launch temporary测量；private persistenceURL硬编码Application Support/Convoy/downloads.json并mkdir，持有旁边锁。Settings.shared @AppStorage使用standard，无defaults注入；任务临时根系统temp，DownloadTask实际动作internal，无法绕manager完成正式接入。不能将SPM能编译等同于安全独立生产下载可运行。

pi给的proposed-isolation.patch是注释草案，不是已应用可编译补丁。需要给上游/自维护依赖增加persistence/defaults/scratch注入及延迟初始化（不重写下载算法/UI）。保持纯远程上游SPM时目前无可维护公开配置途径；不采用全局HOME改写、不改.build/checkouts、不读写既有Convoy记录。

决定：本批编译/纯映射/静态API审计接受，真实下载及Range端到端未实现不冒称通过。已向用户提出本地最小兼容补丁或暂缓下载的具体选择；未实际fork/推送/补丁应用。下载UI/浏览器按前置链等待，当前无可自动推进的已确认实现边界，删除heartbeat valora避免反复无效轮询，用户选择后沿原已授权15分钟串行验收接续（若选择暂缓则不恢复）。Codex用量已接受不重跑。
