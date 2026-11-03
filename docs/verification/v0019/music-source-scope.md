# V0019 音乐来源范围核查（只记录，不实现）

## 代码事实

- `Sources/Valora/SystemMediaSource.swift` 的起点是系统 Now Playing 适配器：
  `stream --no-diff --micros --debounce=50`，读取 macOS 当前媒体会话。
- `Sources/Valora/Controllers.swift` 的 `MediaController.refresh()` 只检查
  `isActive`、`previewMode` 和 `settings.nowPlayingEnabled`；没有浏览器/视频
  bundle 黑名单，也没有 QQ / 网易云 / Apple Music / Spotify 的独立来源选择或优先级。
- `MediaController.applySystem()` 把当前 snapshot 写入同一组 `model` 字段；
  `mediaBundleIdentifier` 用于来源激活、命令前的来源/曲目一致性校验，不是音乐来源过滤。
- 设置页已没有来源选择卡片；当前候选仍只消费系统当前媒体。

## 结论

- 如果当前 macOS Now Playing 是浏览器/网页/视频，本候选仍可能把它当作活动显示；
  它尚未实现“只支持音乐软件、网页/视频不抢占音乐”的独立来源优先。
- 本批没有新增多播放器轮询、平台登录、多歌词源或来源过滤；以上是明确的未实现差距，
  不用设置文案、隐藏浏览器或测试夹具冒充已实现。
- 现有命令一致性保护仍有效：`SystemMediaSource.perform` 在发送控制前比较当前
  bundle/track；但这只防止向已切换的播放器发送旧命令，不等于音乐来源筛选。
