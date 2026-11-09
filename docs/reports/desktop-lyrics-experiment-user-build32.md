# 桌面歌词实验版用户实测候选

2026-11-09，用户当次授权启动实验版自行观察效果。构建条件 `VALORA_LYRICS_EXPERIMENT=1`；候选 `/private/tmp/valora-lyrics-experiment-user-20261109/Valora.app`，版本 1.0.3 / build 32，二进制 SHA-256 `0a98122a04db7768e4f64ba7d3011aa2a3618591a1ac165bd45598c5774edd84`。`nm` 验证实验渲染器符号存在；系统信任环境 `codesign --verify --strict --deep` 通过，build-verification.json 位于候选目录。

启动前没有运行的 Valora；启动后唯一实例 PID 8104，路径对应候选。未覆盖 `/Applications`、未控制真实播放、未提交。实验只接入桌面歌词，锁屏沿用原路径，捕获失败回退原行。用户此前的 build31 候选仍保留于 `/private/tmp/valora-user-test-lyrics-cache-20261109/Valora.app`，可在用户授权后退出实验版并启动它回退。

CPU、真实播放观感、1x、过渡逐帧与真实多屏尚未验收；长句图像存在少量差异。
