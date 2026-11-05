# V0096-R2：外接上移分支未接入生产（限定修复）

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`。只接通生产定位；未改比例、未加 Y 补偿、未动动画/玻璃/音量/歌词/两行监控/图标。未 Git 提交。

## 一、真实原因（不是"上移不够"）

独立验收已定位：`Sources/Valora/LockMusicCoordinator.place()` 构造 `LockCardLayout` 时**从未传 `reserveFullExpansion`**，默认 `false`；全仓库生产代码没有任何 `reserveFullExpansion:` 调用。R1 的 0.30 只存在于纯模型测试，实际窗口一直走内置 0.21 公式 —— 所以"换包了"和"新定位生效"是两件不同的事，R1 报告把两者混同，已在此更正（原称上移 97.2pt 的说法作废）。

新增生产级回归 `testLockTargetOwnsOverlayMusicAndDeviceFramesAcrossClamshellChange` 的实际断言在修复前失败：外接 `minY 300 / H 1080` 时 `panel.frame.minY` 实测 **482.8**，预期 **624**；内置 190.57 通过。

## 二、最小修复

```swift
let layout = LockCardLayout(screenMinY: frame.minY,
                            screenHeight: frame.height,
                            verticalOffset: model.settings.lockPreferences.offset,
                            reserveFullExpansion: !(target?.isBuiltIn ?? false))
```

- 用**实际选定的 target** 决定：外接 `isBuiltIn == false` → 预留全展开（0.30）；内置 → 保持 21% 原锚定；
- 目标未知（`target == nil`）时按"预留"处理，避免在识别不到屏幕时静默套用内置锚定；
- 比例、卡高（240）、正常歌词高（208）、顶锚与所有 UI/动画均未改。

## 三、数值（1080pt 外接，相对该屏自身原点）

| | 修复前（实际生产） | 修复后 |
|---|---|---|
| 顶边 | 422.8 | **564** |
| 正常歌词底边 | 216.8 | **356** |
| 全开（音量+歌词）底边 | 182.8 | **324** |
| 整卡上移 | — | **141.2pt** |

内置屏（1117pt）位置保持 `190.57` 不变（测试通过）。绝对坐标一律加目标屏自身 `minY`（负原点同样平移），不使用固定像素偏移。

## 四、定向验证（无窗口）

| 套件 | 数量 | 结果 |
|---|---|---|
| `LockMusicCoordinatorTests`（含新增真实 `panel.frame.minY == 624` 断言） | 32 | 通过 |
| `LockCardLayoutTests` | 13 | 通过 |
| `MusicDisplayPolicyTests` | 7 | 通过 |
| `LockLyricsTrackChangeTests` | 8 | 通过 |
| `IndependentLyricsDeadlineTests` | 2 | 通过 |
| 合计 | **62** | 0 失败 |

未跑全量、未闪窗/截图/性能，未真实合盖或操作锁屏/媒体/权限/分辨率。

## 五、构建 / 单实例替换

- 候选：`/private/tmp/valora-v0096-r2-layout-wired-candidate/Valora.app`
- binary SHA-256：`ce2e91bb9276efb720d41cfd6df8e64d2b14b78b81eac75f3780f9dd0d594914`
- `codesign --verify --strict --deep` 通过；`dist/Valora.app` 未动
- 替换：pkill 至 0 → `open -n` → 复查**仅 1 个进程**，路径 `/private/tmp/valora-v0096-r2-layout-wired-candidate/Valora.app/Contents/MacOS/Valora`（PID 78410）

## 六、待真实验证

合盖外接屏下卡片是否真的上移到位、是否仍遮头像，需用户一次实测；本轮只证明**生产调用链已接通**且实际窗口 Y 与模型一致，不写"永不遮头像"这类保证。
