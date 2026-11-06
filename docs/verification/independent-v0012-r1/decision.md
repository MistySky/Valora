# V0012-R1 独立验收：部分通过，限定R2

Codex独立原测试161项通过（Valora59、Core102），构建/private/tmp/valora-independent-v0012-r1/Valora.app及codesign --verify --deep --strict通过。歌词隔离QA 28项通过，实际SwiftUI视图快照已独立生成于qa/。日志/private/tmp/valora-independent-v0012-r1-{test,build,qa}.log。

短句及展开加音量快照显示歌词组合居中、音符按封面主色，展开歌词置底；胶囊轮廓源码已限制基础半径。隐藏入口、QRC取消上抛和缓存前检查已补。以上接受为子集，不等同实际人声同步通过。

尚需修复：

1. 新增独立回归Tests/ValoraTests/IndependentLyricsDeadlineTests.swift真实使用不可取消continuation延迟（不是try? sleep，后者会因取消立刻返回）。50ms预算后200ms检查状态仍loading，预期unavailable，600ms provider结束才收尾；测试失败日志/private/tmp/valora-independent-v0012-r1-deadline.log。结构化task group退出等待不合作child，3秒收尾要求未满足，不能一直持有旧控制器/任务。原测试未覆盖这种不合作情况。
2. CompactLyricsView.timedContent中的阅读位置仍是before + currentWidth/2，未使用fraction；R1移除了旧offset动画，当前字内offset恒定、换字跳变。30Hz Timeline只平滑填色，没有平滑横移。按真实字内进度连续算阅读位置，seek仍立即定位。
3. 当前行依然由外层model.currentLyricLine基于0.25秒elapsed选择，内层才用30Hz本地时钟。因此行与字不是同一个连续时间源，换句仍可能迟至下个采样；新视图onAppear又以旧elapsed配当前Date建立锚。需要统一局部时间源并明确最近播放器采样时刻，避免加载/展开时重建旧锚产生相位偏移；不提高全局发布频率。

视觉证据限制：本次qa/lyrics-nonnotch-pill-compact-review.png有正常轮廓/封面波形，但歌词区域为空，尽管对应QA只检查model布尔值仍报通过；短句和展开快照有字。尚不能确认是捕获过渡时机还是产品显示缺陷，必须补实际可见歌词的同条件胶囊视图证据再接受该子项，不能仅用模型状态证明文字可见。

下一步docs/pi-tasks/v0012-r2-local-timeline-deadline.md，仅限定上述返修，暂不清理。实际QQ人声同步/物理多屏仍待用户实机验证，未操作真实媒体。
