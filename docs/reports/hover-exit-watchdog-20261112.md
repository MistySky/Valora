# 悬浮退出位置检查候选

## 背景和授权

用户确认按“真实候选验证区域感应＋仅悬浮期间退出检查”执行。Codex直接负责，分支codex/resource-idle-render-dedup；本笔接续build67媒体通知/窗口去重，未更改歌词、动画或缓存策略。

现有真实应用证据：音乐关闭，远离刘海晃鼠标20秒平均18.45%（包含15秒sample），ps12.1–21.1%；停止后无探针20秒1.19%。热点为AppKit事件线程接收/解码WindowServer事件，业务鼠标回调零星。三进程无窗口对照未接收到事件，结果无效；因此本笔是需实测的候选方案，不将global monitor移除残留假设冒称已证实。

## 改动

仅WindowCoordinator鼠标退出事件来源改变：

- 移除悬浮时注册的全局/本地mouseMoved、leftMouseDragged监听，以及仅供这两个监听使用的排队合并任务。
- 保留现有NSTrackingArea及小sensor处理进入/退出；原624×320画布、可见轮廓、动画参数/计时、命中路径、悬停延迟、展开/收起与点透赋值逻辑不改。
- 仅当任一panel.pointerInside时，创建一个common-mode Timer，沿用既有1/120秒位置处理节奏。检查当前位置并走原trackMouse路径；离开后立即invalidate/nil，远处鼠标不触发此检查。
- 隐藏、锁屏、清除鼠标归属与coordinator销毁时停止Timer。拖动仍受pointerInteractionActive保护，拖动结束后下一次检查释放已经移出的鼠标。
- 构造函数增加可注入的当前位置读取闭包，生产默认NSEvent.mouseLocation，用于无鼠标注入的有限回归。

该设计不是常驻桌面轮询；悬浮内静止时确实仍有120Hz位置检查成本，需真实测量并如实报告。约8毫秒只是目标检查间隔，不能承诺系统调度下硬实时或零体感差异。

## 回归

58项定向测试通过，0失败。新增3项使用离屏fixture和实际Timer.fire回调：

1. 没有mouseExited事件时，fallback仍修正click-through并停止；停止后不再读取位置；原动画画布frame不变。
2. 拖动保护期间保持鼠标归属，结束后fallback恢复点透并停止。
3. 隐藏/锁屏时停止，再次进入时重新启用。

同时覆盖旧退出兜底、多屏鼠标归属、属性去重、固定外轮廓、媒体通知去重、锁屏协调器回归。没有自动操作真实媒体或移动鼠标；这些测试不等于WindowServer实际点击送达或动画体感验收。

日志/private/tmp/valora-hover-watchdog-tests.log；git diff --check通过。尚未提交、推送、合并或发布。

## 实测计划

独立候选构建签名后正常退出旧实例，确认0实例再启动唯一新候选，不覆盖Brew。先在未进入刘海时测远处鼠标，再让用户进入/离开刘海并检查设置和其他软件点击，再次测远处鼠标；区分首次启动与曾经悬浮后的状态，避免漏验监听生命周期。资源降幅与体感以真实候选数据为准。

## 已生成并启动候选

- 1.0.6/build68，路径/private/tmp/valora-hover-exit-watchdog-20261112/Valora.app。
- 显式VALORA_LYRICS_EXPERIMENT=1；Valora Self-Signed；主机环境严格深度签名校验通过。
- binary SHA256：8b612ea7f98563a807271fd746e6e6890e09b579d25af4fbecd46eef71841fa4，与build-verification.json一致。
- 正常退出已核对路径的build67/PID47652，确认0实例后启动build68/PID71033，确认唯一进程及路径。
- 构建日志/private/tmp/valora-hover-exit-watchdog-build.log。未改用户音乐设置，未覆盖Brew。

真实验收已先启动有限240秒、1Hz的只读ps记录，再请求用户开始动作，以减少工具启动延迟漏采的影响。采样文件/private/tmp/valora-build68-mouse-live.jsonl；停止标记/private/tmp/valora-build68-mouse-stop.flag。正在等待用户开始动作确认，尚无性能结论。

## 第一段真实鼠标验收

用户明确选择“现在开始远处晃鼠标”。build68/PID71033，音乐总开关保持关闭；无sample探针的20.12秒CPU累计差分均值1.29%，RSS73.58–73.70MiB。已提前运行的1Hz日志覆盖动作开始时段；另存独立20秒采样/private/tmp/valora-build68-far-mouse.json，动作确认标记/private/tmp/valora-build68-far-mouse-start.json。

本段未再出现build67远处晃鼠标时ps12–21%的高段。旧版18.45%窗口带sample，新版不带，因此不使用两者计算精确百分比收益。下一段必须在进入/离开刘海并确认点击后重测，尚不能仅凭首次启动后的结果宣布全部修复。

## 悬浮、点击之后的真实复测

用户明确回复“点击正常，现在再次远处晃动”，确认进出刘海后设置页签和刘海外其他软件可点击。紧接的20.10秒平均CPU5.37%，前后半段分别约6.26%与4.48%。用户随后明确纠正：“5.37是播放音乐了”。因此该窗口应标记为播放音乐期间的鼠标测试，而非关闭音乐后的残余鼠标异常，不能与首段音乐关闭的1.29%直接比较。数据/private/tmp/valora-build68-after-hover-mouse.json的原label没有记录播放状态，no-media-query只是跳过查询，不能证明音乐关闭。

随后请用户不再操作设置/进入刘海，只在远处晃动；用户确认开始。15秒sample期间，独立1Hz记录中完整覆盖的14.12秒CPU差分1.42%，ps0.2–1.6%。AppKit事件线程MessageHandler采样权重仅15/12692，先前build67鼠标高段为4193/8031；这些只是不同采样窗口的权重，不能转换成CPU百分比。未采到checkHoverExit、updateVisibility、updateTrackingAreas或歌词渲染热点，trackMouse仅一个边界事件采样权重。原先大量WindowServer事件解码热点在此窗口消失。

修正结论：首次按音乐关闭条件测试远处移动为1.29%；进出刘海后用户确认点击正常，播放音乐时该段CPU为5.37%。之后只晃鼠标的复测为1.42%，事件接收热点消失，但这段没有独立查询或确认播放状态，不能继续标为音乐关闭，也不能据此推算播放开销下降。5.37%不再列为已知残余鼠标异常，更不能归因于设置收尾。不同状态不能直接比较或计算优化收益。用户当时已播放音乐，但未明确评价音乐动画体感；实际物理拖动和锁屏恢复也未复测，代码参数未变及定向测试通过不能代替这些场景。

相关文件：

- /private/tmp/valora-build68-after-hover-live.jsonl
- /private/tmp/valora-build68-after-hover-mouse.sample.txt
- /private/tmp/valora-build68-residual-repeat-result.json

本轮记录均已结束（首个240秒记录自动结束，第二个记录写停止标记后正常结束），没有留下持续监测任务。build68保持唯一候选，不再追加代码修改；未提交、发布或覆盖Brew。
