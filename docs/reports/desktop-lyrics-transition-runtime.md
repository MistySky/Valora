# 桌面歌词换句：运行时视口动画

执行：原 OpenCode 会话、原模型、分支 `codex/idle-cpu-optimization`。按 `docs/opencode-tasks/desktop-lyrics-transition-runtime.md` 处理。运行中的用户实例未触碰；未打包、未安装、未启动/替换 App、未操作真实播放、未提交推送。本轮为实验版（`VALORA_LYRICS_EXPERIMENT`）内部改动，普通构建不含实现。

## 一、实现

### 1. 渲染器（`Sources/Valora/NativeLyricsRow.swift`，仅实验/开发编译）

- `NativeLyricsRowSnapshot.switchAnimation`：实验宿主关闭渲染器自带的 CA 换句，避免两套动画叠加。
- 新增 `NativeLyricsStaticLine`：换句瞬间冻结上一句的 base/accent `CGImage`、17pt 内容尺寸、逐字 mask 宽度、旧水平视口宽度、容器位置与 image scale。
- `switchLine` 在构建新行之前冻结旧行，通过 `onSwitchOutgoing` 同步交给宿主，再照常 `onLineChange`。旧行仍使用同一份已缓存的文字位图，不新建第二张时钟或文字管线。
- 空行清除位图时同步清空冻结图像，避免空行之后误用更早一句的旧图。

### 2. 宿主驱动（`Sources/Valora/LyricsRowExperiment.swift`）

- `outgoing` + `incoming/outgoing` 的 offset/opacity 状态；换句时启动 **0.2s、60Hz 的过渡驱动**（仅过渡期间存在），使用 `cubic-bezier(0.42, 0, 0.58, 1)` easeInOut：
  - 进入：`y = +26 → 0`，`opacity = 0 → 1`
  - 退出：`y = 0 → -26`，`opacity = 1 → 0`
- `transitionGeneration` 代次令牌：快速连续换句、隐藏、失败、卸载都会使旧驱动失效；每次换句先 `stopTransition()` 释放旧行。
- 无旧行快照（首句、空行、失败）时**立即显示新行**，不进入 0 透明度状态（与生产在无 outgoing 图层时的行为一致）。
- 失败回调与行回调存在先后不确定性：`failed` 后忽略行回调并停止过渡，避免失败回退被重新拉回过渡状态。
- `debugManualTransition` + `debugSetTransitionProgress`：测试可确定性逐点步进；不改变生产路径。

### 3. 视图

- 实验行改为 `ZStack`：离场行是 `StaticLyricsLineView`（纯 CALayer 冻结快照，无时钟、无逐帧重建），进入行是唯一的 `NativeLyricsRowHost`。
- **整个 17pt 视口**（含内部水平长句裁剪与 mask）随 offset/opacity 移动，外层由实际 `rowHeight` + `.clipped()` 裁切；不再在固定 17pt clip 内移动文字。
- 过渡容器宽度取进入/离场视口并集，避免任一侧被容器提前截断；过渡结束 `outgoing == nil` 后恢复为进入行宽度，短句居中/长句前导的几何与生产一致。
- 切换句子时 `rowHeight`、音符、水平内层裁剪、字体/字距/配色均未改动。

## 二、验证证据

### 1. 端点静态帧与生产完全一致

同一 2x、200pt 行、32pt rowHeight、带音符、同一隔离画布：

| 端点 | 与生产参考帧差异 |
|---|---|
| 过渡开始（旧句、offset 0 / opacity 1） | **0/30208 像素（0.0%，mean 0.00）** |
| 过渡结束（新句、offset 0 / opacity 1） | **0/30208 像素（0.0%，mean 0.00）** |

这直接验证：离场快照在开始时就是生产的旧行画面，进入行在结束后就是生产的新行画面。PNG：`/private/tmp/valora-transition-runtime/endpoint-*.png`。

### 2. 真实宿主确实执行完整进入/退出（非仅设置参数）

`testSwitchKeyFrames` 在真实 `NSHostingView` 中触发换句并连续截图（循环采样，非精确墙钟）：

- 换句后宿主进入 `outgoing != nil`、`settled == false`；随后自动完成并 `outgoing == nil`、`settled == true`。
- 采样状态（实际运行值）：`offset=26.00, opacity=0.000` → `offset=22.00, opacity=0.154` → `offset=0.82, opacity=0.968` → 完成 `offset=0, opacity=1`。
- 截图：开始时生产/实验 ink 均为 `742`、y=21（旧句）；结束后均为 `4857`、y=21（新句）；中途实验画面随视口移动而改变。
- 全程 `NativeLyricsRowView` 数量恒为 **1**；`lineSwitchAnimations == 0`（渲染器 CA 换句未启用）。

### 3. 逐点步进（确定性）

`debugManualTransition` 下按 0/0.25/0.5/0.75 步进，断言四个状态量与 easeInOut 预测一致（容差 0.2pt / 0.01），并逐帧截图；短→长、长→短两个方向都执行。相邻步进的像素缓冲均存在差异，证明呈现状态真的在变化，而不只是参数被设置。PNG：`/private/tmp/valora-transition-runtime/short-to-long-progress-*.png`、`long-to-short-progress-*.png`（目视可见旧句上移淡出、新句从下进入）。

### 4. 边界与生命周期

| 场景 | 结果 |
|---|---|
| 短→长 / 长→短 | 过渡完整执行；结束释放离场快照；单 renderer |
| 快速连续换句（A→B 中途→C） | 离场快照替换为 B（`lineKey` 1.0-），最终停在 C；始终 1 个 renderer + 1 个冻结视口 |
| 暂停 + seek | 暂停不改变当前行且能结束过渡；seek 到新行重新触发并正确结束 |
| 空行→下一句 | 无旧快照时立即显示新行（与生产无 outgoing 图层一致）；空行边界唤醒用例继续通过 |
| 隐藏 | `notchSurfaceOnScreen=false` 立即释放离场快照并回到 settled |
| 捕获失败 | 失败后回退整行生产视图，离场快照释放，不再重新进入过渡 |
| 卸载 | `contentView=nil` 后过渡状态释放，迟到的行回调不推进当前行 |
| 窗口释放 | 渲染器 capture window 在回退/卸载时关闭（既有断言保留） |
| 空行卡死回归 | `IndependentLyricsEmptyTransitionTests` 继续通过 |

### 5. 单时钟 / 低开销

- 过渡中仅一个 `NativeLyricsRowView`；离场行是静态 CALayer 快照，不启动 30Hz 歌词时钟。
- 逐帧不重建 SwiftUI Text/位图：步进全程 `textBuilds` 只增加 1（新句自身的一次构建）。
- 60Hz 驱动只在 0.2s 过渡期间存在，且被代次令牌约束；结束/隐藏/失败/卸载/快速换句都会使其失效。
- 未新增任何生产设置、未改动画时长/曲线/方向。

### 6. 上一轮过渡状态干扰测试的原因（已修复）

1. 既有像素/行为用例在触发换句后立即截图，而当时过渡已变为真实 0.2s 动画，截图落在中途（新行仍透明/偏移），于是“长句必须可见”等断言失败。现在像素比较前等待 `host.isSettled`；断言本身未删除、未放宽。
2. `testSwitchKeyFrames` 的实验段复用了测试开头的 `anchor`，实验行挂载时时钟已越过第二句起点，实际根本没有发生换句。现在实验段使用新的挂载锚点，并新增“开始=旧句、结束=新句”的端点断言。
3. 失败回调可能先于行回调到达，行回调会把刚停止的过渡重新启动。现在 `failed` 后忽略行回调并停止过渡。
4. 无旧快照时空行分支曾按 progress 0 设置进入 opacity 0，导致新句不可见；现在无 outgoing 时直接 settled 显示。

## 三、测试与构建

| 项 | 结果 |
|---|---|
| 实验组（空行 1 + 宿主单元 3 + 真实宿主 22 + 集成 5 + 静态帧 3） | **执行 34，跳过 1，通过 33，失败 0** |
| 其中真实宿主 22 项 | 含 7 项本轮新增运行时过渡用例，全部通过 |
| 普通定向组合 | **执行 154，跳过 7，通过 147，失败 0**；ReferenceCore 另 6 通过 |
| 普通 Release | 成功；实验实现符号 **0** |
| 实验 Release | 成功；实验实现符号 **379** |

本轮未削弱/删除既有断言，未跳过失败场景，未硬编码测试环境。新增 PNG 证据与静态帧 PNG 均在 `/private/tmp/`。

## 四、未验 / 风险

- **真实 App 体感未验**：本轮只证明真实宿主中的状态推进、逐点呈现差异与端点像素一致；0.2s 内的逐帧与生产动画无法在本 harness 锁定同一墙钟，未声称体感等价。
- **CPU/内存本版未测**；未做压力/反复开关/批量闪窗（按项目约定留到完成后的优化阶段）。
- 1x、真实物理多显示器/刘海、真实播放与音量、锁屏路径均未新增验证；锁屏与普通构建未改动。
- 过渡中途的水平原点在“旧句/新句宽度不同”时可能与生产瞬时有几像素差异（生产本身也在换句时重排 HStack）；端点几何已证明一致，中途未做逐像素对照。
- 未打包、未安装、未启动/替换任何 App；当前运行实例保持原样。

## 五、回退

实验实现全部位于 `VALORA_LYRICS_EXPERIMENT` 条件编译内；不设置该环境变量时普通 Release 实验符号为 0。回退只需不启用该构建标志（或删除实验文件/用例），生产 `CompactLyricsView` 与锁屏路径不受影响。

## 六、边界

未安装、未启动/替换 App、未操作真实媒体/权限/设备、未打包提交；未改锁屏、波形、音频、设备、菜单栏、窗口扫描；未改歌词时间轴、30Hz 帧率、字体/字距/配色。
