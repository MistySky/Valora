# 桌面歌词实验接入 R1 返修

读 AGENTS.md、`docs/reports/desktop-lyrics-experiment-integration-independent.md` 和原派工。沿用原会话、模型、分支；只做验收发现的问题，不更改生产样式/时间/帧率，不涉及锁屏。

1. 失败回退在实验行最外层直接返回完整、参数与普通调用一致的 `CompactLyricsView`；不要在已有音符 HStack 中再嵌套完整行。保留 width、rowHeight、showsNote、horizontalInset、centersNoteWhenEmpty、auditRole。原生宿主移除后注销计时器和关闭自有捕获窗口，不能并行保留两条渲染链。
2. 恢复生产长短行动态对齐规则：文字实际长于 availableWidth 时整体 leading，否则 center；随真实当前行或宽度变化更新，不能把 30Hz 状态提升回宿主。音符、无音符、内嵌、展开的外层实际坐标和裁剪与现版对照。
3. 行变化和失败回调异步投递并附带视图代次及歌曲身份，处理前确认仍为当前挂载实例及当前身份；切歌/卸载后失效。切歌重置只针对对应身份，避免旧失败把新歌锁入回退。不要在 SwiftUI 更新事务内直接改 @State，也不要创建每帧回调或无限重试。
4. 新增真实 NSHostingView 宿主测试（单个可复用隔离画布，不批量开关窗、不操作真实播放）：注入新后端抓图失败，对比回退后的完整行与原始 CompactLyricsView 的尺寸、音符/文字位置及截取；覆盖长短句、音符/无音符及内嵌；验证原生计时器和 capture 窗口释放。补旧回调在切歌/卸载后到达的隔离用例。不得只测 fallback struct 或镜像实现的常量。
5. 复跑普通与实验构建、相关定向测试；维持普通 Release 不含实验实现、锁屏不使用实验路径。保留未验证的 1x、动画逐帧、CPU 等风险，像素差异不得假称等价。

输出 `docs/reports/desktop-lyrics-experiment-integration-r1.md` 和真实测试数、视觉证据。只做开发验证，不打包、不启动/替换 App、不提交。完成后停止等 Codex 独立验收。
