# 用户实际点击失败：缺失Hardened Runtime日历资源声明

用户反馈点日历不能去授权。Codex在正式dist候选设置日历页观察开关off，按用户反馈只点击一次开启复现（未接受任何系统权限、未读取事件）。实际没有系统授权窗口，仅出现应用自身“日历读取未获授权，功能保持关闭”提示。

只读系统TCC日志确认：2026-10-24 21:41:19（Asia/Shanghai）Prompting policy for hardened runtime; service: kTCCServiceCalendar requires entitlement com.apple.security.personal-information.calendars but it is missing；accessing=com.wangqing.valora。无需读取TCC数据库。

codesign检查dist flags=0x10002(adhoc,runtime)，未包含entitlements；scripts/package.py使用--options runtime但无--entitlements。之前报告“非沙盒不需要entitlement”的推论错误：忽略Hardened Runtime的资源声明。NSCalendarsFullAccessUsageDescription虽存在，仍不能替代签名资源权限。

授权逻辑fake测试与build/signature结构有效不能证明系统弹窗可用。整体日历功能未通过实机请求入口，本次独立决策追加覆盖此前子集结论。限V0016-R2：保持Hardened Runtime，最小日历entitlement随包签名，核验最终codesign导出、用途声明；保留具体错误诊断，不吞掉所有Error成拒绝。禁止关runtime/开大权限/清TCC/重置用户授权绕过。真实权限最终由用户在弹窗选择。

Apple官方：https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.personal-information.calendars
