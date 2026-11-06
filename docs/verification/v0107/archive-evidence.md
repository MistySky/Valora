# V0107 归档只读取证（alcove-rea-20261021-v2）

来源：`/Users/wangqing/code/tmp/alcove-rea-20261021-v2/exports/Alcove-arm64/`（只读，未改）。
另有本机分析副本 `~/code/tmp/alcove-analysis/Alcove.app`（1.7.7），仅用于 `strings` 交叉核对，未运行。

## 1. Swift 类型字段

`swift-types-fields.txt:121` 起：

- `ClearGlassLayerView`：`cornerRadius, samplesWindowServer, materialStyle, rootLayer, backdrop, sdfLayer, elementLayer, glassBackground, foregroundBackdrop, foregroundSDF, foregroundElement, glassForeground, keyFillPortalLayer, keyFillLayer, keyFillChildPortalLayer, keyFillEffect, keyFillFilter, outerBorderLayer, innerContainer, innerMiddle, innerBorderLayer, gradientMask, innerBorderEdgeMask, outerBorderMask`
- `ClearGlassBorderLayerView`：`cornerRadius, showsOuterBorder, materialStyle, rootLayer, outerBorderLayer, innerContainer, innerMiddle, innerBorderLayer, gradientMask`
- `ClearGlassEffectView`：`cornerRadius, samplesWindowServer`（SwiftUI 包装）
- `ClearGlassBorderEffectView`：`cornerRadius, showsOuterBorder`
- `FakeClearGlassPreview`（字段 97 行）：`cornerRadius, colorScheme, opacity, brightness, showsOuterBorder` —— 设置页预览用，不代表锁屏材质。

结论：这是**自绘的图层栈**（backdrop + SDF + element + 前景 + keyFill + 内外边框），不是简单调用 `NSGlassEffectView`。

## 2. 图层构造与私有滤镜

- `FUN_1000738d4`（ClearGlassLayerView 的 layer 初始化）：
  - `NSClassFromString` 取一个私有类（字符串经混淆）；取不到则回退 `CALayer`。这与 `CABackdropLayer` 的特征一致，但导出未直接给出类名。
  - 建立 `backdrop`/`sdfLayer`/`elementLayer` 层树，并把 `glassBackground` 对象放进 `setFilters_` 数组。
- `FUN_100073dd0`：对相关层 `setValue:forKey:`，并对 `glassBackground`/`glassForeground` 层调用 `setFilters_`。
- `FUN_100073510`：`cornerRadius`/`samplesWindowServer` 变化时重新应用（`samplesWindowServer` 明确影响重算分支）。

**本机 macOS 27.2 实测**（`cafilter-probe.txt`）：
- `CAFilter`、`CABackdropLayer` 类存在；
- `+[CAFilter filterWithName:]` 支持 `glassBackground`、`glassForeground`、`keyFill`；
- 每个滤镜有约 60 个输入（折射量/高度、blur 半径与多段 opacity、face/bleed/shadow/ring/keyFill highlight 等），**全部默认 nil，且不支持 defaultValueForKey:**。只给少量输入或只设置 `inputSourceSublayerName` 时，隔离 harness 中看不到玻璃填充（见 `screenshots/h7-nonkey.png`，只剩极淡边缘）。

## 3. 锁屏现代分支与 NSGlassEffectView 的区分

- `100187f28`（已知现代锁屏分支）的唯一调用者是 `100186a7c`。
- `100187f28` 的 outgoing references 中**没有** `ClearGlassLayerView` / `ClearGlassEffectView` / `NSGlassEffectView` / `CABackdropLayer` / `CAFilter`。
- 全导出中引用 `NSGlassEffectView` 的只有 `100131c1c` 与 `100132088`；两者只经 thunk（`10013230c`/`100132310`）间接暴露，未找到普通直接调用者（可能是函数指针/专门化入口）。
- `ClearGlassEffectView` 的类型元数据访问器 `1000766b0` 在导出中**没有调用者**；`ClearGlassLayerView` 的构造/析构只在自身类方法中出现。

结论（限定）：**不能从该导出证明锁屏现代分支使用了 ClearGlass 自绘栈**，也不能证明它只走 NSGlassEffectView 工厂；现有材料不足以把“原版锁屏玻璃=ClearGlass”当作事实。此前研究文档把“非 key 必然灰”当作系统限制，同样属于推断而非系统保证，本批不沿用为绝对结论。

## 4. 与既有实验的关系

- V0043 发现 OS26+ 分支与私有 variant；V0050/V0051 做设置三档；V0055 用公开 `.glassEffect` 被判“像高斯模糊”；V0056 用 `NSGlassEffectView` + variant5 + darkAqua 被接受为“暗色玻璃”，但用户现在认为太暗。
- 本批新增的关键证据：**`appearsActive` 与 `controlActiveState` 不能改变 `.glassEffect` 的合成结果**（像素级相同），且 NSGlassEffectView 在 key 状态明显更暗（见 `pixel-stats.txt`）。
