# V0099：关闭音乐取消空转 tick + 移除无效游戏检测

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，分支 `codex/final-cleanup`。
只做这两处功能收尾；未改 UI/Alcove 动画/玻璃/布局/选屏/外接位置/歌词/耳机/Codex 日历；Objective-C/Perl 保留。未 Git 提交。

## A. 音乐关闭后不再空转 0.25s

**原状（`Sources/Valora/Controllers.swift`）**：`MediaController.start()` 无条件创建 0.25s `Timer`；`nowPlayingEnabled` 的 sink 只做 `invalidate()/clearMedia()/refresh()`，**定时器从不因关闭而停**，关掉音乐后仍 4Hz 唤醒、每秒一次立即返回的 `refresh()`。

**改法（最小）**
1. 抽出可注入的调度 seam：`MediaTickScheduling` / `MediaTickToken`，生产实现 `TimerMediaTickScheduler`（仍是 0.25s、仍是同一个 tick 体：真实播放锚 + 每 4 tick 一次 `refresh()`）；
2. `start()` 改为 `guard !isActive`（重复 start 不叠加），并按 `nowPlayingEnabled` 调 `applyNowPlayingEnabled`：开启 → `startTickIfNeeded()` + `refresh()`；关闭 → `stopTick()` + `invalidate()` + `clearMedia()`；
3. 订阅 `nowPlayingEnabled` 走同一个入口；`stop()` 一并 `stopTick()`；`isActive` 为 false 时偏好变化不再重启调度。

保留：开启时 0.25s 真实播放锚与每秒重连节奏、暂停/seek/歌词/锁屏需求与既有 epoch/generation 保护；未引入"猜时间"或额外定时器。

**定向验证**（`Tests/ValoraTests/MediaScheduleTests.swift`，fake 调度 + fake 媒体源，无真实播放器/墙钟长等待）：4 项通过
- 启动即关闭 → 0 个 tick、源未启动；
- 开启 → 恰好 1 个 tick、源启动；关闭 → tick 取消、源停止、状态清空；再开 → 仍恰好 1 个（累计 token 数 2，无叠加）；
- 重复 `start()` → 仍 1 个 tick；
- `stop()` 后再改偏好 → token 数不变、0 个存活。

## B. 移除无效游戏检测

**原状**：`ScreenStateMonitor` 每轮扫描都调用 `gameApplication()`（读前台应用、Bundle、`LSApplicationCategoryType`，再走 `GameMatcher`）；而 `Models.hideWhileGaming` 是 `private(set)` 且恒为 false（不读旧存档，`RevivalSettingsReloadTests` 已输入 true 后断言 false），`WindowCoordinator` 里 `isGaming && hideWhileGaming` 永远不成立。

**改法**
- `ScreenStateMonitor`：删除 `gameApplication()` 与 `isGaming`，状态比较只保留 fullscreen / Mission Control；
- `WindowCoordinator`：隐藏条件删去游戏项，订阅列表删去 `$hideWhileGaming`；
- 删除仅服务该链路的 `Sources/ReferenceCore/GameMatcher.swift` 与 `Tests/ReferenceCoreTests/GameMatcherTests.swift`；
- `hideWhileGaming` 属性保留（兼容旧偏好为 true 时"不生效"的既定行为），但不再有任何检测或消费；未写/迁移/擦除用户旧偏好；全屏、Mission Control 检测与其它 `NSWorkspace` 观察（音乐来源等）未动。

## C. 验证汇总（只相关无窗口）

| 套件 | 数量 | 结果 |
|---|---|---|
| MediaScheduleTests（新增） | 4 | 通过 |
| RevivalSettingsReloadTests（旧偏好忽略断言） | 5 | 通过 |
| LockMusicCoordinatorTests | 32 | 通过 |
| MusicDisplayPolicyTests | 7 | 通过 |

未跑全量、未做 CPU/内存/唤醒压力审计（按用户顺序留到全部功能修完后的专项）、未真实锁屏/媒体/设备/权限操作。

## D. Release 交付

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0099-background-cleanup-candidate/Valora.app` |
| 版本 / 构建号 | `0.2.0` / **7**（`build-verification.json` 同为 7） |
| binary SHA-256 | `97c300d2841ed509b7b75a21e5209b5db7c745da97bcf6479322b23f295c6ca5` |
| 签名 | `codesign --verify --strict --deep` 通过 |

替换：AppleScript `quit` 正常退出 build 6 → 复查 0 实例 → `open -n` 新候选 → 复查**仅 1 个进程**（PID 13144）；未用 pkill；`dist` 未覆盖。

## E. 未做

焦点/玻璃/动画已接受的改动未回退；无用 View/外观字段、摘要无障碍、验证代码编译边界与文档整理留给后续批次。
