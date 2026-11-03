# V0042 锁屏音乐玻璃：回到原版调用链与成熟复刻

2026-11-03，现有 OpenCode 会话执行（`docs/opencode-tasks/v0042-lock-music-glass-source-parity.md`）。
按 Codex 复核的证据重建锁屏音乐卡背景，停止 Liquid Glass / 自绘壁纸 / 明暗叠层的实验路线。

## 证据与结论

- `reverse-engineering/lock-screen-music/100186a7c.c:443–452`：该调用点参数为 `material = 0xd`、`blending = 0`、`state` 取默认（active）、`+0x38` 的 `0x101` 后字节即 `frosted = true`、`corner 28`。
- `100131c1c`：只有 `macOS >= 26 && frosted == false` 才创建 `NSGlassEffectView`；否则走 `NSVisualEffectView` 的 `setMaterial / setBlendingMode / setState / setEmphasized`，外层 `NSView` 负责连续圆角裁切、effect 四边约束。
- 因此 **锁屏音乐卡不是 Liquid Glass**。V0041 里"通用工厂能建 Glass ⇒ 锁屏就走 Glass"的推论是错的，已在 `docs/reports/v0041-lock-visual-parity.md` 顶部更正，历史实验保留为失败记录。
- `Sources/AlcoveRevival/LockFrostedBackground.swift`、`LockMusicCoordinator.swift:54–85` 是成熟复刻的玻璃底稿，用户确认这条路线可用。

## 源码变更

1. `Sources/Valora/LockFrostedBackground.swift`（重写，按反编译容器形态）
   - 外层 `NSView` 持有 `layer.cornerRadius = 28`、`cornerCurve = .continuous`、`masksToBounds`，负责裁切；
   - 内层 `NSVisualEffectView` 四边约束到外层：`material = .hudWindow`、`blendingMode = .behindWindow`、`state = .active`、`isEmphasized = true`、`appearance = .darkAqua`；
   - `hitTest` 返回 nil，装饰层不吃交互；
   - 显式 `sizeThatFits` 回传建议尺寸，杜绝"AppKit 视图无固有尺寸把卡片撑大"再次发生（上一轮 345 → 385 的根因）。
2. `Sources/Valora/LockMusicView.swift`（`LockMusicCard`）
   - 按复刻底稿恢复层级：播放器内容 → `.background(LockFrostedBackground(cornerRadius: 28))` → `.overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 0.5))` → `.environment(\.colorScheme, .dark)`；
   - `.background` 不参与前景尺寸计算，`frame(width: 345)` 保持不变；
   - 删除 `.glassEffect`、`LockWallpaperLayer`、`Color.black` 叠层等实验实现。

### 与复刻底稿的差异（必要适配，非重设计）

- 复刻把根 `.environment(\.colorScheme, .dark)` 放在承载卡片的外层 VStack；Valora 里同一个 `LockMusicCard` 有两个宿主（真实锁屏面板、`--lock-card-preview` 预览），因此把该环境放在卡片自身，保证两条路径一致。
- 复刻里 `glass` 是可关偏好；Valora 的 `lockPreferences.glass` 固定为 true（V0036 冻结策略），故不再分支，直接走玻璃。
- Swift 6 / macOS 27：容器视图与 `NSVisualEffectView` 仍是 AppKit 层实现，未引入并发标注以外的改动；`init?(coder:)` 标记 unavailable。

## 保留未动

顶部独占 Space 与锁解动画链（原地开锁 → neutral → 最新音乐）、V0040 三项锁屏设置与各模块总开关、耳机单行 16pt 与顶部对齐、进度条未播放段 0.16、从下往上滑入、普通刘海播放器/歌词、权限与日历、显示来源。

`--lock-card-preview` 保留：它复用同一个 `LockMusicCard`，仅用于核对几何/尺寸/内容；桌面合成下的 `NSVisualEffectView` 比锁屏态偏亮，不能当作真实锁屏材质结论。本轮未启动它。

## 验证

- `swift build` / `swift build -c release` 通过。
- `LockMusicCoordinatorTests` 31 项、`LockMusicStateTests` 13 项通过（无窗口功能回归）。
- 尺寸：卡片前景 `.frame(width: 345)`，背景在 `.background` 中且 `sizeThatFits` 回传建议尺寸，源码层面不会再把卡片撑到 panel 的 385pt。
- 候选：`/private/tmp/valora-v0042-lock-music-glass-candidate/Valora.app`
  - binary SHA-256 `1876b399ae1d86522ff83277ec905fd9e3fb5e3ba3f11d600ce67b0d9f2a82a7`
  - `codesign --verify --strict --deep` 通过
  - **未启动**，未覆盖 `dist`，未退出/启动用户当前运行的实例。

## 边界

- `darkAqua` 与 0.5pt/15% 白色细边是**成熟复刻的体验底稿**，不是已证明的原版精确参数；原版私有玻璃的最终观感仍以用户一次真实锁屏为准。
- 未做真实锁屏/锁通知/多屏/性能/UI 循环测试，未读取壁纸、个人日程、真实媒体，未操作播放/seek/音量/设备连接/授权。
- 不声称"玻璃已实机一致"；等 Codex 独立验收与用户一次体验。
- 无 Git 提交/推送，定时器保持关闭。
