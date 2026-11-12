# 桌面律动/歌词恢复修复（2026-11-09）

分支：`codex/lock-screen-idle-cpu`，保留 build45 的未提交进度隔离/锁屏改动；未提交或推送 Git，未合并 main。

## 一、已复现的律动缺口

`Tests/ValoraTests/IndependentWaveformReturnTests.swift` 的独立失败：`CompactWaveformView` 在窗口仍隐藏时 configure(playing:true)，时钟因 `window.isVisible == false` 不注册；随后只 `orderFrontRegardless()`，没有额外 configure，时钟仍不恢复。旧测试在 orderFront 后手动 configure，掩盖了这个生命周期缺口。

修复：`CompactWaveformView.viewDidMoveToWindow` 对所属窗口的 `isVisible` 建立 KVO 观察；orderOut/orderFront 事件到达时用**当前** playing/reducedMotion/suspended 重新 `synchronizeTimer()`。不恢复 AppModel 全局 4Hz 广播，不新增轮询、不每帧 configure、不改变窗口/Space/点击穿透。多屏每个 native view 观察自己的窗口。

KVO 可能不是所有 AppKit 窗口行为的最强保证，但本轮隔离测试证明 borderless 离屏窗口 orderFront 可触发；仍保留 `windowOnScreen` 在 tick 内的自愈门控。

## 二、歌词问题排查

本轮没有在无额外操作下复现“同曲歌词偶发不显示”。已核对：

- `ExperimentalDesktopLyricsView` 的 active 仍由调用方显式提供；桌面用 `notchSurfaceOnScreen`，锁屏用 `lyricsActive`，没有混用；
- 同 identity 重挂时 `host.begin` 不重置 generation，旧 generation 回调仍被拒绝；
- `NativeLyricsRowView.apply` 在 remount/active 恢复时从 snapshot 重新对齐当前行和时钟；`setActive(false)` 会 shutDownClocks；
- 空行→非空行/换句仍走 onLineChange/boundary wake；没有发现必须同时改歌词的已证实缺口。

因此本批只修复已证实的 waveform 生命周期缺口，不把歌词未复现问题宣称同一根因。剩余假设：宿主在极端时序下丢失一次 line 回调、或 active 状态与窗口实际 orderFront 的边界未覆盖。已保留为后续有证据时的定向诊断，不添加 Release 日志/全屏监听。

## 三、验证

- `IndependentWaveformReturnTests`：1 项通过（原失败回归）。
- `PlayingWaveformLifecycleTests`：2 项通过。
- `DesktopPlayingCadenceTests`：6 项通过。
- 既有实验/普通歌词、锁屏 active、进度隔离、seek/换句相邻定向测试继续通过；未做批量闪窗、反复 orderOut/orderFront、压力或真实播放。

## 四、候选

- `/private/tmp/valora-waveform-return-20261109/Valora.app`
- `1.0.3 (46)`
- binary SHA-256：`d1f0ba36b74eb2f74a7868656e58dedd99622b354aec179ab45b520bceccbd24`
- strict/deep 签名通过
- build45 已正常退出，当前唯一 build46 实例 PID `69080`
- build45 保留在 `/private/tmp/valora-lock-refresh-scope-20261109/Valora.app`

## 五、未验

- 用户日常偶发是否完全消失，需要用户不点击刘海观察真实播放；本批只证明一个确定的 orderFront 缺口已修。
- 歌词不显示若仍出现，不能归因于本批 waveform 修复；需要用户实测并抓取最小状态/栈。
- 真实锁屏/多屏/真实媒体、暂停/减弱动态视觉未由自动测试覆盖。
