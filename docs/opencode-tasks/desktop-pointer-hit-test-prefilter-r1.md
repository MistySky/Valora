# 鼠标命中预筛选 R1：非有限点回退

读取原任务 `desktop-pointer-hit-test-prefilter.md`。Codex 独立新增 `IndependentNotchPrefilterTests`：`(+∞,10)`、`(-∞,10)`、`(NaN,1000)`、`(1000,NaN)` 均未按任务要求进入原精确路径（4 条断言失败），日志 `/private/tmp/valora-pointer-independent-20261109.log`。原报告声称所有非有限点比较都不成立，但 ±∞ 可以直接通过 `<`/`>`，NaN 的另一坐标也可能触发排除。

在 `containsMouse(localPoint:size:contour:)` 的预筛选前明确检查 **x、y 均 finite**；非有限则直接 `preciseContainsMouse`。保持非正/非有限 scale 和异常形状回退原路径，边界规则与正常路径不变。不降低频率、不改其他业务。保留独立测试断言，跑 `IndependentNotchPrefilterTests|NotchHitTestPrefilterTests` 和必要相邻逻辑测试；Release 不能带诊断计数。报告 `docs/reports/desktop-pointer-hit-test-prefilter-r1.md`，不启动/替换 App、不提交。
