# 重连漏报限定修复（等待新候选实机）

用户确认：软件启动后实际断开并重新连接 AirPods，只有系统弹窗，Valora 未出现。撤回对此路径的体验通过结论；电量读数与之前回调崩溃修复的证据仍有效。

## 独立复现

两项 fake 回归在修复前均失败：
1. 明确的 post-start connect 早于第一份快照，被 didRead=false 的 baseline 抑制。
2. connect 后第一份快照只有通用设备信息，known 已记入 ID；型号晚到认出 AirPods 时，fresh 已丢失。

这些是确定的软件缺陷，但没有本次真实回连的 native 事件日志，不能声称已唯一证明用户这次漏报根因。

## 修改

ConnectivityController 按稳定 ID 保留明确连接事件 10 秒；中间通用快照不消费事件，认出 AirPods 才消费并播放一次到达。真实连接可以越过首次 baseline；单纯启动已有设备仍不弹。基于单调时钟，不增加采样频率或计时器。off/stop 清空事件；过期事件丢弃。保留先前 native nonisolated callback 修复。

## 验证

21 项定向用例通过，含原两失败、过期不误弹、旧生命周期/电量/媒体用例。全部 fake 无界面，不控制真实媒体或蓝牙，不闪窗、无性能/循环测试。

当前用户运行包不覆盖、不退出。候选构建签名情况另附 build.log；真实断开重连显示仍待新候选验证，不把 fake 通过等同实机通过。系统原生 AirPods 弹窗没有被屏蔽。

Release构建、打包与codesign strict/deep通过。候选：`/private/tmp/valora-v0035-reconnect-candidate/Valora.app`。SHA256：48dc6fa2d456fe303b6782544d39a57b55d70fbd2f4dce38dadc243a2cdf7ee5。普通候选未启用临时电量采样Info.plist标志。尚未启动替换用户运行版。

用户已明确允许换版；通过旧实例Cmd+Q确认退出，再启动reconnect-candidate，刘海/软件入口正常。设备页实际显示需要授权且开关off（本地候选签名变化）；未代用户点击权限开关或授权，等待用户自行允许后再确认重连。本记录覆盖前文“尚未启动”状态，不代表重连实机通过。
