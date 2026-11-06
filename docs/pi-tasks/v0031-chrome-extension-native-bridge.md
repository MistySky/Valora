# V0031 后续已确认范围：仅Chrome，Valora匹配扩展/桥接及设置引导

V0030-R5-R1已由Codex独立23项功能回归及签名接受，记录docs/verification/independent-v0030-r5-r1/decision.md；现在正式执行本任务，不并行修改已接受模块。用户明确“只做谷歌浏览器，安装的要和我这个匹配”，覆盖旧多浏览器/Firefox范围。参考固定Convoy007a209...的Extensions/Chromium、NativeMessagingHost和IPCKit，只做Google Chrome。

- 设置→下载保留功能总开关，加入Chrome扩展安装/连接区域：打开chrome://extensions、打开随包Valora扩展目录、开发者模式/加载已解压步骤、Valora本地桥接设置动作及实际诊断（未设置/已就绪/需要修复）。正常情况下用户完成Chrome显式启用；未运行Chrome不能假报坏。不要把Convoy插件连接Convoy当Valora完成，不提供Firefox/Edge入口。
- Valora专用扩展名称/品牌/稳定扩展ID（自己的公开key，不复制Convoy key导致ID冲突），专属native host名/allowed_origins、bundleID、应用唤起/Unixsocket/peer信任和可执行路径都指向本Valora；插件/host/IPC/引擎同源固定版本清单及独立Valora协议版本一致。握手必须核协议版本/Valora身份，旧Convoy/错版本不能显示已就绪。保持来源许可。
- 扩展/host真正随.app打包，主App、helper签名资源可审查，不仅源码目录可用；只固定库，不引入Convoy独立App/Sparkle。引擎SPM升级不自动等于扩展升级，记录同步升级和不覆盖其他App注册的机制；路径移动后能诊断修复，不能注册到临时QA目录冒充正式可用。
- Chrome native host注册仅明确用户点击设置动作才允许，开发注入独立browserroot和测试bundle；安全检查canonical path/owner/permissions/peer与消息长度/协议schema，禁止放宽为任意进程。拒绝非法scheme/path/超大消息及非允许扩展来源，不读cookie/token/真实网页。用户数据目录/host注册/插件加载权限安装均由用户在最终可审查候选操作，本轮开发不代写真实Chrome配置，不自动安装/启用扩展/接管真实下载。
- Chrome浏览器端动作沿Convoy已确认成熟模式，HTTP(S)正常下载链接与右键提交走Valora原冲突/列表；不能导入外部YouTube/helper/cookie/media全能功能。权限只保留本批必需；若源所需权限/行为超出已确认HTTP(S)且无法安全缩减，报告具体取舍，不擅自请求更广权限。
- 下载开关off关闭桥接接收/不创建后台监听，不唤起下载manager或接管链接，Chrome有明确未启用提示；打开后才监听，进程和socket随生命周期收尾；保持已接受off屏障，不因扩展绕过。测试仅fake nativeMessaging/隔离host注册/自产localRange/自建请求，Chrome未装或不能实际加载列待用户安装验，不伪造已连接。
- 不修改日历监控AI/400pt主面板/Alcove设置风格或软件完整音乐菜单。只做模块内最小适配，不全局拆包重构。只无界面功能测试/必要构建签名，不连续弹窗/批量菜单点击/压力内存性能/无变化全量。候选/private/tmp/valora-v0031-candidate，不覆盖用户运行包/dist或退出App，不Git提交推送/改归档或pi模型历史，定时器保持关闭。正式报告docs/reports/v0031.md后停等独立验收。

补充执行约束：不得因历史任务写有“实际UI验收”就运行任何批量弹窗/菜单点击/--verify-*或性能内存测试。设置引导正常源码与无界面状态机测试、消息编解码/兼容握手/隔离注册文件/peer验证和localRange功能即可，构建签名一次。新建Chrome专用manifest/公开key后报告实际extension ID、native host name、app/IPC协议版本及匹配检查。只写开发临时browserroot的注册文件，不探测/枚举真实Chrome配置或用户扩展。若需要真实安装授权，先把可审查候选和具体用户步骤交付，不提前请求用户确认空方案。
