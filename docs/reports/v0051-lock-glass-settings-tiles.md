# V0051 锁屏玻璃设置：还原参考页的两块材质预览卡片

2026-11-03，用户提供原版设置截图（Now Playing 卡片里的 Glass / Clear 两块预览卡片）并指出"按 archive 已实现的那版来"。
V0050 的方向（真原生 Liquid Glass 材质）保留，本批只修**设置呈现**和**入口数量**。

## 一、参考实现（archive 源码）

`/Users/wangqing/code/alcove-revival-archive/Sources/AlcoveRevival/SettingsView.swift`：

```swift
SettingsCard {
    toggle("Now Playing", "allowNowPlayingWidgetWhenLocked", true, badge: .nowPlaying)
    if draft.value("allowNowPlayingWidgetWhenLocked", true) {
        SettingsRule()
        choices("nowPlayingStyle", "Glass", [("Glass", ""), ("Clear", "")], style: "glass", height: 46)
        SettingsRule()
        slider("Idle duration", ...) ...
    }
}
```

`SettingsControls.swift` 的 `style == "glass"` 画法（就是截图里那两块）：

```swift
RoundedRectangle(cornerRadius: 15)
    .fill(.gray.opacity(choice.title == "Glass" ? 0.6 : 0.2))
    .overlay(RoundedRectangle(cornerRadius: 15)
        .stroke(choice.title == "Glass" ? .white.opacity(0.3) : .black.opacity(0.6), lineWidth: 1))
    .padding(.horizontal, 13).padding(.vertical, 10)
    .background(Color(white: 0.26), in: RoundedRectangle(cornerRadius: 11))
```

Valora 的 `SettingsControls.swift` 里这段其实早就迁进来了，但锁屏页没用它 —— 这是"还原得不像"的直接原因。

## 二、本批改动

1. `Sources/Valora/SettingsView.swift`
   - 锁屏页样式行改成参考页的画法：`SettingsChoice(title:style:"glass", value:)` × 2，`tileHeight: 46`。
   - 选项值写真实 raw value `glass` / `clear`（V0049 的 `("Clear",""),("Glass","")` 两个都写空串，等于设置不生效）。
2. `Sources/ReferenceCore/LockMusicState.swift`
   - `LockGlassStyle` 回到参考页的两项 `glass` / `clear`，默认 `glass`（原版注册默认）。
   - 旧值兼容：无键 → `glass`；空串（旧两档行写出的，当时固定渲染 clear）→ `clear`；`frosted`（macOS 26 以下旧分支名，参考页在 macOS 26+ 不提供）→ `glass`；其它未知 → `glass`。
3. `Sources/Valora/LockMusicView.swift`
   - 只保留两种材质：`glassEffect(.regular)` / `glassEffect(.clear)`，圆角 30。
   - 删除 `LockFrostedBackground.swift`（`.hudWindow` 只属于旧系统分支，本产品 macOS 27-only，保留即死代码；文件仍在提交 d1d5299 里）。
4. `Sources/Valora/AppDelegate.swift`
   - 新增 QA 用 `--settings --settings-page "<页面原始名>"`，只影响启动时打开的页面，不写偏好。

未改：卡片 345、面板 385×325、顶部独占 Space、锁解动画、V0040 三项设置与模块总开关、耳机、普通刘海播放器、歌词、日历。

## 三、验证

- `swift test --filter "LockMusicStateTests|LockCardAppearanceTests|LockMusicCoordinatorTests"`：14 + 4 + 31 = **49 项通过**。
- `scripts/build.sh` release 构建 + 打包 + `codesign --verify --strict --deep` 通过。
- 设置页实机截图（单次，非循环）：`docs/verification/lock-glass-settings-v0051/lock-page.png`
  - 卡片：启用锁定屏幕 / 锁定时播放提示音 / 解锁时播放提示音 / **玻璃 ・ 透明** 两块材质预览；
  - 选中态是系统强调色描边，"玻璃"处显示浅灰内块+白边，"透明"处显示深灰内块+黑边，与参考截图一致。
- 候选：`/private/tmp/valora-v0051-lock-glass-tiles-candidate/Valora.app`
  - binary SHA-256 `6ed7b91a31ce4786aa2acc7a5ba72a2c2b36f21f9cbb5a7828b496aa7f7ebcca`
  - 已切换为用户当前运行实例（v0050 已退出）。

## 四、仍待实机确认

- 真实锁屏下两种玻璃的合成效果（桌面预览与设置页只证明材质能画、设置能落）。
- 私有 `variant 2/5` 无公开 API；若实机仍偏乳白，下一步只在"面板形态/整屏宿主"上做单变量验证。
- 近白壁纸的墨色反转分支（`_isWallpaperNearlyWhite`）未实现，未读取用户壁纸。
