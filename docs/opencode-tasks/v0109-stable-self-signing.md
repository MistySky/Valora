# V0109 固定自签名落地

用户明确授权「开始，落地」：按 MistySky/Calmon 的 docs/validation/SIGNING.md 模式，解决 Valora 升级后日历/蓝牙重新授权。继续现有 ses_e5f5da1c5ffesaPdioiEijQ5HM，按 AGENTS 开发，Codex 独立验收。当前正式 1.0.1 build20，保留全部 V0108 修复，不再研究玻璃。

实施：配置固定 Valora Self-Signed 代码签名证书；后续每次打包复用同一身份，固定 com.wangqing.valora。生成私钥仅在本机安全临时目录/钥匙串，不提交仓库、日志或打包。证书已存在时复用，不每次生成；证书缺失/无私钥必须明确失败，不能静默降级 adhoc。正式打包同时处理随包 MediaRemoteAdapter 的签名兼容与 Hardened Runtime library validation，不能让媒体适配器失效。用户授权此次建立本机签名身份及必要钥匙串导入；不导出其他证书私钥、不清空或广泛更改信任。

先读 Calmon 固定 commit72235116e1420fa081e8f694991a32809f81498d 的 SIGNING.md（可通过 raw.githubusercontent.com 获取）。当前 security find-identity -v -p codesigning 在沙盒里返回0，需确认沙盒外结果再判断缺失。避免把不受系统信任等同无法签名；验证证书型 designated requirement。

修改脚本及必要测试文档，配置默认营销版本1.0.1，自动构建号分配一次，新正式候选输出 /private/tmp/valora-v0109-self-signed-candidate（不能覆盖dist或运行版），Release只编译一次。若临时私钥须导入后及时删除，保留钥匙串身份。验证新旧两段不同代码可互相满足同一证书DR（用小型无权限探针，不重复正式打包）；验证bundle ID、entitlements、签名、hash、嵌套framework身份。现有定向打包测试通过。

不能触发真实日历/蓝牙授权，不读个人日历，不安装/替换启动生产app，不提交推送。报告实际完成与尚未完成的跨升级TCC实机验收；从旧adhoc切换需要再授权一次是预期。交付可运行候选供用户试用，不能仅写方案。落 docs/reports/v0109-stable-self-signing.md。
