# 换句裁剪：用可控静态关键帧作生产参考

读 AGENTS.md 和 `desktop-lyrics-transition-clipping-investigation.md`。保留空行卡死与音符位置修复。上一任务要求“SwiftUI 参考动画不能可靠暂停时，用静态几何关键帧直接对照”；不能因为真实动画无法暂停就省略静态参考或宣称完全受阻。

## Codex 指定验证方式

1. 在测试代码中建立**静态参考帧**，按 `CompactLyricsView` 当前文字节点结构复制：相同 `Text` 字体/颜色/逐字遮罩、17pt 内层、短句与长句各自的布局及裁剪、HStack 音符/5pt 间距、原 rowHeight 外框与 `.clipped()`；将整个歌词子视图的 `.offset(y:)` 和 `.opacity` 显式设为注入值，模拟 `lineTransition` 的某一瞬间。不启动 SwiftUI 动画、不改变生产代码。先验证 offset=0 且 opacity=1 的 fixture 与实际生产 `CompactLyricsView` 静态结果一致；不一致就报出，不能把 fixture 当基准。
2. 构造实验行对应静态帧，保持当前逐字 mask 和真实水平裁剪，在同一实际 2x/尺寸/音符/配色下，分别注入 offset 0、±5、±10（透明度固定 1 先隔离裁剪，再补 0.5）；比较生产 fixture 与实验在 32pt 桌面行、带音符短/长句和实际内嵌行高的原始截图、可见范围。复用同一隔离画布，不批量闪窗、不操纵真实播放。不要借 y 符号假设得出方向结论。
3. 若静态帧确认当前固定 17pt clip 会提前截断，按前一任务的确定方案调整：把换句动画加在每个 17pt 水平裁剪视口本身，而非视口内文字；由既有外层实际 rowHeight 裁切；旧行共享静态图像且只存在一条活动渲染时钟。短句/长句水平、mask、音符坐标必须保持。固定帧对比改善才能保留；若无改善或桥接不能溢出，恢复原实现并报告证据。
4. 添加空行→下一句、连续换句、seek、隐藏恢复、失败回退及窗口释放回归，保留 `IndependentLyricsEmptyTransitionTests` 断言。30Hz 帧禁止重建文字/位图；不改动画时长、曲线、方向，不加生产设置。
5. 输出 `docs/reports/desktop-lyrics-transition-static-frame.md`，明确静态帧结论与真实过渡体验仍需用户确认，CPU 本版未测。锁屏/普通 Release 不改；禁止启动或替换用户 App、真实播放操作、打包提交。
