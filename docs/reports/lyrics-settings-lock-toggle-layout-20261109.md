# 音乐页歌词卡、锁屏歌词开关与底边对齐（2026-11-09）

分支：`codex/lock-screen-idle-cpu`。保留全部未提交 CPU/诊断成果；未提交或推送 Git，未合并 main。

## 一、设置 UI 与偏好

`Sources/Valora/SettingsView.swift`：

- 原音乐卡只保留 Now Playing 总开关与进度样式，删除多余尾部分割线。
- 新增同级 `lyricsSettings` SettingsCard，不新增侧栏页面：
  - 第一行 “Lyrics”（复用 `showLyrics`）；
  - 总开关开启后才出现 “Inline lyrics” 和 “Lock screen lyrics”；
  - 关闭时两行及关联 `SettingsRule` 完全不挂载；
  - 两个子项仍写入原 `inlineLyrics` / 新 `lockScreenLyrics`，关闭总开关不抹掉值。
- 卡片顺序：原音乐卡 → 歌词卡 → 原刘海屏显示设置卡；沿用 SettingsCard/SettingsToggleRow/SettingsRule 现有材质和间距。

`Sources/ReferenceCore/MusicPreferences.swift`：

- 新增 `lockScreenLyrics`，缺省 false；
- 唯一有效值 `showsLockScreenLyrics = showLyrics && lockScreenLyrics`；
- 旧 `showLyrics` / `inlineLyrics` key 原样复用。

## 二、功能门控与位置

- `LockMusicCard.showsLyricRow` 改为 `showsLockScreenLyrics`；有效关闭时整行不挂载，native 歌词时钟/图片准备不会建立。
- `LyricsController.surfaceNeedsLyrics` 的锁屏分支改为：
  `lockMusicCardVisible && showsLockScreenLyrics`；桌面 notch 需求、已加载缓存、取消/超时/旧 generation 规则不变。
- `LockMusicCoordinator.bindModel` 增加 `settings.$musicPreferences` 去重订阅，设置变化立即 `refresh/place`。
- `LockCardLayout` 新增 `showsLockLyrics`（默认 true，兼容旧调用）：
  - 有歌词：原 cardTop 不变；
  - 无歌词：cardTop 下移恰好 `lyricBlock`（44pt）；
  - 同一音量状态下，无歌词底边 == 有歌词底边；
  - 内置屏、外接/合盖、非零 screenMinY、verticalOffset 都遵守；
  - 体积展开仍从固定顶向下，21% 产品参考线/窗口尺寸/Space/焦点/玻璃/宽度/音量行未改。
- `LockCardPreview` 的预览布局也传有效锁屏歌词，避免预览与实际位置分叉。

## 三、文档

`AGENTS.md` 当前音乐/锁屏约定、`REQUIREMENTS.md` 音乐/锁屏范围已同步本次用户授权，不改无关历史。

## 四、验证

- `MusicPreferencesTests`：默认 lockScreenLyrics false、master/组合真值、旧 key 兼容。
- `LockCardLayoutTests`：新增无歌词下移 44pt、底边对齐（内置/外接、非零原点、offset、volume 两态）。
- `LockMusicCoordinatorTests`：新增设置切换立即重定位并保持底边；既有锁屏生命周期/放置回归。
- `LockLyricsTrackChangeTests`：新增锁屏歌词关闭不请求；既有桌面/锁屏切换、seek、超时、已加载缓存回归。
- `MusicDisplayPolicyTests`：新增歌词卡为同级卡、子项条件挂载、原音乐卡不再含歌词行的源码级检查。
- 本次定向执行 93 个 Valora 测试 + 19 个 ReferenceCore 测试，0 失败；另有既有 1 项条件跳过。
- 未启动独立设置预览窗口，未做真实锁屏位置/真实媒体/锁屏操作；设置预览的圆角卡片视觉和真实锁屏底边仍需用户/Codex 实机确认。

## 五、候选

- `/private/tmp/valora-lyrics-lock-toggle-20261109/Valora.app`
- `1.0.3 (49)`
- binary SHA-256：`b71fc51b92eed3567ed9ba8227366b10d10fd7af129679ed2c5436add22dfbc3`
- strict/deep 签名通过
- build48 已正常退出，当前唯一 build49 实例 PID `88575`
- build48 保留：`/private/tmp/valora-lyrics-apply-dedupe-20261109/Valora.app`

## 六、待验

- 真实锁屏下有/无锁屏歌词的卡片底边是否与设计一致；不同屏幕/合盖/音量展开位置需用户实测。
- 设置页歌词卡的圆角层级、隐藏行、总开关关闭再开的值恢复需一次隔离设置预览/实际设置窗口确认。
- 新 `lockScreenLyrics` 默认 false；旧用户 `showLyrics=true` 时锁屏歌词仍需用户开启。
