# V0043-R1 锁屏音乐前景/背景明暗分离与交付证据更正

2026-11-03，现有 OpenCode 会话执行（`docs/opencode-tasks/v0043-r1-contrast-and-delivery-evidence.md`）。
独立验收结论：底层方向与功能子集接受，整体视觉未放行。本批只做前景/背景明暗策略收尾 + 交付证据更正。

## 一、原版明暗策略（证据）

`100187f28.c`（macOS 26+ 调用点）里背景与前景是**两条独立分支**：

| 位置 | 事实 |
|---|---|
| `1031–1048` | `LockManager._isWallpaperNearlyWhite` → 私有 `variant = 2`（壁纸近白）/ `5`（其它），corner 30 |
| `1055–1065` | **背景**颜色方案固定为 `light` |
| `1078–1088` | **前景**颜色方案独立选择：`_isWallpaperNearlyWhite == 0` → `ColorScheme.dark`（即白字）；否则 `light`（深色字） |

所以关键是：**玻璃背景恒为浅色**，而文字明暗由壁纸亮度另算。这解释了用户截图里"浅色玻璃 + 白字"的组合，也说明我此前把整棵子树强制成某一种 scheme 是错的。

## 二、本批实现

1. `Sources/Valora/LockCardAppearance.swift`（新）
   - `LockCardPalette`：`primary / secondary / waveform / track` 四支语义墨色；
   - `onDarkWallpaper`（白墨）与 `onLightWallpaper`（黑墨）两套；
   - `LockCardAppearance`：`glassScheme` 恒为 `.light`（背景），`contentScheme` 由 `wallpaperIsNearlyWhite` 决定（前景），`palette` 由同一标志派生；
   - `standard` = 非近白壁纸 → 浅玻璃 + 白墨，与所有已观察到的锁屏实拍一致。
2. 前景全部改走 palette（不再写死 white）：
   - `MusicPlayerContent`：新增可选 `palette`，只作用于 `translucent` 分支（普通黑底刘海播放器 `translucent = false` 完全不受影响）；
   - `MediaProgressView`：`textColor` / `trackColor` 的 translucent 分支走 palette；
   - `PlayerWaveform`：translucent 分支走 palette；
   - `LockMusicCard`：`foregroundStyle(appearance.palette.primary)`，玻璃用 `appearance.glassScheme`。
3. 未改：卡片 345 / 圆角 30 / `.clear` 玻璃、顶部独占 Space、锁解链、V0040 三项设置与总开关、耳机单行、进度未播放段、滑入、普通刘海播放器与歌词、权限/日历。

### 未知与缺口（不假装已匹配）

- **壁纸亮度信号目前没有**：`_isWallpaperNearlyWhite` 的等价输入在 Valora 里不存在，所以只有 `standard`（非近白）这一条在跑。
  要补齐需要读当前桌面壁纸并估算亮度，方案会是：`NSWorkspace.shared.desktopImageURL(for:)` → 缩到 32×32 → 平均相对亮度 → 阈值判断；**数据不出本机、不落盘、不截屏**。按任务要求本轮**未实现、未读取真实壁纸**，等明确授权。
- 私有 `variant 2/5` 仍无公开映射；`.regular` 与 `.clear` 都是 macOS 26 Liquid Glass 样式，本批不换材质、不试色。
- 前景策略已可测（fixture），但真实观感仍需一次实机确认。

## 三、验证

- `swift test --filter LockCardAppearanceTests|LockMusicCoordinatorTests|LockMusicStateTests`：
  - 新增 `LockCardAppearanceTests` **4 项**：standard 浅玻璃 + 白墨；近白壁纸切换黑墨且玻璃仍浅；背景与前景互不影响；palette 派生一致。
  - `LockMusicCoordinatorTests` 31 项、`LockMusicStateTests` 13 项通过（共 48 项）。
  - 无窗口、无真实 NSWindow/Space/锁通知、无壁纸读取、无截图。
- 构建：debug / release 通过。
- 候选：`/private/tmp/valora-v0043-r1-lock-contrast-candidate/Valora.app`
  - binary SHA-256 `e99f9d0a3b92c84516f40c2f62d4510b081a1b3fd3ad7e456a4dcfbf585eb0e0`（冻结）
  - `codesign --verify --strict --deep` 通过
  - **独立新路径，未启动，未覆盖旧候选或 `dist`，未退出/启动用户任何实例**

## 四、交付证据更正（对应验收第 3 条）

`docs/reports/v0043-modern-lock-glass-branch-correction.md` 已更正：

- 该报告初版称候选"未启动"是错的。实际在用户要求下以 **PID 16503** 运行过 `valora-v0043-modern-lock-glass-candidate`，并用 `--lock-card-preview` 在该目录做过桌面预览截图。
- 该候选目录在迭代中被**同一路径覆写多次**（`.regular` → `.clear`，另有一次直接 `cp` 二进制再重签做快速预览），所以"报告 hash / 截图 / 当时运行版本"无法一一对应。这是流程错误。
- 本批起改为**独立目录 + 冻结 hash**，不再覆写旧路径；桌面预览只用于几何核对，不作为锁屏材质证据。
- 同时更正该报告里"公开样式不一样就一定是私有 variant / 无法公开实现"的绝对推论：前景色、appearance、容器与合成路径都尚未排除。

## 五、边界

未做真实锁屏 / 锁通知 / 真实 NSWindow / Space / 多屏 / UI 循环 / 批量截图 / 性能；未读壁纸、个人日程、账号数据；未控制真实媒体、设备、权限；无 Git 提交推送；定时器关闭。交付后停等 Codex 独立验收。
