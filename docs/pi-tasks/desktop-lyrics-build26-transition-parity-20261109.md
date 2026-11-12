# 桌面刘海歌词换句：恢复build26的连续衔接

用户已接受build49歌词设置卡及锁屏位置调整，现在明确要求桌面刘海歌词切换动画与本机build26对齐；补充强调“目前切换和动态效果不流畅，或者讲衔接不流畅”。本轮以这个体感问题为主，不继续锁屏CPU/内存优化，不改设置/锁屏位置。Pi沿用当前会话/模型/分支，保留所有未提交成果，不提交推送。

## 真实参考和源码

Codex已核对 `/Applications/Valora.app` 与 `/private/tmp/valora-v0110-r3-device-battery-candidate/Valora.app` 都是1.0.3/build26，二进制SHA256一致：c3c82db28a270ef0236fd87af9f436432b5a5b0eb138a10007a39c24a1419fff。这两包只读保留，禁止覆盖或同时运行第二个Valora。

发布合并基线 `6c98d2b:Sources/Valora/CompactLyricsView.swift`，Codex已导出 `/private/tmp/valora-build26-reference/CompactLyricsView.swift`。注意产物清单没有源码加密对应证明，报告应称发布源码基线，不编造“逐帧已与真实二进制完全相同”。需要真实体感最终由用户确认。

baseline外层：HStack(spacing:5)，音符是固有宽度，LyricsLineContent按line.start+text做.id；新句offset(y:26)+opacity，旧句offset(y:-26)+opacity；整行 `.animation(.easeInOut(duration:0.2), value:lineKey)`；长句固定可用宽度leading、短句固有内容宽度center；原有32pt外框clip（内嵌沿用其实际行高/无音符）。这包含宽度/音符/对齐的布局动画，不能仅抄±26/0.2就声称等价。

## 已知当前差异

ExperimentalDesktopLyricsView当前用max(新句宽度,旧句viewportWidth)的topLeading ZStack；transition结束移除outgoing后容器才收窄，短句及note可能末尾跳位。新旧行都按新句isLong决定整个HStack对齐，长短切换时布局关系可能先变/后跳。宿主以Timer60Hz每帧发布多个offset/opacity属性驱动SwiftUI，虽然单调时钟保证不拉长时长，但不能证明和原SwiftUI事务的呈现节奏一致。以上需在有限预览中定位，不能再只加时钟参数测试。

## Codex决定的改法边界

1. **桌面外层恢复build26的SwiftUI过渡/布局职责**：由一次lineKey变化触发SwiftUI的原式transition与easeInOut布局动画，处理上下移动、双向淡入淡出及宽度/居中/note同步过渡。优先去掉桌面手工60Hz逐帧发布offset/opacity的外壳驱动，交给SwiftUI正常动画事务。不要改成另一种翻页/淡入模式、弹簧或拉长时长遮掩问题。
2. **保留缓存native底层**：当前行逐字高亮/横向阅读仍用现有native缓存和30Hz时钟；旧句用已缓存、正确当下高亮和横向offset的冻结快照退场，不在每帧生成图片/文字。不要整体退回build26的全行SwiftUI Timeline渲染/4Hz全局模型广播，不降低播放精度。
3. 旧句/新句保留各自切换前后的几何；外层布局随同一0.2s过渡平滑迁移至新句尺寸。去掉“取两句较大宽度，结束瞬间收缩”的末尾跳位，不在换句途中突然改对齐或重置note位置。短→短、长→短、短→长必须逐一检查；视觉范围/字体/字号/横向滚动规律跟build26，不添加额外空白、裁切或双音符。
4. 保证只有一个实时native歌词时钟/当前行，退场冻结行无时钟。当前行的30Hz更新与外层动画同步，不在切句边界先露新行一帧后再执行入场，不重放旧句高亮或在退场末尾闪回。保留build48完整输入去重，但不能吞掉lineKey、同identity歌词替换、host generation/active恢复、seek/暂停的必要更新；不为动画每帧重新wire/render整个树。
5. 本轮只桌面刘海模式（紧凑下方歌词、内嵌歌词及桌面展开播放器）。锁屏已有新开关和位置保持；若ExperimentalDesktopLyricsView共享不可避免，则明确传桌面过渡策略/拆小外壳，锁屏沿用原策略，不借共享文件改锁屏动画。失败fallback/无歌词/空行音符语义保持。
6. 中断处理：快速换句/seek/暂停或新歌词内容抵达时，旧退场完成不能清除新行/新过渡；不产生停顿、二次收缩、叠字、丢行。自然首句与空行变化按build26实际行为，不对所有状态强套一个过渡。

## 必须提供的验收证据

- 先给短→短、长→短、短→长的实际可见问题定位。使用一份小的隔离fixture/预览（有限单窗口、无需真实媒体），将发布源码baseline外壳与新实现用同样歌词、宽度、时间锚/字体呈现，观察起始、中段、结束及结束后一帧；至少保留有限中间帧图或短预览证据及位置描述。不能只测终点相同/参数等于0.2s/两段源代码字符串就宣称动画对齐。
- 参考view仅放开发/测试边界；如为适配当前AppModel/内容接口而改了baseline，列明修改，不偷换原动画行为。不能为单测引入Release QA代码。
- 必要定向测试：上述3类宽度/note/边界；换句结束无末尾跳位；空行到非空；暂停/seek中断/快速替换；完整输入去重；波形无需点击恢复。可视测试只有限单窗口和几帧，禁止批量闪窗/长时压力/反复锁解。用户仍负责真实歌曲体感，不操作其播放或音量。
- 缓存构建与活跃实例计数不能因外层动画暴涨，确保无恢复全局高频广播/每帧文字重绘。若确需可见行为与baseline有差异，明确报告，不自行决定新的动画风格。

## 交付

写 `docs/reports/desktop-lyrics-build26-transition-parity-20261109.md`，说明baseline、具体衔接原因、修改、有限中间帧证据/测试数量/未验项。不夸称用户体感已经验收。

必要验证后按AGENTS长期授权交付一次独立Release候选（保留现有实验配置），自动build+1/签名/hash/清单；正常退出旧版→零实例→默认无诊断环境启动唯一新包，保留build49回退，不强退/不覆盖Applications/build26。完成即停等Codex独立验收和用户试听观察。
