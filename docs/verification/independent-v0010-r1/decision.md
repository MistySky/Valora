# V0010-R1 独立验收（2026-10-24）

结论：V0010及R1在本批“获取与匹配探针”范围验收通过，可进入逐行显示和播放同步。未接歌词UI，未完成QRC解密/逐字高亮。

- 检查搜索/LRC/QRC evaluator：HTTP非2xx在内容解析前拒绝；LRC必需retcode/code字段并判断成功；搜索必需code/list；QRC需result及对应content。报告与实现范围一致。
- 重编译并重跑此前独立URLProtocol错误复现（原check.swift，直接链接新probe.swift，不启用其main），HTTP503与业务码1001现都request_failed，不再timed_lrc，见error-check.log。
- 独立swift test119项通过（Valora35/Core84），包含新增HTTP/API/结构错误分支，普通测试无在线依赖。
- 独立公开样例网络探针：validation_ok=true/request_ok=true、无request/qrc失败，studio/live仍分别63/36行LRC，正确版本歌曲编号不变。网络仅显式两个公开样例，无当前媒体/账户/曲库读取。
- QRC仍decoded=false，仅取得HEX载荷，不把合成解析当真实逐字支持。
- 独立构建至/private/tmp/valora-independent-v0010-r1/Valora.app，独立候选及dist签名verify deep strict通过。未安装/发布/提交Git或写播放器/系统设置。

进入V0011：现有下方QuickPeek区域显示逐行歌词、同步暂停恢复seek、切歌提示优先、无歌词回落、长句滚动与多屏归属；默认关闭的单一显示歌词设置沿用现有UI。真实逐字另批验证，无逐字数据不伪造高亮。物理双屏与真实播放对齐仍待实机。
