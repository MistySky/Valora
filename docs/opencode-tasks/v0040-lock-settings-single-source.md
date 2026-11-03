# V0040 锁屏设置精简：各模块总开关为唯一来源

用户在Codex聊天已明确确认并要求交现有OpenCode完成，且要求先提交再派活。前置本地checkpoint已完成：9b2953e，当前codex/lyrics-word-sync。不推送。继续本会话ses_e60ad9e4bffekz1hsfhtNOnPtJ，不新建/改模型。

先读AGENTS.md最新覆盖及docs/verification/independent-opencode-lock-2026-11-03/decision.md。你上轮修复已用户实测认可；Codex独立40Swift/12native回归通过及四轮overlay独占/解锁Y0核验。保持当前修复，绝不能退回旧add-only或再改锁解动画。旧pi请求已撤下，不由pi并行开发。

## 本批已确认范围

1. 锁屏页只保留3项：锁屏总开关、锁定提示音、解锁提示音。保持现有Alcove卡片/字体/顶距/图标，不重做UI。声音默认仍off/on，已有偏好保留。
2. 删除“模拟锁屏”测试开关及其专用实现/状态/订阅/测试。它是V0038为了排查加的桌面动画模拟，不是通用的“强制模拟刘海”；不要搬到通用，不动通用强制模拟刘海外形功能。只删确认专用残留，公共真实锁动画/几何与阶段状态必须保留。
3. 删除锁屏页“音乐”“设备连接”重复设置及专用偏好读取。音乐页现有nowPlayingEnabled作为唯一音乐总开关：on允许真实锁屏音乐卡按既有hasTrack/idle策略显示，off立即隐藏并停止所属锁屏更新，普通音乐逻辑不改。旧allowNowPlayingWidgetWhenLocked=false不再暗中阻止显示，不删除/改写真实用户偏好以实现。
4. 设备连接页的真实总开关/授权状态为唯一来源；锁屏设备信息随该模块on/off实时响应，不以旧allowConnectivityWidgetWhenLocked独立控制。关闭后立即清理锁屏设备卡/观察显示，不能用缓存displayDevices继续显示。保留真实蓝牙授权入口，不触发新授权。旧锁屏专用偏好只停止使用，不清理用户defaults。
5. 锁屏总开关仍控制整个锁屏体验（顶部锁/解动画、声音、锁屏卡）；关闭不影响未锁屏音乐/设备各模块。不将音乐/设备全局开关反向改写，不新增设置。

## 验证与交付

仅本批必要无UI功能回归：锁屏启用+音乐开/关+设备开/关；锁中切总开关即时隐藏/恢复；锁屏主开关off；旧锁屏偏好false不再劫持全局on；模拟入口/专用符号无引用；真实锁解阶段顺序、取消/stop有效。不跑全量、--verify/真实NSWindow/Space/UI循环/批量截图/性能压力或真实锁通知。

保留已确认独立overlay/独占归属/开锁→neutral完成→最新音乐。独立验收另发现native重复独占覆盖首次_originals问题已记录，本批先不并改native收尾，也不借精简全局重构。

必要release构建和签名；候选新目录/private/tmp/valora-v0040-lock-settings-candidate，绝不能覆盖dist、当前运行候选、退出/启动用户软件或改签运行包。报告docs/reports/v0040-lock-settings-single-source.md，列源码变更/定向结果/未覆盖实际条件，交付后停等Codex验收。不Git提交推送，不动来源归档，不操作真实媒体/设备连接/权限/系统设置/个人日程账号。定时器保持关闭。
