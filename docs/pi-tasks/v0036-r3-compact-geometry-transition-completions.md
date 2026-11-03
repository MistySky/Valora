# V0036-R3：修真实紧凑几何收起链，不能只增加阶段名

R2独立验收不通过。先读 `docs/verification/independent-v0036-r2/decision.md` 和当前新增两独立回归（修前已实际失败2项4断言）。本轮Codex只改测试，生产仍是R2，不覆盖/删除有效失败断言。

## 核心失败

1. 真实生产collapse对已经collapsed的播放器同步completion，compact音乐侧翼却仍展开。R2.phase locking在普通紧凑场景同调用栈直接locked；FakeCollapse测试隐藏了这个真实捷径。必须覆盖普通compact音乐（最常见），不是只处理expanded播放器。
2. .restoring立即showsMusicActivity=true且visibleSize仍有+74pt音乐翼，没有开锁后先收回基础刘海再展开音乐的几何过程。当前0.12秒只是音乐恢复后的settle，不能当“收起阶段”。
3. 旧顶边test测的是coordinator.panel（锁屏音乐卡）minY，与顶部刘海问题无关；必须更正不充分证明，测生产Notch visibleSize/contour、顶锚和相关window意图。

## 要实现的结果（按用户实际原版观察）

锁：当前compact/expanded/lyrics/output/peek → 完成普通内容和侧翼收起到基础刘海 → 锁状态展开。
解：开锁glyph → 锁侧翼收回基础刘海 → 当前最新音乐重新展开。
每段必须有真实影响Notch呈现几何/内容和拥有权的状态，不能只是enum名、等一个固定时间再交叉淡化。复用原版/复刻已有呈现结构和完成回调；不要改普通播放器的collapse所有用户场景来冒充解决锁compact，局部协调必要阶段即可。不要求未知原版精确时长凭空猜；先对照source/反编译参数，未知标注。

保持真实session锁定事实与呈现阶段分开：锁定后不能因允许旧内容收起而重新接受音乐/hover/seek交互；解锁恢复可交互的时机有明确门控。基础几何阶段必须抑制旧connectionToast、歌词/QuickPeek、output与hover对宽高/圆角的意外影响，不能把真实媒体状态清空/冻结来伪造收起。收起期间媒体继续更新，展开恢复最新数据。

按生产几何链路验证，不以FakeCollapse控制一个production实际立即完成的回调作为唯一证明。保留fake原生windows/Space/events/sound，允许真实production presenter纯状态接线，补可控completion seam只隔离动画提交，不替换掉被验证的geometry/branch决策。各阶段边界断言neutral尺寸、内容门控、阶段推进、旧completion不会复活。Reduce Motion也须完成语义顺序，允许最小淡化但不丢收尾。快速锁解/期间切屏/总off/sleep/stop和同阶段重复通知不得卡在locking或恢复旧音乐。

## 附带文档/材质

修正source manifest两个错误lock-screen-music/100131c1c.c、100206af0.c空hash记录，真实函数在lock-appearance-0.6.5，不把无文件当证据。
材质R2改动保留待对照，不无依据继续换颜色。根LockMusicView仍environment(.colorScheme,.dark)，须核源完整父容器appearance链，不能仅因局部函数无darkAqua就宣称底色根因已证实。原版同壁纸动态证据不足如实待验，不循环真实锁屏取图。

## 约束/交付

原版源码/复刻已有实现优先，用户把过渡动画作为核心；不能功能能用就通过。保留R1 lifecycle/epoch/fake和Codex解锁music detach修复，既有锁屏UI/声音/设置五条及功能排除不改。不改日历监控/耳机歌词/品牌，不恢复下载Codex或定时器，不全局重构。
只定向无界面fake测试（含新增失败原回归及相邻presentation/lock状态），禁真实NSPanel/Space/锁通知/锁解睡眠/媒体声音设备权限系统写、所有--verify/批量截图/循环闪窗/压力，不Git提交推送/改归档/个人数据/安装发布。
当前运行 `/private/tmp/valora-independent-v0036-r1-candidate/Valora.app`不退出不覆盖；候选 `/private/tmp/valora-v0036-r3-compact-transitions-candidate`一次必要release签名，不自动运行。报告 `docs/reports/v0036-r3-compact-geometry-transitions.md`，给实际阶段-几何-门控-completion对照和原版证据/未知，不把fake当实机帧一致。正式交付后停等Codex独立验收。
