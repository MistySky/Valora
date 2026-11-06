# V0036-R1 独立验收与最小直接补修

## 代码复核
R1已修复上一轮state/sleeping复位、旧系统/Combine交付epoch隔离、informationAirPods发布、当前notch窗口provider/发布、nowPlayingEnabled订阅及过期注释。局部adapter seam真实使用fake windows/events/space/sound/scheduler；本轮已读测试及生产factory，不再调用真实NSPanel/Space/通知源。
10份归档来源hash均一致；20份迁入源码中仅本轮Codex补修的锁屏coordinator及对应测试2份变动，其他18份匹配交付清单。界面/动画/设置/固定策略不变，归档只读。

## 新发现的确定失败
新增 `LockMusicCoordinatorTests.testIndependentUnlockDetachesMusicAndInformationWindows`，完全注入fake，模拟锁定→解锁：音乐窗口orderOut但未detach。原R1组合55项中54过、此新增1项失败，日志before-tests.log。
原版复刻源码LockMusicCoordinator.setLocked(false)明确在解锁时orderOut并detach音乐窗口。R1却调用detachNotchIfNeeded，之后sync再次挂载notch；音乐窗口始终保留在owned Space，因visible已false而没有后续hideTask收尾。

## Codex直接最小修复
按复刻已有源逻辑把该调用改为 `lockSpace?.detachWindowNumber(panel.windowNumber)`，不改其它生产逻辑；顶部notch继续挂载到其0.8秒unlock completion。
补修后锁屏21项通过（coordinator13 + pure state8），日志after-lock-tests.log。随后增强同一独立用例验证notch动画结束前不拆、完成后拆，单项再次通过，日志unlock-regression.log。设备/媒体34项在补修前同轮全部通过；此次仅窗口清理一处变化，不机械再重复跑全组，更未跑全量/闪窗/性能。

## 测试边界
所有新coordinator用例使用fake窗口、fake Space、fake事件、fake scheduler和声音spy，无真实锁屏/窗口挂载/真实声音/设备或媒体控制。不启动新候选或退出用户R3版，不改变系统设置。
候选构建/签名和最终判定见下方追加记录。真实登录窗口可见性与命中、材质/时钟头像避让、实际锁解动画/声音、物理多屏及锁屏媒体更新仍待用户选择时机操作，不能以fake/签名宣称通过。

## 最终判定
本轮自动可验的源码/功能逻辑/构建签名/资源范围接受；不等于真实锁屏体验通过。独立release构建及deep/strict签名通过，锁解声音与项目资源逐字节匹配，macOS最低27.0。候选 `/private/tmp/valora-independent-v0036-r1-candidate/Valora.app`；二进制SHA256 `e536f1bc5c4468ee474e87d7547f8ff6317fba299e4388b3bbdc6863a1f34378`。候选未启动、用户运行R3与dist未改。
