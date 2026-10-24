# V0006：按用户灰白菜单栏参考落实浅色源图标

用户最新给出`/Users/wangqing/Downloads/Velora-macOS-Icons-Transparent/light/Velora-light.icns`和菜单栏灰白圆角轮廓参考图，明确要求“这个提取做成菜单栏图标……参照这个”“你去完成”。当前任务是对菜单栏图标的最新修订，覆盖R3深色图转灰选择。

等当前V0005完成后执行，不打断/丢失设置精简。先读AGENTS与本任务。参考图片已原样保存docs/verification/v0006/reference/menubar-gray-white.png，必须实际查看。用户不喜欢单独重画V，保留其已给浅色图中的完整品牌构图，提取/缩放适合菜单栏的圆角轮廓和V层次，以参考图的灰白轻量视觉呈现，无彩色，避免深灰黑方块、厚重阴影/光晕或普通字母V。参考图是视觉风格，不是将其空心方框直接当品牌图标。

应用包AppIcon保持彩色浅色版。菜单栏来源独立使用上述用户浅色icns，不再指向深色资源。沿用Swift/AppKit/CoreImage原生运行时图像处理来灰度和必要亮度/对比度调整，保持透明外角、比例和18pt尺寸；isTemplate=false保留层次，不能整张设template压成实心方块。不要生成替代品牌图或修改用户下载源文件；无需额外图像生成/外部依赖。构建独立打包MenuBarIcon.icns并记录源指纹，校正相关验证描述。

输出最终dist/Valora.app、docs/reports/v0006.md、docs/verification/v0006/。在16/18pt实际像素尺寸看可辨识度，灰白、不带彩色、透明角、圆角和V层次；提供明暗菜单栏背景离屏预览并标注，条件允许只截实际菜单栏图标小区域，不收集私人窗口。检查NSStatusItem真正使用的图像，别只检查CFBundleIconFile。正常构建签名验证并确认应用彩色图标和V0005设置精简未回退。完整交付后停止待Codex独立复核，禁止真实播放/切歌/seek/音量/权限登录项写入、安装发布或Git提交。
