# Valora 1.0.8 发布验收

用户明确授权提交日历开关修复、构建上传1.0.8，不合并main，本地由用户Brew更新。发布分支codex/resource-idle-render-dedup，基线5cb224c；main保持6c98d2be683e035fdaab9f29dcbd795236748655。v1.0.8标签应指向包含本报告的提交。

本版生产改动仅AppPermissions初始化calendar时读取已解析的provider.status，修复默认provider被忽略而暴露unknown、导致设置页写回关闭偏好的路径。详见calendar-startup-preference-20261113.md。旧版已清成false的偏好无法与主动关闭区分，需要用户更新后再打开一次；系统授权有效且偏好保留时，后续启动保留选择。

21项定向权限/偏好测试通过，修改前新增初始化回归明确失败。package entry、build-number隔离检查和git diff --check通过。正式Release显式VALORA_LYRICS_EXPERIMENT=1；固定Valora Self-Signed签名，与1.0.7 designated requirement一致；严格深度签名校验、hdiutil verify通过。未Apple公证。

未追加真实重装/重启验收，未操作真实播放、偏好或权限；未退出、启动、替换本地运行实例或覆盖Applications。没有歌词/动画代码变更，逐字高亮落后和偶发左右重复仍未定位，本版不宣称解决。

产物：/private/tmp/valora-1.0.8-release-20261113

- 版本：1.0.8 / build71，arm64，macOS27+。
- binary SHA256：91bc1c1c5368df706d95d3a0700fc0f3271ac4ea345a47f8a5bd0582ef828d43。
- DMG SHA256：1d97046a854d1837dc33bf4ae13e11b9511e1ae3565b30de4216484d85f9587b。
- build-verification.json SHA256：1435a6a69a374947ee5981a6904b45d863af891aca2156f8e4b47ba5aa5ebd39。
- 附件：Valora-1.0.8-arm64.dmg、build-verification.json、SHA256SUMS.txt。
- 构建日志：/private/tmp/valora-1.0.8-release-build.log。
- DMG日志：/private/tmp/valora-1.0.8-release-dmg.log。

发布目标：https://github.com/MistySky/Valora/releases/tag/v1.0.8
