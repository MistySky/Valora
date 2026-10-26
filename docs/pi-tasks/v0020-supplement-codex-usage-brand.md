# V0020 同轮补充：Codex 用量名称与标识

用户已明确同意：原“Codex监控”改为“Codex 用量”，使用参考 Agent HUD 的 Codex 对应品牌标识；设置侧栏深灰圆角底＋白色标识，尺寸/圆角沿用 Alcove；未来一体菜单栏与展开面板沿用同一标识、标题和额度语义。当前仅设置占位，不提前实现菜单栏、真实额度请求/账号读取。

本补充与正在执行的 V0020 侧栏分组同轮收尾，不重开主体、不回退生产代码，不修改已发送任务或哈希。若主体已交付，再基于现有成果完成本补充并独立报告增补；Codex会一起验收。

## 已核对的参考资源

仓库 https://github.com/jazzenchen/agent-hud-native-open
Sources/AgentHUDDesktop/Components/AgentLogo.swift 的 canonical/注释明确 Codex 与 ChatGPT 共用 OpenAI 结形标识，资源为 Sources/AgentHUDDesktop/Resources/chatgpt.png。不要把它误称为专门绘制的 Codex 桌面应用图标，更不要使用当前通用 </>。

复用该对应图形作为白色单色 mask，深灰底，不照搬 Agent HUD 的绿色着色、外部quota光环或布局。保留当前 22pt SettingsIcon 容器、内边距/视觉重量和现有选中/失焦行为。资源从可追溯来源取得，保留仓库 revision/path/SHA256 与适用随附许可：仓库 Apache-2.0、Resources/LobeIcons-LICENSE.txt (MIT, Copyright 2023 LobeHub)；准确核实其适用资源出处，不冒称该品牌标识为Valora原创。只引入这一项必需图标，不复制整个logo库或引入依赖。

用现有打包方式或SwiftPM最小资源机制接入，确保独立 .app 真能找到资源，不能只在源码工作目录加载。测试/预览若主bundle位置不同提供明确可靠的同源资源定位，不能把缺图静默当完成。白色图形、透明留白、灰底的暗色/浅色及失焦可读性需实际看图；不使用imagegen重画品牌形状。

## 变化范围

侧栏、该页标题显示“Codex 用量”（空格保持），内部 case codexMonitor/rawValue 等可保留避免无谓重命名。主体分组仍为通用；刘海屏[音乐,锁定屏幕,设备连接]；菜单栏[系统监控,Codex 用量,日历,下载监控]；关于。

正文仍诚实“功能准备中”。未来功能已确认方向为5小时/一周额度及各自重置时间；本批不显示假数值、不接provider、不访问个人账号凭据、令牌或真实限额。

## 交付

更新必要的显示名/顺序断言，构建签名，独立打包产物设置实际渲染含Codex 用量页、浅色/暗色及选中/失焦图标；资源缺失不能以 </> 回退冒称已完成。记录 docs/reports/v0020.md 补充和 docs/verification/v0020/，引用资源出处与许可。沿用主体全部安全边界，不Git/安装发布/改归档/真实媒体设备系统权限操作，不恢复原型或新增模块。
