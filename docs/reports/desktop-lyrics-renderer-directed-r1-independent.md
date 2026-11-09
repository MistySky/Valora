# 原生歌词原型 R1 独立验收

2026-11-07。结论：上轮四项回归转绿，R1 有效修复；新发现两类可复现问题，仍不接受生产接入。CPU 与体感等价尚未通过。

## 复测

本轮先运行上一轮同组测试，43 项中 42 通过、1 跳过。随后在 `IndependentNativeLyricsRowTests.swift` 新增三个回归（不改产品代码）并复跑同组：46 项中 42 通过、3 失败、1 跳过。之前的四个独立断言用例保持通过。

命令：`swift test --filter 'IndependentNativeLyricsRowTests|IndependentLyricsFrameReplacementTests|LyricsLineFrameCacheTests|NativeLyricsRowPrototypeTests|SeekProgressTests|DesktopPlayingCadenceTests'`。

日志：`/private/tmp/valora-lyrics-r1-independent.log`、`/private/tmp/valora-lyrics-r1-independent-final.log`。

## 阻断 1：静态句边界定时器不随输入失效（P1）

位置：`NativeLyricsRow.swift:465` 的 `synchronizeClock`。只要连续刷新模式不变、已有 boundaryWake 就提前返回，没有检查下个边界、播放锚或速率是否改变。

- 下一句从 20 秒改为 1 秒，lineEnd 已正确更新为 1，但唤醒延迟仍约 20 秒。
- 播放速率由 1 改为 2，下一句在进度 20 秒，唤醒仍约 20 秒，预期约 10 秒。
- 现有 SwiftUI wrapper 在 apply 新输入之前 setActive(true)，强制计算时仍用旧快照，不能保证修正此问题。宿主后续更新可能掩盖延迟，不能作为正确性保证。

确定修法：对边界调度维护由当前快照计算的绝对截止时间，输入更新、seek、倍速、行/时间轴变化时重新计算；截止时间未变才复用计时器。按当前墙钟而非把旧采样时刻的完整剩余时长从现在重新计时。连续帧路径不必每帧重建相同计时器；进入静态路径时重新选择正确截止时间。取消旧定时器要覆盖暂停/隐藏/无下一句。

## 阻断 2：换句出栈层丢失原横坐标（P2）

位置：`NativeLyricsRow.swift:357` 的 `snapshotOfLine`。先设 `container.position`，紧接着设原点为 0 的 `container.frame`，后者覆盖前者。

独立用例：宽 260pt 的短句居中时 x=124.040856，换句后出栈图层 x=0。旧字会从左侧退场，违背原有换句观感。滚动行也应保留已有横向滚动位置。

确定修法：使用 bounds 描述尺寸，保留 position；或先设置尺寸再设置正确位置。验证短句居中和长句滚动时的出栈位置，保留当前淡入淡出与垂直移动。不能仅检查动画计数。

## 视觉报告需要纠正的结论

- OC 报告把原型与生产的填充/滚动差异归因为生产既有 kern 0.05 测量、0 绘制，但原型目前同样复用这些测量公式且用 kern 0 绘制。共同口径本身不能解释二者差异，此归因未被证明；不接受“接入前必须统一生产字距”的建议。
- 相同墨迹外包框不证明布局一致；尤其长句裁剪后总是占满行宽，内部位置仍可能不同。需分别检查字形位置、遮罩和裁剪坐标，保留生产可见基线。
- 像素探针捕获失败只打印 capture-failed 不使测试失败，且没有保存本轮图像供独立观察。数值表不是完整视觉验收。本轮未运行该批量开窗探针。
- Reduce Motion 的 0.12s 来自旧原型；当前生产 CompactLyricsView 明确写 0.2s。不能把旧原型参数称为已经与生产等价。

## 边界

本轮不替换 App、不控制真实播放、不安装/提交。原型仍隔离在开发代码；没有真实可比 CPU 结果。生产缓存修正和 seek 相邻测试继续通过。
