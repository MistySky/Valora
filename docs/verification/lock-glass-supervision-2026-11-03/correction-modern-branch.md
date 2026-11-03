# 重要纠正：旧分支不可覆盖macOS26+实际调用

2026-11-03 用户明确提出macOS26新玻璃。Codex继续完整追踪后发现自己前一轮V0042依据遗漏外围OS条件，必须纠正，不能继续以该任务作为最终材质结论。

归档只读反编译：
- docs/alcove-1.7.9-detail-audit/evidence/ghidra/100186a7c.c:134–137，OS>=26检查；frosted=true参数443–452位于 if(OS<26) 内！此前截取参数遗漏外层分支。
- 同文件572–595 else(OS>=26)调用FUN_100187f28(width345,corner30)。
- reverse-engineering/lock-screen-music/100187f28.c:87–95读取样式枚举，另有OS>=27分支；并非全部模式同一材质。
- 该函数1031–1048：_isWallpaperNearlyWhite选择variant2或5，material13、blending0、state默认active，variant已指定，+0x38=0x200。因此+0x39 frosted字节为2，工厂用&1判断为false，不应当作frosted=true。1055–1065 background设light，1078起又按壁纸选前景明暗。
- 工厂100131c1c只在OS26+且frosted&1==0进入NSGlassEffectView，以KVC设置variant、cornerRadius。原版使用新玻璃的分支是真实存在的，不是只有工厂能力或臆测。

纠正：先前“锁屏音乐卡不是LiquidGlass”的概括错误，复刻HUD也非正确材质基线。需要映射样式枚举glass/clear/frosted及真实偏好到100187f28各分支，并核variant2/5的含义；不得把私有variant2/5直接等同public.regular/.clear，亦不能断言public无法实现。按苹果官方NSGlassEffectView.contentView契约宿主内容，不能用不保证层级的任意兄弟视图。

官方参考：https://developer.apple.com/documentation/appkit/nsglasseffectview/contentview；https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)。新玻璃与当前NSVisualEffectHUD不是同一实现；乳白色现象尚需正确分支/外观/容器闭环验证，不再凭照片亮度比例调白纱或私有variant猜数。
