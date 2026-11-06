# V0088 锁屏音乐卡：按刘海规则向下展开（顶边固定）

执行：现有 OpenCode 会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，按 `v0088-lock-card-top-anchored-expansion.md` 限定返修。
未改玻璃材质/焦点策略，未改顶部锁解与 Space，未启动或替换当前用户软件。

## 一、根因（先查布局链，不是先改常数）

V0085 的注释声称"顶部锚定"，但用户录屏显示展开/收起时整卡位移约 30px（逐帧测得卡片上边界在 199–230 之间变化）。逐条核对布局链后确认三处真实缺陷：

| # | 位置 | 缺陷 | 后果 |
|---|---|---|---|
| 1 | `LockRuntimeAdapters.setRootView`（改前） | `panel.contentView = NSHostingView(rootView:)`，**没有** `sizingOptions = []`（刘海浮层那条路径 `LockNotchOverlayWindowFactory` 是有的） | NSHostingView 会把窗口按 SwiftUI 内容尺寸调整；窗口原点在**左下**，长高时整块可视面上移 —— 正是"上面被拉升" |
| 2 | `LockMusicCoordinator.place()`（V0085） | 面板原点按 `top − canvasHeight` 用**常量**画布高定位，但窗口实际高度会被内容改变 | 顶部只在"窗口高度等于常量"时成立，一旦内容高度变化就漂 |
| 3 | `LockMusicView` 历史版本 | 根视图用过 `.padding(.bottom, margin)` + `.frame(..., alignment: .bottom)`（V0057 及之前），后改整屏时又出现过 `setFrameOrigin(screen.frame.origin)` 遗留 | 底对齐/错原点都会让顶边随高度移动 |

V0087 用"常驻空槽"把高度钉死，只是回避了第 1、2 条，用户已明确不接受。

## 二、本次布局策略

1. **窗口尺寸固定、不再被内容撑开**
   `LockFirstMouseHostingView` 增加 `host.sizingOptions = []`，并在挂载后 `panel.setContentSize(...)` 明确回设；窗口高度恒为 `LockCardLayout.canvasHeight = 380`。

2. **顶边由共享布局模型算出，且与展开状态无关**
   新增 `ReferenceCore.LockCardLayout`：
   ```swift
   public static let playerHeight: Double = 166      // 播放器块（含内边距）
   public static let volumeBlock: Double = 24 + 8    // 音量行 + 其上间距
   public static let lyricBlock: Double = 32 + 8     // 歌词行 + 其上间距
   public static let canvasHeight: Double = 380      // 宿主窗口高度（最高态 + 余量）

   public var cardTop: Double { screenMinY + screenHeight * 0.21 + playerHeight + verticalOffset }
   public func cardHeight(volume: Bool, lyrics: Bool) -> Double
   public var panelOriginY: Double { cardTop - canvasHeight }   // 与展开状态无关
   ```
   `place()` 只使用 `panelOriginY`，不再读取当前卡片高度。

3. **SwiftUI 侧顶对齐**
   `LockMusicView` 根视图 `.frame(width: 385, height: canvasHeight, alignment: .top)`，卡片就是第一个子视图；没有 `Spacer`、没有底边 padding、没有居中锚定、没有人为 Y 补偿。

4. **四态高度只向下增长**
   卡片内容顺序固定：播放器 →（可选）音量 →（可选）歌词；两段可选块都是"条件渲染 + `.transition(.opacity.combined(with: .offset(y: -6)))`"（与刘海播放器音量展开同一路径）。
   - 折叠歌词 = 整段移除（不留孤立音符，不留空槽），下方无其他内容，所以只有底边回收；
   - 收起音量同理；
   - 收起音量时歌词上移，播放器块不动。

5. 歌词块仍是 `CompactLyricsView` 原样（音符紧贴文字、整体居中），控制行左侧音符按钮负责折叠，右侧输出按钮负责音量。

## 三、四态尺寸/坐标依据（屏幕高 1117、offset 0）

| 状态 | 卡片高 | 顶边 y（自屏幕底） | 底边 y |
|---|---|---|---|
| H（仅播放器） | 166 | 400.57 | 234.57 |
| H+V（+音量） | 198 | 400.57 | 202.57 |
| H+L（+歌词） | 206 | 400.57 | 194.57 |
| H+V+L | 238 | 400.57 | 162.57 |

- 宿主窗口原点 = `400.57 − 380 = 20.57`，四态相同；
- 最高态 238 ≤ 380，窗口始终装得下，不会裁切；
- 21% 的基准位置与 V0085 之前一致（`屏高×0.21 + 166`）。

## 四、验证

命令（只跑改动相关的无窗口用例，未跑全量、未跑会建真实窗口的 MultiDisplay/Interaction 类、无截图循环/性能审计）：

```
swift test --filter "LockMusicCoordinatorTests|LockMusicStateTests|LockCardAppearanceTests|LockCardLayoutTests"
```

结果：

| 套件 | 数量 | 结果 |
|---|---|---|
| LockCardLayoutTests（新增） | 5 | 通过 |
| LockMusicCoordinatorTests | 31 | 通过 |
| LockMusicStateTests | 13 | 通过 |
| LockCardAppearanceTests | 4 | 通过 |
| 合计 | 53 | 0 失败 |

新增用例覆盖：四态高度差恰为 one volume/one lyric block、顶边与窗口原点与展开状态无关、无展开时仍是 21%+166、最高态不超出宿主窗口、offset 同时平移顶边与原点。

构建/打包/签名（只做核验，未启动、未替换用户软件或 dist）：

- 候选：`/private/tmp/valora-v0088-lock-top-expansion-candidate/Valora.app`
- binary SHA-256：`335e0ef1df1b6af24ac0ce2db5468dec9eb7a360bd8255cec6c1ccce037aa0b3`
- `codesign --verify --strict --deep` 通过

## 五、无法在此证明、明确待验

1. **真实锁屏下的顶边是否真的不动**：无窗口单测只能证明算术与约束，不能证明 WindowServer/玻璃合成后的可见结果；需要一次真实锁屏 + 真鼠标点击（音量展开、歌词折叠、快速反转）。
2. **窗口是否还会被系统调整尺寸**：`sizingOptions = []` + `setContentSize` 已按刘海浮层的既有做法处理，但登录界面接管后的实际窗口 frame 未采集。
3. **登录用户区域安全边界**：当前 21% 基准在本机登录界面上位于用户名上方（历史截图），本次未重新测量；若仍重叠需要用屏幕/布局边界数据再核对，而不是加人为 Y 补偿。
4. 玻璃材质、焦点策略、顶部锁解动画均未改动，沿用已接受版本。

完成，停等 Codex 独立验收；未 Git 提交/推送，未改动只读归档。
