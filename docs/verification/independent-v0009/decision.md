# V0008/V0009 独立验收（2026-10-24）

结论：V0008设置精简子集接受；V0009尚未通过完整验收，需限定修复暂停空闲计时。真实双屏体验待实际设备条件验证。

## 已独立核验

- 重新执行 scripts/build.sh，候选位于 /private/tmp/valora-independent-v0009/Valora.app；构建与 codesign --verify --deep --strict 通过，不替换用户当前候选、不安装。
- 原有测试 Valora 29 + ReferenceCore 62 全部通过（test.log）。
- 独立 --verify-settings 使用隔离QA偏好与生产窗口工厂；亲自查看 General.png、Now-Playing.png：仍为620×687、两页原样式，仅删除条目，悬停关闭时不显示延迟；音乐页仅总开关、进度样式、实时波形。
- 检查 Sources/Tests 引用：controlChoice/shuffleMode/repeatMode 专用链路已移除，手势/触觉未恢复。菜单栏打包仍为Outline-v7。
- 独立 --verify-multidisplay 12项通过，使用真实协调器与注入屏幕，不等于物理双屏验收。
- 右键菜单代码共享基础文案/动作，禁用版本、设置⌘,、分隔、退出⌘Q；未复制播放/显示屏项。pi提供紧凑/展开截图；本轮未独立点击真实菜单，不宣称已独立实机验证。

## 必须修复：暂停期间切换显示选择后，空闲计时永不完成

独立新增 MultiDisplayCoordinatorTests.testPausedIdleDeadlineSurvivesDisplaySelectionChange（保留在测试源中）。用fake歌曲暂停，使mediaIdle.pending=true；切换All displays到Main display；等待3.6秒后mediaIdle仍visible=true且pending=true。idle-test.log记录两条断言失败，已实际复现，无真实播放器写操作。

原因：WindowCoordinator.place调用PresentationController.resetForScreenChange，后者取消idleTask，但保留mediaIdle.input/pending；相同输入再次调用mediaStateChanged时update返回false，无法重新安排任务。换屏属于呈现变化，不能永久中断共享媒体空闲生命周期。修复应明确保持剩余期限或重新建立有效计时，不在同值metadata轮询时无限延后；覆盖拔插/禁用再启用同类路径。

修复前不宣布整体验收通过。歌词仅待办，不开始实现，不恢复定时器。无真实播放/seek/音量/登录项/权限写操作。
