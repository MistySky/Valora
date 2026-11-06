# V0096-R2 独立验收：生产接线与当前候选通过，实机视觉待用户确认

- 生产LockMusicCoordinator.place已按实际target.isBuiltIn传入reserveFullExpansion，外接0.30分支已接通；内置仍旧策略。
- 独立运行52项相关无窗口测试通过：LockMusicCoordinator32、MusicDisplayPolicy7、LockCardLayout13。包含上轮原失败的生产panel.frame.minY断言：外接minY300/H1080从482.8变624，内置190.57保持不变。并非只测独立模型常量。
- 1080pt外接相对自身原点：旧实际top422.8→564，实际抬高141.2pt；正常歌词208高，底边214.8→356；全开240高，底边182.8→324。R2报告旧“正常歌词底边216.8”为算术笔误，正确214.8，不影响生产修复或141.2位移结论。
- strict/deep签名独立通过；候选binary SHA256 ce2e91bb9276efb720d41cfd6df8e64d2b14b78b81eac75f3780f9dd0d594914与报告匹配。git diff --check通过。
- 只读ps确认仅1个Valora进程PID78410，实际运行/private/tmp/valora-v0096-r2-layout-wired-candidate/Valora.app/Contents/MacOS/Valora。已是新候选，不再退出重启同一包；dist未动。
- 原头像遮挡修复的代码/集成候选子集接受。30%为产品位置策略，仍不是系统头像bounds；用户本轮尚待真实合盖、正常歌词/全展开与开盖位置查看。不虚报实机全部通过，不操作用户锁屏/媒体。
- 桌面QA预览仍有独立旧定位调用，不能把QA预览当作外接真实锁屏的验收替代；当前实际锁屏入口使用已修生产调用。后续收尾清理时另核，不扩大本批。
