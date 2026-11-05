# V0090 收回歌词折叠，恢复原有音量展开

执行：现有 OpenCode 会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`，按 `v0090-remove-lyrics-fold-restore-volume.md` 限定回退。
未整库 reset、未回退 `d1d5299`，只做有证据的逐处回退；未 Git 提交/推送、未安装发布、归档只读。

## 一、恢复基线（先从历史核对，不是凭注释）

引入歌词折叠前，用户认可的音量路径是：

| 项 | 证据 | 内容 |
|---|---|---|
| 音量区渲染 | V0072/V0073 会话源码 | `MusicPlayerContent` 内 `if showsVolume { OutputVolumeView(model:).padding(.horizontal,8).frame(height:24).transition(.opacity.combined(with:.offset(y:-6))) }`，**条件渲染，无固定槽、无外置块** |
| 入口 | 同上 | 控制行右侧输出按钮 `showsVolume.toggle()` + `spring(duration:0.45,bounce:0.1)`，锁屏绑 `coordinator.showsVolume` |
| 卡片锚定 | V0085 起 | 面板固定高度 + 卡片顶对齐，音量/歌词只在下方增减（用户明确"点击音量往下延展是对的"） |
| 歌词位置 | V0070 | 卡片最下面，`CompactLyricsView` 原样（音符紧贴文字、整体居中），受全局 `showLyrics` 控制 |

本次即恢复到该组合，并删除此后为"折叠"新增的结构。

## 二、本次回退内容

1. **删除歌词折叠（全链）**
   - `LockMusicView`：删除 `lyricsFolded` 绑定、控制行左侧音符按钮、折叠条件分支；
   - `MusicPlayerContent`：删除 `lyricsToggle`、`lyricsFolded`；
   - `LockMusicCoordinator`：删除 `@Published lyricsFolded`；
   - `LockCardPreview`：删除折叠 `@State`；
   - `CompactLyricsView`：删除 `onIconTap`／`showsIcon`／`LyricsRowAccessibility`（只为折叠服务的分支），恢复 `accessibilityElement(children: .ignore)` 与内联音符。
2. **撤除仅为折叠返修的布局结构**
   - 删除 `LockCardSections`（把播放器固定成 134pt、`includesVolume=false` 外置音量、把音量行搬出播放器的那套结构）；
   - 删除其配套测试 `Tests/ValoraTests/LockMusicCardLayoutTests.swift`（引用该结构，已随结构一起移除）；
   - 恢复 `MusicPlayerContent` 内 `if showsVolume { … }` 的条件音量区（无 `includesVolume` 参数）。
3. **卡片结构回到"播放器 + 可选歌词"两层**
   ```swift
   VStack(spacing: 8) {
       MusicPlayerContent(..., showsVolume: $showsVolume)   // 音量在其内部，条件展开
       if showLyrics && model.lyrics.timeline != nil {
           CompactLyricsView(...).padding(.bottom, 4).transition(...)
       }
   }
   .padding(...).frame(width: 345)
   .background { LockGlassSurface(cornerRadius: 30) }        // 玻璃只做背景，尺寸随内容
   ```

## 三、保留（未动）

- 玻璃材质：`NSGlassEffectView` + 私有 `variant 5` + `darkAqua`；焦点策略（`canBecomeKey` + 激活）不变；
- 顶对齐的固定宿主：`LockCardLayout`（player 166 / volume 24+8 / lyric 32+8 / canvas 380，`cardTop = 屏高×0.21 + player + offset`，`panelOriginY = cardTop − canvas`，与展开状态无关）、`host.sizingOptions = []` + `setContentSize`；
- 首次点击可用（`acceptsFirstMouse`）；
- 锁屏空间/顶部锁解动画、锁屏三项设置（总开关 + 两条提示音）不变；不恢复模拟锁屏与玻璃选择；
- 歌词功能保留（底部、受 `showLyrics` 控制、同步/逐字行为不变）。

## 四、验证

只跑本次相关、无窗口用例（未全量、未跑会创建真实窗口的 MultiDisplay/Interaction 类、无截图循环/性能审计）：

```
swift test --filter "LockMusicCoordinatorTests|LockMusicStateTests|LockCardAppearanceTests|LockCardLayoutTests"
```

| 套件 | 数量 | 结果 |
|---|---|---|
| LockCardAppearanceTests | 4 | 通过 |
| LockMusicCoordinatorTests | 31 | 通过 |
| LockCardLayoutTests | 8 | 通过 |
| LockMusicStateTests | 13 | 通过 |
| 合计 | 56 | 0 失败 |

构建/打包/签名：

- 候选：`/private/tmp/valora-v0090-volume-restore-candidate/Valora.app`
- binary SHA-256：`3ddfb5091e5bf48467a60cbab8701588de77ec1faf087e047b0ac7f7e59cdec5`
- `codesign --verify --strict --deep` 通过；`dist/Valora.app` 未动（仍 2026-11-04 09:16）

## 五、单实例替换（按 AGENTS 最新要求）

1. `pkill -f "MacOS/Valora"` → 复查 `grep -c '[M]acOS/Valora$'` = **0**（确认旧进程全部退出）；
2. `open -n /private/tmp/valora-v0090-volume-restore-candidate/Valora.app`；
3. 复查：仅 **1** 个进程，路径为 `/private/tmp/valora-v0090-volume-restore-candidate/Valora.app/Contents/MacOS/Valora`（PID 9836）；
4. 只读窗口元数据确认该实例已建立刘海窗口（`Valora` 624×320 @ x=2376, y=0），未截屏、未操作播放/音量/设备/锁屏。

替换过程中一次误判：早先用 `ps -Ao pid,etime,command` + `$2` 过滤，把 `etime` 当路径导致"未启动"的错误结论，并因此多起了一份；已全部 `pkill` 后重新单实例启动，现状态为 1 个正确路径的进程。

## 六、仍待真实验证（不冒称）

1. **真实锁屏下音量展开是否只向下、顶部与已有内容不动**：无窗口测试只能证明算术与约束，不能证明 WindowServer/玻璃合成结果；
2. **卡仍可能遮挡登录头像**：21% 是原版取值，不是 macOS 提供的头像安全边界；本次未实测边界，也未用常驻空槽/整卡缩放/盲猜 Y 补偿去掩盖；
3. 折叠已移除，不再有"折叠后残留音符/空槽"的问题；歌词仅在有效歌词存在时出现在最底部。

## 七、后续修正（V0091）：卡片整体偏高

**现象**：用户指出锁屏卡整体位置偏高。

**原因**：V0090 交付后，布局模型改成"把**完全展开态**的底边压在 21% 参考线上"（`cardTop = loginSafeBottom + maxCardHeight`）。这样收起态底边就被抬高 `maxCardHeight − playerHeight = 240 − 164 = 76pt`，即整卡上移 76pt。

**修正**：恢复按**收起态**锚定 —— 收起卡的底边回到原来的 21% 线上：

```swift
cardTop = loginSafeBottom + playerHeight
panelOriginY = cardTop − canvasHeight
```

- `playerHeight = 164`、`volumeBlock = 32`、`lyricBlock = 44`、`maxCardHeight = 240`（宿主窗口高）；
- 屏幕高 1117 时：收起卡底边 = 234.57（原位置），顶边 = 398.57；完全展开底边 = 158.57。

**已知取舍（如实记录，不做补偿）**：完全展开（音量+歌词）会比收起态低 76pt，即越过 21% 这条参考线；21% 是原版取值，**不是** macOS 提供的头像安全边界，本次未实测登录用户区边界，也没有用常驻空槽 / 整卡缩放 / 盲猜 Y 补偿去掩盖。

**测试**：`LockCardLayoutTests` 更新为 9 项（收起态位置、展开越过参考线的幅度、四态相对关系、宿主窗口高、offset 平移、短屏冲突上报），连同协调器 31 + 状态 13 + 外观 4 = **57 项通过**。

**候选（已单实例替换）**：`/private/tmp/valora-v0091-position-restore-candidate`，binary SHA-256 `1964c0a52e11d08de883be7f583020881d16b3c875608d49ccc56298242affbd`，签名通过；先 pkill 至 0 → 启动 → 复查仅 1 个进程、路径正确（PID 11944，刘海窗口 624×320 @ 2376,0）。真实锁屏观感仍待验。

## 八、V0092：抬高一点点，让音量展开不压头像

用户反馈：V0091 收起态位置可以，但**展开音量后压住登录头像**，要求"稍微往上点"。

**做法**：在收起态锚定上再加一个"音量净空" `volumeClearance = volumeBlock = 32pt`：

```swift
cardTop = loginSafeBottom + playerHeight + volumeClearance
```

屏幕高 1117 时：

| 状态 | 底边（自屏幕底） | 与 21% 参考线的关系 |
|---|---|---|
| 收起 | 266.57 | 高 32pt |
| **展开音量** | **234.57** | **正好压线（不压头像）** |
| 展开歌词 | 222.57 | 低 12pt |
| 音量+歌词 | 190.57 | 低 44pt |

- 只抬了 **32pt**（一个音量块），不是把整卡按最大展开抬高 76pt 那版；
- 音量展开是用户点名的场景，现在正好落在原 21% 线上；
- 仍如实记录：**歌词**展开（尤其音量+歌词）会比参考线低 12–44pt，21% 不是 macOS 提供的头像安全边界，本次未实测；不用空槽/整卡缩放/盲猜 Y 补偿掩盖。

**测试**：布局 9（改为"音量展开压线"+"完全展开只低一个歌词块"）+ 协调器 31 + 状态 13 + 外观 4 = **57 项通过**。

**候选（已单实例替换）**：`/private/tmp/valora-v0092-avatar-clearance-candidate`，binary SHA-256 `e863528c5b8dbe9e1894b0a40741a5dcb0b8de2f585cf0493446814990aa1f8c`，签名通过；pkill 至 0 → 启动 → 复查仅 1 进程、路径正确（PID 13474）。
