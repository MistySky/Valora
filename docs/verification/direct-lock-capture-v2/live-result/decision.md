# 实机取证：已定位窗口系统呈现层缩放/下移

51条，未耗尽120预算，含shape/window/space/event及锁定解锁归位。开头有模拟活动，随后两轮真实锁解；rawevent因去重仅第一轮边界，后续phase/window仍完整。

关键同windowNumber2442：
- sequence27/30真实锁定：AppKit frame[552,797,624,320]、host[0,0,624,320]，内容screen顶1117；Quartz bounds X552,Y0,W624,H320。
- sequence33 unlocking：AppKit frame与host不变、topInset0、物理几何185x32不变；Quartz bounds变成X574,Y40,W580,H298。横向比例580/624=.9295，纵向298/320=.9313；明显系统窗口呈现缩小且顶边下移。
- sequence35 restoring：Quartz恢复X552,Y0,W624,H320；AppKit一直没有被改成下移位置。
- 第二轮sequence45 unlocking重复：X571,Y34,W586,H301，之后sequence46恢复。
- 锁中windowSpaces[1,145]，普通[1]，解锁后回[1]。同窗口持续保留桌面和锁屏空间成员。屏幕几何/safeArea/模拟开关未变。

判定：可以确认所采解锁瞬间，软件窗口的Quartz呈现边界受到缩放/位移，而非本地AppKit frame/host geometry向下移动。这与用户视频整条黑色软件区域下浮相符，用户观察正确。锁定早期Quartz样本未抓到变换瞬间，不能把此次解锁样本冒称每个锁定帧都已测到。但整体范围已定位到窗口系统呈现/交接层，不再继续调glyph/本地y偏移/动画duration。

仍需区分的具体机制：普通桌面Space过渡与add-only双成员的因果关系、私有Space具体参与合成策略等未单变量验证。windowSpaces同时归属是实测事实，不是其唯一根因已证明。不要恢复已失败R8迁移严格gate。

下一步最小可审查修复方向：参考DynamicNotch锁屏期间挂起普通primary并使用独立顶部承载overlay，避免复用仍参与普通桌面系统过渡的同一个窗口；复用现有NotchView/状态/动画与几何，单屏最多一份可见活动，真实锁优先，neutral期间正确持有。模拟已正常不重做。先将这一承载交接作为唯一变量构建与fake验证，再用户单次实机。不能宣称已有修复通过。本轮仅读日志/保存证据，无系统锁屏或媒体控制。
