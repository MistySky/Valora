# V0012优先补充：先查成熟歌词获取方式，修复覆盖率，不引入Go

用户最新明确要求：立刻看看Lyrimuse等开源项目各个歌词获取/匹配方式，借鉴别人可用方案，避免当前有些歌拿不到；唯一明确架构要求是不引入Go。本补充属于当前歌词功能，不新增播放器/通知等模块。接收后优先处理本研究与获取链路，不先把显示UI当作整体已完成。

## 已核查源码，可直接定位

- https://github.com/Yudaotor/lyrimuse/tree/main/lyrimuse-engine ：qq.go、qqlocal.go、match.go、des3_qmusic.go。QQ精确ID与本地曲库辅助、搜索匹配、QRC解码、多源候选评分分别核对。
- https://github.com/Yudaotor/lyrimuse/blob/main/lyrimuse/Sources/LyrimuseCore/Lyrics/LyricsSyncEngine.swift 和同目录YRCParser.swift：统一字时间、暂停/进度定位，不以整句动画假装逐字。
- https://github.com/ddddxxx/LyricsKit/tree/master/Sources/LyricsService/Provider ：Swift歌词源请求/解析组织；不同provider协议与失败处理，不直接信任旧接口可用性。
- Lyrimuse有QQ、网易云、酷狗、LRCLIB等实现；先比较成熟方式，不机械并发十几个源。源码仅作协议/策略参考，实际复制/改编要保留并评估其许可证；不把Go引擎打包进来、不新增Go进程或脚本业务运行时，维持Swift6原生服务。

## 优先解决真实缺口

先读docs/verification/zhifou-lyrics-diagnosis/findings.md和search-summary.json。当前《知否知否》搜索HTTP200/约0.93秒，歌词接口200/约0.198秒；基线匹配器以artistMismatch拒绝，因为系统只报胡夏、QQ结果为胡夏 / 郁可唯。这是匹配过严，不应单纯增加provider掩盖。还存在同专辑同276秒男声版，不可简单contains/放开版本/选第一条。

比较并借鉴：歌手拆分与署名顺序/别名、标题版本保护、可验证的精确歌曲ID、专辑与时长联合证据、候选评分和拒绝阈值；证据不足保留ambiguous/无匹配，不显示错版本。分别覆盖合唱完整署名/缺部分署名、明确男声版、Live/DJ/伴奏/同名翻唱。不能因为3秒没解密就把歌曲宣称不支持逐字。

## 研究后落地到当前V0012

- 在docs/research/lyrics-provider-comparison.md写简洁对照：各方案如何定位歌、实际歌词端点、逐字格式、匹配/回退策略、超时/缓存、依赖许可，以及哪些确实可用、哪些只读源码尚未实测。
- Swift实现当前QQ链路应采用的可靠部分，优先真实ID/正确匹配/QRC及错误诊断。若QQ仍有明确覆盖缺口，再用少量公开样例核查网易云/酷狗/LRCLIB作为候选回退；不要未经验证把跨平台多源结果当同版本。
- 不先盲目接入十几源；最多选确有收益的最小回退方案并说明证据，不改变系统当前播放来源选择。若需要引入新依赖或账户访问，先报告具体必要性，不自行扩大权限/登录或读取私密账户库。
- 仍遵守3秒总预算、超时隐藏/拒绝迟到结果、成功有界缓存及请求去重取消；多源不能变成每源3秒串行等待或请求风暴。能缓存精确身份则复用，不能为每个elapsed tick重新查。
- 补结构化故障分类（缺元数据、无候选、署名/版本/时长拒绝、HTTP/API错误、解码错误、超时），生产UI不露错误码，诊断仅记录必要公开歌曲字段；不要把所有失败统称暂无歌词。
- 交付V0012报告时列明该研究与实际采用部分，附真实公开样例、未匹配原因、独立可复现命令和离线防错回归。不能只写调研报告而不改当前已证实的匹配缺陷。

显示规格、非刘海屏补充、缓存/资源/数据安全/Git边界均保持：不真实播放/切歌/seek/音量/系统设置写，不改来源、不Git提交推送、不安装发布、不创建自己的定时器。完成Codex独立验收。
