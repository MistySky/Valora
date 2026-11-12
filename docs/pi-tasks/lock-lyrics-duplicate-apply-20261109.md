# 锁屏歌词：仅去重外壳引起的相同输入 apply

用户持续授权定位并优化锁屏歌词CPU。诊断两轮已完成，读 `docs/reports/lock-lyrics-diagnostics-independent-20261109.md` 最新对照及当前AGENTS。Pi沿用现有会话/模型/分支，不提交推送。

## 实测和决策

build47，单一实例76758；目录 `/private/tmp/valora-lyrics-compare-20261109-222507-e1f75c`。开歌词锁屏稳定CPU7.28%，关3.70%；开时内部41行均单一lock native活跃/registered、无fallback，关时零native。不是多实例或逐帧图片重建。

lock实例按2秒计数差分：无切句时apply4.31/s，update/draw/CA34.14/s，图片/文字/layout重建0；含切句窗口apply10.22/s、draw40.60/s，图片数约每切句2张。`NativeLyricsRowHost.updateNSView`被外壳换句动画刷新时，总会wire/setActive/apply，apply立即update/draw；相同snapshot的重复apply是本轮有依据的最小落点。4Hz新时间锚点与30Hz时钟本来是不同输入，不要把所有34次画帧都误判重复。

## Codex指定实现

1. 在NativeLyricsRowHost的适配层增加每个native view/Coordinator自己的已应用输入记录，只对完整输入相同的多余apply/setActive协调做去重。外壳的offset/opacity仍按原60Hz/0.2s运行，内部clock仍30Hz，不改变时序函数、帧率、翻转或高亮/滚动。
2. 完整输入覆盖snapshot全部有效字段：歌词内容版本（包括同identity替换/词时序变化）、elapsed/sampledAt/rate/playing/duration、width/height/offset、accent、kern/backend、reduceMotion、switchAnimation，以及host identity/generation、active状态和失败注入/恢复条件。不能只按歌曲identity/文本或宽度去重，不通过整段歌词序列每帧深比较或重新hash制造更贵的工作。
3. 若需要内容revision，在AppModel歌词状态赋值边界维护单调revision（每次赋值增也可），不绑定到framekey/SwiftUI.id，不触发无关AppModel广播、不让文字测量每帧构造revision；同identity不同内容必须使key变化。适配层只读小key；不能修改歌词解析器/获取策略。
4. native回调wire仍保证当前host/generation，不因跳过apply留下旧闭包；初挂/同曲重挂/active恢复/失败回退恢复不可跳过必要的当前行同步。窗口/scale等环境改变原有layout恢复仍有效，不把现有缓存状态与新view混用。
5. 真实新anchor、seek、暂停/恢复、速率变化保持立即处理。本批不尝试合并真实4Hz anchor与30Hz clock、不改共享Timer、不改CA事务算法、不新增永久轮询、不改screen monitor/音频/玻璃/内存策略。
6. 修正诊断clockTickCount未递增（当前只声明，0无意义）；增加适配层apply请求/实际执行/相同输入跳过计数，口径清楚。继续保持默认诊断关闭、限时、弱引用和数据隐私，frameTicks/CA计数不是最终呈现帧数。

## 验证与交付

最小回归要证明：同snapshot外壳重复更新不增加native apply/draw/CA；真实新anchor与seek/暂停立即处理；同identity替换timeline/word timing不被吞；host generation/active恢复/同曲重挂/失败恢复正确；0.2s外壳翻转和波形恢复保持。已有歌词空行/时钟/进度隔离/seek回归按需跑。禁止批量闪窗/压力/真实控制音乐或锁屏；少量隔离视图允许。

写 docs/reports/lock-lyrics-duplicate-apply-20261109.md，包含去重key边界、计数前后/定向测试、未验风险。不夸大CPU降幅：这只能消除一部分额外工作，剩余真实高亮CA成本仍在。

必要验证通过后按AGENTS自动交付一个Release候选（实验配置相同），build+1/签名/hash/清单、正常退出旧版→零实例→唯一新包，默认不带诊断环境，保留build47回退，不强退/不覆盖Applications。完成即停等Codex独立验收和用户实测，不自行开始内存或下一批优化。
