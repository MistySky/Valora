# 歌词固定外轮廓：独立验收与运行候选

结论：本批限定修复技术验收通过，build60 已启动供用户体验。真实切歌闪动是否消除及原有体感是否保持，待用户实际确认，不以离屏测试代替。

## 改动边界

对照先前main差异清单 `main-interaction-source-manifest-20261112.json` 的27个生产输入哈希，本批仅 `Sources/Valora/Models.swift` 变化。外层compact歌词32pt空间、inline16pt增量改为由稳定显示模式控制，不再依赖歌词加载/可用性。内容仍按原来的可用性门控，加载期不显示旧歌词，也不因预留空间启动额外内容时钟。

逐项比较本批前快照：NotchView、TransitioningArtwork、LyricsRowExperiment、NativeLyricsRow均字节一致。锁屏与expanded歌词几何保持旧分支；hover、展开收起与原逐句/封面动画未修改。用户明确认可的差异是歌词开启但加载中/无歌词时仍保留空间。AGENTS已记入这项新约定。

## 独立验证

- `VALORA_LYRICS_EXPERIMENT=1 swift test` 定向20项通过，日志 `/private/tmp/valora-fixed-contour-independent-20261112.log`：IndependentLyricsContourTests、NotchFixedContourTests、MusicDisplayPolicyTests、IndependentInteractionTests、NotchSurfaceVisibilityTests、PlayingWaveformLifecycleTests。
- 新增独立回归以物理/非物理刘海×内嵌开关四组场景推进同一时间轴短短、短长、长短、空行，再注入新曲loading/unavailable/ready。完整NotchShape路径、外框尺寸和hover scale一致；加载时不显示旧歌词；停用音乐不保留歌词slot。
- 实际离屏NSHostingView黑色边界：短句/长句/空行/loading均为 `(398,0,452,110)` 像素；该fixture模型size为214×55pt。它验证边界一致，不证明所有中间帧的整体透明度、WindowServer排序或真实桌面流畅度。
- Pi另完成82项相邻定向测试及2项LockCardLayout测试，详见开发报告；未冒称全量测试通过。

## 构建与唯一实例

- 显式固定 `VALORA_LYRICS_EXPERIMENT=1`，`scripts/build.sh --output-dir /private/tmp/valora-fixed-contour-candidate-20261112` 一次正式打包。
- 1.0.3 / build60，固定Valora Self-Signed签名，`codesign --verify --strict --deep`通过；Info.plist及build-verification.json核对一致。
- binary SHA256：`8b8ce7397673f8bdde79a0269ac0257ac0ec2f53f2962793bb40500789db637b`。
- 启动前pgrep确认0个Valora，无需退出旧进程；启动后确认唯一PID41471，路径 `/private/tmp/valora-fixed-contour-candidate-20261112/Valora.app/Contents/MacOS/Valora`，运行记录 `/private/tmp/valora-fixed-contour-running-20261112.json`。
- 未覆盖Applications、未操作真实播放/音量/锁屏或用户设置、未Git提交推送。构建日志 `/private/tmp/valora-fixed-contour-build-20261112.log`。

用户体验时重点确认整首切歌外圈是否仍闪、逐句歌词衔接是否保持。若仍闪，应继续采集外层呈现帧及窗口生命周期证据，不直接改动画参数。内存优化未继续。
