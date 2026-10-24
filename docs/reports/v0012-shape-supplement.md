# V0012 补充报告：无实体刘海统一宽度、歌词解耦与多歌手匹配

> 后续 R1（居中/胶囊/取消/逐字平滑）见 `docs/reports/v0012-r1.md`；最终测试/产物以 `docs/reports/v0012-r3.md` 和 `docs/verification/v0012/` 为准。

- 任务：`docs/pi-tasks/v0012-supplement-nonnotch-lyrics.md`
  （SHA256：`7d38349ed7a718ff0ccb58b2e3e124ac3972da9d42afc7b39cb22a85d9f7345c`，已核对）
- 优先级研究：`docs/pi-tasks/v0012-priority-lyrics-reference-review.md`、`docs/verification/zhifou-lyrics-diagnosis/findings.md`
- 结论：无实体刘海屏的模拟刘海/普通胶囊统一基础 140pt、音乐紧凑 214pt、展开 345pt；歌词能力与“强制模拟刘海”解耦；多歌手不完整系统署名可按保守集合规则匹配，但男声版/Live/伴奏仍被版本保护拒绝。原 3 秒预算、QRC 逐字、封面主色、阅读区和有界缓存保持。

## 1. 最终几何

| 屏幕 | 形态 | 无音乐基础宽 | 音乐紧凑总宽 | 展开总宽 | 形状 |
|---|---|---:|---:|---:|---|
| 有实体刘海 | 硬件几何 | 185pt（本机样例） | 硬件链路 | 345pt（本机样例） | 不套用非刘海固定值 |
| 无实体刘海 | 模拟刘海 | 140pt | **214pt** | **345pt** | 贴顶、肩部、notch contour |
| 无实体刘海 | 普通胶囊 | 140pt | **214pt** | **345pt** | 圆角胶囊、既有顶部间距/高度 |

实现位置：

- `NotchGeometry`：无实体刘海两种形态 compact 统一 140pt、expanded 统一 345pt；`hasPhysicalNotch` 仍为 false，未伪造实体刘海。
- `PresentationMetrics`：无实体刘海音乐/QuickPeek playing 增量统一 74pt，避免 140+62=202pt 的错误；基础 140pt。
- 保留模拟刘海肩部与普通胶囊圆角/顶部高度差异；通知宽度和实体刘海尺寸未改。
- 无音乐基础宽两种形态均为 140pt；无实体刘海不套用 214pt。

## 2. 歌词与模拟开关解耦

- `showsCompactLyrics`/`lyricsAvailable` 不再检查 `forceSimulatedNotch`；只受歌词总开关、有效音乐活动、有效 timed/wordTimed 歌词和 3 秒结果约束。
- 同一无实体屏 `forceSimulatedNotch=false/true` 都显示歌词；切换形态不清空有效歌词、不重新搜索。
- 无歌词/失败/超时仍隐藏，不留空条或歌名占位。
- 展开态两种形态都显示最底部歌词，音量打开时顺序播放器→音量→歌词；紧凑/展开共享同一时间轴和缓存。
- 活动屏显示动态，被动屏保持常规紧凑内容。

QA 截图：

- `docs/verification/v0012/qa/lyrics-nonnotch-pill-compact.png`
- `docs/verification/v0012/qa/lyrics-nonnotch-simulated-compact.png`
- `docs/verification/v0012/qa/lyrics-nonnotch-simulated-expanded.png`
- 以及 `lyrics-active-external.png`、`lyrics-passive-builtin.png`、`lyrics-expanded-bottom.png`。
- 断言使用黑色可见内容宽度 `model.visibleSize.width == 214/345`，不以 624pt 透明宿主宽代替。

## 3. 多歌手匹配修复

真实诊断：系统 artist=`胡夏`，QQ 合唱候选 artist=`胡夏 / 郁可唯`，同专辑/276s；另有同专辑同长度的 `胡夏 - 知否知否 (男声版)`。

- 原匹配器 `normalized(candidate.artist) == normalized(request.artist)` 误拒合唱候选。
- 新规则：标题/版本签名、专辑、时长先过滤；之后要求**请求歌手集合是候选歌手集合的子集**。因此 `胡夏` 可匹配 `胡夏 / 郁可唯`；请求 `胡夏 / 郁可唯` 对仅 `胡夏` 候选仍拒绝；男声版因版本签名不匹配而拒绝。
- 不采用 `contains` 整串、不选第一条；仍有歧义则无匹配。
- 回归：`testIncompleteSoloArtistAcceptsCollaborationButNotMaleVersion`、`testMissingRequestedCollaboratorIsStillRejected`，以及原有版本/专辑/时长/歧义测试。
- 证据摘要：`docs/verification/v0012/zhifou-match/summary.json`；方案对照：`docs/research/lyrics-provider-comparison.md`。

## 4. QRC、预算与缓存（保持）

- 真实公开样例 QRC 已解码：studio 63 行/602 words、live 36 行/391 words；首 word duration 0.16/0.50s；日志只摘要，不输出整首歌词。
- QRC 使用 MIT QQMusicDecoder 的 Swift 适配，许可见 `docs/verification/v0012/source-license.md`；未复制 GPL Lyrimuse、未引入 Go。
- 3 秒总预算、失败/超时不缓存、成功 timed/wordTimed 有界缓存、LRU、哈希文件名、原子写、取消竞争保护均保持。
- 无真实播放器/网络 UI 对齐宣称；真实 QRC 仅显式公开样例网络探针。

## 5. 验证

- XCTest：**161/161 通过**（Valora 59 + ReferenceCore 102），原 147 项回归。
- 歌词 QA：**27/27 通过**，新增两种无刘海紧凑形态/展开/音量/活动屏截图与宽度断言。
- 音乐 UI：**74/74**；注入多屏：**12/12**；设置两页通过。
- `codesign --verify --deep --strict` 通过。
- 产物 binary SHA256：`3e3af8de6596d5304c090458f4fd2bbc343dd084b7371bd943a653a7ac634408`
- 13 个包文件，5,469,374 bytes；清单 `docs/verification/v0012/artifact-manifest.json`。

## 6. 限制与停止点

- QA 使用静态歌词/播放状态和注入屏幕；不是物理双屏或真实播放对齐验收。
- 真实 QRC 网络探针为显式公开样例，不代表所有歌曲；无网/失败仍按 3 秒规则隐藏。
- 未执行真实媒体/系统/设备写操作，未安装/发布/Git 提交；未改品牌图标、Outline-v7 打包接线或来源归档。
- V0012 补充完成，停止等待 Codex 独立验收。
