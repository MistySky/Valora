# 优先回归调查：切歌封面翻转时整块刘海闪一下

用户正在实测build59时报告：切换整首歌曲、封面翻转时整个刘海明显闪一下；并再次强调不要乱动刘海任何动画，原先很流畅。内存实测已暂停，不能把此前纯fixture回归通过当作真实整曲切换已验。沿用当前Pi会话/模型/分支，不提交推送。

## 本批仅只读定位 + 有限隔离复现

不要修改生产代码、不要构建/替换候选、不操作用户真实媒体/音量/锁屏或偏好。先报告问题边界及建议的最小差异，由Codex决定修复；本次没有授权调整任何动画效果。可新增有限的隔离fixture/回归来复现，禁止压力/批量闪窗。

当前实际build59 `/private/tmp/valora-artwork-memory-bounded-r1-20261110/Valora.app`，本次启动PID17091（先核对，不假设仍在）；`/Applications/Valora.app`是真实build26，只读保留，禁止覆盖/同时运行第二个Valora。

## 优先核对（不能先把假设当根因）

1. `TransitioningArtwork.swift` 对6c98d2b发布基线没有源码diff；因此不能直接说封面翻转参数改了，也不能由未改该文件就排除数据/布局/事务引起的回归。内存改了NSImage准备和artworkIdentity；歌词表现层/共享截图宿主也已改变。
2. 同样的正常track metadata→artwork nil/late→lyrics loading→ready事件顺序，比较build26源码与当前NotchView/WindowCoordinator/Presentation/Models几何、mounted状态、whole-notch opacity/visibility/size。观察是否歌词loading导致showsCompactLyrics暂false→卡片/quickPeek收缩再展开、整根view重建或事务传播到父容器。
3. 检查图片identity/图片和颜色发布顺序是否令同次track变化触发多次flip/placeholder/queued；验证相同封面、不同封面、迟到封面，整块black notch不该随封面局部翻转清空。
4. 检查NativeLyricsTextPreparer创建/关闭离屏NSWindow、owner identity重置/handoff是否触发可见窗口ordering/focus/visibility链；不要误判为用户hover。不要为了取证输出歌名/歌词/截图个人窗口。
5. 比较build57（动画改后、封面优化前）与59对应源码路径，区分内存管线与歌词呈现层；不得擅自来回替换真实App做A/B，离线fake事件足够先定位。

## 输出

写 `docs/reports/notch-track-flash-readonly-20261112.md`：具体事件时间线/已复现与未复现、源码位置、可见闪烁证据、最小修复建议及为何不改变原动画效果；记录未验限制，不仅列猜测。若隔离复现能证明回归，留下失败回归并说明，不擅自修成不同效果/改断言。

不得触碰任何原动画参数/曲线/时长/位移/opacity、关闭动画或降帧。用户没有撤销原先要修回流畅的目标，但本批先定位，等Codex发最小修复任务后再改代码。原封面内存/歌词大范围优化先停止扩展。
