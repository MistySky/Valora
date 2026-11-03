# V0018 / V0019 独立验收（2026-10-25）

## 结论

V0019 设置小调整与实时音频波形移除接受。V0018 的实现与原生双击路由接受；原版封面动画的真实屏幕模糊/亮度/回弹体感，以及播放器最小化后的恢复未标记通过。没有发现本轮新增阻断项，不再派返修或自动开启下一模块。

## Codex 独立证据

- 当前源码完整测试：Valora 113 + ReferenceCore 114 = 227，通过，退出码 0。包括实际 NotchPanel 标题命中和 NSHostingView 封面阶段测试；它们不能代替真实显示帧和所有播放器的实机验证。
- 独立 release 构建、打包至 /private/tmp/valora-independent-v0019-candidate/Valora.app；严格深度签名通过。二进制 SHA256 与 dist 相同：da6d7d552e1f0366350424f90c3932736f26129f9d7d98b6cbef33d648f553fc。
- 签名实际 payload 保留 calendars entitlement，Info 保留日历用途声明，没有系统音频捕获用途声明。没有请求/接受真实系统授权。
- 当前构建独立隔离 QA：音乐 74、歌词 31、注入多屏 12、设备 32 全通过；全部 verification.json 已核 passed，不仅依据进程退出码。
- Codex 查看独立设置渲染：悬停并入通用卡，标题后 13pt 留白；音乐粉色播放图标/日历纸面图标保留；设备和日历各一开关；其余新增页真实占位。原型目录确实不存在。
- CUA 实际点击隔离设置预览的九个页签，AX 返回各页正确标题、音乐总开关/三种进度样式/歌词开关、日历单授权开关/非按钮手形、设备总开关、四个准备中页以及真实版本关于页。没有点击真实授权/登录项开关；关闭本次隔离预览进程。
- 实际展开运行中的音乐面板，用 CUA 在歌名区域双击。生产日志 2026-10-25 01:36:22 显示 Opening running media source: com.tencent.QQMusicMac，随后 Media source open request completed；QQ 音乐可访问窗口存在。这证明真实输入到生产 NSWorkspace 请求并成功返回，不以此推断所有窗口状态、所有播放器或最小化恢复都已通过。未发送播放、暂停、切歌、seek、音量命令。
- 阅读生产实现确认原生 mouseDown clickCount==2、当前来源保护、上一首/下一首菜单顺序保留；封面缺失占位不重现旧图、晚图进入既有横向收窄展开。查看用户原版/候选阶段对照，离屏图不能完整复现 blur/brightness，未宣称像素/体感一致。
- rg 核当前 Sources/Package/package.py：没有 LiveAudioTap/useLiveWaveform/audioCapture/process-tap 或 Accelerate 专用入口。普通波形时钟和音频输出音量桥接保留；旧 useLiveWaveform=true 测试字典不再有运行时消费者。

## 明确未完成范围

1. 仅音乐应用持续显示、浏览器/视频不抢占仍未实现：SystemMediaSource/MediaController 仍读系统当前媒体。V0019 只审查并记录该缺口，没有借设置改名宣称满足。
2. 原版动画体感、最小化播放器恢复、真实日历/蓝牙权限、物理双屏、QQ 人声逐字同步等没有由本轮 fake/离屏证据替代。
3. 构建仍有 CompactLyricsView 两处调用 MarqueeLabel.measure 的 actor-isolation 警告，和 SwiftPM 未声明 QRC fixture 警告；本轮未新增/关闭并发检查，不称零警告。测试运行另有系统 AddressBook XPC 诊断，未导致断言失败，未以其作为设备或个人数据访问成功的证据。

## 架构核查

Package.swift 为单个 SwiftPM package，没有外部 .package 依赖声明。三个生产 target：Valora（SwiftUI/AppKit 应用、状态/控制器/界面）、ReferenceCore（可复用状态、几何、偏好、歌词解析等逻辑）、NativeBridge（Objective-C C ABI 系统桥接）。两个 test target 对应前两者。音乐/歌词/设备按文件与控制器分工，尚非独立功能 package。第三方 MediaRemote 适配器由 vendor + 构建/打包脚本随包，不属于 SwiftPM 远程依赖。当前没有进行架构重构。

本轮没有修改生产代码、Git 提交推送、安装发布、恢复定时器或扩展新功能。
