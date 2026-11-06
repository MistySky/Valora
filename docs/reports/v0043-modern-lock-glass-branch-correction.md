# V0043 纠正 macOS 26+ 锁屏音乐玻璃分支

2026-11-03，现有 OpenCode 会话执行（`docs/opencode-tasks/v0043-modern-lock-glass-branch-correction.md`）。
起因：用户实测归档复刻品的锁屏玻璃也乳白，不能作为正确视觉基线；Codex 重读反编译后发现 V0042 依据漏看外层 OS 分支。V0042 的 HUD 结论作废（不重跑，保留为失败记录）。

## 证据表

| # | 位置 | 条件 / 事实 | 结论 | 未知 |
|---|---|---|---|---|
| 1 | `100186a7c.c:134–137` | `_stdlib_isOSVersionAtLeast(0x1a,0,0)`（macOS 26） | 后面存在 OS 分支 | — |
| 2 | `100186a7c.c:443–452` | 位于 `OS < 26` 分支内：`material 0xd`、`blending 0`、`+0x39=1`（`frosted` 字节） | 旧 HUD 参数只用于 macOS 26 以下 | — |
| 3 | `100186a7c.c:572–595` | `else`（OS ≥ 26）调用 `FUN_100187f28(puVar31, 0x4075900000000000=345, 0x403e000000000000=30, param_2)` | macOS 26+ 走 `100187f28`，宽度 345、**圆角 30** | — |
| 4 | `100187f28.c:87–95` | 读一个样式枚举 `cVar7`，并另有 `OS >= 27` 判断；枚举取 0/1/2 时分支不同 | 样式枚举存在三种取值 | 该枚举对应哪个用户偏好未映射 |
| 5 | `100187f28.c:1031–1048` | `_isWallpaperNearlyWhite` → `variant = 2`，否则 `variant = 5`；写 `material 13 / blending 0 / state active / +0x39 = 2 / cornerRadius = param_3(30)` | macOS 26+ 走 `NSGlassEffectView`，**私有 `variant`** 决定外观 | `variant` 2/5 的语义 |
| 6 | `100187f28.c:1055–1065` | 背景颜色方案设为 `light` | 玻璃背景按浅色 | — |
| 7 | `100187f28.c:1078+` | 前景按壁纸条件选择 | 文字明暗随壁纸 | 具体判据未展开 |
| 8 | `100131c1c.c`（工厂） | `OS >= 26 && (*(+0x39) & 1) == 0` → `NSGlassEffectView`，`setValue:@(variant) forKey:<Swift 字符串常量>` + `setCornerRadius:` | `+0x39 = 2` 满足条件，确实进 Glass 分支 | KVC 的 key 名来自 `DAT_1005fc610` 的 Swift 字符串常量，导出中不可解析；二进制里存在 `variant` 字面量，但**未证明**就是该 key |
| 9 | Apple 文档 | `NSGlassEffectView.contentView` 才保证在玻璃内，任意子视图相对 glass 的 z 序不保证 | 承载播放器必须用 contentView 语义 | — |

**纠正两处绝对结论**：
- V0041「原版锁屏就是 Liquid Glass」→ 当时证据只到"工厂能力"，不能得结论。
- V0042「原版锁屏音乐卡不是 Liquid Glass、只能私有近似」→ 同样错，漏看了 `OS >= 26` 外层分支；macOS 26+ 确实走 `NSGlassEffectView`，只是带了私有 `variant`。

## 本批实现

- `Sources/Valora/LockGlassBackground.swift`（新）
  - `lockCardGlass()`：`glassEffect(.clear, in: RoundedRectangle(cornerRadius: 30, style: .continuous))` + `.environment(\.colorScheme, .light)`。
  - 先试过 `.regular`：用户实测（提供截图）仍判为"毛玻璃/乳白，不是 macOS 26 以上的透明玻璃"。改为公开 API 的 `.clear`（Apple 定义为 clear glass，用于内容丰富的背景）。
  - 选 `glassEffect(_:in:)` 而不是 `.background(NSGlassEffectView)`：前者把内容放进玻璃内部，符合 Apple 对 `contentView` 的契约，也避免了"玻璃层盖住播放器导致整张卡消失"的问题（V0041 实测过）。
  - 圆角取反编译 macOS 26+ 分支的 **30**（不是旧分支的 28）。
- `Sources/Valora/LockMusicView.swift`（`LockMusicCard`）
  - 内容固定 `frame(width: 345)` 后再套玻璃，玻璃不参与尺寸；`.glassEffect` 不改变布局尺寸，卡片宽度仍是 345。
  - 删除 `LockFrostedBackground`（`.hudWindow` 旧分支容器）与全部 Liquid Glass tint / 自绘壁纸 / 明暗叠层残留。
- 未改：顶部独占 Space、锁解原地开锁 → neutral → 最新音乐、V0040 三项设置与模块总开关、耳机单行 16pt、进度条未播放段、从下往上滑入、普通刘海播放器/歌词/权限/日历、显示来源。

## 未证与缺口（不声称已一致）

1. **私有 `variant`（2 / 5）语义未映射。** 本候选用公开的 `.clear`。此前写"如果不一样缺口就在这里、没有合法公开手段"是**没有依据的绝对结论**：前景色策略、appearance、容器与合成路径都还没排除。`.regular` 同样是 macOS 26 的 Liquid Glass 样式，不是旧 HUD 毛玻璃；用户说的"毛玻璃感"是观感描述，不等于实现类型。用 KVC 盲写未知 key/值可能 crash，仍不做。
2. **KVC key 名未证实。** 二进制里有 `variant` 字面量，但工厂用的 `DAT_1005fc610` 是 Swift 字符串常量，导出中无法解析到具体值，不能据此认定就是 `variant`。
3. **玻璃是否有可用背景未验证。** 原版 `LockPanel` 是**整屏**容器（`1001bf2dc` 创建屏幕大小的 LockPanel），Valora 的锁屏音乐面板是 385×325 的小面板。面板形态差异是否就是"玻璃拿不到背景、渲染成乳白"的原因，本批**未做结论**，也没有用叠色去掩盖。若下一轮仍乳白，这是首选的单变量验证方向。
4. 桌面 `--lock-card-preview` 只能核对几何/尺寸/内容；登录界面合成与它不同，不能当作材质结论。本轮未启动它。

## 验证

- `swift build` / `swift build -c release` 通过。
- `LockMusicCoordinatorTests` 31 项、`LockMusicStateTests` 13 项通过。
- 尺寸：内容 `frame(width: 345)` 在前、玻璃在后，`.glassEffect` 不改尺寸。
- 候选：`/private/tmp/valora-v0043-modern-lock-glass-candidate/Valora.app`
  - binary SHA-256 `52aa9436e1a162d4f21e2b0fe2c26a87a7e6c66f20c9b273686d4f2844f8c84c`
  - `codesign --verify --strict --deep` 通过
  - 本报告初版写"未启动"是错的：该候选在交付后**被用户要求启动过**（PID 16503），并用 `--lock-card-preview` 做了桌面预览截图。更正记录见文末"交付与证据更正"。未覆盖 `dist`

## 交付与证据更正（2026-11-03）

- 报告初版称候选"未启动"，与对话记录不符：用户在 V0043 交付后要求启动，实际以 PID 16503 运行过 `valora-v0043-modern-lock-glass-candidate`，并用 `--lock-card-preview` 在该目录做过桌面预览截图（含一次 `VALORA_LOCK_PREVIEW_ORIGIN` 定位）。
- 该候选目录在迭代中被**同一路径覆写多次**（`.regular` → `.clear`，另有一次直接 `cp` 二进制 + 重签做快速预览），因此"报告 hash / 截图版本 / 当时运行版本"不能一一对应。这是流程错误，后续改为独立新路径 + 冻结 hash（见 V0043-R1）。
- 桌面预览不是锁屏合成，其颜色不能作为锁屏材质结论；上述预览截图只用于确认几何与卡片尺寸。

## 边界

未做真实锁屏 / 锁通知 / 真实 NSWindow / Space / 多屏 / UI 循环 / 批量截图 / 性能测试；未读取用户壁纸、个人日程或账号数据；未控制真实媒体、设备或权限；无 Git 提交推送；定时器保持关闭。等 Codex 独立验收与用户一次体验。
