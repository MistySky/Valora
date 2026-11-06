# V0106-R1 独立验收：限定基线通过，可进入日常使用包交付

2026-11-06。接受本轮隔离工具与短测有效性，不扩大为正式App全部资源/呈现帧或长期稳定性已验证。无新增生产功能阻断，不继续扩展测试或盲目优化。

## 独立证据

- 源检：AuditTickingMediaSource快照交给真实MediaController时间锚；四阶段记录实际panel.screen，timestamp/arrival独立定义。所有新增测量实现VALORA_DEVELOPMENT包围，AppDelegate审计入口早返回，不启动正式音频/媒体/日历/蓝牙等服务。
- 从short-baseline.json逐阶段重算累计CPU均值及≥0.8秒样本区间峰值，与报告四阶段数字均匹配；14个检查true。elapsed约32→62秒以及交互fixture seek/换歌后重定位与JSON一致。暂停Timeline=0。
- 独立定向25项通过（AuditTickingMediaSource4、LaunchPolicy14、IndependentDevelopmentIsolation2、MediaSchedule5），日志/private/tmp/valora-independent-v0106-r1-tests.log。未全量重跑/再次运行视图。
- 优化QA二进制SHA256 dc421489b65e3e1aad967efeee6c7c1dafc9914e48e5838a0b5d3ddf23e6c031与报告匹配。正常Release nm未发现ResourceBaselineAudit/AuditTickingMediaSource，实际--audit-resources-short退出2，未进AppKit。
- 独立ps：唯一正式Valora为PID69159，build15目录；无遗留QA宿主。不替换、不打包、不加号。

## 结果口径

优化QA播放约11.20%单核平均、交互14.35%平均/32.38%约1秒峰值；暂停4.48%，不能当完整正式App成本或归因特定服务。3分钟内存稳定来自原V0106短时Debug观察，不将R1的105秒扩大成长时验证。原71.5ms本次未复现，只说明本次；回调不是实际呈现FPS，未证明与Alcove同等流畅。

## 明确保留的非阻断限制

- 正式媒体子进程、CoreAudio0.5秒轮询、监控、Codex、实际锁屏/设备组合未包含；后续日常使用观察与必要定向定位，不将QA全关0.23%作为正式全关保证。
- R1第一次暂停teardown帧失败的中间JSON被OC覆盖，证据不完整，已在报告披露，不能称首次就通过；不为追补不可重建的旧运行再循环测。
- fake changeTrack使用Date而非注入now，注入时钟test在paused状态仅断言0未覆盖换歌后继续推进；本次实际测量用默认Date，两者一致，不使本次原始数据失效。仅测量工具防御性后续整理项，不改生产或阻断使用包。
- git diff --check仍仅CalmonCalendarView.swift:184 EOF多空行，最终打包/提交整理时处理；不是已修复，不虚报完全通过。
- 47项真实窗口自动测试未全执行、物理多屏及长期体感等限制仍保留。代码未提交推送，当前仍build15。
