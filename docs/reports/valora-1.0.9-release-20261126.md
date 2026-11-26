# Valora 1.0.9 发布验收

发布分支为 `codex/performance-preserve-motion`，从 v1.0.8 的 `166a245` 延续。DMG 直接封装已验收的 1.0.9 build 81，使用原签名，架构为 arm64，最低系统为 macOS 27。

锁屏新增独立显示器选择和带预览的液态玻璃滑块。「全部显示器」在每块活动屏幕显示锁屏刘海与播放卡。本版修复系统监控采样的端口泄漏、去除歌词时钟的重复登记，并减少波形同一拍内的图层事务及歌词的重复布局。

build 81 通过 58 项定向回归。逐帧回放中，644 个歌词模型层快照和 132 组波形动画状态与 build 80 一致。双屏亮起时两版各采样一分钟，主进程 CPU 分别约 4.44% 和 4.56%，这组结果未显示整体 CPU 下降。离屏回放没有测量实际屏幕帧率。[采样摘要](../verification/playback-layers-20261126/summary.json)

打包入口与构建号分配测试通过。DMG 通过 `hdiutil verify`。只读挂载后核对了版本号、主程序及内嵌框架的 SHA-256、严格深度签名和 Applications 安装链接。签名为 `Valora Self-Signed`，未经 Apple 公证。公开校验清单用仓库相对路径记录构建输入。

| 对象 | SHA-256 |
|---|---|
| Valora-1.0.9-arm64.dmg | `1b25ff14467b3424fc88bf81d1378ab28c8954802ad159303c67af2887d3d17c` |
| Valora 主程序 | `71bdf31f3fb111b31843477ca6617cc863de17059d40d9d77aed6bc968835f90` |
| build-verification.json | `4dcf542554559a1750364520f8c8c005f3da333387bf8477b5d71213beeeff25` |

安装镜像与两个校验附件见 [Valora 1.0.9 发布页](https://github.com/MistySky/Valora/releases/tag/v1.0.9)。
