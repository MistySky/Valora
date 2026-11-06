# V0030 同轮补充 — 定向测试策略交付说明

任务：`docs/pi-tasks/v0030-supplement-targeted-test-policy.md`
SHA256：`c3e6125731d240e79079f2b4e3607bd54742233aa8f20b4853fa4dd73e02fbde`

这不是新功能或 V0030 主体重做。本补充只调整后续验证分工，**未修改生产代码、
测试断言、候选或 dist**。

## 当前状态

- V0030 主体成果保持：候选 `/private/tmp/valora-v0030-candidate`
- 候选 binary SHA256：`2fefb0f9c859ab490bf3835b5ad7e7a5aef142fa74565075b62de751457e6efa`
- 用户 `dist` 未覆盖：`19ba9a0f0cae669dcc32eb8f282750f9fd46a71a603d1bb2d01b9f872b0ffd9f`
- 无正在运行的全量测试；未启动新的重复全量测试
- 本补充没有产生需要重新构建或重新跑全量的源码变化

## 验证策略（本次采用）

1. 本补充无新代码；复用已完成的 V0030 定向结果和最终候选证据：
   - `DownloadMenuModelTests` 6/6
   - V0029-R2 storage/lock 定向回归保留
   - 真实 local Range `DownloadMenuModel` 集成测试通过
   - 原生 `--verify-downloads` 10 checks / 17 rendered
   - `--audit-download-menu` 60 cycles + 180 秒长开
   - release build / deep-strict signing / licenses
2. 已存在且通过的 317 项全量结果是 V0030 收尾时的集成基线；按新政策**不重复**
   全量，直接保留/复用，不把重复执行当作新的验收证据。
3. 后续局部修改只跑改动模块、必要相邻接口和原失败回归；只有新失败、共享底座/
   依赖变化、跨模块或阶段收尾证明需要时才扩大范围并说明。
4. 不删除或跳过下载删除/冲突/生命周期关键边界；Codex 独立验收负责最终集成回归。

## 选择与未覆盖范围

- 本次没有新失败，因此没有触发扩大测试。
- 未重新执行全量测试、未重复 3 分钟内存采样、未重打候选；复用最终候选的既有
  原生 UI、内存、构建/签名和资源证据。
- 生产真实 Downloads/Trash、真实鼠标/键盘焦点、物理多屏、浏览器/helper/cookie
  和真实用户数据仍未验证，和 V0030 主体报告一致。
- Codex 独立验收负责集成回归；pi 不把本补充写成新的体验验收。

完整主体报告：`docs/reports/v0030.md`
证据：`docs/verification/v0030/`
