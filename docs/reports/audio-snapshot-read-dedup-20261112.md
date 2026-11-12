# 音频快照单轮读取去重

用户同意继续资源优化，本笔只处理优先级最高的音频重复读数；不改歌词、动画、窗口/鼠标行为或缓存策略。分支codex/resource-idle-render-dedup，接续build68。

## 改动与边界

NativeBridge.m的volumeChannels现在可通过可选输出参数返回本轮验证声道时已读取的最大音量。ARAudioOutputSnapshot复用它，不再把每个有效声道读第二次。主声道成功时保留fmaxf(0,value)语义；分声道必须全部可读可写后才输出最大值，部分失败仍返回空能力与0音量，不能暴露部分累积结果。

不跨轮保存任何读数或设备信息，不改变0.5秒轮询周期。静态名称/UID等查询仍保留，硬件状态下轮照常重读。ARSetOutputVolume传NULL，继续原有的能力验证、再次读取最新声道值、比例缩放和写入，未改变用户音量控制逻辑。没有新增生产测试入口或公开ABI。

## 验证

新增Tests/NativeBridgeTests/AudioSnapshotReadTests.m，用宏替换CoreAudio入口，直接编译生产NativeBridge.m；fake函数没有调用真实CoreAudio，不读写实际音量、不开窗口。

12个有限场景涵盖主声道、立体声峰值、不可写主声道回退、部分不可读/不可写失败、零声道、无设备、NaN、下一轮/新设备取新值、写入左右比例、错误设备与无效写入参数。

先在旧源码运行：3条断言失败，均为重复读取数量。改后12场景0失败。Swift相邻回归44项通过（ValoraTests42，ReferenceCoreTests2），包括锁屏协调器、播放响应、进度隔离和音量步进。git diff --check通过。

复现原生回归：

```sh
xcrun clang -fobjc-arc -mmacosx-version-min=27.0 -I Sources/NativeBridge/include Tests/NativeBridgeTests/AudioSnapshotReadTests.m -framework Foundation -framework AppKit -framework CoreAudio -framework IOKit -framework IOBluetooth -o /private/tmp/valora-audio-snapshot-after
/private/tmp/valora-audio-snapshot-after
```

日志/private/tmp/valora-audio-snapshot-before.log、/private/tmp/valora-audio-snapshot-after.log、/private/tmp/valora-audio-snapshot-compile.log、/private/tmp/valora-audio-snapshot-swift-tests.log。

## 收益口径

确定收益是每次成功快照中，每个有效声道的volume属性读取从2次减少到1次；其他CoreAudio属性查询不变，不能将此表述为全部音频查询或整机CPU减半。无可写声道设备可能没有该项节省。本笔不承诺大幅CPU降幅或内存下降，需真实候选观察。

开始对旧build68/PID71033采30秒不带探针的CPU与媒体状态；采样期间不并行构建或测试。用户播放不被自动控制，前后观察不是严格同片段A/B。

旧版首段30.20秒CPU5.76%，但媒体get前playing=true、后false，属于播放转暂停的混合窗口，不作为状态一致的前后基线。追加20.16秒，前后均playing=false且同一曲目身份、elapsed=53秒，CPU1.24%，作为暂停状态观察。

数据/private/tmp/valora-audio-dedup-before-cpu.json、/private/tmp/valora-audio-dedup-before-recheck.json。没有改变真实播放或音量。

## 候选交付

- 1.0.6/build69，仅本地测试候选；/private/tmp/valora-audio-snapshot-dedup-20261112/Valora.app。
- 显式VALORA_LYRICS_EXPERIMENT=1，沿用Valora Self-Signed；严格深度签名校验通过，实际二进制摘要与build-verification.json一致。
- binary SHA256：48d06f0931f0a86ed2403a60dc8292735dc26fc3a704fbd594627f8a375b0037。
- 正常退出核对过路径的build68/PID71033，确认0实例后启动build69/PID77534，确认唯一实例及实际路径。
- 构建日志/private/tmp/valora-audio-snapshot-build.log。
- 不覆盖Brew/Applications；没有提交、推送、合并或发布。本笔继承build68的鼠标修复，没有改回旧事件来源。

启动后留出15秒，再独立采30.23秒CPU：平均1.26%，窗口前后均playing=false，与旧版同曲目身份、同elapsed=53秒。旧版暂停20.16秒1.24%；两个观察结果基本一致，没有证据证明本笔带来可测的整机CPU改善。没有为了性能测试改动用户的播放或音量。

候选数据/private/tmp/valora-audio-dedup-after-cpu.json。原生查询次数减少已证实，但不能将其换算成CPU降幅。暂保留此有限去重；本笔没有继续修改歌词/屏幕轮询或内存策略。真实耳机热插拔和用户音量手势未实机复测，fake设备与控制回归不能冒称硬件验收。

采样后独立vmmap：physical footprint26.4M、peak27.4M。这是新进程启动后、暂停状态的读数，不能与已播放/打开设置后的build68 47.3M比较为内存优化；没有更改缓存或内存策略。内存文件/private/tmp/valora-audio-dedup-after-memory.txt。
