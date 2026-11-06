# V0041 锁屏视觉对齐 Alcove

2026-11-03，现有 OpenCode 会话执行。用户提供同一台机器的两张实拍（Valora V0040 候选 / 原版 Alcove）并要求“对齐 alcove”。
在 V0040 成果上继续，未回退独占 Space 修复、锁解动画、阶段顺序。

## 依据

`docs/verification/direct-lock-visual-parity/`：两张原图、四张对比裁切、`findings.md`（含像素测量）。

## 源码变更

1. `Sources/Valora/LockInformationView.swift`
   - 由“圆角毛玻璃卡片 + 24pt 图标 + 设备名 + 电量”改为原版的**单行** `图标 + 电量`，直接印在壁纸上，无底板、无设备名。
   - 面板几何（360×94、原有落位公式）未改，只换内容；电量未知仍显示“电量暂不可用”，不编造数值。
   - 白色细字在亮壁纸上需要可读性，加了一个很轻的黑色投影（radius 2）；这是为可读性的最小处理，不是新增样式。
2. `Sources/Valora/MediaProgressView.swift`
   - 新增 `trackColor`：`translucent` 分支用 `.white.opacity(0.16)`，普通刘海播放器仍用 `.gray.opacity(0.25)`。
   - 原因：`.gray@25%` 压在灰色锁屏卡片上几乎与底色同亮度，未播放段读不出来；原版该段约为卡片底色的 1.14 倍，填充约为 1.8 倍。`.white@16%` 在 `.hudWindow` 卡片上约给出 1.18 倍。
   - 首版用了 0.28，真机上比原版偏亮；已按测量回调到 0.16。
3. `Sources/Valora/LockGlassBackground.swift`（新，取代 `LockFrostedBackground.swift` / `LockGlassBackdrop.swift`）+ `Sources/Valora/LockMusicView.swift`
   - 先按单列测量换成 `.underWindowBackground`，**真机否决**：卡片变成接近不透明深色（内部灰阶 ≈60，背景 ≈205）。
   - 已回退为 `.hudWindow`。改按整行平均重测：`.hudWindow` 内部 ≈120 对原版 ≈137，差约一成，属照片曝光误差；换材质差 2 倍以上。
   - 文件内保留了这次否决的记录，避免以后再次按单点采样误判。
   - 恢复 `.hudWindow` 后先试 10% 白色薄纱，用户反馈“透明度还是不够”。
   - 进一步核实：卡片内部亮度几乎不随背后壁纸变化（背纸 157→226，卡内只有百余级的轻微波动），说明**登录 shield 之上的窗口拿不到 behindWindow 背景**，系统材质只是画了一层不透明底色。这解释了“看起来是灰块、没有玻璃感”。
   - 改为自绘玻璃（`LockGlassBackdrop`）：取当前桌面壁纸，按填充规则缩放裁切、高斯模糊（sigma 26）、按窗口真实屏幕坐标对齐绘制，再叠 0.31 黑色薄纱，最后裁成连续圆角。用公共 API 复现原版可见效果，不依赖 WindowServer 采样。
   - 参数标定：卡内亮度 / 背后壁纸 ≈ 0.69，与原版实测一致（137/200）。离线预览 `/private/tmp/lock-glass-blurred.png` 确认模糊效果正常。壁纸取不到时回退为深灰底色，卡片不会消失。
   - 用户指出方向错了：原版是 **macOS 26 玻璃（liquid glass）**，不是毛玻璃。
   - 回查反编译（`reverse-engineering/lock-appearance-0.6.5/100131c1c.c`）：原版在 macOS 26+ 且 `frosted=false` 时走 **`NSGlassEffectView`**（cornerRadius 28 + 一个通过 KVC 设置的整数参数），`NSVisualEffectView` 只是 `frosted=true` 的回退分支。macOS 27 SDK 里 `NSGlassEffectView` 公开可用（`contentView/cornerRadius/tintColor/style/effectIsInteractive`）。
   - 改为直接用 `NSGlassEffectView`（`LockGlassBackground`，cornerRadius 28，`style = .regular`），删掉自绘模糊/薄纱方案。若需要更透可以一行切 `.clear`。
   - `LockFrostedBackground.swift`、`LockGlassBackdrop.swift` 均删除，反编译依据迁到新文件。
   - 用户随后反馈"是暗色/底色透明度不对"。定位到 **我们自己的 `LockMusicView` 根部 `.environment(\.colorScheme, .dark)`**：它会一路传到 `NSGlassEffectView` 的 appearance，把玻璃强制成深色变体。已删除该根覆盖，只保留卡片内容自己的 `.colorScheme(.dark)`（白字需要）。
   - 曾试过在玻璃后面铺一层壁纸（`LockWallpaperBackdrop`）让玻璃有可折射的内容，离线渲染显示 `NSGlassEffectView` 会盖住同窗口内的兄弟视图，因此删除，保持"只放系统玻璃"的最小形态。
   - 离线校验的边界：`NSGlassEffectView` / `.glassEffect` 是合成层效果，`cacheDisplay` 截图拿不到真实呈现（只出白色兜底），所以材质只能靠用户真实锁屏看，不能用离屏截图代替。

未改动：锁屏页三项设置、耳机/音乐卡显示逻辑（各模块总开关）、独占 Space、解锁→neutral→最新音乐、顶部锁动画、桌面模拟之外的其它模块。

## 验证

- `swift build` / `swift build -c release` 通过。
- `LockMusicCoordinatorTests` 31 项、`LockMusicStateTests` 13 项通过（视图本身无单测；本轮按要求不跑真实 NSWindow/Space/UI 循环/截图批量/性能）。
- 候选：`/private/tmp/valora-v0041-lock-visual-parity-candidate/Valora.app`
  - binary SHA-256 `0e4ac84c7221ba9afde2f83bc1b6c83ff3c3e8767dbc2d63484654f528a34bfb`
  - `codesign --verify --strict --deep` 通过
  - 未覆盖 `dist`、未覆盖 `/private/tmp/valora-v0040-lock-settings-candidate`

## 第二轮实机反馈与修正（2026-11-03）

用户实拍（`current-v0041-firstpass-lock.jpg`）指出：耳机文字"非常的小"，音乐卡"还是 glass 的效果，没对上"。

1. **耳机单行偏小**：两张照片里这行字的像素高度几乎一样，但 Valora 那张照片的缩放是原版的 1.235 倍（同一张 345pt 卡片在照片里 473px vs 383px）。也就是说屏幕上的实际尺寸小了约 23%。字号 13pt → **16pt**，图标 13pt → **17pt**，weight 保持 semibold。
2. **卡片玻璃感**：用户看到的那张近黑色卡片，是上一步被否决的 `.underWindowBackground` 构建（内部灰阶 ≈60）。该改动已回退，`.hudWindow` 的玻璃已恢复。在恢复的基础上再补一层 **10% 白色薄纱**（`LockMusicView` 的卡片背景 ZStack），把内部亮度从 ≈120 拉到 ≈137，对齐原版同背景下的 ≈137；只加白纱、不换材质，避免再次出现整块变黑。
3. **耳机单行位置偏低**：以时钟底沿到该行的间距做同图对照，Valora ≈101pt、原版 ≈37pt，我们的低了约 60pt。信息面板顶锚公式不变，把单行改为在面板内**顶部对齐**（等价于原版“同一顶锚下的细线”），上移约 47pt；没有加任何魔法 offset。
4. 进度条轨道维持 0.16（上一轮已回调）。
5. **卡片偶发不出现**：用户录屏（14:29）显示锁屏只有刘海徽标与耳机行、没有音乐卡；同版本 14:20 的录屏却有卡，属间歇问题。判因：`NSGlassEffectView` 官方只保证 `contentView` 在玻璃内，**任意子视图相对玻璃层 z 序不保证**，把它当 `.background` 垫在播放器下方正踩此条。改为 SwiftUI `View.glassEffect(_:in:)`（内容在玻璃内部，z 序由系统保证），播放器不会再被盖住。
6. **玻璃过淡/白字发灰**：`.regular` 无 tint 实测卡内 / 背后壁纸 ≈0.93（原版 ≈0.69），白字对比度不足。加 `.tint(.black.opacity(0.25))`，目标回到 ≈0.70。`Glass` 还提供 `.clear` 与 `.tint(_:)` 两个后续旋钮。
7. **弹出方式**：用户确认原版是"从下往上滑入"。入场过渡由 `LockScaleAndFade(scale: 0.25)`（从 25% 原地放大，观感是两段式）改为 `LockSlideAndFade(offset: 56)`——自下方 56pt 向上滑入并淡入；离场仍是原来的 0.95 缩小淡出。弹簧参数保持反编译值 `spring(duration 0.6, bounce 0.3, delay 0.075)`。

记录教训：材质不能靠单列采样判断；字号对比必须先归一化两张照片的缩放比（用音乐卡宽度做基准）。

## 更正：V0041 关于"原版锁屏就是 Liquid Glass"的判断是错的

本文件此前写过"回查反编译：原版在 macOS 26+ 且 `frosted=false` 时走 `NSGlassEffectView`，所以锁屏卡应该用系统玻璃"。**这个推论不成立**，已由 Codex 复核反编译调用点纠正：

- `100186a7c` 该调用点传入的参数是 `material=0xd`、`blending=0`、`state` 取默认、`+0x38` 处 `0x101`（后字节 `1`）即 **`frosted = true`**、`corner 28`；
- `100131c1c` 里只有 "macOS 26+ **且** `frosted == false`" 才进 `NSGlassEffectView`，否则走 `NSVisualEffectView` 的 `setMaterial/setBlendingMode/setState/setEmphasized`。

也就是说：**通用工厂支持 `NSGlassEffectView`，不等于锁屏音乐卡走了这条路**；锁屏音乐卡的调用是 frosted=true，实际走的是 `NSVisualEffectView`。我此前把"工厂有能力"当成"本调用使用"，属于误判。

相关的 Liquid Glass / 自绘壁纸 / 明暗叠层实验全部作废（保留在本文件作为失败记录，不删除）。锁屏音乐玻璃的返修见 `docs/reports/v0042-lock-music-glass-source-parity.md`。

## 第三轮：不锁屏即可验证（2026-11-03）

用户建议"不锁屏测试，直接能看到效果"。已落地：

- 新增开发用启动参数 `--lock-card-preview`（`LockCardPreviewController`）：把**同一份** `LockMusicCard` 按锁屏的真实位置、尺寸显示在桌面上；不在设置/菜单里暴露，不改变会话或锁屏状态。
- 卡片拆成独立的 `LockMusicCard`，真实锁屏与预览共用，预览看到的即锁屏所见。
- 配合 `screencapture -R` 只截卡片区域，可反复量化比较，不再需要用户反复锁屏。

用该能力定位到的两件事：

1. `.glassEffect` 的 `tint` 几乎无效：`tint(black 0.30)` 实测卡内仍是被后壁纸的 **1.01 倍**，玻璃本身加了一层白，所以一直是"乳白色"。
2. 真正决定密度的是玻璃**内部**内容：把真实壁纸区域画进卡片、模糊 sigma 18，再压一层 0.32 黑，最后套 `.glassEffect(.regular)`。实测卡内 **145** / 壁纸 **209** = **0.69**，与原版一致，白字对比度恢复。

证据：`docs/verification/direct-lock-visual-parity/preview/`（`tint-030-milky.png` 乳白版 / `shade-032-matched.png` 对齐版）。

## 第四轮：用户要求回退卡片材质（2026-11-03）

用户反馈"越改越离谱，现在改的很大了，恢复之前的"。

定位到尺寸变化的具体原因：为把壁纸塞进玻璃内部用了 `ZStack { LockWallpaperLayer(); ... }`，而 `NSViewRepresentable` 没有固有尺寸、会吃满父级建议尺寸，把卡片从 345pt 撑到 385pt（等于整个面板宽度）。预览截图量到卡片左沿位置与 345pt 不符，确认。

处理：卡片恢复到 **V0041 之前的磨砂容器**（`LockFrostedBackground`：`NSVisualEffectView` `.hudWindow` / behindWindow / active / emphasized + 连续圆角 28），尺寸回到 345×内容高度；删除 `LockWallpaperLayer` 与 `.glassEffect`。保留用户已确认的其它项：耳机单行 16pt/顶部对齐、进度条未播放段 0.16、从下往上滑入、系统监控说明删除。

注意：`--lock-card-preview` 在桌面合成下 `NSVisualEffectView` 会比锁屏态偏亮，预览只用于核对布局/尺寸/内容，材质密度仍以真实锁屏为准。

## 未覆盖 / 风险

- 材质已回到用户上一轮看到的那一版（`.hudWindow`），因此这块不会倒退；耳机单行与进度条轨道需再看一次。
- 耳机单行与音乐卡纵向位置：原版截图的顶部被反光过曝，无法可靠量取锁屏条几何，因此没有调整任何落位常量，只改绘制内容。
- 原版标题行的“……”/波形细节未对齐，本轮未处理。
- 未 Git 提交/推送；定时器保持关闭。
