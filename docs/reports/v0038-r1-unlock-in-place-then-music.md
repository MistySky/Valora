# V0038-R1 模拟锁屏原地开锁→收起→音乐展开

日期：2026-10-30
状态：限定返修完成，等待 Codex 独立验收；**候选未启动，未替换当前运行版**。
候选：`/private/tmp/valora-v0038-r1-unlock-candidate/Valora.app`
候选二进制 SHA-256：`79dafcefe761dda1444b1271ec0ad86b06052dc1255a337c8b3ffc92bdbaf014`

## 1. 修复

只改模拟预览必要的解锁恢复路径，保留已被用户认可的加锁动作和形状/位置。

`Sources/Valora/LockPreviewController.swift`：

- locked→unlocking 仍使用同一个 `LockIndicatorState`/同一 `NotchView` 左翼 `LockActivityGlyph`：
  - 相同展开宽度；
  - 不从锁状态先隐藏后再出现一个 open 图标；
  - 不另画或飞行符号。
- `.unlocking` 阶段保持锁活动宽度，open glyph 显示；0.8 秒原有停留保留。
- 0.8 秒后才进入 `.restoring` neutral 基础刘海；通过实际 geometry animator completion 才结束收起。
- neutral completion 之前 `showsMusicActivity` 保持 false，不会以同宽的 locked/playing 直接替换跳过收起。
- completion 之后使用现有 compact activity 的 `withAnimation`：`active=false`、预览 indicator hidden、预览 presentation false，使当前最新媒体按普通音乐活动展开；无音乐保持基础刘海。
- 不触碰真实 `model.isSessionLocked`、真实 lock indicator、Space/声音/新窗口/真实媒体控制。
- generation/token 继续拒绝快速反转、旧 geometry/scheduler completion；真实锁、总开关 off、stop 仍取消模拟。

## 2. 定向验证

命令：

```text
swift test --filter 'LockPreviewControllerTests'
```

结果：**9 项通过，0 失败**。

新增断言检查实际 geometry，而不只是枚举：

- 解锁开始 `.unlocking` 时 `visibleSize.width` 保持 locked 宽度；
- 0.8 后 `.restoring` 的实际 `visibleSize == geometry.compact`；
- 几何收起 completion 前音乐不恢复；
- completion 后当前最新音乐恢复，实际宽度等于 `.playing` 的 `PresentationMetrics` 宽度；
- 无音乐时最终保持 neutral/基础刘海；
- 加锁 starts from neutral / 无音乐基础刘海；
- 快速 on/off/on 旧 completion 不反转；
- 真实锁接管、总开关 off、真实 session 不变。

没有真实 NSWindow/NSPanel/Space/锁通知/声音/媒体控制，未运行全量、截图、点击循环或压力测试。

## 3. 构建、候选与边界

- Release：`/private/tmp/valora-v0038-r1-unlock-candidate`。
- arm64、macOS 27、ad-hoc hardened runtime；`codesign --verify --deep --strict` 通过。
- 候选二进制：`79dafcefe761dda1444b1271ec0ad86b06052dc1255a337c8b3ffc92bdbaf014`
- 锁解资源哈希不变。
- **候选未启动**；当前运行 V0038/其他应用和 `dist` 未退出、覆盖或替换；未改偏好/权限/归档，未 Git，未恢复定时器。

真实用户点击的连续动画体感仍需 Codex/用户实机验收，fake geometry completion 不等于真实动画帧。
