# 锁屏歌词：准备有界诊断，不做优化

用户已授权准备对照抓取，正在选歌。build46律动恢复独立31项通过，用户确认锁屏解锁后无需点击自动恢复。本轮只准备能定位开歌词额外CPU的观测工具，不改动画、渲染算法或内存策略，Pi沿用当前会话/分支/模型，不提交推送。

## 证据

读 docs/reports/lock-refresh-scope-independent-20261109.md 和 desktop-lyrics-waveform-return-independent-20261109.md。无歌词锁屏稳定约3.16%，有歌词约7—8%。已抓到 NativeLyricsRowClock→update/draw→mask/CA提交；不能由包含式栈样本算CPU占比。现在必须知道真实活跃实例和重复工作，避免再次只抓到同样的栈。

NativeLyricsRow.swift 已有 frameTicks/maskUpdates/textBuilds/layoutPasses/imageBuilds/hostingLayouts/rootViewUpdates、captureWindow计数及clock注册状态，但没有运行时导出。不要用debug构建替换Release比较，避免编译配置混淆。不能附加调试器暂停用户App取值。

## Codex指定诊断

1. 诊断实现仅限 VALORA_LYRICS_EXPERIMENT 编译，并通过明确环境变量 `VALORA_LYRICS_DIAGNOSTICS_DIR` 指向新建的 /private/tmp 子目录才启用。默认无导出、无额外采样timer、无文件I/O；普通Release不得带入该实验诊断实现。
2. 显式开启时每2秒输出一条有界JSONL，最多12分钟/512KiB，超限停止调度并注销自身；不添加永久后台轮询。输出条件数据：单调时钟/UTC时间、系统/模型锁定标志与歌词开关（清楚注明是模型状态）、native live/active/clock-registered实例数，每个实例的稳定会话内数字ID和role（desktop-active/passive/inline/expanded/lock，按实际调用点标记，别猜），所属窗口可见/是否有window、logical active/stopped/playing、快照进度rate、boundary计时器状态、图片后端/失败fallback状态。
3. 每实例输出已有累计计数及必要的少量新增计数：clockTick、apply、update/frameTicks、mask/offset变化次数、CA事务尝试/实际提交次数、文本/图片构建、hosting/layout/root更新、switch与stop/resume次数。计数口径写明，draw每次调用不等于屏幕实际呈现帧数；不要为统计每帧分配对象或写日志。
4. 额外记录可见歌词外壳/host及fallback数量，明确“零native实例是关闭歌词还是fallback”，否则无法比较。注册表只持弱引用，不能因诊断延长视图、window、图片、AppModel生命周期。role元数据不参与动画identity，不改变mount次数。
5. 不导出标题、歌手、歌词全文/词、媒体来源凭据或原始timeline；只计数、布尔与尺寸。不要生成截图或日志截图。
6. 诊断timer读计数必须main actor一致；不触发render/layout、create image、apply或state发布，不引入额外objectWillChange。禁止为探测而反复切开关/操作用户媒体/锁屏。不要重写共享时钟或借机合并事务，这批不优化。

## 验证/交付

- 对弱注册生命周期、诊断关闭零调度/零输出、有界停止和JSONL统计做必要无窗口/单离屏定向测试；回归已有进度隔离、换句、空行与waveform自动恢复。不能用纯测试声称真实锁屏已定位。
- 明确给Codex启动方式、JSONL路径/字段口径/停止条件，写 docs/reports/lock-lyrics-diagnostics-20261109.md。
- 完成必要验证后交付一个独立Release候选，保留实验配置并按AGENTS自动build号/签名/hash/正常退出旧版→零实例→启动唯一新包，不覆盖Applications，不强退。此时普通启动不带诊断环境，避免用户还在选歌就过期。
- Codex独立检查后，在用户准备好时再用相同候选通过明确环境变量启用限时诊断，随后由用户开歌词/关歌词各锁约1分钟，外部同时抓CPU/内存/调用栈。不要自己操控真实歌词开关或音乐。
- 完成即停，不继续CPU/内存优化，等证据和独立验收。
