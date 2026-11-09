# 修复：拖动播放进度回弹

用户反馈（现有 build29 上）：拖动进度条松手后，指针会先跳回拖动前的位置，等系统 seek 完成后再跳到目标；期望与音量一致——拉到哪里就停在哪里。

## 原因（已确认）

- `MediaProgressView` 松手时只是调用 `model.media.seek(target)` 并清空本地拖动值；
- `MediaController.seek` 原本只把命令交给适配器，**不更新本地 elapsed**；
- 进度条的显示值立即退回 `model.elapsed`（仍是拖动前的位置）；
- 等系统返回 seek 结果的下一次快照进入 `applySystem`，才把 elapsed 改成目标位置，于是出现“先回弹、再跳过去”。

音量没有这个问题，因为音量路径本来就有 `localTarget` + 抑制窗口的本地锚点。

## 修复（`Sources/Valora/Controllers.swift`）

按音量同样的思路，为 seek 增加本地乐观锚点：

- `seek` 成功发命令前，立即 `setElapsed(target)` 并记录 `PendingSeek{target, startedAt, deadline, identity}`；播放中按当前倍速从目标继续插值。
- `applySystem` 收到快照时：
  - 同曲目且位置接近目标（≤1.5s）→ 视为确认，清除乐观锚点，采用系统位置；
  - 同曲目但仍带拖动前位置 → 视为在途旧快照，**不覆盖**进度（标题/播放状态等元数据照常更新）；
  - 换了曲目 → 立即以新曲目位置为准并丢弃锚点。
- 命令失败：清除锚点、按系统最后一次位置恢复，并保留原错误提示。
- 超过确认窗口（默认 1.5s）仍无确认：放弃乐观值，回到系统位置，避免指针停在未确认的位置。
- 连续多次 seek：用代次号保证只有最后一次命令的失败回调能回滚。
- `invalidate` / `clearMedia` 会清理锚点。

未改：进度条的视觉、拖动/点击/无障碍调节手势、歌词与播放锚点语义。

## 测试

新增 `Tests/ValoraTests/SeekProgressTests.swift`（8 项，全部通过）：

1. 松手立即显示目标位置（30 → 90，命令参数 `90000000`）。
2. 在途旧快照（30.2）不会把指针拉回。
3. 确认快照（90.4）采用系统位置，后续位置（95）恢复权威。
4. 命令失败回滚到系统位置（≈30）并给出错误提示。
5. seek 期间换曲：以新曲目位置为准。
6. 播放中 seek 后 4 个 tick 从落点继续前进（不回弹）。
7. 连续两次 seek 只认最后一次；旧命令的失败回调被忽略。
8. 确认窗口内无确认 → 回退到系统位置。

相邻回归：`SeekProgressTests|MediaResponsivenessTests|MediaScheduleTests|MediaControllerRecoveryTests|IndependentMediaScheduleLifecycleTests|AuditTickingMediaSourceTests|DesktopIdleMediaPublishTests|DesktopPlayingCadenceTests|LyricsAnchorInterpolationTests|IndependentDeviceMediaReviewTests|LockLyricsTrackChangeTests|LyricsFollowupTests` → **62 通过，0 失败**；`swift build -c release` 通过。

## 未验项

- 未在真实播放上验证（不控制真实媒体）：真实适配器 seek 往返时间和确认位置偏差需实机确认；若某些播放器从不回传新位置，会在 1.5s 后回到系统位置。
- 未打包、未替换运行版（当前仍 build29），等用户决定是否打包测试。

## 候选与替换（用户当次授权）

| 项 | 值 |
|---|---|
| 候选路径 | `/private/tmp/valora-seek-anchor-r4-candidate/Valora.app` |
| 版本 / 构建 | `1.0.3` / **30**（29 → 30） |
| 签名 | `Valora Self-Signed`，strict/deep 通过；adapter test exit 0 |
| App binary SHA-256 | `6a51344f6cff7e8925090021f5bc421c18c345f0cc26b86b4c7efb83ca70dc1d` |

替换：退出旧实例前确认 0 进程（build29 已自行退出），随后启动唯一新包；当前 1 个进程（PID 48188，路径即候选），刘海面板存在。未安装到 `/Applications`、未提交。
