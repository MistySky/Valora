# V0096-R3 用户确认：保留外接接线，比例回21%

现有空闲会话ses_e5f5da1c5ffesaPdioiEijQ5HM继续。用户实测R2太高，Codex解释：此前误把生产参数未接入当成预留不足，R2同时接通外接最大态预留和0.30比例，叠加抬高141.2pt。用户明确同意“保留正确外接接线，只恢复21%比例”，不是回退到漏传参数版。

## 唯一产品调整
- externalReserveFraction 0.30恢复0.21；生产place中的reserveFullExpansion: !(target?.isBuiltIn ?? false)必须保留。外接仍预留maxCardHeight240，内置仍player164+volume32。
- 不用0.24/0.25，不新增偏移项/设置，不改目标选屏、形态跟随、窗口高度、内容、字号、动画、音量/歌词、玻璃或Space。
- 1080pt外接相对屏幕原点：新top466.8，正常歌词208高→bottom258.8，全开240高→bottom226.8；相对当前R2整体下移97.2pt，比最初漏接线版上移44pt。内置1117原点0的panel.minY190.57不变。
- 生产协调器注入外接frame.minY300/H1080实际panel.minY应526.8（不是624或482.8）。更新用例预期须明确原因是用户新决定，不删除实际窗口Y断言。

## 验证交付
只跑相关布局/协调器少量无窗口功能测试，确认真实调用仍外接分支、外接526.8/内置190.57、四态顶边不变，不全量/闪窗/性能/真实锁屏媒体操作。修正注释/报告，21%和30%均非系统头像边界，最后视觉仍由用户确认。

新候选独立/private/tmp/valora-v0096-r3-reference-fraction-candidate（存在另起），构建签名后正常退出旧版→确认0→启动唯一新实例，不覆盖dist或旧运行包，不Git提交push。报告docs/reports/v0096-r3-restore-external-reference-fraction.md写清实际坐标和来源、hash签名与单实例；完成停等Codex验收，不追加其它优化。
