# 封面内存独立验收

## build58初验不接受

唯一实例20124，`/private/tmp/valora-artwork-memory-bounded-20261110/Valora.app`，strict/deep签名通过、SHA256 7e51ee508233d0b221dfb82b05e9b79cfe622d02a31cd73d11dff1dc23960389。原ArtworkMemoryBoundedTests8项通过，但新增2项独立回归失败（3个断言），日志 `/private/tmp/valora-build58-artwork-independent-20261110.log`。

- 120×60 TIFF metadata orientation6，prepare仍输出120×60，应为60×120。小图分支忽略方向。
- 两种256×256细纹理图片的64×64身份摘要相同，可能吞掉真正的封面变更。已派R1改为完整有界像素身份，不再缩64。

这些均可能影响体感/功能，不能仅以位图内存下降就接受。build57已技术验收的歌词动画被冻结，内存任务不修改歌词代码。R1等待独立验收；真实memory footprint峰值未实测，像素字节估算不当作用户稳态节省量。


## build59独立验收通过（技术范围）

R1修复小图EXIF路径，orientation非1经ImageIO真实变换且不放大；完整有界sRGB RGBA像素加实际尺寸生成SHA256，不再缩64导致别名。生产maxPixel256，提色仍32×32原规则；不涉及歌词/动画/锁屏/设置。唯一进程22112，`/private/tmp/valora-artwork-memory-bounded-r1-20261110/Valora.app`，strict/deep签名通过，hash dbb077d32b8bb802eba539b0c0bbdf34a7143d1ac7fe5a8a4f921b66534183c6。

独立57项通过（Valora38+ReferenceCore19），日志 `/private/tmp/valora-build59-independent-20261110.log`：独立EXIF/身份回归、开发者封面8项、过渡/实际56pt视图、歌词音符连续性与owner失效、锁屏歌词门控、waveform恢复、seek及偏好/布局。原build58失败回归现通过。没有将重复的视觉单测再计入57项。

另单次保存56pt@2x对照112×112 PNG：`/private/tmp/valora-artwork-visual-review-20261110/original.png` 与 `bounded.png`；root已视觉检查细棋盘样本。差异33.538%边缘像素、平均RGB差3.83/255，缩放边缘有重采样差异，非数学无损，不以全实色零差异冒称所有封面无差异。日志 `/private/tmp/valora-artwork-visual-review-20261110.log`。

结论：可技术接受有界解码/去全尺寸TIFF。3000图原RGBA36,000,000与准备图262,144是位图字节估算，不是应用总physical footprint实测，未宣称用户稳态或峰值节省几十MB。用户真实封面/歌词柔顺度待醒后确认；保留build57动画候选及build59当前候选回退，不发布/提交Git。当前局部任务完成，停止当前5分钟检查计时器。
