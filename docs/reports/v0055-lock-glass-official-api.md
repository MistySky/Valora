# V0055 锁屏音乐卡：改用 macOS 26+ 官方 Liquid Glass API

2026-11-03。用户连续反馈「玻璃 / Liquid Glass 没做出来」，并明确要求用官方 API、以 macOS 27+ 最新为准（不做私有 API hack、不做旧系统兼容层）。本批只换锁屏音乐卡的**材质实现**，不动任何功能、布局、尺寸、动画、设置项。

## 一、为什么之前做不出来（取证结论）

### 1. 我们用的不是 Liquid Glass 材质

Valora 之前的锁屏卡是手搓 AppKit `NSGlassEffectView`（`Sources/Valora/LockGlassSurface.swift`，旧版），只设了公开的 `style` / `cornerRadius` / `tintColor`。

实测 A/B（同一窗口、同一背景、同一张卡，临时目录脚手架，不入库）：

| 卡片 | 实测 |
|---|---|
| `NSGlassEffectView` 默认 `.regular` | 背后条纹被**完全糊死**，无高光、无折射 → 磨砂塑料 |
| `NSGlassEffectView` 默认 `.clear` | 同上 |
| `_variant` = 18 | 与默认**视觉无差别** |
| `_variant` = 19 | 与默认**视觉无差别** |
| SwiftUI `.glassEffect(.regular, in: .rect(cornerRadius: 30))` | 背景仍可辨 + 边缘折射高光 → **Liquid Glass** |

证据：`docs/verification/lock-glass-official-v0055/ab-materials.png`。

### 2. 私有 `variant` 不是关键

原版 Alcove 的 AppKit 玻璃工厂（`100131c1c.c:59-71`）确实用 KVC `setValue:forKey:@"variant"` 设 18/19（字符串 "variant" @ `0x1005468d2`），但：

- 实测设 18/19 与默认渲染**完全一样**；
- 反查调用图（逆向 `reference-1.7.9/programs/Alcove-arm64/functions` 的 caller 图），该工厂**不在锁屏卡片链路上**（唯一调用者是无调用者的 thunk），它属于别的界面。

macOS 27 运行时上 `NSGlassEffectView` 的私有面：`class_copyPropertyList` 实测有 `_variant`、`_subvariant`、`_contentLensing`、`_adaptiveAppearance`、`_inverseMeshed`、`_placesContentAboveGlass`、`_scrimState`、`_subduedState`、`_tintOpacityReduced`、`_useReducedShadowRadius`、`_groupIdentifier`、`_backdropGroupName`、`_vibrantBlendingStyleForSubtree`；新建实例 `_variant` 默认 `nil`。原版锁屏卡是 SwiftUI 画的（`100187f28` 用 `RoundedRectangle` + `Color`/`BlendMode`/`ColorScheme`），走的是 SwiftUI 侧材质。

### 3. 之前几轮"修补"是手工模拟

上一轮加的 8% 黑 tint、0.8pt 内描边、14pt 投影，都是**手绘的玻璃外观**，叠在不透明乳白模糊上，只会更像灰塑料（实测卡片 83.4 / 底色 87.1、饱和度 5）。

### 4. 模拟预览放大了问题

预览是 borderless 透明 `NSPanel`（`LockCardPreview.swift:26-38`，`level = .floating`）浮在桌面上，材质直接采样壁纸；浅色壁纸上乳白模糊几乎不可见，于是观感是"完全没效果"。

## 二、本批改动（仅材质）

1. `Sources/Valora/LockGlassSurface.swift` —— 改为纯 SwiftUI，套官方公开材质：
   - `LockGlassStyle.glass` → `.glassEffect(.regular, in: .rect(cornerRadius: 30))`
   - `LockGlassStyle.clear` → `.glassEffect(.clear, in: .rect(cornerRadius: 30))`
   - 公开 API（macOS 26+）：`SwiftUICore.Glass` 的 `.regular` / `.clear`（另有 `.tint(_:)` / `.interactive(_:)`，本批未用）。
   - 删除 `NSGlassEffectView` + 私有 `variant` + 手写 tint 的全部代码；本产品 deployment target 是 macOS 27，不需要兼容分支。
2. `Sources/Valora/LockMusicView.swift` —— 去掉手绘的 0.8pt 顶部亮边描边与 14pt 投影（官方材质自带边缘高光与投影，叠加会变成假玻璃）。

**未动**：卡片 345pt、圆角 30、面板 385×325、顶部独占 Space、锁解动画、V0040 三项设置与模块总开关、耳机、普通刘海播放器、歌词、日历、菜单栏、设置项与顺序。

## 三、验证

- `swift build -c release`：**Build complete**（无新增警告）。
- 定向测试：`LockMusicStateTests` 15 + `LockCardAppearanceTests` 4 + `LockMusicCoordinatorTests` 31 = **50 项通过**（按本项目测试分工约定，只跑改动范围与相邻接口，未全量）。
- 打包 + `codesign --verify --strict --deep` 通过；候选 `/private/tmp/valora-v0055-lock-glass-swiftui-candidate`，binary SHA-256 `d12eeac2bb0ea77ba83b912b94d2d588851e648630d263625ed8e8cea98b53ee`。
- 单实例运行（先退出 v0054）：新候选带 `--lock-card-preview`，桌面常显锁屏音乐卡。截图时机器处于**登录/锁屏界面**，因此只留了一张参考图（`simulated-card-on-login-screen.png`）：卡片已是**半透明**面板而非不透明乳白块。

## 四、实机对照（同位置、同壁纸，旧构建 vs 新构建）

候选包**没有**替换用户的 `dist/Valora.app`（仍是 10-25 旧包）；屏幕上的运行实例是新候选 v0055（binary `d12eeac2…`），旧 v0054 已退出。

用 QA 环境变量把预览卡停到壁纸区域后，同一块位置抓图（`VALORA_LOCK_PREVIEW_ORIGIN` 为 QA 用，不写偏好）：

| 区域 | 旧 v0054（`NSGlassEffectView`） | 新 v0055（`.glassEffect`） |
|---|---|---|
| 卡片上半 L / S | 87.8 / 0.7 | 95.0 / 1.8 |
| 卡片下半 L / S | 84.9 / 13.0 | 89.1 / **18.0** |
| 卡片外壁纸 L / S | 89.3 / 0.1 | 94.8 / 0.0 |

新材质的饱和度来自壁纸透色（卡片内 S=18，壁纸 S=0），旧材质靠手写 8% 黑 tint 压暗（比壁纸暗 4）——两者都不是"玻璃本身发光"，而是**背后内容**决定观感。

证据：`docs/verification/lock-glass-official-v0055/compare-old-vs-new.png`、`new-glassEffect-over-wallpaper.png`、`old-NSGlassEffectView-over-wallpaper.png`、`new-glassEffect-over-white-window.png`。

## 五、为什么仍"像高斯模糊"（三个独立原因，都不是材质 API 用错）

1. **官方 `.regular` 本身就是磨砂材质**（"regular glass" = 模糊 + 轻微着色），`.clear` 只是更透一点、同样是模糊；不存在"不模糊的 Liquid Glass"。
2. **背景决定观感**：模拟预览是桌面上的一层，卡片正下方若是纯白窗口/纯白壁纸，玻璃再透也是白（实测壁纸 RGB 249/249/249 → 卡片 242/242/242）。只有背后有颜色才看得出透色。
3. **墨色没跟随壁纸**：原版用 `_isWallpaperNearlyWhite` 判定，浅色壁纸下切**深色墨**（`100187f28.c:1078-1088`）；Valora 还没实现该判定，固定用白墨，白字压在浅玻璃上 → 整块发灰、看不清，这是"糊"的主要来源。

## 六、仍待实机确认

- 解锁后真实桌面的最终观感；真实锁屏（锁屏背景偏暗，白墨问题会小很多）下的合成效果。
- 卡片在深色系统外观下的材质表现（当前未固定 colorScheme，与原版"玻璃背景固定 light"的做法不同；如需对齐再加，不在本批）。
- 原版 Alcove 锁屏卡本身走的不是 NSGlassEffectView 工厂，若要与原版 1:1 仍需继续逆向 `100187f28` 的 SwiftUI 分支。

## 七、下一步候选（均属官方 API / 原版逻辑，待用户选）

- a) 实现 `_isWallpaperNearlyWhite` 等价（读壁纸亮度）→ 浅色壁纸切深色墨/深色前景，与原版一致；
- b) `Glass.tint(...)` 给玻璃一点颜色/对比；
- c) 真实锁屏下复看（不新增功能）。

未做：Git 提交/推送、安装发布、真实媒体控制、系统写操作、循环弹窗/压力测试。

