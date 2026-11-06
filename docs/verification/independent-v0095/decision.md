# V0095 独立复验

用户反馈本版锁屏换歌“看上去没啥问题”，记为用户真实体验主流程正向证据，不自动扩展为所有硬件/网络状态通过。

独立相关41项：原锁屏歌词6、deadline2、锁屏协调器32均通过；新增testInterruptedLoadingResumesWhenSameLockCardReturns失败1项2断言。
- 注入慢A，锁卡显示且loading → 卡片隐藏取消 → 同一首卡片返回，期望恢复一次请求并展示A。实际timeline仍nil，provider.count=1（期望2）。
- LyricsController无需求分支取消loading后，currentIdentity仍保留A，返回时identity==currentIdentity而直接return，无法恢复。不能对所有unavailable重试，否则3s失败预算后每个metadata轮询可能重复请求。

原主缺陷修复子集接受，不回退已认可UI/歌词链路；只限定补恢复取消中断的加载。已完成结果同首不重请求、超时/失败同首不自动无限重试都须保持。当前候选45f76764...df982 strict/deep签名及SHA256独立匹配，实际仅PID63157单实例路径正确；不重复替换同一包。当前原主流程已可使用，边界补修交OpenCode。

本轮未操作真实锁屏/切歌/音量/设备，未做闪窗/全量/性能循环。
