# V0100 无引用残留与摘要无障碍限定清理

现有会话继续；V0099/R1独立接受11项（MediaSchedule实际5而非报告6），build8签名hash单实例通过，请更正旧报告数量笔误。用户功能认可，UI/动画/布局保持；Objective-C/Perl保留。

## 范围
1. CodexUsageSummaryRow只有定义，无生产/测试调用，删除旧独立卡片View。保留同文件仍被CalendarMonitorSharedView和测试使用的CodexUsageSummaryFormatter；可最小重命名文件体现formatter职责，不改日期格式、剩余百分比、两行同卡Grid/字体/对齐。PreviewCodexUsage只有定义无调用可删。每项报告给出引用证据，不能删实际Formatter或额度后台生命周期。
2. LockCardAppearance失效字段glassOverride/glassScheme/contentScheme、环境变量VALORA_LOCK_CARD_GLASS；实际LockGlassSurface固定darkAqua/variant5、前景palette仍用。只留下当前生产读取的外观策略与颜色，不改材质/白色前景/波形/进度透明度。wallpaperIsNearlyWhite生产恒false、浅色palette若无真实入口可同批删；测试若只验证已不存在的实验功能可移除或改为有效当前约定，不为了保留旧测试恢复浅色分支。避免重构播放器/新外观框架。
3. CalendarMonitorSharedView摘要accessibilityLabel需按真实showsStats和codex是否存在组合：只监控只念内存总量/剩余、磁盘总量/剩余/运行；只Codex只念5H/WEEK剩余与重置时间/卡数；两者都显示都念；均无不输出虚假监控或额度。保持现有可见文本、布局、开关及数据取值不动。可用小型纯格式函数进行四组合验证，别为测试构造真实窗口/朗读或访问真实账号额度。
4. 同批仅修正已核过时注释：LockMusicState reserveFullExpansion“can never cover the avatar”改为相对产品参考线，21%不是系统头像边界；保留数值与真实外接接线、不改用户已确认位置。其它显然与已固定外观矛盾的说明纠正；不批量格式化/改名成熟公共API。

## 不在本批
不做验证代码目标迁移或AGENTS历史归档（下一批）；不删用户资源/图标旧候选/历史任务报告/许可证；不做全局无引用自动删除，不动媒体/耳机/日历授权/焦点/锁屏动画/底层桥。

## 验证交付
只影响范围纯格式/外观/设置等无窗口定向；删除旧功能专用测试须列明理由和引用证据；不全量/资源压力/闪窗/真实媒体或系统权限。一次Release新/private/tmp候选，构建号自动9或当前下一号；签名/hash/Info与JSON一致。正常退出旧版→0→唯一新包，不强退/覆盖运行包/dist，不Git提交push。报告docs/reports/v0100-unused-ui-appearance-accessibility.md，完成停等Codex独立验收。保留用户顺序：全部收尾→完整功能全局回归→缺陷修完后资源及Alcove动画流畅度专项。
