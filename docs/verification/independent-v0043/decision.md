# V0043 独立验收：代码/签名子集通过，视觉整体暂不接受

2026-11-03。本次未启动/退出软件、未锁屏、未调用真实窗口测试或性能/截图循环。

## 已验证

- 当前lockCardGlass确为glassEffect(.clear)而非原报告初版regular；内容外框345pt、圆角30。无自绘壁纸/额外染色底板，旧HUD容器已移除。
- 独立44项无窗口测试通过（31 LockMusicCoordinator、13 LockMusicState）。这些只证明功能与生命周期，不证明颜色/材质。
- 最终候选binary52aa9436e1a162d4f21e2b0fe2c26a87a7e6c66f20c9b273686d4f2844f8c84c与报告/包内build-verification一致，strict/deep签名通过。未另行重编Release。
- 当前只读进程检查没有Valora，故本轮没有可直接看到的最新clear真实锁屏卡。用户上一张乳白截图不能确定为最终clear版本，不能冒称已经看过最终clear的实机效果。

## 未接受项

1. 前景明暗缺失是确定代码差异。原版modern100187f28.c:1031–1048按_isWallpaperNearlyWhite选variant，1055起背景light，1078–1088前景独立选light/dark；当前LockMusicCard.foregroundStyle(.white)，共享播放器artist、output、progress/track的translucent分支也写死white。lockCardGlass又对整个子树设light，没有独立前景策略。用户截图已经表现出浅底白字对比不足；单改clear不等于解决可读性。需复用原版可证的明暗策略/语义颜色并核所有前景，不另做固定黑白底纱。
2. 原版私有variant2/5语义和公开API映射仍未知。报告“如果不一样缺口就在这里/没有合法公开手段”没有排除容器/appearance/前景/合成路径等因素，不能下绝对结论。macOS26新regular也是LiquidGlass，不应称其是旧HUD“毛玻璃”；用户视觉描述与实现类型应分开。
3. 记录/候选问题：源码注释仍说regular，实际clear；报告仍称未启动，但OpenCode seq3786明确称已启动PID16503、做桌面预览，且同一候选目录曾覆写多个hash。不能准确对应截图/运行版本。须更正实际操作与版本来源，后续交付独立新路径及冻结hash，不覆盖运行包或自动重启。

结论：底层正确方向与功能子集接受；整体视觉验收暂不放行。无需重复全量或44测试，除非相关逻辑改变；下一步限定前景/玻璃明暗和交付证据收尾。当前不要求用户原样再测，不推送Git或恢复定时器。
