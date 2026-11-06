# V0106-R1 测量有效性限定补齐

V0106基线子集独立复算通过，但不能作为最终性能通过，见docs/verification/independent-v0106/decision.md。沿用同一会话，只修开发工具/报告，不改产品。

1. CPU17.87%是阶段平均，不是峰值。用已有原始逐秒样本独立差分给出采样间隔峰值（1秒尺度），修正文字。无消融/栈不归因暂停CPU到120Hz合成、协调器等；这些只能写可能因素。全关仅QA子集，不包含audio/Codex/monitor等真实服务成本。
2. BaselineDisplayLink增加单调墙钟到达间隔统计，与sender.timestamp间隔分开。两个都不是呈现帧。记录实际panel.screen而非用回调Hz猜落屏；NSScreen.main不能证明面板屏幕。
3. 现在silent fake无snapshot，elapsed固定，长句/换句没有实际推进。增加完全本地fake带时间戳snapshot，交给现有MediaController时间锚，验证elapsed推进、word index/fraction/offset或换句确实变化；fake seek仅fixture，绝不真实播放。
4. 做一份优化编译的独立QA宿主，在单独/private/tmp scratch输出用release优化+显式VALORA_DEVELOPMENT，仅用于仪器（清楚标为优化QA，不是正式Release产品），不覆盖常规Release产物，不打包。正常Release仍开发实现编译掉/flag拒绝；定向检查该边界。若不能安全独立编译先说明，不降低正式Release门控。
5. 只补一轮有界短测：优化QA紧凑播放30秒（真实fake锚）、同窗单次交互15秒、暂停30秒；display-link仪器开/关可各做短30秒对照，区分额外开销。不重跑旧6分钟/全量/闪窗循环。原71.5ms间隔仅定向复核，报告最大间隔对应区间；不能保证不再出现就称消除卡顿。不改UI/动画节奏。
6. 生产音频0.5秒轮询未实测及真实媒体/锁屏/完整正式资源成本如实待观察，不擅自读真实媒体/账号/个人日程/权限。禁止自动控制Alcove。不为填满报告冒用fake数值。
7. 针对性逻辑测试：新flag isolation、fake时间推进、统计差分/arrival，保持Release启动门控；不全量重跑。保留首败证据。原报告追加更正，不抹掉历史数字。结束清理QA宿主且build15仍唯一正式实例，未加构建号、不Git。

交付docs/reports/v0106-r1-baseline-measurement-validity.md和docs/verification/v0106-r1原始数据，停等Codex独立验收。可用作日常包前的基线核对，不宣称实机完全流畅/长期无泄漏。
