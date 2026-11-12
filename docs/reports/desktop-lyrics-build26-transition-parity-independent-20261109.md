# 歌词动画对齐：独立验收记录

## build50 初验未通过

共享LyricsRowExperimentHost的新SwiftUI动画与layoutWidth同时影响锁屏，而任务限定桌面，报告“锁屏不改”不成立。固定16ms延迟和横向布局不同步也尚未排除衔接问题；手动步进帧不是生产路径证据。已派R1，不进入内存优化。

## build51 技术检查与R2

R1类型化隔离桌面build26SwiftUI/锁屏legacyTimer，去掉固定16ms停顿。实际唯一进程98904，路径 `/private/tmp/valora-lyrics-transition-parity-r1-20261109/Valora.app`；strict/deep签名通过，hash7e8a500540f52af5ece7f1f768928e9c3c480773bdeecd00d032d32a522b8796。

独立5项通过：实际keyframes、过渡暂停/seek、策略隔离、master开/lock子开关关不请求歌词、waveform恢复。日志 `/private/tmp/valora-build51-independent-20261109.log`。用户强调“总歌词开、锁屏关必须真关”，源码与该定向用例支持关闭取词/不挂载锁屏歌词；真实此组合CPU仍需单独实测，不能把之前总歌词关采样冒称新组合实测。

生产keyframes在0.10—0.15秒仍有差异，现有断言主要起终点，不证明用户要求的中段衔接。用户已明确反馈不柔顺，因此不把build51当作体感已接受。派R2回到原版keyed child + asymmetric transition + 父HStack animation机制，而非多层手工offset目标/异步handoff。保留缓存native/单连续时钟、锁屏策略、新设置/位置和CPU优化。真实帧验收通过后才派预备的封面内存任务；当前该任务文件仅预备，未正式下发。

## 5分钟跟进

在当前工作中启动本地有界5分钟检查计时器，不是Codex后台自动化。记录 `/private/tmp/valora-five-minute-watch.jsonl`，每300秒检查Pi状态，最多18次，主Agent持续进行验收/派活。完成或需要用户醒后体感确认而无法继续时停止该计时器；不会留下无限周期任务。


## build55独立复核（2026-11-10）

R3 review已移除全局64图缓存，改owner共享准备宿主，三句不同文本只建一个窗口；retired旧native隐藏，冻结旧图单独退场，避免双旧句。唯一实例10937，`/private/tmp/valora-lyrics-transition-parity-r3c-20261110/Valora.app`，strict/deep签名通过、hash04b0c0dccce614f1405a3b0e1857aa08daeb079f29bc5671b88cca1f7c59277e。

独立45项通过（Valora26+ReferenceCore19），日志 `/private/tmp/valora-build55-independent-20261110.log`。但实际中间帧红色音符x存在反向漂移，补真实像素回归复现：新实验稳定短句note x149，切到长句采样161/171/113/56/39；同窗口原SwiftUI参考稳定x200，采样200/182/125/63/39。新增连续性测试失败，不能把前45项当动画目标已通过。

已派 desktop-lyrics-note-continuity-20261110，要求去掉残留独立layoutWidth/layoutIsLong两套布局动画，回到父HStack单一原版布局事务，保留缓存/共享宿主/单实时clock/锁屏独立门控。预备内存任务尚未下发。用户要求5分钟跟进计时器持续工作，用户睡眠期间不主动操作真实播放/锁解。


## build57技术验收（2026-11-10）

owner身份/lease初始化与安全发布边界收尾完成，wire不再调用会写@Published的begin，失效owner迟到bridge不prepare/fallback，重新显示同identity能恢复。唯一实例17718，`/private/tmp/valora-lyrics-transition-parity-r3e-20261110/Valora.app`，strict/deep签名通过，SHA256 2b029442c5daae376525f00808a3777f08500b789a3685bfbb0a33a4889b0469。

独立定向82项通过（Valora63+ReferenceCore19），日志 `/private/tmp/valora-build57-independent-20261110.log`。无Publishing changes警告，无shared image capture failed。仅TrackChangeRetries显式失败注入打印image capture failed，非普通路径失败。

像素回归：新note before200，采样200/190/140/75/39；参考before200，采样200/182/124/63/39，起点一致、单调向左、末端一致；自然tick回归也通过。并非逐帧绝对一致，仍有时间采样/渲染差异，真实歌曲体感留待用户醒后确认。已复现的反向跳位和owner异常已解决，可技术接受并冻结动画改动。

按用户顺序授权，随后派发封面图片降采样/去TIFF哈希内存任务，不再改动画。SettingsReductionTests三项旧源码契约断言仍是先前UI变更后的已知未清理项，本批未将全量测试冒称全绿。当前已接受的歌词开关/锁屏默认关闭/44pt位置保持。
