# 无外框丝带 V 菜单栏模板 v2

用户确认：去掉外框、去掉渐变灰雾，用原品牌丝带V与透明交叠分隔，放大主体，由macOS自动配色。

Codex直接用imagegen生成透明黑色alpha母图，参考用户提供的light/AppIcon.png；提示为提取丝带V，移除方形底板/高光/阴影/颜色，用透明曲线分隔交叠。未交pi处理。AI形状衍生不是逐像素提取或原始矢量。

master.png是母图；MenuBarIcon.png/@2x/@3x分别20/40/60px，20pt逻辑尺寸。isTemplate=true，实际菜单栏明暗和高亮颜色由系统处理。preview-on-white.png仅为白底放大查看，非透明资源。应用彩色icns不变。上一版完整灰白图标保留在MenuBarIcon-Preview-v1。
