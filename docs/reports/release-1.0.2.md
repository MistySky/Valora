# Valora 1.0.2

2026-11-06。固定自签名交付，版本 1.0.2 / build22，ARM64。

升级包改为复用 Valora Self-Signed 代码签名身份，Bundle ID 继续为 com.wangqing.valora；应用与随包 MediaRemoteAdapter 均以同一证书签名，保留 Hardened Runtime 和日历 entitlement。缺少可用签名身份时打包失败，不回退 ad-hoc。默认打包版本 1.0.2。

独立验证：打包入口、自动构建号测试通过；两个不同代码哈希的签名探针具有相同证书型 designated requirement，并互相满足；正式 Release 构建、strict/deep 签名和 DMG 完整性核验通过。此前 400 项产品回归属于 1.0.1，本批未重跑产品全量测试。

从旧 ad-hoc 版升级可能需重新授予一次日历/蓝牙权限。后续同证书升级具备保留授权的身份条件，真实 TCC 跨升级验收尚未完成。自签名未经过 Apple 公证，首次打开可能需用户在系统中放行。

本次不改产品功能、布局或锁屏材质；保留 1.0.1 的修复。私钥仅保存在构建机钥匙串，不随源码或 DMG 发布。证书 SHA-1：3A3B4D8F03D177E1664081C4CC2BB76EE2166A52。

App binary SHA-256：f7c795913fb221c0444e427ed543e40325dff96aa2315d8ff5d5c93528fd3cc6。
产物：/private/tmp/valora-1.0.2-release/Valora-1.0.2-arm64.dmg；镜像 SHA256 见发布附件 SHA256SUMS.txt。
