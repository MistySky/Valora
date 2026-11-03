# V0039-R2 直接修复候选：锁屏表面改为独占自有 Space

2026-11-03，用户在本聊天明确“我直接改（推荐）”，并由 Codex 直接实现与取证，不投 pi。

## 根因（证据）

见 `docs/verification/direct-lock-zoom-root-cause/findings.md`：锁解过渡期间 WindowServer 把整个用户会话表面按 0.9 缩放、顶边下移约 5% 屏高；面板同时属于桌面 Space（成员 `[1, own]`）就会跟着一起缩放，表现为脱离物理刘海。稳定锁屏态其实已贴合。

## 实际改动

1. `Sources/NativeBridge/NativeBridge.m|h`
   - 新增 `migrateWindowNumberExclusively:` / `ARLockSpaceMigrateWindowExclusive`：先把窗口加入自建 Space，再移除捕获到的其它 Space 成员，使窗口**只属于自建 level 400 Space**。
   - **空成员合法**：新建隐藏窗口 `before=[]` 不再被当作失败，直接 add 并验证；这正是 R1 每次 `space-migration-failed` 的分支。
   - 每次尝试返回真实详情：`ok/reason/space/query/before/after/restored`，不再在 Swift 侧硬写 `unknown`。
   - 失败必须回滚：移除自建成员并把捕获成员加回，返回值区分 `not-exclusive` 与 `post-query-unknown`。
   - `detachWindowNumber:` 在独占挂载后**恢复捕获的原成员**，锁结束后面板回到桌面 Space。
2. `Sources/Valora/LockMusicCoordinator.swift`
   - 顶部刘海挂载与隔离 overlay 都改为独占迁移；独占被拒绝时仍走原有 add-only 可见回退。
   - 新增一次性合成校验（0.25s，非定时器）：独占后若 `CGWindowList` 明确报告不在屏上，则回退到 add-only 可见路径，避免 R8 那种“锁屏整个消失”。
3. `Sources/Valora/NotchWindowDiagnostic.swift`
   - `isWindowComposited(_:)`：只查本进程自己的 window number，返回 `nil` 表示无法判断、不触发回退。

未改动：锁屏动画阶段顺序、解锁原地开锁→neutral→最新音乐、桌面模拟锁屏、音乐卡/耳机信息卡、日历监控、歌词、设备、设置。

## 验证

- `swift build` / `swift build -c release` 通过。
- Swift 定向：`LockMusicCoordinatorTests` 28 项通过（25 原有 + 3 新增：独占优先、独占被拒回退、overlay 走独占并报告真实分支）。
- Native fake-only 回归（生产 `NativeBridge.m` + 注入回调，无 NSApp/NSWindow/真实 Space）：
  - 新增 `Tests/NativeBridgeTests/ExclusiveSpaceMigrationTests.m`，6 场景通过：空成员迁移、桌面成员独占并可恢复、add 被静默忽略时回滚、迁移后查询未知时回滚、缺符号不改后端、已独占保持成功。
  - 原有 `IsolatedOverlaySpaceTests.m` 6 场景仍通过。
- 候选：`/private/tmp/valora-v0039-r2-exclusive-space-candidate/Valora.app`
  - binary SHA-256 `833de47049f058b530442d433c26f9f20c3a4581ecd68d42f16c486b03b0b323`
  - `codesign --verify --strict --deep` 通过，runtime 27.0.0
  - 诊断日志 `/private/tmp/valora-v0039-r2-exclusive-space.jsonl`
- 启动后普通桌面态正常：window 1189，Space `[1]`，Quartz `[552,0,624,320]`，未强制迁移。

## 边界

- **这是候选修复，不是已实机通过**。独占 Space 后“是否真的合成在登录界面之上并被钉在顶边”只能由用户一次真实锁解确认。
- 若独占失败或合成校验判定不可见，行为退回本轮之前的 add-only 路径（仍会下移），不会出现锁屏完全消失。
- 未退出/覆盖 `dist` 与 `/Applications`；只切换了 `/private/tmp` 下的测试候选。未做真实锁屏/声音/媒体/设备/权限操作，无 Git 提交。
