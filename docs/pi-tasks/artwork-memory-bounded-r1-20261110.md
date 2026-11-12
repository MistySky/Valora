# build58封面内存验收返修：EXIF小图与真实身份碰撞

Codex确认build58签名/hash/唯一进程20124正确，但独立新增2项无窗口回归都失败，不能接受为不影响体验。日志 `/private/tmp/valora-build58-artwork-independent-20261110.log`；代码 `Tests/ValoraTests/IndependentArtworkPreparationTests.swift`，不要放宽/删断言。

## 1. 小封面EXIF方向被忽略

120×60 TIFF，已断言源metadata orientation=6。ArtworkImage.prepare走<=256分支的CGImageSourceCreateImageAtIndex，输出120×60；正确显示应60×120。当前大图方向测试不能覆盖此分支。

决定：所有orientation非1的图都通过ImageIO带transform的缩略路径（或等价不先全尺寸解码的变换），maxPixel取原图最长边与预算的较小值，保证小图不放大。也处理2—8镜像/旋转语义，不在NSImage逻辑size上交换数字掩盖像素没旋转。普通方向小图保留现有无重采样路径即可。

## 2. 64×64身份已经真实碰撞

两张256×256 checkerboard（1px/2px细节不同），ArtworkPalette.extract得到完全相同SHA256：6031d4087fe3d83d6e1220690a14a5d35dea3e88e5383e6b0abf7951db255809。不是SHA算法碰撞，是先缩64丢了内容，可能令ArtworkTransitionController认为封面没变而保留旧封面。这比“不用32调色板hash”仍然不够。

决定：封面identity哈希**完整的有界准备像素**。生产ArtworkImage.prepare输出本来<=256，hash其全部规范化sRGB/RGBA像素，包含实际宽高，不再缩64。ArtworkPalette.extract的直接NSImage调用兼容入口若给大图，先在同样256像素预算下规范化再hash，不调用TIFF、不持原尺寸副本。字节缓冲含padding须确定性初始化/只hash有效行，确保同图lossless编码稳定。像素预算和身份预算一致，不能只把64改128来凑当前样本。

原32×32提色规则保持，身份与palette分开；不改封面翻转时长/方向/curve。保留所有已验收build57歌词/锁屏/设置成果，严禁再动歌词代码。

## 验证与交付

先让独立2项通过，原ArtworkMemoryBoundedTests、ArtworkPalette/过渡的必要回归通过；小图/透明/非方形/方向与256像素上限、损坏回退/相同视觉PNG TIFF身份稳定保留。补56pt有细节而非全实色的有限视觉样本，报告差异而非声称无损。

更新 `docs/reports/artwork-memory-bounded-20261109.md` R1，明确这两处原版候选风险已修及真实footprint仍未实测。必要检查后一次候选自动build+1/签名hash/正常退出→零实例→唯一新包/默认无诊断，保留build57/58，不强退/覆盖Applications。不跑压力或操作真实媒体。完成等Codex验收，5分钟检查继续。
