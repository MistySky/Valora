# build47 诊断候选独立检查

独立定向16项通过：LyricsDiagnosticsTests、IndependentWaveformReturnTests、PlaybackProgressScopeTests、IndependentLyricsTransitionClockTests、IndependentLyricsEmptyTransitionTests；日志 `/private/tmp/valora-build47-independent-20261109.log`。签名strict/deep通过，hash与Pi报告一致（65a5272e5c1f189c53c402933390d06af9a368154b40e29b8f23b5eb9d0fdfa9）。纯计数不等于最终呈现帧，也不能给出CPU精确分摊。

普通启动实例75861已正常退出、确认零实例后以同一build47启用显式环境变量。注意应使用macOS `open --env VALORA_LYRICS_DIAGNOSTICS_DIR=... APP`，而不是把变量只设给open进程。新实例唯一且已验证实际JSONL输出；首次记录lyricsSwitch=false、nativeLive=0，与当前关闭歌词一致。注册表弱引用、默认无timer/output，限时/体积上限实现存在；现有三个测试并未真实等待12分钟验证到期，不宣称长时实测通过。

读取字段限制：`systemLocked`来源CGSession字典，需与外部IORegistry锁定标记对照；fallback按role布尔聚合，不能用来精确计算同role多个fallback视图数。`nativeLive`为已注册且未解除的view数，不等价于进程所有存活view总数。`stops`包含重复setActive(false)调用，不是实际状态迁移次数。CA计数是draw显式事务提交次数，并非屏幕呈现或render-server提交数。按这些口径分析，避免过度推断。

会话元数据：
{
  "directory": "/private/tmp/valora-lyrics-compare-20261109-222507-e1f75c",
  "pid": 76758,
  "app": "/private/tmp/valora-lock-lyrics-diagnostics-20261109/Valora.app",
  "build": 47
}

外部监控第一轮已开始，用户尚需自行打开歌词、播放选定歌曲并锁屏。两轮请使用同一首歌尽量同一段；开/关歌词状态从内部JSONL交叉验证。当前未有本轮真实锁屏诊断结论。


## 开启歌词首轮初查

诊断会话 `/private/tmp/valora-lyrics-compare-20261109-222507-e1f75c`。外部lyrics-on样本已包含锁屏/解锁，锁屏单次调用栈成功；排除明确包含sample的区间后初读CPU均值约7.66%，仍需稳态筛选。内部锁屏+歌词42行中41行nativeLive/active/registered/fallback为1/1/1/0；起始曾短暂出现隐藏desktop-inline，退出曾有零实例，不能当作全程重复实例。

role=lock id4持续约78秒：apply约7.79/s、frameTicks/CA事务约37.95/s、mask更新33.40/s、textBuilds0.29/s、imageBuilds0.59/s、switches0.29/s。当前没有每帧重建图片的证据，图片数约每切句两张。clockTick字段全部为0，需要核对计数是否实际递增，不能用此字段推断共享时钟没运行。apply可能在换句的60Hz外壳动画更新期间额外触发，待按单行稳定期/切句期分开验证，不先归因或改动画。

已启动第二轮lyrics-off外部采样，内部诊断同一会话继续。等待用户关闭歌词并自行锁屏，暂未形成两轮最终对照结论。


## 开关歌词两轮对照完成

同一build47/进程76758/限时诊断会话。外部CPU由进程累计CPU时间差计算，排除sample_in_previous_interval=true的8秒抓栈区间，再去掉锁屏初始10秒。第一份lyrics-on外部监控尾部还录到了第二次无歌词锁屏，不能按文件标签误归类，须结合内部lyricsSwitch及真实锁屏分段。

- 开歌词锁屏22:26:02—22:27:23，稳定CPU7.28%，全段非sample均值7.66%，中位7.00%，RSS92.17—99.91MiB；内部41行均为lyricsSwitch=true，nativeLive/active/registered/fallback=1/1/1/0。
- 关歌词锁屏22:29:05—22:30:19，稳定CPU3.70%，全段非sample均值4.25%，中位3.49%，RSS130.22—134.61MiB；内部37行均为lyricsSwitch=false，nativeLive/active/registered/fallback=0/0/0/0。
- 稳定段差3.58个百分点，真实单实例native歌词有额外成本，但不以此精确分摊函数CPU；两轮起始RSS、歌曲段落不同，不以RSS差认定歌词内存成本。

按lock实例id4相邻2秒计数差分：无切句窗口16个/32秒，apply4.31/s、frameTicks和CA提交34.14/s、mask32.26/s，文字/图片/layout/hosting/root重建均0；包含切句窗口23个/46秒，apply10.22/s、frameTicks/CA40.60/s、mask34.19/s，switch0.50/s，textBuild0.50/s、imageBuild1.0/s，符合每句两张图。clockTickCount只声明未递增，是诊断缺陷，不能按0解释为无clock。

代码对照：NativeLyricsRowHost.updateNSView在任何外壳刷新时均wire/setActive/apply，apply无输入去重且立即update/draw。换句外壳60Hz进度会增加相同输入apply；正常4Hz新锚点本身是不同输入，不能把全部34Hz当重复或简单删除。下一批先对适配层完整输入做去重，保持30Hz驱动和真实新锚点/seek立即更新；不能承诺该项能吃掉全部3.58个百分点或保证降到3%。
