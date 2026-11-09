# 用户实测候选 build 35

2026-11-09 用户当次授权替换并要求后续候选自动单实例切换，约定已写入 AGENTS.md。以 `VALORA_LYRICS_EXPERIMENT=1` 构建 `/private/tmp/valora-user-test-35/Valora.app`，1.0.3 / build 35，二进制 SHA-256 `bf741537a15784e07ca0666634c8ca8f374f1fb55443bdea7e0b1f0047729d37`。系统信任环境下 strict/deep 签名校验通过，实验渲染器存在；build-verification.json 在候选目录。

build34 正常退出，确认零实例后启动候选，唯一实例 PID 99506。包含已独立验收的鼠标窗口接收状态去重及此前桌面歌词实验代码；真实鼠标抖动 CPU、悬停体感、歌词换句体感尚待用户实测，不能保证降幅。未覆盖 `/Applications`，未控制真实播放，未提交推送。build34 候选保留于 `/private/tmp/valora-user-test-34/Valora.app`。
