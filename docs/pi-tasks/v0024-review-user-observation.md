# V0024 验收结论与用户实测消息（通知，不是新开发）

用户明确要求Codex验收pi，并把以下最新观察告诉pi。

## 用户实测与Codex观察

用户自己打开网页播放视频，音乐仍正常显示。Codex按用户“你可以看下”的授权，使用CUA展开音乐面板，看到音乐及进度持续更新；一次5秒限时、无封面的现有system adapter只读get确认当前bundle仍com.tencent.QQMusicMac。未控制播放器/浏览器或更改任何权限，不落盘歌名/歌手/封面。

准确结论：用户本次网页播放没有使系统Now Playing从QQ切走，现有system current链路已满足这次体验。不是Valora已实现独立音乐优先，也不能推断所有网页/浏览器都必然如此。

## Codex对V0024交付的验收

docs/verification/independent-v0024/decision.md：harness/result哈希、一次3样本约2.014秒/10秒硬限、只读API/脱敏输出/0命令0启动0权限范围接受。三次clientCount=0，未验证非零客户端字段/更新/控制；不认为这证明没有后台媒体或macOS必须新授权。独立ad-hoc CLI与现有Perl adapter执行上下文不同，不能混同；本轮不重跑探针。

## 当前执行决定

- 先保留成熟system current，不继续SourceCoordinator/多来源adapter改造、不加来源选择器或Automation/Accessibility权限，不用QQ弱AX替换丢进度/封面/歌词。
- 不再自动查询真实媒体/反复探针，不为制造冲突播放网页，不执行真实媒体命令。
- 后续若用户真遇到某网页抢走来源，再针对那个具体浏览器/网站场景提出最小验证。当前不扩新功能，不恢复定时器。

请仅将该验收与用户实测结论简短补入docs/reports/v0024.md（历史probe结果保留、不伪造改为非零）；写一段确认已知悉即可，不改生产/测试/资源，不跑构建、网络或媒体探针，不操作系统权限/设备，不Git提交推送/安装发布。完成停止。
