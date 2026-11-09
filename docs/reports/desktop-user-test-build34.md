# 本地实测候选 build 34

2026-11-09 用户当次授权替换。当前源码以 `VALORA_LYRICS_EXPERIMENT=1` 构建 `/private/tmp/valora-user-test-34/Valora.app`，1.0.3 / build 34。二进制 SHA-256：`15677816cb1b94d5d52d45d7090265a3d30acb333ceb17fd179766305287d2ca`；系统信任环境下 strict/deep 签名校验通过，实验渲染器与鼠标预筛选符号存在。构建记录在候选目录 `build-verification.json`。

原 build33 正常退出，确认无 Valora 后启动候选；唯一实例 PID 91334。包含实验桌面歌词视口过渡、换句单调计时以及鼠标保守范围快速排除；锁屏仍旧路径。真实鼠标 CPU、悬停、歌词动画体感与真实播放尚待用户实测。未覆盖 `/Applications`、未控制真实播放、未提交推送；build33 候选保留于 `/private/tmp/valora-lyrics-experiment-user33/Valora.app` 可供后续授权回退。
