# V0010：Swift 6 QQ 歌词获取与匹配验证（先验证，不接UI）

先读AGENTS.md、docs/CONTINUATION-PLAN.md、docs/verification/independent-v0009-r2/decision.md。用户已授权按顺序推进歌词，本批仅验证获取，完成后等Codex独立复核，不能自己开始UI或设备功能。

## 目标

用Swift6/Foundation URLSession编写可复现的小型获取验证，确定QQ歌词接口实际可用性、歌曲匹配及逐行/逐字数据可获得程度。可把纯解析/匹配逻辑放ReferenceCore中以供后续复用；网络验证可用scripts下Swift命令行探针，明确输入/输出目录和超时。不要把探针接到正常App启动、设置或系统播放器。

参考协议实现：LyricsKit QQMusic.swift（https://github.com/ddddxxx/LyricsKit/blob/master/Sources/LyricsService/Provider/QQMusic.swift），Lyrimuse的lyrimuse-engine/qq.go（https://github.com/Yudaotor/lyrimuse/blob/main/lyrimuse-engine/qq.go）和qqlocal.go（https://github.com/Yudaotor/lyrimuse/blob/main/lyrimuse-engine/qqlocal.go）。先读当前实际代码，不能把仓库自述或旧接口当成实测。参考LyricsKit思路自行Swift实现，不引入Go引擎，不擅自新增第三方包；保留实际复制/改编文件的许可来源，不能不加说明整段移植GPL源码到本项目。

## 验证范围

1. 用显式的公开歌曲样例输入（歌名/歌手/专辑/时长），不要读取用户当前歌曲、QQ账户、本地私人曲库/凭据。少量正常HTTP请求即可，不登录、不处理验证码、不重试风暴。以真实响应核对搜索得到的songmid/歌曲ID和歌词接口响应，若接口失效可核查当前公开客户端/网页路径，不绕登录/付费限制。失败要记录HTTP状态/解析原因，不能把空响应写成成功。
2. 匹配考虑歌名歌手、专辑、时长与live/remix等版本标识；不确定就返回无匹配，不盲选第一首。不要求全平台或所有歌曲覆盖。
3. 解析LRC时间戳，保留行顺序与有效时间边界；明确无歌词/纯音乐/纯文本与带时间戳的区别。实际可获得逐字QRC时核对返回格式、解码需求与逐字时间字段；本批不能拿逐行文本平均切字冒充逐字。若QRC解码需额外工作，报告独立下一小任务，不用假数据宣称已支持。
4. 网络超时/取消/HTTP失败/解码失败要可定位，避免日志记录cookie/token/身份标识；网络烟测手动显式运行，普通swift test禁止依赖在线服务。少量可复现fixture覆盖解析、版本误配/拒绝、无歌词；真实网络证据与离线fixture测试分开标明。禁止真实媒体播放/暂停/切歌/seek/音量、蓝牙或系统设置写操作。

## 体验及边界

本批不改设置页面/NotchView/QuickPeek布局或动画，不改应用图标、菜单栏Outline-v7及打包接线，不重构现有播放器。后续UI必须沿用Alcove/归档复刻的成熟样式，歌词属于新增区域内容，不借机重新设计。

不修改只读来源/小写velora；不安装发布、不提交Git、不创建定时器，不自行发下一任务；保持现有pi会话模型与历史。

## 交付

- docs/reports/v0010.md，列明真实测试日期、样例、调用方式、成功/失败路径和接口依赖，不写未经验证的能力。
- docs/verification/v0010/：网络响应结构摘要（不输出整首歌词到报告）、歌词时间戳/行数/逐字数据有无、样例匹配结果、离线测试日志、构建签名记录与必要来源许可说明。
- 独立可复现命令及脚本，明确当前仅探针、没有接入UI；尽量不改变生产App启动行为。
- 新的有价值测试与现有97项回归通过，构建签名通过并更新dist候选（界面和功能不变）。若网络确实不可用，交付可诊断的失败结论及最小建议，不能伪称成功或无限尝试。
