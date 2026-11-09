# 用户实测候选 build 31

2026-11-09 用户当次授权替换运行版自行实测。构建当前 `codex/idle-cpu-optimization` 生产代码到 `/private/tmp/valora-user-test-lyrics-cache-20261109/Valora.app`，版本 1.0.3，构建 31。包含此前已接入的播放节奏、去重、歌词缓存修复和 seek 锚改动；新歌词渲染器 `NativeLyricsRow` 仍仅为 debug 原型，未接入本版，不能借此声称新渲染器 CPU 优化已实测。

二进制 SHA-256：`541c80630c74d4e6f9a15b01f7009f34102e9cd15a0f0a438c79ada6b5c43d17`。构建验证记录位于候选目录 `build-verification.json`；系统证书信任环境中 `codesign --verify --strict --deep` 通过，签名为 Valora Self-Signed。受限环境的证书信任查询失败不代表签名无效，系统环境复核已通过。

启动前检查无 Valora 实例；启动后唯一实例 PID 90917，路径为本候选。未覆盖 `/Applications`，未触发真实播放控制，未提交或推送。实际 CPU、歌词观感、真实播放功能待用户观察；本批没有证明 CPU 降幅。
