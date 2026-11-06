# V0050 锁屏音乐卡：真正的玻璃/透明效果 + 三项样式设置

> **已被 V0051 更正**：参考页只提供 Glass / Clear 两项（且用两块材质预览卡片），Frosted 只属于 macOS 26 以下的旧分支。
> 本文保留当时的取证与材质实现记录，最终设置页以 `docs/reports/v0051-lock-glass-settings-tiles.md` 为准。

2026-11-03，本次由 Codex 直接实现（用户：看 archive 和 tmp 逆向，把锁屏的玻璃和透明效果做出来，包括设置）。

## 一、取证（archive + /Users/wangqing/code/tmp 逆向）

| 来源 | 事实 |
|---|---|
| `alcove-analysis` 二进制字符串 | 原版 1.7.9 确有锁屏音乐样式设置：`settings.lockScreen.nowPlaying.style.frosted / .clear / .glass`，`en.lproj` 对应文案 `Frosted / Clear / Glass` |
| 同二进制枚举元数据 | `enum NowPlayingStyle` 声明顺序 `glass, clear, frosted` |
| `alcove-revival-archive/docs/alcove-1.7.9-detail-audit/原版锁屏默认值-2026-10-18.txt` | `NSUserDefaults` 注册默认 `nowPlayingStyle = Glass`（tag 0） |
| `reverse-engineering/lock-screen-music/100186a7c.c:134–137 / 443–452 / 572–595` | OS < 26 走 `.hudWindow` 描述符（`material 0xd`、`frosted=1`）；OS ≥ 26 调用 `100187f28(宽345, 圆角30)` |
| `reverse-engineering/lock-screen-music/100187f28.c:94–451` | `frosted` 分支：描述符 `material 0xd`、`+0x39=1` → `NSVisualEffectView` |
| `100187f28.c:452–1094` | 其余样式分支：`material 0xd`、`variant 2（近白壁纸）/5`、`+0x38=0x200`、背景 `ColorScheme.light`、前景按 `_isWallpaperNearlyWhite` 另选；`+0x39=2` 使 `frosted & 1 == 0` → `NSGlassEffectView` |
| `lock-appearance-0.6.5/100131c1c.c` | 工厂：`frosted & 1 == 0` 时建 `NSGlassEffectView` 并 KVC 写 `variant`、`cornerRadius` |

结论：
1. 原版**有三个**样式，不是两个；默认 **Glass**。
2. macOS 26+ 原版确实走 `NSGlassEffectView`（带私有 `variant` 2/5），`.hudWindow` 只属于旧系统分支。
3. 私有 `variant` 数值没有公开映射。本批用**公开原生材质**按名称对应实现，不 KVC 猜私有值，也不自绘壁纸/叠黑白纱。

## 二、实现

### 1. 样式枚举与设置（`Sources/ReferenceCore/LockMusicState.swift`、`SettingsView.swift`、`SettingsLocalization.swift`）

- `LockGlassStyle`：`glass / clear / frosted`（顺序同原版），默认 `.glass`。
- 设置页锁屏卡片新增三档：**玻璃 / 透明 / 磨砂**（`Glass / Clear / Frosted`）。
- 修复上一版 `choices("lockGlassStyle", …, [("Clear",""),("Glass","")])` 的**两个选项都写空值**缺陷：这条设置此前实际不生效，是用户"实现没落地"的直接原因。
- 存档兼容：无键 → 原版默认 `glass`；空字符串（旧两档行写出的值，当时固定渲染 clear）→ `clear`，保持用户当前看到的观感；其它未知值 → `glass`。

### 2. 材质（`Sources/Valora/LockMusicView.swift`）

| 样式 | 实现 |
|---|---|
| 玻璃 `glass` | `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))` |
| 透明 `clear` | `.glassEffect(.clear, in: 同上)` |
| 磨砂 `frosted` | `LockFrostedBackground`（`NSVisualEffectView` `.hudWindow` + `behindWindow` + `active` + `emphasized`）＋ 0.5pt/15% 白细边 |

- 圆角统一取反编译 macOS 26+ 分支的 **30**（旧 frosted 用 28）。
- 内容在玻璃**内部**（`glassEffect` 满足 Apple `contentView` 契约），不再用"背景视图叠在内容后面"的做法；卡片宽度仍先固定 345，玻璃不改布局。
- 移除了 `.clear` 那版用的 `.ultraThinMaterial` 与整树 `.colorScheme(.dark)` 里对材质的污染；深色环境只用于玻璃自身的明暗。
- 未改：卡片 345、面板 385×325、顶部独占 Space、锁定/解锁动画链、V0040 总开关与两条提示音、耳机、普通刘海播放器、歌词、日历、权限。

### 3. 预览用材质覆盖（`LockCardPreview.swift`）

`VALORA_LOCK_GLASS_STYLE=glass|clear|frosted` 只在 `--lock-card-preview` 检查路径生效，不写用户偏好。

## 三、验证

- `swift test --filter "LockMusicStateTests|LockCardAppearanceTests|LockMusicCoordinatorTests"`：14 + 4 + 31 = **49 项通过**（含新增 `glass/clear/frosted` 往返、空值兼容、枚举顺序断言）。
- `scripts/build.sh` release 构建 + 打包通过，`codesign --verify --strict --deep` 通过。
- 桌面 `--lock-card-preview` 单次最小检查（非循环、非压力）截图三张，均在真实壁纸上确认材质可渲染：
  - `docs/verification/lock-glass-styles-v0050/{clear,glass,frosted}.png`
  - clear：壁纸可透出、系统自带亮边轮廓（正是用户说的"透明但要线条轮廓"）；
  - glass：更深、更实的 Liquid Glass；
  - frosted：`.hudWindow` 深灰模糊 + 白细边。
- 候选：`/private/tmp/valora-v0050-lock-glass-styles-candidate/Valora.app`
  - binary SHA-256 `ee5f20daeb6a85ac014a184ed0a7db0ed9e3f4e2235d8db3572a9afe44b6bf7a`
  - 未覆盖 `dist`，未退出/替换用户正在运行的 v0049 实例（预览实例每次截屏后即退出）。

## 四、仍待实机确认

1. **真实锁屏合成**：桌面预览只能证明材质能画出来，登录界面/独占 Space 下的最终观感仍需用户锁一次确认。
2. **私有 `variant` 2/5**：公开 API 无法指定；若真实锁屏上仍偏"乳白"，剩余可查方向是面板形态（原版是整屏 `LockPanel`，我们仍是 385×325 小面板）与 `tintColor`，不继续盲调私有值。
3. **近白壁纸分支**：`_isWallpaperNearlyWhite` 的等价输入（读桌面壁纸亮度）仍未实现，因此固定走深色墨；未读用户壁纸。
4. 桌面预览中的具体壁纸颜色不代表锁屏背景。
