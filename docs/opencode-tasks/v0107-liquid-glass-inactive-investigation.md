# V0107：真实 Liquid Glass，避免重做失败版本

用户本轮要求做一版 Liquid Glass 锁屏卡片，认为现版太暗；最新强调「其实我最想要的是 Liquid Glass，但是之前实验了很多版本了，不行」。目标不是浅色磨砂。正确项目仅 /Users/wangqing/code/Valora。归档 alcove-revival-archive 只读，Codex 此前误改已撤回，那个候选不是交付。

继续指定现有会话 ses_e5f5da1c5ffesaPdioiEijQ5HM，遵循 AGENTS.md。只做本批，不改模型/会话、不恢复旧队列、不安装或启动生产服务、不控制媒体、不锁屏、不提交推送。

先核对已有 V0043、V0050、V0055、V0056 及 docs/research/liquid-glass-inactive-window-2026-11-04.md、docs/verification/glass-window-level-experiment/。这些材料中有互相矛盾及证据不足的绝对结论，不能直接照抄为系统限制。当前 LockGlassSurface 是 regular + darkAqua + 私有 variant5；不要仅换 clear/light 后声称解决。

研究遗漏路径：/Users/wangqing/code/tmp/alcove-rea-20261021-v2/exports/Alcove-arm64/swift-types-fields.txt:121 起 ClearGlassLayerView / ClearGlassEffectView，包含 samplesWindowServer、backdrop、glassBackground、glassForeground、keyFill、内外边框。对应 functions/10007 的反编译与汇编，追踪锁屏现代分支（100187f28）是否调用，和 NSGlassEffectView 工厂区分。来源本机只读，不能假设看到类名就证明适用于锁屏。

先以隔离 debug 预览验证有依据的方案：同背景同卡片在非 key 状态下保留背景轮廓、玻璃边缘折射；检查 SwiftUI appearsActive=true 是否在此前试过及能否实际影响合成。可在已知单一预览进行一次有焦点/失焦对照，禁止批量闪窗/压力测试、不碰用户真实锁屏焦点。cacheDisplay 不包含 WindowServer 合成，不算视觉证据。

有可验证改善才最小接入产品，不改几何/位置/动画/歌词/音量/生命周期。如果仍失败，保留生产源码并明确给出这次新增证据与未解决项，不再打一个同样失败的正式包。若可交付，按自动构建号规范只打包一次到新 /private/tmp 目录、签名核验，报告实际验证与限制。Codex 随后独立验收。
