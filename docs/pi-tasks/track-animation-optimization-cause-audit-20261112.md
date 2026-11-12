# 结合Codex全部优化改动，核对整首切歌动画退化原因

用户最新指令：核心是“为了优化，切歌那边的动画被改了”，要求结合Codex决定/引入的改动，让Pi核对原因。这里指**整首歌曲切换时封面翻转及整个刘海的可见变化**，不能只分析同一首歌逐句换行。用户要求不随意改动任何刘海动画，原版很流畅。

沿用当前固定Pi会话/模型/分支。此批以只读因果核查和有限隔离复现为主：不改生产代码、不构建/替换候选、不改动画参数、不开/关用户真实播放/音量/锁屏/偏好，不提交推送。允许新增少量明确的测试fixture或诊断报告，不许压力/批量闪窗。

## 核查基准和范围

- 基准 main `6c98d2be683e035fdaab9f29dcbd795236748655` / 本机build26（只读保留，不启动第二实例）。当前为build59，实际运行路径先核对。
- 阅读AGENTS最新动画冻结/main回归约定、`docs/reports/main-interaction-regression-review-20261112.md` 及source manifest、前一份 `notch-track-flash-readonly-20261112.md`。
- 必须计入main以来所有未提交与未跟踪生产文件：CPU/鼠标优化、progress隔离、native歌词owner与真实keyed transition、共享截图宿主、封面ImageIO/identity等。Codex的设计决定和验收测试也应反查，不限于你最后一笔diff；不能因“只是执行Codex任务”排除某处设计。

## 不能重复的旧结论

1. `TransitioningArtwork.swift`没diff，只能证明该文件没改，不能据此说切歌效果没变。实际动画包含**触发次数/触发时刻、输入快照顺序、父容器几何、事务范围、窗口ordering、缓存构建时延**。
2. 旧报告把歌词的±26pt/0.2s参数写进封面flip段，应纠正；封面参数以ArtworkFlipMetrics及TransitioningArtwork实际实现为准。
3. lyrics loading→移除行/compact高度变化的主体路径在main已有；未经对照不能把它当新增原因，也不能默认保持占位作为修复，那会改变原交互。
4. 不能只再列一遍可能性，要找出**main正常、某项优化接入后新增异常**的最小事件链；如果仍无法证明，明确哪一环缺证据和最小需要用户怎样配合。

## 需要具体回答的问题

### A. 整首切换事件顺序/触发

比较同一组fake输入（正常新封面、封面先缺失后迟到、同封面不同曲、连续快速两次切歌）：main与当前何时发布artwork/identity/colors、title/artist/album/playing、mediaRevisionIdentity、lyrics loading/ready、songPeek/presentation？

记录封面TransitionController.update/runTransition次数和代次、外层show/hidden/phase、黑色notch尺寸/opacity/子树identity是否变化。证明是否重复flip、短暂placeholder/空图、先收后展、错误全树重建或局部动画transaction传播到父级。

### B. Codex引入的歌词表现层/准备窗口

新NativeLyricsTextPreparer的NSWindow orderFrontRegardless/close、owner.begin/invalidate、keyed child/冻结旧图、异步handoff，何者会随**整首切歌**触发？main没有这些窗口链。核对是否影响frontmost/NSApp激活/屏幕监测/NotchPanel ordering，或让新帧在不正确的时间提交。不要将旧句切换测试通过当作整首切换已经正确。

### C. 封面内存与progress优化的连带

完整有界像素identity相对原TIFF身份的语义、ImageIO提前解码、多个Published写入与进度订阅节奏变化，是否增加一次切歌内的状态转折或改变原动画起跑条件？同图lossless重编码/分辨率变化/实际颜色数据应分开，不因identity字符串格式不同就宣称必然多flip。

### D. 鼠标与刘海显隐路径

透明sensor/新tracking area、click-through setter、updateVisibility/place/root swap是否与切歌尺寸变化耦合，改变pointerInside/hoverScale或重新ordering？比较main持续mouseMoved与当前边界事件的后果，仅作为切歌回归因果核查，不借机另改鼠标风格。

## 证据方式

优先用现有fake/注入接口做有限离屏场景，记录事件日志和少量可见帧/几何数值；相同输入下把main相关函数/外层作为明确参考（必要适配要列明）。不将手动指定offset或终点像素一致冒充真实中段/触发顺序等价。

可以通过测试夹具中分开启用“只有封面优化/只有native歌词窗口/只有progress隔离”等方式缩小因果；不来回替换用户运行App、不改真实设置做试探。若isolated draw无法捕捉WindowServer闪烁，明确说明限制并提出一次最小真实录制/日志方案，等待Codex安排用户配合。

## 输出与停止点

新报告 `docs/reports/track-animation-optimization-cause-audit-20261112.md` 必须包含：

1. main vs 当前切歌事件时间线；
2. 每项优化对应哪种可见影响：已证明/已排除/仍假设；
3. 最小复现与日志/图片路径，未复现不能称根因已确认；
4. 建议最小恢复差异，说明为何恢复main触发/表现而不改动画效果；
5. 哪些之前验收只覆盖了局部，没有覆盖本次整首切换。

只给证据和最小建议，不立即实施。完成即停，由Codex审核决定下一笔，先回归main再替换候选。
