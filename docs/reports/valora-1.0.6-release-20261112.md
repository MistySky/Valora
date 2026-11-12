# Valora 1.0.6 发布构建

1.0.6/build65，arm64，macOS27+。仅交付V0113状态栏独立命名与实际可见性恢复修复，保留1.0.5点击穿透修复。根因、隔离复现与独立16项定向验收见v0113相关报告。本批未改动画、歌词或日期样式；本地由用户Brew管理，未启动/退出/替换其安装或实例。

正式Release显式VALORA_LYRICS_EXPERIMENT=1；签名Valora Self-Signed，与已发布版本designated requirement相同；codesign严格深度验证与hdiutil verify通过；package entry checks通过。未新增真实安装重启验收，不将隔离测试冒称实际系统菜单栏排列验证。

用户授权在codex/lock-screen-idle-cpu提交、推送、打v1.0.6标签并上传GitHub Release；不合入main。标签应指向包含本报告的发布提交。

输出：/private/tmp/valora-1.0.6-release-20261112

- binary SHA256：8d42f49540c2115f4decb98821bd0f35a54ad996fb1341d8ff51b2bfd9ca653c
- DMG SHA256：97d085b1ad70d2e53eee672c40181776376e491dfa8a1882a71012321e6e7d65
- build-verification.json SHA256：b0ac653ea723c2cc8e09a0a2c3ff66f44b3bedd04b9d94aa7fa12b078f9def1b

构建日志：/private/tmp/valora-1.0.6-build.log

DMG日志：/private/tmp/valora-1.0.6-dmg.log
