# V0098-R1：跨 Surface 共享激活生命周期 + 未知锁态保守化

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，分支 `codex/final-cleanup`。
保留 V0098 的激活动作、玻璃材质（darkAqua/variant 5）、动画、UI、位置、歌词/音量；未删任何独立失败断言。未 Git 提交。

## 一、失败复现与根因

独立用例 `IndependentLockActivationLifetimeTests` 场景：`card.acquire → preview.acquire → card.release`，此时 preview 仍持有，但策略已被恢复成 `.accessory`、旧应用也被激活 —— 2 条断言失败。

根因：V0098 里每个 surface 各自 `LockActivationOwner.makeProduction()`，**私有 depth 不共享**；先退出的那个把自己的 owner 引用计数归零就恢复了策略。

## 二、修复

1. **共享生命周期**（`Sources/Valora/LockActivationOwner.swift`）
   - 新增 `LockActivationRegistry`：持有共享 depth、首次捕获的原策略与进入前应用，**最后一个 scope 退出**才恢复；
   - `LockActivationOwner` 变为"单个 surface 的 scope"：内部仍有自己的计数（每 surface 防重复进入、可嵌套），只在最外层进出时触碰 registry；
   - 生产：协调器与 `LockCardPreview` 都用 `LockActivationOwner(registry: .shared)`；未持有就 release 只记 `not-owned`，不碰策略；再次进入重新捕获；"进入时已是 `.regular`"（别人已抬起）→ 不记录、退出不擅降。
2. **未知锁态不再当作已解锁**
   - `Hooks` 增加 `sessionLockIsKnown`；生产通过新的纯函数 `LockActivationRegistry.lockState(from:)` 读取：缺 session、缺 key、值不是 Bool/NSNumber 一律 `nil`（未知）；
   - 未知时只恢复策略，**不**激活旧应用，原因记为 `policy-restored; previous app not activated (lock state unknown)`。

## 三、同轮文案

`LockGlassSurface`、`LockCardPreview`、协调器 `present()` 里"只在 key 窗口才有玻璃 / 原版同样约束"一类绝对说法，改为"本实现观察到的表现 + 真实锁屏待验"，未改材质与激活动作。

## 四、定向验证（无窗口，fake 钩子）

`LockActivationOwnerTests` 14 项 + `IndependentLockActivationLifetimeTests` 1 项 = **15 项通过**，覆盖：

| 用例 | 断言 |
|---|---|
| 卡先退、预览后退（独立用例，断言原样保留） | 卡退出后仍 `.regular`、不激活旧应用；预览退出才恢复且只恢复一次 |
| 预览先退、卡后退 | 同样只在最后退出恢复一次 |
| 重复 release | 不重复恢复（`not-owned`）；随后新周期重新捕获 |
| 单 owner 嵌套 acquire | 内层 release 仍保持 `.regular`，外层 release 才恢复 |
| 未知锁态（`sessionLockIsKnown = false`） | 策略恢复，**不**激活旧应用 |
| 锁态解析纯函数 | `nil` session / 缺 key / 字符串 → `nil`；`true`/`false`/`1` 正常 |
| 既有 8 项 | 重复进入、未持有、已 regular 不记录、锁屏不激活、用户切走不抢焦点、应用退出、快速进出平衡 |

回归：`LockMusicCoordinatorTests 32`、`LockCardLayoutTests 13`、`LockLyricsTrackChangeTests 8` 全部通过。

## 五、Release 交付

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0098-r1-shared-lifetime-candidate/Valora.app` |
| 版本 / 构建号 | `0.2.0` / **5**（自动分配，`build-verification.json` 同为 5） |
| binary SHA-256 | `10b90acfc65fe93d6cfba26fc18c886d7c5807be4104d6bf7b0105ff897a8ed9` |
| 签名 | `codesign --verify --strict --deep` 通过 |

替换：`osascript -e 'tell application "Valora" to quit'`（正常退出，**未使用 pkill**）→ 复查 0 实例 → `open -n` 新候选 → 复查**仅 1 个进程**（PID 6584）；`dist` 未覆盖。

## 六、边界

真实锁屏/登录下的"恢复先前应用"仍未实机验证；本轮只证明共享所有权、逆序退出、未知锁态保守化在注入钩子下正确。不声称密码焦点问题已解决。
