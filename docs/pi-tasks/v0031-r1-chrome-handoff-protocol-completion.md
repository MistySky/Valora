# V0031-R1 限定返修：Chrome接管收尾与host版本匹配

读AGENTS和docs/verification/independent-v0031/decision.md。独立12 Swift及包签名子集通过，但JS三个接管情景与真实host隔离子进程两个版本情景均失败。沿本批范围修复，不新功能/不改下载算法或其他模块。

1 Chrome onDeterminingFilename所有分支恰好suggest一次，含成功/失败/异常/超时；成功不能漏回调。官方primary来源https://developer.chrome.com/docs/extensions/reference/api/downloads#event-onDeterminingFilename。仅ok不够，确认accepted:true及本Valora匹配协议后才cancel Chrome下载；cancel callback lastError时不能erase，保留原记录和可恢复提示。native调用加有界deadline，原子suggest-once和迟到响应处理，不能超时回落Chrome后又因迟到结果cancel/erase或再次提交；host失败不吞Chrome下载。补独立Node vm断言不调用真实Chrome，保留Tests/BrowserExtensionTests/independent-handoff.mjs的有效call counts断言；有效成功fixture可补新必需身份字段但不删边界。成功/不接受/取消失败/host不回调/迟到/功能关闭各一次功能情景，非压力循环。

2 NativeMessagingHost Chrome入口必须先验证protocolVersion（缺失/非法/错误拒绝，不把旧请求改version1假匹配），所有status/ping/download/launchApp/getDownloads/pause/resume/cancel同样生效；验证Chrome提供的调用origin与本Valora固定extension ID一致。App侧也保留身份和peer检查，不能靠只测validateEnvelope绕过真实host入口。独立Tests/BrowserExtensionTests/independent-native-version.py给出正确origin+错误/缺失version，目前ok:true必须修。仅隔离TMPDIR运行实际打包host、fake nativeChrome/隔离socket，禁止真实Chrome配置/页面/下载。

3 popup当前open初始hidden，render任何分支都不显示，用户在App未运行时无法显式“打开Valora”。修状态机：host注册有效但App没运行时提供显式打开，下载off与App没运行状态准确区分，正常连接不重复启动；host未设置给真实引导，不假连接。只用fake DOM/runtime事件测，不打开用户浏览器。

只无界面定向功能/必要构建签名，严禁--verify-*、弹窗/批量截图、循环开关或内存性能/无关全量。已有主体资源身份/最小权限/400ptUI/开关off不启动桥接、源码许可保留。签名peer不可放宽。保存真实Chrome/正式host注册安装步骤，安装由用户在可审查候选手动操作，本轮不写真实Chrome根、启用插件或接管真实下载/读cookie。可补同包signed host到隔离fake service的正向握手证据，不用虚假peer closure当真实签名已测。

候选新/private/tmp/valora-v0031-r1-candidate，报告docs/reports/v0031-r1.md。不要覆盖正在运行包/dist或退出用户App，不Git提交推送/改归档模型历史，不恢复定时器、不开始V0032。完成停等独立验收。
