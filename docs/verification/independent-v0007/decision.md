# V0007独立验收：设置修复子集接受，播放模式不通过

日期2026-10-23，用户授权测试随机/循环并验收pi。未恢复定时派工，未投递新任务。

## 已独立核验

- 正常scripts/build.sh --output-dir /tmp/valora-independent-v0007成功，签名通过；未覆盖用户当前dist候选。
- swift test独立运行82项通过：Valora19、ReferenceCore63，日志tests.log。
- 使用独立构建运行--verify-settings，隔离QA偏好，截图由真实SwiftUI视图层次渲染，不冒称物理屏幕截图。已查看General、General-hover-on、Now-Playing：保持旧控件/布局风格，灰色表面层次、悬停关闭时无延迟，开启时显示延迟滑块，标题标记整组已移除。
- 显示图标Main/All/Built-in/External映射不同且选择行和菜单共用映射，选项差异不误当同一图标。
- 源码检索手势/触觉入口已移除；普通按钮/seek控件保留；固定音乐值通过sanitizedMusicValues忽略旧覆盖；悬停关闭/延迟变化会取消旧任务。物理多屏选择/全屏/登录项写入未实测，不夸大通过范围。
- 对比描边/渐进模糊仍无渲染消费者，沿用已披露缺口，不因隐藏设置宣称效果实现。

## QQ真实模式测试

证据qq-modes.json。不输出歌曲文字、封面或用户账号。

- 系统当前来源确认com.tencent.QQMusicMac，初始暂停、原生模式“顺序播放”；系统payload不含shuffleMode/repeatMode。
- 原路径send6返回0，但QQ原生播放模式仍“顺序播放”。
- 原路径send7返回0，但QQ原生播放模式仍“顺序播放”。
- 原生菜单可从顺序播放切到“单曲循环”，说明可观察的原生状态可变。
- 在单曲循环下再次send7返回0，但QQ仍“单曲循环”。
- 通过QQ原生菜单恢复“顺序播放”，最后仍暂停；未切歌、未启动播放、未改喜欢/登录项/权限。
- 结论：当前QQ暂停会话中，Valora所用send6/7链路并未产生可观察的播放模式变化。adapter exit0只能证明MediaRemote接受命令，不能证明播放器执行。不扩大为所有QQ版本、队列及播放状态绝不支持；本次未在播放中或切换歌单后重测。

## 必须修复/收敛

1. Sources/Valora/MusicPlayerContent.swift:71使用(mode ?? 0)>0判开启。vendor/mediaremote-adapter/include/MediaRemoteAdapter.h明确Disabled=1、EnabledModes=2/3，故1会被错误高亮；nil又通过accessibilityValue被宣称关闭。应区分未知/关闭/开启，使用真实枚举映射，不能把nil伪装关闭。
2. :82只以mediaCanControl启用附加模式按钮，无模式能力及执行后状态确认；QQ当前会话未响应却仍可点。不能以测试fake send6/7成功宣称QQ功能可用。应对未知支持与不响应明确处理，或在验证可靠路径前禁用/提示该来源不支持。禁止自动改成QQ专用Accessibility后台控制而声称通用系统能力。

设置配色/精简/悬停/图标对应/标题移除限定子集接受。完整V0007新增随机循环控制不通过真实功能验收；不整体标记完成。等待用户决定是否继续限定返修，当前不自动派工。
