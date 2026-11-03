# V0039 真实锁屏独立顶部承载与锁解音乐连续交接

## 用户授权与现状
用户要求落实：隔离普通桌面与锁屏窗口；补解锁动画，改善锁定→解锁→播放间跳变/停顿。最新明确“交给pi，写好文档的话”，本任务由既有pi执行，Codex独立验收。不恢复设备/下载等旧队列，不另开会话。先完整读AGENTS.md最新覆盖、docs/CONTINUATION-PLAN.md及本任务，严格保留用户禁测范围。

桌面模拟锁解已获用户实测认可，其动画/位置是可用基线，不重做UI。真实锁屏下浮仍未修。当前用户运行/private/tmp/valora-lock-capture-v2-candidate/Valora.app（binary01ec7979...），不得退出/覆盖/重签。

## 已有真实证据（先读，不再只猜）
- docs/verification/direct-lock-capture-v2/live-result/decision.md、own-window-diagnostic.jsonl、transformed-windows.json。
- 同window2442：AppKit frame[552,797,624,320]、host624x320、contentTopScreen1117持续正确；Quartz解锁阶段却580x298/X574/Y40，随后恢复624x320/X552/Y0；第二轮586x301/X571/Y34重复。
- 锁中windowSpaces[1,145]，桌面[1]；保留两种成员是事实，但不能把其等同唯一根因已证明。证据证明所采解锁的窗口系统呈现缩放/下移，不是本地glyph动画纵移。锁定瞬间未恰好采中Quartz异常，不能冒称全帧数据。
- 用户视频项目根目录3a4155c3a84637b2c3f7088996bd39dd.mp4，笔记docs/research/user-lock-video-3a4155c3.md；可离线抽帧只看顶部，不读/拷贝桌面工作内容。用户确认原版Alcove对照见docs/research/original-lock-unlock-user-video.md。
- R8直接替换迁移API+严格查询gate曾让用户真实锁屏完全消失，已回退！不得照搬R8、改变查询unknown就把全部UI隐藏。历史docs/reports/v0036-r8-direct-space-migration.md仅供失败分析。

## 本批实现目标：只变真实锁屏承载/交接，不改已正常动画
1. 真实锁屏采用独立、固定屏幕顶部的lock notch overlay，与普通桌面primary隔离。复用现有NotchView、LockIndicatorState、geometry/动画，绝非另设计独立下方黑条；基础尺寸仍来自实体hardware geometry，展开为原两翼。模拟预览仍走普通primary，不参与真实Space。
2. 独立overlay的生命周期/Space归属必须避免继续带着普通桌面成员参与缩放。参考外部已核源码DynamicNotch suspendPrimaryWindowForLock/LockScreenLiveActivityWindowManager/SkyLightOperator及BoringNotch→SkyLightWindow固定版本；源码版本和路径见docs/research/lock-screen-external-source-comparison.md。外部临时文件若已丢失可重新只读拉固定revision，不执行/安装/加入依赖。不能只新建一个同样双归属窗口就称隔离完成，也不能仅调level/frame/猜偏移或换Space函数而不处理窗口所有权。
3. 尽量小改，引入可注入overlay/factory与承载切换适配器，复用现有Space与window底座。明确primary、lock overlay、底部音乐卡、设备卡各自所有者/挂载/退出顺序。仅自己的窗口；缺符号/迁移失败/query unknown需有明确可诊断降级，禁止重复R8无声全消失。新overlay准备成功/具备可呈现条件后才能隐藏primary；失败保持已知可显示回退并标记fallback，不能假称隔离成功。native API的ABI/失败处理需依固定源码及可验证证据，不凭名称猜语义；不得改其他App/系统窗口、全局Space或安全设置。
4. 锁屏及解锁过程中不对窗口origin/scale做入场动画，固定使用screen.frame.maxY，不用visibleFrame或经验y补偿。host.frame显式与canvas一致，safeArea处理沿已确认顶锚。系统activeSpace/screen/wake事件驱动重新定位，不增加常驻orderFront轮询。
5. 活动屏screen变化/关闭/睡眠/stop/总开关off都清理正确；仅活动屏动态锁态，原普通多屏策略保持，物理多屏未实测如实待验。不要一开设置或启动普通App就显示锁overlay。非刘海模拟形态沿原geometry，不改日历监控等功能。

## 锁/解/播放连续动画（用户明确要求）
- 有音乐：先收起完整播放器/紧凑音乐两翼→基础刘海→展开锁glyph；无音乐基础直接展开锁。
- 解锁：保持当前锁位置/展开宽度，同一glyph原地开锁（锁环运动或系统fallback），不能先消失再出现独立开锁符号。开锁完成/展示后收基础刘海；真实几何收起completion后才恢复最新音乐并用原compact activity动画展开；无音乐停基础。
- overlay与primary只能在相同neutral几何/同屏顶锚处交棒，不能让音乐在仍受系统变换的窗口里过早恢复，也不能两份可见内容叠加。保留open glyph直到对应阶段完成，不能为减少停顿直接跳过动作。
- 真实锁/解/睡眠事实与动画呈现阶段区分，不把延后动画的sessionLocked充当系统真锁事实。必要时增加真实transition输入但不全局重构。
- 既有withAnimation.logical completion、epoch/generation、快速反转/重锁/旧回调拒绝保留；优先移除重复调度/无效root重建/早恢复造成的跳变。现有.8开锁展示可沿用；若调整需证据/明确原因，不为“流畅”任意砍时长或加delay掩盖系统问题。不做CPU/帧率/内存压力测试，不宣称fake动画流畅实机通过。
- V0038-R1已交的恢复音乐withAnimation修复保留，加锁已认可部分不动。真实底部Glass/耳机功能与声音开关保持，不扩大重做材质。

## 诊断必须支持下一轮一次实机
保留Codexcapture-v2的phase/kind分预算、限流、rawlock/unlock事件、自己的Quartz bounds查询。给primary与overlay都记录role/windowNumber/frame/Quartz bounds/Space归属/activeScreen及handoff准备、提交、fallback原因；phase采用正确真实/预览来源，不能混到同一无角色记录。默认关闭，候选先配LSEnvironment指向新唯一路径/private/tmp/valora-v0039-lock-handoff.jsonl，打包后重签核验。禁止普通状态耗尽锁/解/最终归位额度，新增role后需复核整体120硬上限和各阶段关键事件保留；用现有实测日志重放，不拿用户反复试作预算测试。不得截屏或读取其他App窗口/媒体标题/个人日程账号。

## 必要定向验证与交付
只无UI fake：primary/overlay互斥可见及正确挂载身份；overlay失败不隐藏primary；开锁期宽度不变→neutral→音乐，真实completion前不恢复；无音乐；快速锁解/旧完成；sleep/wake/stop/masteroff；换屏/旧window解绑；已正常preview无Space/音效副作用。native所属修复应有注入回调/错误路径验证，不只枚举断言，不创建真实NSPanel/Space、不发真实锁通知、不真实声音/媒体设备/权限操作。
严禁全量、--verify-*、批量点击/截图、循环闪窗/CPU内存流畅度压力。只定向功能与必要一次Release/签名、资源检查。候选/private/tmp/valora-v0039-isolated-lock-candidate，不覆盖当前包/dist，不自动启动/退出用户App、不改偏好/授权/系统设置、不改只读归档、不Git提交推送或恢复定时器。
报告docs/reports/v0039-isolated-lock-notch-handoff.md：真实证据→代码差异→窗口/Space所有权与失败降级→动画交接时序→定向测试→候选hash/签名/诊断路径→必须用户实测边界。交付后停止待Codex独立验收，不能仅凭fake称系统下浮/流畅度已修好。
