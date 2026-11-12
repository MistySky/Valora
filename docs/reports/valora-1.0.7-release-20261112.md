# Valora 1.0.7 发布验收

用户明确授权提交、构建、上传1.0.7，禁止合入main。分支codex/resource-idle-render-dedup，基线1.0.6/f6666aa；main保持6c98d2be683e035fdaab9f29dcbd795236748655。标签v1.0.7应指向包含本报告的发布提交。本机继续由用户Brew管理，本次没有退出、启动或替换运行实例，没有覆盖Applications。

## 发布内容

- 鼠标进入/退出仍由现有区域感应处理；遗漏退出事件仅在悬浮期间通过120Hz位置检查兜底，移除全局/本地鼠标移动监听，离开、隐藏、锁屏后停止检查。保留点击穿透与拖动保护。
- 媒体快照只发布变化字段，窗口frame、锁屏几何、tracking area跳过相同值更新；比较真实当前状态，保留外部变化纠正。
- 原生歌词只跳过没有图层写入的空CATransaction；歌词计时、渲染器、动画参数、帧率和刘海外轮廓不变。
- 音频快照复用本轮能力验证已读的声道音量，不跨轮缓存、不改变轮询周期和音量写入路径。
- 保留1.0.5点击穿透与1.0.6日历菜单栏修复；不进行缓存清空或其他内存优化。

## 验证与边界

本轮实施阶段的定向回归：歌词52项（51通过、1项显式像素探针未启用而跳过）；媒体/窗口90项通过；鼠标58项通过；音频12个原生fake场景及44项Swift相邻回归通过。不同批次有重叠，不累加为独立覆盖数。日志与复现命令见同目录resource-render-dedup-step1、resource-media-window-dedup、hover-exit-watchdog、audio-snapshot-read-dedup的20261112报告。

实测音乐关闭、远处晃鼠标build68约1.29%；用户确认进出刘海后设置与其他软件点击正常。5.37%那段由用户确认正在播放，不能当作关闭音乐后的残余鼠标异常。build69暂停平均1.26%，build68暂停1.24%，未证明音频读取去重带来可测CPU降低。26.4M是新进程暂停footprint，不与已使用进程47.3M比较为内存收益。不同状态不能混算。

本次仅将已验收代码标为1.0.7/build70，没有追加生产修改；package entry与build-number隔离检查、git diff --check通过。Release显式VALORA_LYRICS_EXPERIMENT=1；arm64/macOS27+；固定Valora Self-Signed，未Apple公证。codesign严格深度验证、DMG生成及hdiutil verify通过。

签名后的binary摘要因版本/构建元数据签名改变而不同。对两个二进制的临时副本移除签名后，build69与本次build70均为4ed44e3258d161572d869472bd7ccae719166922b3242c897eca67a64922f1f2，确认可执行代码一致；原包未修改。构建号只通过原分配器分配一次。

本次不启动正式包，不重新进行窗口/媒体操作。真实耳机热插拔、音量手势、锁屏/物理多屏和长期使用未在最终包新增验收；fake/有限回归不等于这些场景通过。不声称动画体感已在所有场景全面复验。

## 产物

路径：/private/tmp/valora-1.0.7-release-20261112

- 版本：1.0.7 / build70
- binary SHA256：930e45b65624d028b3f045ab8104d646352dbfd9bbd6454bcb8a54d36cba80ff
- DMG SHA256：598d5f69c0340da6699c26a4a3667b0ada410ce542a35b04332a3cc98241159e
- build-verification.json SHA256：35e546e44efe5627d0628e40601d25c84307a45ab73c62851860e9d7a7d2ed84
- 附件：Valora-1.0.7-arm64.dmg、build-verification.json、SHA256SUMS.txt。
- 构建日志：/private/tmp/valora-1.0.7-release-build.log。
- DMG日志：/private/tmp/valora-1.0.7-release-dmg.log。

发布目标：https://github.com/MistySky/Valora/releases/tag/v1.0.7
