# 媒体读取循环临时对象释放（2026-11-12）

## 范围

仅修改 `Sources/Valora/SystemMediaSource.swift` 的 reader 永久循环释放边界。未改动画、交互、封面、歌词、hover、progress、seek、锁屏、媒体适配器参数或诊断。未正式打包、未替换运行实例、未操作真实媒体/音量/锁屏/偏好、未提交。

## 精确实现

新增内部 helper：

```swift
static let streamBufferLimit = 16_000_000
enum StreamEnd { case eof, bufferLimit }

static func readStream(
    readChunk: () -> Data,
    bufferLimit: Int = streamBufferLimit,
    didExceedLimit: () -> Void = {},
    emit: (SystemMediaSnapshot?) -> Void
) -> StreamEnd
```

限制：

- `buffer` 在 helper 外层、跨 chunk 保留；
- 每轮 `autoreleasepool` 覆盖：
  - 阻塞的 `availableData` / 注入的 `readChunk()`；
  - `buffer.append(chunk)`；
  - 16MB 上限判断；
  - 逐行 `Data`、`JSONSerialization`、事件过滤、`SystemMediaSnapshot` 构造；
  - `emit` 调用；
- **不是**给整个永久 dispatch task 包一层 pool，也没有只改 queue 的 autoreleaseFrequency。

生产的 reader 现在调用同一 helper；`readChunk` 只读 `output.fileHandleForReading.availableData`，超限回调仍调用 `task.terminate()`。

## 所有权 / 顺序

- `buffer` 由 helper 栈拥有，跨 iteration 保留；只在新行完整时移除。
- `line`、JSON dictionary、payload、临时 CFString/Data 在轮末 pool drain 时释放。
- `SystemMediaSnapshot` 被 `DispatchQueue.main.async` 闭包**强捕获**；即使 reader pool 随后排空，主线程仍拿到完整 snapshot/artwork Data。
- `emit` 在主线程闭包外按原行顺序同步调用；main hop 的 FIFO 保持原事件顺序，没有合并/排序/延迟。
- malformed 行、非 `data`、`diff` 行仍 `continue`；无效 payload 仍 emit `nil`；EOF、16MB 上限、`task.terminate()`、`waitUntilExit()`、epoch 校验、停止错误回调都保持原语义。
- 未改 `--debounce=50`、`--no-diff`、读取频率或媒体控制器。

## 测试

新增 `Tests/ValoraTests/SystemMediaStreamAutoreleaseTests.swift`，5 项通过：

- chunk 跨界 JSON、同 chunk 多行、malformed/non-data/diff 行、EOF；
- valid snapshot + artwork 数据在主 hop 后完整，invalid payload emit nil；
- 注入 32-byte 上限：先终止，不解析超限 chunk；
- EOF 留半行不 emit；
- iteration probe 在下一轮读取前已释放（probe 在 `readChunk` 的临时作用域内，验证跨 iteration 不保留）。

相关信息：

- `SystemMediaStreamAutoreleaseTests` 5/5；
- `MediaControllerRecoveryTests` 11/11；
- `AuditTickingMediaSourceTests` 1/1；
- `PlaybackProgressScopeTests` 3/3；
- `SystemMediaSnapshotTests` 1/1、`SystemMediaTests` 4/4、`MediaIdleTests` 6/6、`LyricsTimelineTests` 6/6。

未启动真实媒体适配器，未读取真实播放/锁屏/设置。

## 未验项与边界

- 未正式构建 Release 包、未替换、未测真实进程的 footprint/autorelease 池；build60 的 37.8M 池归属是修复前证据，不能宣称本修复立即等量降低内存。
- 没有长期运行/压力循环；按任务禁止压力测试。
- 当前测试的 iteration probe 证明读取迭代边界不保留临时对象；Swift/XCTest 没有直接读取 `NSAutoreleasePool` 所属对象的公共接口，因此没有把“池内对象已空”冒充为直接池内容快照。生产代码边界由 helper 的真实 `autoreleasepool` 覆盖。
- 未验证真实 adapter 的 EOF/terminate 外部进程生命周期，只验证注入循环语义。
- 未改任何动画/交互；固定外轮廓主题的整改仍等待 Codex。

## Codex 独立验收勘误与后续

上文 iteration probe 原先在测试内部自行创建pool且对象可由Swift ARC释放，即使生产循环没有局部pool也可能通过，不能作为生产释放池证据；“artwork在main hop后完整”原开发测试仅同步保存快照，也不足以证明真实main hop。Codex已补充 `IndependentMediaStreamPoolTests`：真实objc_autorelease对象配合旧循环负对照，以及pool排空后实际main队列交付数据。原弱probe已替换为严格缓冲上限等值测试。

固定外轮廓已在前笔build60交付，本笔保持其生产代码字节不变；上文“仍等待Codex”是陈旧状态。当前本笔build61已完成独立验收及单实例替换，详见 `media-stream-autorelease-independent-20261112.md`。一次新启动低内存值不作为长期节省量。
