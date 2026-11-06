# V0036-R5 用户双录屏后的窗口顶锚核查与最小修复报告

日期：2026-10-29
状态：限定返修，等待 Codex 独立验收；**真实顶部下浮根因尚未被单次窗口诊断唯一证实；29a2518... 候选已按用户“换掉重新启动”启动，待锁/解观测**。
候选：`/private/tmp/valora-v0036-r5-window-anchor-candidate/Valora.app`
候选二进制 SHA-256：`29a2518d996cddded93f9776ad394fe887e8404d8f527b166d9ebe0bb470baf3`

## 1. 用户视频证据

已读取用户授权的两段录屏派生帧，只分析顶部刘海区域，不读取/复制视频中的无关工作内容：

- Valora：`e3f0b00d7d8e3e783e7fadd915c7fa37.mp4`，1280×720/30fps；派生帧 `valora-full-5.5.png`、`valora-lock1.jpg`、`valora-unlock1.jpg`、`valora-lock2.jpg`。
- 原版 Alcove：`b0f89d1549a5b675dd1c50d20d32aa01.mp4`，1280×720/30fps；派生帧 `/private/tmp/valora-lock-video-review/lock-sequence.jpg`、`unlock-sequence.jpg`。
- Valora 第一次锁屏约 5.3–5.8s，锁 glyph 所在黑色 notch 条与硬件刘海之间出现壁纸间隙，随后回到顶部；约 15.8–16.3s 再次重复。解锁约 10.6s 也短暂出现相同分离，再回顶部显示 open glyph。
- 原版已提供的片段中，锁定时锁定状态从顶部刘海展开，未观察到相同独立下浮条；解锁后左右收回基础刘海。
- 手持运动、透视和拍摄距离不一致，不将视频像素当作 UI point，也不拟合精确 duration/spring。两段未清楚覆盖音乐重新展开和完整控制卡底色，这两项仍待验。

## 1.1 用户确认的正确展开模型

正常播放不是覆盖刘海或向下铺条，而是在同一硬件刘海顶部**左右两侧横向扩展**：基础宽度增加 liveActivity 的 74pt，顶部/高度不变，封面在左翼。锁定必须复用同一个 compact liveActivity，只把左翼封面换成锁 glyph；有音乐时先收回到基础刘海，再展开锁；解锁保持锁宽度做 open glyph，再收回基础刘海，有音乐才展开音乐。R5 早期全屏窗口方案不符合该模型，已撤销。

## 2. 代码核查结论与证据边界

### 2.1 已排除的模型几何路径

- `NotchView` 顶部内容使用 `localContour.topInset`；物理刘海分支 `NotchContour.stationary` 返回 `topInset: 0`，内容是顶部对齐的 `VStack`，没有模型驱动的垂直偏移。
- `WindowCoordinator` 的 notch panel 目标为：
  - `x = screen.frame.midX - 312`
  - `y = screen.frame.maxY - 320`
  - `width/height = 624/320`
  目标顶边等于 display frame 顶边；`EdgeHostingView.safeAreaInsets` 被置零，没有用 safe-area 下移内容。
- R4 的 locking/neutralizing/restoring 只改变 `model.visibleSize`、`NotchShape`、内容和 Space 所有权；没有 `frame.origin.y` 的 off/neutral 阶段常量。
- 锁屏音乐卡 `LockMusicPanel` 位于较低位置，且没有锁 glyph；用户视频中的条包含锁 glyph，不应误判为音乐卡。
- `ARLockPresentationSpace` 的 add/remove/show 只管理本进程窗口成员关系，没有显式 frame/transform 写入；R4 的 Space 所有权在所有非 hidden lock 阶段保持，未发现重复 notch panel 或重复 orderFront timer。

因此，“模型 geometry 目标 topInset=0 / fake frame 正确”不能证明真实屏幕位置；实际可见下浮最可能位于 **NSWindow/WindowServer 在屏幕锁定或 Space 交接时对窗口的约束/坐标处理**，但仅凭手持视频不能唯一证明。

### 2.2 本轮最小窗口修复

1. `NotchPanel` 覆盖 `constrainFrameRect(_:to:)`，返回调用者提出的 frame。notch 是程序定位的顶部边缘面板，不允许 AppKit 在登录/菜单栏/Space 过渡中把它约束到 visible frame 或下移。
2. **撤销全屏 frame 方案，改为与普通播放完全相同的小 notch panel**：锁定时不再把 panel 改成 display.frame，锁定状态只是 `NotchView` 里的 compact liveActivity 内容替换（左翼封面换成锁 glyph），顶部、高度、面板尺寸与普通播放一致。用户指出的正确行为是“基于刘海向两侧张开”，不是独立黑条/全屏。
3. `WindowCoordinator.anchorPanelTop(_:)` 在 `orderFrontRegardless` 后按当前 display 的 `frame.maxY` 重新确认普通面板顶部 frame。该操作：
   - 只在本进程 notch panel 上；
   - 只由可见性/阶段事件触发，不是重复 orderFront timer；
   - 使用的是屏幕顶边，不是视频观察出的 y 偏移、也不是经验补偿；
   - 不改变 panel 尺寸、内容布局、level、collectionBehavior 或 Space 所有权。
4. `NSWindow.didMoveNotification` 只在 notch panel 被系统移动时事件驱动地重新锚定；不是 timer/order-front loop。R4 的 `LockSwiftUIGeometryAnimator` logical completion、neutral Space 所有权、music unlock 立即 detach、epoch/token、information 发布和音乐门控全部保留；没有把本次锚定修复建立在新固定 delay 上。
5. 当前候选不再使用 R5 早期尝试的屏幕大小 LockPanel frame；如果用户实测仍有独立条，应优先检查 Space 交接/NotchPanel 窗口位置，而不是把面板做成全屏再补 y。

需要明确：这两项是**候选根因修复**，不是已由真实屏幕唯一确认的结论。若仍未消除，使用下面默认关闭的有界诊断取得真实 window/content frame，而不是继续猜 y。

## 3. 默认关闭的实机诊断

新增 `NotchWindowDiagnostic`：

- 仅当环境变量 `VALORA_NOTCH_DIAGNOSTIC` 指向路径时启用，默认关闭；
- 只记录本进程自己的 display/screen frame、safeAreaTop、menuBarHeight、panel.frame、content.bounds、phase、sessionLocked、notchMounted、windowNumber；
- 最多 120 条，事件驱动，无 timer，不枚举其他窗口/App，不读取窗口标题、账号或屏幕内容；
- 不运行于当前 R4 实例，不在用户当前 App 注入。

一次有界使用方式（由 Codex/用户协调，候选另行启动）：

```text
VALORA_NOTCH_DIAGNOSTIC=/private/tmp/valora-notch-diagnostic.jsonl \
  /private/tmp/valora-v0036-r5-window-anchor-candidate/Valora.app/Contents/MacOS/Valora
```

只锁/解一次，保留日志后退出候选。重点看 `.locking/.neutralizing/.locked/.unlocking/.restoring` 各条：
- `screen.maxY` 与 `panel.maxY` 是否相等；
- `panel.frame` 是否在阶段间向下变化；
- `content.bounds` 是否被 NSPanel/NSScreen safe area 改变；
- `windowNumber` 是否在阶段中变化（重复挂载/重建）；
- `display` 是否发生切换。

这不作为自动测试，也不声称已经运行。

## 3.1 普通音乐与锁定的实际共用几何/动画

- 普通 compact 音乐：`AppModel.visibleSize` → `PresentationMetrics.stationarySize(liveActivity: .playing)`，物理刘海宽度增加 74pt，高度仍为 `safeAreaTop`；`NotchView.topStrip` 左翼放封面。
- 锁定：同一 `AppModel.visibleSize` → `.locked`，物理刘海同样增加 74pt/同高度；同一 `NotchView.topStrip` 左翼放 lock glyph；`NotchContour` 的 active 形态也统一为音乐/锁定共用。
- 动画：普通音乐 compact 活动使用 `PresentationController.idleAnimation` 的 `spring(duration: 0.35, bounce: -0.2)`；锁定 compact 活动改用同一 `.35/-0.2` 节奏，glyph 自身的 `.45/.2` 开合动画单独保留。
- 面板尺寸/顶部：锁定不再使用全屏 panel frame，不改变 notch panel 尺寸或顶部；只是内容/活动宽度切换。
- 发现并修正的实机设置：当前用户偏好曾为 `forceSimulatedNotch=1`，导致应用走模拟刘海而非实体刘海两侧展开；已只将这一偏好设为 `false` 并重启候选，未改其他设置。

## 4. 测试与 fake 边界

命令：

```text
swift test --filter 'LockMusicStateTests|LockMusicCoordinatorTests'
```

结果：**35 项通过，0 失败**（23 coordinator + 12 state），沿用 R4 的 fake window/factory、fake Space、fake event source、fake scheduler、geometry completion、sound spy 和注入时钟。

本轮新增的是 **WindowCoordinator/NSPanel 锚定代码**，没有把 fake 的 `frame == target` 当作真实屏幕锚定证明；R5 仍需要上面的实机诊断/视觉核验。没有运行真实 NSPanel/Space/锁通知/锁解、没有播放声音/媒体控制/设备权限/系统设置/个人数据、没有 `--verify-*`、批量截图、闪窗、循环或性能压力。

已有 R4 回归继续通过：

- `testIndependentLockNeutralAttachesBeforeShowingBadge`
- `testIndependentNeutralGeometryRetainsNotchSpaceOwnership`
- neutral `visibleSize == compact`、最新音乐延后恢复、旧 completion 拒绝、音乐/设备窗口 unlock 立即 detach、notch 最终 detach。

## 5. 候选、签名与资源

- 一次 `scripts/build.sh --output-dir /private/tmp/valora-v0036-r5-window-anchor-candidate` Release。
- arm64，macOS 27.0；`codesign --verify --deep --strict` 通过。
- 候选二进制 SHA-256：`29a2518d996cddded93f9776ad394fe887e8404d8f527b166d9ebe0bb470baf3`
- `lock.caf`：`bae768098424a94a5d8fb096e71b128dec61b22a4bcff7490b81e2784e255306`
- `unlock.caf`：`01c26c9afa276e9cf104b12586ad88d59fc8833f3b228f488bdda38694a36251`
- 用户当前 R4 包已按要求由 R5 29a2518... 替换启动；`dist` 未退出/覆盖。候选进程已在运行，未做真实锁屏以外的自动测试。

## 6. 材质与保留范围

- 材质 R2 的候选改动保留，R5 没有继续改颜色/材质。
- `LockMusicView` 仍有 `.environment(.colorScheme,.dark)`；完整父容器 appearance/壁纸采样链没有通过同壁纸原版对照，不宣称底色已解决。
- 未改普通音乐/歌词/耳机/Calmon/品牌、五条锁屏设置、固定 Glass/600秒/offset0/volume 默认收起，也未恢复下载、Codex、定时器或其他模块。

## 7. 剩余实机边界

1. 用户当前 R4 视频已经证明下浮存在；R5 29a2518... 已启动，但仍需用户锁/解一次验证，不能把 `constrainFrameRect`/全屏 frame/anchor 代码称为已修好。
2. 真实登录界面/Space 下的 WindowServer 实际 frame 需要候选一次诊断或一次锁解录屏；如果 panel.frame 仍下移，诊断会区分 `constrainFrameRect`、WindowServer 重定位或 content bounds。
3. 真实锁屏动画帧、真实声音、设备 tile、物理多屏和壁纸材质仍待用户环境。
4. 原版视频现在可用作顶部动作参照；本轮没有把任何原版时长/材质结论声称为精确 1:1。

本轮 R5 候选已按用户要求替换启动；完成后停止，不继续下一功能。
