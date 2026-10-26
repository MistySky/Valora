# 用户确认的接续顺序（2026-10-24）

目标目录/Users/wangqing/code/Valora；来源/Users/wangqing/code/alcove-revival-archive只读；不在小写velora开发。

1. 现有功能收尾：V0009-R2已通过Codex独立97项测试、构建签名、音乐UI74项及注入多屏12项验收，见docs/verification/independent-v0009-r2/decision.md；当前V0010/R1获取验证已独立验收通过（119测试、构建签名、错误模拟与两公开样例网络复核），见docs/verification/independent-v0010-r1/decision.md；docs/pi-tasks/v0011-line-lyrics-display-sync.md已在确认ready后投递，因已核实上游超时中断，单次投递v0011-resume-01从现有成果继续；接续后再次Connection error/Request timed out中断，已停止重复投递，用户已选择继续等pi服务恢复，由pi接着完成，Codex验收；未正式交付，不宣布验收通过，再歌词显示与同步，不把pi报告当通过。真实双屏缺设备时明确待实机，不伪称完成；能独立推进的歌词验证不因物理条件无限停滞。
2. 歌词：先小任务验证QQ歌词获取和匹配（Swift6/URLSession；参考LyricsKit、Lyrimuse源码，核查许可，不引入Go）。接口实测结果写报告，有LRC时间戳再接逐行，有QRC逐字时间再高亮，不造时间戳。随后复用既有下方QuickPeek区域，开关采用现有设置控件风格；切歌提示优先约2秒再回歌词，无歌词回退歌名歌手。短句不滚，长句右向左且当前唱到部分可见；暂停同时停时间轴/高亮/滚动，恢复/seek按真实进度；缓存、取消、快速切歌过期结果、防错版本、多屏活动归属均需验证。未经验证不把网络接口或逐字功能称为可用，不默认全量接入多歌词源。
3. 清理：在现有功能与歌词验收后清掉确定无引用的专用残留/临时重复产物，保留所需供应商许可/资源、用户资产及验收证据；不为了减行数重构公共底座，不大范围删除旧图标候选和历史证据，不Git提交。不改变已验收体验。
4. 设备连接：上述完成后按AGENTS.md最新范围，基于归档成熟设备纵向链路迁Swift6/macOS27。只保留总开关/设备外观(3D模型、符号)，时长固定默认(先核原版默认，当前取证5秒)，低电量提醒默认开受总开关、阈值20%固定、提示音默认策略。核对原版与复刻区别，UI/控件图标/布局/动画沿用Alcove，只减少确认条目；设备实体/低电量实测条件不足必须注明，不能用fake冒充。

用户授权每15分钟本聊天接续一次；使用现有绑定pi文件邮箱单任务串行派工。busy/request/claimed时不重复派工，不新开pi、不改历史或模型。每次完成一批独立验收后才派下一批，范围只限上面顺序和限定返修。功能UI/图标按Alcove，可参考复刻；已确认Valora彩色应用图标、Outline-v7菜单栏图标例外不变。不得擅自真实播放/切歌/seek/音量、连接设备、改权限/登录项、安装发布或Git提交。不重启用户候选来冒充验收。

只在有关键完成、失败或需用户决定时通知，状态无变化安静。所有已授权范围完成后通知并移除此接续；遇用户必需的物理测试可记录待验并通知一次，不以缺设备反复空转或宣称全通过。

最新覆盖：项目已上传私有GitHub，main/c4771fc及baseline-2026-10-24-before-lyrics-v2保存实施前基线。pi已恢复并交付V0011；源码独立136测试/构建通过，但体验按用户最新要求返修。当前V0012最终逐字/上下换句任务已投递，见docs/LYRICS-NEXT.md，等待正式交付独立验收，不再按旧超时等待或重复投V0011。定时器仍已移除。

最新调度覆盖：已恢复内置接续valora，每10分钟，当前范围歌词完整收尾→清理→流畅度测试；本轮不自动迁入设备。另核查用户指定《知否知否》获取失败原因，按只读元数据/HTTP/匹配证据定位，不盲目放宽匹配。

最新宽度覆盖：无实体刘海屏模拟/胶囊播放紧凑214pt、展开345pt统一，歌词与强制模拟开关解耦，均可显示紧凑和展开歌词；此前“普通胶囊紧凑不显示”撤销。待消费V0012补充任务已更新，验收以最新AGENTS/LYRICS-NEXT和任务为准。

最新用户确认（V0012-R1，同轮交付）：紧凑/最小及展开歌词短句均整体居中，覆盖旧左对齐；长句仍按真实逐字演唱位置跟随。胶囊圆弧及隐藏/取消缺陷与逐字时间同步优化一起修复、一起交付独立验收。见docs/pi-tasks/v0012-r1-centered-lyrics-contour-cancellation.md及docs/pi-tasks/v0012-r1-supplement-word-sync.md。不要修改已发送任务哈希，不重复派工，不先进入清理。

最新阶段：V0012-R1同轮补充已正式交付，Codex独立161原测试/构建签名/歌词QA28通过，但新增非合作provider超时回归失败，局部选行与逐字时间源分离、长句横移仍按词跳变；限定R2见docs/pi-tasks/v0012-r2-local-timeline-deadline.md及docs/verification/independent-v0012-r1/decision.md。R2已排入现有邮箱，不重复派工，仍不进入清理。

最新阶段：R2原163项独立测试/构建签名/歌词QA28通过，原deadline已修；新增立即取消回归仍会挂起controller，采样时刻未真实保留且分段缓存key存在越界路径。限定R3见docs/pi-tasks/v0012-r3-anchor-cache-cancel.md及docs/verification/independent-v0012-r2/decision.md，已单次投递原邮箱，不重复，不先清理。

最新阶段：R3已独立166测试/构建签名/歌词QA28通过，三个返修项接受。整体仍有无逐字LRC长句offset固定0导致后文不可读的旧需求缺口，限定docs/pi-tasks/v0012-r4-line-only-overflow.md已单次排入邮箱。保留QRC逐字行为，不新增功能，完成复验后才V0013清理。

最新阶段：V0012/R1—R4歌词实现自动范围独立接受，168测试、构建签名、歌词QA31/音乐74/注入多屏12通过，见docs/verification/independent-v0012-r4/decision.md。实际QQ人声同步和物理双屏待用户实机，通知一次，不冒称全部实机通过。已单次投递V0013限定残留清理，完成独立验收后才V0014流畅度；本轮不进入设备。保留用户资源/历史证据/基线，不Git提交推送或安装发布。

最新阶段：V0013限定清理独立接受，168测试/构建签名通过，见docs/verification/independent-v0013/decision.md。已单次投递V0014隔离流畅度/资源测量，必须原始证据并区分回调与呈现FPS；不重复派工、不进入设备。歌词人声同步/物理双屏待实机已通知一次。V0014正式交付后独立复验，全部本轮范围完成才通知并移除接续。

本轮最终完成：歌词V0012/R1—R4、限定清理V0013、隔离流畅度V0014均经Codex独立复核；V0014独立168测试/构建签名、资源audit39项、歌词31/音乐74/注入多屏12通过，见docs/verification/independent-v0014/decision.md及audit/audit.json。暂停/隐藏/歌词关闭/被动屏无持续歌词刷新，CPU/RSS证据已保存；回调调度不等同真实呈现FPS。实际QQ人声同步、物理双屏及长期体感仍如实待用户实机，已通知一次，不反复打扰。授权本轮范围完成，停止自动派工，不进入设备，不Git提交推送或安装发布。

Codex内置接续automationId=valora已在本轮独立验收完成后删除，工具返回deleteStatus=deleted；不自动恢复。

用户最新明确授权开始设备连接模块（原版Alcove证据＋只读成熟复刻代码迁移），覆盖此前本轮不进入设备的停止点；按docs/pi-tasks/v0015-device-connectivity-migration.md执行。设置仅总开关/3D或符号外观，低电量提醒固定开启/20%受总开关，时长和提示音核原版默认，证据不足采用已说明5秒/提示音开策略。V0015单次投递现有pi，完成Codex独立验收；不恢复旧全量队列/定时器，不真实设备连接或系统写、不Git提交推送/安装发布，保留已接受音乐歌词多屏体验。

最新设备验收：V0015原185项独立测试/构建签名/设备QA29及精简设置视觉通过子集，新增设备开关即时读取/stop拒绝刷新两回归失败，声音无stop接口及退出漏收尾；见docs/verification/independent-v0015/decision.md。限定V0015-R1已单次投递现有pi，不重复；完成独立复验，不恢复定时器、不新增模块或真实设备/系统写。

用户最新再次重申：“整体还是继续alcove 的，升级语言，只是加了个人的歌词”。整体以原版Alcove为体验基准、成熟复刻为直接代码底稿，主要做Swift6/macOS27迁移，不自创产品/布局/动画/公共架构；歌词是明确新增个人功能。此前逐项确认的设置精简和品牌/交互按明确记录保留，不借迁移扩需求。必要适配须列原代码位置、具体原因、最小修改和体验影响；原实现已有处理优先直接保留恢复。当前设备R1补充见docs/pi-tasks/v0015-r1-supplement-alcove-baseline.md，仍等独立验收。

设备设置最新覆盖：用户同意移除3D/符号外观设置，仅留设备连接总开关。固定按型号自动3D，未知/无资源/Reduce Motion沿用既有符号回退；旧外观偏好不覆盖。补核蓝牙用途声明及授权处理，3D本身不需蓝牙授权，实际IOBluetooth权限弹窗未实测不冒称已授权；见docs/pi-tasks/v0015-r1-supplement-auto-artwork-permission.md，补充排同轮邮箱，不重复主体。

用户最新要求当前需授权项目沿用Alcove手形权限附件hand.raised.slash.fill，基于真实状态、点击授权/系统设置引导、返回刷新，不能只是灰色占位。仅核当前设备检测/实时波形及确需批准的登录项，不给歌词或所有设置乱加；用现有SettingsToggleRow接口最小接线，不自创权限中心，QA不实改权限。见docs/pi-tasks/v0015-r1-supplement-permission-hand-ui.md，同轮补充已排邮箱，不重复R1。

用户最新纠正权限交互：手形仅状态标志不可点击，真正操作仍是功能开关；点击尝试开启才处理授权，成功后标志消失且完成本次开启，拒绝/取消保持关闭；明确覆盖旧“点手/禁用开关”方案。Codex独立R1 194测试/构建签名/设备QA31及精简设置视图通过子集，但当前手形Button+disabled开关不符，限定docs/pi-tasks/v0015-r2-toggle-authorization-flow.md已投递。只做原样式最小接线，不新权限中心，不实际触发或接受授权，完成独立复验。

最新验收：V0015-R2原198测试/独立构建签名/设备QA31通过子集，但两项新增权限回归失败，见docs/verification/independent-v0015-r2/decision.md。限定V0015-R3修取消状态可观察、音频授权返回完成及首次登录批准衔接；已投递同一pi邮箱，不重复，不恢复定时器或新增模块。

最新独立验收：V0015-R3原201测试/构建签名/隔离设置视图及设备QA31通过子集，原两回归已修；新增登录旧回调完成新意图回归失败，另核生产音频激活异步被旧denied清pending、首次注册取消未撤销。限定V0015-R4已投递，见docs/verification/independent-v0015-r3/decision.md及docs/pi-tasks/v0015-r4-permission-async-cancellation.md；不重复，不恢复定时器，不开新模块。

最新验收结论：V0015-R4设备/权限自动验证范围独立接受，205全量原测试＋两项新增独立边界测试通过，构建签名/设置视图/设备31/歌词31/音乐74/注入多屏12通过；见docs/verification/independent-v0015-r4/decision.md。真实OS授权、耳机连接与3D/提示音、物理双屏仍待实机，不冒称全部通过。不继续返修派工，不恢复定时器；菜单栏监控/Codex/日历目前仅讨论，未授权本轮实现。

用户授权联动测试已完成：独立新增3项设备×音乐歌词×展开音量×多屏/暂停空闲交叉回归全通过；独立实际SwiftUI隔离设备QA31通过，未发现新增阻断，不改生产代码不派返修。见docs/verification/independent-v0015-interaction/decision.md。真实设备/授权/物理双屏等仍待实机；菜单栏新模块未接入，不算已测。

用户最新授权V0016：先迁入Alcove原样日历设置页（单开关）并接真实EventKit日历授权，手形仅标志、开关请求、成功完成/拒绝取消off；本批不实现Calmon展示/菜单栏/快捷键，不读取真实日程或改权限。任务docs/pi-tasks/v0016-calendar-settings-authorization.md已排现有pi邮箱；默认访问关闭为本项目策略，基本日期月历不依赖日程授权。完成独立验收，不恢复定时器，不Git提交推送。

V0016独立授权子集通过：215测试+2新增日历权限回归、构建签名/设备32/设置几何通过，软件已打开。用户指出日历图标错误，Codex复核确认为SettingsIcon迁入漏掉归档calendar专用分支，侧栏/标题成了通用粉底SF。整体UI不接受，限定V0016-R1已投递恢复原专用分支，见docs/pi-tasks/v0016-r1-calendar-original-icon.md。卡内calendar.badge.clock保持，授权逻辑不改；真实授权待实机，不开始菜单栏展示。

用户实机反馈日历不能授权，Codex仅点一次开关复现失败（未接受授权/读事件）；TCC明确Hardened Runtime缺com.apple.security.personal-information.calendars，dist runtime签名无entitlements。V0016整体入口不通过，限定R2补最终签名资源声明并区分真实拒绝和请求错误，与R1图标同轮收尾。见docs/pi-tasks/v0016-r2-calendar-signing-entitlement.md；保持runtime，不清TCC/重置权限，不以fake冒称弹窗通过。

用户最新仅授权可点击HTML设置原型V0017（docs/pi-tasks/v0017-clickable-settings-html-prototype.md），不真实实现/修改原生软件。侧栏通用→音乐→日历→锁屏→设备连接→系统监控→Codex监控→关于，锁屏在日历下；先看整体效果，暂停继续扩日历展示。产物docs/prototypes/settings-v1/index.html，所有权限/屏幕/日程/用量仅模拟，生产代码与系统状态不动。完成Codex检查并给用户打开，不恢复定时器或Git提交推送。

用户提供原版录屏并明确将封面翻转/双击收尾交给pi，V0018已投递现有会话。证据docs/verification/user-original-artwork-video/，任务docs/pi-tasks/v0018-recorded-artwork-flip-and-title-doubleclick.md。Codex前一轮原生标题mouseDown+NSWorkspace唤起和晚到封面逻辑占位已在当前未提交源码，224测试/构建签名/MusicQA74通过，但真实双击成功/原版逐帧一致性未确认，不能冒称通过；交接后Codex冻结相同生产文件，pi从当前成果继续，不回退菜单顺序/日历权限/HTML原型。

用户最新撤销复杂设置原型，要求保留现有Alcove原生样式小调整；Codex已按明确指令删除docs/prototypes/settings-v1（清单docs/verification/settings-simple-plan/prototype-removal.json），不要恢复原型/大卡方案。新授权V0019见docs/pi-tasks/v0019-simple-native-settings-reduction.md：悬停并入通用上卡、统一标题后留白、去通知/实时活动分组、正在播放改音乐图标不变；整个移除实时波形及系统音频捕获专用链路（普通波形/音量保留）；设备/日历仅授权；锁屏日历下，系统/Codex/下载/关于占位，不接真实功能。先完成V0018再串行本任务，Codex独立复核，不Git/安装发布/系统媒体权限操作或恢复定时器。

2026-10-25 Codex独立验收V0018/V0019：227测试、独立构建签名、音乐74/歌词31/注入多屏12/设备32通过，九页设置经CUA实际点击核对；原型已删除、实时波形整链移除，V0019接受。真实歌名双击生产日志确认QQMusicMac唤起请求及完成；原版动画体感/最小化恢复不冒称通过。仅音乐来源优先仍未实现，保留明确缺口。见docs/verification/independent-v0018-v0019/decision.md。停止待用户下一步，不自动派新功能、恢复定时或Git提交。

2026-10-25 用户确认V0020：恢复Alcove侧栏分组，通用独立；刘海屏组为音乐→锁定屏幕→设备连接；菜单栏组为系统监控→Codex监控→日历→下载监控；关于最后独立留白。覆盖V0019平铺顺序，仅改导航分组/间距，各页内容和13pt顶距保留。见docs/pi-tasks/v0020-alcove-sidebar-groups.md，单次派现有pi，交付后独立复核，不扩功能或Git/系统媒体权限操作。

2026-10-25 用户授权恢复每15分钟验收与串行安排新活；Codex heartbeat automationId=valora 已创建ACTIVE。当前先V0020独立验收/必要限定返修，通过后优先对已确认“仅音乐应用、网页视频不抢占、显示控制同源”做只读可行性核查并备最小任务。菜单栏监控/日历/下载/锁屏的未定具体内容先给计划，不凭占位自动扩功能；按用户后续明确确认推进。busy或request/claimed不重复派工，不新pi、不改历史模型；原系统/媒体写、权限、安装发布及Git限制仍保留。状态无变化安静，关键完成/失败/需决定通知。

2026-10-25 用户确认V0020同轮补充：Codex监控显示名改“Codex 用量”，图标参考Agent HUD对应Codex的OpenAI结形标识，白色标识＋Alcove深灰圆角底，替换通用</>；来源实际Codex/ChatGPT共用chatgpt.png，资源可追溯随许可。未来菜单栏单色/展开同名方向保留，当前仍占位不接账号/额度后台。见docs/pi-tasks/v0020-supplement-codex-usage-brand.md，现有邮箱排同轮，不重复主体。

2026-10-25 V0020＋Codex 用量补充独立源码/9设置回归/构建签名/打包图标及原生视图渲染接受，记录docs/verification/independent-v0020/decision.md。CUA报告Mac锁屏，真实点击待解锁，不把离屏视图称实机通过。已按授权串行投V0021音乐来源优先只读可行性研究；不改生产、不查真实媒体或触发新授权，正式报告后复核最小实现范围。

2026-10-25 用户最新覆盖V0020品牌方案：页面改“AI 用量”，内部先列“Codex 用量”，系统sparkles白色AI符号＋Alcove深灰底；完全移除本次Agent HUD图形及其随附许可/专用资源/打包机制，不是保留素材剥许可。内部Codex语义统一CodexUsage/codexUsage，泛化页壳AIUsage/aiUsage，不留codexMonitor命名、不凭空造未实现provider。保留其他有效第三方许可与历史证据。V0022已排现有邮箱，V0021只读研究之后串行，见docs/pi-tasks/v0022-ai-usage-native-icon-no-import.md；仍仅占位无账号服务/额度请求。

2026-10-25 用户要求新包启动查看：已核dist SHA256 4f6a517e...与独立V0020候选一致且签名通过；CUA退出旧实例并启动该包、打开真实通用设置，AX确认刘海屏/菜单栏不可点击标签及九个正确顺序入口（Codex 用量仍旧品牌方案，V0022尚排队，已提前明确告知用户）。此时Mac可交互，原锁屏阻碍已解除；只打开设置未改用户偏好/授权/媒体。V0022仍待交付不冒称AI版已启动。

2026-10-25 用户最新V0022同轮覆盖：菜单栏组顺序日历→下载监控→AI 用量→系统监控；关于上方加Valora应用名分组标题（原Alcove应用名标题样式），刘海屏组和通用不变。必须以docs/pi-tasks/v0022-supplement-sidebar-order-about-heading.md为准覆盖主体旧顺序/关于独立无标题方案。当前V0022主体邮箱pending不覆盖/不改哈希；补充已在本文件明确供pi接主体时同轮读取，若交付遗漏则空闲后单次投此补充，不重复主体。

2026-10-25 V0022主体交付初审：AI用量/系统图标/品牌资源许可移除已做，但最新菜单栏顺序和关于Valora标题遗漏，整体不接受。已在ready且无邮箱后单次投已有v0022-supplement-sidebar-order-about-heading.md限定补齐，不重复主体。记录docs/verification/independent-v0022/initial-review.md。V0021报告已到尚未独立接受，先核证据避免把尚未验证路径说成绝对不可实现，不授权真实权限/多播放器实现。

2026-10-25 V0022＋最终顺序/Valora标题独立源码、9设置回归、构建签名、项目外资源/渲染及真实九页点击子集接受，最新dist已依此前启动授权运行停AI页。实机另发现设备“需授权+开关on”，新增两项隔离回归失败，限定V0023授权初始状态/旧偏好吞开启意图修复已单次投现有pi；见docs/verification/independent-v0022/decision.md。V0021研究17份静态哈希匹配，独立事实子集接受，但绝对“无权限只有system”推论不接受；当前仅已证实system，per-client等仍待验证。下一步真实只读探针/新增权限实现需用户明确确认，不自动接多来源。

2026-10-25 V0023独立39项通过原失败已修，但首次normalize写launchAtLogin=false仍触发SettingsView全局LoginItem.set，隔离宿主在真实SM已enabled时可注销系统登录项，未满足“只改本软件配置”。整体未接受，限定V0023-R1系统写隔离已单次投pi；记录docs/verification/independent-v0023/decision.md。禁止真实注册/注销复现，须注入状态/动作spy验证；不回退已接受UI或原权限修复。

2026-10-25 V0023/R1自动/注入实际视图范围独立接受：41定向回归（含原两失败与新7项）/独立release构建签名/项目外设置渲染及资源检查通过。SettingsView无全局LoginItem系统写，程序性首次纠正/refresh只改本软件配置，显式关闭/取消按注入所有权流程。见docs/verification/independent-v0023-r1/decision.md。真实TCC/登录项批准/设备仍待实机，候选已打包但未本轮自动重启。当前已授权验收修复完成；下一步真实音乐来源只读探针需用户确认，提案docs/pi-tasks/proposed-v0024-per-client-read-probe.md未投递未执行，等待决定，不再派新模块。

2026-10-25 本轮验收修复已完成，仅待用户确认下一步真实媒体只读探针，已删除heartbeat automationId=valora，工具返回deleteStatus=deleted；不自动恢复或执行提案。

2026-10-25 用户要求验收：复核既有41项独立测试/构建记录后，用已验证独立产物重新打包项目dist并CUA重启。实际设备页AX确认需授权标志＋开关off，原初始状态问题在最新运行包已纠正；未点真实授权/媒体控制。记录docs/verification/independent-v0023-r1/runtime-acceptance.md，并更正独立decision误填pi产物hash，当前dist与独立build-check一致。仅现有修复验收，不授权V0024或恢复定时器。

2026-10-25 用户明确同意V0024真实媒体只读验证（回答“可以”）：允许一次有界隔离per-client查询，禁止播放控制/系统权限或默认来源修改/账号内容/元数据内容落盘；最多3样本10秒硬限，不制造网页播放场景。docs/pi-tasks/v0024-per-client-read-probe.md已单次投现有pi，覆盖旧仅静态限制但不授权生产实现/真实命令/新权限/恢复定时器。完成Codex独立核证据与最小方案。

2026-10-25 用户自行网页视频并播测试音乐正常并让Codex查看：CUA确认音乐面板和进度持续更新；一次有界system adapter只读当前bundle仍com.tencent.QQMusicMac，故此次网页未接走系统当前来源，现有链路已满足该场景。V0024独立CLI3次零clients/约2秒，只接受执行与局限证据，不认定无权限不可能或后台优先已实现。记录docs/verification/independent-v0024/decision.md。先保留成熟system current，不自动多来源改造/新增权限/重复探针；遇真实抢占再按具体场景处理，不恢复定时器。

2026-10-25 用户明确要求“验收pi，这个消息告诉pi”：已通过现有邮箱单次发送V0024验收与用户网页/QQ并播正常观察，见docs/pi-tasks/v0024-review-user-observation.md。仅通知并补报告，不是新开发，不重跑探针或扩来源；当前保留system current，实际抢占复现后再按具体场景处理。

2026-10-25 用户要求继续下一个任务，已单次派V0025一体菜单栏原生底座与可点击隔离预览（docs/pi-tasks/v0025-unified-menubar-foundation.md）：单入口/单面板，运行时顺序系统监控→AI用量→日历，显隐同步；不改变设置侧栏最新顺序，不新增设置条目，未接真实后端先用隔离预览验结构，普通启动保留原入口/菜单/品牌与全部已接受功能。不读账号/日程/真实监控，不加权限或依赖，不自动多来源改造/恢复定时器；交付Codex独立验收后才下一批日历/真实数据。

2026-10-25 用户反馈V0025偏离意图/左右键不像原版及刘海消失。初审不接受：入口仍仅V、缺三区同步。Codex未检测到Valora运行，dist被候选覆盖；已将独立V0023-R1运行包恢复并CUA启动，AX及截图确认刘海已显示，暂停空闲正常收起，未改源码或媒体/偏好。不武断归因崩溃。V0025-R1现单次派pi纠正可见三区/左击统一面板/右击既有快捷菜单，原刘海不受影响；候选只打临时目录，严禁覆盖用户dist或退出当前应用。见docs/pi-tasks/v0025-r1-user-intent-and-notch-preservation.md。

2026-10-25 用户明确要求“下载监控改为下载，然后日历先做出来”：V0026已排现有邮箱，先V0025-R1限定收尾再串行菜单栏日历。参考Calmon小月历（非快捷键大面板），基本日期/月历可用且不需授权，系统日程仅现有单开关+fullAccess才读，开发QA禁止真实个人日程/系统权限操作。侧栏菜单栏日历→下载→AI用量→系统监控，Valora下关于；正常运行只显示已完成模块真实内容，不放假监控数值、不影响刘海。候选只打临时目录不覆盖用户dist，见docs/pi-tasks/v0026-menubar-calendar-download-label.md。

2026-10-25 V0025-R1/V0026独立验收不接受：既有相关39项通过，新增日历生命周期五case全失败（stop后读取、查询叠加、跨月今天、gate撤销仍读、原生日期条落后一日），见docs/verification/independent-v0026/decision.md。V0026-R1已单次投pi限定功能/生命周期/真实容器尺寸与可读性收尾，保留用户dist和刘海。用户提出UI材质讨论：当前灰底不算完整Alcove/Calmon原生popover观感；建议日历结构参考Calmon、弹出层原生macOS材质，设置/刘海保留Alcove；尚不借功能返修全局重做UI。

2026-10-25 用户确认仅菜单栏及点击展开面板做原生macOS材质调整，内容布局参考Calmon；设置/刘海/音乐歌词设备及品牌等原样。补充docs/pi-tasks/v0026-supplement-native-menubar-material.md接续R1，先完成已发现功能边界再局部UI收尾，不覆盖用户dist或退出应用，不扩模块/重构/恢复定时器。

2026-10-25 用户最终确认直接迁入MistySky/Calmon日历和系统监控，独立菜单栏入口/独立弹窗，覆盖旧单入口一体面板和原生材质补充；删除被替换的专用旧日历/系统监控代码，完整复用Alcove风格日历授权单开关/权限流程。设置/刘海/音乐歌词设备品牌原样，ScreenStateMonitor非CPU监控不得误删。任务docs/pi-tasks/v0027-calmon-calendar-monitor-migration.md接续R1成果、保留五边界语义，不再投入旧统一UI；候选仅临时目录不覆盖dist，不恢复定时器。

2026-10-25 用户确认日历/监控独立左击弹窗，右击仅与刘海一致的禁用版本/设置/分隔线/退出；软件Outline-v7图标始终独立保留既有左右键及完整音乐管理菜单，不是全关闭fallback。刘海不变。最新任务 docs/pi-tasks/v0027-calmon-calendar-monitor-migration-routes.md。

2026-10-25 用户报告旧Calmon点击菜单后内存持续增长，要求迁入特别注意。必须独立验证面板反复开关/长开、暖机后RSS及physical footprint走势、对象/订阅/通知/任务/图标缓存有界和释放，不凭来源结论通过；保留必要菜单栏采样，隔离候选不影响用户dist。最新要求见docs/pi-tasks/v0027-supplement-popover-memory-regression.md。

2026-10-25 ## 用户最新授权：内部可优化，UI不动
用户确认：“如果觉得不合适的地方也可以优化修改，但是ui别动”。迁入不要求照搬来源缺陷；允许有证据、限本迁入范围的内部实现优化，尤其内存生命周期、缓存上限、采样调度/去重、异步取消、线程隔离和数据正确性。每项记录来源位置、问题、最小修复与验证。Calmon布局、字号、间距、图标、材质和可见交互保持原样，Valora设置/刘海/音乐歌词同样不动。不得借优化改UI、加功能、全局重构或拆包；若内部修复确实必须改变可见体验，先报告具体原因和最小方案，不擅改。 最新补充docs/pi-tasks/v0027-supplement-memory-internals-ui-fixed.md。

2026-10-25 V0027独立验收整体暂不接受：原263项/独立构建签名/源码哈希/原生模块视图通过，新增3项中日期入口隐藏恢复及授权Published旧状态两项失败，限定R1。454秒内存独立复跑监控3分钟稳定、60轮后对象释放；日历长开因另一QA焦点干扰不足，不冒称通过。记录docs/verification/independent-v0027/decision.md。UI不动、用户dist未替换，返修docs/pi-tasks/v0027-r1-status-recreation-calendar-grant.md。

2026-10-25 V0027-R1功能子集独立接受：267测试、原两失败/撤销边界、构建签名、生产音乐菜单与模块基础菜单/原生QA通过，UI未动。独立455秒内存监控37/37可见稳定、四对象释放；日历仅1/37可见，关闭原因未知不冒称长开通过。仅补docs/pi-tasks/v0027-r2-calendar-memory-evidence.md审计判定/日历有效长开证据，保留已接受修复，不改用户dist或真实权限。

2026-10-25 用户确认后续Codex用量UI：菜单栏5H/WEEK双行百分比沿系统监控；展开为纵向列表，5小时用量/已使用百分比及下一行浅色本地重置日期，周用量同样；重置卡显示可用次数，下面直接逐张列本地到期日期，不悬停二级弹窗、不执行重置。只这三类，不加会话/Token。后续顺序日历内存验收收尾→Codex用量→下载，暂不全局架构重构。下载候选用户指定TheDynamicPunk/Convoy；已只读确认SPM公开DownloadEngine library及独立引擎API，尚未引入/编译实测，不将浏览器桥接或外部视频工具视为自动获得。


## 2026-10-25 最新串行落地计划（用户已授权定时验收及落地）

按以下顺序执行，不做整体架构重构，不扩旧全量队列。每批先pi正式交付、Codex独立代码/针对性回归/构建签名/必要UI资源及生命周期验收；失败只限定返修，通过才下一批。

1. V0027-R2验收收尾：审计有效性与明确QA固定窗口日历视图内存，生产transient真实鼠标/物理双屏待实机，不能将固定展示冒称生产交互。保留已接受R1功能。
2. V0028 Codex用量：docs/pi-tasks/v0028-codex-usage.md；菜单栏5H/WEEK沿CPU/MEM双行，弹窗仅5小时/周已用百分比与下面浅色本地重置日期；重置卡可用数+下面直接逐张到期日期。Agent HUD取数思路、自己薄适配；仅account/rateLimits/read只读额度，不读auth/token/会话/email，不重置/登录/装hooks。真实额度有界验证为此功能授权范围，覆盖旧笼统禁止账号读取仅限这项最小额度字段，其他限制继续。
3. V0029下载引擎：固定TheDynamicPunk/Convoy commit/version，SPM只依赖DownloadEngine，自有DownloadService薄适配，先验证公开状态/真实segmentMap/暂停继续/持久化/删除语义及Swift6/macOS27编译；记录真实许可/来源不剥声明。测试仅本地临时HTTP服务器与开发自建文件，不请求外网大文件、不动个人下载目录内容。引擎/插件/NativeMessagingHost同源版本清单、升级兼容检查，SPM更新不冒称插件自动更新。
4. V0030菜单栏下载：独立圆环内下载箭头，已知量真进度/未知等待/暂停静止/空闲停动画；左击列表、超高纵向滚动、沿Convoy DownloadRowView/SegmentBar等成熟操作和材质，去掉分类/侧栏/独立Convoy大窗口。顶部不要加号；下载图标右键新增“新建下载…”入口，其他仍版本/设置/退出。默认macOS Downloads目录（开发用临时目录覆盖）；文件重名沿上游明确冲突处理，不自动覆盖。行内暂停/开始继续/失败重试/已完成Finder显示和打开等沿Convoy，列表稳定不随进度重排。任务右键删除及批量选择/键盘等已有操作按适合菜单栏容器的Convoy原语义迁入，不自己简化成危险直接删除。DeleteConfirmationSheet/DeletionPlan同一删除决策：默认只删记录保留完成文件，可显式勾选将完成文件移废纸篓；未完成取消并丢弃进度/临时分段，按原来源是否需确认判定；零数据或文件已不存在按来源trivial流程。开发只测试自己创建的临时文件/隔离Trash替身，绝不删真实用户文件或执行下载到用户目录。
5. V0031浏览器接入：复用/适配Convoy扩展+NativeMessagingHost/IPC，必须改Valora身份/可信host注册路径/协议，不把原Convoy插件直接指向Convoy当Valora集成。设置→下载放浏览器扩展安装引导、打开扩展页/目录、握手诊断与移除接入；状态未设置/已就绪/需要修复，未启动浏览器不假失败。Chrome/Edge等首次用户加载解压扩展，Firefox签名/更新来源先核上游可复用范围与身份限制。开发用隔离配置/测试浏览器及IPC fake握手，不自动安装/启用真实扩展、写真实浏览器host注册、读真实cookies/网页或接管真实下载。安装启用/敏感权限最终由用户在可检查候选上操作；无条件的浏览器端验证列待验，不伪造通过。版本升级同时管理引擎/插件/host兼容且不覆盖其他App扩展配置。

下载上述是本聊天用户需求确认后的执行范围；各V0029–V0031任务在前批通过后按实际接口证据细化，不预先并行投递。下载/AI变更只在所属薄适配与模块内，不借机拆全项目。用户要求旧日历/监控替代代码删除已执行；保留历史任务/验收/用户资源/基线，成熟功能与UI不动。

定时接续已通过内置heartbeat重新创建automationId=valora，ACTIVE，每15分钟，本聊天；忙碌/已有request或claimed不重复派工，不新pi，不变更会话01a1664f-f5e9-70bd-b053-21a027d5407a历史/模型。只关键完成失败需决定通知，全部本轮范围完成删除接续。候选始终临时目录，不替换用户dist、不退出当前软件，不安装发布或Git提交推送，不改归档。真实系统权限/登录项/媒体/设备/个人日程写操作限制继续。

2026-10-25 V0027-R2独立自动/固定展示内存范围接受：37定向测试/构建签名，日历固定QA窗口37/37可见187.4秒，footprint预热后约29.42–29.44MiB、1次fake事件读取，详见docs/verification/independent-v0027-r2/decision.md。生产transient/真实鼠标/多屏/TCC仍待实机，不冒充、不无限补测；允许串行V0028 Codex用量。heartbeat valora已ACTIVE每15分钟。

2026-10-26 V0028独立45定向/构建签名通过但整体未接受；新增3项失败：stop重启真实在途2、10次开窗变11请求、畸形权威map回落旧值。限定V0028-R1请求生命周期/新鲜缓存节流/严格解析及fake子进程测试，见docs/verification/independent-v0028/decision.md、docs/pi-tasks/v0028-r1-refresh-lifecycle-parser.md。UI不动，不重复真实quota读取，不推进下载直到接受。

2026-10-26 V0028-R1独立42定向/构建签名/原生注入30开关通过，原3失败修复；短序列request delta0、真实查询未重跑，记录docs/verification/independent-v0028-r1/decision.md。本批自动范围接受，串行V0029。源码核Convoy固定007a209...的shared初始化会触碰硬编码AppSupport/Convoy任务记录，下一批先依赖编译及隔离，不盲目运行单例、不静默fork或改全局HOME，不碰真实用户数据；见docs/pi-tasks/v0029-convoy-dependency-isolation.md。

2026-10-26 V0029独立36相关测试/构建签名/固定版本与链接审计通过，编译纯适配子集接受，实际引擎隔离未成立：shared/private init写死AppSupport/Convoy/standard defaults/temp，不能盲跑。docs/verification/independent-v0029/decision.md。已请求用户选择“仅增加存储/配置注入的本地兼容补丁（不GitHub fork/push）”或“暂缓”；未修改依赖checkout/真实数据。等待选择期间无可自动派的新实现，已删除heartbeat valora；若用户选择继续，按已授权15分钟接续恢复并串行最小隔离→Range临时测试→下载UI→浏览器，不重复请求旧定时授权、不扩架构/UI，不Git发布。

2026-10-26 用户已选择采用本地兼容补丁，覆盖前V0029等待/不应用补丁限制；授权项目内显式可审查的兼容SwiftPM包及最小存储/配置/所属manager注入，不改算法或UI、不GitHub fork/push、不改checkouts或全局HOME。派docs/pi-tasks/v0029-r1-local-compatibility-isolation.md，先独立根/suite/scratch与真实本地Range验证（仅自产临时文件），接受后下载UI再浏览器；15分钟接续按原授权恢复，其他媒体/权限/用户数据/安装/Git限制原样。

2026-10-26 V0029-R1独立23相关/真实Range与构建签名通过，但新增两个存储所有权回归失败：首次目录创建晚于锁获取导致双owner；无锁实例清理会误删owner分段。整体未接受，限定V0029-R2存储锁/无所有权动作及未完成重启恢复验证，见docs/verification/independent-v0029-r1/decision.md。候选仅临时包，dist未动，暂不派V0030。

2026-10-26 V0029-R2自动/本地Range范围独立接受：24定向通过、原两失败修复、未完成partial重启恢复完成字节一致、固定37源hash及patch重建一致、release构建/包签名通过，见docs/verification/independent-v0029-r2/decision.md。用户dist未动；进入V0030菜单栏下载列表，浏览器V0031之后单独派。系统Trash/真实鼠标/浏览器未冒称通过。

## 2026-10-26 用户最新测试分工（覆盖旧每轮全量要求）
pi开发/返修按实际修改范围跑定向测试：改动模块、必要相邻接口、原失败回归；通过后及时交付，不默认每次全量swift test，不对同版无新修改反复全量。只有新失败/共享底座变化等明确证据才扩大测试，报告说明选择与未覆盖范围。Codex独立验收负责集成回归；涉及跨模块、共享底座/依赖或阶段收尾时集中跑一次全量，单纯局部返修先复验原失败和受影响范围，不机械每轮全量。构建签名、原生UI/资源/内存等按本次变更所需执行，不把全量单测代替真实视图与功能验收。V0030在途保留成果，不中断已在运行的有效测试、不重复派主体；后续测试按此策略。

## 2026-10-26 用户最新：菜单栏模块独立开关
用户明确“下载，codex用量等信息那个也是加开关的，关闭菜单栏也不显示了”。下载、AI用量内Codex用量、系统监控及日历菜单栏展示各有持久化开关；关闭即移除对应status item并关闭弹窗，再开恢复，不影响软件Outline入口/刘海/其他模块。沿Alcove当前SettingsToggleRow样式，不重构布局。日历展示开关与既有EventKit授权开关区分：基本月历展示不依赖日程授权，不用授权冒充显隐。为保持现有体验，展示默认沿当前可见状态（首次默认开）；用户关闭持久化，重启不闪现或自行开启。Codex/监控关闭停止所属查询/采样，拒绝迟到更新；下载开关控制入口展示，不擅自暂停/取消后台已提交任务或删除记录/文件，再开继续可见。V0030同轮补充见docs/pi-tasks/v0030-supplement-module-visibility-switches.md；现有测试策略补充优先保持单邮箱，不覆盖request/重复主体，空闲且邮箱空后串行投本补充，独立验收前须收齐。

## 2026-10-26 用户纠正：模块开关为功能总开关，通用另有软件图标显示开关
覆盖此前“仅显隐，下载后台继续”的Codex误解。系统监控、AI用量、下载页移除“功能准备中”，各放实际SettingsToggleRow总开关；开启才启用对应功能，关闭时停止所属采样/查询/刷新/定时器/在途请求并拒绝迟到响应，移除入口/关闭弹窗，重启off不初始化后台。不影响其他模块/刘海。下载关闭暂停所有在途任务、保存记录/partial，不删除任务文件；再开恢复可查看状态，不自动重启已暂停网络任务，用户可手动继续。服务关闭需等待取消/保存收尾，快速开关不重叠实例或恢复旧请求。日历遵循功能关闭不后台读日程，基本日期与授权区分。
用户另明确通用加“是否显示图标”：加“显示菜单栏图标”独立控制Valora软件Outline-v7/V status item，首次默认沿当前显示开启，持久化。此开关仅软件图标显隐，不是应用退出/刘海/音乐总开关，不连带关闭其他菜单模块；隐藏后仍保留刘海右键设置等既有恢复入口，不删除既有完整音乐菜单，重新显示复用原路由且不重复status item。此前“Outline永远保留”仅被本显式开关覆盖，模块全部关闭时仍按软件图标开关决定显示。
当前已关闭定时器，不自动恢复。V0030主体未独立接受，最新补齐任务docs/pi-tasks/v0030-supplement-feature-switches-and-app-icon.md替代尚未投递的旧visibility补充，旧补充不要投。保持用户当前运行候选不退出不覆盖，完成另打新目录。pi仅定向测试，Codex独立验收。

2026-10-26 用户截图指出Calmon日历显示缺失：Valora固定关闭节日且provider返回空，漏迁原节假日来源/休班/去重，详情全源平铺出现重复且缺休息标签。限定补充docs/pi-tasks/v0030-supplement-calendar-calmon-parity.md已排现有邮箱，在功能开关任务之后串行修复，恢复来源成熟逻辑不改UI；只注入日历fixtures，不读真实个人日程/改权限。定时器关闭，不自动恢复。

## 2026-10-26 用户要求保留原日历宽度
只读核对Calmon固定72235116...的CalMon/App/UIStyle.swift：calendarPanelWidth=360pt，monitoringPanelWidth=400pt，二者并不相同。Valora相应常量目前同为360/400，必须保持；日历节日/角标/去重修复不能改宽度、缩放或网格布局。AI用量现360pt，下载现560pt（分段行更多信息），其他面板统一宽度尚未由用户确认，不借“参照Calmon”擅自把监控收窄360或下载压窄400。高度仍内容/屏幕约束滚动，pt不等同截图物理像素。此要求随当前日历修复验收核对，不重做主体、不恢复定时器。

2026-10-26 V0030/开关/日历补充独立验收整体暂不接受：日历原生fixture节日休班及360/400宽度、候选签名子集确认；新增localRange测试证明off后排队resume复活（downloading/activeCount1），另HolidayProvider eager真实store破坏fixture/关闭资源隔离，全量运行已中止非通过。限定V0030-R1 docs/pi-tasks/v0030-r1-off-action-barrier-calendar-isolation.md，保留UI仅修off屏障与惰性可注入日历传输/生命周期。记录independent-v0030/decision.md；不进入V0031、定时器关闭，用户运行包未动。

2026-10-26 V0030-R1独立原resume回归修复确认，集中334例全量1例3断言失败（旧日历fake普通provider未隔离节假日路径），另新增自动enqueue后off复活与日历hide后排队读取两例均失败。限定V0030-R2补全deferred任务生命周期/QA隔离，见independent-v0030-r1/decision.md。原UI/日历360pt监控400pt和映射保留，不重复全量直到定向修复完成，不进入V0031或恢复定时器。

2026-10-26 V0030-R2自动范围独立接受：30定向原失败全过、日志无真实store诊断、源码gate/懒注入/取消闭环、vendor patch重建37文件一致、独立release/签名、下载原生17图/60轮及日历3fixture/设置39图通过。见independent-v0030-r2/decision.md；不冒称本版全量或实机全部通过。未替换用户包，定时器关闭。用户正讨论宽度统一360或400，建议400但尚未确认；等最新选择，不擅改宽度/自动投V0031。

2026-10-26 用户明确确认统一400pt并要求交pi，覆盖旧日历360pt保留限制。派docs/pi-tasks/v0030-r3-unified-400pt-popovers.md：日历/系统监控/AI用量/下载主popover内容统一400pt，只调整宽度及必要排布，保留字体材质功能和下载原操作。日历网格随宽度等分、下载长名截断辅助换行不隐藏操作；实际原生几何验收，pi只局部定向不重复全量。V0030-R2已接受修复不回退，定时器关闭，不先开V0031；新候选仅临时目录不替换当前软件。

## 2026-10-26 用户明确禁止当前阶段压力/内存/反复开关测试
用户：“这个测试要求关闭，不准再测试了等后期软件搞完后优化，都测试功能就行”。立即覆盖旧60轮开关/3分钟长开/CPU-RSS-footprint/帧率稳定/循环状态截图等要求。当前只做本次改动必要功能用例和最小布局检查，不主动运行反复闪窗、批量打开关闭、长时间驻留、内存/资源压力/流畅度性能测试，留到软件完成后用户明确授权优化阶段。禁止直接运行混有60循环的--verify-downloads或同类批量闪窗QA来验单一宽度；需要其功能断言时仅提取不闪窗的逻辑用例，必要原生点击只做单次最小检查，不借“功能回归”重跑循环。不删除历史测试/证据，不将未跑压力项写为通过。若此类程序已在运行，只停止自己启动的测试进程，不退出用户正常Valora/pi，不损坏源码成果。功能测试、必要构建签名继续，pi定向，Codex同样遵守。当前无监测到此类Valora测试进程（仅搜索命令本身），定时器仍关闭。

2026-10-26 用户再次报告菜单栏仍反复开关；Codex确认pi在busy尚未消费禁测补充，直接终止了UI验证串行driver PID60757及测试子进程60854（SIGTERM，非程序缺陷），未停止pi或正常用户App。禁止对这次143/中止作自动重试，禁止改跑--verify-calendar-parity/--verify-settings/--verify-menu-modules/--verify-downloads整组或其他反复前台闪窗脚本；用户要求优先，交付已有400pt源码/构建/功能结果即可，原生批量自动化测试本轮跳过，不再做任何菜单栏连续点击开关。禁测补充request已在单邮箱等待，收到后只确认遵守，不另起UI验证。

2026-10-26 V0030-R3本轮400pt布局/功能范围接受：独立9项无界面用例通过、共享400与日历368网格源码/已生成原生证据复核、候选385ae062...签名通过；无重复弹窗/压力/全量测试。见independent-v0030-r3/decision.md。用户截图Codex官方剩余79/97与Valora已用21/3互补，字段usedPercent正确，标题口径歧义待确认文案修改，不改计算或重读账户。定时器关闭，用户运行包未动。

2026-10-26 用户最新确认Codex与官方一致显示剩余（79/97而非已用21/3），菜单栏与面板/accessibility统一派生100-usedPercent；要求启动开启即后台更新、点击显示缓存。现代码已start/180s刷新但每次request清.loading，限定V0030-R4核Hub固定源并保留最后成功快照/过期标识/取消限流，fake传输验证不重查真实账户。任务docs/pi-tasks/v0030-r4-remaining-quota-background-cache.md已投。下载后续仅Google Chrome，必须Valora专属扩展ID/host/协议/版本和设置安装引导；docs/pi-tasks/v0031-chrome-extension-native-bridge.md准备，R4验收后串行投，旧Firefox/多浏览器不做。禁所有循环闪窗/压力与真实Chrome配置安装，定时器关闭。

2026-10-26 用户确认系统监控/Codex共用菜单栏点击入口和一体展开面板，要求验收派活。R4独立19无界面/签名子集通过，新增cachedFailure点击绕cooldown失败，见independent-v0030-r4/decision.md。V0030-R5同轮补冷却与合并：CPU/MEM+5H/WEEK并排，上监控下Codex、400pt单滚动；各自总开关决定所属内容/后台，双方off入口消失。软件V/日历/下载不动。任务docs/pi-tasks/v0030-r5-combined-monitor-codex-entry.md。禁止全部批量闪窗/循环/压力，仅无界面功能和构建签名；定时器关闭，Chrome-only V0031后移等本批接受。

2026-10-26 V0030-R5独立20功能回归/缓存冷却/签名子集通过，但新增初始off再开启Codex回归失败：provider已有79/97，共享菜单栏仍--；初始off未observe且enable时未重连，监控同类路径。限定R5-R1恢复启用观察与旧session隔离，任务docs/pi-tasks/v0030-r5-r1-enable-observation-reconnect.md，见independent-v0030-r5/decision.md。合并400pt UI不重做，不点击弹窗/循环压力，不进入Chrome V0031或恢复定时器。

2026-10-26 V0030-R5-R1自动功能范围独立接受：23定向原启用观察失败/后续快照/off-on/缓存冷却/剩余后台获取均通过，epoch与重连源码闭环，候选3101792c...签名通过。见independent-v0030-r5-r1/decision.md；未弹出面板/点击菜单/循环压力/全量，实机视觉仍待用户。现按已确认顺序正式投V0031 Chrome-only扩展/Valora匹配host/IPC及设置安装引导，开发只隔离browserroot/fake协议，真实安装由用户最终操作；定时器关闭，不改当前用户App。

2026-10-26 V0031独立12Swift功能/包签名子集通过，整体未接受：Node vm三个Chrome交接用例失败（成功漏suggest、不明确accepted仍取消、取消失败仍erase）；隔离host错误/缺失version仍ok两个探针失败；popup打开App按钮永不显示。限定V0031-R1修原功能，见independent-v0031/decision.md及docs/pi-tasks/v0031-r1-chrome-handoff-protocol-completion.md。仅fake Chrome/隔离TMPDIR无界面验证，不安装真实扩展/写真实浏览器注册，不弹窗循环/压力；当前用户App不动，定时器关闭。

2026-10-26 用户要求设置保持Alcove简洁：“显示菜单栏图标”仅文字+开关，无左图标/额外说明；下载设置去长段解释，Chrome安装/桥接以简洁状态行和明确动作呈现，步骤由点击安装后展开，侧栏标题原图标保留。另反馈下载popover透明度与Calmon不一致、监控首次展开滚动条闪现，限定V0032最小材质/初始布局整理，400pt和功能不变；任务docs/pi-tasks/v0032-alcove-settings-popover-polish.md。严禁任何自动批量弹窗/截图/循环压力，用户单次看最终视觉，未复现瞬态不冒称通过。V0031-R1已报告待独立协议验收，V0032不改其JS/协议peer业务；定时器关闭。

2026-10-26 Codex在pi执行V0032时仅只读复核V0031-R1：8 JS handoff+5 popup+4隔离host版本/origin共17情景通过及候选签名通过，记录independent-v0031-r1/decision.md；无浏览器真实操作或弹窗。为避免并行UI生产编译，本轮未重跑Swift，待V0032最终同包补无界面相关验证，真实Chrome加载/稳定路径安装仍待用户。
