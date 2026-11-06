# V0107：Liquid Glass 锁屏卡片调查（不改产品，不出包）

执行：现有会话。只做历史/归档核对与隔离 harness 实验；**未改产品源码、未打包、未加构建号、未启动或替换生产实例**。正式版本已是 1.0.0 / 构建 16（`dist/Valora.app`，本地 ad-hoc 签名）；本批未启动或退出任何 Valora 实例，结束时也无 Valora 进程在跑。未 Git 提交。

## 一、结论先行

本批**没有找到可验证的“非 key 锁屏仍保留 Liquid Glass 折射”实现**，因此：

- **不接入产品、不打新包**（避免重复浅色/clear 换皮或再造一个失败候选）；
- 生产 `LockGlassSurface` 保持现状：`NSGlassEffectView` + `.regular` + `.darkAqua` + 私有 variant 5；
- 新增证据与未解决项如下，供用户决定下一步（接受现状 / 允许更深取证 / 明确选择轻材质）。

## 二、历史材料复核

| 材料 | 结论 | 本批处理 |
|---|---|---|
| `docs/research/liquid-glass-inactive-window-2026-11-04.md` | 论坛/DTS 未给解法；“非 key 必然拿不到 active 玻璃”被写成系统限制；并称 Alcove 用 `NSVisualEffectView` active | **不当作绝对事实**：论坛只是个案；归档显示还有自绘 ClearGlass 图层栈 |
| V0043 | OS26+ 分支、私有 variant 2/5 | 保留为分支证据，不当作完整材质结论 |
| V0050/V0051 | 三档玻璃/设置预览 | 设置样式已删，仅历史 |
| V0055 | 公开 `.glassEffect` 被判“像高斯模糊” | 本批 harness 复现：确实是均匀模糊，无边缘折射 |
| V0056 | `NSGlassEffectView`+variant5+darkAqua 被接受为暗色玻璃 | 现状；用户现在反馈“太暗” |
| `docs/verification/glass-window-level-experiment/` | 窗口层级实验 | 保留；未重复其失败路径 |

## 三、归档新增证据（只读）

详见 `docs/verification/v0107/archive-evidence.md`。要点：

1. `ClearGlassLayerView` 不是系统材质控件，而是自绘栈：`rootLayer/backdrop/sdfLayer/elementLayer/glassBackground/glassForeground/keyFill*/outerBorder/innerBorder/gradientMask`；`ClearGlassEffectView` 只有 `cornerRadius, samplesWindowServer`；另有 `FakeClearGlassPreview` 仅用于设置预览。
2. `FUN_1000738d4` 用 `NSClassFromString`（混淆字符串，取不到回退 `CALayer`）建层，并把 `glassBackground` 放进 `setFilters_`；`FUN_100073dd0` 继续用 KVC 设置参数并在 `samplesWindowServer` 变化时重算。
3. 本机 macOS 27.2 确认私有 `CAFilter`/`CABackdropLayer` 存在，`glassBackground`/`glassForeground`/`keyFill` 可创建；但每个滤镜约 60 个输入**全部默认 nil、无 defaultValueForKey**。只设置 `inputSourceSublayerName` 或少量参数时，隔离 harness 中**看不到玻璃填充**（仅极淡边缘）。
4. 锁屏现代分支 `100187f28`（由 `100186a7c` 调用）的引用中**没有** ClearGlass/NSGlassEffectView/CABackdropLayer/CAFilter；全导出中 `NSGlassEffectView` 只出现在 `100131c1c`/`100132088`，且只经 thunk 暴露。`ClearGlassEffectView` 元数据访问器没有调用者。
   - 因此**不能证明**锁屏现代分支用了 ClearGlass 自绘栈，也不能证明它只走 NSGlassEffectView；归档证据不足以支撑“原版锁屏玻璃 = ClearGlass”的断言。

## 四、隔离 harness 实验

方法：独立 AppKit/SwiftUI harness（非 Valora 产品代码、未链接进产品），单一窗口、不抢用户锁屏焦点；用 `screencapture` 读取 **WindowServer 合成结果**（不是 `cacheDisplay`）。同一窗口内并排对照，key/non-key 各一次，不循环开关。

### 4.1 `appearsActive` 是否影响玻璃

在统一黑白棋盘背景上（`screenshots/h5-nonkey.png`，像素统计见 `pixel-stats.txt`）：

| 变体 | 卡内平均 RGB | 卡内方差 |
|---|---|---|
| `.glassEffect(.regular)` | 188.7 | 0.4 |
| `.regular` + `.environment(\.appearsActive, true)` | 188.7 | 0.4 |
| `.glassEffect(.clear)` | 157.4 | 0.3 |
| `.clear` + `appearsActive=true` | 157.4 | 0.2 |
| `.regular` + `.environment(\.controlActiveState, .key)` | 188.7 | — |

**像素级相同**：`appearsActive` 与 `controlActiveState` 不改变 `.glassEffect` 的合成结果。此前 h2 截图中“regular 与 regular+active 看起来不同”是因为两张卡位于不同背景色区域，不是材质差异；本批已用统一棋盘纠正。

### 4.2 key / non-key 对照

- `.glassEffect`（regular/clear）：key 与 non-key 都是**均匀模糊面**，棋盘格完全糊成平均色（卡内方差≈0），边缘只有干净圆角，没有可见折射/透镜。
- `NSGlassEffectView`（regular, darkAqua, variant5）：key 状态明显更暗（棋盘上均值 116 → key 下更深），non-key 稍浅但仍为暗色模糊；同样没有边缘折射。
- `NSVisualEffectView(.underWindowBackground, state=.active)`：亮而平的乳白面，非玻璃。

### 4.3 私有 CAFilter 自绘尝试

按归档线索搭建 `CABackdropLayer` + `CAFilter(glassBackground/glassForeground)` 的三种层级组合（`harness5.swift`）：卡区域内仍是**原始棋盘**（方差 ~16000），只有极淡圆角轮廓 → 滤镜没有产出玻璃填充。与“约 60 个输入默认 nil、无默认值”一致；没有 Alcove 的实际参数值，无法安全复现。

`screenshots/h7-nonkey.png` 中 A/B/C 三张自绘卡基本透明，仅最右 NSGlassEffectView 对照卡可见。

## 五、为什么本批不出包

- 用户要求的是“Liquid Glass”，而不是浅色/clear 磨砂；harness 证明公开 `.glassEffect` 在当前系统上就是均匀模糊、无折射，换过去只是另一次材质换皮，且 V0055 已被用户拒绝。
- 自绘 ClearGlass 需要一整套私有滤镜参数（折射量/高度、多段 blur、face/bleed/shadow/keyFill 等），归档中这些值以混淆字符串/常量出现，**本批无法可靠还原**；用猜测值做出的东西不能声称是 Alcove 的 Liquid Glass。
- 任务明确：仍失败则保留生产源码、报告新增证据与未解决项，不再打同样失败的正式包。本批按此执行。

## 六、未解决项 / 下一步选项

1. **接受现状**：继续使用当前暗色玻璃；本批不改。
2. **允许更深取证**：提取 Alcove ClearGlass 的全部滤镜参数并做隔离试验（需要更多时间；如需运行原版做图层内省，须用户另行授权，当前任务不允许启动原版/真实锁屏）。
3. **明确选择轻材质**：如果用户只是觉得“太暗”，可单独选一个更亮的公开 `.glassEffect`/tint 方案，但这不解决“非 key 折射”，且属于材质口味选择，本批未擅自改。
4. 真实锁屏下的合成仍无法用桌面 harness 证明；需要用户实机一次锁屏观察（本批不自动锁屏）。

## 七、边界与状态

- 未改 `LockGlassSurface`、`LockMusicView`、几何/动画/歌词/音量/生命周期；未运行真实媒体/设备/日历/权限；未锁屏；未安装/未打包；未加构建号；未 Git 提交。
- 本批未启动/退出/替换 Valora，也未触碰 `dist` 的 1.0.0 产物；结束时无 Valora 进程、无遗留 harness。
- 证据：`docs/verification/v0107/`（`archive-evidence.md`、`cafilter-probe.txt`、`pixel-stats.txt`、`screenshots/`、`harness-sources/`）。
- 停等 Codex 独立验收；不继续性能/功能开发。
