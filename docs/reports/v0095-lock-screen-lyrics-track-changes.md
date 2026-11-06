# V0095：锁屏换歌歌词请求与生命周期

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，分支 `codex/music-display-lock-policy`。
未改锁屏玻璃、顶部锁解、Space、音量、头像位置、顶部两行对齐、菜单图标与 Codex 额度逻辑；未恢复歌词折叠；未 Git 提交/推送。

## 一、问题与根因（静态控制流 + fake 回归）

`LyricsController.update()` 把 `model.showsMusicActivity` 当作"需要歌词"的条件，而 `AppModel.showsMusicActivity` 在真实锁屏稳定阶段恒为 `false`（`!isSessionLocked || isLockTransitioning`）。于是：
- 锁中换歌 → 身份变 `nil` → 清空 timeline，且不再请求下一首；
- 请求成功回调同样要求 `showsMusicActivity` → 锁中结果被丢弃；
- `visibilityChanged()` 以桌面 `screenHidden`/`showNotch` 取消所有请求，完全没有考虑锁屏音乐卡。

这与用户实测"锁屏后切歌没有歌词"一致。

## 二、最小修复

1. **统一"需要歌词的表面"**：`surfaceNeedsLyrics = 普通刘海可用（showNotch && !screenHidden && showsMusicActivity） || 实际锁屏音乐卡可见`。
   新增 `AppModel.lockMusicCardVisible`（`@Published`），由 `LockMusicCoordinator.applyVisibility`/`stop` 与真实卡片显隐同步。
2. `LyricsController.update()` 重写门控：
   - `enabled = nowPlayingEnabled && showLyrics && hasTrack`，不满足 → 取消并清空；
   - `enabled` 但**无表面** → 取消在途请求、保留已加载 timeline（表面回来同一首不重复请求）；
   - 有表面 → 身份 = 当前曲目，正常请求/缓存；
   - 提交（成功与失败两条路径）统一检查 `nowPlayingEnabled && showLyrics && surfaceNeedsLyrics && 代次 && 身份`，锁中结果可以提交，迟到/旧代次结果仍拒绝。
3. `visibilityChanged()` 不再直接取消，而是交给 `update()` 按统一规则判断 —— 桌面隐藏不再打断可见锁屏卡的需求。
4. 订阅新增 `model.$lockMusicCardVisible`；锁屏总开关/卡片显隐/空闲策略仍由协调器决定卡片是否可见，因此歌词需求自动跟随；音乐总开关、显示歌词开关、`showNotch`、`screenHidden` 语义保持。
5. 未新增第二个请求器：锁屏与刘海共用同一个 `LyricsController`、同一个 Provider、同一个缓存与真实播放锚。

## 三、定向验证（全部使用注入 fake，无真实网络/切歌/锁屏）

新增 `Tests/ValoraTests/LockLyricsTrackChangeTests.swift`（6 项）：

| 用例 | 断言 |
|---|---|
| `testLockedTrackChangeRequestsTheNewSongAndShowsLyrics` | 锁中（`isSessionLocked = true`，`showsMusicActivity == false`）换 A→B：请求 A、B，timeline 为 B |
| `testSameSongAcrossLockAndUnlockIsNotRefetched` | 锁屏进出同一首：请求次数恒为 1，已加载 timeline 不变 |
| `testHiddenNotchDoesNotCancelTheLockCardDemand` | `screenHidden = true` 但锁卡可见：仍请求且 timeline 有效 |
| `testHiddenCardStopsDemand` | 卡片隐藏后再换歌：不再发新请求 |
| `testFastTrackChangesCommitOnlyTheNewestResult` | 慢 provider 下 A→B→C，只提交 C |
| `testLyricsSwitchOffClearsAndStops` | 关闭音乐总开关后清空并停止请求 |

本轮实际执行（逐套件）：

| 套件 | 数量 | 结果 |
|---|---|---|
| LockLyricsTrackChangeTests（新增） | 6 | 通过 |
| IndependentLyricsDeadlineTests | 2 | 通过 |
| LyricsCacheTests | 4 | 通过 |
| LyricsServiceTests | 17 | 通过 |
| IndependentCodexTransportTests | 4 | 通过 |
| CodexUsageSummaryTests | 14 | 通过 |
| LockMusicCoordinatorTests | 32 | 通过 |
| LockMusicStateTests | 13 | 通过 |
| LockCardAppearanceTests | 4 | 通过 |
| 合计 | **96** | 0 失败 |

未跑全量、未闪窗/截图循环/性能审计、未运行会创建真实窗口的 MultiDisplay/Interaction 套件。

## 四、构建 / 单实例替换

- 候选：`/private/tmp/valora-v0095-lock-lyrics-candidate/Valora.app`
- binary SHA-256：`45f76764c4f49f7fc526b3d4b280c332f8f9055ed1da3783a2dc6ae38d6df982`
- `codesign --verify --strict --deep` 通过；`dist/Valora.app` 未动
- 替换：pkill 至 0 → `open -n` 候选 → 复查**仅 1 个进程**，路径 `/private/tmp/valora-v0095-lock-lyrics-candidate/Valora.app/Contents/MacOS/Valora`（PID 63157）

## 五、仍待真实验证

真实锁屏下换歌的歌词更新（含网络延迟、缓存命中、3 秒预算与真实播放锚）仍需用户实机确认；本轮只证明门控与生命周期在注入 fake 下正确，不冒称实机通过。
