# V0009-R2 独立验收（2026-10-24）

结论：本次限定返修通过代码、离线回归、独立构建签名及合成呈现验收。真实双屏跨屏操作体感仍待实际设备，不宣称整个产品全部实机验收。

- 独立swift test：97项通过（Valora35/Core62），包含两次独立失败回归，均未删弱断言；暂停期间切显示、暂停悬停再切显示/直接reset、禁用再启用、同值轮询不延期通过。
- 独立构建到/private/tmp/valora-independent-v0009-r2/Valora.app；独立候选及dist候选codesign --verify --deep --strict均通过。
- 实际检查PresentationController.resetForScreenChange：已有pending保留剩余期限，旧指针归属清除后如stored input仍pointerInside=true则重新求值媒体输入并安排正常3秒期限，修复范围符合任务。
- 与V0009保存源码指纹比较：协调器、NotchView、进度/音量、控制器、菜单文案、AppDelegate、验证接线均未变化；变更为PresentationController及相关测试。打包图标仍Outline-v7，不回退原版品牌。
- 独立--verify-music：74项通过；独立--verify-multidisplay：12项通过。使用隔离QA偏好和fake数据，未控制真实媒体。已查看expanded-music-review.png与quick-peek-review.png，现有呈现保留；不以合成截图宣称原版逐像素一致或物理双屏通过。
- 未安装/发布/提交Git/修改系统权限登录项或播放状态。

允许按已授权顺序进入V0010：先Swift6 QQ歌词获取与匹配验证，不立即改UI或迁入设备功能。真实双屏待验项随交付保留。
