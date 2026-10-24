# 独立验收：图标通过，整体候选限定返修

正式交付后核验源映射121项的242个源/目标指纹，只有scripts/package.py与V0001旧目标指纹不同，符合V0002图标接入改动；其余匹配。38个用户图标文件与源/仓库指纹匹配，10个包文件与最终清单匹配。独立离线构建到/tmp/valora-independent-built成功，binary及图标与交付包SHA256相同；Swift6/macOS27基线、签名、静态默认浅色图标配置正确，深色资源保留，未冒称自动外观切换。

独立98项XCTest通过（Valora22、Core76）；独立实际SwiftUI合成音乐验证91/91通过。已查看迁移设置页和独立expanded-music图，与旧代码布局链路一致的方向正确；不扩大为原版逐像素/所有实机体感通过。独立NSWorkspace图标渲染已查看，正确使用确认图稿。

独立只读系统媒体验证：快照/封面可读，停止后不再回调，显式重新start获取新快照，未执行播放/seek/音量/权限操作。

整体候选暂不通过，具体两处：
1. MediaController.system.onError只clearMedia，未清systemStarted；SystemMediaSource已退出且process=nil时，后续refresh因systemStarted=true永不重连，暂时流失败会永久无音乐直至切开关或重启。当前只读验证测的是显式source.stop/start，不覆盖Controller故障恢复。
2. Controllers.seek直接Int64(target*1_000_000)。Snapshot只要求Double有限且非负，有限但超大duration可通过；缩放可能溢出或超Int64范围并trap。需要有界安全转换，非法数据不发送命令，不改变正常seek语义。

限定修复原媒体生命周期与数值边界，不重写UI、不加功能、不动已确认图标。旧NativeBridge只保留现有4个系统适配函数，作为旧底层代码存在已如实记录；自有UI/业务保持Swift6，不以迁移名义增加其他语言模块。
