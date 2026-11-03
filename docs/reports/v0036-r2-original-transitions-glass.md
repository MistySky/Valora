# V0036-R2 锁解过渡顺序与锁屏音乐卡材质返修报告

日期：2026-10-28
状态：限定返修完成，等待 Codex 独立验收；**真实锁屏/解锁、真实壁纸材质、真实动画帧仍待用户一次实机核验**。
候选：`/private/tmp/valora-v0036-r2-transitions-candidate/Valora.app`
候选二进制 SHA-256：`f799bbffaef4b7741367c108cccee2bc1235379af54778fb88ba05863734d171`

## 1. 结论

本轮只修用户实际观察到的锁解过渡顺序和锁屏音乐卡底色，不重做 UI、不扩功能。处理后：

- 锁定不再把普通音乐/扩展面板直接替换成锁标志；先让现有普通呈现完成收起，再把锁标志提交并让锁屏音乐卡出现。
- 解锁先保留顶部开锁分体 glyph，立即移走锁屏专用音乐/设备窗口，然后进入恢复阶段；恢复普通音乐后短暂结束恢复阶段，再做最终 badge 清场。
- 中间阶段不会因为 `expanded`、Quick Peek、歌词高度或 `isSessionLocked` 的异步组合把刘海向下拉出；顶边锚定由现有面板固定 frame 保证。
- 锁屏音乐卡移除了复刻自加、并非原版 fallback 证据的 `NSVisualEffectView` 强制 `darkAqua`，以及非源实现的白色描边 overlay；保留源实现可证的 material/blending/state/emphasized/continuous corner 路径。
- 保留 R1 的 state/sleep 复位、epoch、fake adapters、当前 notch provider、`informationAirPods` 发布、全局音乐开关和锁屏 Space 所有权/解锁清理。

没有真实锁屏/解锁、没有播放声音、没有媒体控制/音量/蓝牙/权限/系统设置写、没有真实窗口/Space 呈现测试、没有 `--verify-*`、闪窗、批量截图或性能压力测试。用户当前运行包和 `dist` 未动。

## 2. 原版证据、用户观察、复刻现状

### 2.1 用户实测观察（本轮的动态验收依据）

用户对原版 Alcove 的观察：

1. 锁定时在顶部刘海原位置先收起当前音乐/左右扩展，再展开锁定状态；不应出现先向下拉出再回顶部。
2. 解锁时先显示开锁状态/动画，再收起锁状态，最后恢复当前音乐。
3. 当前 Valora 缺少这个连续顺序，且锁屏音乐控制卡底色不对。

这是行为验收依据，不冒充逐帧原版二进制证据。

### 2.2 可读的原版/复刻来源

- `reverse-engineering/lock-screen-music/100186a7c.c`：音乐卡宽度、内边距、内嵌播放器布局和 glass 背景接线；旧边界文档记录 345pt 卡、旧证据 30pt 圆角以及入场 spring 参数，复刻实际使用 28pt。
- `reverse-engineering/lock-appearance-0.6.5/100131c1c.c`：
  - fallback 创建 `NSVisualEffectView`，设置 material=13（HUD）、blending=0（behindWindow）、默认 state active、emphasized=true，并用连续圆角容器裁切；
  - 在 macOS 26 的 `frosted=true` 分支才避开 `NSGlassEffectView`；
  - 该 fallback 函数没有设置 `darkAqua` appearance。
- `reverse-engineering/lock-appearance-0.6.5/依据与边界.txt`：明确 glass 固定、frosted 分支、corner 28；同时说明旧材料响应和壁纸亮度分支尚未完整恢复。
- `reverse-engineering/lock-appearance-0.6.5/100206af0.c`：`lock.top`/`lock.bottom` 分体 glyph、字体和开锁变换来源；复刻当前 -24°、x+2/y-2 仍是复刻值，不是原版逐帧常数。
- `Sources/AlcoveRevival/LockMusicCoordinator.swift`：现有 `setLocked(false)` 先 orderOut 并 detach 音乐面板，顶部 notch 保留到解锁阶段；这是 R1 Codex 补回的清理路径，本轮保留。
- `Sources/AlcoveRevival/NotchView.swift`：锁 glyph 视图；现有复刻状态只有 hidden/locked/unlocking。
- `Sources/AlcoveRevival/PresentationController.swift`：已有 `collapse(completion:)` 和呈现 completion 机制，本轮直接用它安排“普通内容收起完成后再提交锁状态”，没有新增多个 `asyncAfter` 平行状态机。
- `Sources/AlcoveRevival/LockFrostedBackground.swift`：复刻当前 `.hudWindow`/`.behindWindow`/active/emphasized/continuous clip；但强制 `darkAqua` 和 `LockMusicView` 白色 overlay 属于复刻附加，不是 `100131c1c` fallback 的调用。

### 2.3 当前复刻/Valora 差异

- 原版/复刻源码没有完整暴露 `普通内容收起→锁定展开→开锁→锁收起→音乐恢复` 的显式阶段；现有 `LockIndicatorState` 只有 hidden/locked/unlocking。R2 最小扩展这四个阶段，而不是另起全局状态机。
- 用户观察到的“向下拉出”来自旧路径直接修改 `isSessionLocked`/`presenter.collapse`/`lockNotchMounted`，同时 `visibleSize` 仍可能读取 expanded/peek/歌词高度；R2 让普通内容在 `.locking` 阶段保持，收起 completion 后才提交 badge。
- 原版时长没有据可读证据确认。R2 保留复刻既有 `0.8s` 解锁 glyph、`0.12s` restore settle、`32ms` entry commit、`0.85s` hide；这些是复刻/重建值，不是原版精确时长，不能宣称 1:1。


### 2.4 精简对照表

| 用户原版观察 | 具体原版函数/复刻源位置 | Valora 实现 | 尚无证据的参数 |
|---|---|---|---|
| 锁定时在顶部原位置先收起当前音乐/左右扩展，再展开锁状态 | 用户实测；复刻 `PresentationController.collapse(completion:)`；`LockMusicCoordinator.setLocked` 现有 collapse 调用；原版 `100184060` 的 `isVisible` 0/1 与 `onDisappear` 链 | `LockIndicatorState.locking` 保持普通内容，`presenter.collapse` completion 后才提交 `.locked`；`NotchView` 顶边固定 | 原版普通收起与 badge 展开之间的精确间隔/曲线 |
| 解锁先显示开锁状态/动画，再收起锁状态，最后恢复音乐 | 用户实测；`LockActivityGlyph` 的 `lock.top` 分体；复刻 0.8s unlock task；`100184060`/`100186a7c` 的可见性/transition 链 | `.unlocking` 保留 open glyph 并立即 orderOut/detach 音乐卡；0.8s 后 `.restoring` 恢复最新媒体，0.12s 后 `.hidden` | 原版 unlock glyph 与内容恢复的精确帧时长 |
| 卡片入场为 spring 节奏 | `1001866a4.c` 可读 spring `init(0.6,0.3)` + delay `0.075`；`isHidden` 分支 spring `0.25,1.0` | 保留既有 `LockMusicView` spring `.6/.3` delay `.075` 与 `LockScaleAndFade` 的 source/revival `.25/.95` 过渡 | 原版 `.25/.95` 是否逐帧保持 |
| Glass 材质不是自造渐变/遮罩 | `100131c1c.c` material HUD(13), blending behindWindow(0), active, emphasized, continuous clip；fallback 未设 appearance | 保留这些路径；移除复刻自加 `darkAqua` 和白色 stroke | 原版壁纸亮度/ColorScheme 分支的真实颜色 |
| 当前 Valora 向下拉出再回顶部 | 用户实测；旧路径同时改 `isSessionLocked`/`expanded`/异步 `lockNotchMounted` | `showsMusicActivity` 在 `.locking` 和 `isSessionLocked` 下仍保留；WindowCoordinator 在 locking 不隐藏普通面板；panel frame 不动 | 真实屏上的最终帧观感 |

没有可读的原版动态录屏覆盖锁/解完整路径；因此上表只把用户实测作为动态顺序依据，把 decompile 作为结构/材质依据，不把复刻 delay 或 spring 冒充原版精确值。若用户补给同壁纸原版录屏，才可进一步做逐帧对照。

## 3. 阶段状态与取消时序

`Sources/ReferenceCore/LockIndicatorState.swift` 新增：

- `.hidden`
- `.locking`：普通内容仍在，正在完成收起；badge 未显示。
- `.locked`：锁 badge 和锁屏音乐卡稳定显示。
- `.unlocking`：开锁分体 glyph 显示，锁屏专用卡已经移走。
- `.restoring`：badge 不再显示，普通音乐恢复，短暂 settle 后 finally hidden。

每个转移带 generation/token；`showsBadge` 只在 locked/unlocking 为真，`isLocking` 只用于允许普通内容在收起阶段留存。

### 锁定

1. 收到真实 lock edge，播放边沿声音（仍受设置/epoch 控制）。
2. `model.isSessionLocked=true`，`LockIndicatorState.beginLocking()`；`showsLockActivity=false`，普通音乐仍通过 `showsMusicActivity` 渲染。
3. 取消 Quick Peek，调用现有 `PresentationController.collapse(completion:)`；如果已经 collapsed，completion 立即完成。
4. completion 检查 session epoch、状态 token；只有当前 locking 且仍锁定，才 `completeLocking`。
5. 提交 `.locked` 后，`LockMusicState` 才可以根据真实媒体/暂停/600 秒策略显示锁屏音乐卡；notch 挂载由 `lockNotchMounted`/当前 provider 完成。

因此 expanded/peek/歌词高度不会在 badge 出现后残留；顶边由 WindowCoordinator 固定 panel frame 保持。

### 解锁

1. 收到 unlock edge，播放 unlock 声音（设置/epoch）。
2. `.locked → .unlocking`；立即 `orderOut` 并 `detachWindowNumber(panel.windowNumber)` 锁屏专用音乐窗口，保留顶部 notch 的 open glyph。
3. 0.8 秒复刻解锁阶段后 `finishUnlockToRestoring`：`model.isSessionLocked=false`，进入 restoring；普通音乐以当前最新 title/artist/artwork/playing 重新渲染，不替换成冻结快照。
4. 0.12 秒 restore settle 后 `finishRestoring → hidden`；notch 解除 lock badge ownership。音乐源本身没有被冻结；模型订阅继续更新。
5. 若用户在 locking 完成前 unlock：force hidden、恢复普通呈现、旧 collapse completion token 失效，不会把 badge 补回。
6. 若 locking 期间快速 relock/unlock：旧 completion 和旧 epoch 都被 token/epoch 拒绝；睡眠/停止取消 unlock/restore task。
7. Reduce Motion 仍走相同的有界 completion 顺序；没有为了减少动画绕过状态收尾。

### 动画实现边界

- badge 阶段的 SwiftUI 内容切换使用 `withAnimation` 的复刻 spring `.45/.2`；仅复刻 glyph 已有参数，不是原版精确证据。
- 锁屏卡自身继续使用源/复刻的入场 spring `.6/.3`、delay `.075`，以及既有 `LockScaleAndFade` 的 `.25` 入场 / `.95` 离场；没有改卡片尺寸、字号或控制位置。
- 普通音乐与 badge 的顶部内容只在阶段边界用 opacity transition 替换；形状/宽高由同一 `NotchShape`/固定 panel frame 过渡，顶边不移动。
- 没有为动画新增 `asyncAfter` 平行状态机；锁定 completion 来自 `PresentationController`，解锁/restore 用同一个可取消 scheduler token。

### 保留 R1 的所有权修复

解锁时音乐面板的 detach 仍发生在 `.unlocking` 开始，而不是 `detachNotchIfNeeded` 的错误位置；顶部 notch 保留到 open glyph 阶段结束。R1 的独立回归 `testIndependentUnlockDetachesMusicAndInformationWindows` 保留并通过。

## 4. 锁屏音乐卡材质

### 已改

`Sources/Valora/LockFrostedBackground.swift`：

- 保留 `.hudWindow` material、`.behindWindow` blending、`.active` state、`isEmphasized=true`、continuous corner clip、masksToBounds。
- 移除复刻附加的 `view.appearance = NSAppearance(named:.darkAqua)`。`100131c1c` fallback 没有该设置；强制深色会改变 behind-window 材质采样，是用户看到底色不对的可证差异。

`Sources/Valora/LockMusicView.swift`：

- 移除 `RoundedRectangle(...).stroke(.white.opacity(0.15), lineWidth:0.5)` 复刻附加描边。`100186a7c`/`100131c1c` 的可读 fallback 路径没有这层白色 overlay；它会在卡片边缘/底色上叠色。
- 保留 345pt 卡、16/14 内边距、28pt 复刻圆角、白色内容与 `.colorScheme(.dark)`，没有改变布局、字号、图标、控制位置、声音资源或耳机链路。

### 仍未知

原版锁屏卡会根据壁纸亮度/ColorScheme 和动态采样做更多颜色处理（`100187f28` 等有 `isWallpaperNearlyWhite` 路径）；本轮没有读取/修改用户壁纸，也没有真实登录界面截图，不能宣称材质已 1:1。当前只按可证差异移除了复刻自加的 appearance 和白色 overlay，真实颜色仍需同一壁纸下的一次原版/Valora 对照。

## 5. 测试

运行：

```text
swift test --filter 'LockMusicStateTests|LockMusicCoordinatorTests'
```

结果：**26 项通过，0 失败**。

新增/保留的隔离测试包括：

- `LockIndicatorState` 的 locking→locked→unlocking→restoring→hidden 顺序、`showsBadge/isLocking` 和 stale token。
- `LockMusicCoordinatorTests.testLockWaitsForBoundedNormalCollapseBeforeShowingBadge`：锁定阶段保持普通音乐、badge 等到 collapse completion、fake panel 顶边原点不变。
- `LockMusicCoordinatorTests.testUnlockShowsOpenGlyphThenRestoresNormalMusicBeforeBadgeHidden`：unlocking 阶段普通内容仍保持锁定，音乐面板立即 detach，0.8 后 restoring、0.12 后 hidden。
- `LockMusicCoordinatorTests.testRapidLockUnlockRejectsStaleLockCompletion`：旧 collapse completion 不复活 badge。
- R1 的 unlock detach/indicator regression、旧 epoch callback、当前 notch 重绑、信息 Published、nowPlaying 门控、固定 deadline 和 sound spy 均保留。
- 所有 coordinator 测试使用 fake window/factory、fake Space、fake event source、fake scheduler、fake notch provider、sound spy、注入时钟和 session；没有 NSWindow/NSHostingView/真实通知/Space/NSSound 或真实等待。
- 未运行 `--verify-*`、真实窗口测试、批量截图/闪窗/性能测试或全量。

日志与清单：`docs/verification/v0036-r2/targeted-tests.log`、`source-manifest.json`、`build-verification.json`、`resource-check.json`、`codesign-display.txt`。

## 6. 构建、签名、候选

- 一次 `scripts/build.sh --output-dir /private/tmp/valora-v0036-r2-transitions-candidate` Release 构建/打包。
- arm64，macOS 27.0，ad-hoc hardened runtime，`codesign --verify --deep --strict` 通过。
- 候选二进制 SHA-256：`f799bbffaef4b7741367c108cccee2bc1235379af54778fb88ba05863734d171`。
- `lock.caf`：`bae768098424a94a5d8fb096e71b128dec61b22a4bcff7490b81e2784e255306`
- `unlock.caf`：`01c26c9afa276e9cf104b12586ad88d59fc8833f3b228f488bdda38694a36251`
- 候选未启动；用户当前运行版和 `dist` 未替换。

## 7. 需要一次实机核验的内容

建议用户方便时只做一次、同一壁纸下：

1. 启动候选，保持已有正常音乐和暂停/播放状态。
2. 真实锁定一次，观察刘海是否只在顶部先收起普通内容、再展开锁状态，不向下拉出。
3. 真实解锁一次，观察 open glyph 是否先出现、锁屏卡是否立即消失、正常音乐是否在 glyph 后恢复。
4. 在同一壁纸下对照原版和候选的锁屏音乐卡底色/边缘，不调整壁纸、不连续锁解、不批量截图。

真实登录界面可见性、点击、真实声音、设备 tile、物理多屏和材质颜色仍应列为待验；本轮 fake 测试和源码审查不冒充这些实机结果。
