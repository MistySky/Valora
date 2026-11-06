# V0030-R2 限定返修：补全异步动作所属生命周期

先读independent-v0030-r1/decision.md。原resume回归和懒transport修复通过，保留成果，不重做UI/日历映射/下载算法。整体尚未通过，以下仍是R1要求的原范围。

1 testIndependentAutomaticEnqueueCannotStartAfterFeatureOff已失败（本地Range，关闭后downloading/activeCount1）。引擎addDownload另排自动start Task，adapter只跟踪resume不够。所有deferred入口需真正受功能off屏障约束，尤其默认自动新建及冲突addSeparate/restart/队列续启；可最小注入manager运行gate或改adapter控制自动开始，但保持Convoy单模块正常语义/默认用户体验，不能用永远关闭autoStart规避。补回原有效两断言，快off-on旧任务不能复活，明确新用户动作仍能开；自产temp/Range，无真实Downloads/Trash。若Vendor修改同步patch/manifest和可重建证据，不改checkouts或全局HOME。

2 IndependentHolidayDispatchTests已失败：ensureEvents后立刻hide，排Task尚未执行仍读transport一次。loadEvents排Task在实际调用transport.events前重新核started/panel/gate/generation，并正确释放inFlight/pending排队状态，不能简单return造成之后永不刷新。实际transport异步队列的执行边界也需遵循可取消/访问门控；stop/撤权同样拒绝未开始请求。保留已有在途合并/晚响应拒绝、源筛选和日历显示映射。使用fixture spy/gated transport测隐藏/stop/撤权发生在排队后执行前、重新打开仍可新读、快换月仅latest，无真实EventKit读取。

3 全量334例中旧IndependentMenuBarMigrationTests授权回归失败（fake读取预期1实际0），并出现系统存储连接诊断。检查所有Test/preview/QA默认HolidayProvider，fake普通events不等于节假日也fake；明确注入nonReading或fixture，使未有意验证真实系统的路径0真实store创建/metadata/event calls。既有测试有效断言保留，必要完善等待稳定条件，不以删除测试、改期望0、关闭日志或大幅sleep掩盖；报告诊断实际来源，不无证据归因用户权限。

pi先只跑原失败+相关下载/日历/开关定向；成功交付，Codex最终集成。无需重复3分钟审计或全量/UI映射，必要release/签名一次。新候选/private/tmp/valora-v0030-r2-candidate，报告docs/reports/v0030-r2.md。禁止覆盖dist/当前运行包、退出用户软件、真实个人日程/系统权限/媒体设备/浏览器/cookie/helper/文件删除、Git提交推送/改归档模型历史；不恢复定时器、不进入V0031。完成停等独立验收。
