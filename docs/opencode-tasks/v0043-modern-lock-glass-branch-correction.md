# V0043 紧急纠正V0042取证遗漏：macOS26+新玻璃分支

用户指出复刻品也乳白/不正确，并提醒macOS26新玻璃。本聊天Codex重新读完整反编译，找到自己上一批指令的错误：只读到了OS<26分支frosted=true，漏掉外层else→100187f28。V0042已完成无需重跑，它现在是被真实体验否决的材质路线；不要再以“只能接受近似或自绘壁纸”向用户二选一，尚未穷尽正确原生路径。继续现有会话，不改模型。

先读docs/verification/lock-glass-supervision-2026-11-03/correction-modern-branch.md并逐行核原档：
- /Users/wangqing/code/alcove-revival-archive/docs/alcove-1.7.9-detail-audit/evidence/ghidra/100186a7c.c:134–137及572–595，证明旧HUD参数443–452在OS<26！OS26+调用FUN_100187f28(width345,corner30)。
- reverse-engineering/lock-screen-music/100187f28.c:87–95枚举+OS27；1031–1048 wallpaperNearlyWhite→variant2/5，+0x38=0x200，+0x39为2且&1==0，工厂进入NSGlassEffectView；1055起背景light及1078起前景按壁纸条件。请完整追踪glass/clear/frosted enum映射，别截另一个frosted分支下结论。
- reverse-engineering/lock-appearance-0.6.5/100131c1c.c以及对应ghidra完整工厂：KVC variant名/2或5值如何作用到真实NSGlassEffectView；原版调用及反编译版本注明。私有variant不可未核就猜成public style枚举。
- 苹果contentView官方契约：https://developer.apple.com/documentation/appkit/nsglasseffectview/contentview；任意addSubview不保证相对glass的z序，必须使用正确contentView承载同一音乐前景。SwiftUI玻璃正确加在最终内容外，不放不受约束的壁纸ZStack。

## 工作顺序
1. 先查出实际glass样式对应分支、variant与appearance构造，形成短证据表（文件行/条件/unknown）。纠正V0041/V0042报告“所有锁屏都走HUD”及“原版只能私有近似”的无依据绝对说法，历史记录保留带更正。
2. 基于证据做最小原生玻璃候选，优先macOS27公开原生API；如精确效果依赖未映射私有variant，明确具体缺口与可评估选择，不盲填枚举、不直接KVC未知key/值造成crash、不自绘壁纸。不要先把“拿不到背景”“只能自绘”当成结论。若已有公开实现失败先核容器/窗口透明/appearance/读取到背景的前提，而不是叠黑白层。
3. 保持卡片总宽345、panel385透明边距及音量展开，卡片背景不贪婪撑尺寸；锁屏顶部独占Space/原地开锁→neutral→音乐一律不改。固定原生玻璃，无新设置，不改变V0040总开关、耳机/源/歌词/日历。background亮/前景白字环境分离按真实分支处理，避免整树强制dark把玻璃染黑或整树light白底。
4. 若证据仍不足，交阶段报告明确待证，停止无限调参数/反复要求用户锁屏，不能假称完成。桌面预览只可读布局，不能代表登录界面合成。

只本批必要真fake44定向+构建签名；禁止真实NSWindow/Space/锁通知/实际锁屏、UI循环/批量截图/性能压力，不运行MultiDisplay测试类、--verify或自动预览。不读用户壁纸/个人日程或其它账号数据，不控制真实媒体/设备/权限。归档只读，不改当前运行版（用户可能运行归档），不自动退出/启动/替换；候选/private/tmp/valora-v0043-modern-lock-glass-candidate，报告docs/reports/v0043-modern-lock-glass-branch-correction.md，交付后等Codex独立验收。无Git提交推送、定时器关闭。
