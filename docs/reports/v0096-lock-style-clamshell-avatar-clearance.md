# V0096：合盖外接屏锁屏外形跟随强制刘海 + 音乐卡避让头像

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`。未回退 V0095/R1 歌词修复、V0094 传输与两行对齐、用户图标；未改锁屏动画/音量交互/玻璃材质/卡片内容字号。未 Git 提交。

## 一、用户已确认的两条

1. **选屏独立、外形跟随**：锁屏仍按 active/online 内置屏优先、合盖后回退主外接屏；**外形**在无物理刘海的锁屏目标上跟随现有 `forceSimulatedNotch`（on=模拟刘海几何/轮廓，off=胶囊），真实物理刘海仍用硬件几何。不新增开关。
2. **外接屏卡片不遮头像**：真实合盖时音乐卡挡住登录头像，需要按目标屏实际逻辑坐标与最大展开范围预留。

## 二、原实现与问题

- `LockDisplayPolicy.geometry(for:)` 固定传 `simulated: false`，锁屏目标即使勾选强制刘海也永远是胶囊；
- `NotchView.simulated` 在锁屏几何下恒为 false（`!usesLockGeometry && settings.forceSimulatedNotch`），`localSize` 还显式传 `presentationSize(..., simulated: false)` —— 三处都得改，否则只换了绘制路径、高度/顶部间距/命中范围仍是胶囊；
- `LockCardLayout.cardTop = 登录线 + playerHeight + volumeClearance(32)`，最大展开（音量+歌词）底边会比登录线低 44pt —— 在内置屏上是已认可位置，但在**较矮的外接屏**上就会压到头像。

## 三、修复

1. **统一外形来源**：`LockDisplayPolicy.geometry(for:simulated:)` 新增参数，只有 `safeAreaTop <= 0`（无物理刘海）时才把 `simulated` 传下去；`LockMusicCoordinator.place()` 用 `settings.forceSimulatedNotch` 计算锁屏几何，并新增订阅 `settings.$forceSimulatedNotch` → 重算当前锁目标（不改音乐选屏、不伪造 `hasPhysicalNotch`）。
2. **NotchView**：锁屏几何下 `simulated = forceSimulatedNotch && 无物理刘海`；`localSize` 由 `simulated: false` 改为传入该值，使高度/顶部间距/轮廓/命中范围同源。
3. **卡片避让**：`LockCardLayout` 增加 `reserveFullExpansion`；为真时 `cardTop = 登录线 + maxCardHeight`，四态底边都不越过登录线。协调器按目标屏决定：**内置屏保持已认可锚定**（音量展开正好压线），**外接/合盖屏启用完整预留**。所有状态仍只向下扩展，顶边固定，`panelOriginY = cardTop - canvasHeight` 与展开无关；坐标按目标屏自身 frame（含负原点）计算，不使用固定像素偏移、不缩放不缩字。
4. 登录线仍是 `21%` 这一**产品保留值**，并非 macOS 提供的头像 bounds——报告与代码注释都如实标注；本轮没有读取登录窗口内容或用户屏幕。

## 四、定向验证（无窗口）

| 套件 | 数量 | 结果 |
|---|---|---|
| `MusicDisplayPolicyTests`（新增锁屏外形用例） | 7 | 通过 |
| `LockCardLayoutTests`（新增外接预留/负原点用例） | 11 | 通过 |
| `LockMusicCoordinatorTests`（旧"忽略模拟开关"断言按新规则更新） | 32 | 通过 |
| `LockLyricsTrackChangeTests`（V0095/R1 回归） | 8 | 通过 |
| `IndependentLyricsDeadlineTests` | 2 | 通过 |
| 合计 | **60** | 0 失败 |

- 旧断言 `lock geometry must ignore the music simulation flag` 已按用户新决定改为：外接屏（无物理刘海）`forceSimulatedNotch=true` 时 `compact.height = 24`（模拟形），关闭后 `19.5`（胶囊）；改动原因写入测试注释。
- 新增策略用例同时验证：真实物理刘海在开关打开时仍是硬件几何。
- 新增布局用例验证：外接屏四态底边都 ≥ 登录线、`panelOriginY` 不随展开变化、负原点屏幕（`screenMinY = 300`）锚点按自身 frame 计算且宿主不越出屏幕。

未跑全量、未闪窗/截图/性能，未真实合盖或操作锁屏/媒体/权限。

## 五、构建 / 单实例替换

- 候选：`/private/tmp/valora-v0096-clamshell-lock-candidate/Valora.app`
- binary SHA-256：`da1e7951c610ef2620ec42d7c984a45b166789fd486e1cf98fc8989cd63e2804`
- `codesign --verify --strict --deep` 通过；`dist/Valora.app` 未动
- 替换：pkill 至 0 → `open -n` → 复查**仅 1 个进程**，路径 `/private/tmp/valora-v0096-clamshell-lock-candidate/Valora.app/Contents/MacOS/Valora`（PID 69032）

## 六、仍待真实验证

1. 真实合盖 + 外接屏下：强制模拟刘海开关切换后锁屏外形是否即时跟随（含顶部锁解 overlay 与普通面板 fallback 两条路径）；
2. 外接屏上音量+歌词全部展开时是否真的不遮头像——`21%` 仍是保留值，不是实测到的头像边界，需用户一次合盖锁屏查看；
3. 开盖切回内置屏时是否保持原已认可位置与动画。
