# V0022：AI 用量页面、CodexUsage 命名、撤掉外来品牌资源

用户最新要求：“引入了啥？为啥有协议，就搞或者叫ai用量，里面先设计codex用量，图标搞成ai的，里面的类肯定要改codexusages而不是监控，去掉引入协议的内容”。本要求覆盖V0020品牌补充的OpenAI图标/显示名/保留codexMonitor内部命名方案，不撤销侧栏分组。

Codex已说明本次只借用了Agent HUD图标、没有引入SDK/后台服务，协议是图标许可。现在完整撤掉该借用资源及其许可，不是保留第三方图形但仅剥离许可。原项目其他仍使用的第三方依赖/许可证必须保留。

当前V0021仅文档只读研究，完成后串行本任务，不重开V0021或修改已发哈希。此为用户明确授权的生产UI小调整，不引入AI服务或账号功能。

## 1 当前设置

菜单栏分组：系统监控 → AI 用量 → 日历 → 下载监控；侧栏与页标题用“AI 用量”。保留通用独立、刘海屏[音乐,锁定屏幕,设备连接]、关于独立和Alcove分组间距、13pt页顶距。

“AI 用量”是可扩展页面壳，本轮内部仅显示“Codex 用量”条目/小卡与诚实的“功能准备中”。沿用现有SettingsCard/字体/间距，不新增复杂卡组或假可用开关/数值，不接入真实额度/账号，不凭空增加Claude等选项。

侧栏/页标题使用系统SF Symbols的sparkles（白色AI符号＋既有深灰圆角容器），不使用OpenAI/ChatGPT结形或通用</>，不下载/生成其他商标图，不引入依赖。当前已有系统符号渲染与深灰容器可最小复用；去除专门加载外部PNG的实现。

## 2 内部命名

Codex相关已存在类型/case/函数/测试/QA不得继续以codexMonitor/Codex Monitor/“Codex监控”命名。使用清晰Swift命名codexUsage/CodexUsage；泛化页面壳可为aiUsage/AIUsage，内部Codex子内容采用CodexUsage语义。用户写codexusages表达是usage不是monitor，不为复数拼写无意义造数据模型。

目前还没有真实Codex provider/业务类，不要为凑命名建立假监控服务或空架构。仅重命名当前实际承担页面/子内容的标识，必要原生子view可用CodexUsageView。不要改系统监控systemMonitor或下载监控downloadMonitor，不无谓改其他偏好key。导航当前没有需要保留的持久化Codex Monitor选择时，删除旧raw/display映射；若发现确有持久化消费者须写最小迁移，不静默漏入口。

## 3 完整移除本次引入资源

移除 Sources/Valora/Resources/CodexUsage 内chatgpt.png、AgentHUD-LICENSE.txt、LobeIcons-LICENSE.txt、本资源PROVENANCE.md；该专用目录无其他必需内容时删除目录。移除CodexUsageArtwork.swift中的外部资源加载/旧品牌Mark，改系统符号。

移除Package.swift仅为该目录的resources声明、脚本package.py直接复制和对应manifest字段；确认该模块没有其他SwiftPM资源才撤Bundle.module相关机制。不留运行时资源缺失fallback或图标缺失警告，不让构建依赖已删除目录。最终新打包.app不能携带该目录/PNG/两个许可证或旧Valora_Valora.bundle里的拷贝；避免旧构建残留被package.py无条件复制，应按当前真实资源声明控制并从干净产物验证，不清空用户其他目录。

保留MediaRemote适配器等其他正在使用的第三方许可，应用彩色图标、Outline-v7、设备资源不动。历史任务/报告/验收截图保留为历史，不是继续运行时引入；不要为抹掉历史而重写旧证据或误删品牌原始资源。

## 验证交付

针对性设置回归改为AI页面/分组顺序/Codex子内容/系统符号，无外部图标加载与专用资源/许可打包；删除只测试被移除品牌PNG的专用断言，保留其他有效设置回归。独立打包.app从项目外运行设置渲染，确认浅色/暗色/失焦、AI图标可见、页面内Codex 用量条目/准备中、无旧Codex Monitor和无资源缺失。构建签名，验证日历entitlement和无音频捕获声明保持。

报告docs/reports/v0022.md，证据docs/verification/v0022/，明确本轮未引入SDK、依赖或后台服务、被移除资源范围、其他有效许可保留。若Mac仍锁屏，真实点击待验，不绕过或声称实机成功。完成停止，Codex独立复核。

禁止真实媒体播放切歌seek音量、设备连接、权限登录项/系统设置写、个人日程/账号额度读取、安装发布、Git提交推送、改归档或会话模型历史，不恢复HTML原型。
