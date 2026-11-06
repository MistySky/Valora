# V0036-R4 收起阶段 Space 所有权与真实动画 completion 报告

日期：2026-10-29
状态：限定返修完成，等待 Codex 独立验收；真实锁屏动画、真实壁纸材质和物理多屏仍未实机验收。
候选：`/private/tmp/valora-v0036-r4-completion-candidate/Valora.app`
候选二进制 SHA-256：`d07b9112b1b72784a22b72484a3ecae88bbfd69cab656ff5cf74bf22f7da70cd`

## 1. 结果

R3 的两个独立失败已修复，且没有删除有效所有权断言：

1. **锁 badge 未出现前的阶段也拥有自媒体 Space**：`.locking`、`.neutralizing` 不再因为 `showsBadge == false` 提前 detach notch。普通登录 Space 窗口无法证明真实锁屏可见，因此只要呈现链仍在锁定阶段，就保留进程自己的 notch Space 成员身份。
2. **解锁 neutral 阶段保留 notch 所有权**：open glyph 结束后 `.restoring` 仍保留 locked session 与 notch Space；neutral 动画完成、`finishRestoring` 成功后才释放 notch。锁屏音乐/设备窗口仍在 unlock 开始立即 orderOut/detach，不被 notch 所有权保留误拖到桌面。
3. **不再用固定 0.12 秒替代动画完成**：新增 `LockGeometryAnimating` seam。生产 `LockSwiftUIGeometryAnimator` 使用 SwiftUI `withAnimation(..., completionCriteria: .logicallyComplete)` 的 completion；收起阶段完成才推进 locked/恢复音乐。测试使用手动 completion fake，只替换动画完成信号，不替换生产 geometry/phase 决策。
4. **旧断言调整**：R4 将“open glyph 结束立即 detach notch”的旧断言改为“neutral 完成才 detach”；`detach` 仍然最终必须发生，音乐/信息窗口仍立即 detach。不是删除或放宽所有权断言，而是按用户完整 neutral 阶段修正边界。

## 2. 原失败与修复对应

### F1：neutral 阶段没有 Space 所有权

独立回归：`testIndependentLockNeutralAttachesBeforeShowingBadge`。

修前：`syncLockIndicator` 只按 `showsBadge` 挂载；`.locking/.neutralizing/.restoring` 的 `showsBadge=false`，即使几何目标已是基础刘海也没有 presentation Space 成员身份。普通用户 Space 的 notch 不能证明登录界面之上可见。

R4：

- `syncLockIndicator` 改为 `wanted = lockIndicator.phase != .hidden`；
- `.locking` 时普通内容收起，notch 已挂入 owned Space；
- `.neutralizing` 继续保留该 Space；
- `.locked` 只改变 glyph/卡片和目标几何，不经历“先丢失再重新挂载”的空洞；
- `.unlocking/.restoring` 继续保留，直到 neutral completion；
- `.hidden` 正常内容阶段才 detach；
- `stop/off/sleep/failclosed/provider change` 的 detach 仍成对清理。

回归证明 `.neutralizing` 时 `lockNotchMounted == true`，不是只给出 `geometry.compact`。

### F2：固定 0.12s 抢跑 neutral 动画

独立回归：`testIndependentNeutralGeometryRetainsNotchSpaceOwnership`，以及 R3 的几何回归。

修前：`withAnimation(.45/.2)` 提交 neutral 目标后，scheduler 0.12 就进入 `.locked`/`.hidden`；动画插值可能尚未到基础刘海就反向展开，且 notch 在 open glyph 后已被 detach。

R4：

- `LockGeometryAnimating.animate(changes:completion:)` 是唯一 neutral 几何提交接缝；
- 生产实现使用 `withAnimation(animation, completionCriteria: .logicallyComplete)`；
- completion 通过 epoch、phase、generation/token 检查后才推进；
- `.neutralizing` 完成才 `.locked`；
- `.restoring` 完成才 `isSessionLocked=false` / latest 音乐展开 / notch detach；
- 同步 completion（Reduce Motion 或没有实际动画）仍走同一阶段检查，不会留下挂起的旧 task 句柄；
- 测试 `GeometryAnimatorSpy` 在调用 `animate` 时应用 changes，但 completion 必须手动 `completeNext()`；未 complete 时不会进入下一阶段。

## 3. 逐阶段窗口所有权与内容门控

| 阶段 | notch / presentation Space | 锁屏音乐卡/设备窗口 | 内容与输入 |
|---|---|---|---|
| `.hidden` | 普通窗口归属；不保留锁 Space | 无 | 正常音乐/hover；真实未锁定 |
| `.locking` | **挂入 owned lock Space**；需要可见收起 | 无锁卡 | 普通音乐仍可用于真正收起；`isSessionLocked=true`，hover/点击/seek 被禁用；媒体更新 |
| `.neutralizing` | **保留 owned Space**；基础 `geometry.compact` | 无锁卡 | 不显示锁 glyph/music/notification/quick/output；等几何 completion |
| `.locked` | 保留 owned Space | badge + 锁屏音乐卡 | 锁屏卡按既有真实媒体门控；锁中禁止普通交互 |
| `.unlocking` | 保留 owned Space；open glyph | 音乐/设备卡 unlock 起点立即 orderOut + detach | 普通内容不恢复 |
| `.restoring` | **保留 owned Space 直到 neutral completion** | 无锁卡 | session 仍为 locked；基础几何；不显示音乐 |
| `.hidden` after unlock | 先按 neutral completion 释放 notch/锁 Space | 无锁卡 | 当前最新音乐重新展开并恢复可交互 |

- `lockNotchMounted` 对应 notch 窗口所有权；`showsLockActivity` 仍只控制锁 glyph，二者已分离。
- 锁屏音乐/信息窗口没有因为 notch 所有权保留而被保留在登录 Space。
- `WindowCoordinator.trackMouse/hover` 在 `isSessionLocked` 时拒绝进入；neutral 中 `visibleSize` 忽略 connectionToast、Quick Peek、歌词、output 高度和 expanded；`hoverScale` 固定为单位比例。
- 普通媒体模型继续更新，未冻结 title/artist/artwork/playing。恢复使用当前最新数据。

## 4. completion 与取消

- `neutralTask` 只在 compact 生产 completion 同步返回时用 0ms 调度把锁流程送入 `.neutralizing`；它不是动画时长替代。
- `.neutralizing` 的推进由 `LockGeometryAnimating` completion 完成；没有 0.12 秒 scheduler。
- `.restoring` 的推进同样由 geometry animation completion 完成；没有 0.12 秒 scheduler。
- 每个 geometry completion 检查 `isCurrent(epoch)`、当前 phase 和 generation/token。旧 callback：
  - 快速 lock→unlock：unlock 先把 phase 置 hidden/取消 neutral；旧 completion 失败；
  - stop/off/sleep：phase 被 forceHidden 或 coordinator 停止；旧 completion 失败；
  - restart：epoch 改变；旧 completion 失败；
  - 同一 completion 重复调用：phase 已推进，token 不再匹配；只推进一次；
  - 同步 completion：changes 后直接执行一次 completion，phase 已更新，没有残留 sched task/句柄。
- `unlock` 0.8 秒仍属于既有 open-glyph 动画阶段；本轮没有把它改成另一个猜测值，也没有宣称它是原版精确时长。

## 5. 生产接线与测试 seam

新增：

- `Sources/Valora/LockRuntimeAdapters.swift`
  - `LockGeometryAnimating` protocol；
  - `LockSwiftUIGeometryAnimator`：`withAnimation(completionCriteria: .logicallyComplete)`；
- `LockMusicCoordinator` 注入 `geometryAnimator`，默认生产实现；测试注入 `GeometryAnimatorSpy`。

测试 fake：

- `GeometryAnimatorSpy.animate` 应用真实 phase/geometry changes 后保留 completion；测试手动 `completeNext()`。它不创建 NSWindow/Space/真实动画。
- `LockMusicCoordinatorTests.testIndependentLockNeutralAttachesBeforeShowingBadge`：neutral 阶段 `lockNotchMounted=true`。
- `testIndependentNeutralGeometryRetainsNotchSpaceOwnership`：open glyph 后 neutral 仍挂载；geometry completion 后才 detach。
- `testNeutralCompletionIsOneShotAndOldCallbackCannotRelock`：未完成/旧 completion 不复活；单次 completion 只推进一次。
- `testSleepCancelsQueuedNeutralStage`：sleep 后旧 completion 不复活。
- `testIndependentUnlockDetachesMusicAndInformationWindows`：音乐/设备立即 detach；“notch 最终 detach”调整到 neutral 完成，断言未删除。

所有 coordinator 测试仍使用 fake window/factory、fake Space、fake event source、fake scheduler、fake notch provider、sound spy、注入时钟/session；没有真实 NSWindow/NSHostingView/DistributedNotificationCenter/NSWorkspace 通知/Space/NSSound。

## 6. 构建、签名、测试

命令：

```text
swift test --filter 'LockMusicStateTests|LockMusicCoordinatorTests'
```

结果：**34 项通过，0 失败**：

- `ValoraTests.LockMusicCoordinatorTests` 23
- `ReferenceCoreTests.LockMusicStateTests` 11

日志/清单：

- `docs/verification/v0036-r4/targeted-tests.log`
- `docs/verification/v0036-r4/test-inventory.json`
- `docs/verification/v0036-r4/source-manifest.json`
- `docs/verification/v0036-r4/build-verification.json`
- `docs/verification/v0036-r4/resource-check.json`
- `docs/verification/v0036-r4/codesign-display.txt`

构建：

- 一次 `scripts/build.sh --output-dir /private/tmp/valora-v0036-r4-completion-candidate` Release。
- arm64，macOS 27.0，ad-hoc hardened runtime；`codesign --verify --deep --strict` 通过。
- 二进制 SHA-256：`d07b9112b1b72784a22b72484a3ecae88bbfd69cab656ff5cf74bf22f7da70cd`
- `lock.caf`：`bae768098424a94a5d8fb096e71b128dec61b22a4bcff7490b81e2784e255306`
- `unlock.caf`：`01c26c9afa276e9cf104b12586ad88d59fc8833f3b228f488bdda38694a36251`
- 候选未启动；用户当前 `independent-v0036-r1` 运行包和 `dist` 未退出/覆盖/替换。

## 7. 证据边界与剩余未知

- 原版/复刻来源 hash 已列入 R4 manifest；本轮修正的锁材质函数只使用 `reverse-engineering/lock-appearance-0.6.5/100131c1c.c` 和 `100206af0.c`，不再把 `lock-screen-music` 下不存在的函数文件当证据。
- 原版锁解动态录屏未找到；0.8s open-glyph、neutral animation spring、0.12 以外的具体时长/曲线仍无原版逐帧证据。R4 的关键是 **completion 契约与 Space 所有权**，不是宣称帧一致。
- `LockMusicView` 仍使用 `.environment(.colorScheme,.dark)`；R2 的材质移除只保留为待对照改动，完整父容器/壁纸 appearance 链未证实，不能宣称卡片底色已最终解决。
- 真实登录 Space、真实锁屏/解锁、真实声音、真实设备、物理多屏和实际动画仍需用户一次同壁纸实机核验；fake completion 只证明阶段/所有权契约，不冒充实际插值帧。

## 8. 交付

正式交付后停止，不自行启动候选、不进入下一功能。
