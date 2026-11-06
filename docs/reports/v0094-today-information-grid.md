# V0094：传输预取消收尾 + 顶部两行共同列宽对齐

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，分支 `codex/music-display-lock-policy`。
**B 的旧方案（搬事件区/今天限定/系统芯片概况/四行/最近到期）已被用户最新截图撤回，本报告按最新覆盖实现"保留现有两行、仅对齐"。** 未 Git 提交/推送、未安装发布、归档只读；未读真实账号/额度/事件，未操作媒体/设备/锁屏/权限。

## A. 传输：启动前取消挂起 + 真实子进程收尾

独立验收新增用例 `testAlreadyCancelledReadFinishesWithoutLaunchingAnEngine` 的失败原因确认：`Run.finish` 在 continuation 尚未注册时只置 `finished = true`，**没有保存 `pendingError`**；`start` 只检查那个从未赋值的 `pendingError`，随后再来的 `finish` 因 `finished` 早退，continuation 永不恢复 → 350ms 后依然挂起。

修复（`Sources/Valora/CodexAppServerClient.swift`）：

1. `finish` 在 continuation 为空时把失败原因存入 `pendingError`；`start` 改判 `finished`，一旦已终态就**直接 resume（CancellationError / 原错误）且完全不走启动分支**，不会创建进程或管道；
2. **真实 child 收尾**：`finish` 把仍在运行的子进程登记到进程内注册表（`NSLock` + `nonisolated(unsafe)` 受锁保护的数组），TERM 后 0.5s 后台 SIGKILL；**下一次读取在启动前**先 `SIGKILL` 掉仍存活的旧子进程，并最多等 250ms 确认它退出，才允许启动新引擎 —— 因此 provider 重启不会出现两个真实 child 并存；
3. 其余保留：绝对 deadline（`DispatchWorkItem`，与 stdout 无关）、stdout 256KB 上限、stderr 只读即丢、`finished` + 锁保证 continuation 只 resume 一次、单次 handler 清理与关闭、忽略 SIGPIPE、三方法白名单。

## B. 顶部两行：共同列宽对齐（覆盖旧方案）

- 保留截图中**同一张卡的两行**：
  1）内存 总量 剩余 / 磁盘 总量 剩余 / 已运行 时长
  2）5H 剩余 日期时间 / WEEK 剩余 日期时间 / 重置卡 数量
- 两行改为**同一个 `Grid`**（3 列、水平间距 12、行距 8），列宽由两行共同决定：内存↔5H、磁盘↔WEEK、已运行↔重置卡 左缘对齐；中间保留 1pt 细分隔线（跨 3 列）。
- 卡片左右仍是 16pt 内容边距 + 12pt 卡内边距，11pt regular、secondary、同样圆角与半透明底；**移除原来的 `minimumScaleFactor(0.8)`**，改为不缩字，并用真实字体量宽验证不溢出（见下）。
- 日历、事件区、菜单入口、左右击行为、监控/Codex 两个开关语义、内存与 Codex 数值格式均未动。

## C. 定向验证（本次实际执行）

| 套件 | 数量 | 结果 |
|---|---|---|
| `IndependentCodexTransportTests` | 4 | 通过（含原两项 + 启动前取消 + 新增"忽略 TERM 子进程在下次读取前被清掉"） |
| `CodexUsageSummaryTests` | 14 | 通过（含新增"两行共同列宽且总宽 ≤344pt"） |
| `LockMusicCoordinatorTests` | 32 | 通过 |
| `LockMusicStateTests` | 13 | 通过 |
| `LockCardAppearanceTests` | 4 | 通过 |
| 合计 | **67** | 0 失败 |

行宽实测（真实 11pt 字体，worst case）：`内存 32 GB 9.0 GB` / `磁盘 494.4 GB 263.7 GB` / `已运行 2 天` 与 `5H 100% 12/31 23:59` / `WEEK 100% 12/31 23:59` / `重置卡 99张` 三列取最大值 + 2×12pt 间距 ≤ 344pt（断言通过，未缩字）。

## D. 构建 / 单实例替换

- 候选：`/private/tmp/valora-v0094-two-row-align-candidate/Valora.app`
- binary SHA-256：`df9f777f117007740a9739a2954ebd859653e964adff11cb30258361821808b2`
- `codesign --verify --strict --deep` 通过；`dist/Valora.app` 未动
- 替换：pkill 至 0 → `open -n` 候选 → 复查**仅 1 个进程**，路径 `/private/tmp/valora-v0094-two-row-align-candidate/Valora.app/Contents/MacOS/Valora`（PID 60323）

## E. 未验 / 边界

1. 真实额度读取仍未在 App 内主动触发（开关默认关）；真实账号的 5H/WEEK/重置卡数值与时间以用户开启后为准。
2. 真实子进程行为已用自产脚本验证（预取消不启动、忽略 TERM 的后代被清掉），但未在真实 Codex 引擎上重复做取消/重启压测。
3. 两行对齐为无窗口宽度与结构验证；面板实际渲染仍需用户肉眼确认。
