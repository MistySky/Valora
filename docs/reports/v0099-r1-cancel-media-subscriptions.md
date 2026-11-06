# V0099-R1：停止时取消媒体订阅（避免跨周期累积）

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，分支 `codex/final-cleanup`。
只修 `MediaController` 的订阅生命周期；未改媒体链路、epoch/generation 语义、源停止/清理行为，也未动已接受的 UI/玻璃/焦点/动画/位置与游戏链路移除。未 Git 提交。

## 一、失败点

独立用例 `IndependentMediaScheduleLifecycleTests`：`start → stop → start → nowPlayingEnabled=false` 时一次关闭实际调用 `source.stop` **2 次**（预期 1）。

原因：`stop()` 只停 tick、`invalidate()`，**没有取消 `subscriptions`**；下一次 `start()` 又注册一条 `nowPlayingEnabled` 订阅。旧订阅仍在，偏好变化时两条都执行，`invalidate()` 被调用两次；周期越多累积越多。

## 二、修复（仅生命周期）

```swift
func stop() {
    guard isActive else { return }   // 重复 stop 不触碰另一个周期
    isActive = false
    commandGeneration &+= 1
    stopTick()
    invalidate()
    subscriptions.removeAll()        // 取消本周期订阅（旧回调不再处理偏好）
    system.onSnapshot = nil
    system.onError = nil
}
```

- `start()` 原有的 `guard !isActive` 保留：重复 start 不叠加调度；
- 新周期注册自己的订阅，读取的是**当时**真实开关；
- `applyNowPlayingEnabled` 仍有 `isActive` 守卫，停止后的偏好变化不调源、不重启 tick；
- 媒体 epoch/generation、`invalidate()` 的源停止与状态清理语义未变。

## 三、定向验证（fake 调度 + fake 源，无窗口）

| 套件 | 数量 | 结果 |
|---|---|---|
| `IndependentMediaScheduleLifecycleTests`（原失败） | 1 | 通过（一次关闭 = 一次 `source.stop`） |
| `MediaScheduleTests`（含新增"三个 start/stop 周期后一次关闭仍只停一次"） | 5 | 通过 |
| `RevivalSettingsReloadTests` | 5 | 通过 |
| `LockMusicCoordinatorTests` | 32 | 通过 |

新增用例覆盖：多次周期无累积、关闭后仅一次停止、`liveCount == 0`、stop 后偏好变化不重启；既有用例仍覆盖"启动即关闭 0 tick / 开启 1 tick / 重复 start 不叠加 / stop 后改偏好不重启"。

未跑全量、未做性能/资源审计、无真实媒体或锁屏操作。

> 数量更正（V0100）：`MediaScheduleTests` 实为 **5** 项（不是 6），独立验收记录为 11 项相关测试。

## 四、Release 交付

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0099-r1-media-subscriptions-candidate/Valora.app` |
| 版本 / 构建号 | `0.2.0` / **8**（`build-verification.json` 同为 8） |
| binary SHA-256 | `203363338181fbcf3d41b9f3363c8abc34cc82c11d30b472badfd5fe7bacd024` |
| 签名 | `codesign --verify --strict --deep` 通过 |

替换：AppleScript `quit` 正常退出 build 7 → 复查 0 实例 → `open -n` 新候选 → 复查**仅 1 个进程**（PID 15445）；未用 pkill；`dist` 未覆盖。

## 五、未做

无用 View/外观字段、摘要无障碍、验证代码编译边界与文档整理仍留给后续批次；未提前做性能/唤醒专项。
