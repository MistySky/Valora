# R3 独立验收

2026-11-07。上一轮宿主重绘/隐藏恢复回归已通过。原同组测试 57 项，56 通过、1 跳过；日志 `/private/tmp/valora-lyrics-r3-independent.log`。

仍不接受：R3 未遵循派工第 3 条，添加了 `displayTime(for:)` 的 `abs(now - sampledAt) <= 60` 限制，超过即使用 sampledAt 显示，以照顾固定 1970 锚的旧测试。有效锚不会因为超过 60 秒自动变无效，该规则使本应显示乙的 61 秒进度显示甲。

已新增 `testValidPlaybackAnchorOlderThanOneMinuteStillInterpolates`：当前真实 Date 减 61 秒作为锚，歌词甲起点 0、乙起点 60；未等待一分钟、未启窗口。11 个独立用例中 10 通过、1 失败。日志 `/private/tmp/valora-lyrics-r3-age-independent.log`。

要求删除这种按锚年龄退回旧进度的规则，不提高阈值，不按测试环境分支。固定锚几何测试应注入匹配的显示时钟，真实行为测试保持默认实时钟。显示、生命周期恢复、边界选行使用一致时钟接口；播放锚只供插值。不要为测试改变真实算法。

视觉门槛仍未解决，本轮没有改变字体或实际运行版；CPU 未验。
