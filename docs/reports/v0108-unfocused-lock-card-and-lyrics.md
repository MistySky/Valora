# V0108：锁屏卡失焦暗色 + 空歌词居中 + 解锁残留排查

执行：现有会话。用户确认“那个暗色的失焦好看很多”，并要求：无歌词时音符居中而不是靠左；解锁时中间音乐控制延迟消失。本批改了锁屏卡焦点与空歌词布局，并对解锁路径做了最小清理；**未改几何/动画节奏/歌词内容/音量/生命周期**，未 Git 提交。

## 一、失焦暗色（已改）

证据：用户认可的 `docs/verification/lock-glass-variant-v0056/dark-variant-desktop.png` 里菜单栏是“飞书”，说明当时 Valora **没有 key**，即失焦暗色；本批 harness 也测到 `NSGlassEffectView(darkAqua, variant5)` 非 key 时更接近该图。

- `LockMusicCoordinator.present()` 不再 `makeKey`/切 regular 激活策略；删除 `activateGlassSurface`/`deactivateGlassSurface` 与 `activationOwner`/`glassActivated`。
- 解锁/隐藏/stop 不再恢复激活策略，因此也不会出现“焦点交还”带来的视觉过渡。
- `LockCardPreviewController` 同样改为 `orderFrontRegardless()`，不再 `acquire`/`makeKeyAndOrderFront`；预览与真实锁屏保持同一失焦材质。
- 材质仍是 `NSGlassEffectView` + `.regular` + `.darkAqua` + variant5，未改。

## 二、空歌词音符居中（已改）

- `CompactLyricsView` 新增 `centersNoteWhenEmpty`（默认 false，刘海保持原样）。为 true 时，当前行不存在就只渲染音符本身，由外层 `.center` 对齐居中，不再带一段空白文本宽度。
- 锁屏卡 `LockMusicCard`：
  - `showLyrics && playing && timeline != nil` 才显示歌词行；**暂停时整行移除**（用户建议的“没播放把歌词拿掉”）。
  - 播放但当前行空缺时，`centersNoteWhenEmpty: true` 使音符居中。
  - 刘海紧凑/展开布局与暂停行为未改。

## 三、解锁时“中间音乐控制延迟消失”（部分处理，待确认）

代码核对：

- 解锁发生在 `.locked` 时，`beginUnlock` 已经立即 `visible=false / appeared=false / panel.orderOut / detach`，并取消 appearance/hide 任务；现有测试 `testUnlockShowsOpenGlyphThenRestoresNormalMusicBeforeBadgeHidden` 也断言卡片在解锁开始即移除。
- 本轮补上 `.neutralizing` 解锁分支的同样立即移除（此前该分支只 `forceHidden`，依赖 0.85s hide 任务），并随第一点删除了焦点交还路径——这两个都可能是“延迟消失”的来源。
- 但无法仅靠源码确认用户看到的是锁屏卡控制条、还是解锁后刘海中间恢复的播放/暂停按钮；后者在 0.8s 锁徽章收起后才恢复，属于现有解锁节奏，不是本批改动。

如果更新候选后仍有延迟，请给一段 3–5 秒解锁录屏（或说明是“卡片里的播放键”还是“刘海中间的播放键”），我再定向修，不再猜。

## 四、测试与构建

| 项 | 结果 |
|---|---|
| `LockMusicCoordinatorTests` | 32 通过 |
| `LockActivationOwnerTests` | 14 通过 |
| `LockLyricsTrackChangeTests` | 8 通过 |
| 合计 | **54 通过** |
| Debug / Release 编译 | 均通过 |

未跑全量、未做 UI 循环/性能测试。

## 五、候选

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0108-unfocused-lock-card-candidate/Valora.app` |
| 版本 / 构建号 | `1.0.0` / **17**（`Info.plist` 与 `build-verification.json` 一致） |
| binary SHA-256 | `0d29973aa4ffc85539c073c36c93d3e32b2f91be1f02468c292d50ab7092c463` |
| 签名 | `codesign --verify --strict --deep` 通过 |
| 启动 | 无旧实例 → 启动该候选 → 仅 1 个进程 PID 34854 |

说明：营销版本仍用默认 1.0.0；如果要作为 1.0.1 正式修复，请明确，我会用 `--version 1.0.1` 重新打包。未覆盖 `dist` 的 1.0.0、未安装、未 Git 提交。

## 六、待用户确认

1. 锁屏卡失焦材质是否就是你认可的那版（更接近 v0056 截图）。
2. 播放但无歌词行时音符是否居中；暂停时整行移除是否符合预期。
3. 解锁残留是否已消失；若没有，请给短录屏/说明是哪一个控制。

## 七、V0108-R1：暂停歌词行恢复（用户反馈）

用户实看后指出：暂停时把歌词行拿掉，卡片收缩/展开的缩放效果不如刘海屏。该建议（“没播放把歌词拿掉”）据此撤回。

- `LockMusicCard` 恢复为 `showLyrics && timeline != nil` 即显示歌词行，**暂停不再移除整行**；暂停时保持当前行，与刘海一致，不产生卡片高度变化。
- 保留 `centersNoteWhenEmpty`：播放/暂停时若当前没有歌词行，音符居中而不是靠左。
- 失焦暗色与解锁清理不变。

验证：`LockMusicCoordinatorTests` 32 + `LockActivationOwnerTests` 14 + `IndependentLockActivationLifetimeTests` 3 + `LockLyricsTrackChangeTests` 8 = **57 通过**；Debug/Release 编译通过。

新候选：

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0108-r1-lock-lyrics-pause-candidate/Valora.app` |
| 版本 / 构建号 | `1.0.0` / **18** |
| SHA-256 | `5ca9399493e057bc207282f9603c2d276b15497b7132d48bbdc19c2ed260c8f1` |
| 签名 | strict + deep 通过 |
| 替换 | 按 bundle id 正常退出 build17 → 0 → 启动 build18 → 仅 1 个进程 PID 36639 |

仍待确认：解锁“中间音乐控制”是否仍延迟；如仍有请给短录屏或说明是卡片内还是刘海中间的控制。

## 八、V0108-R2：保持张开，无歌词时音符居中（用户最终口径）

用户澄清：暂停时**保持歌词行张开**（不收缩）；只要歌词开关开着，即使没有歌词，也应在歌词行显示**居中的音乐小图标**，不是靠左。

- `LockMusicCard`：`showLyrics` 开着就挂载 `CompactLyricsView`（不再看 `playing` 或 `timeline`）；暂停时保持当前行，无歌词/无当前行时由 `centersNoteWhenEmpty` 只渲染居中音符。
- 歌词开关关闭时才移除整行；行出现/消失沿用 `ExpansionTiming.duration` 的收放 spring（接近刘海的展开节奏），不再裸布局跳变。
- 失焦暗色保持。

验证：57 项（协调器 32 + 焦点 14 + 独立焦点 3 + 歌词切换 8）通过；Debug/Release 编译通过。

新候选：

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0108-r2-lock-lyrics-centered-candidate/Valora.app` |
| 版本 / 构建号 | `1.0.0` / **19** |
| SHA-256 | `6e9929e8e8957ea7bb849d5a1e203b97f92faa9a1defe46f02d42eaaad42182c` |
| 签名 | strict + deep 通过 |
| 替换 | 按 bundle id 正常退出 build18 → 0 → 启动 build19 → 仅 1 个进程 PID 38768 |

解锁“中间音乐控制”延迟如仍存在，仍需短录屏/说明是哪一处控制。
