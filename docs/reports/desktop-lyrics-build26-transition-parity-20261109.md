# 桌面刘海歌词换句：build26 连续衔接（2026-11-09）

分支：`codex/lock-screen-idle-cpu`。保留 build49 及全部未提交设置/锁屏/CPU 成果；未提交或推送 Git，未合并 main。

## 一、基线

发布源码基线为 `6c98d2b:Sources/Valora/CompactLyricsView.swift`（导出副本 `/private/tmp/valora-build26-reference/CompactLyricsView.swift`）。只称“发布源码基线”，不声称对真实 build26 二进制逐帧完全相同。baseline 的换句由 `lineKey` 触发 SwiftUI transition：新句 offset+26/opacity 0→1，旧句 offset-26/opacity 1→0，外层 `.easeInOut(0.2)` 同时迁移宽度/居中/note 布局。

## 二、定位到的衔接问题

旧实验外壳：

- 外层用 `transitionWidth = max(新句宽度, 旧句 viewportWidth)`，transition 结束移除旧句后才收窄，末尾可能跳位；
- 新旧行都按新句 `isLong` 决定整个 HStack 对齐，长短切换先变/后跳；
- 用 60Hz Timer 每帧发布 incoming/outgoing offset/opacity，虽然时长单调，但呈现节奏不等同 SwiftUI 动画事务；
- 初次发布新行时，若初始 26/0 状态未先渲染，旧行/新行可能有一帧位置或透明度错误。

## 三、修改

`Sources/Valora/LyricsRowExperiment.swift`：

- 生产桌面切句改为一次 SwiftUI `withAnimation(.easeInOut(0.2), completionCriteria:.logicallyComplete)`，由一个短的 main-queue handoff 让初始 26pt/0 opacity 先落地；不再有生产 60Hz Timer。
- 旧句仍使用 `NativeLyricsStaticLine` 冻结快照，不重建文字/图片、不启第二个时钟；一个 live native 当前行 + 一个冻结旧行。
- 去掉 `max(新旧宽度)` 容器；外层用 `layoutWidth`/`layoutIsLong` 的 0.2s SwiftUI 布局动画迁移到新句宽度、leading/center 和 note 位置；不再结束后突然收窄。
- 当前行仍由 native 缓存/30Hz 时钟驱动逐字高亮和横向阅读；不恢复全局 4Hz 广播。
- 保留 build48 完整输入去重；新 anchor/seek/active/generation/active 恢复仍会更新。
- 60Hz timer 仅保留在 `debugManualTransition/debugUsesTimer` 隔离测试 seam；生产路径不启动。

## 四、验证

- `LyricsRowExperimentHostingTests` 25 项通过，包括 production/experiment endpoint keyframes、短长/长短宽度、note、OUTGOING 单实例、快速切换、失败/隐藏清理；
- `LyricsRowTransitionStaticFrameTests` 3 项、`IndependentLyricsTransitionClockTests` 8 项通过（后者为 debug timer seam）；
- 新增 `testSwitchKeyFrames` 生产 SwiftUI 起点/终点帧检查通过；`testRuntimeViewportTransitionSteppedShortAndLong` 保存中段步骤帧到 `/private/tmp/valora-transition-runtime`；
- 相关锁屏/设置/进度/去重/波形回归共 **96 Valora + 19 ReferenceCore** 通过，既有条件跳过 1 项；
- 未做真实歌曲、真实锁屏、真实多屏或用户体感验收。

## 五、候选

- `/private/tmp/valora-lyrics-transition-parity-20261109/Valora.app`
- `1.0.3 (50)`
- binary SHA-256：`01c47fdd56a073228214d9cdb9c8310870576ea10180eeefe13f202ed129c197`
- strict/deep 签名通过
- build49 已正常退出，当前唯一 build50 实例 PID `96166`
- build49 保留：`/private/tmp/valora-lyrics-lock-toggle-20261109/Valora.app`

## 六、未验

- 用户真实歌曲中的短→短、长→短、短→长连续体感；本批不能以源码/离屏帧宣称与 build26 二进制完全逐帧相同。
- 旧句冻结快照在高亮中途、seek/暂停边界及真实字体环境下的可见细节。
- 锁屏沿用原有歌词策略，不改锁屏动画；真实锁屏位置/设置卡视觉仍待用户确认。

## R1：策略隔离与生产中间帧修正

独立验收指出 build50 报告/实现的两处问题，已修正：

### 1. 桌面/锁屏策略真正隔离

新增类型化 `LyricsTransitionStrategy`：

- `.build26SwiftUI`：桌面刘海，使用一次 SwiftUI `withAnimation` + 动画的 `layoutWidth`/`layoutIsLong`；
- `.legacyTimer`：`LockLyricsRow` 显式传入，保留 build49 的 timer/旧宽度策略；锁屏不使用新 `layoutWidth`，也不使用桌面新 SwiftUI 过渡。

不再按字符串 role 猜策略；`LockLyricsRow` 与桌面调用点的策略有独立测试。锁屏策略在生产中仍走旧 timer 路径，build50 报告“锁屏未改”的错误已撤回。

### 2. 去掉固定 16ms 停顿

生产不再 `asyncAfter(16ms)`；只保留一次 `DispatchQueue.main.async` handoff，让 26pt/0-opacity 的初始状态先提交。没有额外固定空档；横向布局与竖向 host 动画在同一 line change 的 SwiftUI 更新链中开始。

`testSwitchKeyFrames` 改为同一时间原点的绝对采样，修正原先累积 delay 污染；并检查起点旧行、中段、结束后无二次收缩。该测试实际打印的采样（渲染采样有时差，不冒充精确同帧）：

- t≈0：production/experiment 都从旧行开始；
- t≈0.05：两者都仍在过渡，墨迹/位置接近；
- t≈0.10：两者都已向新行迁移，但 native/ SwiftUI 采样存在可见差异；
- t≈0.15–0.25：结束点一致。

因此本批不能宣称“生产中间帧已与 build26 二进制完全一致”；只能证明起点/终点、无末尾二次收缩、策略隔离和有限中间帧已按同一时间原点检查。

验证：相关定向 **96 Valora + 19 ReferenceCore** 通过；新增策略隔离、生产 keyframe、宽度/note/去重/锁屏回归。未提交 Git。

R1 候选：

- `/private/tmp/valora-lyrics-transition-parity-r1-20261109/Valora.app`
- `1.0.3 (51)`
- binary SHA-256：`7e8a500540f52af5ece7f1f768928e9c3c480773bdeecd00d032d32a522b8796`
- strict/deep 签名通过
- build50 已正常退出，唯一 build51 实例 PID `98904`
- build50 保留：`/private/tmp/valora-lyrics-transition-parity-20261109/Valora.app`

## R2：策略隔离与中间帧复核（未宣称 keyed-child 已完成）

### 已修正

- `LyricsTransitionStrategy` 类型化隔离：桌面 `.build26SwiftUI`，锁屏 `.legacyTimer`；
- 去掉固定 16ms handoff，改为一次主队列 commit；
- 桌面外层宽度/对齐/note 用 `layoutWidth`/`layoutIsLong` 的 SwiftUI 0.2s 布局动画；
- production host 不再启动 60Hz timer；timer 只在测试 seam；
- `testSwitchKeyFrames` 改为同一时间原点绝对采样。

### 实际中间帧（production reference vs experiment，渲染采样有时差）

日志/测试输出：

```text
t≈0.00  reference ink742/y21, experiment755/y21
t≈0.05  reference828/y15, experiment829/y17
t≈0.10  reference4032/y0,  experiment2875/y1
t≈0.15  reference5007/y22, experiment4978/y0
t≈0.25  reference4857/y21, experiment4857/y21
```

结论：起点、终点一致，t≈0.10/0.15 的墨迹面积和 y 仍有可见差异；不能宣称逐帧等价。

### 未完成的 R2 核心项（明确阻碍）

R2 要求桌面外壳恢复真实 keyed child `.id(lineKey)` + SwiftUI transition，旧句为冻结资源、新句为唯一活跃 native 行。当前实现仍是单一 native host + 手动 SwiftUI 状态动画；要改成 keyed child，必须先解决：

1. SwiftUI transition 同时保留旧/新 child 时，旧 native child 仍可能启动时钟；
2. 旧句必须替换为冻结静态资源而不是旧 native view，但报告切换发生在 native layer 已更新之后；
3. 新行 keyed child 重建与“只保留一个活跃 native 时钟”的输入去重/缓存生命周期需要新的表现层边界。

本批没有在这三个边界未解决时硬切 keyed child，也没有引入第二套时钟/翻页风格。当前 build52 仅是可回退的中间候选，**不宣称满足 R2 接受标准**。

R2 候选：

- `/private/tmp/valora-lyrics-transition-parity-r2-20261109/Valora.app`
- `1.0.3 (52)`
- binary SHA-256：`6dc34ef4f641f4e44574bb2906f425a7222626ae20b4f443f0244ef77dc77a6a`
- strict/deep 签名通过
- build51 已正常退出，当前唯一 build52 实例 PID `608`
- build51 保留：`/private/tmp/valora-lyrics-transition-parity-r1-20261109/Valora.app`

## R3：桌面 keyed child 与原版 transition

R3 已实现桌面专用行呈现 owner，不再用 incoming/outgoing offset 两套状态模拟：

### 实现

- `LyricsRowExperimentHost` 增加 `presentationID`、`presentationLineKey` 和当前 native 弱引用；
- 桌面 `keyedRow` 的 native child 使用 `.id(host.presentationID)`，真实 `.transition(.asymmetric(insertion: .offset(y: 26)+opacity, removal: .offset(y: -26)+opacity))`；父 HStack 用 `.animation(.easeInOut(duration: 0.2), value: presentationID)` 承载宽度/对齐；
- `NativeLyricsRowView` 在改写旧行图层前调用 `onLineChangeWillApply`，owner 先冻结旧行并解除其 clock/boundary wake，再发布新 presentation ID；
- 旧 native 不再参与 clock/行选择；过渡中的旧句用纯 SwiftUI `FrozenLyricsImageView`（切换当时冻结的 base/accent image、mask、offset），退场结束释放；
- 新 native child 初次 apply 直接显示绑定的新行，只注册一个 continuous clock；空行/初次挂载不会重复 handoff；
- keyed child 共享 `NativeLyricsImageCache`（text + scale + rowHeight + accent），同一行重复 seek 不重新截图；旧行 0 次，新行每真实换句至多一次；
- 失败 fallback 会停止当前 native 并释放 capture window；capture window 不随每个旧 child 重建。

### 实际 keyed 帧（production model 触发，实际采样时间）

```text
t≈0.008  ink=744  y=21.0
t≈0.051  ink=1308 y=18.0
t≈0.101  ink=5360 y=0.0
t≈0.151  ink=5317 y=0.0
t≈0.254  ink=4857 y=21.0
```

起点是旧句，中段连续移动，终点为新句；同测试同时断言过渡中只有一个 native clock、旧 native retired、结束后只剩一个 native child。短→长、短→短、长→短生命周期分别有回归。采样仍有渲染时差/抗锯齿差异，不能与真实 build26 二进制承诺逐像素一致；用户真实体感仍待确认。

### 验证

定向测试通过：

- `LyricsRowExperimentHostingTests` 27
- `LyricsRowTransitionStaticFrameTests` 3
- `LockLyricsTrackChangeTests` 9 / `LockMusicCoordinatorTests` 36
- `SwiftUITextFidelityTests`、`NativeLyricsRowPrototypeTests`、`PlaybackProgressScopeTests`、`LyricsDiagnosticsTests`、`IndependentWaveformReturnTests`、`LockCardLayoutTests`

`SettingsReductionTests` 仍有既有 3 项失败（hover 消费者、源文本 “Show lyrics”、coordinator 文本断言），本次未改设置页，未把它们算作 R3 通过。未提交 Git。

### R3 候选

- `/private/tmp/valora-lyrics-transition-parity-r3b-20261109/Valora.app`
- `1.0.3 (54)`
- binary SHA-256：`17392537212c070ab7aec7806e4fa5b2214b2651bc08218577e3aba761b3915c`
- strict/deep 签名通过
- 当前唯一实例 PID `8798`
- 回退保留：build52 `/private/tmp/valora-lyrics-transition-parity-r2-20261109/Valora.app`；build49 `/private/tmp/valora-lyrics-lock-toggle-20261109/Valora.app`
- 默认无诊断环境变量；未做真实播放/锁屏/发布/提交

R3 已实现目标机制，用户真实切歌柔顺度仍需试听确认。

## R3 review 补充：单旧行与共享准备宿主

复核指出 R3 的两处具体问题，已修正并重新出候选。

### 1. 退场旧句只保留一份可见视觉

`keyedRow` 仍保留一条旧行退场路径：

- handoff 时旧 native 冻结并 `isHidden=true`，立即停止 clock/boundary wake；
- 旧句的可见退场只由纯 SwiftUI `FrozenLyricsImageView` 承载；
- 旧 native 的 removal 不再显示，避免同时出现冻结图 + 旧 native 两份旧句；
- 新 native child 仍是唯一活跃 native clock。

`testDesktopKeyedSharedPreparationAndSingleOldVisual` 检查：退场时恰好 1 个 retired native，且该 native 已隐藏；全程只有一个实时 clock。R3KEY 采样仍有时差，不能用单帧墨迹面积证明逐像素等价。

### 2. 移除全局 64 项图片缓存，改为 owner 共享准备宿主

- 删除 `NativeLyricsImageCache`（不再静态保留全歌 CGImage）；
- 新增 `NativeLyricsTextPreparer`，由桌面 `LyricsRowExperimentHost` 持有；
- owner 生命周期内只有一个 `NSHostingView` + 一个离屏 `NSWindow`；
- 每句仍生成新的 base/accent 两张不可变图；换句不新建截图 window；
- owner `invalidate`/失败 fallback 关闭准备宿主；锁屏 legacy 路径不变。

新增回归 `testDesktopKeyedSharedPreparationAndSingleOldVisual`：三句不同文本自然切换后 `windowCreations == 1`；owner teardown 后 `windowCloses == 1`；退场旧 native 隐藏且只有一个实时 clock。

本补充后 keyed 采样（实际触发，非手动步进）：

```text
t≈0.006  ink=744  y=21.0
t≈0.051  ink=828  y=17.0
t≈0.101  ink=4697 y=1.0
t≈0.151  ink=4845 y=0.0
t≈0.252  ink=4857 y=21.0
```

中段仍与 build26 参考存在采样/时差差异，不承诺像素绝对一致；用户真实体感仍待确认。

### 验证与候选

定向通过：`LyricsRowExperimentHostingTests`（含新增共享准备/单旧行测试）、`LyricsRowTransitionStaticFrameTests`、`LockLyricsTrackChangeTests`、`LockMusicCoordinatorTests`、`SwiftUITextFidelityTests`、`NativeLyricsRowPrototypeTests`、`PlaybackProgressScopeTests`、`LyricsDiagnosticsTests`、`IndependentWaveformReturnTests`、`LockCardLayoutTests`。

`SettingsReductionTests` 仍有既有 3 项失败，未改设置页，未算入本批通过。未提交 Git。

最终 R3 review 候选：

- `/private/tmp/valora-lyrics-transition-parity-r3c-20261110/Valora.app`
- `1.0.3 (55)`
- binary SHA-256：`04b0c0dccce614f1405a3b0e1857aa08daeb079f29bc5671b88cca1f7c59277e`
- strict/deep 签名通过
- 当前唯一实例 PID `10937`
- 回退保留 build52：`/private/tmp/valora-lyrics-transition-parity-r2-20261109/Valora.app`

## R4：桌面 keyed 音符连续性（删除第二套布局状态）

独立回归暴露 build55 桌面音符起点偏左约 51px，并在切句开头反向移动。根因是 keyed 路径仍保留 R1 的 `layoutWidth/layoutIsLong/syncOuterLayout`，与父层 presentation 动画并行。

### 修正

- 桌面 `.build26SwiftUI` 删除 `layoutWidth`、`layoutIsLong`、`syncOuterLayout` 和 activeLineKey 的单独 `withAnimation`；
- child 直接使用本行真实 `resolvedWidth`，父 HStack 仅用 `.animation(.easeInOut(duration: 0.2), value: presentationID)` 管理宽度/isLong/对齐；
- 不改字体、note 宽度、5pt spacing、18pt inset、可用宽度、行高和过渡数值；
- 保留 keyed transition、唯一实时 clock、隐藏 retired native、唯一冻结旧图、owner 共享准备宿主、输入去重、锁屏 legacy、歌词开关和 44pt 位置。

### 独立 note 回归结果

`testDesktopKeyedNoteDoesNotJumpOrReverseAtLineChange` 通过：

```text
新实验 before=200 samples=[200, 187, 133, 49, 39]
原SwiftUI before=200 samples=[200, 182, 124, 63, 39]
```

起点完全一致；短→长只向左，无反向移动。参考仍是同一窗口的真实 `CompactLyricsView` 外壳。

### 自然播放 tick 回归

新增 `testDesktopKeyedNaturalTickNoteDoesNotReverse`，不 seek，使用播放时钟跨过下一句；实际采样（测试记录）：

```text
before=200
t≈0.204 x=200
t≈0.405 x=200
t≈0.601 x=66
t≈0.802 x=39
t≈1.001 x=39
t≈1.201 x=39
```

自然 tick 同样无起点跳位、无反向移动。

`testNoteAndTextPositionsMatchProduction` 已显式指定 `.build26SwiftUI`，六组位置输出 note/text 均与 production 对齐（空行 note 差 1px）。

### 验证

定向通过：`LyricsRowExperimentHostingTests` 30、`LyricsRowTransitionStaticFrameTests` 3、`LockLyricsTrackChangeTests` 9、`LockMusicCoordinatorTests` 36、`SwiftUITextFidelityTests`、`NativeLyricsRowPrototypeTests`、`PlaybackProgressScopeTests`、`LyricsDiagnosticsTests`、`IndependentWaveformReturnTests`、`LockCardLayoutTests`。未提交 Git。

### R4 候选

- `/private/tmp/valora-lyrics-transition-parity-r3d-20261110/Valora.app`
- `1.0.3 (56)`
- binary SHA-256：`cc0aaa71a458364f46f160b2eb82509bf3c8debdbcee613d2590b6b7266a1d67`
- strict/deep 签名通过
- 当前唯一实例 PID `14580`
- 回退保留 build55：`/private/tmp/valora-lyrics-transition-parity-r3c-20261110/Valora.app`；build52：`/private/tmp/valora-lyrics-transition-parity-r2-20261109/Valora.app`

真实用户体感仍待醒后确认；采样有渲染时差，不承诺逐像素绝对一致。

## R5：owner 生命周期与发布边界

build56 独立日志中的 `Publishing changes from within view updates` 已消除；owner 失效后的迟到 bridge 不再重开截图宿主。

### 修正

- `NativeLyricsRowHost.wire` 不再调用 `host.begin`；make/update 只读取当前 generation/identity 并绑定 token/callback，不同步写 `@Published`；
- 新 owner 的初始 identity/generation 通过构造期 `prepareInitial` 预留，非 published；
- 身份重置/首次激活放在外层 `onAppear`/`onChange`；同 identity 重新显示且 owner 已失效时，`begin` 重新取得 lease、恢复当前行；
- handoff 先在 native update 内冻结旧行/停 clock，再把 `presentationID`/displayedLine/frozen 图的发布延后到主队列一次安全提交，没有固定 16ms；
- 增加 `isActiveOwner` lease：`invalidate` 后旧 generation callback 被丢弃；`NativeLyricsRowHost.updateNSView` 在 owner 失效时停止 view 而不 apply、不 prepare、不 fallback；
- `NativeLyricsRowView` 在 owner preparer 不可用时直接返回，不把退出误判成图像失败；
- retired old child 由 late update 不能重新 active；共享 preparer 仅由有效 owner 打开/关闭；旧 child 拆卸不关闭新 child 使用的宿主。

### 验证

- `LyricsRowExperimentHostingTests` 31 项通过，包括新增 `testInvalidatedOwnerDropsLateBridgeAndReactivatesSameIdentity`；
- 该回归确认：invalidate 后旧 callback 不改 displayedLine、不 failed、不新建窗口；同 identity 重新 activate 后恢复 1 个 native row，无需点击；
- 全量 `LyricsRowExperimentHostingTests` 日志不再出现 `Publishing changes from within view updates`；
- 依然出现的 `image capture failed` 仅来自显式注入 `debugFailImageRender`/`failHostRender` 的失败测试；Note、SharedPreparation、自然 tick 与 owner 生命周期用例没有非注入失败日志；
- keyed 音符回归：before=200，短→长采样 `[200,195,152,85,39]`，参考 `[200,186,131,67,39]`，无反向；
- 自然 tick：`before=200`，实际约 `t=.20/.40/.60/.80/1.00/1.20` 为 `200/200/200/200/67/39`；
- 锁屏 legacy、唯一实时 clock、三句不同文本一份 capture 宿主保持；未提交 Git。

### R5 候选

- `/private/tmp/valora-lyrics-transition-parity-r3e-20261110/Valora.app`
- `1.0.3 (57)`
- binary SHA-256：`2b029442c5daae376525f00808a3777f08500b789a3685bfbb0a33a4889b0469`
- strict/deep 签名通过
- 当前唯一实例 PID `17718`
- 回退保留 build56：`/private/tmp/valora-lyrics-transition-parity-r3d-20261110/Valora.app`；build55：`/private/tmp/valora-lyrics-transition-parity-r3c-20261110/Valora.app`

真实用户体感仍待醒后确认。
