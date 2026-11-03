# 用户反馈切歌封面翻转不明显/未呈现：源码复核

当前用户观察原版切歌封面翻转，Valora未看到相应效果。本次只读代码核查，不真实切歌，不修改生产代码，不打断正在进行的V0017 HTML原型。

## 已确定

- TransitioningArtwork.swift实际从归档成熟文件迁入，差异仅ArtworkTransitionController加@MainActor；不是完全没有动画代码。
- 紧凑和展开都使用TransitioningArtwork；设置固定disableAlbumArtFlip=false，系统ReduceMotion时跳过，紧凑被动屏allowsDynamic=false按已确认多屏规则不翻转。
- 具体过渡是水平压缩到0.0825→替换→弹性展开，配亮度模糊，不是任意新增3D旋转。原版参数在ArtworkFlipMetrics，不能凭名字自行换动画。
- 可静态复现的跳过路径：Controllers.applySystem在歌曲identity变化且snapshot.artwork=nil时model.artwork=nil；ArtworkPalette返回空identity；TransitioningArtwork同步nil导致ArtworkTransitionState.set清current为nil/idle。后续封面到达时因current=nil被视为首次封面直接idle显示，跳过old→new翻转。真实播放器这次是否正好经过该路径仍需带时间戳的隔离记录/用户安排实测，不能仅静态推断宣称唯一根因。
- 同专辑同封面identity相同不动画为当前按封面内容身份策略，不能与漏动画混淆。

## 原版/复刻证据界限

归档docs/刘海音乐实施与验收.txt 0.5.5段：原参数来自1002db0d0/1002dafd8/1002db078/1002de228等，但mirrored朝向/锚点/plusLighter/CALayer插值/hasTranslucency分支未全还原；明确写“实际切歌确认最终封面正确，未录制逐帧翻转，不能标记1:1”。既有测试最终image正确和状态机idle不证明实际逐帧体感正确。

后续专项需用隔离媒体快照和真实SwiftUI视图覆盖：有封面A→新曲暂缺→B晚到、直接A→B、同封面、快速切歌最新目标、清空/停止、紧凑与展开、减少动态/活动屏，帧级观察scale/blur/brightness以及图片替换时点。保留原过渡节奏，修触发/生命周期，不瞎换3D动画或全局动画参数。禁止为测试自动真实播放/切歌或写用户减少动态效果设置。

当前只是缺陷记录，V0017仍只HTML不改Swift；现有邮箱有同轮视觉补充pending，不覆盖或重复派工。
