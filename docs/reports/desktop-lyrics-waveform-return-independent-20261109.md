# build46 独立验收

2026-11-09。本轮只验收“律动/歌词偶发不显示、点击恢复”修复，未推进内存优化。

## 源码

CompactWaveformView 在 viewDidMoveToWindow 中解除旧可见性观察，再观察所属窗口 isVisible；变化时按最新 playing/reducedMotion/suspended 和窗口实际可见性协调时钟。没有增加常驻轮询或恢复 AppModel 全局进度广播；原律动幅度、周期、动画未修改。此路线不同于派工优先建议的协调器显式通知，但单窗口KVO确有独立可复现证据。多屏/所有真实AppKit可见性路径仍不能由小窗口测试保证。

## 独立验证

`VALORA_LYRICS_EXPERIMENT=1 swift test --filter 'IndependentWaveformReturnTests|PlayingWaveformLifecycleTests|PlayingWaveformVisibilityTests|PlaybackProgressScopeTests|DesktopPlayingCadenceTests|SeekProgressTests|IndependentLyricsTransitionClockTests|IndependentLyricsEmptyTransitionTests'`：31项通过、0失败。日志 `/private/tmp/valora-build46-independent-20261109.log`。

原 IndependentWaveformReturnTests 在build45对应源码失败，在本轮通过：窗口显示后无需额外configure即可注册时钟。既有隐藏停止、重挂恢复、暂停/减弱动态/挂起门控、进度隔离、seek、歌词时钟及空行恢复回归通过。测试仅少量离屏验证，未控制真实媒体/锁屏。

## 运行候选

当前唯一实例PID69080，路径 `/private/tmp/valora-waveform-return-20261109/Valora.app`，Info.plist build46。strict/deep签名通过，SHA256 `d1f0ba36b74eb2f74a7868656e58dedd99622b354aec179ab45b520bceccbd24` 与Pi交付报告一致。本轮未额外构建/替换。

## 结论与限制

已证实的律动可见性恢复缺口接受；不宣称所有日常偶发已消除，仍需自然播放观察。歌词偶发不显示尚未复现、没有本轮独立修复，不能当作已解决或与律动同根因。原歌词参数、进度隔离和CPU优化结构保留，但没有新一轮真实CPU数据，不能承诺资源占用绝无变化。用户无需为这次验收再次锁屏；先正常使用观察，复发时尽量先保留现场，由Codex采集状态后再点击恢复。


## 用户实机锁屏/解锁回归

用户保持歌词开启、音乐播放，自行锁屏后解锁，明确反馈：不点击刘海，歌词和律动都自动恢复正常。恢复功能的这条真实路径通过，不代表所有日常间歇性歌词问题已根治。

原始 `/private/tmp/valora-build46-lock-return-20261109.jsonl`：锁屏段22:08:15—22:11:44（北京时间），105个两秒区间，CPU平均8.04%，中位7.49%，去掉初始10秒平均7.84%；RSS111.38—119.09MiB。上一版build45有歌词稳定段7.18%，本轮7.84%，差0.66个百分点；顺序测试未严格控制歌曲/歌词进度，不能据此证明精确等效或认定回归。没有回到早期约10.7%的稳定开销。

解锁起始有约29.98%的过渡峰值，原监控只覆盖解锁后16秒，故另补20秒只读采样 `/private/tmp/valora-build46-unlocked-followup-20261109.jsonl`，CPU具体均值/范围见该文件（已回到约3—5%的桌面播放水平），RSS约121MiB。短时样本不证明长期无泄漏。本轮支持：锁屏和解锁恢复功能通过；CPU改善保持大体同一量级，不宣称本次KVO修复进一步降低歌词CPU。可结束本轮恢复修复验收，再进行用户授权的内存分析/定向优化。
