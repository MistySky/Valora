# V0036-R3 紧凑几何收起与再展开返修报告

日期：2026-10-28
状态：限定返修完成，等待 Codex 独立验收；**真实锁屏帧、真实壁纸材质、物理屏幕/多屏仍待一次用户实机核验**。
候选：`/private/tmp/valora-v0036-r3-compact-transitions-candidate/Valora.app`
候选二进制 SHA-256：`4ccc271c80a06943e23620a3d0d7797c6243693fbae499ced29aee53bbd18dbf`

## 1. 结果

R2 的两个独立失败已在生产逻辑上修复，不是只改 phase 名称：

1. **compact 音乐锁定**：不再把 `PresentationController` 对已经 collapsed 的播放器同步 completion 直接当作锁 badge 已可显示。锁定先在 `.locking` 保留/收起普通内容；即使 compact 的 collapse completion 同步返回，也先进入 `neutralizing` 基础刘海几何，再展开锁 badge。
2. **解锁**：`.unlocking` 的 open glyph 结束后进入 `.restoring` **neutral** 基础刘海，而不是立即 `showsMusicActivity=true`；neutral 完成才释放 session 音乐门控，恢复当前最新音乐并重新取得音乐侧翼。
3. **顶边测试**：不再测锁屏音乐卡 `coordinator.panel` 的 `minY`。回归改测生产 `model.visibleSize`、`model.contour.topInset` 和几何阶段；音乐卡窗口只保留所有权断言。
4. **交互/几何门控**：锁定事实保持为 `model.isSessionLocked`，呈现阶段单独由 `LockIndicatorState` 驱动；neutral 阶段抑制 connectionToast、Quick Peek、歌词、output、hover 和 expanded 几何。锁定期间 `WindowCoordinator.trackMouse/hover` 不再接受 hover，普通内容也不接受实际鼠标点击。

R2 的 Glass material 改动保留；本轮没有继续换颜色或增加遮罩。源码 manifest 的错误路径已纠正到 `lock-appearance-0.6.5`。

## 2. R2 独立失败与修复

### F1：compact 音乐直接跳过收起

Codex 回归：`testIndependentCompactMusicDoesNotSkipCollapseOnRealPresenterPath`。

修前真实路径：

- compact 音乐仍有左右侧翼，`visibleSize.width > geometry.compact.width`；
- `PresentationController.collapse` 发现 presentation 已 collapsed，立即执行 completion；
- R2 在同一调用栈直接 `.locked`，没有 neutral 基面，也没有让 compact 侧翼先收回。

R3：

- lock edge 先 `.locking`；普通内容/侧翼仍存在但交互关闭；
- `collapsePresentation` completion 后，**通过 scheduler 的 0ms 下一轮提交**进入 `.neutralizing`（避免同步快捷键把阶段跳完，也便于观察真实 phase）；
- `.neutralizing` 下 `model.visibleSize == notchGeometry.compact`，`showsMusicActivity=false`、`showsLockActivity=false`；
- 再经过 0.12s（复刻/既有 restore 值，不是原版精确证据）`completeLocking` 才进入 `.locked`。

新增生产路径回归 `testCompactProductionCollapsePathUsesNeutralBaseBeforeBadge` 直接使用真实 `PresentationController`（仅状态/SwiftUI transaction，无真实 NSWindow/锁屏/媒体控制），验证 locking→neutralizing→locked 和 neutral 尺寸。`testIndependent...` 现在通过。

### F2：解锁没有 neutral 收起

Codex 回归：`testIndependentUnlockRetractsBadgeBeforeRestoringMusicGeometry`。

R2 修前：open glyph 结束立即 `.restoring` 且 `showsMusicActivity=true`，`visibleSize` 直接是带 +74pt 音乐侧翼的尺寸（示例 259×32），没有基础刘海阶段。

R3：

- 0.8s open glyph 结束后 `.restoring`，但 `model.isSessionLocked` 仍为 true，`showsMusicActivity=false`；
- `visibleSize` 此时为 neutral `geometry.compact`；
- 0.12s neutral 收尾后才设置 `model.isSessionLocked=false`、phase `.hidden`，当前最新媒体数据重新渲染音乐侧翼；
- 顶部通知、Quick Peek、歌词、输出高度、hover 在 neutral 均不参与尺寸/轮廓计算。

`testIndependentUnlockRetractsBadgeBeforeRestoringMusicGeometry` 现在通过。测试也验证了恢复后 `series width > compact`，说明不是永久停在基础刘海。

## 3. 阶段、几何、内容、所有权与 completion

| 阶段 | 呈现几何 | 普通音乐内容 | 锁 badge / 卡片 | 输入与 completion |
|---|---|---|---|---|
| `.hidden` | 正常 music/live | 当前真实媒体 | 无 | 正常 hover/点击；无锁任务 |
| `.locking` | 先保留现有 music/expanded 形状，准备收起 | `showsMusicActivity` 仍为 true，供现有 presentation 收起；媒体订阅持续更新 | 无 badge；无锁屏卡 | 实际 session `isSessionLocked=true`，禁止 hover/seek/点击；`PresentationController.collapse` completion |
| `.neutralizing` | `geometry.compact`；无 live/notification/quick/output/expanded 高度 | 不渲染 | 无 badge；锁屏卡不可见 | collapse completion 后下一轮提交；neutral timer 0.12s |
| `.locked` | lock live activity 尺寸 | 不渲染 | badge + 锁屏音乐卡 | neutral timer 后提交；锁屏卡可交互门控按既有 |
| `.unlocking` | lock badge 尺寸 | 不渲染 | open glyph；音乐/信息卡立即 orderOut/detach | 0.8s open glyph task |
| `.restoring` | `geometry.compact`；neutral | 不渲染，session 仍锁 | badge 已退出，卡片不可见 | 0.12s neutral completion |
| `.hidden` after unlock | 当前最新音乐侧翼 | 当前最新 title/artist/artwork/playing，可交互 | 无 | 恢复完成；旧 task/token 拒绝 |

补充：

- 锁定事实 `model.isSessionLocked` 在整个张开/收起阶段保持锁定；呈现阶段单独决定内容和几何，不把“让旧内容完成收起”误解释为恢复音乐交互。
- 媒体模型没有被清空或冻结；收起后恢复使用当前模型数据。
- lock 的 `.locked` 只在 neutral timer 完成后提交；unlock 的 `.hidden` 只在 neutral timer 完成后提交。
- 快速锁→解→锁、旧 collapse completion、old neutral task、sleep/stop、总 off、同阶段重复事件都通过 epoch/phase/generation/token 拒绝或取消。
- Reduce Motion 走同一阶段语义；只影响动画提交的 spring/ease 时长，不跳过 `neutralizing/restoring`。

### 顶边锚定

回归使用生产 `model.visibleSize` 和 `model.contour.topInset`：

- lock 的 `.locking` 前后 `contour.topInset` 不变；
- `.neutralizing` 和 `.restoring` 使用 `geometry.compact`，顶层 `NotchShape` 仍由固定 WindowCoordinator panel frame 提供顶边锚定；
- 不再用锁屏音乐卡 `coordinator.panel.frame.minY` 作为刘海证明。

## 4. 原版/复刻证据与未知

- 用户实测观察仍是动态顺序的主要依据：锁前收起→锁展开；解锁开锁→收起→音乐恢复。
- `Sources/AlcoveRevival/PresentationController.swift`：已有 `collapse(completion:)` 与 SwiftUI 逻辑完成；R3 复用该链路处理 expanded 普通内容，compact 的额外 neutral 阶段由锁屏协调器局部拥有。
- `Sources/AlcoveRevival/NotchView.swift`：锁 badge / glyph 结构；现有复刻只有 hidden/locked/unlocking。
- `reverse-engineering/lock-appearance-0.6.5/100131c1c.c`：fallback material HUD(13)、behindWindow(0)、active、emphasized、continuous corner；没有设置 darkAqua。
- `reverse-engineering/lock-appearance-0.6.5/100206af0.c`：`lock.top`/`lock.bottom` 分体 glyph 依据；-24°/x+2/y-2 是复刻当前值，不是原版逐帧常数。
- `reverse-engineering/lock-screen-music/1001866a4.c`：音乐卡 spring `0.6,0.3` + delay `0.075`（可读证据）；`100186a7c.c` 有 scale/opacity transition 证据。
- **未知**：原版 neutral 几何阶段的精确 duration/curve、完整父容器 appearance/壁纸采样链、真实登录窗口逐帧效果。0.8s、0.12s、32ms、0.85s 是复刻/重建策略值，不冒充原版精确时长。
- 未找到可读原版动态录屏覆盖锁/解完整路径；没有自行锁用户电脑或录屏。

### 材质

R2 修改保留：

- 保留 `.hudWindow`/`.behindWindow`/`.active`/`emphasized`/continuous corner；
- 移除复刻自加 `darkAqua` 与白色 stroke overlay；
- 没有继续调整颜色。

但 `LockMusicView` 仍对根视图使用 `.environment(\.colorScheme,.dark)`，原版完整父容器/壁纸亮度 appearance 链尚未还原；R2/R3 不能据此宣称底色根因已最终证实。仍需同一壁纸下一次原版/候选对照。

## 5. 测试

命令：

```text
swift test --filter 'LockMusicStateTests|LockMusicCoordinatorTests'
```

结果：**31 项通过，0 失败**：

- `LockMusicCoordinatorTests` 20：
  - compact 生产 collapse 路径 locking→neutralizing→locked；
  - neutral 抑制 music/toast/output/peek/hover；`visibleSize==compact`；
  - unlock `.restoring` neutral，0.12 后才恢复最新音乐；
  - 旧 completion/rapid lock/unlock、unlock detach、notch 所有权、sound、Deadline、信息发布、旧 epoch、总开关等回归；
  - Codex 两个独立失败回归现在通过。
- `LockMusicStateTests` 11：
  - locking→neutralizing→locked→unlocking→restoring→hidden；
  - neutral 几何、stale token、固定 600 秒、sleep/wake。
- 所有 coordinator 用例使用 fake window/factory、fake Space、fake event source、fake scheduler、fake notch provider、sound spy、注入时钟/session；没有创建真实 NSWindow/NSHostingView/通知/Space/NSSound，不真实等待。
- 未运行 `--verify-*`、真实锁屏/睡眠、媒体/声音/设备/权限/系统写、批量截图、闪窗、循环或性能压力测试。

日志/清单：`docs/verification/v0036-r3/targeted-tests.log`、`test-inventory.json`、`source-manifest.json`、`build-verification.json`、`resource-check.json`、`codesign-display.txt`。

### source manifest 修正

R2 manifest 曾错误记录 `lock-screen-music/100131c1c.c` 和 `100206af0.c` 的空 hash；实际函数位于 `lock-appearance-0.6.5/`。R3 manifest 已移除无效索引，使用正确路径及非空 hash；不把不存在文件当证据。

## 6. 候选与签名

- 一次 `scripts/build.sh --output-dir /private/tmp/valora-v0036-r3-compact-transitions-candidate` Release 构建/打包。
- arm64，macOS 27.0，ad-hoc hardened runtime；`codesign --verify --deep --strict` 通过。
- 二进制 SHA-256：`4ccc271c80a06943e23620a3d0d7797c6243693fbae499ced29aee53bbd18dbf`
- `lock.caf`：`bae768098424a94a5d8fb096e71b128dec61b22a4bcff7490b81e2784e255306`
- `unlock.caf`：`01c26c9afa276e9cf104b12586ad88d59fc8833f3b228f488bdda38694a36251`
- 候选未启动；当前用户运行 `independent-v0036-r1` 包和 `dist` 未退出/覆盖/替换。

## 7. 实机待验

一次同壁纸实机对照即可补齐动态/材质：

1. 正常 compact 音乐下锁定：观察侧翼先回到基础刘海，再出现锁 badge，不向下拉出。
2. 解锁：观察 open glyph→基础刘海→当前音乐展开的边界；不要只截静态图。
3. 同壁纸下比较卡片底色/边缘；保留当前运行版，不反复锁屏。
4. 物理多屏/真实登录窗口、真实声音、设备 tile 和媒体续播仍需用户环境验证。

本轮 fake/生产状态回归不能代替上述真实帧和材质验收。
