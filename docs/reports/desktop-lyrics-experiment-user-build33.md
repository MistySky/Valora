# 用户实测候选 build 33

2026-11-09 用户授权替换本地运行版。候选为 `/private/tmp/valora-lyrics-experiment-user33/Valora.app`，1.0.3 / build 33，以 `VALORA_LYRICS_EXPERIMENT=1` 构建。二进制 SHA-256：`009e30d8a68651a52aba899289e929c6aea335c670f5bec5f94c004d3983a432`；签名 strict/deep 校验通过，实验渲染器符号存在，build-verification.json 位于候选目录。

原 build32 正常退出，确认零实例后启动本候选；唯一实例 PID 65126。包含音符居中及空歌词行后继续播放的修复；实验换句仍为原生图层动画，未恢复原版体感。未覆盖 `/Applications`、未控制真实播放、未提交推送。真实 CPU/歌词观感待用户验证；前版候选 `/private/tmp/valora-lyrics-experiment-user-20261109/Valora.app` 保留。
