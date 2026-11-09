# 桌面鼠标移动：去重窗口鼠标接收状态

用户允许继续优化，指定由新 OC 会话 GLM-5.3-Flash 执行，Codex 决定方案与独立验收。沿用当前分支与现有改动，读 AGENTS.md（用户已覆盖旧会话/模型条款）、`desktop-pointer-hit-test-prefilter-independent.md`。

## 实测证据与边界

2026-11-09 build34、用户确认暂停播放并在远离刘海位置晃动鼠标约 30 秒：13 次采样均值 14.4%、范围 8.5–20.2%。随后用户被要求静止约 20 秒：11 次均值 0.4%、范围 0.1–0.9%。这是一次短时对照，不可推广为稳定 CPU 承诺。高值触发栈 `/private/tmp/valora-build34-paused-moving-20261109.txt` 有 `WindowCoordinator.trackMouse` → `NSWindow.setIgnoresMouseEvents` → `_setEventMask` → `SLSSetWindowEventMask`；也有系统事件处理和音频输出查询，不能按样本数断言各自 CPU 占比。

## Codex 指定最小修改

`WindowCoordinator.trackMouse(at:)` 对每个鼠标事件无条件执行 `record.panel.ignoresMouseEvents = !inside`，即便真实属性早已是该值。改为**读取该 NSWindow 的当前真实属性，只有与目标值不同时才赋值**；锁屏分支若同样无条件赋 true，可以用相同幂等辅助，但不得改变锁屏交互。不能使用未经同步的自行缓存作为唯一判断，其他位置会改这个属性；需要容忍外部/可见性路径修改后下一事件恢复正确状态。

保留每次 mouseMoved / leftMouseDragged 的检测、不降低频率、不延迟 hover、不更改进入/退出/激活/拖动/锁屏/多屏/形状路径判断、不更换事件监听 API。保留上次保守范围预筛选和所有歌词实验。用户在意真实悬停体验，不得用固定间隔节流或扩大/缩小命中范围。

## 验证

- 添加一次性隔离窗口或可注入面板测试，验证真实目标状态不变时不触发 setter；进入与离开时分别立即赋正确值；其他路径先改变属性后下一次鼠标事件仍能纠正；两个屏幕的状态独立；drag、pointerInteractionActive、隐藏、锁屏分支保持原本语义。可通过可注入 setter/最小 debug 计数观测实际调用，不能只测试与实现相同的纯布尔表达式。
- 复跑预筛选独立回归、多屏/悬停/交互、锁屏相邻定向测试，不删改断言。禁止压力/大量重复调用/批量闪窗，不能用循环压力基准冒称用户实测。
- 普通/实验 Release 构建；报告代码位置、测试与构建数，真实抖动 CPU 与悬停体验仍未测，不能承诺降幅。明确系统全局事件接收本身可能还有成本，且这次采样不证明去重是全部成本。
- 写 `docs/reports/desktop-pointer-window-state-dedup.md`，完成后停止；不操作真实鼠标/播放、不启动或替换用户 App、不打包安装、不提交推送。
