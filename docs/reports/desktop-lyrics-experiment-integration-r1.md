# 桌面歌词实验接入 R1：回退行、长句对齐与回调代次

执行：原会话、原模型、分支 `codex/idle-cpu-optimization`。按 `docs/opencode-tasks/desktop-lyrics-experiment-integration-r1.md` 与独立验收报告返修。普通构建隔离与锁屏旧路径保留；未打包、未启动/替换 App、未提交。

## 一、修复内容

### 1. 回退改为最外层完整生产行

`ExperimentalDesktopLyricsView.body` 现在：

```
if host.failed → CompactLyricsView(width, rowHeight, showsNote, horizontalInset,
                                   centersNoteWhenEmpty, auditRole)   // 最外层整体替换
else → 实验行（音符 + 原生宿主 + 同样的 frame/padding/clip/无障碍）
```

- 回退分支**不再嵌套**在实验行的 HStack 里，也不再强制 `showsNote:false`；参数与普通调用完全一致。
- 失败时原生宿主在同一更新里被移除（`dismantle` → `stop`），只保留一条渲染链。
- 实测：注入抓图失败后，回退行与生产 `CompactLyricsView` 的截图为 **0/30208 差异像素（0.0%，均值 0.00）**，即字节级相同；树中不再有 `NativeLyricsRowView`，capture 窗口计数回到基线。

### 2. 长句整体对齐恢复生产规则

- 实验行外框改为 `alignment: isLong ? .leading : .center`；`isLong` 由**真实当前行**的 `LyricsLineMetrics.totalWidth > availableWidth` 决定（宿主节奏更新，随行/宽度变化），没有把 30Hz 状态提升回宿主。
- 真实宿主对照（同一 `NSHostingView` 尺寸、2x、同模型）：

| 场景 | 与生产整行差异 |
|---|---|
| 短句 + 音符（32pt 行，18pt inset） | 0.9%（mean 0.84） |
| 长句 + 音符（4s 滚动） | 8.7%（mean 1.57） |
| 内嵌无音符（17pt 行，10pt inset） | **0.0%（0 差异像素）** |

- 外层 `frame.size` 与生产一致（测试断言）；音符、无音符、内嵌三种外层坐标/裁剪按生产参数构造。

### 3. 回调异步 + 代次/身份校验

- 新增 `LyricsRowExperimentHost`（`@StateObject`）：持有 `identity`、`generation`、`failed`、`label`。
- `onLineChange` / `onRenderFailure` 一律 `DispatchQueue.main.async` 投递，并携带创建时捕获的 generation + identity；到达时校验仍匹配才生效。
- **关键修正**：`begin(identity:)` 在 representable 的 `wire()`（make/update）里同步执行——`.onAppear` 可能晚于首次 `makeNSView`，否则首帧失败回调会因代次为 0 被丢弃。
- 切歌：`onChange(of: identityKey)` 调 `begin`（换代、清失败/标签）；卸载：`onDisappear` → `invalidate()`（换代），迟到回调全部丢弃。
- 无每帧回调：渲染器只在换句/失败时回调，不产生无限重试。

隔离用例（实验构建）：当前回调生效、旧代次/旧身份被忽略、卸载后迟到回调被丢弃。

## 二、验证

实验构建测试（真实 `NSHostingView`，单窗口、不批量开关）：

| 用例 | 断言 |
|---|---|
| 短句 + 音符 | 外层尺寸相等、原生行已挂载、整行差异 0.9% |
| 长句 + 音符 | 同上，差异 8.7%（长句残余） |
| 内嵌无音符 | 整行 0 差异像素 |
| 注入失败 | 原生行被移除、capture 窗口计数回基线、回退整行与生产 **0.0%** 差异 |
| 宿主状态 | 当前/旧代次/旧身份/卸载后回调 |

构建与测试计数：

| 项 | 结果 |
|---|---|
| 普通定向组合（同 R2 组 + 接入用例） | 执行 **154**，跳过 **7**（opt-in 探针 + 实验构建专属选择用例），**通过 147**，失败 0；ReferenceCore 另 6 通过 |
| 实验构建定向组（含宿主测试） | 执行 **70**，跳过 **7**，**通过 63**，失败 0 |
| 普通 Release | 构建成功；`nm` 中实验实现计数 **0** |
| 实验 Release | 构建成功；实验实现符号计数 **366** |

锁屏 `LockMusicView` 仍直接使用 `CompactLyricsView`，未改。

## 三、未验 / 风险（不宣称等价）

- 长句整行仍有 **8.7% 差异像素（mean 1.57）**，属亚像素采样/AA；短句 0.9%、内嵌 0.0% 是整行（含音符）对照结果。
- 换句过渡逐帧、1x、真实多显示器、真实播放、CPU/内存均**未验**。
- 实验构建仅用于本机评估，未打包、未安装、未启动/替换 App；回退方法仍是不设 `VALORA_LYRICS_EXPERIMENT` 重新构建（无持久化开关）。
- 无障碍标签仅由宿主回调维护，未在真实 App 复核。

## 四、边界

未安装、未启动/替换 App、未操作真实播放、未打包提交；未改锁屏/波形/音频/设备/菜单栏/窗口扫描；未改生产样式/时间/帧率。
