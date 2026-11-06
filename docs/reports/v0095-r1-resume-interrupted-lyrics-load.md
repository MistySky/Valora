# V0095-R1：恢复被隐藏打断的同曲歌词加载

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`。
保留 V0095 已认可的主修复（统一歌词需求面、共享 Controller/Provider/缓存、提交校验），**未改** UI/动画/玻璃/锁屏布局/顶部两行/图标；未 Git 提交。

## 一、失败边界

独立验收新增 `testInterruptedLoadingResumesWhenSameLockCardReturns` 1 case 2 断言失败：

```
loading 中卡片隐藏 → 取消在途请求并置 unavailable（currentIdentity 仍是 A）
卡片回来仍是 A → identity == currentIdentity 直接 return
→ 永久没有歌词，直到换曲
```

## 二、最小修复（只放开"因需求消失而中断"这一种）

`LyricsController` 新增 `interruptedIdentity: LyricsTrackIdentity?`：

1. **仅当**在无表面分支里取消的是**正在 loading** 的请求时，记录 `interruptedIdentity = currentIdentity` 并置 `.unavailable`；
2. 请求前判断改为：
   ```swift
   if identity == currentIdentity, interruptedIdentity != identity { return }  // 成功态/失败态都不重试
   cancelCurrentTask(); generation &+= 1
   currentIdentity = identity; interruptedIdentity = nil
   ```
   即同曲只有"被需求消失打断"的那一次可以恢复，恢复后标记清空；
3. `cancel()` 一并清空 `interruptedIdentity`。

保留行为：
- 已成功同首跨锁/显隐 → `status == .ready`、`interruptedIdentity == nil` → 不重复请求；
- 3s 超时/接口失败 → `.unavailable` 但 `interruptedIdentity == nil` → 同首元数据轮询不重试；
- 隐藏期间换曲 → 回来时 identity≠currentIdentity，直接请求新曲，不会带出旧曲歌词；
- 快速换曲仍按代次拒绝旧结果；关开关清空并取消；未新增第二个 Provider/服务。

## 三、验证（无窗口，注入 fake）

| 套件 | 数量 | 结果 |
|---|---|---|
| `LockLyricsTrackChangeTests` | 8 | 通过（含原失败的"中断恢复"与新负例"超时后元数据轮询不重试"） |
| `IndependentLyricsDeadlineTests` | 2 | 通过 |
| `LockMusicCoordinatorTests` | 32 | 通过 |
| 合计 | **42** | 0 失败 |

新增负例 `testTimeoutDoesNotRetrySameTrackOnMetadataChurn`：budget 0.05 触发真实超时 → 状态 `.unavailable`，随后连续 4 次 `mediaMetadataChanged()` 同一首，请求次数不变。

## 四、构建 / 单实例替换

- 候选：`/private/tmp/valora-v0095-r1-interrupted-load-candidate/Valora.app`
- binary SHA-256：`db7ef9c9a4a5a8c195a9443097f9fc028a9b41d15e795e47d24940ba82ad6e52`
- `codesign --verify --strict --deep` 通过；`dist/Valora.app` 未动
- 替换：pkill 至 0 → `open -n` → 复查**仅 1 个进程**，路径 `/private/tmp/valora-v0095-r1-interrupted-load-candidate/Valora.app/Contents/MacOS/Valora`（PID 66490）

## 五、仍待真实确认

真实锁屏下"卡片隐藏/再次出现"的中断恢复、真实网络延迟与缓存命中仍需用户实机复核；本轮只证明门控与生命周期在 fake 下正确。
