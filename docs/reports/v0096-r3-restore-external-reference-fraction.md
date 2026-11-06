# V0096-R3：保留外接接线，参考比例恢复 21%

执行：现有会话 `ses_e5f5da1c5ffesaPdioiEijQ5HM`。用户实测 R2 过高，确认"保留正确外接接线、只把 0.30 恢复 21%"，**不是**回退到漏传参数版。未改选屏、形态跟随、窗口高度、内容、字号、动画、音量/歌词、玻璃、Space。未 Git 提交。

## 一、唯一产品调整

- `LockCardLayout.externalReserveFraction`: **0.30 → 0.21**（注释随之更正）；
- **保留**生产接线：
  ```swift
  place(): reserveFullExpansion: !(target?.isBuiltIn ?? false)
  ```
  外接仍按最大展开（`maxCardHeight = 240`）预留，内置仍 `player 164 + volume 32`；
- 未新增偏移项/设置，未用 0.24/0.25 之类折中值。

## 二、坐标（1080pt 外接，相对该屏自身原点）

| | 漏接线版（最初） | R2（0.30） | **R3（0.21 + 接线）** |
|---|---|---|---|
| 顶边 | 422.8 | 564 | **466.8** |
| 正常歌词底边 | 216.8 | 356 | **258.8** |
| 全开底边 | 182.8 | 324 | **226.8** |

- 相对 R2 整体下移 **97.2pt**；比最初漏接线版仍上移 **44pt**（因为最大展开预留还在）；
- 内置屏（1117pt，原点 0）：`panel.minY = 190.57` 不变；
- 生产协调器注入外接 `frame.minY 300 / H 1080` 的实际断言：`panel.frame.minY = 526.8`（= 300 + 0.21×1080）。用例预期已更新并注明"用户新决定"，真实窗口 Y 断言保留、未删除。

## 三、定向验证（无窗口）

| 套件 | 数量 | 结果 |
|---|---|---|
| `LockMusicCoordinatorTests`（真实 `panel.frame.minY == 526.8`、内置 190.57） | 32 | 通过 |
| `LockCardLayoutTests`（外接 466.8 / 258.8 / 226.8、负原点平移、四态同顶边） | 13 | 通过 |
| `MusicDisplayPolicyTests` | 7 | 通过 |
| `LockLyricsTrackChangeTests` | 8 | 通过 |
| `IndependentLyricsDeadlineTests` | 2 | 通过 |
| 合计 | **62** | 0 失败 |

21% 与 30% 都只是产品位置取值，**都不是** macOS 提供的头像边界；代码注释与报告均已如实标注。未跑全量、未闪窗/性能，未真实合盖或操作锁屏/媒体/权限。

## 四、构建 / 单实例替换

- 候选：`/private/tmp/valora-v0096-r3-reference-fraction-candidate/Valora.app`
- binary SHA-256：`e04d497ca173133937587f54581b03915113296aa9a9508b140f31a1724b7785`
- `codesign --verify --strict --deep` 通过；`dist/Valora.app` 未动
- 替换：pkill 至 0 → `open -n` → 复查**仅 1 个进程**，路径 `/private/tmp/valora-v0096-r3-reference-fraction-candidate/Valora.app/Contents/MacOS/Valora`（PID 81948）

## 五、待真实验证

合盖外接屏下的最终视觉（是否既不挡头像、也不显得过高）由用户确认；本轮只证明外接分支仍接通、真实窗口 Y 与模型一致（526.8 / 190.57）。
