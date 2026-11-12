# build49 独立验收

## 实现核对

音乐页使用同级lyricsSettings卡片，不新增侧栏；原音乐卡仅保留Now Playing和进度样式。showLyrics为原key总开关，关闭时不挂载inline/lock行及其分割线，子偏好保留。lockScreenLyrics新key默认false，showsLockScreenLyrics统一为master&&lock；锁屏整行和歌词需求按此值门控。LockMusicCoordinator收到musicPreferences变化后refresh/place，不靠新timer。

LockCardLayout有歌词时原top不变，无歌词时减去lyricBlock44pt（macOS底左坐标），固定canvas和旧内外屏参考线保留。相同volume状态底边保持相等。预览也接入有效开关。歌词渲染、翻转、共享时钟、之前CPU优化未因本轮调整而撤回；本轮不继续性能优化。

## 独立测试

`VALORA_LYRICS_EXPERIMENT=1 swift test --filter 'MusicPreferencesTests|LockCardLayoutTests|LockMusicCoordinatorTests|LockLyricsTrackChangeTests|MusicDisplayPolicyTests|IndependentWaveformReturnTests|SeekProgressTests'`：Valora62项、ReferenceCore19项，共81项通过，0失败。日志 `/private/tmp/valora-build49-independent-20261109.log`。覆盖默认/真值组合、布局底边、设置变化重定位、锁屏关闭不取词、波形恢复及seek。Settings布局含源码级断言，不等价于已做真实视觉验收；本轮未开独立设置预览/真实锁屏。

## 候选与替换

核对实际唯一进程88575，路径 `/private/tmp/valora-lyrics-lock-toggle-20261109/Valora.app`，Info.plist构建49。strict/deep签名通过，SHA256 `b71fc51b92eed3567ed9ba8227366b10d10fd7af129679ed2c5436add22dfbc3` 与Pi交付报告一致。Pi已按报告正常退出build48并替换，本轮确认后没有为中间测试再次重启/构建候选。build48保留回退。

## 判断

代码和定向回归接受，可交用户查看。音乐页圆角卡层级、开关操作及真实锁屏的有/无歌词位置仍由用户确认，尤其内外屏/音量展开真实效果不冒称已验。此次不需要再次CPU采样；等待用户位置与设置反馈。
