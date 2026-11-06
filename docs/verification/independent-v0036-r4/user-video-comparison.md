# 原版与Valora R4 用户实机录屏对照：仍不接受

原版：b0f89d1549a5b675dd1c50d20d32aa01.mp4，用户已明确确认原版Alcove，19.233s/1280×720/30fps。
Valora：e3f0b00d7d8e3e783e7fadd915c7fa37.mp4，用户在Codex已启动R4候选后提供对应录屏，20.833s/1280×720/30fps，SHA256 c3037125a7f3d825dd76212076b9d3f2c9b9c944d50a1d2746c262eba2614e90.
两段原视频均保留用户原目录，不复制进项目；派生图只临时分析。当前Valora候选binary d07b9112b1b72784a22b72484a3ecae88bbfd69cab656ff5cf74bf22f7da70cd，启动前34定向fake/签名通过不能覆盖视频实际失败。

## 明确可见的差异

- Valora第一次锁屏约5.3–5.8秒：锁条在硬件刘海下方形成独立横条，上下之间可见壁纸间隙，然后回到顶部；第二次约15.8–16.3秒重复出现。
- Valora第一次解锁约10.6秒附近亦短暂出现脱离顶部的锁条，随后回顶部显示open glyph，再收回基础刘海。
- 原版约13.5秒起从顶部刘海左右扩展，约17.1秒起开锁、继而左右回收至基础刘海（约17.6–17.8秒）。已检查的帧未见相同的脱离硬件刘海下浮过程。
- 两次锁定重复现象，不只是一次偶发。固定模型目标topInset=0和目标NSWindow.frame不变的fake断言，不能证明WindowServer/登录Space切换的实际屏幕位置。
- 浮出的条中可见锁glyph，不把它误认底部锁屏音乐控制卡。
- 手机在运动、透视与拍摄距离不完全一致，只断言相对屏幕边框/硬件刘海的可见分离，不把视频像素等同SwiftUI point，也不拟合精确弹簧常数。
- 本视频没有清晰底部完整控制卡材质，仍不能验底色。两段也没有清晰“音乐重新展开”的可比段，不编造该段原版实机证明。

## 定位边界

这是真实视觉失败，不等于已唯一确诊为某个Space transform或NSWindow constrainFrameRect。需要核主窗口/hosting顶锚/坐标系/系统菜单栏与Space过渡/原版窗口类和挂载时序；不能只再调phase/delay说完成，更不能凭猜测加固定y补偿掩盖。

临时证据：/private/tmp/valora-lock-video-comparison/valora-full-5.5.png、valora-lock1.jpg、valora-unlock1.jpg、valora-lock2.jpg；原版裁帧 /private/tmp/valora-lock-video-review/lock-sequence.jpg、unlock-sequence.jpg。只读这些与顶部动画有关区域，忽略视频中的工作内容。
