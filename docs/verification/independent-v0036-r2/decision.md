# V0036-R2 独立验收：核心过渡未通过

## 结果
28项（coordinator18+core10）中原26项通过，Codex新增2项失败，共4个断言失败。所有使用fake窗口/Space/事件/scheduler/sound；一项故意使用真实生产PresentationController.collapse（只运行状态/SwiftUI transaction，无真实NSWindow/锁屏/媒体控制）验证生产接线，不再用FakeCollapse遮蔽。未启动候选或更改用户运行版。

## F1 紧凑音乐锁定直接跳过收起
新增testIndependentCompactMusicDoesNotSkipCollapseOnRealPresenterPath：音乐左右翼存在，expanded=false，visibleSize.width>geometry.compact.width。锁事件后实际.phase立刻locked，而不是locking；showsLockActivity立刻true。
原因：PresentationController.collapse138–145只管展开播放器，当phase.collapsed时同步completion立即return。紧凑音乐左右扩展不是expanded播放器。R2没有任何路径先移除compact liveActivity宽度；锁/音乐在实体或模拟刘海通常都增加74pt，因此可能直接内容交叉淡化，几何完全没有用户要求的先收回再展开。
pi原testLockWaitsForBoundedNormalCollapseBeforeShowingBadge注入FakeCollapse，人工持有completion，看似等待，但与生产默认compact同步完成不一致。

## F2 解锁没有锁状态收起后再展音乐
新增testIndependentUnlockRetractsBadgeBeforeRestoringMusicGeometry：open glyph阶段结束后.phase=restoring，但showsMusicActivity已true，visibleSize为259x32而基础compact为185x32，两个断言失败。R2所谓restoring只是恢复音乐后的0.12s settle，没有中间neutral几何。用户要求开锁→收起→再展音乐，当前依然open glyph→音乐直接切换。

## 其他审核
- pi所谓顶边锚定测试读coordinator.panel.frame.minY，是独立锁屏音乐卡窗口，不是顶部notch窗口或NotchShape轮廓，不能验证用户向下拉出的bug。无界面后续测试必须观察生产notch可见几何/contour/phase和completion边界，不能改测别的窗口常量。
- private候选binary f799bbffaef4b7741367c108cccee2bc1235379af54778fb88ba05863734d171，独立codesign strict/deep通过。
- 来源清单19项中17项真实hash匹配；另2项是旧错误目录、sha256=null，不是有效证据。正确lock-appearance-0.6.5路径下两函数均另有hash匹配；修报告/manifest错误索引即可，不宣称整份19有效。
- 迁入18份源码除Codex本轮新增测试变动外17份均匹配交付。未改生产。
- material差异删除darkAqua/白stroke源码已确认；根视图仍强制dark ColorScheme、实际壁纸采样/appearance未实测，不能断言用户底色问题已解决；不能把函数未设appearance当作整条父容器没设appearance。
- 0.8/0.12等仍是复刻/新增策略常量，不是逐帧原版证据；不要求凭空改另一个值，重点是几何过程与阶段真正确立。

## 判定
总体不接受，限定R3修紧凑收起/neutral几何/再展开及生产链路回归，保留生命周期、解锁窗口清理、资源及UI取舍。真实动画与底色仍待证据核对，不以fake或签名代替。当前运行independent-v0036-r1不动，无新安装/Git/定时器/真实锁屏操作。
