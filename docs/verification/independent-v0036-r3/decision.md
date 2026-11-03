# V0036-R3 独立验收：几何前进，真实呈现接线仍不接受

## 已修与通过
上轮compact真实presenter快捷径与unlock直接恢复音乐的两个独立失败已通过。本轮33项中原31项通过；新增2项均失败，共3断言失败。所有测试均fake窗口/Space/事件/调度/声音，无真实锁屏/NSPanel/Space操作，不启动候选。
18份归档源hash全部匹配（修正的原版函数路径有效）；17份Valora源中仅本轮Codex新增测试变动，其余16份匹配。候选binary4ccc271c80a06943e23620a3d0d7797c6243693fbae499ced29aee53bbd18dbf，codesign strict/deep独立通过。

## F1 收起阶段缺presentation Space拥有权
LockMusicCoordinator.syncLockIndicator只调用updateNotchMount(wanted:lockIndicator.showsBadge)。showsBadge仅locked/unlocking=true，locking/neutralizing/restoring=false。
- 新testIndependentLockNeutralAttachesBeforeShowingBadge：lock edge→collapse完成→neutralizing，model.isSessionLocked=true、geometry.compact，但lockNotchMounted=false。真实锁屏早已进入登录界面，此时普通用户Space的notch不足以证明过渡可见。历史复刻Space挂载链已记录普通用户Space会被登录界面遮住，不能用静态geometry==compact冒称真实收起显示。
- 新testIndependentNeutralGeometryRetainsNotchSpaceOwnership：unlock→open glyph结束→restoring，仍处于呈现锁定门控，但notch已detach；缺少先完成neutral回收再移交普通窗口的明确拥有权边界。真实解锁是否已返回桌面仍需实机时序，这里fake证明的是提前detach事实，不冒称已实际复现视觉帧。
窗口挂载与glyph内容须分开；不要求neutral显示锁图标，而是保证需要渲染收起形变时该进程窗口仍能呈现。

## F2 仍靠固定0.12s抢跑下一段而不是收起completion
neutralizing/restoring用badgeAnimation spring(duration:.45,bounce:.2)提交geometry，然后scheduler after.12直接locked/hidden开始反向展开。没有使用该geometry动画.logicalComplete回调。因.12与.45提交节奏不一致，有在达到基础刘海之前反向展开的明确风险；即使fake中目标CGSize精确等于compact，也不证明屏幕插值已经到达目标。
这是源码/时序契约审查，不谎称测过实际动画帧。用户核心要求完整收起→再展开，必须用呈现完成契约而非再猜一个delay值。Reduce Motion也需可完成语义，不增加常驻timer。

## 判定/范围
总体暂不接受。保留R3几何、原版源/用户观察区分、材质待实机边界；限定修呈现拥有权及完成回调。不扩大功能、不改普通音乐/耳机/日历/监控/已确认UI，不真实锁屏或替换用户independent-v0036-r1运行包，定时器仍关。material仍未同壁纸对照，不能宣称底色已修好。
