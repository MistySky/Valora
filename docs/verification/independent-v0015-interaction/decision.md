# 设备、音乐、歌词与多屏联动测试

结论：本轮隔离联动范围通过，未发现需要产品返修的新问题。只新增独立回归测试，没有修改生产代码，没有派新任务。

## 新增交叉回归

测试文件Tests/ValoraTests/IndependentInteractionTests.swift，使用真实AppModel、ConnectivityController、LyricsController、WindowCoordinator和PresentationController，设备源/歌词提供者/声音为隔离fake或spy，不操作真实系统媒体与设备。

1. 新设备提示抢占紧凑歌词期间更换歌曲；歌词控制器取得新曲歌词；展开音乐并显示音量后关闭设备，音乐展开/音量状态不被重置；收起后恢复新曲歌词。歌词请求仅发生于两次歌曲身份，不因设备提示或展开音量而重复获取。
2. 设备提示期间切到另一注入屏展开，再切回，保持最多一屏展开，提示不中断；关闭音乐不误关设备提示，随后关闭设备无残留通知；音乐重新开启后恢复歌词和活动屏归属。
3. 已连接设备跨20%低电量边沿触发一次声音spy；期间暂停音乐，等待超过音乐3秒空闲和设备5秒提示；提示结束不能恢复已超时音乐/歌词；恢复播放后正常显示歌词且不重复低电量音。

3/3通过，耗时8.94秒，摘要test-summary.log；原始编译/运行日志/private/tmp/valora-interaction-test.log。两次测试清理接口/Swift6编译问题已在测试代码纠正，不是产品运行失败。

## 视图联动复核

复用刚独立签名的V0015-R4候选/private/tmp/valora-independent-v0015-r4/Valora.app（生产源码本轮未变），运行--verify-connectivity至本目录connectivity，31/31通过。已目视检查expanded-music-with-connection-pending.png及compact-connection-restored-lyrics.png，展开播放器/底部歌词和提示结束后紧凑歌词恢复正常，无叠字。验收视图来自自身SwiftUI层级cacheDisplay，不证明AVPlayer视频图层或物理屏幕效果。

本轮没有重跑无关全量测试、没有修改生产代码，因此沿用上一轮205全量测试、两项新增权限边界及构建签名结论，不将三项新增联动描述为重新全量测试。

## 实机边界

没有真实播放/切歌/seek/音量写、连接耳机、播放提示音、修改权限或登录项；无安装发布/Git提交推送，未开启定时器。真实授权弹窗、真实AirPods及3D声音、物理双屏、真实QQ人声同步仍保留待验，不以注入显示器或fake媒体冒充实机通过。新菜单栏监控/Codex/日历尚未接入，不在本次联动范围内。
