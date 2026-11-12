# 锁屏歌词：完全输入去重（2026-11-09）

分支：`codex/lock-screen-idle-cpu`。保留 build47 的未提交诊断/进度隔离/锁屏改动；未提交或推送 Git，未合并 main。

## 一、实测依据

build47 两轮诊断（开/关歌词）已证明：开歌词时单实例、无 fallback、图片未逐帧重建；lock native 在无切句窗口约 4.31 apply/s、34.14 update/draw/s，切句窗口 apply 约 10.22/s。这个数量包含外壳换句动画引起的重复 `NativeLyricsRowHost.updateNSView`，但不是所有 draw 都是重复（4Hz anchor 与 30Hz clock 是不同输入）。

## 二、修改

### 1. 完整输入 key

在 `LyricsRowExperiment` 的原生适配层增加 `NativeLyricsAppliedKey`，覆盖：

- `identity` + `contentRevision`
- `elapsed` / `sampledAt` / `rate` / `playing` / `duration`
- `width` / `rowHeight` / `verticalOffset`
- `accent` / `textKern` / `textBackend` / `switchAnimation` / `reduceMotion`
- `active`
- host identity / host generation
- `failRender`

完整 timeline 不用每帧深比较；`AppModel.lyrics` 赋值边界维护单调 `lyricsRevision`，同 identity 的内容/词时序替换会增加 revision。初挂、同曲重挂、active 恢复、host generation 变化、失败恢复都使 key 变化。

### 2. 适配层去重

`NativeLyricsRowHost` 仍每次 `wire` 当前 host/generation，保证 callbacks 不陈旧；然后比较 key：

- key 相同：记录一次 apply 请求和 skipped，不执行 `setActive/apply`；
- key 不同：执行原有 `setActive/apply`；
- 外壳的 offset/opacity 仍由 SwiftUI 0.2s 60Hz 动画驱动，不改变时序；
- native clock 仍 30Hz，不合并真实 4Hz anchor；
- 不改共享 Timer、CA 事务算法、解析器、玻璃/音频/屏幕监测。

### 3. 诊断修正

`NativeLyricsRowView.clockTickCount` 现在实际递增；新增 `applyRequestCount` / `applySkippedCount`，诊断 JSONL 区分 apply 请求、实际执行、相同输入跳过。诊断仍默认关闭、限时 12 分钟/512KiB、弱引用、无歌词文本。

## 三、验证

实验构建定向测试：

- `LyricsRowExperimentHostingTests` 的重复外壳输入/同 identity 替换/新 anchor 用例通过；
- 原有歌词 hosting/transition/空行/锁屏 active/进度隔离/waveform 自动恢复相邻回归通过；
- 总执行 102 项，1 项按既有条件跳过，0 失败。

普通无实验 Release 构建成功，二进制中诊断环境变量字符串不存在。未做真实锁屏 CPU/压力/批量闪窗/真实媒体操作。

## 四、候选

- `/private/tmp/valora-lyrics-apply-dedupe-20261109/Valora.app`
- `1.0.3 (48)`
- binary SHA-256：`a7c3ea539f9677ef30d89be0079e8a0bfba6a351ae9ba8cd65bf1b34d8b2b5b8`
- strict/deep 签名通过
- build47 已正常退出，当前唯一 build48 实例 PID `81766`（默认未带诊断环境）
- build47 保留在 `/private/tmp/valora-lock-lyrics-diagnostics-20261109/Valora.app`

## 五、未验 / 风险

- 真实锁屏下有歌词 CPU 的实际降幅仍需 Codex 用同一 build48 开诊断环境、用户开/关歌词各锁约 1 分钟对照；本批只去掉有证据的相同输入重复 apply，不宣称已经解决全部 7–8%。
- 真实高亮 mask/CA 成本、切句图片构建和 30Hz clock 仍在；4Hz anchor 与 30Hz clock 未合并。
- 若真实内容替换未经过 AppModel.lyrics 赋值边界，revision 可能不更新；当前生产路径已覆盖，未覆盖的外部注入需单独验证。
