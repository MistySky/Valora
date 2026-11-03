# 锁屏音乐材质：Codex对OpenCode的限定修正依据

2026-11-03。读取现有OpenCode session ses_e60ad9e4bffekz1hsfhtNOnPtJ，最新idle3360。用户反复反馈材质/弹出异常、乳白色及尺寸增大，最终要求回到原样；当前聊天再次明确让Codex指挥OpenCode，参考原版反编译及成熟复刻玻璃分支，透明方案不追。

## 一手证据链（归档只读）

- reverse-engineering/lock-screen-music/100186a7c.c:443–452，以及docs/alcove-1.7.9-detail-audit/evidence/ghidra/100186a7c.c同片段：调用参数material=0xd、blending=0、state使用默认active、+0x38处0x101（后字节对应frosted=true）、corner28。不能只看到工厂可创建NSGlassEffectView就断言本锁屏分支一定用它。
- docs/alcove-1.7.9-detail-audit/evidence/ghidra/100131c1c.c：OS>=26并且bVar4(+0x39)&1==0才进入NSGlassEffectView；否则NSVisualEffectView setMaterial/setBlendingMode/setState/setEmphasized。后者返回外层NSView，连续圆角/裁切在外层，VisualEffect子视图四边约束。
- reverse-engineering/lock-appearance-0.6.5/依据与边界.txt早已明确以上调用链，不可笼统称macOS26必用Glass；也明确复刻玻璃视觉尚非1:1。
- Sources/AlcoveRevival/LockFrostedBackground.swift：hudWindow/behindWindow/active/emphasized，darkAqua，continuous28。
- Sources/AlcoveRevival/LockMusicCoordinator.swift:54–85：345pt外卡，内18/top16/bottom14，white15%@0.5细边，根dark环境；用户认为该玻璃路线可用。darkAqua/细边属于成熟复刻的体验底稿，原版证据尚未完整证明，不能写成原版精确参数。

## 当前源码差异与误判

- Valora当前LockFrostedBackground缺复刻darkAqua，圆角直接裁NSVisualEffectView而非原版工厂外层NSView。
- 当前LockMusicCard缺复刻细描边，根dark环境被移除。内容colorScheme设置在background之前，不等价于明确给AppKit背景appearance指定darkAqua。
- V0041报告把通用工厂的可选Glass分支，当成了锁屏实际分支；又根据不同角度/曝光照片的亮度比例定黑白叠层，不能证明真实材质；壁纸ZStack贪婪尺寸曾撑大345→385，用户否决。这些失败实验不可继续累计叠加。
- 原版/当前progress裁图已实际查看，但裁图/照片不是同壁纸同曝光的最终系统材质测量；现有0.69亮度比例不作为硬指标。

## 本次指挥范围

先按成熟复刻玻璃路径做最小对齐，同时依据反编译保持明确容器和约束，限定锁屏音乐背景/边界/固定尺寸。保留现有耳机行、音乐源/权限/歌词、V0040设置及用户确认的滑入等；不改普通刘海播放器或已修好的独占Space/锁解链。透明样式、壁纸抓取、LiquidGlass实验不做。桌面预览只核几何，不能等同真实锁屏材质。交付新候选不自动替换用户运行版。
