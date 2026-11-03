# V0039-R1 真实体验拒绝：独立窗口未成功接管

2026-11-03 用户实测：仍下移。当前重建包 /private/tmp/valora-v0039-r1-live-20261103/Valora.app。

实际日志seq14独立overlay561在neutralizing失败，reason=failure:space-migration-failed、visible=false。没有ready记录。seq15原primary526回退进入[1,36]，而非成功独立接管。seq22 locked Quartz[583,55,562,289]、seq28 unlocking[573,37,582,300]，AppKit仍[552,797,624,320]、hostTop屏幕1117。确证实际运行的是旧fallback并再次被系统缩放/下移，不能宣称独立overlay方案被实际验证无效，也不能声称本版已修复。

源码ensureOverlay先make隐藏窗口→查询原Space→迁移→orderFront。native要求original非nil且非空，否则不调用迁移。新未显示窗口可能尚无Space是待证假设；日志把所有native失败折成一条并硬写unknown，无法区分原查询nil/空、符号缺失、迁移status失败、迁移后未验证。不得断言唯一原因，不得盲删guard或再次猜Y。

37项Swift/6场景fake只说明已覆盖逻辑，不保证真实WindowServer的未显示窗口生命周期；真实体验明确未通过。保留本次用户失败证据，限定R2查窗口就绪与native分支，避免同条件无有效新证据反复要求用户锁屏。
