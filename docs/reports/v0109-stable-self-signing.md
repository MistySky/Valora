# V0109：固定自签名落地

执行：现有会话。用户授权建立本机固定签名身份并按 Calmon `docs/validation/SIGNING.md` 模式接线；仅本批，完成候选后交 Codex 验收。**未提交/推送、未安装、未替换或启动生产 App、未触发真实日历/蓝牙授权、未读个人日历、未读真实媒体。** 当前生产仍是 `/Applications/Valora.app`（1.0.1/build20，ad-hoc，PID 19174），未动。

## 一、本机签名身份

按 Calmon 生成方式创建一次并复用，不在脚本里生成：

- CN：`Valora Self-Signed`
- 证书 SHA-1：`3A3B4D8F03D177E1664081C4CC2BB76EE2166A52`
- 证书 SHA-256：`24F5864F15F94C4DECD53629FA6F9B0D1CE5251C69C879751C3280E113989F1B`
- RSA 2048，3650 天，`keyUsage=critical,digitalSignature`、`extendedKeyUsage=critical,codeSigning`、`basicConstraints=critical,CA:false`
- 证书与私钥导入登录钥匙串（`-T /usr/bin/codesign -T /usr/bin/security`）；临时 `.key` 导入后立即删除，临时目录已清理。
- 对该证书单独添加 user trust（`security add-trusted-cert -d -r trustRoot -k login.keychain-db`）。未清空或修改其他证书信任。

沙盒内 `security find-identity -v -p codesigning` 为 0；本机终端初始也为 0（`CSSMERR_TP_NOT_TRUSTED`）。加本证书 trust 后：

```
1) 3A3B4D8F03D177E1664081C4CC2BB76EE2166A52 "Valora Self-Signed"
   1 valid identities found
```

## 二、打包接线（scripts/package.py）

- 固定 `SIGNING_IDENTITY = "Valora Self-Signed"`；`require_signing_identity()` 要求存在**有效**身份。
  - 证书存在但未信任/无私钥 → 明确失败并提示修复；“找不到” → 明确失败；**绝不回退 ad-hoc**。
- 签名顺序：先 `Contents/Frameworks/MediaRemoteAdapter.framework`，再 App；两者同一身份、`--options runtime`、`--timestamp=none`；App 继续带 `Resources/Valora.entitlements`（日历 full access）。
- 打包后强制校验：
  - App/framework 的 designated requirement 必须含 `certificate leaf = H"..."` 且不含 cdhash；
  - `Authority` 必须列出 `Valora Self-Signed`；
  - `codesign --verify --deep --strict` 通过。
- `build-verification.json` 新增/更正：`signing_identity`、证书 SHA-1/SHA-256、`designated_requirement`、`framework_signing_identity`、`framework_designated_requirement`、`framework_binary_sha256`、`framework_adhoc_signed`、`adhoc_signed`（实际计算）。
- `scripts/package_args.py` 默认营销版本改为 **1.0.1**；构建号仍只由 `build_number.py` 在真实打包入口分配一次。
- 中间产物 `scripts/build_media_adapter.py` 仍以 ad-hoc 构建框架；正式包在 `package.py` 内重新签名，最终 App 内只保留固定证书签名。

MediaRemoteAdapter：App 进程不 `dlopen` 该框架，媒体适配器由 `/usr/bin/perl` 子进程加载；框架已用同一证书签名，`Hardened Runtime` 下 adapter 自检仍通过（见下）。未额外加入 `disable-library-validation`。

## 三、候选与验证

| 项 | 值 |
|---|---|
| 候选 | `/private/tmp/valora-v0109-self-signed-candidate/Valora.app` |
| 版本 / 构建号 | `1.0.1` / **21**（默认版本，单一构建号） |
| Bundle ID | `com.wangqing.valora` |
| App binary SHA-256 | `84fdc257a16c90775b6510fe48091ae2f0b2969a563a68b4c56e0c41f2495f32` |
| Framework binary SHA-256 | `82c2f3e6eec72e2dda38f9b5b0d61da98756173e1fc5cdbf9d62b430cc129df6` |
| App DR | `identifier "com.wangqing.valora" and certificate leaf = H"3a3b4d8f03d177e1664081c4cc2bb76ee2166a52"` |
| Framework DR | `identifier "com.vandenbe.MediaRemoteAdapter" and certificate leaf = H"3a3b…"` |
| Runtime / Team | `flags=0x10000(runtime)`，`TeamIdentifier=not set` |
| 签名核验 | `codesign --verify --deep --strict` 通过 |
| adapter 自检 | `perl … test` exit 0 |
| Gatekeeper | `spctl -a` rejected（自签名未公证，预期） |
| 打包测试 | `test_build_number.py`、`test_package_entry.py`、`test_signing.py` 通过 |
| 跨版本 DR | 两个不同 cdhash 的小探针同身份签名，DR 相同且互相满足（`test_signing.py`） |

候选未启动：当前生产 App 正在运行，按本批“不替换/不启动生产”要求未退出它；用户可在方便时退出生产版后打开候选试用。

## 四、仍未完成的实机 TCC 验收

- **跨升级日历/蓝牙授权继承尚未实测**：需要实际安装/升级自签名版本并在系统设置中授予一次日历/蓝牙，再做下一次同证书升级观察是否不再询问。本批不触发真实权限，故不冒充完成。
- 从当前 ad-hoc build20 切换到本自签名版本属于身份变更，**首次需要重新授权一次**（预期）；之后同证书版本升级才应复用。
- 自签名证书**不被系统根信任**，首次打开仍可能被 Gatekeeper 拦（右键打开或移除 quarantine）；无 Developer ID/公证。
- 证书私钥只在本机登录钥匙串；换机需重新生成并重新授权一次。构建数已用 21，后续正式包从 22 起。

## 五、边界

- 未改产品 UI/功能；只改打包签名与默认版本。
- 未提交/推送；`dist` 与 `/Applications/Valora.app` 未替换；未安装；未触发真实媒体/日历/蓝牙/设备/权限。
- 临时签名材料已清理，仅钥匙串保留证书与私钥。
