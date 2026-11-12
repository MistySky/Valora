# 产品调整：音乐页独立歌词卡片、锁屏歌词开关及底边对齐

用户明确停止继续锁屏CPU优化，改做此产品需求。沿用现有Pi会话/模型/分支，保留所有未提交源码、证据和CPU优化，不提交推送。本轮只做下面功能；不进入内存优化、不继续mask/CA/帧率优化，诊断默认关闭。

## 用户澄清（优先于之前的独立页面理解）

不要新增侧栏“歌词”页面/分组。用户说“音乐里面……一圈一圈的设置……歌词那个和刘海屏一样拿出来就行”，Codex已说明：在现有“音乐”页，把歌词独立成一张与 `musicDisplaySettings` 同级的圆角 SettingsCard。不要改 SettingsCatalog 的侧栏页面。

## 1. 设置UI与偏好

- 现有music第一张卡只保留Now Playing总开关与进度样式，清掉移出行后多余分割线。
- 新增同级 `lyricsSettings` 卡，第一行“歌词”总开关，复用现有 `showLyrics` 持久化key及原用户值，不重置总开关。
- 总开关开启时，下方才显示“内嵌歌词”和“锁屏歌词”两行；关闭时两行/关联分割线完全不显示，不只是disabled。开关关闭不抹掉两项各自保存的选择，再开恢复。
- 内嵌歌词复用现有 `inlineLyrics` key/行为。新增 `lockScreenLyrics` Bool，缺省false，中文“锁屏歌词”；总开关与新开关共同决定锁屏歌词是否显示。可在MusicPreferences提供唯一有效值 `showsLockScreenLyrics = showLyrics && lockScreenLyrics`，避免各模块口径分歧。
- 卡片使用现有SettingsCard/SettingsToggleRow/SettingsRule和已有间距、字体、圆角样式，不做新设计，不额外增加说明段落/CPU数字。
- 不新增侧栏，不把歌词设置放到锁定屏幕页；音乐页卡片顺序为原音乐卡、歌词卡、原刘海屏显示设置卡（若现有布局需固定顺序，保持它们同级即可）。

## 2. 真实功能门控

- LockMusicCard.showsLyricRow 改为有效锁屏歌词开关。有效开启：保留现有native歌词渲染、空行音符居中、暂停保持、逐字/翻转及fallback；有效关闭：整行不挂载，无native歌词时钟/图片准备。
- LyricsController.surfaceNeedsLyrics 的锁屏需求必须同时判断锁屏卡可见和有效锁屏歌词开关。关闭锁屏歌词不能在桌面隐藏时仍为锁屏请求歌词。保留桌面正常取词需求、已加载缓存、取消及过期generation规则；音乐播放/进度/音量不关闭。
- 检查所有 `lockMusicCardVisible` 被当作“需要歌词”的使用点（例如AppModel几何/歌词偏好及注释），只对确实歌词语义的点加有效开关；不要把cardVisible本身改成歌词可见，否则会破坏播放器/4Hz进度。
- 设置变化应及时触发锁屏卡布局和位置刷新；LockMusicCoordinator.bindModel 当前未订阅musicPreferences，需补有界/去重的相关变化，不靠新timer或用户点击。
- master off及lock子开关off关闭歌词行；master on + lock off只影响锁屏，不禁用桌面歌词。保留内嵌歌词原物理刘海/多屏限制。

## 3. 位置（用户本次明确授权调整）

用户要求：有效开启锁屏歌词时保持现在的位置；有效关闭时卡片整体往下移，使它的底边对齐“当前开启锁屏歌词”的底边。

当前 LockCardLayout.lyricBlock = 32 + 8 + 4 = 44pt。同一屏幕、相同verticalOffset和音量展开状态下：有歌词保持原cardTop；无歌词cardTop向下44pt（macOS底左坐标即减44）。因此 `noLyricsBottom(volume) == originalWithLyricsBottom(volume)`，而不是凭感觉另选百分比。

- 将偏移作为LockCardLayout明确的输入/派生值或方法，默认兼容原有布局调用；Coordinator生产路径传有效开关。不要散落魔法数字44，统一使用lyricBlock。
- 内置屏、外接/合盖、非零screenMinY、已有verticalOffset均遵守底边不变；开启时原内置/外接锚点完全不动。音量展开与收起各自底边都与原对应有歌词状态一致。
- 不改21%产品参考线、不猜登录头像边界、不改Space/焦点/锁解动画/卡玻璃/宽度/音量行。固定canvas尺寸维持原值，除非真实测试证明必须调整，不引入新点击遮挡区域。
- 原注释“固定top/向下展开”要说明切换锁屏歌词模式会整体重定位、同一模式内音量仍按原方式展开，文档不能与新产品行为矛盾。

## 4. 验证与交付

定向覆盖：旧偏好保留/新key默认false及持久化；master/inline/lock真值组合；总开关off子项隐藏且保留选择；lock行显示门控与无需词时取消/不请求；锁屏设置变化立即重定位；内置/外接/非零原点/volume开关下开启位置不变、关闭后底边相等；桌面歌词、seek、波形恢复和锁屏生命周期必要回归。单一隔离设置预览检查圆角卡片层级/隐藏行，无批量闪窗/压力/反复锁解；不操作用户真实音乐/音量/锁屏/偏好。

修改AGENTS.md当前功能约定和必要REQUIREMENTS说明本次用户授权的歌词独立卡/锁屏默认关闭/底边规则，保留历史证据，不重写无关文档。

报告 `docs/reports/lyrics-settings-lock-toggle-layout-20261109.md`，写实际修改、测试/日志、候选和未验的真实锁屏位置。必要检查通过后按长期授权打包一次独立Release候选（保留已有实验配置），自动build+1/签名/hash/清单；正常退出旧App→确认零实例→默认不带诊断环境启动唯一新包，保留build48回退，不强退/不覆盖Applications。完成即停，由Codex独立验收后用户确认真实锁屏位置；不要继续CPU优化。
