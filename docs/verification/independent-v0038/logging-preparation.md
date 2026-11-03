2026-10-30 用户报告模拟正常真实锁屏异常并要求读日志。检查/tmp及任务临时目录未发现日志；当前运行V0038未配置VALORA_NOTCH_DIAGNOSTIC，Codex此前只解释取证步骤却未实际准备，导致本次无数据，不得分析旧日志冒充本次。
已从同版V0038克隆/private/tmp/valora-v0038-logging-candidate/Valora.app，Info.plist LSEnvironment配置VALORA_NOTCH_DIAGNOSTIC=/private/tmp/valora-v0038-live-lock-diagnostic.jsonl，ad-hoc重签strict/deep通过；未改二进制动画源码/偏好。CUA退出旧实例多次返回user changed并重取状态，未能可靠退出，停止继续重复操作。诊断候选尚未启动/日志写出尚未确认，不得称日志已开启。需用户手动退出旧Valora后再由Codex启动候选并先确认日志生成，再进行一次用户自锁解。

用户确认已退出后，CUA已启动logging-candidate。实际确认/private/tmp/valora-v0038-live-lock-diagnostic.jsonl存在，24条正常态，含shape/window/space，实体geometry185x32、hostTopScreen1117与screen.maxY1117一致。普通24条额度已满但锁阶段独立96条保留，尚未锁屏，不能分析原因。模拟阶段现日志phase仍引用真实indicator，重复模拟无必要；接下来只需用户真实锁解一次。
