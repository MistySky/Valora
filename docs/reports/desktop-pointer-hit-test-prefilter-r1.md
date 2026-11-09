# 鼠标命中预筛选 R1：非有限点回退

执行：原 OpenCode 会话、原模型、分支 `codex/idle-cpu-optimization`。按 `docs/opencode-tasks/desktop-pointer-hit-test-prefilter-r1.md` 处理。未启动/替换 App、未控制鼠标/媒体、未打包提交。

## 一、根因

原实现只依赖“严格 `<`/`>` 在非有限点上不成立”，这不正确：

- `(+∞, 10)`：`x > maxX` 为真 → 被误排除；
- `(-∞, 10)`：`x < minX` 为真 → 被误排除；
- `(NaN, 1000)`：`y > maxY` 为真 → 即使 x 是 NaN 也会被误排除；
- `(1000, NaN)`：`x > maxX` 为真 → 同样被误排除。

Codex 独立用例 `IndependentNotchPrefilterTests` 的 4 条断言因此失败。

## 二、修复

在 `containsMouse(localPoint:size:contour:)` 进入范围判断**之前**显式检查坐标：

```swift
guard localPoint.x.isFinite, localPoint.y.isFinite else {
    return preciseContainsMouse(localPoint: localPoint, size: size, contour: contour)
}
```

- 非有限点直接走原 `NotchShape.path(...).contains`，不进入预判；
- 正常点、范围边界、严格越界规则完全不变；
- 点重载仍先做 `localPoint` 变换；非正/非有限 `scale` 继续走原精确路径；
- 异常形状（非有限/非正尺寸、负半径、超上限）继续返回 `nil` 回退；
- 未改频率、hover delay、展开/拖动/激活或多屏坐标变换；未改歌词/播放/音频/锁屏。

独立测试与自有测试均未修改、未删除、未放宽。

## 三、验证

| 项 | 结果 |
|---|---|
| `IndependentNotchPrefilterTests` | **1/1 通过**（含 ±∞、两个 NaN 坐标，均 `pathConstructions == 1`） |
| `NotchHitTestPrefilterTests` | **5/5 通过**（280 次原 path 对照、边界、异常输入、跳过 path 计数） |
| 多屏/交互/音乐/锁屏相邻组合 | **执行 88，通过 88，失败 0** |
| 普通 Release | 构建成功；`NotchHitTestDiagnostics` 符号 **0** |

## 四、未验 / 风险

- 真实 CPU 与悬停体感未在本轮重新测量；4 个非有限点属防御性输入，未在真实鼠标事件中出现。
- 未做压力/批量闪窗/真实鼠标抖动；未启动或替换运行版。

## 五、回退

仅新增上述 4 行 `guard`；回退即删除该 guard，恢复上一版行为。无其他依赖。

## 六、边界

未安装、未启动/替换 App、未操作鼠标/媒体、未打包提交；未改其他业务与歌词实验工作。
