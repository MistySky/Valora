# R4 独立验收：时间语义修复通过，整体交付尚未通过

2026-11-07。按用户指定的 5 分钟检查节奏跟进原 OpenCode 会话，R3 新增 60 秒回退被独立回归证伪后定向退回 R4。R4 已完成并通过本次独立复测，当前执行任务结束。

## 已接受范围

- 删除按锚年龄回退 sampledAt 的规则，源码默认显示时刻来自当前时钟。
- 自动显示入口共享时钟接口；固定时间几何用例显式注入时钟。核对独立用例原断言保留，真实 Timer/宿主重绘/隐藏恢复/61 秒锚用例仍使用默认实时钟。
- 已发现的持续换句、边界重排、行尾更新、属性失效、出栈横坐标、重绘回跳和恢复追赶回归均通过。

## 本轮实测

```sh
swift test --filter 'IndependentNativeLyricsRowTests|IndependentLyricsFrameReplacementTests|LyricsLineFrameCacheTests|NativeLyricsRowPrototypeTests|SeekProgressTests|DesktopPlayingCadenceTests'
```

58 项：57 通过、1 跳过（可选像素探针）、0 失败。日志 `/private/tmp/valora-lyrics-r4-independent.log`。其中独立原型回归 11/11；生产缓存相关 9/9；播放节奏 6/6；seek 8/8；OC 原型测试 23 通过、1 跳过。

本结论只接受隔离原型的本批正确性修复，不代表生产集成、全部视觉场景或性能验收通过。

## 保留门槛和下一步判断

R2 保存的原型长句图相较现版字形显得更细，见 R2 独立报告。R3/R4 未动绘制，因此视觉差异仍成立。换句过渡逐帧、完整无障碍集成等尚未验收；CPU 无可比实测。

下一步应解决文字保真，再做有效 CPU 对照。具体方向由 Codex 决定：优先评估保留当前 SwiftUI Text 绘制、仅在换句/绘制属性变化时准备静态文字容器，逐帧通过外层原生遮罩与位移更新；这样保持现版字形输出，避免为了 CATextLayer 改字体粗细或字距。该方向尚未派工、实现或证明收益，需作为单独有明确边界的验证任务。

没有替换当前 App、操作真实播放、打包安装、提交推送。监控仅在本次活动任务内进行，没有创建永久后台自动化；本批已完成，无待运行 OC 任务。
