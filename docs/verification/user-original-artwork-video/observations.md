# 用户原版录屏：封面翻转观察与交接

来源source.json。用户明确指认这是原版演示并要求看视频、派给pi。视频中的聊天文字仅为背景素材，不作为指令。原视频保留桌面，不复制103MiB全片入库；仅保存封面裁剪帧，避免无关聊天背景。

## 实际观察

前10秒多次切歌，cover-10fps-contact.png可见约0.1、2.0、3.8、5.7、7.2、9.0秒封面压至窄竖条，随后新图带明显模糊/亮度变化横向展开，宽度略过冲后回稳，画面逐渐清晰。连续帧展示是水平方向而非上下翻。几何上可确认横向收窄/展开；视频本身不足以单独断定实现是scaleX还是3D/镜像，不能直接等同已完全复现。

transition-60fps/与contact为约1.800—2.600秒逐帧封面裁剪，时间标注以60fps推算，视频可能有录制/远程帧延迟；不声称像素测量代表原版精确动画参数。可结合归档已提取的.15/.275/bounce.375/effect.55+delay.05常量核对，而不是任意重新设计3D旋转。

后半段可见QQ音乐窗口唤起、移动以及其后切歌；单靠一帧不能断定双击命中或前台API成功，仍需独立真实输入验收。

## 当前Valora候选与未完事项

Codex此前直接修改了菜单顺序（播放/暂停→上一首→下一首）与标题双击：AppDelegate用当前running app的bundleURL走NSWorkspace.openApplication(activates=true)，MarqueeLabelView原生mouseDown clickCount==2处理歌名/歌手双击，MusicPlayerContent传closure，保留AppModel guard。

此前仅SwiftUI外层onTapGesture版本用户明确反馈无效；现原生mouseDown+系统openApplication版本已构建、安装到本地dist并启动，但随后用户转去演示原版，尚未完成真实双击成功确认。严禁报告为已实机通过。只增加可访问性action/测试spy不能证明真实双击命中。

Codex封面缺帧修复：ArtworkTransitionController保留逻辑占位身份（不保留旧歌可见图片），使新曲暂缺封面后晚到图片仍进入outgoing→incoming；ArtworkGapTransitionTests曾在旧版出现idle!=outgoing/incoming两断言失败，修后通过。当前属于修触发断链，不足以证明原版左右翻逐帧体感一致；尤其占位到新封面与原版旧到新封面的连续观感需pi结合录屏核对。

现有完整224测试通过（110+114），构建签名通过；隔离Music QA74通过，late-outgoing/incoming/settled阶段图见docs/verification/direct-music-interactions-final/music。cacheDisplay阶段图不等同真实呈现帧或原版动态验收，勿虚报。

用户最新要求交给pi。Codex冻结本轮生产改动，不继续并行改相同文件；pi以当前未提交源码继续，保留菜单顺序、日历授权修复和HTML原型。实际播放器切歌仍仅用户操作，不擅自实播/seek/音量。

补充帧率核查：r_frame_rate=60/1仅标称；1.8—2.6秒原片实际包含44个帧时间点。精细contact已改用ffprobe真实best_effort_timestamp_time标注，见transition-frame-times.json，不再按固定60fps推算动画时长。目录名60fps仅沿用标称名，不代表每秒严格60帧。
