# V0012-R3：修正采样锚、分段缓存与取消先于注册

先读docs/verification/independent-v0012-r2/decision.md。保留R2已接受子集：非合作provider超时及时收尾、居中、圆弧、单一局部Timeline、真实fraction连续横移。仅修下述三项，不新增功能、不换架构。

1. 修复新增独立立即取消回归：Tests/ValoraTests/IndependentLyricsDeadlineTests.swift中testImmediateCancellationDoesNotRetainController已复现失败。cancel发生在attach前时，LyricsDeadlineRace.finish将finished=true且completion=nil，attach后来不能恢复。采用一次完成且保存完成结果/正确注册取消的门闩，保证先cancel/先complete/先attach均恰好resume一次。不要删测试或删20ms owner保活步骤，后者确保已取消task真实进入handler；timeout/provider waiters和controller不可永久挂起。补竞态回归，避免用unchecked Sendable掩盖未锁状态。
2. 真正保留elapsed的采样时刻。CompactLyricsView.init/onAppear仍是(model.elapsed, Date())，这不是采样锚；模型无elapsed对应timestamp。采样elapsed10在t=0，t=.20挂载时须显示10.20，不是10。可在现有model/媒体控制器保存一致的播放时间锚供歌词读取，保证快照、定时采样、暂停/恢复、seek、preview QA路径都一致，不提升全局发布/网络频率，不改进度条成熟体验。局部视图重挂载不能丢失采样年龄；编写使用延迟挂载/展开的可控时钟回归，验证不是仅实例化独立Clock常量。
3. LyricMetricsCache当前key只有line.start+line.text。相同文字/起点但不同word分段会拿旧数组，而currentWord索引按新line.words，可能越界。按完整分段/歌曲身份正确缓存或失效，加安全索引；同text/start从1个word切到多个word（及相反）必须重建正确尺寸，无旧段染色/崩溃。缓存仍有界，不每帧重复测量，不靠禁用歌词规避。

报告docs/reports/v0012-r3.md，包含新增独立测试及针对性回归、构建签名、必要隔离视图。实际QQ人声试听及物理双屏仍待用户；不操控真实播放器、不改系统设置权限登录项、不连接设备、不安装发布、不Git提交推送、不改归档及图标。交付后待Codex独立验收，暂不清理。
