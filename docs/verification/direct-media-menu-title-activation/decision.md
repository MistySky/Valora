# 用户指定菜单顺序与双击标题打开来源

用户明确要求菜单栏上一首/下一首互换，并指出原版双击歌曲名称会打开当前播放软件。本次Codex已提前说明直接处理两项小修复，未打断pi的V0017 HTML原型；只修改AppDelegate菜单/来源激活接线、AppModel小入口、MusicPlayerContent标题交互，以及新增针对性测试。

- 状态菜单原顺序播放/暂停→下一首→上一首，改为播放/暂停→上一首→下一首；对应图标与selector随项一起保留，不改播放命令或刘海右击菜单。
- 展开面板歌名/歌手区域增加双击与可访问性“打开当前播放软件”入口，保留字体/布局/滚动；按当前model.mediaBundleIdentifier查找仍运行的应用并unhide/activate。不开URL、不猜播放器、不启动已退出的应用、不发媒体命令。
- 无歌曲/无来源/音乐关闭/合成预览不激活；点击时读取最新来源，避免旧闭包目标。
- 归档音乐视图未发现此双击接线，原版行为依据用户说明补齐；不假称已独立验证原版gesture实现。

MusicSourceActivationTests两项通过，覆盖最新来源与无效状态、且model.media为空仍可调用证明未经过播放命令。独立候选构建/签名与dist重新打包签名通过，原日志/private/tmp/valora-media-shortcuts-{test,build,package}.log。

已通过CUA退出旧Valora并启动新dist，不操作音乐播放器；展开面板实际AX标题显示Help“ 双击打开当前播放软件 ”并暴露SecondaryAction“打开当前播放软件”。未自动实际激活个人音乐软件，未切歌/播放/seek/音量。尝试读取状态项UI时AX提示offscreen，实际菜单排序本轮依据源码构建核对，未冒称菜单点击已实测。用户可自行双击检查前台效果。

本次未改设置原型，未修改系统权限/登录项、未安装发布或Git提交推送。封面翻转另有缺陷记录尚未修复，本变更不冒称涵盖它。

最终dist binary SHA256：44f67b7d5827f8400d40bce14b615ee3fa8dcf0fe18cf1465850ab309c234f4d
