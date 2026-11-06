# V0098-R2：锁态只读一次快照

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，分支 `codex/final-cleanup`。
只修「两次锁态查询拼接」这一处；未动共享 registry 引用计数、玻璃、激活动作、UI/动画/布局。未 Git 提交。

## 一、失败点

生产的 `LockActivationRegistry.Hooks` 原来有两个 Bool 闭包：

```swift
sessionLocked:       { productionSessionLocked() == true }
sessionLockIsKnown:  { productionSessionLocked() != nil }
```

`release()` 先问"知道吗"、再问"锁了吗"，**各查一次会话字典**。若第一次返回"已知未锁"、第二次查不到（`nil`），第二个闭包按 `== true` 得到 `false`，于是仍被当作"已解锁"而激活了先前应用。独立用例 `testUnknownSecondSessionReadMustNotBeInterpretedAsUnlocked` 复现了这一点（1 断言失败）。

## 二、修复（只此一点）

两个 Bool 钩子合并为一个三态快照：

```swift
/// true 锁定 / false 解锁 / nil 未知
var sessionLockState: () -> Bool?
```

`release()` 只读**一次**并局部保存：

```swift
switch hooks.sessionLockState() {
case .none:      // 未知
    …"previous app not activated (lock state unknown)"; return
case .some(true):// 锁定
    …"previous app not activated (locked)"; return
case .some(false):
    break            // 只有明确 false 才继续 frontmost / running 守卫
}
```

生产钩子改为 `sessionLockState: { productionSessionLocked() }`（内部仍用纯函数 `lockState(from:)`：缺 session / 缺 key / 非 Bool-NSNumber → `nil`）。没有新增定时器或"重试直到成功"。

## 三、测试调整（接口合并，不是删回归）

- 我的 `LockActivationOwnerTests` 中对应的两个钩子替换为单个 `sessionLockState`（`{ self.locked }` 与 `{ nil }`），断言不变；
- 独立用例随接口合并改写为三项，语义更强：
  1. `testLockStateIsReadOnceAndNeverRecombined`：reader 第一次返回 `false`、之后返回 `nil`，断言 **只读 1 次**，且按该快照允许受守卫的恢复；
  2. `testUnknownOrLockedSnapshotNeverActivates`：`nil` 与 `true` 都只恢复策略、不激活旧应用；
  3. 跨 surface 逆序退出的原断言**原样保留**。

结果：`IndependentLockActivationLifetimeTests` 3 + `LockActivationOwnerTests` 14 = **17 项通过**。
回归：`LockMusicCoordinatorTests 32`、`LockCardLayoutTests 13`、`LockLyricsTrackChangeTests 8` 全部通过。

## 四、Release 交付

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0098-r2-lock-snapshot-candidate/Valora.app` |
| 版本 / 构建号 | `0.2.0` / **6**（`build-verification.json` 同为 6） |
| binary SHA-256 | `6b6ced70c17e0e8fe0909ae9ee12ba77024999ae63972928733ef614052a7914` |
| 签名 | `codesign --verify --strict --deep` 通过 |

替换：AppleScript `quit` 正常退出旧版（build 5）→ 复查 0 实例 → `open -n` 新候选 → 复查**仅 1 个进程**（PID 10232）；未使用 pkill；`dist` 未覆盖。

## 五、边界

真实锁屏/登录下的恢复行为仍未实机验证；本轮只证明"单次锁态快照 + nil/true 不激活 + 明确 false 才继续"在注入钩子下成立，不扩大为已修复实际密码焦点问题。
