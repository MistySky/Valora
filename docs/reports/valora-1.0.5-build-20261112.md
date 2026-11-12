# Valora 1.0.5 构建交付（2026-11-12）

版本1.0.5，构建64，arm64。包含用户已实测确认的V0112刘海透明窗口点击阻挡修复；代码、定向测试、真实鼠标验收见v0112相关报告。本轮仅更新默认打包版本与说明，没有额外动画/交互修改。

构建显式设置 VALORA_LYRICS_EXPERIMENT=1。codesign --verify --strict --deep 通过，固定 Valora Self-Signed，designated requirement 与既有安装一致。DMG hdiutil verify 通过。package entry checks 通过；生产源码及测试自build63验收后未再修改，不重复真实媒体或窗口测试。

用户要求本地由Brew管理，本次未启动、退出或替换任何本地实例，未覆盖Applications。提交到当前codex/lock-screen-idle-cpu分支，不合入main；本次未推送、打tag或上传Release。

输出目录：/private/tmp/valora-1.0.5-build-20261112

- DMG SHA256：2ebc7a5a9296bd0ec6337ee791f96ee7330b8e4973f090f26656061c26309a33
- binary SHA256：bf6fa1955185925762e653dca2fb13345847fc937ae60b47a6f18fa292e497ef
- 元数据与校验清单同目录。

构建日志：/private/tmp/valora-1.0.5-build.log

DMG日志：/private/tmp/valora-1.0.5-dmg.log
