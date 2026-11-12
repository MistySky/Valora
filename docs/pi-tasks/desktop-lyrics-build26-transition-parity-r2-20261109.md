# 动画R2：用户仍感到不柔顺，不能只接受终点一致

用户最新反馈：“切歌感官上和之前不一致，感觉不柔顺”。Codex已询问是逐句还是整首切换，用户暂未补答；结合原主诉，当前先按歌词逐句切换继续处理，不擅自改封面翻转/整刘海动画。用户已授权夜间继续工作、5分钟跟进。内存任务先不执行。

## build51独立证据

锁屏/桌面策略隔离已修，固定16ms停顿去掉，独立5项通过；但真实生产采样仍有明显过渡差异：

```
t=.00 reference ink742/y21, experiment755/y21
t=.05 reference828/y15, experiment829/y17
t=.10 reference4032/y0, experiment2875/y1
t=.15 reference5007/y22, experiment4978/y0
t=.25 两者4857/y21
```

日志 `/private/tmp/valora-build51-independent-20261109.log`。小的采样时差/抗锯齿可解释部分差异，但不能将这些数值直接证明视觉等价。现有test仍只断言起终点；中段只print，不是对齐断言。手动步进PNG也不是生产动画证据。

## 实现方向（Codex决定）

不要再用“发布offset/opacity目标 + 另一个async启动”模拟原版的transition。桌面外壳恢复原版真实SwiftUI keyed child `.id(lineKey)` + `.transition(.asymmetric(insertion:.offset(y:26).combined(with:.opacity),removal:.offset(y:-26).combined(with:.opacity)))`，父HStack `.animation(.easeInOut(duration:0.2),value:lineKey)` 的呈现机制。恢复原版短句固有宽度/长句availWidth及同一事务的布局迁移，不分别管理两套起跑时刻/横竖动画。

保留native图片缓存和高亮渲染：给SwiftUI过渡的旧句使用切换当时的冻结资源/高亮/横向偏移，当前句使用唯一活跃native行。为与keyed child生命周期配合，允许小范围抽出“行呈现”外壳/共享准备资源接口，确保退场的旧视图不再驱动媒体时钟、不重新选成新行；新行优先复用已准备图片，不每帧重建，不起两套连续时钟。不要将整个CompactLyricsView Timeline30Hz旧实现直接切回生产，也不降低高亮/滚动频率。

如实现中发现真实SwiftUI transition需要调整资源/行生命周期，则先明确设计边界，再在本批局部完成；不要仅改0.2s/曲线或加延迟。保持build49锁屏timer策略、歌词开关/44pt底边、进度隔离、waveform恢复、输入去重。禁止改其他UI。

## 证据与交付

用同一实际起点/同一歌词进度、短→短/长→短/短→长的有限真实生产路径预览，保存baseline与新版起中末关键帧，并报告实际采样时间。参考需明确是发布源码baseline，不能拿当前已优化代码悄悄替代。中段要有判据：墨迹面积/位置或肉眼同窗对照，承认抗锯齿时差；不要只有末端像素一致。不要批量窗口或压力。

本轮独立接受标准是：原版过渡机制已恢复且无跳位/二次收缩/先显新句后翻/双时钟；用户真实体感仍待醒后确认。必要回归通过后按AGENTS一次Release候选替换、唯一进程、签名/hash、默认无诊断，保留build51。更新原report的R2证据和真实未验限制。若无法在本批有把握对齐，报告具体阻碍，不继续叠加其他风格，不发内存优化。
