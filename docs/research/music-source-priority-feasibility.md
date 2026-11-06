# 音乐来源优先与控制同源：只读可行性研究

日期：2026-10-25  
任务：`docs/pi-tasks/v0021-music-source-priority-feasibility.md`  
任务 SHA256：`6ca3ff3bbe549b7b6f33042c63dc5f4d83c6fbc1c215e6624e6a3374029a542d`

## 结论摘要

1. **当前 Valora 不能实现“音乐继续显示、网页/视频不抢占”**。`SystemMediaSource` 只读取 macOS 当前 Now Playing 会话；`MediaController` 只有一个 system 来源；`send`/`seek` 也没有目标应用参数。浏览器成为当前媒体时，Valora 会收到浏览器快照，而不是后台音乐。
2. **只过滤浏览器不可行**：过滤只会隐藏/冻结当前系统流；它不会读取后台音乐。缓存旧歌并自行推进进度也不是真实来源，不能作为完成。
3. **不新增 Automation/Accessibility 权限的子集，最多保持现有 system 当前会话；无法满足来源优先与控制同源。** 这不是一个可以通过文案或隐藏浏览器修好的 UI 问题。
4. **可选的独立来源路径需要用户明确授权一种新依赖**：
   - Apple Music / Spotify：Apple Events/AppleScript（Automation 权限）；
   - QQ 音乐：Accessibility（辅助功能权限）读取/点击播放控制栏；
   - 私有 MediaRemote per-client：静态还原存在，但无官方接口、无当前版本运行证据，风险最高。
5. **推荐的最小实现批次**是“用户明确选择来源 + 复用现有模型/UI 的 SourceCoordinator + 先做一个 Apple Music 适配器”的验证批次；QQ/Spotify 随后按本机安装和权限决定，NetEase 目前没有可引用证据。不要先做自动应用排名、多个音乐同时播放策略或私有 MediaRemote 全链路。

## 方法与边界

本任务只读：

- 当前 Valora 源码、`vendor/mediaremote-adapter` 源码/README/LICENSE、当前 `SystemMediaSnapshot`/`MediaController`；
- 归档成熟复刻源码、其 reverse-engineering 静态记录；
- 已安装 QQMusic 11.10.5 与系统 Music 1.7 的 Info.plist / Music.sdef；
- 公开 GitHub 仓库、公开官方文档；
- 静态文件 SHA256。

没有执行：真实播放器/浏览器查询、MediaRemote `get/stream`、AppleScript/Apple Events、ScriptingBridge、AXUIElement、权限提示、模拟音频、媒体命令、播放/切歌/seek/音量、账号/凭据/限额读取。没有构建、测试、安装、发布或 Git 写操作。

静态证据：`docs/verification/v0021/static-evidence.json`。  
“源码已证实”只表示静态代码/字典存在；“待实测”表示没有运行验证，不能当作功能通过。

## 当前实现的实际能力

### SystemMediaSource / MediaController

当前源码（工作树，未提交）：

- `Sources/Valora/SystemMediaSource.swift` SHA256 `5fba87232324961ffb2e1a700e9309e09194181147e517c9d0d56be850967a62`
- `Sources/Valora/Controllers.swift` SHA256 `ecc8c755a4003e4659e8134903738c8531a869d61b53b4296d893e0d9bdd3b41`
- `Sources/ReferenceCore/SystemMediaSnapshot.swift` SHA256 `28c36f40a77fa3c3bfb7c4a0f1ecfb5cf94076d458f64b9b634780dfedb11f4c`

事实：

- `SystemMediaSource.start()` 固定运行
  `stream --no-diff --micros --debounce=50`，输出当前系统 Now Playing 快照。
- `perform()` 在发送前用一次 `get --micros --no-artwork` 校验 bundle/track，然后运行
  `send` 或 `seek`；没有目标 bundle/player 参数。
- `MediaController.refresh()` 只检查 `isActive`、`previewMode`、`nowPlayingEnabled`，然后启动唯一的 system source；没有来源列表、优先级、选择或 per-app adapter。
- `applySystem()` 将快照的 bundle/title/artist/album/duration/elapsed/artwork 写入同一个 model；`model.source` 固定为“系统”。
- `SystemMediaSnapshot` 没有读取 `isMusicApp`、`mediaType`、`parentApplicationBundleIdentifier`；即使适配器 payload 有这些键，当前 normalized snapshot 也不使用。
- 当前 `command`/`seek` 绑定的是当前 system snapshot；浏览器接管后，目标就是浏览器，不能定向到后台音乐。

### 适配器能力

`vendor/mediaremote-adapter` 对应上游：

- repo: `https://github.com/ungive/mediaremote-adapter`
- commit: `797729d9b16316dc313844476c153d7a107ca0df`
- license: BSD-3-Clause（`vendor/mediaremote-adapter/LICENSE`）
- `README.md` SHA256 `73021ed63cb4ac9ea0d63f92ceed75cf720eb91a11862f64e90dcc8d74312bb0`
- `src/adapter/get.m` SHA256 `8663a55f9299f0f48fe251ae57843917ddb2fde40ce43ec6d9f845ec4df91770`
- `src/adapter/send.m` SHA256 `b1cd333df5207a0ba1a3688724963ead68b028523a4bdc348cb680202b1143ed`

事实：

- `get` 读取当前 Now Playing 信息；`stream` 推送当前 Now Playing 更新。
- `send COMMAND` 最终调用 `g_mediaRemote.sendCommand(commandValue, nil)`；无 target。
- `seek` 使用当前 destination；无 target。
- payload 包含 `bundleIdentifier`、`parentApplicationBundleIdentifier`、`isMusicApp`、`mediaType` 等字段，但适配器没有“按客户端选择”的命令接口。
- 该适配器是私有 MediaRemote 的封装，依赖 `/usr/bin/perl` 的 entitlement 与私有 framework；不是公开官方媒体来源 API。

### 归档成熟复刻已有代码（只读参考）

归档 commit：`5bdd087f5637e7f9a6ed5e54d1861b200fbe3f43`。相关文件：

- `Sources/AlcoveRevival/Controllers.swift` SHA256 `64096cf11dd80e6ac09764c19c6569c482ffeee14518df41dbd2367627979bfc`
- `Sources/AlcoveRevival/SystemMediaSource.swift` SHA256 `fa026f86d8d58c37b50ebdbb10e71e35455c6011159d80bb360fee68ddeb23da`
- `Sources/NativeBridge/NativeBridge.m` SHA256 `47944581b5fed13c22eea1ccbf6c85dc9f24464ec08886da48adc80a3cd5ef93`
- `reverse-engineering/takeover/MEDIA_CHAIN.txt` SHA256 `b1a8f0a29bc4676b4b37e69adecd9d789f980ef13d2afff3744e1bf107c10a9f`

归档已有但当前 Valora 未迁入：

- `Controllers.swift` 的 `musicSource` 分支（System/Music/Spotify/QQ音乐）。
- Apple Music/Spotify 的 `NSAppleScript` 读取/控制/seek 分支。
- QQ 的 `ARQQMusicSnapshot`/`ARQQMusicCommand` Accessibility 分支。
- `NativeBridge.ARReadNowPlayingForBundle` 使用私有
  `MRMediaRemoteGetNowPlayingClients`、`MRMediaRemoteGetNowPlayingInfoForClient`
  等读取指定 client；当前 Valora 没有这个 bridge。
- 原版 helper 的静态 reverse-engineering 还显示 per-client 对象链：
  `MRMediaRemoteGetNowPlayingPlayerForClient` → `MRPlayerPath`/`MRDestination`/`MRNowPlayingController` → `sendCommand:options:completion`。
  这条链**没有在当前 Valora/macOS 27 上运行验证**，且为私有 API；不能作为默认方案。

归档没有明确 LICENSE 文件；这里只作只读研究参考，不复制/分发其代码。`MEDIA_CHAIN.txt` 也明确记录了当时 MediaRemote clientCount=0、current client=nil 等运行限制，不能把静态还原当作成功。

## 四个音乐应用逐一核查

“独立读取”是指不依赖系统当前 Now Playing；箭头只表示静态证据下的能力，不等于本机运行通过。

| 应用 | state | title | artist | album | duration | elapsed | artwork | 定向控制 | 机制/权限 | 浏览器接管后仍真实更新？ | 证据状态 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| macOS 系统当前媒体 | 当前会话 | 当前 | 当前 | 当前 | 当前 | 当前 | 当前 | 仅当前目标 | 私有 MediaRemote adapter；无 TCC | **否**；浏览器会成为当前 | 当前源码 + adapter 源码/README；静态已证实，运行受系统影响 |
| Apple Music | 可读（sdef player state） | 可读 | 可读 | 可读 | 可读 | 可读/可写 player position | sdef artwork 类支持 picture data | playpause / next / previous / set position | Apple Events/Automation；需用户授权 | 预期可，只要 Music 运行；**未实测** | 已安装 Music 1.7 sdef + 归档 AppleScript 子集；静态已证实，运行待测 |
| QQ 音乐 | playing | title | artist | — | — | — | — | playpause / next / previous | Accessibility/AX；需辅助功能授权；要求播放控制栏窗口 | 预期可，只要 QQ 窗口存在；**未实测** | QQMusic 11.10.5 Info + 归档 AX 代码；无 sdef；运行待测 |
| Spotify | 可读（归档脚本） | 可读 | 可读 | 可读 | 可读（ms） | 可读/可写 player position | artwork URL（归档再下载） | playpause / next / previous / set position | Apple Events/Automation；需用户授权 | 预期可，只要 Spotify 运行；**未实测** | 本机未安装，无 sdef/Info 静态；只有归档脚本，不能证明本机成功 |
| 网易云音乐 | 未知 | 未知 | 未知 | 未知 | 未知 | 未知 | 未知 | 未知 | 本机未安装；没有归档本地 adapter；没有找到官方公开本地控制 API | 未知 | 无本地/源码证据，不能列作可用 |

补充：

- Apple Music 的 sdef 明确有 `player state`、`player position`（rw）、`current track`、track 的 `name/artist/album/duration`、`artwork` 的 `data`。这证明**公开脚本字典**能力，不证明用户已授予 Automation，也不证明当前播放状态一定可读。
- QQ 的 Info 有 `NSAppleMusicUsageDescription`（媒体库用途），没有 `NSAppleEventsUsageDescription`，没有找到 sdef；归档使用 Accessibility，而不是 AppleScript。不能把 Apple Music 的脚本成功推断到 QQ。
- Spotify 未安装，不能在本机读取 sdef/Info；归档脚本是成熟复刻的证据，但不是 Spotify 官方保证。**不能用 Spotify 脚本或 QQ AX 互相推断。**
- 网易云没有安装、没有归档本地 adapter、没有找到官方本地控制接口；结论是“未知/不可承诺”，不是“支持”。

### 浏览器接管后的行为

- 系统 MediaRemote：浏览器成为当前 Now Playing 后，`stream`/`get` 返回浏览器；`send`/`seek` 也发送到当前浏览器。后台 QQ/Music/Spotify 不会因此被读取。
- 如果只过滤 `isMusicApp == false`：只会让 Valora 隐藏当前浏览器快照，不能恢复后台音乐；用户会看到“没有音乐”或冻结状态。**拒绝作为解决方案。**
- 如果缓存旧歌并用本地 timer 推进：系统来源已经切换，数据不是真实更新；暂停/seek/歌词都会失真。**拒绝作为解决方案。**
- Apple Music/Spotify/QQ 的 app-specific adapter 理论上可绕过系统当前会话，直接读取各自应用；但它们依赖 Automation/AX、应用仍在运行、窗口/权限状态；本轮没有运行验证，不能写成已完成。

## 候选方案

### A. 保持 system current（无新权限）

- 复用现有 `SystemMediaSource`/`MediaController`；只能显示当前系统媒体。
- 不满足“音乐软件播放时网页视频不抢占”，也不能保证控制同源。
- 可作为 fallback，不能作为优先功能的实现。

### B. App-specific adapters（推荐方向，需用户授权权限）

复用现有 `AppModel`/UI/播放控制，新增一个薄的来源协调层：

- `MediaSource` 协议：`start/stop`、`snapshot`、`capabilities`、`command/seek`、权限/错误状态；
- System adapter（现有）+ Apple Music AppleScript adapter + QQ AX adapter；Spotify adapter 待安装/静态核验后加入；NetEase 待证据；
- `SourceCoordinator` 负责当前来源、generation、取消、退出/暂停/过期、fallback、命令同源；
- 同一 source snapshot 提供 `title/artist/album/duration/elapsed/artwork/identity`；进度使用 snapshot 的 elapsed/timestamp 锚，不用本地旧 timer 伪造；
- 歌词 identity 加入 source + track identity；切来源清旧歌词/封面；
- 命令/seek 捕获 source generation，并在执行前校验来源仍为当前；
- 不允许“显示 Apple Music、命令却走 system current”。

优点：可满足浏览器接管；缺点：Apple Music/Spotify 要 Automation，QQ 要 Accessibility；用户未授权前不能默认提示。

### C. 私有 MediaRemote per-client

- 归档/原版 reverse-engineering 有 `GetNowPlayingClients`、`GetNowPlayingInfoForClient`、`GetNowPlayingPlayerForClient`、`MRNowPlayingController` 的静态对象链。
- 理论上可读后台 client、定向发送命令；但：
  - 非官方、无稳定 ABI；
  - 当前适配器没有这条链；
  - 原版 helper 的 bundle identity/entitlement 与 Valora 不同；
  - 历史记录显示 clientCount=0/current client=nil 的运行限制；
  - 本轮无运行证据。
- 只能作为后续高风险研究候选，不应作为第一实现。

### D. 过滤/缓存

拒绝：简单过滤隐藏当前媒体；缓存旧歌伪造持续播放。两者都不能满足“真实更新”和“命令同源”。

## 推荐的最小批次

前提：先由用户确认来源范围、优先级、权限与多应用策略；本任务不授权实现。

### Batch 0：决定与权限（无代码）

需要用户回答第 7 节问题；不得默认弹出 Automation/Accessibility，不得自动排应用顺序。

### Batch 1：可验证的单来源协调（建议）

在不改变现有 UI 外观的前提下，先做：

1. `MediaSource` 协议 + `SourceCoordinator`（复用现有 `MediaController`/`AppModel`/UI）；
2. **一个**显式选择的 app adapter（建议 Apple Music，因为本机有完整 sdef、归档脚本路径和完整字段）；
3. system current 作为 fallback；
4. 明确“未授权/应用未运行/暂停/退出”状态，不缓存旧歌；
5. 命令/seek 同源校验，source generation/cancellation；
6. 现有歌词身份、进度锚、封面/标题/控制链路接入 source identity。

为什么先一个：它把来源选择、同源、退出/过期、取消/世代、歌词身份、进度锚和权限边界全部验证，而不把四个应用的不同限制混在一起。QQ/Spotify 作为后续独立 adapter；NetEase 等有安装/静态证据再评估。

### Batch 2+：逐个加入

- QQ AX：先验证当前 11.10.5 的播放控制栏、权限与读取字段；明确无 duration/elapsed/artwork/seek。
- Spotify：先安装并读取 sdef/Info，再验证 Automation 与命令；不能从 Apple Music/QQ 推断。
- 网易云：先安装并找到可引用的本地接口/脚本字典；否则不承诺。
- 私有 per-client：只有在前述路径都无法满足、且有当前 macOS 运行证据和用户明确批准时才考虑。

## 建议的测试矩阵

单元/注入测试（不运行真实媒体）：

1. 选中 Apple Music 播放；系统当前切到浏览器；Apple Music adapter 仍更新；显示/命令/seek 都指向 Apple Music。
2. 选中来源暂停、退出、崩溃、无快照；coordinator 清空/fallback，不显示旧歌或旧歌词。
3. 快速切换来源；旧 adapter 迟到回调/generation 被丢弃；不会把旧 source 的歌写到新 source。
4. 命令与 seek 在 UI 捕获后来源已变化；执行前校验失败，不向错误应用发送。
5. 歌词 identity：source + bundle + track；来源切换清旧歌词；同歌跨来源不误复用。
6. 进度锚：source elapsed/timestamp + rate；暂停冻结；seek 后重锚；无 snapshot 时不靠本地 timer 伪造。
7. 权限 denied/未决定/取消：开关保持 off，不发起系统提示（直到用户操作）；不把 denied 当 no track。
8. 应用未安装/未运行/窗口不存在：明确错误/fallback，不冒充当前来源。
9. 多个音乐应用同时播放/全部暂停：按待定策略；未决定前不自动选一个排名。
10. 浏览器/视频：不得被显示为音乐；不得用过滤隐藏后台音乐来假称优先。
11. 现有音乐 UI：普通波形、封面、播放/暂停、seek、音量、歌词、双击/多屏不回归。
12. QQ：无 duration/elapsed/artwork/seek 时 UI 不伪造；Apple Music/Spotify：artwork 缺失/加载失败可回落。

真实设备/媒体验证必须由用户明确安排；本轮不运行。

## 需要用户决定的事项

1. **允许的音乐来源**：QQ、网易云、Apple Music、Spotify 全部？还是先 Apple Music？
2. **优先级/选择方式**：显式选择来源，还是自动；若自动，哪个应用优先？多个同时播放怎么办？未确认前不自定排名。
3. **浏览器/视频**：是“完全不显示”，还是作为非音乐 fallback；YouTube Music 等网页音乐如何归类？
4. **权限**：是否接受 Apple Music/Spotify 的 Automation、QQ 的 Accessibility？是否允许首次使用时弹系统授权？不能默认。
5. **多应用同时播放**：只显示一个、全部暂停、还是用户选择；没有确认不实现。
6. **QQ 能力降级**：只有 state/title/artist，没有 duration/elapsed/artwork/seek；UI 如何显示“不可 seek/无封面”？
7. **来源退出/暂停**：清空、隐藏、回退 system current，还是保留最后快照（不得继续计时/伪装更新）？
8. **UI**：V0019 当前没有来源选择；是否允许在音乐页增加一个最小来源选择控件，还是只用自动策略？
9. **Spotify/网易云**：是否安装并提供静态核验；未安装前不能承诺。
10. **私有 MediaRemote per-client**：是否允许高风险试验；不建议第一版。

## 证据与限制

- `docs/verification/v0021/static-evidence.json`：当前/归档/适配器文件哈希，QQ/Music 静态 Info，Music sdef 哈希，Spotify/网易云未安装。
- `Sources/Valora/SystemMediaSource.swift`、`Controllers.swift`、`ReferenceCore/SystemMediaSnapshot.swift`：当前实现。
- `vendor/mediaremote-adapter`：README/private header/send/get；BSD-3-Clause，commit `797729d9...`。
- 归档 `Sources/AlcoveRevival/Controllers.swift`、`Sources/NativeBridge/NativeBridge.m`、`reverse-engineering/takeover/MEDIA_CHAIN.txt`：成熟复刻/静态还原；归档无明确 LICENSE，未复制代码。
- 已安装 Music 1.7 `com.apple.Music.sdef` SHA256 `ebc83706f8b3b5b2db66dd0adcaac96abaad5fdd2c67b1c2fe185d510f65e664`；QQMusic 11.10.5 Info SHA256 `a61c1a1d634d385abedb4b5744a9582ee4a08907bb177c15e0d11baabd2272e5`。
- 公开官方参考（只用于能力边界，不作为本地成功证明）：
  - Spotify Web API current playback: `https://developer.spotify.com/documentation/web-api/reference/get-information-about-the-users-current-playback`
  - Spotify Web API start/resume: `https://developer.spotify.com/documentation/web-api/reference/start-a-users-playback`
  - 这些是远端 Web API，要求账号/活跃设备/Premium，不等同于 macOS 本地来源优先；本轮没有调用。
- 没有 Spotify/网易云安装静态证据；没有运行任何播放器/MediaRemote/AppleScript/AX/权限/媒体命令。静态字典/源码存在不等于用户权限、当前应用版本或运行行为已经通过。
