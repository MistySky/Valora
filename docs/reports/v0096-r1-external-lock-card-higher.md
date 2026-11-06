# V0096-R1：外接屏锁屏音乐卡显著上移

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`。只改**外接/合盖屏**的初始位置；内置屏、卡片内容字号、玻璃、顶部锁解动画、Space 迁移、音量与歌词布局、V0095/R1 歌词修复、顶部两行对齐与用户 V 图标均未动。未 Git 提交。

## 一、实测反馈与依据

- 用户合盖实测：V0096 后**正常歌词态就挡住半个头像**，要求"明显上移"。
- 只读确认外接 U2701B 当前模式逻辑 **1920×1080 pt**（pixel 3840×2160，backing 2x，60Hz），开盖样本 NSframe `{{1728,37},{1920,1080}}`；该样本同时存在 active 内置屏，**不是**合盖时刻的头像边界记录，不能当作用户环境取证。
- 上一版算法（外接沿用 21%）在 1080pt 上的实际值：cardTop=466.8；正常歌词态（高 208）bottom=258.8；全开（240）bottom=226.8 —— 与"遮半个头像"一致，说明 21% 不是可用的登录区避让标准。

## 二、本轮调整

- `LockCardLayout` 新增 `externalReserveFraction = 0.30`，**仅当 `reserveFullExpansion`（外接/合盖目标）时**用 30% 作为布局保留基线；内置屏继续用 21% + 原音量预留（`loginSafeFraction` 未改，内置屏不会漂移）。
- 新公式：`reservedBottom = minY + H × (外接 ? 0.30 : 0.21) + offset`；`cardTop = reservedBottom + (外接 ? maxCardHeight : playerHeight + volumeClearance)`。
- 1080pt 外接屏（minY=0）结果：

| 状态 | 卡片高 | 底边 | 顶边 |
|---|---|---|---|
| 收起 | 164 | 400 | 564 |
| 正常歌词 | 208 | **356**（较上版 258.8 上移 **97.2pt**） | 564 |
| 音量展开 | 196 | 368 | 564 |
| 全开（音量+歌词） | 240 | **324** | 564 |

- 顶边固定：音量/歌词增减只改底边，不会重新居中或带动标题/封面/控件；不缩卡、不缩字号、不造空槽。
- 所有坐标都按目标屏自身 frame（含负原点）计算，不使用固定像素偏移。30% 是**产品位置调整**，不是 macOS 提供的头像 bounds，也不作为"永不遮挡"的保证，代码注释同样如实写法。

## 三、定向验证（无窗口）

| 套件 | 数量 | 结果 |
|---|---|---|
| `LockCardLayoutTests` | 13 | 通过（含外接 1080 的 324/564/356 数值、内置仍 21% 锚定、负原点平移 564/324） |
| `LockMusicCoordinatorTests` | 32 | 通过（合盖目标切换、面板/信息面板跟随目标屏） |
| `MusicDisplayPolicyTests` | 7 | 通过（锁屏外形跟随强制刘海、物理刘海仍硬件） |
| `LockLyricsTrackChangeTests` | 8 | 通过（V0095/R1 回归） |
| `IndependentLyricsDeadlineTests` | 2 | 通过 |
| 合计 | **62** | 0 失败 |

未跑全量、未闪窗/截图/性能，未真实合盖、未操作锁屏/媒体/权限/分辨率。

## 四、构建 / 单实例替换

- 候选：`/private/tmp/valora-v0096-r1-external-higher-candidate/Valora.app`
- binary SHA-256：`6c05304a61a562764727c384ebf1b0eae2b5c6cbc0a164407ff31a1c36aaee28`
- `codesign --verify --strict --deep` 通过；`dist/Valora.app` 未动
- 替换：pkill 至 0 → `open -n` → 复查**仅 1 个进程**，路径 `/private/tmp/valora-v0096-r1-external-higher-candidate/Valora.app/Contents/MacOS/Valora`（PID 76080）

## 五、待真实验证

1. 合盖外接屏下正常歌词态是否已明显让开头像（若仍挡，需要继续上移——请给方向，不再凭猜测加比例）；
2. 全开（音量+歌词）在外接屏是否仍完整可见且不越出屏幕顶部；
3. 开盖回内置屏位置是否保持原样、合盖/拔插切换后是否重算正确。
