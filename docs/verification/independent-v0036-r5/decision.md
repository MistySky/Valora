# V0036-R5 独立复核：可交单次实机验证，不标记动画通过

## 确认
- 独立34定向fake全部通过（coordinator23+core11）；测试源已读，继续隔离真实NSPanel/Space/通知/声音，没有用户锁屏或桌面动作。
- 来源清单21份archive、18份Valora全部hash匹配。候选binary89269c156d670d7d317a15336e5e0fdd8158b90317f2a1f92f228458bd52992d匹配，codesign strict/deep独立通过。
- 生产改动确实位于NotchPanel.constrainFrameRect和WindowCoordinator.anchorPanelTop：返回调用者frame；orderFront之后以display.frame.maxY计算目标顶边，frame相等则不写，不使用经验y偏移、不加常驻timer。
- 保留R4logical animation completion、neutral期间Space所有权、解锁music窗口清理、epoch、设备/音乐门控和用户功能取舍。没有改底色/普通媒体/Calmon/品牌或恢复废弃功能。

## 不得夸大
- 没有采到真实窗口/WindowServer frame。AppKit约束只是候选根因，不能从用户视频就唯一确诊。本轮没有新增锚定路径的真正无界面失败回归；34项主要覆盖既有锁屏状态，不证明NSPanel系统约束或真实插值。
- 默认关闭diagnostic最多120条事件、仅本进程窗口，不读取其他窗口标题/内容。当前实现只在anchorPanelTop校正后记录；这能看校正后自报frame，却无法单独区分校正前窗口是否被下移，也不能观察WindowServer-only transform。若视觉仍失败，应在下一次试验前补对应before/after及窗口/内容坐标诊断，不重复猜补偿或催用户多次重录。
- 材质仍未同壁纸对照，当前也没有声称根视图dark ColorScheme已还原完整原版链。

## 判定
代码/构建签名/资源与既有回归子集通过，可作为下一次用户手动锁解候选。总体动画验收仍待真实确认，不能称“下浮已修复”。当前运行/private/tmp/valora-v0036-r4-completion-candidate未退出/覆盖；R5未启动，dist不动。无新派工/定时器/真实锁屏/媒体设备或系统权限操作。
候选 `/private/tmp/valora-v0036-r5-window-anchor-candidate/Valora.app`。
