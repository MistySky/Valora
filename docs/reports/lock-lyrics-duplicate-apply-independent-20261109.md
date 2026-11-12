# build48 输入去重独立验收

独立定向24项通过，另补过渡中的暂停/seek和失败回退2项通过，共26项，0失败。日志 `/private/tmp/valora-build48-independent-20261109.log` 与 `/private/tmp/valora-build48-transition-independent-20261109.log`。失败注入测试有预期image capture failed输出，不是测试失败。

完整key覆盖snapshot有效标量、内容revision、host identity/generation、active及失败注入，跳过前仍wire当前回调；lyricsRevision仅在歌词状态实际赋值变化时增加，无每帧timeline深比较。普通新进度anchor立即apply；相同输入外壳更新不增加apply，内容替换不被吞。clockTick诊断已递增。30Hz时钟、0.2s外壳翻转及真实4Hzanchor均保留。

候选 `/private/tmp/valora-lyrics-apply-dedupe-20261109/Valora.app`，build48，签名strict/deep通过，SHA256 a7c3ea539f9677ef30d89be0079e8a0bfba6a351ae9ba8cd65bf1b34d8b2b5b8。默认实例81766正常退出→零实例→以显式open --env重启同一候选，唯一新进程和诊断文件实际输出已核验。会话：
{
  "directory": "/private/tmp/valora-lyrics-dedupe-check-20261109-224730-2c4677",
  "pid": 83525,
  "app": "/private/tmp/valora-lyrics-apply-dedupe-20261109/Valora.app",
  "build": 48
}

首条JSON歌词开关false、零native；外部监控第一轮已就绪，用户需开启歌词播放并自行锁屏。尚无build48真实CPU降幅结论，不能将26项通过当作资源验收通过。


## build48 开启歌词锁屏实测

用户配合播放并锁屏；内部32行均确认lyricsSwitch=true，单实例lock活跃且clock注册，无fallback。外部样本锁屏22:49:25—22:50:30（北京时间），30个区间；剔除sample扰动区间，全段CPU均值8.31%，去掉起始10秒稳定均值7.55%，中位7.98%，RSS128.69—132.62MiB。解锁后原监控覆盖22秒，去掉初始10秒CPU均值2.42%。原始会话 `/private/tmp/valora-lyrics-dedupe-check-20261109-224730-2c4677`。

与build47开启歌词稳定7.28%比较，本轮7.55%，没有可见下降。未严格控制歌词位置/词密度，不能据+0.27个百分点认定回归，但不能宣称性能达标或显著优化。

计数证明去重真实生效：包含切句的2秒窗口，旧apply10.22/s→新4.45/s，新requests10.36/s、skipped5.90/s；update/CA旧40.60/s→新34.95/s。无切句窗口新apply4.00/s，clock29.97/s，update/CA33.96/s；图片/文字/layout重建均0。共享30Hz时钟仍正常，未以停动画换CPU。两轮统计窗口长度和词句不同，不给计数差直接换算CPU。

结论：重复输入处理已经减少，但实际锁屏CPU未明显下降，本次资源目标不接受为已达成。保留正确的去重，后续需分析持续30Hz mask/CA提交的实际成本和更新方式，不能继续把同一项输入去重包装成主要降幅。另4Hz新anchor仍触发即时draw；它们是不同输入，未经时序正确性分析不能直接删除或降频。暂无需用户再次锁屏。
