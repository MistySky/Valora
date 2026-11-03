> 历史核查记录（V0036 实施前）。当前实现与验证见
> `docs/reports/v0036-lock-screen-selected-migration.md`；本文件保留为
> 迁移前缺口证据，不表示锁屏仍是占位页。

# 锁屏迁移前核查

本次只读核查来源、更新研究记录，不触发系统锁屏，不迁入生产实现，不投递新任务。

## 当前 Valora

`Sources/Valora/SettingsView.swift` 的 `.lockScreen` 仍路由 `placeholderPage(.lockScreen)`；当前不是已有锁屏后端待调整。

## 可直接参考的成熟复刻

- `Sources/AlcoveRevival/LockMusicCoordinator.swift`：锁定/解锁、睡眠/唤醒与屏幕事件，独立非激活 NSPanel，既有音乐组件复用、空闲隐藏、生命周期。
- `LockFrostedBackground.swift`：材质。
- `LockInformationView.swift`：信息组件。不能由复刻存在自动推导本项目全部启用。
- `Sources/NativeBridge` 的 ARLockPresentationSpace：锁屏 Space 挂载需迁移前另核接口与资源释放。

来源目录均为 `/Users/wangqing/code/alcove-revival-archive`，只读。

## 原版证据与限制

`reverse-engineering/lock-screen-music/依据与边界.txt` 区分了原版 LockPanel、345pt 音乐卡、部分动画和位置常数，与复刻材质/部分动画策略。复刻明确仍需真实登录窗口显示点击、时钟头像避让和锁屏音乐来源更新验证；不能把其 fake/预览结论视作实机验收。

旧归档 `lock-screen-personal-plan.json` 是旧项目产品规划，不自动成为 Valora 的已确认配置。

## 建议的最小接入范围

先迁移音乐锁屏纵向链路：总开关、已存在的音乐内容和原版对应材质、锁定/解锁与睡眠清理、关闭后注销监听并停止专用任务。先不恢复电池、天气、专注等未启用模块，不自动加 keepAwake 或播放锁解声音。设置沿现有 Alcove 风格，具体保留项先交用户确认。实际锁屏由用户在合适时机操作；远程期间只做无界面注入状态测试与必要构建。
