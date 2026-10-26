# V0028：Codex用量三项最小接入

前置：V0027-R2自动/固定展示内存范围由Codex独立接受后才投递。用户已明确排计划落地，优先Codex再下载，暂不整体架构重构或拆包。只在自己的服务/模型内建立必要边界，不改成熟功能UI。

## 确认UI和行为
- 设置“AI 用量”内仅Codex用量；菜单栏独立状态项用系统监控CPU/MEM同样的固定宽双行，标签5H/WEEK，显示已使用百分比。点击独立原生popover，右键复用模块基础菜单（禁用版本/设置/分隔/退出），软件Outline-v7音乐菜单不变。
- 展开为纵向列表：标题Codex用量；第一项“5小时用量”左、已用百分比右，下一行浅色小字本地日期时间+重置；第二项周用量同样；第三项重置卡/可用次数，下面直接逐张列重置1/2…及本地到期日期。无圆环卡片、不悬停二级弹窗、不执行任何重置；仅这三类，不加会话/Token/成本/模型榜。
- 材质/字号/间距/分隔线沿Calmon日历监控风格。保留Alcove其他设置/刘海/音乐歌词/设备/品牌原样，不加账号登录选择页或无用设置。源数据缺失用未提供/暂不可用，不能假零。

## 获取与适配边界
- 参考 https://github.com/jazzenchen/agent-hud-native-open 固定commit的CodexAppServerClient/CodexLocator/CodexRateLimits/ResetCreditsDetails，核官方app-server account/rateLimits/read文档/本机协议，记录来源；按需要最小复用代码及有效许可，不引入整套HUD/图标/UI/数据库/会话监听/hooks。
- 自己的CodexUsageProvider/快照/调度适配，本机安装的可信Codex引擎以app-server stdio初始化后仅account/rateLimits/read。用户已授权该功能落地，允许只读额度验证；禁止读取auth.json/访问令牌/refresh token、rollout会话/对话/账户email等无关数据，不使用account/read，不改登录/权限/hooks/模型或当前pi会话，不发模型请求/重置额度。不得把本聊天可用工具当产品内接口。
- 同次返回统一更新5H/周/重置卡。rateLimitsByLimitId若存在含空字典以其为准，优先全局codex桶，按windowDurationMins认5小时/周，不把其他模型桶混入；旧rateLimits仅兼容缺字典。支持字段缺失/0/过期/多桶/不合法百分比，不能伪造数据。
- 重置卡availableCount权威，credits可缺或少于总数；按真实expiresAt排序，单张无有效期/部分卡未提供需如实说明，不能把到期时间写成补充时间，不执行使用卡操作。数量或展示很多时滚动，不无限撑高popover。
- 先静态接口与fixture验证，再最多一次有界真实只读额度核对；不持久化原始RPC/账户标识，日志只字段存在与成功失败、耗时等脱敏摘要。失败/缺引擎/未登录/离线/旧协议明确状态，不能显示旧缓存为实时成功。任何需要新授权/登录写操作停止该真实动作，其他独立工作继续并报告。
- 全局同类请求最多1在途，超时硬限/取消/输出缓冲有界/进程退出清理；每分钟至数分钟的有限刷新并合并打开刷新，不1秒轮询网络。进程/观察者不随每次开popover叠加；暂停/睡眠/关闭模块/退出释放，UI局部更新，失败退避，旧响应不覆盖新会话快照。额度缓存小且有界，不接持续历史库。

## 验证和交付
注入传输/时钟/引擎locator/额度fixture测试，多桶/缺失/错误/超时/取消/迟到/状态项宽度/连续开关内存与子进程计数。真实RPC只读验证与fake界面明确区分；固化无副作用命令allowlist，测试证明无thread/turn/account修改/重置方法。复核音乐/日历监控/权限必要回归，release构建签名及原生状态项/popover/资源。候选仅/private/tmp/valora-v0028-candidate，不覆盖dist或退出用户Valora。禁止真实媒体/设备/个人日程/浏览器安装/系统权限写/Git提交推送/改归档/新pi或模型历史。报告docs/reports/v0028.md，证据docs/verification/v0028，完成停止Codex独立验收再下一批。
