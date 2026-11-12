# 优先修复：桌面歌词偶发不显示 / 律动停止，点击刘海恢复

用户反馈：日常播放中偶发，不限定解锁；点一下刘海恢复。当前build45。暂停下一批性能改造，优先正确性；Pi沿用当前会话/模型/分支，不提交推送，不覆盖已有工作。

## 已确认的独立复现

Codex新增 `Tests/ValoraTests/IndependentWaveformReturnTests.swift`，已单独跑过，1项失败（有意保留为待修复回归）。日志 `/private/tmp/valora-waveform-return-independent-20261109.log`。

单个离屏窗口中：waveform.configure(playing:true)发生在window仍隐藏时→时钟未注册；之后只orderFrontRegardless，等待一次短runloop，时钟仍未注册；再用完全相同参数configure，立即注册恢复。测试最后断言恢复不应依赖额外configure而失败，修复后应通过。没有批量闪窗/循环压力，也未操作用户播放。

源码：CompactWaveformView.synchronizeTimer以window.isVisible门控，clockTick在隐藏后stop/unregister；恢复依赖configure/viewDidMoveToWindow，orderOut→orderFront不会改变mount。既有PlayingWaveformVisibilityTests在每次orderFront后手动configure，掩盖了缺口。build45隔离全局进度广播后，不再有持续AppModel刷新替它兜底。

注意：这个测试证明一个实际生命周期缺口，不证明用户每次日常偶发都由它造成。必须另查无orderOut情况下是否有断链，以及hover显示暂停图标的正常状态，不能将两者混为一谈。

## 实施边界（Codex决定）

1. 将桌面面板实际orderOut/orderFront与native动效的停止/恢复建立明确、事件驱动的连接。优先在WindowCoordinator/NotchPanel已知的面板显示完成点，给已挂载native动效发送一次可见性变化通知（小接口/弱注册或轻量视图遍历均可），停止走隐藏边界，恢复发生在实际orderFront之后。waveform用最新playing/reducedMotion/suspended条件重新协调时钟。同一状态不重复注册；不依赖用户点击、媒体元数据变化或新的进度广播。
2. 不恢复AppModel全局4Hz广播，不新增常驻恢复轮询，不每帧重新configure整树，不依赖已证实不可靠的borderless occlusion通知，不改变click-through/sensor/窗口尺寸/Space。显式可见性通知须覆盖实际桌面隐藏/显示、初次挂载、同曲返回、活动显示器切换；多屏每个native view按所属窗口判定，不能把全局notchSurfaceOnScreen当每个窗口可见性。
3. 歌词单独排查并给出证据：NotchView歌词显示条件、LyricsController加载状态发布、ExperimentalDesktopLyricsView host identity/generation与异步line/contentWidth回调、native active/stop/remount、单次boundary唤醒和连续时钟。确认在同曲恢复/同identity卸载重挂/空行到非空行/播放中可见性变化时，已经缓存的当前行能主动重新对齐到最新进度，并重新协调时钟；旧generation回调仍必须拒绝。若renderer已显示当前行但host丢掉一次回调，必须有受控重同步，不能靠下一次切句或用户点击。
4. 不凭猜测同时改所有歌词路径。先写能揭示所发现缺口的最小回归，再修它；若歌词问题暂不能复现，报告排除项和剩余假设，可加debug有界诊断计数/状态，不能宣称同一根因已确认。不要打印歌词全文或个人数据，不引入Release常驻日志/全屏鼠标监听。
5. 保留build45的资源优化、歌词逐字高亮/翻转/标题滚动/律动幅度节奏及所有交互。暂停、reducedMotion、suspended、隐藏状态必须继续正确停钟；恢复不重置标题/歌曲/播放状态，不重置原动画epoch，不更改系统减弱动态设置。

## 验证与交付

先让独立失败回归通过；补“无额外configure恢复”“已播放→隐藏停钟→同曲显示恢复”“暂停/减弱动态/悬停切换不错误启钟”，歌词按已证实路径覆盖。仅少量单窗口离屏验证和状态测试，不批量闪窗/反复开关/压力，不操作真实音乐/音量/锁屏。必要相邻回归包含进度隔离、seek、歌词换句/空行恢复/锁屏active清理。旧测试不得通过额外手动configure掩盖生产边界。

写 `docs/reports/desktop-lyrics-waveform-return-20261109.md`：明确已复现/仅假设、修改位置、测试数与日志、未验项。必要验证通过后按AGENTS长期授权交付一个新的Release候选，保留现有实验配置；自动build+1、签名/hash/清单，正常退出build45→零实例→启动唯一新包，不强退/不覆盖Applications，保留build45回退。完成即停等Codex验收。

锁屏开歌词的性能抓栈已保存于 `/private/tmp/valora-lock45-stack-with-lyrics-20261109/locked.sample.txt`；那批每帧渲染优化先不做，勿混入此次恢复修复。
