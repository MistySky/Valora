# 资源优化第一笔：跳过歌词空图层事务

分支codex/resource-idle-render-dedup，从1.0.6发布提交f6666aa创建。用户授权Codex直接实施；本笔无Pi委派。生产仅NativeLyricsRow.swift draw函数修改，版本与运行实例不变。

## 改动

原draw的fill、opacity、position三个属性分支本来已有去重，但即使三个分支都不写入，仍无条件CATransaction.begin/commit。现在用完全相同的三个条件，在全部为false时提前返回；有任意变化仍按原帧执行相同赋值。更新入口、共享30Hz、下一句边界、文本准备、动画身份/曲线/时长、布局算法和外轮廓均未改。没有新增缓存或持久对象。

## 证据

新增LyricsNoOpTransactionTests先在原代码执行：3项出现6条失败，均为空提交计数超过预期，证实用例能抓住旧行为。改后：
- 暂停图像行重复render不增加提交，基色/高亮图片非空字节相等，位置、尺寸、mask不变。
- 逐字开始前的等待区间不提交空事务，但时钟保持注册；到开始后的相同时间点高亮立即推进，下一1/30秒同样推进。
- 只有opacity/position变化且高亮不变时，仍各提交一次并实际更新对应图层。

定向集合：52项，51通过、1可选像素探针跳过、0失败（NativeLyricsRowPrototypeTests.testPrototypePixelsAgainstTheShippedRow需VALORA_ROW_PIXEL_PROBE=1，未启用）。覆盖现有歌词逐字/长句/切句、暂停恢复、转场时钟、空行与外轮廓回归。加强非空像素字节断言后新增3项复核通过。git diff --check通过。

日志：
- /private/tmp/valora-render-dedup-before.log
- /private/tmp/valora-render-dedup-after.log
- /private/tmp/valora-render-dedup-pixels-recheck.log

## 效果边界

证明的是无图层变化时的显式空提交被消除，不是整机CPU降幅。连续逐字高亮或滚动每帧参数确实变化时仍照常提交，故本笔主要减重复调用/静止帧的无效工作；不可据此保证播放CPU从4%到1%。Core Animation自身也可能合并空事务，需要后续同条件实测判断收益。未改内存策略。

未构建正式包、未替换/重启本地Brew实例、未操作媒体或设置、未提交推送。测试不能替代真实流畅度确认。后续应逐笔核对稳定几何下重复布局，并在允许实测候选时验证CPU/内存与交互后回落，不合并未验证的大范围优化。

## 用户请求体验版（后续授权）

用户随后要求“启动下，我看下”。正式构建一次为1.0.6/build66，显式VALORA_LYRICS_EXPERIMENT=1，签名严格深度验证通过，元数据与实际二进制摘要一致。启动前pgrep确认0实例，无须退出旧进程；启动后仅PID41443，路径/private/tmp/valora-render-dedup-preview-20261112/Valora.app/Contents/MacOS/Valora。没有覆盖Applications/Brew安装。

binary SHA256：987cde113c0053e9b58b4ebe57cbd1edf6c50c53ccf3640652242b193db8a560。构建日志/private/tmp/valora-render-dedup-preview-build.log。CUA启动后屏幕捕获报-3811，进程检查独立确认启动成功；未据此声称界面或体感验收通过，等待用户体验。

## 首次播放观察

用户反馈不点击时可能约6%。随后仅ps读取（不叠加sample），build66/PID41443连续24.19秒累计CPU差分均值4.26%，ps平滑读数1.8–4.4%。数据/private/tmp/valora-build66-first-playing-observation.json。与用户稍早6%的时段不同，不能否定其观察；与旧版4.02%也不是同歌曲同片段A/B，不能声称CPU提升或退化。

本笔仅减少画面不变时的空事务。逐字高亮/滚动持续变化时依然每帧提交，因此播放稳态收益可能很小；截至此时没有证据证明整机CPU明显下降。
