# 动画独立验收失败：音符初始位置错且先反向移动

build55的新共享准备/单旧行已实现，独立45项通过；但不能接受动画对齐。Codex新增了一条实际像素位置回归，并用同一窗口/同一输入对照原SwiftUI外壳，找到用户“不柔顺”的具体几何问题。内存任务继续等待。

## 可复现证据（不是参数/源码断言）

新增 `LyricsRowExperimentHostingTests.testDesktopKeyedNoteDoesNotJumpOrReverseAtLineChange`，日志：

- `/private/tmp/valora-build55-note-continuity-20261110.log`
- `/private/tmp/valora-build55-note-reference-20261110.log`

暂停的短句稳定0.35s后，seek到长句（触发真实生产keyed路径），按绝对t=.001/.05/.10/.15/.25采样红色note像素x：

```
新实验 before=149 samples=[161,171,113,56,39]
原SwiftUI before=200 samples=[200,182,125,63,39]
```

两次独立复现一致。说明不是只差抗锯齿：初始静态短句音符就偏左约51像素，切句开始又先往右12/22像素，然后突然向左。旧测试默认legacy策略/只看终点或活跃clock，没捕捉新desktop策略的布局。

新增测试目前1项2个断言失败，有意保留。它是有限单窗口、两条短过渡，不是压力测试。不要放宽阈值掩盖这种50px偏移/反向移动；可以按参考真实路径完善容差和实际采样时间记录。

## 指定修复方向

桌面keyedRow仍残留R1手工 `layoutWidth/layoutIsLong/syncOuterLayout`，与父层presentationID动画并行，造成两套布局状态时序。**删除桌面这一层独立布局状态/单独withAnimation，直接像baseline一样由新旧child的真实固有/available宽度、isLong和父HStack唯一 `.animation(.easeInOut(0.2),value:presentationID)` 管理几何。** ZStack/child用本行真实resolvedWidth，不再先保旧layoutWidth再独立改alignment。

不要改字体/固有音符宽度、HStack spacing、inset、可用宽度、行高、偏移等数值凑测试；先保证稳定短句音符和文字与参考一致，再保证短→长平滑向左、长→短平滑向右、短→短按目标平滑，无反向漂移/起点跳位/结束收缩。

保留真正keyed transition、唯一实时clock、隐藏退役旧native/唯一冻结旧图、owner共享截图宿主（不同3句只建1个window）、输入去重、锁屏legacy、独立歌词开关/44pt位置及其他CPU成果。

## 验收/交付

先让新增独立回归通过，并在原testNoteAndTextPositionsMatchProduction等里明确测试desktop .build26SwiftUI策略（不能全用默认legacy冒称desktop通过）。实际逐句播放路径也有限采样，避免仅seek通过而自然tick不一致；midframe保存图，记录实际时间与baseline。

必要定向回归后一次有实质修改的Release候选按AGENTS正常替换/唯一实例/签名hash/默认无诊断；保留build49/55。不要改真实媒体或锁屏，不跑压力/批量闪窗。报告误差和用户醒后待验体感，不发布/提交。
