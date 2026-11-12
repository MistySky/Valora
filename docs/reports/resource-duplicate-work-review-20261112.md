# 资源重复开销代码复核

本次仅阅读源码并记录结论；未追加生产代码变更、测试、构建或替换。保留此前 build66 的空 CATransaction 去重。用户要求由 Codex 直接负责，不派 Pi；不改变动画、交互、外轮廓和流畅度。

## 1. 优先级最高：媒体快照的重复发布及通知放大

证据：

- SystemMediaSource.swift:123 使用 stream --no-diff --micros --debounce=50；每个合格完整事件排队交给 onSnapshot，没有本地快照相等过滤。50ms 是事件合并参数，不能据此声称每秒固定收到20次。
- Controllers.swift:277 applySystem 只对部分命令/封面工作判断变化；314起仍无条件写入 title/artist/album/playing/rate/duration/bundleIdentifier 等 @Published 属性。即使只有进度变化，元数据也再次发布。
- WindowCoordinator.swift:253 合并 playing/title/artist/album，各自排队调用 mediaStateChanged；同时 title 的另一订阅触发 updateVisibility，bundleIdentifier 订阅触发 musicVisibilityChanged → updateVisibility。
- Controllers.swift:333 updateSongPeek 又同步调用 mediaStateChanged。PresentationController.swift:53 有状态相等判断，因此不能称每次都重启动画或闲置倒计时，但重复排队、构造输入与比较仍发生。
- LyricsController.swift:34 同时监听 title/artist/album/duration/bundleIdentifier；每个完整快照可由这5个字段排队5次 update，applySystem 末尾又同步调用一次。update 内有身份检查，不能称重复请求了6次网络歌词；关闭歌词/没有歌曲的清空分支则还会无条件发布空歌词状态。
- PresentationController.trackChanged 在歌词开启时仍调用 songPeek.cancel，增加 generation 并写回 @Published 状态。此路径当前由每次 applySystem 的 updateSongPeek 到达，不能直接以曲目身份去重整个 handler，因为它还涉及多屏目标与可见性语义。

建议首先在生产者对没有变化的显示字段避免赋值。保留每次有效时间锚、seek确认、播放状态和元数据真变化的原时序；不能只比较 track identity 就丢掉整包。是否再合并同轮协调器通知，应另做验证，避免改掉同步清旧歌词的行为。

## 2. 通知下游存在实际窗口操作

- WindowCoordinator.swift:673 updateVisibility 虽有 notchSurfaceOnScreen 值比较，但可见分支仍每次设置 sharingType、ignoresMouseEvents、panel frame、sensor frame，并对两个窗口 orderFrontRegardless。
- updateTrackingSize:494 每次主动调用 EdgeHostingView.updateTrackingAreas；后者:64 无条件移除旧 NSTrackingArea 并创建新对象，即使几何相同。
- anchorPanelTop 有 frame 相等判断，鼠标移动主路径也已有去重；不能称所有窗口路径均未去重。尤其不要回退已修复的点击穿透/退出兜底。
- LockMusicCoordinator.swift:227 合并订阅 playing/title/artist/album/bundleIdentifier，没有 removeDuplicates/同轮合并；每个完整快照可由这5个字段排队5个 refresh。
- refresh:482 在校验会话后，无论锁屏与否都会 place、syncLockIndicator、refreshInformation；place:796 每次查询目标显示器，重写 @Published lockNotchGeometry 并设置两块卡位置。最终 applyVisibility 的相等判断发生得较晚，不能挡住前面的工作。

建议优先拦截源头无变化发布，再根据完整几何/可见性输入去重实际窗口操作。Space迁移、窗口重新挂载、屏幕变化后的强制校正须有独立失效机制，不能简单增加一个永久 frame 缓存。

以上是确定存在的调用/分配路径；真实媒体事件频率、AppKit内部合并程度及CPU贡献尚未计数。不能由源码调用数推算CPU百分比或宣称6%全部来自这条链。

## 3. 歌词内部的重复工作

- NativeLyricsRow.swift:425 update 每帧 refreshLineEnd，同行内通常结果相同；switchLine:449 已做一次，返回 update 后再做一次。可随时间轴版本、当前行及duration失效缓存，必须支持同当前行但后续时间轴改变。
- layoutLine:802 无条件提交多层布局。layout:831每次进入它；viewDidMoveToWindow 中 synchronizeDrawing 若因scale触发 buildTextLayers，后者已 layoutLine，随后仍再 layoutLine。可按完整目标几何及图层代际去重。
- synchronizeClock:991 连续帧每次 register；register:1117 每次重写弱引用字典；fire:1146 每tick filter字典、compactMap数组。属于持续小开销，不预设能带来明显降幅。
- LyricsRowExperiment.swift:856 updateNSView 在 lastAppliedInput 相等检查之前 wire；wire 创建 SwitchBox 与数个闭包。可研究稳定owner/回调输入下复用，但必须保留generation与最新回调，不能盲目把guard前移。

已有去重：文字/颜色/scale未变时 synchronizeDrawing 不重建文字图片；updateNSView 已能跳过相同完整输入的 apply。灰色/高亮两张图内容不同，是现有逐字效果需要，不能当重复图片删掉。换行 keyed identity/转场、30Hz和动画曲线均不属于本次可调整项。

## 4. 无操作时的固定后台成本

- AudioOutputController.swift:75 每0.5秒读取完整 CoreAudio 快照，比较在读取之后；设备名、UID、型号、能力等稳定字段仍反复查询。NativeBridge.m:35 volumeChannels 为验证可用性读过音量，ARAudioOutputSnapshot:56 又读一次各声道音量。可以研究合并单次查询结果、区分静态设备信息与动态音量；设备热插拔/输出切换/音量反馈必须保持。
- ScreenStateMonitor.swift:87 每0.75秒枚举可见窗口及查询Space，非空时 screens() 调用两次。重复取屏幕可直接避免；整体枚举是全屏/Mission Control隐藏的职责，不能因暂停音乐就停掉。
- 媒体总开关关闭已经停止0.25秒tick；暂停进度已有不变不发布；进度锚已从宽泛AppModel拆分。日历日期图也按文本去重，未发现1.0.6日期显示修复新增高频定时器。

## 5. 内存与验证边界

本轮新确认的是通知闭包、tracking area、时钟容器等短期分配，不等于持续泄漏。歌词stop仍保留最后prepared图片、popover/settings复用等有限驻留在前份报告中已有记录；没有持有链/持续增长证据，不为降低冷启动之后的正常平台而强制清缓存。

建议顺序：媒体无变化字段发布 → 桌面/锁屏协调器重复窗口工作 → 歌词布局/注册 → 音频与屏幕轮询。每批先用有限计数确认触发频率，再比较同歌曲同片段、同设置的累计CPU时间差与physical footprint；探针采样另开窗口。验证真实改变仍及时到达、点击穿透、锁屏恢复、歌词逐字/换句/seek与外轮廓完全保持，不以单测或参数相同代替用户流畅度确认。

此审查没有证明某一项是当前6%的主要来源，也没有证明相对旧版退化。它给出了比空事务更值得优先验证的、源码可定位的重复开销。
