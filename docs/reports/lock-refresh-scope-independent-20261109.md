# build45 独立验收（2026-11-09）

当前唯一运行实例 PID53834，路径 `/private/tmp/valora-lock-refresh-scope-20261109/Valora.app`；strict/deep签名通过，SHA256 `d71642b4c80fbfac4ebe69f2a2fe33d72914d9a8d1157f0a7e45544b67487971` 与交付报告一致。没有再次构建或替换用户运行版本。

## 源码核对

PlaybackProgress 以单个 Snapshot(elapsed,sampledAt) 发布；AppModel 兼容读写入口代理该对象，纯进度不再向 AppModel 整体广播。MediaProgressView、CompactLyricsView、ExperimentalDesktopLyricsView 已增加独立订阅，进度读写及现有时间锚点仍保留。未改4Hz媒体供给、30Hz歌词底层或翻转参数。MarqueeLabel 复用完整文本/字号/字重键的128项缓存，沿用原测量公式；MusicMarqueePair 每次body只计算一次longestWidth。beginUnlock三条直接移除窗口分支补lyricsActive=false。

## 独立测试

- `VALORA_LYRICS_EXPERIMENT=1 swift test --filter 'PlaybackProgressScopeTests|LockMusicCoordinatorTests|DesktopIdlePublishTests|DesktopPlayingCadenceTests|IndependentLyricsTransitionClockTests|IndependentLyricsEmptyTransitionTests'`：53项通过，0失败。日志 `/private/tmp/valora-lock45-independent-20261109.log`。
- 已构建产物补跑 SeekProgressTests：8项通过，0失败。日志 `/private/tmp/valora-lock45-seek-independent-20261109.log`。
- 总计61项通过。测试不证明真实锁屏CPU降幅或动画观感完全一致。

## 待实机

先保持歌词关闭、音乐播放，用户自行锁屏约2分钟，与build44关闭歌词稳定段10.42%对照；记录锁定状态、CPU和RSS。之后再按需要打开歌词检查逐字高亮/翻转、暂停、seek和解锁恢复。此处尚未有build45真实锁屏结果。


## build45 真实锁屏对照结果

原始 `/private/tmp/valora-lock45-no-lyrics-20261109.jsonl`，121个采样点，21:38:22—21:42:22（北京时间），每2秒读取累计CPU时间差、RSS及IORegistry锁定标志；用户自行关闭歌词并锁屏，音乐播放条件按用户配合，未自动记录曲目/进度。

锁屏21:39:56—21:42:22，74个采样区间：CPU平均3.54%，中位2.995%，范围2.49—18.95%；去掉初始10秒，平均3.16%。RSS101.25—106.50MiB。与build44关闭歌词锁屏平均10.54%、稳定10.42%相比，本轮平均低约66%，稳定段低约70%。不同时间的顺序对照，非严格控制实验；不能由此分摊文字缓存和进度隔离各自的贡献。

采样结束仍锁屏，因此本轮四分钟记录未覆盖解锁瞬间，不能据此宣布解锁资源清理实测通过。当前支持：无歌词锁屏CPU明显下降；开启歌词后的CPU和动态、seek/暂停/解锁观感仍待验。两轮启动时长/RSS基线不同，不能把RSS差值直接算成内存优化收益或证明无泄漏。


## build45 开启歌词后的实机结果

用户自行打开歌词、保持音乐播放并锁屏。本次读取到的原始记录 `/private/tmp/valora-lock45-with-lyrics-20261109.jsonl` 覆盖21:45:04—21:47:22（北京时间，读取时监控尚可继续记录）；锁屏段21:45:12—21:47:04，57个采样区间，约112秒。

CPU平均7.49%，中位6.00%，范围3.99—23.94%；去掉锁屏起始10秒稳定段平均7.18%。RSS140.31—146.73MiB。解锁段21:47:06起，包含27.49%过渡峰值；去掉解锁起始10秒后约3.12%（短窗口，不能作为长期恢复结论）。

与build45无歌词稳定段3.16%相比，开启歌词后高约4.02个百分点；顺序对照受歌词密度、曲目/进度等未控制因素影响，不能把差值精确分摊给native渲染或某个函数。相较build44有歌词稳定段10.72%，本轮低约33%。说明共享刷新优化对有歌词场景也有效，但开启歌词仍有可测的额外开销；若继续优化，应在开启歌词锁屏时再抓栈，先区分每帧渲染和4Hz进度更新触发的额外准备，不能盲目降帧或改动画。两轮RSS起点不同，不把差值当歌词内存成本。用户尚未确认本轮翻转/逐字高亮观感。


## build45 开启歌词锁屏调用栈

用户保持歌词开启再次自行锁屏。`/private/tmp/valora-lock45-stack-with-lyrics-20261109/locked.sample.txt`：21:49:29（北京时间），PID53834/build45，单次8秒/10ms采样成功。伴随锁屏监控读到84个有效非标记区间，均值约7.62%；包含采样扰动，非独立严格性能基线。

观察到 NativeLyricsRowClock → NativeLyricsRowView.update → draw → maskLayer.bounds / CATransaction.commit → CA::Context::commit_transaction。主连续分支13个inclusive样本，draw分支10个，事务提交分支8个；这些是包含式栈命中数，非CPU比例，也不能相加。另有1条切行→buildTextLayers→buildTextImages→renderTextImage，符合缓存文字在切行时准备的路径；不能从低样本推断绝无重复准备，但本次没有证据支持每帧重新画整行文字。其他样本仍有屏幕状态检测、音频输出轮询，波形只看到零星路径，不宜据此归因波形。

源码对应：NativeLyricsRowView.update 每帧仍做行查找/synchronizeDrawing/refreshLineEnd/synchronizeClock；draw 对改变的高亮mask和位移提交显式CA事务，现有代码已比较fill/offset，因此不能派“加一个同值判断”冒称新优化。候选优化应先核实实际活跃renderer数、4Hz apply和30Hz clock是否重复准备/更新、静态行/词间停顿是否仍无效提交；仅将不随帧变化的准备放到输入/切行边界，评估同一runloop内合并重复更新，保留30Hz可见采样、逐字时间函数、0.2秒翻转与所有交互。事务提交是必要动态成本的一部分，单次sample不能证明简单合并一定显著降CPU；需要定向计数与改后实测。
