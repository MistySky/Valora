# V0012-R2 独立验收：限定R3

独立原163项测试通过（60+103），独立构建/private/tmp/valora-independent-v0012-r2/Valora.app及deep/strict签名通过，独立歌词QA28项通过并产生qa/视图。原非合作provider deadline测试通过；词内横移已使用真实fraction、局部Timeline统一选行/填色。接受这些子集。

新增独立立即取消回归失败：IndependentLyricsDeadlineTests.testImmediateCancellationDoesNotRetainController，在start后立即cancel，保持owner20ms使已取消task进入handler，再释放owner，等待provider超过600ms完成后仍不释放controller。日志/private/tmp/valora-independent-v0012-r2-cancel-entry.log。源码对应LyricsDeadlineRace.cancel先finish、continuation尚未attach时结果丢失；attach不检查finished/保存结果，永不resume。

另两处源码确认尚未满足同步安全：

- CompactLyricsView依旧以model.elapsed与Date()在init/onAppear/onChange建锚，model没有该elapsed对应采样时刻。R2报告声称保留采样时刻不符合当前源码。例：采样时刻t=0 elapsed10，0.20秒后挂载，建锚(10,0.20)，会显示10而非10.20；展开/加载重挂载最多落后一个0.25秒采样周期。需要真实采样锚跨挂载保留。
- LyricMetricsCache key仅line.start+line.text，不含word分段；换歌/版本后相同行起点和文字但不同word分段会复用旧width数组，currentWord按新words索引读取旧数组，有越界路径。必须按完整分段/歌曲身份失效并防御索引，补回归。此项为源码确认、尚未动态制造产品崩溃。

胶囊补充快照可见居中歌词，圆弧不再大圆头；最终用户实机审美和人声试听仍待用户，不将注入截图称实机通过。R3仅上述三个确定问题，完成再验收，不进入清理。
