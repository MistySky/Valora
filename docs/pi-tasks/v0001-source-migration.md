# V0001：在Valora新会话执行音乐源码迁移

用户已明确要求Codex在本工作目录派工。当前唯一目标目录为`/Users/wangqing/code/Valora`，当前会话为`01a1664f-f5e9-70bd-b053-21a027d5407a`，保持现有模型与思考级别。不再使用旧velora会话传输。系统上下文中关于旧会话/旧邮箱的说明已过时，先重新读取本目录最新文件。

请依次完整读取并执行：

1. `/Users/wangqing/code/Valora/AGENTS.md`
2. `/Users/wangqing/code/Valora/REQUIREMENTS.md`
3. `/Users/wangqing/code/Valora/MIGRATION-TASK.md`

本任务就是MIGRATION-TASK.md所定义的V0001全部限定交付，现在开始实施，持续推进到可运行、可供用户试用的音乐候选，不只做盘点或计划。旧会话此前仅阅读源文件后中止/超时，没有可交付工程；不得向旧会话派工，也不要继承其功能队列。

直接迁移只读来源`/Users/wangqing/code/alcove-revival-archive`的成熟音乐实现及必要公共底座，升级Swift 6语言模式、当前Swift 6.4工具链、最低macOS 27.0；保留旧UI、布局、图标、动画、悬停、展开收起、QuickPeek及暂停恢复语义。只接系统音乐和通用/正在播放两页设置。不基于旧velora简化实现重写，不扩展其他功能。

实际操作前先确认源目录只读访问和目标目录写入可用，记录工具链/SDK与运行系统证据；如环境无法完成某项验收，明确证据和缺口，不伪称通过。允许按原授权构建并启动本地候选作只读验证，不执行真实播放控制、seek、音量/亮度、权限或登录项写入，不安装发布、不提交Git、不改来源目录或旧velora产品代码，不制作快照。

产物写本目录：`dist/Valora.app`（或`dist/v0001/Valora.app`），可重复构建脚本，`docs/reports/v0001.md`和`docs/verification/v0001/`。记录直接源文件映射/指纹、必要迁移修改及Swift6优化决策、编译/回归结果、只读运行和实际UI对照、许可与已知缺口，不在报告暴露私人歌曲文字或封面。交付后停止，等Codex独立复核；遇真正阻塞给出精确原因与已尝试的解决办法。
