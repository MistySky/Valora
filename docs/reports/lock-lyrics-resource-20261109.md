# 锁屏歌词资源优化（2026-11-09）

分支：`codex/lock-screen-idle-cpu`（从 `codex/alcove-tracking-area` 的 `3b4dc91` 拉出）。本批未提交/推送 Git，未合并 main。

## 一、现状与嫌疑

锁屏音乐卡原本直接使用 `CompactLyricsView`。播放时它由 `TimelineView(.animation(minimumInterval: 1/30))` 驱动：每帧重新进入 SwiftUI 行布局，更新高亮 mask/横向阅读位移，并保留暂停行。桌面 26 版也走这条路径，所以流畅但播放态 CPU 较高。

桌面 build43 已使用 native 歌词实验渲染器（`NativeLyricsRow`）降低每帧准备成本，但锁屏卡没有接入。本批只把锁屏歌词接到同一底层，并补锁屏独立的 active 生命周期；不预先宣称锁屏 CPU 根因已确认，真实锁屏仍需实测。

## 二、实际修改

### 1. 锁屏独立 active

`LockMusicCoordinator` 新增 `@Published private(set) var lyricsActive`：

- 卡片实际呈现（0.032s appearance 完成且 panel 可见）后置 true；
- 退场期间保持 true，直到 0.85s hideTask 真正 orderOut 后置 false；
- `stop()`、隐藏、关闭歌词、功能关闭、解锁清理最终都会走到 false；
- 不读取桌面 `model.notchSurfaceOnScreen`。

`LockMusicView` 通过 `LockMusicCard(lyricsActive:)` 传入；桌面 `DesktopLyricsRow` 仍使用自己的 `notchSurfaceOnScreen`，两套 active 不共享。

### 2. 锁屏复用 native 歌词底层

新增 `LockLyricsRow`：

- `VALORA_LYRICS_EXPERIMENT` 编译时使用 `ExperimentalDesktopLyricsView`，即现有 `NativeLyricsRow` 的字形/图像/度量按行缓存、每帧只更新 mask/阅读偏移；
- 普通 Release 继续回退 `CompactLyricsView`；
- 宽度、字号、音符、空行居中、行高、0.2s/±26pt 换句过渡沿用现有实验行；
- 长短句宽度改为从当前显示行的同步 metrics 计算（保留工作区已有的未提交修复），不再等异步 `contentWidth`，避免先显示短句再收缩的卡顿；锁屏与桌面共用该修复。

未改卡片尺寸、位置、玻璃、配色、音量、播放器交互、锁屏布局、Space/焦点/登录区域，也未改桌面鼠标 tracking-area 路径。

## 三、验证

定向测试：

- `VALORA_LYRICS_EXPERIMENT=1 swift test --filter "LockMusicCoordinatorTests|LyricsRowExperimentHostingTests|IndependentPointerWindowStateTests"`：61 项通过，0 失败（其中实验 hosting 22 项；测试环境中 native 图像捕获有环境日志，但断言通过）。
- 普通（无实验）`swift test --filter "LockMusicCoordinatorTests|IndependentPointerWindowStateTests"`：39 项通过，0 失败。
- 新增锁屏 active 用例：呈现后独立于桌面 notch 标志；退场期间保持；0.85s 退场结束释放；stop 立即释放。

未做真实锁屏/反复锁解/CPU 压力/批量闪窗；纯状态测试不能证明真实锁屏视觉与 CPU。

## 四、候选

- `/private/tmp/valora-lock-lyrics-resource-20261109/Valora.app`
- `1.0.3 (44)`
- binary SHA-256：`a41f9f674da147570caa14bd9eb6f1647674505ec31a713e4427d4ec1a6ae9ea`
- strict/deep 签名通过
- build43 已正常退出，当前唯一 build44 实例 PID `36796`
- build43 保留在 `/private/tmp/valora-lyrics-viewport-sync-20261109/Valora.app`

## 五、未验

- 真实锁屏下的 CPU 降幅、逐字高亮、换句、长短句、空行音符居中、暂停保持、解锁清理，仍需用户实际锁屏并由 Codex 采样；本轮没有真实锁屏数据。
- 锁屏与桌面共用 native 渲染器；桌面跟踪区/鼠标优化未改，但锁屏 native 行在真实锁屏窗口/玻璃上的呈现未由自动测试覆盖。
- 若真实锁屏有视觉或时钟生命周期问题，优先回退 build43，不要继续叠加未验证的窗口/渲染改动。
