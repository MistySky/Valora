# V0093-R1 传输生命周期返修：真实取消与超时

执行：现有 OpenCode 会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，依据 `docs/verification/independent-v0093/decision.md` 与 `Tests/ValoraTests/IndependentCodexTransportTests.swift`。
用户 seq5413 已确认的 UI（5H 带日期、两行监控同卡）**未改动**；"监控移到日历下方"仅讨论，未实施。未 Git 提交/推送、未安装发布、归档只读。

## 一、独立验收的两项失败（复现后修复）

| 失败用例 | 原表现 | 根因 |
|---|---|---|
| `testCancellingReadTerminatesTheActualSilentChild` | `task.cancel()` 后仍要等到静默子进程自己退出 | `readRateLimits` 里是**同步阻塞**的 `availableData` 轮询，Task 取消根本打断不了它，也没有取消处理器去结束真实子进程 |
| `testSilentStdoutCannotBypassTheReadDeadline` | 2s deadline 在 3.2s 静默子进程退出后才生效（实测 3.64s） | 同上：`while Date() < deadline { handle.availableData }` 在无输出时**阻塞在读取**，deadline 无法被检查 |

## 二、修复后的传输结构（`Sources/Valora/CodexAppServerClient.swift`）

1. **可取消**：`withTaskCancellationHandler` 包住整个读取；`onCancel` 直接调用 `finish(.failure(CancellationError()))`，它会先 `process.terminate()`，再在后台队列上 0.5s 后 `SIGKILL`（有界收尾，不阻塞调用方）。
2. **绝对 deadline**：改为 `DispatchWorkItem` 在全局队列上 `asyncAfter(timeout)`；无论子进程是否输出、输出半行，都按点触发 `timeout`。stdout 不再用阻塞式轮询。
3. **非阻塞管道**：stdout/stderr 都用 `readabilityHandler` 处理；stderr **只读不存、立即丢弃**，不日志化敏感内容。
4. **有界输出**：stdout 行缓冲上限 `stdoutLimit = 256 KB`，超限即 `outputLimit` 失败，不无限占内存。
5. **单次收尾**：`finished` 标志 + `NSLock` 保证 continuation **只 resume 一次**；成功后同样清 handler、关文件句柄。取消发生在进程启动**之前**时，`pendingError` 会让 `start()` 直接以 `CancellationError` 结束，不会留下孤儿进程。
6. **避免 SIGPIPE 崩溃**：初始化时一次性 `signal(SIGPIPE, SIG_IGN)`；写入前检查 `finished` 状态。
7. **白名单不变**：仅 `initialize` / `initialized` / `account/rateLimits/read`；本轮**没有**跑真实额度握手，全部使用自产临时 shell 假进程与协议 fixture。

## 三、定向验证（本次实际执行数量，逐套件记录）

| 套件 | 数量 | 结果 |
|---|---|---|
| `IndependentCodexTransportTests`（原两项失败） | **2** | 通过（总耗时 2.183s，取消 <0.6s、deadline 2s 生效） |
| `CodexUsageSummaryTests` | **13** | 通过 |
| `LockMusicCoordinatorTests` | **32** | 通过 |
| `LockMusicStateTests` | **13** | 通过 |
| `LockCardAppearanceTests` | **4** | 通过 |
| 合计（本次实际执行） | **64** | 0 失败 |

更正此前报告的数量错误：V0093 那次实际是 13+32+13+4=**62**（不是 49）；本 R1 又加上传输 2 项，故本次 64。未执行其它套件，不冒称。

停用验证：开关默认关闭，新实例启动后进程表里只有 Valora 本体；系统里唯一的 `codex app-server`（PID 6414，已运行 3h45m）是 ChatGPT/Codex CLI 自身会话，父进程 75987，**不是本 App 拉起**。

## 四、构建 / 单实例替换

- 候选：`/private/tmp/valora-v0093-r1-bounded-transport-candidate/Valora.app`
- binary SHA-256：`08b2327a31a2e29ba1de4774792492b179039a125d06e3745d8cab9025e53d3d`
- `codesign --verify --strict --deep` 通过；`dist/Valora.app` 未动
- 替换：`pkill -f "MacOS/Valora"` → 复查 0 → `open -n` 候选 → 复查**仅 1 个进程**，路径 `/private/tmp/valora-v0093-r1-bounded-transport-candidate/Valora.app/Contents/MacOS/Valora`（PID 54884）

## 五、未改动 / 未验

- UI、菜单入口、内存格式、图标、音乐、锁屏、5H 日期与"两行同卡"布局均未动；
- 真实额度读取仍未主动触发（开关默认关），真实账号数值/重置时间以用户开启后为准；
- 未在真实登录/锁屏或其它时区验证。
